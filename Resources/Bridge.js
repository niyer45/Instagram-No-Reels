/* Native bridge for the Instagram shell.
   Reports routes, readiness, theme, the signed-in avatar and Stories tray geometry
   through one message handler ("instagram") and hands every navigation that changes
   page to the native Router. Observes the page only; never reads credentials or cookies.
   Native -> page: window.__instagram.policy(json), .refresh(), .layout(values). */
(function () {
'use strict';
const HOSTS=['instagram.com','www.instagram.com'];
const BLOCKED=new Set(['reel','reels','tv','clips']);
const LOGIN_ROOTS=new Set(['challenge','checkpoint','two_factor','consent','oauth']);
const LOGIN_ACCOUNTS=new Set(['login','emailsignup','signup','password','onetap','logout','suspended','disabled']);
const OTHER_ROOTS=new Set(['about','legal','privacy','terms','developer','web','emails','session','press','api','graphql','ajax','static','_u']);
const PROFILE_TABS=new Set(['tagged','saved','feed']);
const EXPLORE_PAGES=new Set(['tags','locations','people']);
const FLOW_KINDS=new Set(['login','stories','create']);
const HANDLE=/^[a-z0-9._]{1,30}$/;
const SEARCH_STABLE_FRAMES=24,READY_STABLE_FRAMES=6,FALLBACK_MS={home:8000,default:4000},GIVE_UP_MS=25000;

function official(href){if(typeof href!=='string'||!href)return false;try{const u=new URL(href,'https://www.instagram.com');return u.protocol==='https:'&&!u.port&&!u.username&&!u.password&&HOSTS.includes(u.hostname);}catch(_){return false;}}
function normal(parts){return '/'+parts.join('/').toLowerCase()+'/';}
/** Classifies a path into a page kind and an identity (same table as Sources/Navigation/RouteClassifier.swift; both check Tests/route-fixtures.json). */
function classify(pathname){
 const parts=String(pathname||'/').split('/').filter(Boolean);
 if(!parts.length)return {kind:'home',identity:''};
 const first=parts[0].toLowerCase(),second=(parts[1]||'').toLowerCase();
 const other={kind:'other',identity:normal(parts)};
 if(BLOCKED.has(first))return {kind:'blocked',identity:''};
 // Hashtag, location, people and keyword-result pages are content pages of their own, not the Search tab.
 if(first==='explore')return EXPLORE_PAGES.has(second)||second==='search'&&(parts[2]||'').toLowerCase()==='keyword'?other:{kind:'search',identity:''};
 if(first==='stories')return {kind:'stories',identity:''};
 if(first==='create')return {kind:'create',identity:''};
 if(first==='direct'){if(second==='t'&&parts[2])return {kind:'thread',identity:parts[2]};if(!second||second==='inbox')return {kind:'inbox',identity:''};return other;}
 // /accounts/password/change/ is a signed-in settings page; /accounts/password/reset/ is login.
 if(first==='accounts'){if(LOGIN_ACCOUNTS.has(second)&&!(second==='password'&&(parts[2]||'').toLowerCase()==='change'))return {kind:'login',identity:''};if(second==='activity')return {kind:'activity',identity:''};return {kind:'settings',identity:normal(parts)};}
 if(LOGIN_ROOTS.has(first))return {kind:'login',identity:''};
 if(first==='notifications')return {kind:'activity',identity:''};
 if(first==='settings')return {kind:'settings',identity:normal(parts)};
 const offset=first==='p'?1:second==='p'&&HANDLE.test(first)?2:0;
 if(offset){
  const code=parts[offset];if(!code||!/^[\w-]{1,100}$/.test(code))return other;
  const rest=(parts[offset+1]||'').toLowerCase();
  if(!rest)return {kind:'post',identity:code};
  if(rest==='comments'||rest==='c')return {kind:'comments',identity:code};
  if(rest==='liked_by')return {kind:'likes',identity:code};
  return other;
 }
 if(OTHER_ROOTS.has(first)||!HANDLE.test(first))return other;
 if(parts.length===1)return {kind:'profile',identity:first};
 if(BLOCKED.has(second))return {kind:'blocked',identity:''};
 if(PROFILE_TABS.has(second)&&parts.length===2)return {kind:'profile',identity:first};
 return other;
}
/** Decides how a navigation from the current page is performed: stay (in page), native (Router), block, or pass (native policy decides). */
function decide(currentHref,targetHref,role='page'){
 let target;try{target=new URL(targetHref,currentHref);}catch(_){return 'pass';}
 if(!official(target.href))return 'pass';
 const t=classify(target.pathname);if(t.kind==='blocked')return 'block';
 // The tray never hands login redirects to native: they would replace the Home root (the tray shows itself).
 if(role==='tray')return t.kind==='stories'||t.kind==='home'?'stay':t.kind==='login'?'block':'native';
 let current;try{current=new URL(currentHref);}catch(_){return 'native';}
 const c=classify(current.pathname);
 if(c.kind!==t.kind)return 'native';
 if(FLOW_KINDS.has(c.kind))return 'stay';
 return c.identity===t.identity?'stay':'native';
}
/** Whether a page of this kind shows meaningful content, from a DOM probe. */
function readiness(kind,probe){
 if(probe.loginForm)return true;
 if(probe.complete&&probe.elapsed>=(FALLBACK_MS[kind]||FALLBACK_MS.default))return true;
 switch(kind){
  case 'home':return probe.approvedPosts>0||probe.caughtUp;
  case 'search':return probe.searchStable;
  case 'profile':return probe.profileHeader&&!probe.loading;
  case 'post':case 'comments':case 'likes':return (probe.articles>0||probe.mainMedia)&&!probe.loading;
  case 'login':return probe.complete;
  case 'stories':case 'create':return probe.mainMedia||probe.complete;
  default:return probe.mainContent&&!probe.loading;
 }
}
/** Stable key for a theme colour, or null for transparent / unparsable values. */
function opaqueRGB(value){const m=String(value||'').match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/);return m&&(!m[4]||Number(m[4])===1)?m.slice(1,4).map(Number):null;}
/** First opaque surface colour in a top-down list of nodes under a point. Before a node's own background, a child that
    covers the point (`isSurface`) with `pointer-events:none` is checked: elementsFromPoint skips such layers, and Meta's
    login page paints its grey surface with one. */
function surfaceRGB(nodes,styleOf,isSurface){
 const listed=new Set(nodes);
 for(const node of nodes){if(!node)continue;
  for(const child of Array.from(node.children||[]).slice(0,32)){
   if(listed.has(child)||!isSurface(child))continue;const css=styleOf(child);
   if(css.pointerEvents!=='none'||css.display==='none'||css.visibility==='hidden'||css.opacity==='0')continue;
   const rgb=opaqueRGB(css.backgroundColor);if(rgb)return rgb;}
  const rgb=opaqueRGB(styleOf(node).backgroundColor);if(rgb)return rgb;}
 return null;
}
/** SVG path data for a wordmark shape element (path, polygon, polyline or rect); null when unusable. */
function shapePath(tag,attr){
 tag=String(tag||'').toLowerCase();
 if(tag==='path')return attr('d')||null;
 if(tag==='polygon'||tag==='polyline'){const n=String(attr('points')||'').trim().split(/[\s,]+/).map(Number);if(n.length<4||n.length%2||n.some(x=>!Number.isFinite(x)))return null;
  let d='M'+n[0]+' '+n[1];for(let i=2;i<n.length;i+=2)d+='L'+n[i]+' '+n[i+1];return tag==='polygon'?d+'Z':d;}
 if(tag==='rect'){const [x,y,w,h]=['x','y','width','height'].map(k=>Number(attr(k)||0));if(!(w>0&&h>0)||![x,y].every(Number.isFinite))return null;return 'M'+x+' '+y+'H'+(x+w)+'V'+(y+h)+'H'+x+'Z';}
 return null;
}
/** Avatar URLs must be Instagram CDN images. */
function avatarURL(src){try{const u=new URL(src);return u.protocol==='https:'&&/(^|\.)(cdninstagram\.com|fbcdn\.net)$/.test(u.hostname)?u.href:null;}catch(_){return null;}}
if(typeof module!=='undefined'&&module.exports){module.exports={classify,decide,readiness,official,opaqueRGB,surfaceRGB,avatarURL,shapePath};return;}
if(window.top!==window||!official(location.href))return;

const boot=window.__instagramBoot||{};const role=boot.role==='tray'?'tray':'page';
const started=typeof performance!=='undefined'&&performance.now?performance.now():Date.now();
function now(){return typeof performance!=='undefined'&&performance.now?performance.now():Date.now();}
function post(type,payload){try{window.webkit.messageHandlers.instagram.postMessage(Object.assign({},payload||{},{type}));}catch(_){}}
const listeners={policy:[],refresh:[]};let policy=boot.policy||null;
let layout={headerHeight:boot.headerHeight||0,storiesHeight:boot.storiesHeight||0,hideChrome:!!boot.hideChrome};
function applyLayout(){const root=document.documentElement;if(!root)return false;
 root.style.setProperty('--native-header-height',(Number(layout.headerHeight)||0)+'px');
 root.style.setProperty('--native-stories-height',(Number(layout.storiesHeight)||0)+'px');
 if(root.getAttribute('data-native-chrome')!==(layout.hideChrome?'hidden':'web'))root.setAttribute('data-native-chrome',layout.hideChrome?'hidden':'web');
 if(root.getAttribute('data-native-role')!==role)root.setAttribute('data-native-role',role);return true;}
window.__instagram=Object.freeze({
 policy(value){let p=value;if(typeof p==='string'){try{p=JSON.parse(p);}catch(_){return;}}if(!p||typeof p!=='object')return;policy=p;for(const f of listeners.policy){try{f(p);}catch(_){}}},
 refresh(){for(const f of listeners.refresh){try{f();}catch(_){}}},
 layout(values){if(values&&typeof values==='object'){for(const k of ['headerHeight','storiesHeight'])if(Number.isFinite(values[k]))layout[k]=Math.max(0,Math.min(400,values[k]));if(typeof values.hideChrome==='boolean')layout.hideChrome=values.hideChrome;}applyLayout();},
 on(name,f){if(listeners[name]&&typeof f==='function')listeners[name].push(f);},
 post,
 get currentPolicy(){return policy;}
});
applyLayout();

// Routes: report every document and history change; hand page changes to native.
let lastRoute='',webTitle='';
function postRoute(){const title=(webTitle||String(document.title||'').replace(/(^|\s*[•|]\s*)Instagram.*$/,'')).trim().slice(0,80);
 const key=location.pathname+'\n'+location.search+'\n'+title;if(key===lastRoute)return;lastRoute=key;post('route',{path:location.pathname,search:location.search,title});}
function intercept(url){const decision=decide(location.href,url,role);
 if(decision==='native'){try{post('navigate',{url:new URL(url,location.href).href});}catch(_){}return true;}
 return decision==='block';}
// Instagram's router can render the next page in place around a history change that is cancelled here. The route
// content (main, its first child, header and first article) is compared with the state at the user's last touch (or at
// the cancel); if it changed, a popstate for the unchanged location makes Instagram's router render this page again.
let touchSignature=null,touchAt=-1e9;
function routeSignature(){const main=document.querySelector('main');return main?[main,main.firstElementChild,main.querySelector('header'),main.querySelector('article')]:[null];}
function sameSignature(a,b){return a.length===b.length&&a.every((node,i)=>node===b[i]);}
function restoreAfterCancel(){
 const baseline=touchSignature&&now()-touchAt<2000?touchSignature:routeSignature();const state=history.state;
 const frame=f=>typeof requestAnimationFrame==='function'?requestAnimationFrame(f):setTimeout(f,16);
 frame(()=>frame(()=>{if(sameSignature(baseline,routeSignature()))return;let event;
  try{event=new PopStateEvent('popstate',{state});}catch(_){try{event=new Event('popstate');}catch(_){return;}}
  try{window.dispatchEvent(event);}catch(_){}}));}
for(const name of ['pushState','replaceState']){const original=history[name];history[name]=function(...args){
 if(args[2]!=null&&intercept(args[2])){restoreAfterCancel();return;}const result=original.apply(this,args);afterRouteChange();return result;};}
window.addEventListener('popstate',afterRouteChange);
for(const type of ['pointerdown','touchstart'])window.addEventListener(type,()=>{touchSignature=routeSignature();touchAt=now();},{capture:true,passive:true});
// Links are decided in the window's capturing phase, before any Instagram handler (React listens on its root) can route.
window.addEventListener('click',event=>{
 if(event.defaultPrevented||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
 const link=event.target&&event.target.closest?event.target.closest('a[href]'):null;if(!link)return;
 const href=link.getAttribute('href');if(!href||href.startsWith('#')||/^javascript:/i.test(href))return;
 if(intercept(link.href||href)){event.preventDefault();event.stopImmediatePropagation();}
},true);
function afterRouteChange(){postRoute();if(role==='tray')updateViewer();}

// Readiness: per-kind probes held for a few frames; a fallback reveals settled pages.
let readySent=false,readyFrames=0,searchControl=null,searchKey='',searchFrames=0,frameQueued=false;
function visible(node){if(!node||!node.getBoundingClientRect)return false;const r=node.getBoundingClientRect();if(!(r.width>0&&r.height>0))return false;if(typeof getComputedStyle!=='function')return true;const css=getComputedStyle(node);return css.display!=='none'&&css.visibility!=='hidden'&&css.opacity!=='0';}
function probeSearch(complete){
 const control=document.querySelector('input[placeholder*="Search" i],input[aria-label*="Search" i],input[type="search"],[role="combobox"]');
 const ok=complete&&visible(control);const r=ok?control.getBoundingClientRect():null;
 const key=ok?[r.top,r.left,r.width,r.height].map(Math.round).join(','):'';
 searchFrames=ok&&control===searchControl&&key===searchKey?searchFrames+1:0;searchControl=control;searchKey=key;
 return searchFrames>=SEARCH_STABLE_FRAMES;
}
function probe(kind){
 const main=document.querySelector('main');const complete=document.readyState==='complete';
 const loading=!!main&&[...main.querySelectorAll('[role="progressbar"],[data-visualcompletion="loading-state"],svg[aria-label^="Loading"]')].some(visible);
 const mainMedia=!!main&&!!main.querySelector('img,video');
 return {complete,elapsed:now()-started,loading,mainMedia,
  loginForm:!!document.querySelector('input[type="password"],input[name="username"]')||loggedOutLanding(),
  approvedPosts:kind==='home'?document.querySelectorAll('[data-following-approved="yes"]').length:0,
  caughtUp:!!document.querySelector('[data-instagram-caught-up]'),
  articles:main?main.querySelectorAll('article').length:0,
  profileHeader:!!document.querySelector('main header img,main header h1,main header h2'),
  mainContent:!!main&&(mainMedia||(main.textContent||'').trim().length>0),
  searchStable:kind==='search'?probeSearch(complete):false};
}
// Instagram's logged-out landing: placeholder /u/ tab links, a "Log in" button, or a login link without posts.
function loggedOutLanding(){
 if(document.querySelector('a[href="/u/profile/"],a[href="/u/direct/"]'))return true;
 if(document.querySelector('a[href^="/accounts/login"],a[href^="https://www.instagram.com/accounts/login"]')&&!document.querySelector('article'))return true;
 return [...document.querySelectorAll('button,[role="button"]')].some(b=>/^log in$/i.test((b.textContent||'').trim())&&!(b.closest&&b.closest('[role="menu"],[role="dialog"]')));
}
function checkReady(){
 frameQueued=false;if(readySent||role!=='page')return;
 const kind=classify(location.pathname).kind;
 const state=probe(kind);
 if(readiness(kind,state))readyFrames++;else readyFrames=0;
 // Login content reports kind "login" whatever the route, so native hides page chrome over it.
 if(readyFrames>=READY_STABLE_FRAMES||(kind==='search'&&readyFrames>0)){readySent=true;postTheme();post('ready',{kind:state.loginForm&&kind!=='settings'?'login':kind});
  // Stylesheets can restyle the page after first paint without DOM mutations; re-sample the surface.
  for(const delay of [300,1000,2500])setTimeout(postTheme,delay);return;}
 if(now()-started<GIVE_UP_MS)queueFrame();
}
function queueFrame(){if(frameQueued)return;frameQueued=true;if(typeof requestAnimationFrame==='function')requestAnimationFrame(checkReady);else setTimeout(checkReady,16);}

// Theme: mirror the page background to native surfaces. Sampling (elementsFromPoint plus computed styles) is
// throttled: on readiness and its delayed re-samples, at once on the first DOM change after a route change, and
// otherwise on DOM changes at most once per THEME_INTERVAL_MS after the page is ready (the skeleton covers it before).
const THEME_INTERVAL_MS=500;
let lastTheme='',themeAt=-Infinity,themeQueued=false,themeRoute='';
function routeKey(){return location.pathname+location.search;}
function postTheme(){if(typeof getComputedStyle!=='function')return;themeAt=now();themeRoute=routeKey();
 // The visible full-width surface at the top of the viewport (it meets the native status bar), then body/html.
 // elementsFromPoint returns the whole stack, including fixed background layers that are not ancestors.
 const width=window.innerWidth||0;
 const stack=typeof document.elementsFromPoint==='function'?document.elementsFromPoint(width/2,2):[];
 const nodes=stack.filter(node=>{const r=node.getBoundingClientRect?node.getBoundingClientRect():null;return r&&r.width>=width*0.9;}).slice(0,16);
 const covers=node=>{const r=node.getBoundingClientRect?node.getBoundingClientRect():null;return !!r&&r.width>=width*0.9&&r.top<=2&&r.bottom>2;};
 const rgb=surfaceRGB([...nodes,document.body,document.documentElement],node=>getComputedStyle(node),covers);
 if(rgb){const key=rgb.join(',');if(key!==lastTheme){lastTheme=key;post('theme',{backgroundRGB:rgb});}}}
function requestTheme(){
 if(!readySent)return;
 if(routeKey()!==themeRoute){postTheme();return;}
 if(themeQueued)return;
 const wait=themeAt+THEME_INTERVAL_MS-now();
 if(wait<=0){postTheme();return;}
 themeQueued=true;setTimeout(()=>{themeQueued=false;postTheme();},wait);
}

// Web chrome: mark Instagram's tab bar, top bar and app banners so NativeSkin.css hides them.
function pathOf(a){try{const u=new URL(a.getAttribute('href'),location.href);return official(u.href)?u.pathname:null;}catch(_){return null;}}
function findTabBar(){
 const marked=document.querySelector('[data-native-hidden="tabbar"]');if(marked)return marked;
 const height=window.innerHeight||0;
 for(const seed of document.querySelectorAll('a[href="/explore/"],a[href="https://www.instagram.com/explore/"]')){
  // The outermost bar-sized wrapper, so the bar's own border and background go too.
  let best=null,node=seed.parentElement;
  for(let depth=0;node&&depth<8&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article'))break;
   const r=node.getBoundingClientRect();
   if(!(r.height>0&&r.height<130&&r.top>height*0.6))continue;
   if([...node.querySelectorAll('a[href]')].map(pathOf).includes('/'))best=node;
  }
  if(best)return best;
 }
 return null;
}
function findTopBar(){
 const marked=document.querySelector('[data-native-hidden="header"]');if(marked)return marked;
 const width=window.innerWidth||0;
 for(const seed of document.querySelectorAll('svg[aria-label="Instagram"],svg[aria-label="Back"],[aria-label="Back"]')){
  let best=null,node=seed.parentElement;
  for(let depth=0;node&&depth<8&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article,input,textarea,[role="combobox"],a[href^="/stories/"]'))break;
   const r=node.getBoundingClientRect();
   if(r.top<=2&&r.width>=width*0.9&&r.height>=30&&r.height<=90)best=node;
  }
  if(best)return best;
 }
 return null;
}
function findBanners(){
 const found=[];
 for(const control of document.querySelectorAll('a,button,[role="button"]')){
  if(!/^(open( in)? (the )?app|use the app|get the app|open instagram)$/i.test((control.textContent||'').trim()))continue;
  let node=control;
  for(let depth=0;node&&depth<6&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article,input[type="password"]'))break;
   const position=typeof getComputedStyle==='function'?getComputedStyle(node).position:'';
   if(position==='fixed'||position==='sticky'){found.push(node);break;}
  }
 }
 return found;
}
let lastAvatar='';
function scanChrome(){
 const kind=classify(location.pathname).kind;
 const tabBar=findTabBar();
 if(tabBar){
  if(tabBar.getAttribute('data-native-hidden')!=='tabbar')tabBar.setAttribute('data-native-hidden','tabbar');
  for(const link of tabBar.querySelectorAll('a[href]')){
   const path=pathOf(link);const route=path?classify(path):null;const image=link.querySelector('img');
   if(route&&route.kind==='profile'&&image){const url=avatarURL(image.currentSrc||image.src);const key=url?route.identity+' '+url:'';
    if(url&&key!==lastAvatar){lastAvatar=key;post('avatar',{url,username:route.identity});}break;}
  }
 }
 if(layout.hideChrome&&!FLOW_KINDS.has(kind)){
  const header=findTopBar();
  if(header){if(header.getAttribute('data-native-hidden')!=='header')header.setAttribute('data-native-hidden','header');
   const heading=header.querySelector('h1,h2,[role="heading"]');const text=(heading&&heading.textContent||'').trim();
   if(text&&text.length<=80&&text!==webTitle){webTitle=text;postRoute();}}
 }
 for(const banner of findBanners())if(!banner.hasAttribute('data-native-hidden'))banner.setAttribute('data-native-hidden','banner');
}

// Stories tray role: show only the tray, report its size and the story viewer state.
let trayStyle=null,lastViewer=null,lastTray='',lastWordmark='';const confirmed=new WeakSet();
function updateViewer(){
 const open=location.pathname.startsWith('/stories/');if(trayStyle)trayStyle.disabled=open;
 if(open!==lastViewer){lastViewer=open;post('storyViewer',{open});}
 if(!open)return;
 for(const dialog of document.querySelectorAll('[role="dialog"]')){
  if(confirmed.has(dialog)||!/view.*story.*signed.in|signed.in.*view.*story/i.test(dialog.textContent||''))continue;
  const button=[...dialog.querySelectorAll('button,[role="button"]')].find(b=>/^(view story|view|continue)$/i.test((b.textContent||'').trim()));
  if(button){confirmed.add(dialog);button.click();}
 }
}
function scanTray(){
 if(!document.documentElement)return;
 updateViewer();if(lastViewer)return;
 if(!trayStyle){trayStyle=document.createElement('style');trayStyle.textContent='body{visibility:hidden!important;overflow:hidden!important}[data-native-story-tray]{visibility:visible!important;position:fixed!important;top:0!important;left:0!important;width:100%!important;z-index:2147483647!important}';}
 if(!trayStyle.parentNode)document.documentElement.appendChild(trayStyle);
 const items=[...document.querySelectorAll('a[href^="/stories/"],button[aria-label*="story" i],[role="button"][aria-label*="story" i]')];
 let tray=null;const width=window.innerWidth||0;
 for(const item of items){let node=item;for(let depth=0;node&&depth<7;depth++,node=node.parentElement){
  const r=node.getBoundingClientRect();
  if(r.height>=40&&r.height<=190&&r.width>=width*0.6&&!node.querySelector('article,a[href*="/p/"],svg[aria-label="Instagram"]'))tray=node;}}
 if(tray){
  for(const old of document.querySelectorAll('[data-native-story-tray]'))if(old!==tray)old.removeAttribute('data-native-story-tray');
  if(!tray.hasAttribute('data-native-story-tray'))tray.setAttribute('data-native-story-tray','');
  const key=Math.ceil(tray.getBoundingClientRect().height)+','+items.length;
  if(key!==lastTray){lastTray=key;post('storiesTray',{height:Math.ceil(tray.getBoundingClientRect().height),items:items.length});}
 }
 const wordmark=document.querySelector('svg[aria-label="Instagram"]');
 if(wordmark){const paths=[...wordmark.querySelectorAll('path,polygon,polyline,rect')].slice(0,12).map(p=>({d:shapePath(p.tagName,k=>p.getAttribute(k))||'',evenOdd:(p.getAttribute('fill-rule')||p.getAttribute('clip-rule'))==='evenodd'})).filter(p=>p.d&&p.d.length<=20000);
  const viewBox=wordmark.getAttribute('viewBox')||'';const key=viewBox+paths.length+(paths[0]?paths[0].d.length:0);
  if(paths.length&&viewBox&&key!==lastWordmark){lastWordmark=key;post('wordmark',{viewBox,paths});}}
}

let chromeQueued=false;
function onMutation(){
 if(role==='tray'){scanTray();return;}
 queueFrame();
 if(!chromeQueued){chromeQueued=true;const run=()=>{chromeQueued=false;applyLayout();scanChrome();requestTheme();postRoute();};
  if(typeof requestAnimationFrame==='function')requestAnimationFrame(run);else setTimeout(run,16);}
}
new MutationObserver(onMutation).observe(document,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',onMutation);
window.addEventListener('load',onMutation);
postRoute();onMutation();
})();
