const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert');

console.log('Running Web Core Smoke Test...');

const systemId = process.argv[2] || 'snes';
const isGBA = systemId === 'gba';
const romName = {snes:'super_mario_world.smc',gba:'hello_world.gba',nes:'gemu_test.nes',gb:'gemu_test.gb',gbc:'gemu_test.gbc',genesis:'gemu_test.md'}[systemId];
const gameTitle = systemId === 'snes' ? 'Super Mario World' : isGBA ? 'Homebrew Demo' : 'GEMU Test';
const coreCode = fs.readFileSync(path.join(__dirname, '../web/cores', systemId === 'gbc' ? 'gb' : systemId, 'emulatrix.js'), 'utf8');
const savesCode = fs.readFileSync(path.join(__dirname, "../web/saves.js"), "utf8");
const appCode = fs.readFileSync(path.join(__dirname, '../web/app.js'), 'utf8');

let renderedFrames = 0;
let nextRAF = 1;
const rafs = new Map();
const canvasMock = {
    getContext: () => ({
        getImageData: (x, y, w, h) => ({
            data: new Uint8ClampedArray(w * h * 4)
        }),
        putImageData: () => { renderedFrames++; }
        ,createImageData: (w,h) => ({data: new Uint8ClampedArray(w*h*4)})
        ,drawImage: () => {}
        ,fillRect: () => {}
        ,clearRect: () => {}
    }),
    toDataURL: () => 'data:image/jpeg;base64,/9j/2Q==',
    getBoundingClientRect: () => ({width:640,height:480,left:0,top:0}),
    style: {},
    addEventListener: () => {}
};

const domMock = {
    getElementById: (id) => ({
        getBoundingClientRect: () => ({width:640,height:480,left:0,top:0}),
        appendChild: () => {},
        style: {},
        classList: { add: () => {}, remove: () => {} },
        addEventListener: () => {}
    }),
    createElement: (tag) => {
        if (tag === 'canvas') return canvasMock;
        return {
            style: {},
            appendChild: () => {},
            querySelector: () => canvasMock,
            getBoundingClientRect: () => ({width:640,height:480,left:0,top:0}),
            addEventListener: () => {},
            classList: { add: () => {}, remove: () => {} }
        };
    },
    addEventListener: () => {},
    body: { classList: { add: () => {}, remove: () => {} } }
};

const audioMock = class {
    constructor() {
        this.currentTime = 0;
        this.state = 'running';
        this.destination = {};
    }
    createBuffer(channels, length, sampleRate) {
        return {
            duration: length / sampleRate,
            getChannelData: () => new Float32Array(length)
        };
    }
    createBufferSource() {
        return {
            connect: (destination) => { this.lastDestination = destination; },
            start: () => {}
        };
    }
    createGain() {
        return {context: this, connect: () => {}, gain: {
            value: 1, setValueAtTime(value) { this.value = value; }
        }};
    }
    resume() { this.state = 'running'; return Promise.resolve(); }
    suspend() { this.state = 'suspended'; return Promise.resolve(); }
    close() { this.state = 'closed'; return Promise.resolve(); }
};

let gmodOnReady = false;
let gmodGameLoaded = null;
const windowListeners = {};

const windowObj = {
    Event: class { constructor(type) { this.type = type; } },
    dispatchEvent: (event) => (windowListeners[event.type] || []).forEach(fn => fn(event)),
    AudioContext: audioMock,
    addEventListener: (evt, fn) => {
        (windowListeners[evt] = windowListeners[evt] || []).push(fn);
    },
    document: domMock,
    location: {
        search: '?system=' + systemId + '&rom=' + romName + '&game=' + encodeURIComponent(gameTitle) + '&mode=screen',
        reload: () => { throw new Error('Core requested page reload during startup'); }
    },
    gmod: {
        onReady: () => { gmodOnReady = true; },
        onGameLoaded: (title) => { gmodGameLoaded = title; },
        onError: (err) => console.error('GMod Error:', err)
        ,onVideoFrame: (data) => { windowObj.videoFrame = data; }
    }
};

