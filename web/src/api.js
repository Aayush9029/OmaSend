import {useCallback,useEffect,useRef,useState} from 'react';
export async function api(path,body){
 const options=body===undefined?{}:{method:'POST',headers:{'X-OmaSend':'1'},body};
 if(body!==undefined&&!(body instanceof FormData)){options.headers['Content-Type']='application/json';options.body=JSON.stringify(body);}
 const response=await fetch('/api/'+path,options);
 if(!response.ok)throw new Error((await response.text()).slice(0,250)||'Request failed');
 return response.json();
}
const empty={status:{peers:[],deviceName:'',trustedLAN:false},history:[],devices:[],admin:false,platform:''};
export function useCompanion(){
 const [state,setState]=useState(empty),[online,setOnline]=useState(false),inflight=useRef(false),mounted=useRef(true);
 const refresh=useCallback(async()=>{
  if(inflight.current)return;inflight.current=true;
  try{const data=await api('state');if(!mounted.current)return;
   setState(previous=>{
    if(JSON.stringify(previous)===JSON.stringify(data))return previous;
    return {...data,history:JSON.stringify(previous.history)===JSON.stringify(data.history)?previous.history:data.history,devices:JSON.stringify(previous.devices)===JSON.stringify(data.devices)?previous.devices:data.devices};
   });setOnline(true);
  }catch{if(mounted.current)setOnline(false);}finally{inflight.current=false;}
 },[]);
 useEffect(()=>{mounted.current=true;refresh();const timer=setInterval(()=>{if(!document.hidden)refresh();},3000);const visible=()=>{if(!document.hidden)refresh();};document.addEventListener('visibilitychange',visible);return()=>{mounted.current=false;clearInterval(timer);document.removeEventListener('visibilitychange',visible);};},[refresh]);
 return {state,online,refresh};
}
export async function copyText(text){
 if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(text);return;}
 const input=document.createElement('textarea');input.value=text;input.className='sr-only';document.body.append(input);input.select();const copied=document.execCommand('copy');input.remove();if(!copied)throw new Error('Select the text and copy it manually.');
}
export function sendNotice(result){return !result.peers?'Saved':result.sent===result.peers?'Sent':`Sent to ${result.sent} of ${result.peers} devices`;}
