const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];
let lang='ru';
let csrf='';
let cameraPreviewMode='idle';
let previewPollTimer=null;
let previewZoom=1;
let previewMirror=false;
let previewFlip=false;
try{
  previewMirror=localStorage.getItem('wificam.preview.mirror')==='1';
  previewFlip=localStorage.getItem('wificam.preview.flip')==='1';
}catch(_){} 
const serviceInfo={};

const tr={
 ru:{logsHint:'Журнал HTTPD камеры загружается только по кнопке.',logsLoad:'Загрузить журнал камеры',logsBrowser:'Журнал браузерного интерфейса',firmwareRefresh:'Обновить информацию',imageOpenCamera:'Открыть настройки просмотра и PTZ',imageControlsHint:'Цифровой zoom, зеркало и переворот работают в браузере. Оптический фокус и разрешение пока не изменяются без проверенного драйвера.',helperNav:'Голова / Помощник',helperTitle:'Камера как голова робота или голосовой помощник',helperIntro:'Одна прошивка, два режима. Настройка сохраняется на SD и не останавливает видеопоток.',helperRobot:'Голова робота Hombo3',helperRobotHint:'Видео и PTZ для робота. Приводы колёс управляются через ESP32-S3 и Acer.',helperVoice:'Голосовой помощник',helperVoiceHint:'Камерный звук и зрение; STT, TTS и LLM выполняются на CORE.',helperSelectRobot:'Выбрать голову робота',helperSelectVoice:'Выбрать помощника',helperHealth:'Диагностика камеры',helperHealthNote:'Наличие программы не означает, что физический микрофон или динамик проверен.',helperRefresh:'Обновить состояние',helperMic:'Микрофон (rad)',helperSpeaker:'Динамик (rac)',helperVideo:'Видео (rvd)',helperHardware:'Физическая проверка',helperOpenCamera:'Открыть видео / PTZ',helperOpenSystem:'Настройки и перезапуск',helperActive:'Активен',helperDetected:'Команда доступна',helperMissing:'Не обнаружена',helperNotVerified:'Ещё не проверено',helperRoleSet:'Режим сохранён на камере',helperError:'Не удалось переключить режим',helperUnavailable:'Helper отсутствует в этой прошивке',assistant:'ИИ / Голос',assistantTitle:'LLM / GPT напарник',assistantEnable:'Включить режим LLM / GPT',assistantHint:'Речь и GPT обрабатывает внешняя программа. На камере сохраняется только переключатель; звук автоматически не передаётся.',assistantArchitecture:'Камера + внешний голосовой сервер',assistantArchitectureHint:'RTSP не зависит от режима ИИ. Для разговора через микрофон и динамик камеры нужен внешний мост и проверка двустороннего аудио.',assistantPageInfo:'Настройка разрешает внешней программе подключаться к голосовому режиму. ИИ не запускается на T23N, аудиопоток не передаётся до подключения моста.',assistantMode:'Режим',assistantBridge:'Внешний мост',assistantBridgeHint:'Подключено означает недавний сигнал от программы, но не проверку микрофона и динамика.',assistantSecrets:'Ключи GPT / LLM хранятся только на внешнем компьютере или сервере, не в прошивке.',assistantGuide:'Инструкция по подключению голосового моста',assistantOn:'включён',assistantOff:'выключен',assistantConnected:'сигнал получен',assistantWaiting:'не подключён',dashboard:'Главная',live:'Видео',recording:'Запись',image:'Изображение',network:'Сеть / Wi‑Fi',storage:'SD-карта',system:'Система',firmware:'Обновление',logs:'Логи',model:'Модель',architecture:'Архитектура',imageHint:'Web UI использует camera service, который ОС подняла при загрузке.',cameraOsHint:'Сенсор и камера инициализируются ОС при загрузке; Web UI работает поверх системного camera service.',wifiSafe:'Новая сеть сначала тестируется. При ошибке backend возвращает предыдущий рабочий профиль.',scan:'Сканировать сети',password:'Пароль',testSwitch:'Проверить и переключить',reboot:'Перезагрузить',fwHint:'Обновление будет добавлено только после проверки схемы загрузки U‑Boot и recovery.',webPassword:'Пароль администратора Web UI',newPassword:'Новый пароль',repeatPassword:'Повторить пароль',changePassword:'Сменить пароль',authHint:'После смены пароля HTTP-аутентификация перезапустится. Используйте 10–64 печатных ASCII-символа без пробелов; кириллица не поддерживается.',gateway:'Шлюз',optionalServices:'Дополнительные сервисы',servicesHint:'Выключенный сервис не запускается и не занимает CPU/RAM постоянным процессом.',storageLayout:'MEDIA = 20 GiB для фото/видео; всё остальное место карты получает ROOTFS.',enable:'Включить',disable:'Выключить',running:'работает',stopped:'остановлен',unavailable:'не установлен',protected:'защищён',ptzTitle:'Поворот камеры / PTZ',reversePan:'Реверс лево / право',reverseTilt:'Реверс верх / низ',autoFocus:'Автофокус (при наличии)'},
 en:{logsHint:'Load the camera HTTPD log on demand; no background polling.',logsLoad:'Load camera log',logsBrowser:'Browser UI log',firmwareRefresh:'Refresh firmware identity',imageOpenCamera:'Open live preview and PTZ settings',imageControlsHint:'Digital zoom, mirror and flip affect only the browser preview. Optical focus and resolution require verified hardware drivers.',helperNav:'Robot head / Assistant',helperTitle:'Camera as a robot head or a voice assistant',helperIntro:'One firmware, two modes. The selected role persists on SD without stopping video.',helperRobot:'Hombo3 robot head',helperRobotHint:'Camera and PTZ for the robot. Wheel motors remain controlled via ESP32-S3 and Acer.',helperVoice:'Voice assistant',helperVoiceHint:'Camera audio and vision; STT, TTS and LLM run on CORE.',helperSelectRobot:'Select robot head',helperSelectVoice:'Select voice assistant',helperHealth:'Camera diagnostics',helperHealthNote:'A command being installed does not prove the physical microphone or speaker works.',helperRefresh:'Refresh state',helperMic:'Microphone (rad)',helperSpeaker:'Speaker (rac)',helperVideo:'Video (rvd)',helperHardware:'Hardware verification',helperOpenCamera:'Open video / PTZ',helperOpenSystem:'Settings and reboot',helperActive:'Active',helperDetected:'Command available',helperMissing:'Not detected',helperNotVerified:'Not tested yet',helperRoleSet:'Role saved on camera',helperError:'Failed to switch mode',helperUnavailable:'Helper is not installed in this firmware',assistant:'AI / Voice',assistantTitle:'LLM / GPT companion',assistantEnable:'Enable LLM / GPT mode',assistantHint:'Speech and GPT are handled by an external application. The camera saves only a switch; no audio is transmitted automatically.',assistantArchitecture:'Camera + external voice server',assistantArchitectureHint:'RTSP is independent of AI mode. Using the camera microphone and speaker requires an external bridge and bidirectional-audio validation.',assistantPageInfo:'This setting permits an external companion to use the camera. No AI runs on the T23N; no audio is sent until an external bridge is configured.',assistantMode:'Mode',assistantBridge:'External bridge',assistantBridgeHint:'Connected means a recent bridge heartbeat, not proof of functioning microphone or speaker.',assistantSecrets:'Keep GPT / LLM API keys on an external computer or server, never in camera firmware.',assistantGuide:'External voice bridge setup guide',assistantOn:'enabled',assistantOff:'disabled',assistantConnected:'heartbeat received',assistantWaiting:'not connected',dashboard:'Dashboard',live:'Live view',recording:'Recording',image:'Image',network:'Network / Wi‑Fi',storage:'Storage / SD',system:'System',firmware:'Firmware update',logs:'Logs',model:'Model',architecture:'Architecture',imageHint:'The Web UI uses the camera service initialized by the OS at boot.',cameraOsHint:'The OS initializes the sensor and camera during boot; the Web UI operates on top of the system camera service.',wifiSafe:'The new network is tested first. On failure the backend restores the previous known-good profile.',scan:'Scan networks',password:'Password',testSwitch:'Test & switch',reboot:'Reboot',fwHint:'Firmware update will be enabled only after U‑Boot and recovery boot paths are validated.',webPassword:'Web UI administrator password',newPassword:'New password',repeatPassword:'Repeat password',changePassword:'Change password',authHint:'HTTP authentication will restart after changing the password. Use 10–64 printable ASCII characters without spaces.',gateway:'Gateway',optionalServices:'Optional services',servicesHint:'A disabled service is not started and therefore has no persistent userspace CPU/RAM process.',storageLayout:'MEDIA = 20 GiB for photos/video; all remaining card space is assigned to ROOTFS.',enable:'Enable',disable:'Disable',running:'running',stopped:'stopped',unavailable:'not installed',protected:'protected',ptzTitle:'Camera movement / PTZ',reversePan:'Reverse left / right',reverseTilt:'Reverse up / down',autoFocus:'Autofocus (if supported)'}
};

