const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];
let lang='ru';
let csrf='';
const serviceInfo={};

const tr={
 ru:{dashboard:'Главная',live:'Видео',recording:'Запись',image:'Изображение',network:'Сеть / Wi‑Fi',storage:'SD-карта',system:'Система',firmware:'Обновление',logs:'Логи',model:'Модель',architecture:'Архитектура',imageHint:'Web UI использует camera service, который ОС подняла при загрузке.',cameraOsHint:'Сенсор и камера инициализируются ОС при загрузке; Web UI работает поверх системного camera service.',wifiSafe:'Новая сеть сначала тестируется. При ошибке backend возвращает предыдущий рабочий профиль.',scan:'Сканировать сети',password:'Пароль',testSwitch:'Проверить и переключить',reboot:'Перезагрузить',fwHint:'Обновление будет добавлено только после проверки схемы загрузки U‑Boot и recovery.',webPassword:'Пароль администратора Web UI',newPassword:'Новый пароль',repeatPassword:'Повторить пароль',changePassword:'Сменить пароль',authHint:'После смены пароля HTTP-аутентификация перезапустится.',gateway:'Шлюз',optionalServices:'Дополнительные сервисы',servicesHint:'Выключенный сервис не запускается и не занимает CPU/RAM постоянным процессом.',storageLayout:'MEDIA = 20 GiB для фото/видео; всё остальное место карты получает ROOTFS.',enable:'Включить',disable:'Выключить',running:'работает',stopped:'остановлен',unavailable:'не установлен'},
 en:{dashboard:'Dashboard',live:'Live view',recording:'Recording',image:'Image',network:'Network / Wi‑Fi',storage:'Storage / SD',system:'System',firmware:'Firmware update',logs:'Logs',model:'Model',architecture:'Architecture',imageHint:'The Web UI uses the camera service initialized by the OS at boot.',cameraOsHint:'The OS initializes the sensor and camera during boot; the Web UI operates on top of the system camera service.',wifiSafe:'The new network is tested first. On failure the backend restores the previous known-good profile.',scan:'Scan networks',password:'Password',testSwitch:'Test & switch',reboot:'Reboot',fwHint:'Firmware update will be enabled only after U‑Boot and recovery boot paths are validated.',webPassword:'Web UI administrator password',newPassword:'New password',repeatPassword:'Repeat password',changePassword:'Change password',authHint:'HTTP authentication will restart after changing the password.',gateway:'Gateway',optionalServices:'Optional services',servicesHint:'A disabled service is not started and therefore has no persistent userspace CPU/RAM process.',storageLayout:'MEDIA = 20 GiB for photos/video; all remaining card space is assigned to ROOTFS.',enable:'Enable',disable:'Disable',running:'running',stopped:'stopped',unavailable:'not installed'}
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
  const j=await r.json();
  if(!j.ok)throw new Error(j.error||'API error');
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
    stateEl.textContent=label+(info.enabled?' • autostart':'');
    btn.textContent=info.enabled?tr[lang].disable:tr[lang].enable;
    btn.disabled=info.state==='unavailable'&& !info.enabled;
    btn.classList.toggle('danger',Boolean(info.enabled));
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
  try{
    const r=await post('web_password',{new_password:a});
    $('#newWebPassword').value='';$('#repeatWebPassword').value='';toast(r.message);
  }catch(e){toast(e.message)}
}

$$('#nav button').forEach(b=>b.onclick=()=>{
  $$('#nav button').forEach(x=>x.classList.remove('active'));b.classList.add('active');
  $$('.page').forEach(x=>x.classList.remove('active'));$('#'+b.dataset.page).classList.add('active');
  $('#pageTitle').textContent=tr[lang][b.dataset.page]||b.dataset.page;
  if(b.dataset.page==='storage')loadStorage();
  if(b.dataset.page==='network')loadServices();
});
$('#langBtn').onclick=()=>{lang=lang==='ru'?'en':'ru';translate()};
$('#scanBtn').onclick=scan;
$('#wifiForm').addEventListener('submit',applyWifi);
$('#webPasswordForm').addEventListener('submit',changeWebPassword);
$('#rebootBtn').onclick=()=>{if(confirm(lang==='ru'?'Перезагрузить камеру?':'Reboot camera?'))apiAction('reboot')};

translate();
refreshStatus();
loadServices();
setInterval(refreshStatus,15000);
