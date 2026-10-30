import 'dart:convert';

import 'package:pure_live/i18n/i18n.dart';

/// The receiver's self-contained browser remote; no external assets, cookies,
/// tokens in URLs, HTML interpolation of user titles, or credential export.
String remoteControlHtml() {
  final labels = <String, String>{
    for (final key in [
      'remote_control_title',
      'remote_control_pair',
      'remote_control_code',
      'remote_control_link',
      'remote_control_send',
      'remote_control_unpair',
      'remote_control_idle',
      'remote_control_failed',
      'remote_control_paired',
      'remote_control_ok',
      'play',
      'pause',
      'refresh',
      'previous',
      'next',
      'volume',
      'mute',
      'fullscreen',
      'danmaku',
      'back',
    ])
      key: i18nOr(key, key),
  };
  final encoded = jsonEncode(labels).replaceAll('<', r'\u003c');
  return '''
<!doctype html><html lang="zh"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>PureLive</title>
<style>body{font:16px system-ui;background:#14161b;color:#f4f4f6;max-width:640px;margin:auto;padding:24px}input,button{font:inherit;border-radius:12px;padding:12px;border:1px solid #777;margin:4px;min-height:48px}input{max-width:90%}button{cursor:pointer;background:#303743;color:inherit}button:disabled{opacity:.4}#keys{display:grid;grid-template-columns:repeat(3,1fr)}#keys button{min-width:0}#state{overflow-wrap:anywhere}#status{min-height:24px}</style>
<h1 id="title"></h1><div id="pair"><input id="code" inputmode="numeric" maxlength="6" autocomplete="off"><button id="connect"></button></div>
<p id="status" role="status"></p><div id="remote" hidden><p id="state"></p>
<div id="keys"></div><p><input id="link" type="text" maxlength="4096"><button id="send"></button></p>
<label id="volumeLabel" for="volume"></label><input id="volume" type="range" min="0" max="100" value="50"><p><button id="disconnect"></button></p></div>
<script>
const labels=$encoded;
const el=id=>document.getElementById(id);let token=sessionStorage.getItem('purelive-remote-token')||'',target=null,busy=false;
el('title').textContent=labels.remote_control_title;el('code').placeholder=labels.remote_control_code;
el('connect').textContent=labels.remote_control_pair;el('link').placeholder=labels.remote_control_link;
el('send').textContent=labels.remote_control_send;el('disconnect').textContent=labels.remote_control_unpair;
el('volumeLabel').textContent=labels.volume;
async function api(path,body){const r=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{'Authorization':'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',signal:AbortSignal.timeout(15000)});if(!r.ok){if(r.status===401){token='';sessionStorage.removeItem('purelive-remote-token');show();}throw Error(r.status)}return r.status===200&&r.headers.get('content-type')?.includes('json')?await r.json():null;}
function show(){el('pair').hidden=!!token;el('remote').hidden=!token;}
async function status(){if(!token)return;try{const data=await api('status');target=data.targetId;el('state').textContent=data.state?[data.state.nick,data.state.title].filter(Boolean).join(' · '):labels.remote_control_idle;const allowed=data.state?.commands||[];document.querySelectorAll('#keys button').forEach(b=>b.disabled=!target||!allowed.includes(b.dataset.command));if(typeof data.state?.volume==='number'&&document.activeElement!==el('volume'))el('volume').value=Math.round(data.state.volume*100);}catch(e){el('status').textContent=labels.remote_control_failed;}}
async function command(command,value){if(busy||!target)return;busy=true;const selected=target;try{await api('command',{targetId:selected,command,value});el('status').textContent=labels.remote_control_ok;}catch(e){el('status').textContent=labels.remote_control_failed;}finally{busy=false;await status();}}
for(const command of ['previous','up','next','left','ok','right','play','down','pause','refresh','mute','fullscreen','danmaku','back']){const button=document.createElement('button');button.dataset.command=command;button.textContent=({up:'↑',down:'↓',left:'←',right:'→',ok:'OK'})[command]||labels[command]||command;button.onclick=()=>command&&window.runRemoteCommand(command);el('keys').append(button);}
window.runRemoteCommand=command=>window.remoteDispatch(command);window.remoteDispatch=command;
el('connect').onclick=async()=>{try{const data=await api('pair',{code:el('code').value.trim()});token=data.token;sessionStorage.setItem('purelive-remote-token',token);el('code').value='';el('status').textContent=labels.remote_control_paired;show();await status();}catch(e){el('status').textContent=labels.remote_control_failed;}};
el('send').onclick=async()=>{if(busy)return;busy=true;try{await api('link',{text:el('link').value.trim()});el('status').textContent=labels.remote_control_ok;el('link').value='';}catch(e){el('status').textContent=labels.remote_control_failed;}finally{busy=false;await status();}};
el('volume').onchange=()=>command('volume',Number(el('volume').value)/100);
el('disconnect').onclick=async()=>{try{await api('unpair',{});}finally{token='';target=null;sessionStorage.removeItem('purelive-remote-token');show();}};
show();status();setInterval(status,2000);
</script></html>''';
}
