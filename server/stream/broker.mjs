// GEMU controls membership; LiveKit handles encoded media and congestion control.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import {AccessToken, RoomServiceClient} from 'livekit-server-sdk';

const LEASE_MS = 15000;
const valid = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,96}$/.test(value);
const equal = (a, b) => crypto.timingSafeEqual(crypto.createHash('sha256').update(a).digest(), crypto.createHash('sha256').update(b).digest());

export function createBroker({servers, apiKey, apiSecret, publicUrl, admin, now = Date.now}) {
  const rooms = new Map();
  let serial = Promise.resolve();
  function enqueue(fn) { const p = serial.then(fn); serial = p.catch(() => {}); return p; }
  async function reconcile() {
    // Rediscover retired rooms after reconnects or a broker restart. Do not
    // leave previously granted participants outside membership enforcement.
    for (const room of await admin.listRooms()) {
      if (room.name.startsWith('gemu_') && !rooms.has(room.name))
        rooms.set(room.name, {publisher: '', viewers: [], until: 0});
    }
    for (const [name, state] of rooms) {
      const live = now() < state.until;
      let participants;
      try { participants = await admin.listParticipants(name); }
      catch (err) { if (err.status === 404 || err.code === 'not_found') { if (!live) rooms.delete(name); continue; } throw err; }
      for (const person of participants) {
        const publisher = live && person.identity === state.publisher;
        const viewer = live && state.viewers.includes(person.identity);
        const permission = {canPublish: publisher, canSubscribe: viewer, canPublishData: false,
          canUpdateMetadata: false, canPublishSources: publisher ? [3, 4] : []};
        // A join token starts with no media privileges. Only this authoritative
        // membership reconciliation enables publishing/subscribing.
        if (!publisher && !viewer) {
          await admin.updateParticipant(name, person.identity, {permission});
          await admin.removeParticipant(name, person.identity);
        } else if (person.permission?.canPublish !== publisher || person.permission?.canSubscribe !== viewer) {
          await admin.updateParticipant(name, person.identity, {permission});
        }
      }
      if (!live) { await admin.deleteRoom(name); rooms.delete(name); }
    }
  }
  async function sync(server, data) {
    if (!valid(data.instance) || !Array.isArray(data.rooms) || data.rooms.length > 16) throw new Error('invalid request');
    const names = new Set();
    for (const row of data.rooms) {
      if (!valid(row.id) || !valid(row.publisher) || !Array.isArray(row.viewers) || row.viewers.length > 32
          || row.viewers.some(id => !valid(id) || id === row.publisher) || names.has(row.id)) throw new Error('invalid room');
      names.add(row.id);
    }
    const prefix = 'gemu_' + crypto.createHash('sha256').update(server + ':' + data.instance).digest('hex').slice(0, 24) + '_';
    const wanted = new Set(data.rooms.map(row => prefix + row.id));
    for (const [name, state] of rooms) if (name.startsWith(prefix) && !wanted.has(name)) state.until = 0;
    const result = [];
    for (const row of data.rooms) {
      const name = prefix + row.id;
      if (!rooms.has(name) && rooms.size >= 128) throw new Error('room capacity reached');
      rooms.set(name, {publisher: row.publisher, viewers: [...new Set(row.viewers)], until: now() + LEASE_MS});
      const members = [];
      for (const identity of [row.publisher, ...new Set(row.viewers)]) {
        const token = new AccessToken(apiKey, apiSecret, {identity, ttl: 20});
        token.addGrant({room: name, roomJoin: true, canPublish: false, canSubscribe: false,
          canPublishData: false, canUpdateOwnMetadata: false});
        members.push({identity, role: identity === row.publisher ? 'publish' : 'view', token: await token.toJwt()});
      }
      result.push({id: row.id, room: name, url: publicUrl, members});
    }
    await reconcile();
    return {rooms: result, leaseSeconds: LEASE_MS / 1000};
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'GET' && req.url === '/healthz') { res.end('{"ok":true}'); return; }
    if (req.method !== 'POST' || req.url !== '/sync') { res.writeHead(404); res.end('{}'); return; }
    const bearer = (req.headers.authorization || '').replace(/^Bearer /, '');
    const entry = Object.entries(servers).find(([, secret]) => equal(bearer, secret));
    if (!entry) { res.writeHead(401); res.end('{"error":"unauthorized"}'); return; }
    let body = '', size = 0;
    try {
      for await (const chunk of req) { size += chunk.length; if (size > 65536) throw new Error('body too large'); body += chunk; }
      const data = JSON.parse(body);
      const result = await enqueue(() => sync(entry[0], data));
      res.end(JSON.stringify(result));
    } catch (err) { res.writeHead(400); res.end('{"error":"request rejected"}'); }
  });
  server.headersTimeout = 10000;
  server.requestTimeout = 10000;
  const timer = setInterval(() => enqueue(reconcile).catch(() => console.error('Media membership reconciliation failed')), 2000);
  timer.unref();
  server.on('close', () => clearInterval(timer));
  return {server, reconcile: () => enqueue(reconcile), rooms};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const apiKey = process.env.LIVEKIT_API_KEY, apiSecret = process.env.LIVEKIT_API_SECRET;
  const servers = JSON.parse(fs.readFileSync(process.env.GEMU_SERVERS_FILE || '/run/secrets/servers.json', 'utf8'));
  if (!apiKey || !apiSecret || !Object.keys(servers).length || Object.values(servers).some(k => k.length < 32)) throw new Error('Configure service secrets');
  const admin = new RoomServiceClient(process.env.LIVEKIT_INTERNAL_URL || 'http://livekit:7880', apiKey, apiSecret);
  const {server} = createBroker({servers, apiKey, apiSecret, publicUrl: process.env.LIVEKIT_PUBLIC_URL, admin});
  server.listen(8090, '0.0.0.0', () => console.log('GEMU stream broker listening on 8090'));
}
