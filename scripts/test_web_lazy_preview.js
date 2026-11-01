#!/usr/bin/env node
// No browser dependencies. Exercise the actual web/app.js with mocked DOM.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const src = fs.readFileSync(path.join(__dirname, '..', 'web/app.js'), 'utf8');
const html = fs.readFileSync(path.join(__dirname, '..', 'web/index.html'), 'utf8');
const requests = [];
const timers = new Map();
const intervals = [];
const documentListeners = {};
const windowListeners = {};
const stored = new Map();
const localStorage = {
  getItem: key => stored.get(key) ?? null,
  setItem: (key,value) => stored.set(key,String(value)),
};
let nextTimer = 1;

function element(id) {
  const flags = new Set(id === 'dashboard' ? ['active'] : []);
  let srcValue;
  const e = {
    id,
    textContent: '',
    value: '',
    disabled: false,
    dataset: {},
    style: {},
    classList: {
      add: c => flags.add(c),
      remove: c => flags.delete(c),
      contains: c => flags.has(c),
      toggle: (c, on) => { if (on) flags.add(c); else flags.delete(c); },
    },
    addEventListener: () => {},
    removeAttribute: attr => { if (attr === 'src') srcValue = undefined; },
    set src(value) { srcValue = value; requests.push('image:' + value); },
    get src() { return srcValue; },
  };
  return e;
}
const ids = new Map();
function get(id) {
  if (!ids.has(id)) ids.set(id, element(id));
  return ids.get(id);
}
const buttons = ['dashboard','live','recording','image','network','storage','system','firmware','logs']
  .map(name => { const b=element('nav-'+name); b.dataset.page=name; return b; });
const pages = ['dashboard','live','recording','image','network','storage','system','firmware','logs']
  .map(get);
const doc = {
  hidden: false,
  documentElement: {lang:'ru'},
  querySelector: sel => sel.startsWith('#') ? get(sel.slice(1)) : get(sel),
  querySelectorAll: sel => {
    if (sel === '#nav button') return buttons;
    if (sel === '.page') return pages;
    if (sel === '.ptz-control') return [];
    return [];
  },
  addEventListener: (type, cb) => { documentListeners[type] = cb; },
};
const win = {addEventListener:(type,cb)=>{windowListeners[type]=cb;}};
const sandbox = {
  document:doc, window:win,
  console, URLSearchParams, Date, localStorage,
  setTimeout:(fn)=>{const id=nextTimer++;timers.set(id,fn);return id;},
  clearTimeout:id=>timers.delete(id),
  setInterval:fn=>{intervals.push(fn);return intervals.length;},
  fetch:async (url)=>{
    requests.push('fetch:'+url);
    return {status:200,ok:true,text:async()=>JSON.stringify({
      ok:true,csrf:'test',camera:'running',ssid:'lan',disk:'0,0,0,0',
      uptime:100,services:{},ptz:true,autofocus:false,
    })};
  },
};
vm.createContext(sandbox);
vm.runInContext(src,sandbox,{filename:'web/app.js'});
const flush = () => new Promise(resolve => setImmediate(resolve));
(async()=>{
  await flush();
  assert.equal(requests.filter(v=>v.startsWith('image:')).length,0,
    'page load must not fetch a frame');
  assert.equal(requests.filter(v=>v.includes('op=services')).length,0,
    'service scan must be deferred');

  // View-only mirror/flip: transforms the browser image, not camera RTSP.
  sandbox.setPreviewOrientation('mirror',true);
  sandbox.setPreviewOrientation('flip',true);
  assert.match(get('liveFrame').style.transform,/scaleX\(-1\) scaleY\(-1\)/);
  assert.equal(stored.get('wificam.preview.mirror'),'1');
  assert.equal(stored.get('wificam.preview.flip'),'1');
  sandbox.digitalZoom(1);
  assert.match(get('liveFrame').style.transform,/scale\(1\.25\)/);
  // Preview orientation must not initiate a new network request.
  assert.equal(requests.filter(v=>v.startsWith('image:')).length,0);
  buttons.find(b=>b.dataset.page==='live').onclick();
  await flush();
  assert.equal(get('liveFrame').src,undefined,
    'switching to PTZ must not auto-start video');
  assert.equal(get('previewStart').disabled,false);

  sandbox.startPreview();
  assert.match(get('liveFrame').src,/\/cgi-bin\/live\.mjpg/);
  assert.equal(get('previewStart').disabled,true);
  assert.equal(get('previewStop').disabled,false);

  get('liveFrame').onerror(); // RHD unavailable -> single JPEG fallback.
  assert.match(get('liveFrame').src,/\/cgi-bin\/snapshot\.jpg/);
  assert.equal(requests.filter(v=>v.startsWith('image:/cgi-bin/snapshot.jpg')).length,1);
  get('liveFrame').onload(); // schedule the next frame after previous completes.
  assert.equal(timers.size,1);
  buttons.find(b=>b.dataset.page==='dashboard').onclick();
  assert.equal(get('liveFrame').src,undefined,'tab switch must release image request');
  assert.equal(timers.size,0,'tab switch must cancel pending JPEG refresh');

  buttons.find(b=>b.dataset.page==='live').onclick();
  sandbox.startPreview();
  doc.hidden=true;
  documentListeners.visibilitychange();
  assert.equal(get('liveFrame').src,undefined,'background tab must disconnect MJPEG');
  const before=requests.length;
  intervals.forEach(fn=>fn());
  assert.equal(requests.length,before,'no background status requests');
  doc.hidden=false;
  documentListeners.visibilitychange();
  assert.equal(get('liveFrame').src,undefined,'returning must not auto-start video');
  sandbox.startPreview();
  windowListeners.pagehide();
  assert.equal(get('liveFrame').src,undefined,'page unload must disconnect stream');

  assert(!html.includes('onclick="apiAction(\'camera_stop\')"'),
    'web UI must not stop shared Raptor used by Hombo3');
  assert(!html.includes('id="liveFrame" src='),'no image URL on initial HTML');
  console.log('WEB LAZY PREVIEW: OK. Zero idle JPEG, pause-on-hide/exit, no RTSP shutdown.');
})().catch(e=>{console.error(e);process.exitCode=1;});
