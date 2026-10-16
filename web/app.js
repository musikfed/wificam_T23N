const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];
let lang='ru';

const tr={
 ru:{dashboard:'Главная',live:'Видео',recording:'Запись',image:'Изображение',network:'Сеть / Wi‑Fi',storage:'SD-карта',system:'Система',firmware:'Обновление',logs:'Логи',model:'Модель',architecture:'Архитектура',imageHint:'Параметры сенсора/ISP будут подключены через camera service.',wifiSafe:'Новая сеть сначала тестируется. При ошибке backend возвращает предыдущий рабочий профиль.',scan:'Сканировать сети',password:'Пароль',testSwitch:'Проверить и переключить',reboot:'Перезагрузить',fwHint:'Обновление будет добавлено только после проверки схемы загрузки U‑Boot и recovery.'},
 en:{dashboard:'Dashboard',live:'Live view',recording:'Recording',image:'Image',network:'Network / Wi‑Fi',storage:'Storage / SD',system:'System',firmware:'Firmware update',logs:'Logs',model:'Model',architecture:'Architecture',imageHint:'Sensor/ISP controls will be connected through the camera service.',wifiSafe:'The new network is tested first. On failure the backend restores the previous known-good profile.',scan:'Scan networks',password:'Password',testSwitch:'Test & switch',reboot:'Reboot',fwHint:'Firmware update will be enabled only after U‑Boot and recovery boot paths are validated.'}
};

function translate(){
  $$('[data-i18n]').forEach(el=>{const k=el.dataset.i18n;if(tr[lang][k])el.textContent=tr[lang][k]});
  document.documentElement.lang=lang;
}
function toast(msg){const t=$('#toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),3200);log(msg)}
function log(msg){const b=$('#logBox');if(b)b.textContent=new Date().toLocaleTimeString()+'  '+msg+'\n'+b.textContent}

async function call(op,options={}){
  const url='/cgi-bin/api?op='+encodeURIComponent(op);
  const r=await fetch(url,{cache:'no-store',...options});
  const j=await r.json();
  if(!j.ok)throw new Error(j.error||'API error');
  return j;
}

async function refreshStatus(){
  try{
    const s=await call('status');
    $('#kernel').textContent=s.kernel||'—';
    $('#ssid').textContent=s.ssid||'offline';
    $('#ip').textContent=s.ip||'no IPv4';
    $('#uptime').textContent=Math.floor((s.uptime||0)/60)+' min';
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

async function scan(){
  $('#networks').innerHTML='Scanning…';
  try{
    const r=await call('wifi_scan');
    $('#networks').innerHTML='';
    (r.networks||[]).forEach(n=>{
      const d=document.createElement('div');
      d.className='network';
      d.innerHTML='<b></b><span></span>';
      d.querySelector('b').textContent=n.ssid;
      d.querySelector('span').textContent=(n.signal||'?')+' dBm';
      d.onclick=()=>{$('#wifiSsid').value=n.ssid};
      $('#networks').appendChild(d);
    });
    if(!r.networks?.length)$('#networks').textContent='No networks returned';
  }catch(e){toast(e.message)}
}

async function applyWifi(ev){
  ev.preventDefault();
  const body=new URLSearchParams({ssid:$('#wifiSsid').value,password:$('#wifiPassword').value}).toString();
  try{
    toast(lang==='ru'?'Проверяем новую сеть…':'Testing new network…');
    const r=await call('wifi_apply',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
    $('#wifiPassword').value='';
    toast(r.message||'Wi-Fi updated');
    setTimeout(refreshStatus,1500);
  }catch(e){toast(e.message)}
}

async function apiAction(op){try{const r=await call(op);toast(r.message||op)}catch(e){toast(e.message)}}
async function loadStorage(){try{const s=await call('storage');$('#storageInfo').textContent=`${Math.round(s.used_kb/1024)} MiB / ${Math.round(s.total_kb/1024)} MiB (${s.use}) — ${s.path}`}catch(e){toast(e.message)}}

$$('#nav button').forEach(b=>b.onclick=()=>{
  $$('#nav button').forEach(x=>x.classList.remove('active'));b.classList.add('active');
  $$('.page').forEach(x=>x.classList.remove('active'));$('#'+b.dataset.page).classList.add('active');
  $('#pageTitle').textContent=tr[lang][b.dataset.page]||b.dataset.page;
  if(b.dataset.page==='storage')loadStorage();
});
$('#langBtn').onclick=()=>{lang=lang==='ru'?'en':'ru';translate()};
$('#scanBtn').onclick=scan;
$('#wifiForm').addEventListener('submit',applyWifi);
$('#rebootBtn').onclick=()=>{if(confirm(lang==='ru'?'Перезагрузить камеру?':'Reboot camera?'))apiAction('reboot')};

translate();
refreshStatus();
setInterval(refreshStatus,15000);
