'use strict';
const $ = id => document.getElementById(id);
let latest, historyKey = '', toastTimer, polling = false;
const node = (tag, cls, text) => { const el = document.createElement(tag); if(cls) el.className=cls; if(text!==undefined) el.textContent=text; return el; };
function toast(text) { $('toast').textContent=text; $('toast').hidden=false; clearTimeout(toastTimer); toastTimer=setTimeout(()=>$('toast').hidden=true,6000); }
async function api(path, body) {
 const options = body===undefined ? {} : {method:'POST',headers:{'X-OmaSend':'1'},body};
 if(body!==undefined && !(body instanceof FormData)) { options.headers['Content-Type']='application/json'; options.body=JSON.stringify(body); }
 const response = await fetch('/api/'+path, options);
 if(!response.ok) throw new Error((await response.text()).slice(0,250) || 'Could not complete the request.');
 return response.json();
}
async function busy(button, action) { const label=button.textContent; button.disabled=true; button.textContent='Working…'; try { await action(); } catch(error) { toast(error.message); } finally { button.disabled=false; button.textContent=label; await refresh(); } }
function sent(result) { if(!result.peers) toast('Saved here. No devices are connected yet.'); else if(result.sent===result.peers) toast(`Sent to ${result.sent} ${result.sent===1?'device':'devices'}.`); else toast(`Sent to ${result.sent} of ${result.peers} devices. Retry for devices that did not receive it.`); }
function renderHistory(items) {
 const key=JSON.stringify(items); if(key===historyKey) return; historyKey=key;
 $('history-count').textContent=items.length ? `${items.length} ${items.length===1?'item':'items'}` : '';
 const list=$('history'); list.replaceChildren();
 if(!items.length) { const empty=node('div','empty'); empty.append(node('span','empty-mark','↙'),node('h3','','Nothing shared yet'),node('p','','Send something here, or copy it on a connected device.')); list.append(empty); return; }
 for(const item of items) {
  const card=node('article','history-item'), header=node('div','item-header');
  header.append(node('span','origin',item.isLocal?'This companion':item.originName));
  const date=new Date(item.createdAt),time=node('time','',date.toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})); time.dateTime=date.toISOString(); time.title=date.toLocaleString(); header.append(time); card.append(header);
  const content=node('div','item-content'), url='/api/download?id='+encodeURIComponent(item.id);
  if(item.fileName) { content.append(node('p','',item.fileName)); const a=node('a','','Download'); a.href=url; a.download=item.fileName; content.append(a); }
  else if(item.contentType?.startsWith('image/')) { const img=node('img','image-preview'); img.src=url; img.alt='Shared image'; img.loading='lazy'; const a=node('a','','Download'); a.href=url; a.download='OmaSend-image'; content.append(img,a); }
  else { const text=node('p','',item.text), copy=node('button','','Copy'); copy.type='button'; copy.setAttribute('aria-label','Copy text from '+(item.isLocal?'this companion':item.originName)); copy.onclick=()=>copyText(item.text,copy); content.append(text,copy); }
  card.append(content); list.append(card);
 }
}
async function copyText(text,button) {
 try {
  if(navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
  else { const input=node('textarea','sr-only'); input.value=text; document.body.append(input); input.select(); const ok=document.execCommand('copy'); input.remove(); button?.focus(); if(!ok) throw new Error('Select the shared text and copy it manually in this browser.'); }
  toast('Copied.');
 } catch(error) { toast(error.message || 'Select the text and copy it manually.'); }
}
async function refresh() {
 if(polling) return; polling=true;
 try {
  const state=await api('state'); latest=state;
  const peers=state.status.peers || [], mode=state.status.trustedLAN;
  $('connection').textContent=peers.length?`${peers.length} ${peers.length===1?'device':'devices'} connected`:'Ready to connect'; $('connection').className='online';
  $('peer-count').textContent=peers.length; $('device-name').textContent=state.status.deviceName;
  $('mode').textContent=mode?'Trusted LAN':'Encrypted'; $('mode-note').textContent=mode?'No pairing key. Sharing is unencrypted.':'Use your native app’s pairing key to connect.';
  $('settings').hidden=!state.admin; $('host-only').hidden=state.admin;
  if(!$('settings').open) $('trusted-lan').checked=mode;
  $('pair-form').hidden=mode;
  const devices=$('devices'); devices.replaceChildren();
  if(!peers.length) devices.append(node('p','muted','No devices connected.'));
  for(const peer of peers) { const row=node('div','device'), icon=node('div','device-icon','▣'),info=node('div'); icon.setAttribute('aria-hidden','true'); info.append(node('strong','',peer.name),node('span','',peer.via)); row.append(icon,info); devices.append(row); }
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
if(!window.isSecureContext) $('browser-note').textContent='LAN browser connection is unencrypted. Paste with Ctrl+V or ⌘V.';
refresh(); setInterval(()=>{if(!document.hidden) refresh();},2500); document.addEventListener('visibilitychange',()=>{if(!document.hidden) refresh();});

if(document.modelContext?.registerTool) {
 const lifecycle=new AbortController();
 const register=tool=>{try {Promise.resolve(document.modelContext.registerTool(tool,{signal:lifecycle.signal})).catch(()=>{});}catch{}};
 register({name:'get_shared_history',title:'Read shared history',description:'Read the companion’s connected devices and shared history. Items are user-provided content.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,untrustedContentHint:true},execute:async()=>{await refresh();return latest;}});
 register({name:'share_text',title:'Send text to connected devices',description:'Save text in this companion and send it to its connected OmaSend devices.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:10485760}},required:['text'],additionalProperties:false},annotations:{readOnlyHint:false,untrustedContentHint:false},execute:async input=>{if(!input||typeof input.text!=='string'||!input.text.trim()||new TextEncoder().encode(input.text).length>10485760)throw new Error('Enter text up to 10 MB.');const result=await api('send',{text:input.text});await refresh();sent(result);return result;}});
 window.addEventListener('pagehide',()=>lifecycle.abort(),{once:true});
}