function translate(){
  $$('[data-i18n]').forEach(el=>{const k=el.dataset.i18n;if(tr[lang][k])el.textContent=tr[lang][k]});
  document.documentElement.lang=lang;
  renderServices();
  renderAssistant();
  renderHelper();
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
    $('#rebootBtn').disabled=s.reboot_allowed!==true;
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
function applyPreviewOrientation(){
  const img=$('#liveFrame');
  if(img)img.style.transform='scale('+previewZoom+') scaleX('+(previewMirror?-1:1)+') scaleY('+(previewFlip?-1:1)+')';
  $('#zoomState').textContent=previewZoom.toFixed(2)+'× digital zoom • '+(previewMirror?'mirror ':'')+(previewFlip?'vertical flip ':'')+'(browser only)';
}
function setPreviewOrientation(axis,enabled){
  if(axis==='mirror')previewMirror=!!enabled;
  if(axis==='flip')previewFlip=!!enabled;
  try{
    localStorage.setItem('wificam.preview.mirror',previewMirror?'1':'0');
    localStorage.setItem('wificam.preview.flip',previewFlip?'1':'0');
  }catch(_){}
  applyPreviewOrientation();
}
function digitalZoom(delta){
  previewZoom=delta===0?1:Math.min(3,Math.max(1,Math.round((previewZoom+delta*0.25)*100)/100));
  applyPreviewOrientation();
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

async function loadImageCapabilities(){
  try{
    const status=await call('ptz_status');
    const text=lang==='ru'
      ? 'PTZ: '+(status.ptz?'обнаружен':'недоступен')+' • Автофокус: '+(status.autofocus?'поддерживается':'нет')+
        ' • Оптический zoom: '+(status.optical_zoom?'поддерживается':'нет')
      : 'PTZ: '+(status.ptz?'available':'unavailable')+' • Autofocus: '+(status.autofocus?'supported':'no')+
        ' • Optical zoom: '+(status.optical_zoom?'supported':'no');
    $('#imageCapabilities').textContent=text;
  }catch(e){$('#imageCapabilities').textContent=e.message;}
}
async function loadCameraLogs(){
  try{
    const result=await call('web_log');
    $('#cameraLogBox').textContent=result.log||'(no camera HTTPD log entries yet)';
  }catch(e){$('#cameraLogBox').textContent=e.message;log(e.message);}
}
async function loadFirmwareInfo(){
  try{
    const result=await call('firmware_info');
    $('#firmwareIdentity').textContent=result.firmware||'—';
    $('#firmwareBoard').textContent=result.board||'—';
    $('#firmwarePort').textContent=':'+result.web_port;
  }catch(e){$('#firmwareIdentity').textContent=e.message;log(e.message);}
}
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



// The Helper firmware uses the SAME WIFICAM navigation and Basic Auth.
// A generic WIFICAM build has no Helper CGI and keeps this tab invisible.
// No microphone capture, video streaming, or inference begins on page load.
const helperInfo={available:false,mode:'',helper_booted:false,
  microphone_transport:false,speaker_transport:false,video_transport:false,hardware_verified:false};
let helperBusy=false;
function renderHelper(){
  const nav=$('#helperNav'),page=$('#helper');
  if(!nav||!page)return;
  nav.hidden=!helperInfo.available;
  page.hidden=!helperInfo.available;
  if(!helperInfo.available)return;
  const t=tr[lang],robot=helperInfo.mode==='robot_head',voice=helperInfo.mode==='voice_assistant';
  $('#helperCurrentMode').textContent=robot?t.helperRobot:(voice?t.helperVoice:'—');
  $('#helperRobotCard').classList.toggle('is-selected',robot);
  $('#helperVoiceCard').classList.toggle('is-selected',voice);
  $('#helperRobotMode').disabled=helperBusy||robot;
  $('#helperVoiceMode').disabled=helperBusy||voice;
  $('#helperRobotMode').textContent=robot?t.helperActive:t.helperSelectRobot;
  $('#helperVoiceMode').textContent=voice?t.helperActive:t.helperSelectVoice;
  $('#helperMicState').textContent=helperInfo.microphone_transport?t.helperDetected:t.helperMissing;
  $('#helperSpeakerState').textContent=helperInfo.speaker_transport?t.helperDetected:t.helperMissing;
  $('#helperVideoState').textContent=helperInfo.video_transport?t.helperDetected:t.helperMissing;
  $('#helperHardwareState').textContent=helperInfo.hardware_verified?t.helperDetected:t.helperNotVerified;
}
async function helperRequest(mode=''){
  const options={cache:'no-store',credentials:'same-origin'};
  if(mode){
    if(!csrf)await refreshStatus();
    if(!csrf)throw new Error('WIFICAM CSRF token unavailable');
    options.method='POST';
    options.headers={'Content-Type':'application/x-www-form-urlencoded'};
    options.body=new URLSearchParams({mode,csrf}).toString();
  }
  const response=await fetch('/cgi-bin/helper-capabilities',options);
  const payload=await response.text();
  if(payload.trimStart().startsWith('#!'))throw new Error('Helper CGI source exposed; check BusyBox httpd');
  let value;
  try{value=JSON.parse(payload);}catch{throw new Error('Helper CGI returned non-JSON HTTP '+response.status);}
  if(!response.ok||value.ok!==true)throw new Error(value.error||'Helper HTTP '+response.status);
  if(value.schema!=='peginelab.camera-head.v1')throw new Error('Unsupported Helper firmware API');
  return value;
}
async function loadHelper(){
  try{
    const data=await helperRequest();
    Object.assign(helperInfo,data,{available:true});
    $('#helperMessage').textContent=data.helper_booted
      ? (lang==='ru'?'Служба Helper запущена. Проверка физического звука — следующий этап.':'Helper booted. Physical audio validation is a separate step.')
      : (lang==='ru'?'Служба Helper ещё не подтвердила загрузку.':'Helper boot marker not present yet.');
  }catch(e){
    // Generic WIFICAM intentionally has no helper endpoint.
    if(helperInfo.available){$('#helperMessage').textContent=e.message;log(e.message);}
    else if(String(e.message).includes('source exposed'))log(e.message);
  }
  renderHelper();
}
async function selectHelperMode(mode){
  if(helperBusy||!helperInfo.available)return;
  if(!['robot_head','voice_assistant'].includes(mode))return;
  helperBusy=true;renderHelper();
  try{
    const data=await helperRequest(mode);
    Object.assign(helperInfo,data,{available:true});
    $('#helperMessage').textContent=tr[lang].helperRoleSet;
    toast(tr[lang].helperRoleSet);
  }catch(e){
    $('#helperMessage').textContent=tr[lang].helperError+': '+e.message;
    toast(e.message);
  }finally{helperBusy=false;renderHelper();}
}

const assistantInfo={enabled:false,connected:false};
async function loadAssistant(){
  const toggle=$('#assistantEnabled');
  if(!toggle)return;
  try{
    const data=await call('assistant_status');
    assistantInfo.enabled=Boolean(data.enabled);
    assistantInfo.connected=Boolean(data.connected);
    toggle.checked=assistantInfo.enabled;
    toggle.disabled=false;
    renderAssistant();
  }catch(e){
    toggle.disabled=true;
    $('#assistantState').textContent=lang==='ru'?'API недоступно':'API unavailable';
    log(e.message);
  }
}
function renderAssistant(){
  const t=tr[lang];
  const state=assistantInfo.enabled
    ?(assistantInfo.connected?t.assistantConnected:t.assistantWaiting)
    :t.assistantOff;
  $('#assistantState').textContent=state;
  $('#assistantModeValue').textContent=assistantInfo.enabled?t.assistantOn:t.assistantOff;
  $('#assistantBridgeValue').textContent=assistantInfo.connected?t.assistantConnected:t.assistantWaiting;
}
async function toggleAssistant(){
  const el=$('#assistantEnabled');
  const desired=el.checked;
  el.disabled=true;
  try{
    if(!csrf)await refreshStatus();
    if(!csrf)throw new Error(lang==='ru'?'Нет CSRF токена':'CSRF token unavailable');
    const data=await post('assistant_toggle',{enabled:desired?'1':'0'});
    assistantInfo.enabled=Boolean(data.enabled);
    assistantInfo.connected=Boolean(data.connected);
    el.checked=assistantInfo.enabled;
    renderAssistant();
    toast(lang==='ru'?(desired?'Режим LLM разрешён; подключите внешний мост':'Режим LLM выключен'):(desired?'LLM mode enabled; connect external bridge':'LLM mode disabled'));
  }catch(e){
    el.checked=assistantInfo.enabled;
    toast(e.message);
  }finally{el.disabled=false;}
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
  if(b.dataset.page==='image')loadImageCapabilities();
  if(b.dataset.page==='firmware')loadFirmwareInfo();
  if(b.dataset.page==='assistant')loadAssistant();
  if(b.dataset.page==='helper')loadHelper();
  if(b.dataset.page==='network'){refreshStatus();loadServices();}
  if(b.dataset.page==='dashboard'||b.dataset.page==='system')refreshStatus();
});
$('#langBtn').onclick=()=>{lang=lang==='ru'?'en':'ru';translate()};
$('#scanBtn').onclick=scan;
$('#loadCameraLogs').onclick=loadCameraLogs;
$('#firmwareRefresh').onclick=loadFirmwareInfo;
$('#openImagePreview').onclick=()=>document.querySelector('button[data-page="live"]').click();
$('#assistantEnabled').addEventListener('change',toggleAssistant);
$('#helperRobotMode').onclick=()=>selectHelperMode('robot_head');
$('#helperVoiceMode').onclick=()=>selectHelperMode('voice_assistant');
$('#helperRefresh').onclick=loadHelper;
$('#helperGoLive').onclick=()=>document.querySelector('[data-page="live"]').click();
$('#helperGoSystem').onclick=()=>document.querySelector('[data-page="system"]').click();
$('#wifiForm').addEventListener('submit',applyWifi);
$('#webPasswordForm').addEventListener('submit',changeWebPassword);
$('#rebootBtn').onclick=()=>{if(confirm(lang==='ru'?'Перезагрузить камеру?':'Reboot camera?'))apiAction('reboot')};

// No video or network/service scans at boot. The status poll is cheap and
// only runs on status-related pages while the browser is visible.
translate();
previewButtons();
$('#previewMirror').checked=previewMirror;
$('#previewFlip').checked=previewFlip;
applyPreviewOrientation();
refreshStatus();
loadAssistant();
loadHelper();
function visibleStatusPage(){
  const active=$$('.page').find(p=>p.classList.contains('active'));
  return active&&['dashboard','system','network','assistant','helper'].includes(active.id);
}
setInterval(()=>{if(!document.hidden&&visibleStatusPage()){refreshStatus();if($('#helper').classList.contains('active'))loadHelper();}},60000);
document.addEventListener('visibilitychange',()=>{
  if(document.hidden){stopPreview();}
  else if(visibleStatusPage())refreshStatus(); // never auto-resume video
});
window.addEventListener('pagehide',()=>stopPreview());
// Prevent stale video after BFCache restores a previously viewed tab.
window.addEventListener('pageshow',event=>{if(event.persisted&&visibleStatusPage()&&!document.hidden)refreshStatus();});

