import {memo,useEffect,useRef,useState} from 'react';
import {Paperclip,Clipboard,ArrowUp,Check,LoaderCircle,Download} from 'lucide-react';
import {IconButton} from './ui';
import {api,sendNotice} from './api';
export default memo(function Composer({refresh,notify}){
 const [text,setText]=useState(''),[busy,setBusy]=useState(false),[sent,setSent]=useState(false),[drag,setDrag]=useState(false);const input=useRef(null),editor=useRef(null),locked=useRef(false),depth=useRef(0),timer=useRef();
 useEffect(()=>()=>clearTimeout(timer.current),[]);
 async function run(action){if(locked.current)return;locked.current=true;setBusy(true);try{const result=await action();notify(sendNotice(result));setSent(true);clearTimeout(timer.current);timer.current=setTimeout(()=>setSent(false),1500);}catch(e){notify(e.message);}finally{locked.current=false;setBusy(false);refresh();}}
 function send(event){event?.preventDefault();if(!text.trim())return editor.current?.focus();const value=text;run(async()=>{const result=await api('send',{text:value});setText(current=>current===value?'':current);return result;});}
 function upload(file){if(!file)return;if(!file.size||file.size>100*1024*1024)return notify('Choose a file between 1 byte and 100 MB.');run(()=>{const data=new FormData();data.append('file',file);return api('upload',data);});if(input.current)input.current.value='';}
 async function paste(){try{if(!navigator.clipboard?.readText||!window.isSecureContext)throw Error();const value=await navigator.clipboard.readText();setText(current=>current+value);editor.current.focus();}catch{notify('Paste with Ctrl+V or ⌘V');editor.current.focus();}}
 return <form className="composer" onSubmit={send} onDragEnter={e=>{if(e.dataTransfer.types.includes('Files')){e.preventDefault();depth.current++;setDrag(true);}}} onDragOver={e=>{if(e.dataTransfer.types.includes('Files'))e.preventDefault();}} onDragLeave={()=>{depth.current--;if(depth.current<=0)setDrag(false);}} onDrop={e=>{e.preventDefault();depth.current=0;setDrag(false);if(e.dataTransfer.files.length!==1)notify('Drop one file at a time');else upload(e.dataTransfer.files[0]);}}>
 <textarea ref={editor} aria-label="Text to share"  value={text} onChange={e=>setText(e.target.value)} maxLength={10485760} onKeyDown={e=>{if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)){e.preventDefault();send();}}}/>
 <div className="flex items-center justify-between composer-toolbar"><div className="flex items-center gap-2"><IconButton label="Attach file" shortcut="U" data-hotkey="u" disabled={busy} onClick={()=>input.current.click()}><Paperclip/></IconButton><IconButton label="Paste" shortcut="P" data-hotkey="p" onClick={paste}><Clipboard/></IconButton><input ref={input} type="file" hidden onChange={e=>upload(e.target.files[0])}/></div><IconButton label={sent?'Sent':'Send'} shortcut="Ctrl / ⌘ Enter" type="submit" className="send-button" disabled={busy||!text.trim()}>{busy?<LoaderCircle className="spin"/>:sent?<Check className="confirm"/>:<ArrowUp/>}</IconButton></div>
 {drag&&<div className="drop-overlay"><Download aria-label="Drop file"/></div>}
 </form>;
});
