#!/usr/bin/env node
// Simulate the actual browser UI against the real Helper CGI protocol, no camera required.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const base=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(base,'web/index.html'),'utf8');
const css=fs.readFileSync(path.join(base,'web/styles.css'),'utf8');
const js=fs.readFileSync(path.join(base,'web/app.js'),'utf8');
for(const id of ['helperNav','helper','helperRobotMode','helperVoiceMode','helperRefresh',
  'helperCurrentMode','helperMicState','helperSpeakerState','helperVideoState','helperHardwareState'])
  assert(html.includes('id="'+id+'"'),'missing Helper element '+id);
assert(css.includes('[hidden]{display:none!important}'),'hidden helper must not display in generic WIFICAM');
let mode='voice_assistant',posts=[],videoRequests=[];
const els=new Map(),listeners={};
function get(id){
  if(!els.has(id)){
    const classes=new Set(id==='dashboard'?['active']:[]);
    els.set(id,{id,textContent:'',value:'',checked:false,disabled:false,hidden:true,style:{},dataset:{},
      classList:{add:x=>classes.add(x),remove:x=>classes.delete(x),contains:x=>classes.has(x),
        toggle:(x,v)=>v?classes.add(x):classes.delete(x)},addEventListener(){},
      removeAttribute(){},set src(v){videoRequests.push(v)}});
  }
  return els.get(id);
}
const names=['dashboard','live','recording','image','network','storage','assistant','helper','system','firmware','logs'];
const nav=names.map(n=>{const e=get('nav-'+n);e.dataset.page=n;return e;});
const document={
  hidden:false,documentElement:{lang:'ru'},
  querySelector(s){return s.startsWith('#')?get(s.slice(1)):get(s)},
  querySelectorAll(s){if(s==='#nav button')return nav;if(s==='.page')return names.map(get);return []},
  addEventListener(n,fn){listeners[n]=fn}
};
const statuses={ok:true,csrf:'testcsrf',ssid:'lab',disk:'0,0,0,0',camera:'running',uptime:100};
const result=()=>({ok:true,schema:'peginelab.camera-head.v1',mode,
  available_modes:['robot_head','voice_assistant'],helper_booted:true,
  microphone_transport:true,speaker_transport:true,video_transport:true,hardware_verified:false});
const response=(value)=>({ok:true,status:200,text:async()=>JSON.stringify(value)});
const ctx={console,document,URLSearchParams,Date,localStorage:{getItem:()=>null,setItem:()=>{}},
  window:{addEventListener(){}},confirm:()=>true,
  setTimeout:()=>1,clearTimeout(){},setInterval:()=>1,
  fetch:async(url,options={})=>{
    if(url==='/cgi-bin/helper-capabilities'){
      if(options.method==='POST'){
        const data=new URLSearchParams(options.body);
        assert.equal(data.get('csrf'),'testcsrf','Helper must use main API form-CSRF token');
        assert(['robot_head','voice_assistant'].includes(data.get('mode')));
        assert.equal(options.headers['Content-Type'],'application/x-www-form-urlencoded');
        posts.push(data.get('mode'));mode=data.get('mode');
      }
      return response(result());
    }
    if(url.includes('op=assistant_status'))return response({ok:true,enabled:false,connected:false});
    if(url.includes('op=status'))return response(statuses);
    return response({ok:true});
  }};
vm.createContext(ctx);
vm.runInContext(js,ctx,{filename:'app.js'});
const flush=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
  await flush();await flush();
  assert.equal(get('helperNav').hidden,false,'helper tab must become visible on Helper firmware');
  assert.equal(get('helper').hidden,false);
  assert.equal(get('helperCurrentMode').textContent,'Голосовой помощник');
  assert.equal(get('helperRobotMode').disabled,false);
  assert.equal(get('helperVoiceMode').disabled,true);
  assert.equal(videoRequests.length,0,'initial UI must not subscribe to video');
  await ctx.selectHelperMode('robot_head');
  assert.deepEqual(posts,['robot_head']);
  assert.equal(get('helperRobotMode').disabled,true);
  assert.equal(get('helperVoiceMode').disabled,false);
  assert.equal(get('helperCurrentMode').textContent,'Голова робота Hombo3');
  assert.equal(videoRequests.length,0);
  console.log('HELPER WEB UI: JSON auth, form CSRF, both modes, no idle video: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
