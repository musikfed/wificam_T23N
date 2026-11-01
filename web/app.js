const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];
let lang='ru';
let csrf='';
let cameraPreviewMode='idle';
let previewPollTimer=null;
let previewZoom=1;
const serviceInfo={};

const tr={
 ru:{dashboard:'Главная',live:'Видео',recording:'Запись',image:'Изображение',network:'Сеть / Wi‑Fi',storage:'SD-карта',system:'Система',firmware:'Обновление',logs:'Логи',model:'Модель',architecture:'Архитектура',imageHint:'Web UI использует camera service, который ОС подняла при загрузке.',cameraOsHint:'Сенсор и камера инициализируются ОС при загрузке; Web UI работает поверх системного camera service.',wifiSafe:'Новая сеть сначала тестируется. При ошибке backend возвращает предыдущий рабочий профиль.',scan:'Сканировать сети',password:'Пароль',testSwitch:'Проверить и переключить',reboot:'Перезагрузить',fwHint:'Обновление будет добавлено только после проверки схемы загрузки U‑Boot и recovery.',webPassword:'Пароль администратора Web UI',newPassword:'Новый пароль',repeatPassword:'Повторить пароль',changePassword:'Сменить пароль',authHint:'После смены пароля HTTP-аутентификация перезапустится. Используйте 10–64 печатных ASCII-символа без пробелов; кириллица не поддерживается.',gateway:'Шлюз',optionalServices:'Дополнительные сервисы',servicesHint:'Выключенный сервис не запускается и не занимает CPU/RAM постоянным процессом.',storageLayout:'MEDIA = 20 GiB для фото/видео; всё остальное место карты получает ROOTFS.',enable:'Включить',disable:'Выключить',running:'работает',stopped:'остановлен',unavailable:'не установлен',protected:'защищён',ptzTitle:'Поворот камеры / PTZ',reversePan:'Реверс лево / право',reverseTilt:'Реверс верх / низ',autoFocus:'Автофокус (при наличии)'},
 en:{dashboard:'Dashboard',live:'Live view',recording:'Recording',image:'Image',network:'Network / Wi‑Fi',storage:'Storage / SD',system:'System',firmware:'Firmware update',logs:'Logs',model:'Model',architecture:'Architecture',imageHint:'The Web UI uses the camera service initialized by the OS at boot.',cameraOsHint:'The OS initializes the sensor and camera during boot; the Web UI operates on top of the system camera service.',wifiSafe:'The new network is tested first. On failure the backend restores the previous known-good profile.',scan:'Scan networks',password:'Password',testSwitch:'Test & switch',reboot:'Reboot',fwHint:'Firmware update will be enabled only after U‑Boot and recovery boot paths are validated.',webPassword:'Web UI administrator password',newPassword:'New password',repeatPassword:'Repeat password',changePassword:'Change password',authHint:'HTTP authentication will restart after changing the password. Use 10–64 printable ASCII characters without spaces.',gateway:'Gateway',optionalServices:'Optional services',servicesHint:'A disabled service is not started and therefore has no persistent userspace CPU/RAM process.',storageLayout:'MEDIA = 20 GiB for photos/video; all remaining card space is assigned to ROOTFS.',enable:'Enable',disable:'Disable',running:'running',stopped:'stopped',unavailable:'not installed',protected:'protected',ptzTitle:'Camera movement / PTZ',reversePan:'Reverse left / right',reverseTilt:'Reverse up / down',autoFocus:'Autofocus (if supported)'}
};

