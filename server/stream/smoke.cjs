const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');
const assert = require('assert/strict');
const base = (process.env.GEMU_SMOKE_ORIGIN || (()=>{throw new Error('Set GEMU_SMOKE_ORIGIN to your HTTPS origin');})()).replace(/\/$/, '');
const key = fs.readFileSync(process.env.GEMU_STREAM_KEY_FILE || (()=>{throw new Error('Set GEMU_STREAM_KEY_FILE to the game-server credential file');})(),'utf8').trim();
const instance = 'smoke_' + Date.now();
async function sync(rooms) {
  const response = await fetch(base+'/gemu-stream/sync', {method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({instance,rooms})});
  assert.equal(response.status,200);return response.json();
}
(async()=>{
  let browser, timer;
  try {
    const response = await fetch(base+'/gemu-stream/sync',{method:'POST',body:'{}'});assert.equal(response.status,401);
    browser = await chromium.launch({channel:'chrome',headless:true,args:['--autoplay-policy=no-user-gesture-required']});
    const catalog = await (await fetch(base+'/gemu/roms.json')).json();
    const landing = await browser.newPage();let coreRequests=0;
    landing.on('request',r=>{if(r.url().includes('/cores/') || r.url().includes('/roms/'))coreRequests++;});
    await landing.goto(base+'/gemu');
    await landing.waitForFunction(n=>document.querySelectorAll('.library-game').length===n,catalog.roms.length);
    assert.equal(await landing.locator('#app').isVisible(),false);
    await landing.locator('nav a[href="?system=gba"]').click();
    await landing.waitForFunction(n=>document.querySelectorAll('.library-game').length===n,catalog.roms.filter(r=>r.system==='gba').length);
    assert.equal(coreRequests,0);await landing.close();
    console.log('Root library and GBA filter: PASS (no automatic ROM/core downloads)');
    const publisher = await browser.newPage(), viewer = await browser.newPage();
    for(const page of [publisher,viewer]) {
      await page.addInitScript(()=>{window.gemuRTC={status:(ok,detail)=>{window.rtcStatus={ok,detail};}}});
      page.on('pageerror',e=>console.log('Page error:',e.message.slice(0,200)));
    }
    await publisher.route('**/gemu/rtc-smoke.html',route=>route.fulfill({contentType:'text/html',body:`<!doctype html><body><canvas width="256" height="224"></canvas><script>
      const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
      let n=0;setInterval(()=>{ctx.fillStyle='hsl('+n++%360+',80%,50%)';ctx.fillRect(0,0,256,224);ctx.fillStyle='white';ctx.fillText(String(n),10,30)},33);
      const audio=new AudioContext(),gain=audio.createGain(),tone=audio.createOscillator();gain.gain.value=.03;tone.connect(gain);tone.start();
      window.GModEmulator={streamSource:()=>({canvas,audio:gain})};
      </script><script src="stream.js"></script></body>`}));
    await publisher.goto(base+'/gemu/rtc-smoke.html');await viewer.goto(base+'/gemu/viewer.html');
    const rooms=[{id:'one',publisher:'publisher',viewers:['viewer']}];
    async function refresh(){const data=await sync(rooms);const r=data.rooms[0];for(const [page,id] of [[publisher,'publisher'],[viewer,'viewer']]) await page.evaluate(c=>GEMUStream.configure(c),{room:r.room,url:r.url,token:r.members.find(m=>m.identity===id).token});}
    await refresh();timer=setInterval(()=>refresh().catch(()=>{}),5000);
    await Promise.all([publisher.waitForFunction(()=>window.rtcStatus?.ok,{},{timeout:25000}),viewer.waitForFunction(()=>window.rtcStatus?.ok,{},{timeout:25000})]);
    const result=await viewer.evaluate(()=>({time:document.querySelector('video').currentTime,frames:document.querySelector('video').getVideoPlaybackQuality().totalVideoFrames,audio:document.querySelector('audio').srcObject.getAudioTracks().length}));
    assert.ok(result.frames>0);assert.equal(result.audio,1);
    const audioPeak=await viewer.evaluate(async()=>{
      const ctx=new AudioContext();await ctx.resume();
      const source=ctx.createMediaStreamSource(document.querySelector('audio').srcObject),analyser=ctx.createAnalyser();source.connect(analyser);
      await new Promise(r=>setTimeout(r,250));const samples=new Float32Array(analyser.fftSize);analyser.getFloatTimeDomainData(samples);
      const peak=Math.max(...samples.map(Math.abs));await ctx.close();return peak;
    });
    assert.ok(audioPeak>0.001);result.audioPeak=audioPeak;
    console.log('Public WebRTC publish/view PASS:',JSON.stringify(result));
    clearInterval(timer);timer=null;
    await publisher.evaluate(()=>GEMUStream.stop());
    await viewer.waitForFunction(()=>!window.rtcStatus.ok,{},{timeout:5000});
    console.log('Publisher departure detected: PASS');
  } catch(e){console.error(e.message);process.exitCode=1;}
  finally {if(timer)clearInterval(timer);await sync([]).catch(()=>{});if(browser)await browser.close();}
})();
