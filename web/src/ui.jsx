import {forwardRef} from 'react';
import * as Tooltip from 'radix-ui/tooltip';
import {Monitor} from 'lucide-react';
import apple from './logos/apple.svg?raw';
import windows from './logos/windows11.svg?raw';
import arch from './logos/archlinux.svg?raw';
import linux from './logos/linux.svg?raw';
const marks={darwin:apple,windows,arch,linux};
export function platformFor(platform='',name=''){
 if(platform==='darwin'||platform==='macos')return 'darwin';
 if(platform==='windows')return 'windows';
 if(/arch|omarchy/i.test(name))return 'arch';
 if(platform==='linux')return 'linux';
 if(/macbook|mac mini|mac studio|imac|macos/i.test(name))return 'darwin';
 if(/winbloat|windows|desktop-/i.test(name))return 'windows';
 if(/linux|ubuntu|fedora/i.test(name))return 'linux';
 return '';
}
export function PlatformIcon({platform,name,className=''}){
 const kind=platformFor(platform,name),source=marks[kind];
 if(!source)return <Monitor className={'platform-icon '+className} aria-hidden="true"/>;
 const path=source.match(/<path d="([^"]+)"/)[1];
 return <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={`platform-icon ${kind==='windows'?'windows-mark':''} ${className}`}><path d={path}/></svg>;
}
export const IconButton=forwardRef(function IconButton({label,shortcut,children,className='',...props},ref){return <Tooltip.Root><Tooltip.Trigger asChild><button ref={ref} type="button" aria-label={label} className={'icon-button '+className} {...props}>{children}</button></Tooltip.Trigger><Tooltip.Portal><Tooltip.Content className="tooltip" sideOffset={7}>{label}{shortcut&&<kbd className="shortcut-key">{shortcut}</kbd>}</Tooltip.Content></Tooltip.Portal></Tooltip.Root>;});
export function StatusDot({connected,label}){return <span className={'status-dot '+(connected?'connected':'pending')} role="img" aria-label={label} title={label}/>;}