function translate(){
  $$('[data-i18n]').forEach(el=>{const k=el.dataset.i18n;if(tr[lang][k])el.textContent=tr[lang][k]});
  document.documentElement.lang=lang;
  renderServices();
}
function toast(msg){const t=$('#toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),3200);log(msg)}
function log(msg){const b=$('#logBox');if(b)b.textContent=new Date().toLocaleTimeString()+'  '+msg+'\n'+b.textContent}

async function call(op,options={}){
  const url='/cgi-bin/api?op='+encodeURIComponent(op);
  const r=await fetch(url,{cache:'no-store',credentials:'same-origin',...options});
  const body=await r.text();
  if(body.trimStart().startsWith('#!')){
    throw new Error('BusyBox CGI disabled: /cgi-bin/api is exposed as source instead of executed');
  }
  let j;
  try{j=JSON.parse(body)}
  catch{throw new Error('CGI returned non-JSON HTTP '+r.status+'; check camera httpd/CGI logs')}
  if(!r.ok||!j.ok)throw new Error(j.error||'API HTTP '+r.status);
  return j;
}
function formBody(data){return new URLSearchParams({...data,csrf}).toString()}

async function refreshStatus(){
  try{
    const s=await call('status');
    csrf=s.csrf||'';
    $('#kernel').textContent=s.kernel||'—';
    $('#ssid').textContent=s.ssid||'offline';
    $('#ip').textContent=s.ip||'no IPv4';
    $('#netSsid').textContent=s.ssid||'—';
    $('#netIp').textContent=s.ip||'—';
    $('#netGateway').textContent=s.gateway||'—';
    $('#netDns').textContent=s.dns||'—';
    $('#cameraState').textContent=s.camera||'—';
    $('#uptime').textContent=Math.floor((s.uptime||0)/60)+' min';
    $('#webUser').textContent=s.user||'unauthenticated';
    const d=(s.disk||'').split(',');
    $('#diskUse').textContent=d[3]||'—';
    $('#diskFree').textContent=d[2]?Math.round(Number(d[2])/1024)+' MiB free':'—';
    $('#online').textContent='● Online';
    $('#online').classList.add('good');
  }catch(e){
    $('#online').textContent='● API offline';
    $('#online').classList.remove('good');
    log(e.message);
  }
}

async function post(op,data={}){
  return call(op,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:formBody(data)});
}

// The browser does NOT subscribe to camera frames by default. Hombo3 RTSP
// remains independent, including when this PegineLab browser disconnects.
function previewAllowed(){
  const live=$('#live');
  return !document.hidden && Boolean(live && live.classList.contains('active'));
}
function previewButtons(){
  const start=$('#previewStart'),stop=$('#previewStop');
  if(start)start.disabled=cameraPreviewMode!=='idle';
  if(stop)stop.disabled=cameraPreviewMode==='idle';
}
function stopPreview(reason){
  // Removing src aborts the browser's HTTP MJPEG request, so its CGI/curl
  // reader can exit. Never stop Raptor RVD/RSD/RAD or Hombo3's RTSP stream.
  if(previewPollTimer!==null){clearTimeout(previewPollTimer);previewPollTimer=null;}
  cameraPreviewMode='idle';
  const img=$('#liveFrame');
  if(img){
    img.onload=null;
    img.onerror=null;
    img.removeAttribute('src');
  }
  const mode=$('#previewMode');
  if(mode)mode.textContent=reason||(lang==='ru'
    ? 'Видео выключено: нет видеотрафика вебморды'
    : 'Preview is off: web UI sends no video traffic');
  previewButtons();
}
function previewFallback(){
  if(cameraPreviewMode!=='mjpeg'||!previewAllowed())return;
  // RHD MJPEG unavailable: one snapshot at a time, only when a frame has
  // finished loading. No overlapping AJAX requests or unbounded queue.
  stopPreview();
  cameraPreviewMode='snapshot';
  const img=$('#liveFrame');
  $('#previewMode').textContent=lang==='ru'
    ? 'Резерв: одиночный JPEG не чаще раза в 2 секунды'
    : 'Fallback: one JPEG at a time, at most every 2 seconds';
  img.onerror=()=>{if(cameraPreviewMode==='snapshot')stopPreview('JPEG/CGI unavailable; check RVD and BusyBox CGI');};
  img.onload=()=>{
    if(cameraPreviewMode!=='snapshot'||!previewAllowed())return;
    previewPollTimer=setTimeout(()=>{
      previewPollTimer=null;
      if(cameraPreviewMode==='snapshot'&&previewAllowed()){
        img.src='/cgi-bin/snapshot.jpg?t='+Date.now();
      }
    },2000);
  };
  previewButtons();
  img.src='/cgi-bin/snapshot.jpg?t='+Date.now();
}
function startPreview(){
  if(!previewAllowed())return;
  stopPreview();
  cameraPreviewMode='mjpeg';
  const img=$('#liveFrame');
  $('#previewMode').textContent=lang==='ru'
    ? 'Включён MJPEG: второй поток только для этой вкладки'
    : 'MJPEG enabled: second stream for this tab only';
  img.onerror=()=>{if(cameraPreviewMode==='mjpeg'&&previewAllowed())previewFallback();};
  previewButtons();
  img.src='/cgi-bin/live.mjpg?t='+Date.now();
}
function refreshPreview(){startPreview();}
function digitalZoom(delta){
  previewZoom=delta===0?1:Math.min(3,Math.max(1,Math.round((previewZoom+delta*0.25)*100)/100));
  const img=$('#liveFrame');
  if(img)img.style.transform='scale('+previewZoom+')';
  $('#zoomState').textContent=previewZoom.toFixed(2)+'× digital preview zoom (NOT optical)';
}
async function loadPtzStatus(){
  try{
    const r=await call('ptz_status');
    const ready=Boolean(r.ptz);
    $('#ptzCapability').textContent=ready?'Thingino motors ready':'PTZ motors unavailable on this hardware/boot';
    $$('.ptz-control').forEach(b=>b.disabled=!ready);
    $('#panInvert').checked=Boolean(r.pan_invert);
    $('#tiltInvert').checked=Boolean(r.tilt_invert);
    // Focus requires a real optical focus driver. Do not present a false feature.
    $('#focusBtn').disabled=!r.autofocus;
  }catch(e){$('#ptzCapability').textContent=e.message;$$('.ptz-control').forEach(b=>b.disabled=true);}
}
async function ptzMove(direction){
  try{await post('ptz_move',{direction});}catch(e){toast(e.message);}
}
async function ptzInvert(axis,enabled){
  try{
    await post('ptz_invert',{axis,enabled:enabled?'1':'0'});
    await loadPtzStatus();
  }catch(e){toast(e.message);await loadPtzStatus();}
}

async function scan(){
  $('#networks').innerHTML='Scanning…';
  try{
    const r=await call('wifi_scan');
    $('#networks').innerHTML='';
    (r.networks||[]).forEach(n=>{
      const d=document.createElement('div');d.className='network';d.innerHTML='<b></b><span></span>';
      d.querySelector('b').textContent=n.ssid;d.querySelector('span').textContent=(n.signal||'?')+' dBm';
      d.onclick=()=>{$('#wifiSsid').value=n.ssid};$('#networks').appendChild(d);
    });
    if(!r.networks?.length)$('#networks').textContent='No networks returned';
  }catch(e){toast(e.message)}
}

async function applyWifi(ev){
  ev.preventDefault();
  try{
    toast(lang==='ru'?'Проверяем новую сеть…':'Testing new network…');
    const r=await post('wifi_apply',{ssid:$('#wifiSsid').value,password:$('#wifiPassword').value});
    $('#wifiPassword').value='';toast(r.message||'Wi-Fi updated');setTimeout(refreshStatus,1500);
  }catch(e){toast(e.message)}
}

async function apiAction(op){try{const r=await post(op);toast(r.message||op);setTimeout(refreshStatus,500)}catch(e){toast(e.message)}}
async function loadStorage(){try{const s=await call('storage');$('#storageInfo').textContent=`${Math.round(s.used_kb/1024)} MiB / ${Math.round(s.total_kb/1024)} MiB (${s.use}) — ${s.path}`}catch(e){toast(e.message)}}

async function loadServices(){
  try{
    const r=await call('services');
    Object.assign(serviceInfo,r.services||{});
    renderServices();
  }catch(e){log(e.message)}
}
function renderServices(){
  ['ssh','wireguard','amneziawg'].forEach(name=>{
    const info=serviceInfo[name]||{state:'—',enabled:0};
    const stateEl=$('#'+name+'State'),btn=$('#'+name+'Toggle');
    if(!stateEl||!btn)return;
    const label=tr[lang][info.state]||info.state;
    stateEl.textContent=label+(info.enabled?' • autostart':'')+(info.protected?' • '+tr[lang].protected:'');
    btn.textContent=info.protected?tr[lang].protected:(info.enabled?tr[lang].disable:tr[lang].enable);
    btn.disabled=Boolean(info.protected)||(info.state==='unavailable'&& !info.enabled);
    btn.classList.toggle('danger',Boolean(info.enabled)&&!info.protected);
  });
}
async function toggleService(name){
  const info=serviceInfo[name]||{enabled:0};
  try{
    const r=await post('service_toggle',{service:name,enabled:info.enabled?'0':'1'});
    toast(r.message||name);
    await loadServices();
  }catch(e){toast(e.message)}
}

async function changeWebPassword(ev){
  ev.preventDefault();
  const a=$('#newWebPassword').value,b=$('#repeatWebPassword').value;
  if(a!==b){toast(lang==='ru'?'Пароли не совпадают':'Passwords do not match');return}
  if(!/^[\x21-\x7E]{10,64}$/.test(a)){
    toast(lang==='ru'?'Пароль: 10–64 ASCII-символа без пробелов, без кириллицы':'Password: 10–64 printable ASCII characters, no spaces');
    return;
  }
  try{
    const r=await post('web_password',{new_password:a});
    $('#newWebPassword').value='';$('#repeatWebPassword').value='';toast(r.message);
  }catch(e){toast(e.message)}
}

$$('#nav button').forEach(b=>b.onclick=()=>{
  // Stop before leaving the live page; this closes the MJPEG HTTP request.
  if(b.dataset.page!=='live')stopPreview();
  $$('#nav button').forEach(x=>x.classList.remove('active'));b.classList.add('active');
  $$('.page').forEach(x=>x.classList.remove('active'));$('#'+b.dataset.page).classList.add('active');
  $('#pageTitle').textContent=tr[lang][b.dataset.page]||b.dataset.page;
  if(b.dataset.page==='live'){
    // PTZ status is lightweight. VIDEO IS NOT STARTED until explicitly requested.
    loadPtzStatus();
    previewButtons();
  }
  if(b.dataset.page==='storage')loadStorage();
  if(b.dataset.page==='network'){refreshStatus();loadServices();}
  if(b.dataset.page==='dashboard'||b.dataset.page==='system')refreshStatus();
});
$('#langBtn').onclick=()=>{lang=lang==='ru'?'en':'ru';translate()};
$('#scanBtn').onclick=scan;
$('#wifiForm').addEventListener('submit',applyWifi);
$('#webPasswordForm').addEventListener('submit',changeWebPassword);
$('#rebootBtn').onclick=()=>{if(confirm(lang==='ru'?'Перезагрузить камеру?':'Reboot camera?'))apiAction('reboot')};

// No video or network/service scans at boot. The status poll is cheap and
// only runs on status-related pages while the browser is visible.
translate();
previewButtons();
refreshStatus();
function visibleStatusPage(){
  const active=$$('.page').find(p=>p.classList.contains('active'));
  return active&&['dashboard','system','network'].includes(active.id);
}
setInterval(()=>{if(!document.hidden&&visibleStatusPage())refreshStatus();},60000);
document.addEventListener('visibilitychange',()=>{
  if(document.hidden){stopPreview();}
  else if(visibleStatusPage())refreshStatus(); // never auto-resume video
});
window.addEventListener('pagehide',()=>stopPreview());
// Prevent stale video after BFCache restores a previously viewed tab.
window.addEventListener('pageshow',()=>{if(visibleStatusPage()&&!document.hidden)refreshStatus();});

