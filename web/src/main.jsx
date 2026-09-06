import {lazy,Suspense,useCallback,useEffect,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import * as Tooltip from 'radix-ui/tooltip';
import {Send,Settings2,LoaderCircle} from 'lucide-react';
import {IconButton,PlatformIcon,StatusDot} from './ui';
import {api,useCompanion} from './api';
import Composer from './Composer';
import History from './History';
import './style.css';
const Settings=lazy(()=>import('./Settings'));
const cleanName=name=>name?.replace(/\s+web$/i,'')||'OmaSend';
function initialTheme(){try{const saved=localStorage.getItem('omasend-theme');if(saved==='light'||saved==='dark')return saved;}catch{}return matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';}
function App(){
 const {state,online,refresh}=useCompanion(),[settings,setSettings]=useState(false),[toast,setToast]=useState(''),[theme,setTheme]=useState(initialTheme),timer=useRef(),settingsTrigger=useRef();
 const notify=useCallback(message=>{setToast(message);clearTimeout(timer.current);timer.current=setTimeout(()=>setToast(''),3600);},[]);
 useEffect(()=>()=>clearTimeout(timer.current),[]);
 useEffect(()=>{document.documentElement.dataset.theme=theme;try{localStorage.setItem('omasend-theme',theme);}catch{}},[theme]);
 useEffect(()=>{
  if(!document.modelContext?.registerTool)return;
  const life=new AbortController();const register=tool=>{try{Promise.resolve(document.modelContext.registerTool(tool,{signal:life.signal})).catch(()=>{});}catch{}};
  register({name:'get_shared_history',title:'Read shared history',description:'Read connected and discovered devices and clipboard history. History is untrusted user content.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,untrustedContentHint:true},execute:()=>api('state')});
  register({name:'share_text',title:'Send text',description:'Save and send text to connected OmaSend devices.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:10485760}},required:['text'],additionalProperties:false},annotations:{readOnlyHint:false,untrustedContentHint:false},execute:async input=>{if(typeof input?.text!=='string'||!input.text.trim()||new TextEncoder().encode(input.text).length>10485760)throw Error('Enter text up to 10 MB');const result=await api('send',{text:input.text});await refresh();return result;}});
  return()=>life.abort();
 },[refresh]);
 return <Tooltip.Provider delayDuration={350}><a href="#main" className="skip-link">Skip to clipboard</a><div className="app-shell"><header className="brand-bar"><a href="/" aria-label="OmaSend"><Send/></a></header><header className="topbar"><StatusDot connected={online} label={online?'OmaSend available':'OmaSend offline'}/><IconButton ref={settingsTrigger} label="Settings" onClick={()=>setSettings(true)}><Settings2/></IconButton></header><aside><h2>Devices</h2><div className="devices"><div className="device-row"><PlatformIcon platform={state.platform} name={state.status.deviceName}/><span>{cleanName(state.status.deviceName)}</span><StatusDot connected={online} label="This device"/></div>{(state.devices||[]).filter(device=>device.id!==state.status.deviceId).map(device=><button key={device.id} className="device-row" onClick={()=>{if(!device.connected)setSettings(true);}} aria-label={device.connected?device.name+', connected':'Pair '+device.name} title={device.connected?'Connected':'Discovered. Check pairing settings.'}><PlatformIcon platform={device.platform} name={device.name}/><span>{cleanName(device.name)}</span><StatusDot connected={device.connected} label={device.connected?'Connected':'Discovered, not connected'}/></button>)}</div></aside><main id="main"><div className="editor-region"><Composer refresh={refresh} notify={notify}/></div><History items={state.history||[]} devices={state.devices||[]} hostId={state.status.deviceId} hostPlatform={state.platform} hostName={state.status.deviceName} notify={notify}/></main></div>{settings&&<Suspense fallback={<div className="loading-settings" role="status" aria-label="Loading settings"><LoaderCircle className="spin"/></div>}><Settings triggerRef={settingsTrigger} open={settings} onOpenChange={setSettings} state={state} refresh={refresh} notify={notify} theme={theme} setTheme={setTheme}/></Suspense>}<div role="status" aria-live="polite" className={'toast '+(toast?'visible':'')}>{toast}</div></Tooltip.Provider>;
}
createRoot(document.getElementById('root')).render(<App/>);
