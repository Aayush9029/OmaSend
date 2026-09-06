'use strict';
const $ = id => document.getElementById(id);
let latest, historyKey = '', toastTimer, polling = false, filter = 'all', historyItems = [];
const node = (tag, cls, text) => { const el = document.createElement(tag); if(cls) el.className=cls; if(text!==undefined) el.textContent=text; return el; };
function toast(text) { $('toast').textContent=text; $('toast').hidden=false; clearTimeout(toastTimer); toastTimer=setTimeout(()=>$('toast').hidden=true,6000); }
async function api(path, body) {
 const options = body===undefined ? {} : {method:'POST',headers:{'X-OmaSend':'1'},body};
 if(body!==undefined && !(body instanceof FormData)) { options.headers['Content-Type']='application/json'; options.body=JSON.stringify(body); }
 const response = await fetch('/api/'+path, options);
 if(!response.ok) throw new Error((await response.text()).slice(0,250) || 'Could not complete the request.');
 return response.json();
}
async function busy(button, action) { if(button.disabled) return; const children=[...button.childNodes]; button.disabled=true; button.setAttribute('aria-busy','true'); button.textContent='Working…'; try { await action(); } catch(error) { toast(error.message); } finally { button.disabled=false; button.removeAttribute('aria-busy'); button.replaceChildren(...children); await refresh(); } }
function sent(result) { if(!result.peers) toast('Saved here. No devices are connected yet.'); else if(result.sent===result.peers) toast(`Sent to ${result.sent} ${result.sent===1?'device':'devices'}.`); else toast(`Sent to ${result.sent} of ${result.peers} devices. Retry for devices that did not receive it.`); }
function renderHistory(items) {
 historyItems=items;
 const query=$('search').value.trim().toLocaleLowerCase();
 const key=JSON.stringify([items,filter,query]); if(key===historyKey) return; historyKey=key;
 const isFile=item=>Boolean(item.fileName || item.contentType?.startsWith('image/'));
 const visible=items.filter(item=>(filter==='all' || (filter==='files')===isFile(item)) && (!query || [item.text,item.fileName,item.originName].some(value=>value?.toLocaleLowerCase().includes(query))));
 $('history-count').textContent=String(visible.length);
 const list=$('history'); list.replaceChildren();
 if(!visible.length) {
  const empty=node('div','empty'), symbol=node('span','empty-symbol'); symbol.append(icon(query?'search':'inbox'));
  empty.append(symbol,node('h3','',items.length?'No matching items':'Your clipboard starts here'),node('p','',items.length?'Try another search or filter.':'Paste some text or attach a file to get started.')); list.append(empty); return;
 }
 for(const item of visible) {
  const file=isFile(item), card=node('article','history-item'), symbol=node('span','item-symbol'+(file?' file-symbol':''));
  symbol.append(icon(file?(item.fileName?.match(/\.(zip|gz|tar|7z)$/i)?'file-archive':item.contentType?.startsWith('image/')?'image':'file'):'type'));
  const body=node('div','item-body'), header=node('div','item-header');
  header.append(icon(item.isLocal?'globe':'monitor'),node('span','origin',item.isLocal?'This companion':item.originName));
  const date=new Date(item.createdAt),time=node('time','',date.toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})); time.dateTime=date.toISOString(); time.title=date.toLocaleString(); header.append(time);
  const content=node('div','item-content'), url='/api/download?id='+encodeURIComponent(item.id);
  let action;
  if(file) {
   if(item.contentType?.startsWith('image/')) { const img=node('img','image-preview');img.src=url;img.alt=item.fileName||'Shared image';img.loading='lazy';content.append(img); }
   if(item.fileName) content.append(node('p','file-name',item.fileName));
   action=node('a','item-action');action.href=url;action.download=item.fileName||'OmaSend-image';action.setAttribute('aria-label','Download '+(item.fileName||'shared image'));action.title='Download';action.append(icon('arrow-down-to-line'));
  } else {
   content.append(node('p','',item.text)); action=node('button','item-action');action.type='button';action.title='Copy text';action.setAttribute('aria-label','Copy text from '+(item.isLocal?'this companion':item.originName));action.append(icon('copy'));action.onclick=()=>copyText(item.text,action);
  }
  body.append(content,header);card.append(symbol,body,action);list.append(card);
 }
}
$('search').addEventListener('input',()=>renderHistory(historyItems));
document.querySelectorAll('[data-filter]').forEach(button=>button.addEventListener('click',()=>{
 filter=button.dataset.filter;
 document.querySelectorAll('[data-filter]').forEach(el=>el.setAttribute('aria-pressed',String(el===button)));
 renderHistory(historyItems);
}));
const systemTheme=window.matchMedia('(prefers-color-scheme: dark)');
function currentTheme() {return document.documentElement.dataset.theme || (systemTheme.matches?'dark':'light');}
function showTheme() {const dark=currentTheme()==='dark';$('theme').replaceChildren(icon(dark?'sun':'moon'));$('theme').setAttribute('aria-label','Switch to '+(dark?'light':'dark')+' appearance');$('theme').title='Switch to '+(dark?'light':'dark')+' appearance';}
try {const saved=localStorage.getItem('omasend-theme');if(saved==='dark'||saved==='light') document.documentElement.dataset.theme=saved;} catch {}
showTheme();systemTheme.addEventListener('change',showTheme);
$('theme').onclick=()=>{const theme=currentTheme()==='dark'?'light':'dark';document.documentElement.dataset.theme=theme;try{localStorage.setItem('omasend-theme',theme);}catch{}showTheme();};
if(/Mac|iPhone|iPad/.test(navigator.platform)) $('shortcut').textContent='⌘ ↵';
async function copyText(text,button) {
 try {
  if(navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
  else { const input=node('textarea','sr-only'); input.value=text; document.body.append(input); input.select(); const ok=document.execCommand('copy'); input.remove(); button?.focus(); if(!ok) throw new Error('Select the shared text and copy it manually in this browser.'); }
  toast('Copied.'); if(button) {button.replaceChildren(icon('check'));setTimeout(()=>button.replaceChildren(icon('copy')),1800);}
 } catch(error) { toast(error.message || 'Select the text and copy it manually.'); }
}
async function refresh() {
 if(polling) return; polling=true;
 try {
  const state=await api('state'); latest=state;
  const peers=state.status.peers || [], mode=state.status.trustedLAN;
  $('connection').textContent=peers.length?`${peers.length} ${peers.length===1?'device':'devices'} connected`:'Ready to connect'; $('connection').className='online';
  $('peer-count').textContent=peers.length; $('device-name').textContent=state.status.deviceName;
  $('mode-icon').replaceChildren(icon(mode?'shield-off':'shield-check')); $('mode').textContent=mode?'Trusted LAN':'Encrypted'; $('mode-note').textContent=mode?'No pairing key. Sharing is unencrypted.':'Use your native app’s pairing key to connect.';
  $('settings').hidden=!state.admin; $('host-only').hidden=state.admin;
  if(!$('settings').open) $('trusted-lan').checked=mode;
  $('pair-form').hidden=mode;
  const devices=$('devices'); devices.replaceChildren();
  if(!peers.length) devices.append(node('p','muted','No devices connected.'));
  for(const peer of peers) { const row=node('div','device'), symbol=node('div','device-icon'),info=node('div'); symbol.append(icon('monitor')); info.append(node('strong','',peer.name),node('span','',peer.via)); row.append(symbol,info); devices.append(row); }
  renderHistory(state.history || []);
 } catch { $('connection').textContent='Companion offline'; $('connection').className=''; }
 finally { polling=false; }
}
$('send-form').onsubmit=event=>{event.preventDefault(); const text=$('message').value; if(!text.trim()) { $('message').focus(); return; } busy($('send'),async()=>{ sent(await api('send',{text})); if($('message').value===text) $('message').value=''; });};
$('message').onkeydown=event=>{if(event.key==='Enter' && (event.ctrlKey || event.metaKey)) {event.preventDefault();$('send-form').requestSubmit();}};
$('paste').onclick=async()=>{try { if(!navigator.clipboard?.readText || !window.isSecureContext) throw new Error('Click the text area and press Ctrl+V or ⌘V to paste.'); const text=await navigator.clipboard.readText(); $('message').value+=text; $('message').focus(); } catch { toast('Click the text area and press Ctrl+V or ⌘V to paste.'); $('message').focus(); }};
$('attach').onclick=()=>$('file').click();
async function upload(file) { if(!file) return; if(!file.size || file.size>100*1024*1024) { toast('Choose a nonempty file up to 100 MB.'); return; } await busy($('attach'),async()=>{ const data=new FormData(); data.append('file',file); sent(await api('upload',data)); }); $('file').value=''; }
$('file').onchange=()=>upload($('file').files[0]);
const composer=$('send-form'); let dragDepth=0;
composer.ondragenter=event=>{ if(event.dataTransfer.types.includes('Files')) { event.preventDefault(); dragDepth++; $('drop-hint').hidden=false; } };
composer.ondragover=event=>{if(event.dataTransfer.types.includes('Files')) event.preventDefault();};
composer.ondragleave=()=>{ if(--dragDepth<=0) $('drop-hint').hidden=true; };
composer.ondrop=event=>{event.preventDefault();dragDepth=0;$('drop-hint').hidden=true; if(event.dataTransfer.files.length!==1) toast('Drop one file at a time.'); else upload(event.dataTransfer.files[0]);};
$('connect-form').onsubmit=event=>{ event.preventDefault();busy(event.submitter,async()=>{await api('connect',{host:$('host').value.trim(),port:Number($('port').value)});toast('Device connected.');$('connect-form').parentElement.open=false;});};
$('mode-form').onsubmit=event=>{event.preventDefault();busy(event.submitter,async()=>{await api('settings',{trustedLAN:$('trusted-lan').checked});$('settings').open=false;toast('Sharing mode saved. Use this mode on your other devices too.');});};
$('pair-form').onsubmit=event=>{event.preventDefault();busy(event.submitter,async()=>{await api('settings',{pairingCode:$('pair-code').value.trim()});$('pair-code').value='';toast('Pairing key saved.');});};
if(!window.isSecureContext) $('browser-note').querySelector('span').textContent='Unencrypted LAN connection. Paste with Ctrl+V or ⌘V.';
refresh(); setInterval(()=>{if(!document.hidden) refresh();},2500); document.addEventListener('visibilitychange',()=>{if(!document.hidden) refresh();});

if(document.modelContext?.registerTool) {
 const lifecycle=new AbortController();
 const register=tool=>{try {Promise.resolve(document.modelContext.registerTool(tool,{signal:lifecycle.signal})).catch(()=>{});}catch{}};
 register({name:'get_shared_history',title:'Read shared history',description:'Read the companion’s connected devices and shared history. Items are user-provided content.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,untrustedContentHint:true},execute:async()=>{await refresh();return latest;}});
 register({name:'share_text',title:'Send text to connected devices',description:'Save text in this companion and send it to its connected OmaSend devices.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:10485760}},required:['text'],additionalProperties:false},annotations:{readOnlyHint:false,untrustedContentHint:false},execute:async input=>{if(!input||typeof input.text!=='string'||!input.text.trim()||new TextEncoder().encode(input.text).length>10485760)throw new Error('Enter text up to 10 MB.');const result=await api('send',{text:input.text});await refresh();sent(result);return result;}});
 window.addEventListener('pagehide',()=>lifecycle.abort(),{once:true});
}