const context = vm.createContext({
    window: windowObj,
    global: windowObj,
    document: domMock,
    console: console,
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: clearTimeout,
    setInterval: (fn, ms) => setInterval(fn, ms),
    clearInterval: clearInterval,
    requestAnimationFrame: (fn) => { const id=nextRAF++; rafs.set(id,fn); return id; },
    cancelAnimationFrame: (id) => rafs.delete(id),
    Event: windowObj.Event,
    TextDecoder, TextEncoder, performance,
    navigator: {userAgent:'test', maxTouchPoints:0},
    localStorage: {data: {}, setItem(k,v) {this.data[k]=v;}, getItem(k) {return this.data[k];}},
    URLSearchParams: URLSearchParams,
    ArrayBuffer: ArrayBuffer,
    Uint8Array: Uint8Array,
    Uint8ClampedArray: Uint8ClampedArray,
    Int8Array: Int8Array,
    Uint16Array: Uint16Array,
    Int16Array: Int16Array,
    Uint32Array: Uint32Array,
    Int32Array: Int32Array,
    Float32Array: Float32Array,
    Float64Array: Float64Array,
    Math: Math,
    btoa: (str) => Buffer.from(str, 'binary').toString('base64'),
    atob: (b64) => Buffer.from(b64, 'base64').toString('binary'),
    fetch: async (url) => {
        assert.strictEqual(url, 'roms/' + systemId + '/' + encodeURIComponent(romName), 'ROM URL must include its system folder');
        const romPath = path.join(__dirname, '../web/roms', systemId, romName);
        const buf = fs.readFileSync(romPath);
        return {
            ok: true,
            status: 200,
            arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)
        };
    }
});

// Run Core
vm.runInContext(coreCode, context);

vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/systems.js'), 'utf8'), context);

// Run App Bridge
vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/save-storage.js'), 'utf8'), context);
vm.runInContext(savesCode, context);
    vm.runInContext(appCode, context);

// Fire 'load' event
if (windowListeners['load']) {
    windowListeners['load'].forEach(fn => fn());
}

