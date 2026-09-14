// The catalog the addon fetches from the shared host must satisfy both Lua loaders:
// sv_emu_management wants data.roms[*].{filename,system}; cl_emu_management shows title or filename.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');

const ROOT = path.join(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, 'web/roms.json'), 'utf8'));
const extensions = {snes: ['smc', 'sfc'], nes: ['nes'], genesis: ['md', 'bin', 'gen', 'smd'],
  gb: ['gb'], gbc: ['gbc'], gba: ['gba']};
let count = 0;
function check(value, message) { assert(value, message || 'catalog check failed'); count++; }

check(catalog && typeof catalog === 'object' && !Array.isArray(catalog), 'catalog must be an object, not a bare array');
check(Array.isArray(catalog.roms) && catalog.roms.length > 0, 'catalog must expose a non-empty roms list');

const seen = new Set();
for (const row of catalog.roms) {
  const label = row && row.filename;
  check(typeof label === 'string' && /^[a-z0-9_]+\.[a-z0-9]+$/.test(label), 'hosted filename must be lowercase with a known extension: ' + label);
  check(!seen.has(label), 'duplicate catalog filename: ' + label);
  seen.add(label);
  check(extensions[row.system] !== undefined, 'unknown system in catalog: ' + row.system);
  check(extensions[row.system].includes(label.slice(label.lastIndexOf('.') + 1)), label + ' does not belong to ' + row.system);
  check(Number.isInteger(row.size) && row.size > 0, 'row missing a size: ' + label);
  check(typeof row.sha256 === 'string' && /^[0-9a-f]{64}$/.test(row.sha256), 'row missing a sha256: ' + label);
  const file = path.join(ROOT, 'web/roms', row.system, label);
  if (fs.existsSync(file)) {
    const bytes = fs.readFileSync(file);
    check(bytes.length === row.size, label + ' catalog size is stale');
    check(crypto.createHash('sha256').update(bytes).digest('hex') === row.sha256, label + ' catalog sha256 is stale');
  }
}
console.log('All ' + count + ' catalog checks PASSED!');
// Spawn defaults must exist in our selected development deployment too.
const vm = require('vm');
const context = {window: {}}; vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(ROOT,'web/systems.js'),'utf8'),context);
for (const system of Object.keys(extensions)) {
  const lua = fs.readFileSync(path.join(ROOT,'lua/emu/systems',system+'.lua'),'utf8');
  const rom = lua.match(/defaultRom\s*=\s*"([^"]+)"/)[1];
  assert(catalog.roms.some(r=>r.system===system && r.filename===rom),system+' spawn default is absent from hosted catalog');
  assert.equal(context.window.EmuSystems[system].defaultRom,rom,system+' browser and Lua defaults differ');
}
console.log('All six spawn defaults match the development catalog and browser.');
