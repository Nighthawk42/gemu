import test from 'node:test';
import assert from 'node:assert/strict';
import {createBroker} from './broker.mjs';

test('authenticated rooms isolate servers, restrict roles, revoke departures and expire leases', async () => {
  let clock = Date.now();
  const people = new Map(), removed = [];
  const admin = {
    listRooms: async () => [...people.keys()].map(name => ({name})),
    listParticipants: async room => people.get(room) || [],
    updateParticipant: async (room, id, {permission}) => { people.get(room).find(p => p.identity === id).permission = permission; },
    removeParticipant: async (room, id) => { removed.push(id); people.set(room, people.get(room).filter(p => p.identity !== id)); },
    deleteRoom: async room => people.delete(room)
  };
  const broker = createBroker({servers: {one: 'a'.repeat(64), two: 'b'.repeat(64)}, apiKey: 'test', apiSecret: 'c'.repeat(64),
    publicUrl: 'wss://example.test', admin, now: () => clock});
  await new Promise(resolve => broker.server.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${broker.server.address().port}/sync`;
    const body = {instance: 'instance', rooms: [{id: '1', publisher: 'owner', viewers: ['viewer']}]};
    const post = (secret, data = body) => fetch(url, {method: 'POST', headers: {Authorization: `Bearer ${secret}`}, body: JSON.stringify(data)});
    assert.equal((await post('bad')).status, 401);
    assert.equal((await post('a'.repeat(64), {instance: '../invalid', rooms: []})).status, 400);
    const first = await (await post('a'.repeat(64))).json();
    const second = await (await post('b'.repeat(64))).json();
    const name = first.rooms[0].room;
    assert.notEqual(name, second.rooms[0].room);
    const jwt = JSON.parse(Buffer.from(first.rooms[0].members[0].token.split('.')[1], 'base64url'));
    assert.equal(jwt.video.room, name);
    assert.equal(jwt.video.canPublish, false); assert.equal(jwt.video.canSubscribe, false);
    people.set(name, ['owner', 'viewer', 'intruder'].map(identity => ({identity, permission: {}})));
    await broker.reconcile();
    assert.deepEqual(people.get(name).map(p => [p.identity, p.permission.canPublish, p.permission.canSubscribe]),
      [['owner', true, false], ['viewer', false, true]]);
    assert.ok(removed.includes('intruder'));
    await post('a'.repeat(64), {instance: 'instance', rooms: [{id: '1', publisher: 'owner', viewers: []}]});
    assert.ok(removed.includes('viewer'));
    clock += 16000; await broker.reconcile();
    assert.equal(broker.rooms.size, 0); assert.ok(removed.includes('owner'));
  } finally { await new Promise(resolve => broker.server.close(resolve)); }
});