async function run() {
    // Wait for boot
    for (let i = 0; i < 40; i++) {
        await new Promise(r => setTimeout(r, 50));
        if (windowObj.GModEmulator && windowObj.GModEmulator.isReady) break;
    }

    if (!windowObj.GModEmulator || !windowObj.GModEmulator.isReady) {
        throw new Error('Emulator failed to report ready within timeout');
    }

    console.log('Emulator ready confirmed!');
    console.log('Loaded game:', windowObj.GModEmulator.getLoadedGame());
    assert(gmodOnReady && gmodGameLoaded === gameTitle, 'real bridge callbacks must fire');
    const adapter = windowObj.EmuSystems[systemId];
    const gain = windowObj[adapter.gain];
    windowObj.GModEmulator.setVolume(0.25);
    assert.strictEqual(gain.gain.value, 0.25, 'quarter volume must change gain, not just enable sound');
    windowObj.GModEmulator.setVolume(0);
    assert.strictEqual(gain.gain.value, 0, 'mute must set gain to zero');
    windowObj.GModEmulator.setVolume(2);
    assert.strictEqual(gain.gain.value, 1, 'volume must clamp to one');
    windowObj.GModEmulator.setVolume(NaN);
    assert.strictEqual(gain.gain.value, 1, 'invalid volume must not poison audio gain');

    windowObj.GModEmulator.configureHardware();
    windowObj.GModEmulator.setHardwareButtons(['up', 'a']);
    const inputName = {snes:'SUPERNINTENDO_KEY_INPUT_1',gba:'GAMEBOYADVANCE_KEYS',nes:'NINTENDO_KEYSTATE1',gb:'GAMEBOY_INPUT_STATE',gbc:'GAMEBOY_INPUT_STATE',genesis:'GENESIS_INPUT_STATE_1'}[systemId];
    if (systemId === 'snes') assert.strictEqual(windowObj[inputName], (1<<11)|(1<<7));
    else if (systemId === 'genesis') assert.strictEqual(windowObj[inputName], windowObj.GENESIS_BTN_UP|windowObj.GENESIS_BTN_A);
    else assert(windowObj[inputName][4] && windowObj[inputName][8], 'Up/A must reach libretro indices');
    windowObj.GModEmulator.setHardwareButtons([]);
    assert(typeof windowObj[inputName] === 'number' ? windowObj[inputName] === 0 : Object.keys(windowObj[inputName]).length === 0, 'input release clears core state');

    let frameTime = performance.now();
    function advance() {
        for (let i = 1; i <= 30; i++) {
            const pending = [...rafs.entries()]; rafs.clear();
            frameTime += 17;
            pending.forEach(([,fn]) => fn(frameTime));
        }
    }
    advance();
    assert(renderedFrames > 0, 'core must actually render frames');
    assert.strictEqual(windowObj[adapter.audio].lastDestination, gain, 'audio sources must connect through gain');
    windowObj.GModEmulator.pause();
    const pausedFrames = renderedFrames;
    advance();
    assert.strictEqual(renderedFrames, pausedFrames, 'pause must stop frame execution');
    windowObj.GModEmulator.resume();
    await Promise.resolve(); // GBA schedules its resumed RAF after AudioContext.resume().
    advance();
    assert(renderedFrames > pausedFrames, 'resume must restart frames');
    // Losing browser focus (closing the window, leaving play) must not pause the game.
    windowObj.dispatchEvent(new windowObj.Event('blur'));
    await new Promise(r => setTimeout(r, 20));
    const blurredFrames = renderedFrames;
    advance();
    assert(renderedFrames > blurredFrames, 'a browser blur must not pause gameplay');
    const pauseReports = [];
    windowObj.gmod.onPauseChanged = (value) => pauseReports.push(value);
    windowObj.GModEmulator.togglePause();
    advance();
    const heldFrames = renderedFrames;
    windowObj.dispatchEvent(new windowObj.Event('focus'));
    await new Promise(r => setTimeout(r, 20));
    advance();
    assert.strictEqual(renderedFrames, heldFrames, 'a player pause survives focus changes');
    assert(windowObj.GModEmulator.streamSource(), 'a paused game keeps its stream source');
    windowObj.GModEmulator.togglePause();
    await new Promise(r => setTimeout(r, 20));
    advance();
    assert(renderedFrames > heldFrames && pauseReports.join() === 'true,false', 'toggling resumes and reports pause changes');
    windowObj.GModEmulator.captureFrame(35);
    assert(windowObj.videoFrame, 'both cores must expose spectator frame capture');
    console.log('Frame render tests passed!');

    // Test save state & load state
    const stateB64 = windowObj.GModEmulator.saveState();
    if (!stateB64 || stateB64.length < 100) {
        throw new Error('Save state returned invalid base64');
    }
    console.log('Save state generated, size:', stateB64.length, 'chars');

    const loadOk = windowObj.GModEmulator.loadState(stateB64);
    if (!loadOk) {
        throw new Error('Load state failed');
    }
    console.log('Load state confirmed!');
    assert(await windowObj.GModEmulator.quickSave() && await windowObj.GModEmulator.quickLoad(), 'shared quick save/load must roundtrip');
    windowObj.GModEmulator.setVolume(0.25);
    windowObj.GModEmulator.reset();
    assert.strictEqual(gain.gain.value, 0.25, 'reset must preserve volume');
    await windowObj.GModEmulator.shutdown();
    assert(typeof windowObj[inputName] === 'number' ? windowObj[inputName] === 0 : Object.keys(windowObj[inputName]).length === 0, 'shutdown releases input');
    assert.strictEqual(windowObj[adapter.audio].state, 'closed', 'shutdown closes audio');

    console.log('All Web Core Smoke Tests PASSED!');
    process.exit(0);
}

run().catch(err => {
    console.error('Test FAILED:', err);
    process.exit(1);
});
