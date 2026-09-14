// Spectator audio capture: AudioWorklet processor, graph tap and mu-law codec.
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert');

let count = 0;
const check = (value, message) => { assert(value, message); count++; };

async function main() {
  // The processor mixes stereo to mono and box-filters down to the stream rate.
  let Processor;
  const posted = [];
  const workletContext = vm.createContext({
    sampleRate: 44100, Float32Array,
    AudioWorkletProcessor: class { constructor() { this.port = {postMessage: (data) => posted.push(data)}; } },
    registerProcessor: (name, cls) => { assert.strictEqual(name, 'gemu-capture'); Processor = cls; }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/capture-worklet.js'), 'utf8'), workletContext);
  const processor = new Processor({processorOptions: {rate: 11025, block: 4}});
  check(processor.process([[new Float32Array(16).fill(0.5), new Float32Array(16).fill(-0.1)]]) === true, 'processor stays alive');
  check(posted.length === 1 && posted[0].length === 4, 'a block posts after rate x block input samples');
  check(Math.abs(posted[0][0] - 0.2) < 1e-6, 'stereo is mixed to mono and averaged');
  check(processor.process([[]]) === true && processor.process([]) === true, 'missing input is tolerated');

  // The page taps every node connected to the destination, including early ones.
  const modules = [];
  let tap;
  class FakeNode {
    constructor(context) { this.context = context; this.connections = []; }
    connect(destination) { this.connections.push(destination); return destination; }
  }
  class FakeContext {
    constructor() {
      this.destination = {name: 'destination'};
      this.audioWorklet = {addModule: (url) => { modules.push(url); return Promise.resolve(); }};
    }
    createGain() { const node = new FakeNode(this); node.gain = {value: 1}; return node; }
    createBufferSource() { return new FakeNode(this); }
  }
  const win = {AudioContext: FakeContext};
  const pageContext = vm.createContext({
    window: win, console, Math, Promise,
    btoa: (text) => Buffer.from(text, 'binary').toString('base64'),
    AudioWorkletNode: class extends FakeNode {
      constructor(context, name, options) { super(context); this.name = name; this.options = options; this.port = {}; tap = this; }
    }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/systems.js'), 'utf8'), pageContext);
  const frames = [];
  win.EmuSystems.gba.prepareAudioCapture((data, rate) => frames.push({data, rate}));
  const context = new win.AudioContext();
  const early = context.createBufferSource();
  early.connect(context.destination);
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(modules[0] === 'capture-worklet.js' && tap && tap.name === 'gemu-capture', 'capture loads the AudioWorklet module');
  check(tap.options.processorOptions.rate === 11025, 'worklet resamples to the stream rate');
  check(early.connections.includes(tap), 'output connected before the worklet loads is tapped when ready');
  const late = context.createGain();
  late.connect(context.destination);
  check(late.connections.includes(tap), 'later game output is tapped immediately');
  const sink = tap.connections[0];
  check(sink.gain.value === 0 && !sink.connections.includes(tap), 'the silent sink never feeds back into the tap');

  // Encoded blocks decode with the same table the spectator page uses.
  const values = [0, 0.5, -0.5, 1, -1, 0.01];
  tap.port.onmessage({data: Float32Array.from(values)});
  const bytes = Buffer.from(frames[0].data, 'base64');
  const decode = (b) => { const u = ~b & 255, m = (Math.pow(256, (u & 127) / 127) - 1) / 255; return u & 128 ? -m : m; };
  check(frames[0].rate === 11025 && bytes.length === values.length, 'one mu-law byte per sample');
  check(bytes[0] === 0xff, 'silence encodes as 0xFF');
  values.forEach((value, i) => check(Math.abs(decode(bytes[i]) - value) < 0.02, 'mu-law round-trips sample ' + value));

  console.log(`All ${count} audio capture tests PASSED!`);
}

main().catch((err) => { console.error(err); process.exit(1); });
