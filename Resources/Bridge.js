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
/** Route words that may appear in a link shape; every other path segment is reduced to a placeholder. */
const ROUTE_VOCAB=new Set(['p','reel','reels','tv','stories','highlights','direct','t','inbox','new','requests','explore','tags','locations','people','search','keyword','accounts','activity','edit','login','onetap','emailsignup','signup','password','change','reset','privacy_and_security','settings','notifications','tagged','saved','followers','following','liked_by','comments','c','audio','about','legal','privacy','terms','web','lite','create','style','details','challenge','your_activity','interactions','u','_u','profile','two_factor','checkpoint','story','select']);
const VARIANT_VALUES=new Set(['following','home','past_posts','favorites']);
/** Reduces a link to its shape (DEBUG outline): route words kept, handles, codes, ids and query values replaced. Never returns user content. */
function hrefShape(href){
 if(typeof href!=='string')return null;const raw=href.trim();if(!raw)return null;
 if(raw[0]==='#')return '#';
 const scheme=raw.match(/^([a-z][a-z0-9+.-]*):/i);
 if(scheme){const s=scheme[1].toLowerCase();if(s==='javascript')return '<script>';if(s!=='http'&&s!=='https')return '<scheme>';}
 let u;try{u=new URL(raw,'https://www.instagram.com/');}catch(_){return '<external>';}
 if(!official(u.href))return '<external>';
 const parts=u.pathname.split('/').filter(Boolean),out=[];
 parts.forEach((seg,i)=>{const s=seg.toLowerCase(),prev=i?parts[i-1].toLowerCase():'';
  out.push(i===0?(ROUTE_VOCAB.has(s)?s:'<user>'):prev==='p'||prev==='reel'||prev==='tv'?'<code>':prev==='stories'&&s!=='highlights'&&s!=='create'?'<user>':prev==='tags'?'<tag>':/^\d+$/.test(s)?'<id>':ROUTE_VOCAB.has(s)?s:'<x>');});
 const query=[];u.searchParams.forEach((v,k)=>query.push(k+'='+(k==='variant'&&VARIANT_VALUES.has(v)?v:'<v>')));
 return '/'+(out.length?out.join('/')+'/':'')+(query.length?'?'+query.join('&'):'');
}
const SAFE_LABELS=new Set(['Back','Home','Search','Explore','Reels','Messenger','Messages','Direct','Notifications','Activity Feed','New post','Create','Instagram','Close','Loading','Options','More','More options','Settings','Like','Unlike','Comment','Share','Share Post','Save','Remove','Down chevron icon','Chevron','Following','For you','Favorites','Stories','Carousel','Next','Previous','Go back','Play','Pause','Audio','Tags','Verified','Sponsored','Add to story','Add to your story','Add post to your story','Your story','Copy link','Share to...','Send','Cancel']);
/** An aria-label if it is a known fixed UI label, else `<other>` (labels often carry usernames); null when absent. */
function safeLabel(label){if(label==null||label==='')return null;return SAFE_LABELS.has(label)?label:'<other>';}
const OUTLINE_SKIP=new Set(['script','style','link','meta','noscript','template']);
const OUTLINE_UI=new Set(['Following','For you','Favorites','Add to story','Add to your story','Add post to your story','Your story','Copy link','Share to...','Share','Send','Cancel','Close','Post','Reels']);
const OUTLINE_DATA=['data-native-','data-following-','data-instagram-'];
/** Structure-only outline of a DOM tree (DEBUG diagnostics): tags, roles, allowlisted labels, our own data-* names,
    positions, rects and link shapes. Reads no other attribute and outputs no text. `env.indexes` (a Map) receives node -> index. */
function outlineTree(body,env){
 const {styleOf,rectOf,maxNodes=400,maxDepth=12,indexes}=env,nodes=[];let truncated=false;
 const kinds=new Map();
 function kindOf(node){if(kinds.has(node))return kinds.get(node);const tag=String(node.tagName||'').toLowerCase();let k=tag==='img'?1:tag==='video'?2:tag==='article'?4:0;
  for(const c of Array.from(node.children||[]))k|=kindOf(c);kinds.set(node,k);return k;}
 function visit(node,depth){
  const tag=String(node.tagName||'').toLowerCase();if(OUTLINE_SKIP.has(tag))return;
  if(nodes.length>=maxNodes){truncated=true;return;}
  const children=Array.from(node.children||[]),css=styleOf(node)||{},e={i:nodes.length,d:depth,tag};
  const role=node.getAttribute('role');if(role)e.role=String(role).slice(0,24);
  const aria=safeLabel(node.getAttribute('aria-label'));if(aria!==null)e.aria=aria;
  const data=Array.from(node.getAttributeNames?node.getAttributeNames():[]).filter(n=>OUTLINE_DATA.some(p=>n.startsWith(p)));if(data.length)e.data=data;
  const hidden=node.getAttribute('data-native-hidden');if(hidden)e.hidden=hidden;
  e.pos=css.position;if(css.position==='fixed'||css.position==='sticky'){e.top=css.top;e.z=css.zIndex;}
  if(css.display==='none'||css.visibility==='hidden'||css.opacity==='0')e.vis=0;
  if(css.opacity!==undefined&&css.opacity!=='1')e.opacity=css.opacity;
  const r=rectOf(node)||{};e.rect=[r.x,r.y,r.width,r.height].map(v=>Math.round(Number(v)||0));
  const k=kindOf(node),has=(k&1?'i':'')+(k&2?'v':'')+(k&4?'a':'');if(has)e.has=has;
  e.n=children.length;
  if(tag==='a')e.href=hrefShape(node.getAttribute('href'));
  if(!children.length){const t=node.textContent;if(typeof t==='string'&&t.length<=40){const s=t.trim();if(s.length<=24&&OUTLINE_UI.has(s))e.ui=s;}}
  if(indexes)indexes.set(node,e.i);
  nodes.push(e);
  if(tag==='svg'||depth>=maxDepth)return;
  for(const c of children){if(truncated)return;visit(c,depth+1);}
 }
 if(body)visit(body,0);
 return {nodes,truncated};
}
/** Marked elements of the outline (null when absent). `indexOf(node)` gives the outline index or -1. */
function outlineMarks(doc,indexOf,env){
 const sel={topBar:'[data-native-hidden="header"]',bottomNav:'[data-native-hidden="tabbar"]',headerSpacer:'[data-native-header-spacer]',storiesSlot:'[data-instagram-stories-slot]',followingBar:'[data-native-hidden="following-bar"]',storiesRow:'[data-native-stories-row]'},marks={};
 for(const k of Object.keys(sel)){const node=doc.querySelector(sel[k]);if(!node){marks[k]=null;continue;}
  const css=env.styleOf(node)||{},r=env.rectOf(node)||{};
  marks[k]={i:indexOf(node),tag:String(node.tagName||'').toLowerCase(),pos:css.position,rect:[r.x,r.y,r.width,r.height].map(v=>Math.round(Number(v)||0))};}
 return marks;
}
/** Extra DEBUG outline sections: `main` (outline rooted at <main>) and `bars` (nav/header/navigation and fixed/sticky elements, small subtrees).
    `bodyTree`/`bodyIndexes` come from the body outline made with the same env. Same sanitizer, so no text, no raw URLs. */
function outlineSections(doc,env,bodyTree,bodyIndexes){
 const mainNode=doc.querySelector('main'),mainIndexes=new Map();
 const mainTree=mainNode?outlineTree(mainNode,{...env,indexes:mainIndexes,maxNodes:400,maxDepth:12}):null;
 const picked=new Map(),add=(node,kind)=>{if(picked.size<12&&!picked.has(node))picked.set(node,kind);};
 for(const node of doc.querySelectorAll('nav,header,[role="navigation"]')){
  if(node.closest&&node.closest('article'))continue;
  add(node,String(node.tagName||'').toLowerCase()==='header'?'header':'nav');
 }
 const fromOutline=(tree,indexes)=>{if(!tree||!indexes)return;
  for(const [node,i] of indexes){const e=tree.nodes[i];if(e&&(e.pos==='fixed'||e.pos==='sticky'))add(node,e.pos);}};
 fromOutline(bodyTree,bodyIndexes);fromOutline(mainTree,mainIndexes);
 const bars=[];
 for(const [node,kind] of picked){
  const css=env.styleOf(node)||{},r=env.rectOf(node)||{},hidden=node.getAttribute('data-native-hidden');
  bars.push({kind,rect:[r.x,r.y,r.width,r.height].map(v=>Math.round(Number(v)||0)),pos:css.position,hidden:hidden||null,
   nodes:outlineTree(node,{...env,indexes:undefined,maxNodes:60,maxDepth:6}).nodes});
 }
 // The Search field box (marked by tabScanSearch): a deeper subtree so every label, input, overlay and button in it is visible.
 const fieldNode=doc.querySelector('[data-native-search-field]');
 let searchField=null;
 if(fieldNode){const r=env.rectOf(fieldNode)||{};
  searchField={rect:[r.x,r.y,r.width,r.height].map(v=>Math.round(Number(v)||0)),nodes:outlineTree(fieldNode,{...env,indexes:undefined,maxNodes:80,maxDepth:6}).nodes};}
 // The topmost dialog (DEBUG `dialog-open` capture): share sheet, story composer, menus. Structure only, same sanitizer.
 let dialog=null;
 const dialogs=Array.from(doc.querySelectorAll('[role="dialog"]')),dialogNode=dialogs.length?dialogs[dialogs.length-1]:null;
 if(dialogNode){const r=env.rectOf(dialogNode)||{};dialog={count:dialogs.length,rect:[r.x,r.y,r.width,r.height].map(v=>Math.round(Number(v)||0)),nodes:outlineTree(dialogNode,{...env,indexes:undefined,maxNodes:120,maxDepth:8}).nodes};}
 return {main:mainTree,bars,searchField,dialog};
}
if(typeof module!=='undefined'&&module.exports){module.exports={classify,decide,readiness,official,opaqueRGB,surfaceRGB,avatarURL,shapePath,hrefShape,safeLabel,outlineTree,outlineMarks,outlineSections};return;}
if(window.top!==window||!official(location.href))return;

const boot=window.__instagramBoot||{};const role=boot.role==='tray'?'tray':'page';
const started=typeof performance!=='undefined'&&performance.now?performance.now():Date.now();
function now(){return typeof performance!=='undefined'&&performance.now?performance.now():Date.now();}
function post(type,payload){try{window.webkit.messageHandlers.instagram.postMessage(Object.assign({},payload||{},{type}));}catch(_){}}
const listeners={policy:[],refresh:[]};let policy=boot.policy||null;
let layout={headerHeight:boot.headerHeight||0,storiesHeight:boot.storiesHeight||0,hideChrome:!!boot.hideChrome,refreshing:!!boot.refreshing};
// Refresh: native sets `refreshing` while a reload is held behind a snapshot, so the reloading document stays invisible
// (NativeSkin.css). If native never clears it, the document reveals itself after REFRESH_FAILSAFE_MS.
const REFRESH_FAILSAFE_MS=25000;let refreshTimer=null;
function armRefreshFailsafe(){if(refreshTimer!==null||!layout.refreshing)return;refreshTimer=setTimeout(()=>{refreshTimer=null;layout.refreshing=false;applyLayout();},REFRESH_FAILSAFE_MS);}
function setAttr(root,name,value){if(value===null){if(root.getAttribute(name)!==null&&root.removeAttribute)root.removeAttribute(name);}else if(root.getAttribute(name)!==value)root.setAttribute(name,value);}
function applyLayout(){const root=document.documentElement;if(!root)return false;
 root.style.setProperty('--native-header-height',(Number(layout.headerHeight)||0)+'px');
 root.style.setProperty('--native-stories-height',(Number(layout.storiesHeight)||0)+'px');
 if(root.getAttribute('data-native-chrome')!==(layout.hideChrome?'hidden':'web'))root.setAttribute('data-native-chrome',layout.hideChrome?'hidden':'web');
 if(root.getAttribute('data-native-role')!==role)root.setAttribute('data-native-role',role);
 setAttr(root,'data-native-refreshing',layout.refreshing?'':null);
 if(!layout.refreshing&&refreshTimer!==null){clearTimeout(refreshTimer);refreshTimer=null;}
 if(role==='page')setAttr(root,'data-native-stories',boot.storiesSlot===true&&Number(layout.storiesHeight)>0?'tray':null);
 return true;}
window.__instagram=Object.freeze({
 policy(value){let p=value;if(typeof p==='string'){try{p=JSON.parse(p);}catch(_){return;}}if(!p||typeof p!=='object')return;policy=p;for(const f of listeners.policy){try{f(p);}catch(_){}}},
 refresh(){for(const f of listeners.refresh){try{f();}catch(_){}}},
 layout(values){if(values&&typeof values==='object'){for(const k of ['headerHeight','storiesHeight'])if(Number.isFinite(values[k]))layout[k]=Math.max(0,Math.min(400,values[k]));if(typeof values.hideChrome==='boolean')layout.hideChrome=values.hideChrome;if(typeof values.refreshing==='boolean'){layout.refreshing=values.refreshing;armRefreshFailsafe();}}applyLayout();},
 on(name,f){if(listeners[name]&&typeof f==='function')listeners[name].push(f);},
 /** DEBUG diagnostics: sanitized structure of the page (see outlineTree); null in the tray. */
 outline(){if(role!=='page')return null;
  try{const root=document.documentElement,css=getComputedStyle.bind(window),env={styleOf:n=>css(n),rectOf:n=>n.getBoundingClientRect(),indexes:new Map()};
   const tree=outlineTree(document.body,env),sections=outlineSections(document,env,tree,env.indexes),prop=k=>root.style.getPropertyValue(k),q=hrefShape('/'+location.search)||'';
   return {route:{kind:classify(location.pathname).kind,search:q.includes('?')?q.slice(q.indexOf('?')):''},viewport:{w:window.innerWidth,h:window.innerHeight},scroll:{x:Math.round(window.scrollX),y:Math.round(window.scrollY)},documentHeight:Math.round(root.scrollHeight),
    layout:{headerHeight:prop('--native-header-height'),storiesHeight:prop('--native-stories-height'),chrome:root.getAttribute('data-native-chrome'),page:root.getAttribute('data-native-page'),stories:root.getAttribute('data-native-stories'),refreshing:root.getAttribute('data-native-refreshing')!==null},
    marks:outlineMarks(document,n=>env.indexes.has(n)?env.indexes.get(n):-1,env),outline:tree.nodes,truncated:tree.truncated,main:sections.main,bars:sections.bars,searchField:sections.searchField,dialog:sections.dialog};
  }catch(_){return {error:'exception'};}},
 post,
 /** Reports a dropped navigation for the DEBUG `nav-blocked` capture (FeedFilter calls it too). */
 blocked(url,decision){reportBlocked(url,decision);},
 get currentPolicy(){return policy;}
});
applyLayout();armRefreshFailsafe();

// Routes: report every document and history change; hand page changes to native.
let lastRoute='',webTitle='';
function postRoute(){const title=(webTitle||String(document.title||'').replace(/(^|\s*[•|]\s*)Instagram.*$/,'')).trim().slice(0,80);
 const key=location.pathname+'\n'+location.search+'\n'+title;if(key===lastRoute)return;lastRoute=key;post('route',{path:location.pathname,search:location.search,title});}
// DEBUG `nav-blocked` capture trigger only (native ignores it in release): a navigation was dropped on a Home or post page.
// Sends the link's shape (route words kept; handles, codes, ids and query values replaced) and an enumerated decision, never the URL.
const BLOCK_DECISIONS=new Set(['bridge-block','feed-pushstate','reels-button']);
function reportBlocked(url,decision){
 if(role!=='page'||!BLOCK_DECISIONS.has(decision))return;
 const kind=classify(location.pathname).kind;if(kind!=='home'&&kind!=='post')return;
 let shape='<none>';try{if(url)shape=hrefShape(new URL(String(url),location.href).href)||'<none>';}catch(_){}
 post('navBlocked',{shape,decision});
}
function intercept(url){const decision=decide(location.href,url,role);
 if(decision==='native'){try{post('navigate',{url:new URL(url,location.href).href});}catch(_){}return true;}
 if(decision==='block')reportBlocked(url,'bridge-block');
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
  approvedPosts:kind==='home'?homeFeedShown():0,
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
/** Whether a node sits inside a dialog (share sheet, story composer, menu): the page's own chrome never lives there, so a dialog's
    full-width header (Back / title) or link must not be taken for the top bar or tab bar and hidden. */
function inDialog(node){return !!(node&&node.closest&&node.closest('[role="dialog"],[aria-modal="true"]'));}
function findTabBar(){
 const marked=document.querySelector('[data-native-hidden="tabbar"]');if(marked)return marked;
 const height=window.innerHeight||0;
 for(const seed of document.querySelectorAll('a[href="/explore/"],a[href="https://www.instagram.com/explore/"]')){
  if(inDialog(seed))continue;
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
  if(inDialog(seed))continue;
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

// Following-feed web bar (Home only): the variant's top bar has no wordmark or Back icon, so findTopBar misses it. It shows
// when the native header collapses (scroll) and in the pull-to-refresh gap. Seeds on the "Following" label, then on
// whatever fixed/sticky full-width bar sits at the viewport top. Marked "following-bar" (not "header", which would stop
// findTopBar from finding the wordmark header). Selector notes: docs/DOM-NOTES.md.
const BAR_STOP='main,article,[role="combobox"],a[href^="/stories/"],a[href^="https://www.instagram.com/stories/"],[data-following-approved],[data-instagram-stories-slot],img,video';
const BAR_SKIP='article,[data-following-approved],[role="dialog"],[role="menu"],[data-native-hidden]';
let followingBar=null,lastBarSearch=-Infinity,lastBarProbe=-Infinity,barTimer=0;
// A subtree blocks the Following-bar match when it holds a stop element or a RENDERED text field (hidden / zero-size inputs,
// e.g. the display:none forms inside the observed bar, do not block).
function barBlocked(node){
 if(node.querySelector(BAR_STOP))return true;
 for(const el of node.querySelectorAll('input,textarea')){
  const type=String(el.getAttribute('type')||'').toLowerCase();
  if(el.tagName.toLowerCase()==='input'&&(type==='hidden'||type==='file'||type==='checkbox'||type==='radio'))continue;
  const r=el.getBoundingClientRect();if(!(r.width>0&&r.height>0))continue;
  const cs=getComputedStyle(el);if(cs.display==='none'||cs.visibility==='hidden')continue;
  return true;
 }
 return false;
}
function isHome(){return classify(location.pathname).kind==='home';}
function barScrollY(){return Number(window.scrollY)||Number(window.pageYOffset)||0;}
function barQualifies(node,fixedOnly){
 if(!node||node===document.body||node===document.documentElement||node.hasAttribute('data-native-hidden')||node.hasAttribute('data-native-story-tray'))return false;
 const r=node.getBoundingClientRect(),width=window.innerWidth||0,limit=(Number(layout.headerHeight)||0)+64;
 if(!(r.width>=width*0.9&&r.height>=30&&r.height<=90))return false;
 const viewportTop=r.top>=-2&&r.top<=limit,documentTop=r.top+barScrollY()>=-2&&r.top+barScrollY()<=limit;
 if(fixedOnly){if(!viewportTop)return false;const p=getComputedStyle(node).position;if(p!=='fixed'&&p!=='sticky')return false;}
 else if(!viewportTop&&!documentTop)return false;
 return true;
}
function markFollowingBar(node){
 const r=node.getBoundingClientRect();
 node.setAttribute('data-native-bar-height',String(Math.round(r.height)));
 node.setAttribute('data-native-hidden','following-bar');
 followingBar=node;return node;
}
function findFollowingBarByPoint(){
 if(typeof document.elementsFromPoint!=='function')return null;
 const width=window.innerWidth||0;
 for(const y of [2,20]){
  let stack;try{stack=document.elementsFromPoint(width/2,y)||[];}catch(_){stack=[];}
  for(const el of stack){
   let node=el;
   for(let depth=0;node&&depth<8&&node!==document.body&&node!==document.documentElement;depth++,node=node.parentElement){
    if(barBlocked(node))break;
    if(barQualifies(node,true))return node;
   }
  }
 }
 return null;
}
const NAV_SEL='nav,[role="navigation"]';
function navPrecedesMain(nav){
 for(let sib=nav.nextElementSibling;sib;sib=sib.nextElementSibling){if(String(sib.tagName).toLowerCase()==='main'||sib.querySelector('main'))return true;}
 return false;
}
function navOk(nav){return !nav.closest(BAR_SKIP)&&!barBlocked(nav)&&navPrecedesMain(nav)&&barQualifies(nav,false);}
// The in-flow nav placeholder (45 px) that wraps the fixed bar must be the marked node, else it stays as a blank strip.
function upgradeToNav(node){
 if(!node||String(node.tagName).toLowerCase()==='nav')return node;
 let nav=node.parentElement;
 for(let depth=0;nav&&depth<8&&nav!==document.body&&nav!==document.documentElement;depth++,nav=nav.parentElement){
  if(nav.matches(NAV_SEL)&&navOk(nav)){
   node.removeAttribute('data-native-hidden');node.removeAttribute('data-native-bar-height');
   return markFollowingBar(nav);
  }
 }
 return node;
}
function findFollowingBar(){
 if(!layout.hideChrome||typeof getComputedStyle!=='function')return null;
 if(followingBar&&followingBar.isConnected&&followingBar.getAttribute('data-native-hidden')==='following-bar')return followingBar=upgradeToNav(followingBar);
 followingBar=null;
 const marked=document.querySelector('[data-native-hidden="following-bar"]');if(marked){followingBar=upgradeToNav(marked);return followingBar;}
 // Structural nav seed first: an in-flow nav above the feed (observed: section > nav 402x45 before main, wrapping the fixed bar).
 for(const nav of document.querySelectorAll(NAV_SEL)){
  if(navOk(nav))return markFollowingBar(nav);
 }
 const seeds=[];
 for(const el of document.querySelectorAll('span,h1,h2,p,div,[aria-label="Following"]')){
  if(el.getAttribute('aria-label')==='Following'){seeds.push(el);continue;}
  if(el.children&&el.children.length===0&&(el.textContent||'').trim()==='Following')seeds.push(el);
 }
 for(const seed of seeds){
  if(seed.closest(BAR_SKIP))continue;
  let best=null,node=seed;
  for(let depth=0;node&&depth<=8&&node!==document.body&&node!==document.documentElement;depth++,node=node.parentElement){
   if(barBlocked(node))break;
   if(barQualifies(node,false))best=node;
  }
  if(best)return markFollowingBar(upgradeToNav(best));
 }
 const byPoint=findFollowingBarByPoint();
 return byPoint?markFollowingBar(upgradeToNav(byPoint)):null;
}
function scanFollowingBar(){
 if(!layout.hideChrome||!isHome())return;
 if(followingBar&&followingBar.isConnected&&followingBar.getAttribute('data-native-hidden')==='following-bar'){followingBar=upgradeToNav(followingBar);return;}
 const t=now();
 if(t>lastBarSearch&&t-lastBarSearch<300){
  if(!barTimer)barTimer=setTimeout(()=>{barTimer=0;scanFollowingBar();},Math.max(0,300-(t-lastBarSearch))+1);
  return;
 }
 lastBarSearch=t;
 findFollowingBar();
}
function probeFollowingBar(){
 if(!layout.hideChrome||!isHome()||(followingBar&&followingBar.isConnected))return;
 const t=now();if(t>lastBarProbe&&t-lastBarProbe<100)return;lastBarProbe=t;
 const node=findFollowingBarByPoint();if(node)markFollowingBar(node);
}

// Instagram's own stories row inside the feed document (Home page role): marked so NativeSkin.css hides it while the native
// tray is active (html[data-native-stories="tray"]). Items are story links/buttons outside cards; the row is the outermost
// ancestor (<= 7 up) that is 40-190 px tall, wide, holds >= 2 items and no post, card, slot or main. Selector notes: docs/DOM-NOTES.md.
const STORY_ITEMS='a[href^="/stories/"],a[href^="https://www.instagram.com/stories/"],button[aria-label*="story" i],[role="button"][aria-label*="story" i]';
const STORY_ITEM_SKIP='article,[data-following-approved],[data-native-hidden],[role="dialog"],[role="menu"],[aria-modal="true"]';
// A share sheet or composer that is not marked as a dialog still floats: items under a fixed-position ancestor are never the feed's row.
function inFixedOverlay(item){
 if(typeof getComputedStyle!=='function')return false;
 let node=item.parentElement;
 for(let depth=0;node&&depth<12&&node!==document.body&&node!==document.documentElement;depth++,node=node.parentElement)if(getComputedStyle(node).position==='fixed')return true;
 return false;
}
const STORY_ROW_EXCLUDE='article,a[href*="/p/"],[data-following-approved],[data-instagram-stories-slot],main';
function scanStoriesRow(){
 if(role!=='page'||!isHome())return;
 for(const old of document.querySelectorAll('[data-native-stories-row]'))
  if(!old.isConnected||old.querySelector(STORY_ROW_EXCLUDE))old.removeAttribute('data-native-stories-row');
 if(document.querySelector('[data-native-stories-row]'))return;
 const items=[...document.querySelectorAll(STORY_ITEMS)].filter(i=>!i.closest(STORY_ITEM_SKIP)&&!inFixedOverlay(i));
 if(items.length<2)return;
 const width=window.innerWidth||0,found=[];
 for(const item of items){
  let best=null,node=item.parentElement;
  for(let depth=0;node&&depth<7&&node!==document.body&&node!==document.documentElement;depth++,node=node.parentElement){
   const r=node.getBoundingClientRect();
   if(r.height>=40&&r.height<=190&&r.width>=width*0.6&&items.filter(i=>node.contains(i)).length>=2&&!node.querySelector(STORY_ROW_EXCLUDE))best=node;
  }
  if(best&&!found.includes(best))found.push(best);
 }
 for(const row of found)if(!found.some(o=>o!==row&&o.contains(row)))row.setAttribute('data-native-stories-row','');
}
// DEBUG `dialog-open` capture trigger only (native ignores it in release): a [role="dialog"] appeared on a Home or post page
// (share sheet, story composer, menus). At most one message per 2 s; a dialog skipped by the throttle is picked up by a later scan.
const DIALOG_THROTTLE_MS=2000;
let lastDialogPost=-Infinity;const seenDialogs=new WeakSet();
function scanDialogs(){
 if(role!=='page')return;
 const kind=classify(location.pathname).kind;if(kind!=='home'&&kind!=='post')return;
 for(const dialog of document.querySelectorAll('[role="dialog"]')){
  if(seenDialogs.has(dialog))continue;
  const t=now();if(t-lastDialogPost<DIALOG_THROTTLE_MS)return;
  seenDialogs.add(dialog);lastDialogPost=t;post('dialogOpen');return;
 }
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
  scanFollowingBar();
 }
 for(const banner of findBanners())if(!banner.hasAttribute('data-native-hidden'))banner.setAttribute('data-native-hidden','banner');
 scanStoriesRow();
 scanDialogs();
}

/** Instagram's top bar is position:fixed and the element right after it reserves the bar's height with padding-top
    (60 px seen on profiles), so hiding the bar alone leaves a blank strip. That sibling is marked and the skin zeroes
    its padding while the bar stays hidden, also once the page turns out to be logged-out content and web chrome is
    shown again. Only 30–120 px paddings count, so ordinary content spacing is left alone. Runs after scanTabs, which
    hides the own-profile top bar, so that bar's spacer collapses in the same pass. */
function markHeaderSpacers(){
 if(typeof getComputedStyle!=='function')return;
 for(const hidden of document.querySelectorAll('[data-native-hidden="header"]')){
  const spacer=hidden.nextElementSibling;
  if(!spacer||spacer.hasAttribute('data-native-header-spacer')||getComputedStyle(hidden).position!=='fixed')continue;
  const padding=parseFloat(getComputedStyle(spacer).paddingTop)||0;
  if(padding>=30&&padding<=120)spacer.setAttribute('data-native-header-spacer','');
 }
 for(const bar of document.querySelectorAll('[data-native-hidden="following-bar"]')){
  const position=getComputedStyle(bar).position,fixed=position==='fixed';
  const spacer=bar.nextElementSibling;
  if(fixed&&spacer&&!spacer.hasAttribute('data-native-header-spacer')){
   const padding=parseFloat(getComputedStyle(spacer).paddingTop)||0;
   if(padding>=30&&padding<=120)spacer.setAttribute('data-native-header-spacer','');
  }
  if(!fixed&&position!=='sticky')continue;
  const height=Number(bar.getAttribute('data-native-bar-height'))||0;if(!height)continue;
  for(const sibling of [bar.nextElementSibling,bar.previousElementSibling]){
   if(!sibling||sibling.hasAttribute('data-native-hidden')||sibling.hasAttribute('data-native-header-spacer'))continue;
   if(sibling.children&&sibling.children.length)continue;
   if((sibling.textContent||'').trim())continue;
   if(Math.abs(sibling.getBoundingClientRect().height-height)<=2)sibling.setAttribute('data-native-hidden','following-spacer');
  }
 }
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

// --- Home ---
/** Home readiness: the number of approved posts that are laid out, or 0 while the first post
    card in the feed (the top of Home) is still unresolved, since FeedFilter keeps unresolved
    cards' space but hides them and revealing then would show a blank feed top. Cards FeedFilter
    collapsed (not approved, not pending) are skipped. */
function homeFeedShown(){
 const cards=[...document.querySelectorAll('[data-following-approved]')].filter(c=>!(c.getAttribute('data-following-approved')==='no'&&c.getAttribute('data-following-pending')==='no'));
 if(!cards.length||cards[0].getAttribute('data-following-approved')!=='yes')return 0;
 return cards.filter(c=>{if(c.getAttribute('data-following-approved')!=='yes')return false;const r=c.getBoundingClientRect?c.getBoundingClientRect():null;return !!r&&r.height>0;}).length;
}
/** Closes Instagram's story viewer in the tray web view with its own Close control, else
    history.back(). Native calls it for the downward and edge swipes. Returns what it did. */
function closeStoryViewer(){
 if(!location.pathname.startsWith('/stories/'))return 'closed';
 const icon=document.querySelector('svg[aria-label="Close"]');
 const control=icon&&icon.closest?icon.closest('button,[role="button"],a[href]'):null;
 if(control&&typeof control.click==='function'){control.click();return 'clicked';}
 history.back();return 'back';
}
if(role==='tray')window.__instagramTray=Object.freeze({closeViewer:closeStoryViewer});
// --- end Home ---

// --- Tabs ---
// Search, Notifications and Profile (Phase 2C). Marks Instagram's DOM with data-native-* attributes that
// NativeSkin.css styles (sections Search / Notifications / Profile), adds the native-style Search Cancel
// control, hides app-install prompts, and gives native window.__instagramTabs (switchAccount, unread,
// cancelSearch, hasSearchField). Structural selectors only; each one and its fallback is in docs/DOM-NOTES.md.
const TAB_SEARCH='input[placeholder*="Search" i],input[aria-label*="Search" i],input[type="search"]';
const TAB_APP_TEXT=/see (the )?full (profile|post|photo|video|reel)s? in the app|use the app to see more|get the full experience|(open|continue|view) (this )?in (the )?(instagram )?app|(use|get|download) the (instagram )?app/i;
const TAB_APP_CONTROL=/^(open instagram|open( in)? (the )?app|use the app|get the app|download( the)? app|switch to the app)$/i;
const TAB_PROFILE_BUTTON=/^(edit profile|share profile|follow|follow back|following|requested|message|contact|email|call|view archive|ad tools|professional dashboard|subscribe)$/i;
const TAB_FOLLOW_PRIMARY=/^(follow|follow back)$/i;
const TAB_COUNT=/^[\d.,]+\s*[kmb]?\s+(posts?|followers?|following)$/i;
const TAB_TOP_BAR_SEED=/^(settings|options|new post|new|create|discover people|threads|switch accounts?|down chevron icon|chevron)$/i;
function tabSet(node,name,value=''){if(node&&node.getAttribute&&node.getAttribute(name)!==value)node.setAttribute(name,value);}
function tabUnset(node,name){if(node&&node.hasAttribute&&node.hasAttribute(name))node.removeAttribute(name);}
function tabText(node){return String(node&&node.textContent||'').replace(/\s+/g,' ').trim();}
function tabRect(node){return node&&node.getBoundingClientRect?node.getBoundingClientRect():{top:0,left:0,width:0,height:0,bottom:0};}
function tabPosition(node){return typeof getComputedStyle==='function'?getComputedStyle(node).position:'';}
/** The profile handle a link opens (`/alice/` -> alice), or null. */
function tabHandle(link){const href=link&&link.getAttribute&&link.getAttribute('href');if(!href)return null;
 try{const u=new URL(href,'https://www.instagram.com');if(!HOSTS.includes(u.hostname))return null;const parts=u.pathname.split('/').filter(Boolean);const r=classify(u.pathname);return r.kind==='profile'&&parts.length===1?r.identity:null;}catch(_){return null;}}
/** Scales an avatar block to `target` px with CSS zoom (keeps Instagram's nested fixed-size wrappers and story ring in proportion). */
function tabZoom(wrapper,img,target){
 let base=Number(wrapper.getAttribute('data-native-zoom-base'));
 if(!(base>0)){const w=tabRect(img).width;if(!(w>0))return;base=Math.round(w*10)/10;wrapper.setAttribute('data-native-zoom-base',String(base));}
 if(Math.abs(target-base)<1)return;const zoom=(target/base).toFixed(4);
 if(wrapper.style&&wrapper.style.zoom!==zoom)wrapper.style.zoom=zoom;}
/** The outermost ancestor of an image (≤ 4 levels, below `stop`) no larger than 1.4× it: the avatar block with its ring. */
function tabAvatarBlock(img,stop){const size=tabRect(img).width;let block=null,node=img.parentElement;
 for(let depth=0;node&&depth<4&&node!==stop;depth++,node=node.parentElement){const r=tabRect(node);if(size>0&&r.width<=size*1.4&&r.height<=size*1.4)block=node;else break;}
 return block;}
function tabPageKind(){const kind=classify(location.pathname).kind;const root=document.documentElement;if(root&&root.getAttribute('data-native-page')!==kind)root.setAttribute('data-native-page',kind);return kind;}

// Search: native field skin, Cancel (appears on focus or text; clears and blurs), result rows.
let tabSearchInput=null;
function tabSearchActive(){const input=tabSearchInput;
 const active=!!input&&input.isConnected!==false&&(document.activeElement===input||!!String(input.value||'').trim());
 const root=document.documentElement;
 if(active)tabSet(root,'data-native-search-active','yes');else tabUnset(root,'data-native-search-active');
 return active;}
function tabSetValue(input,value){
 // React tracks the instance's value; the prototype setter plus an input event updates its state.
 const proto=Object.getPrototypeOf(input);const descriptor=proto&&Object.getOwnPropertyDescriptor(proto,'value');
 if(descriptor&&descriptor.set)descriptor.set.call(input,value);else input.value=value;
 try{input.dispatchEvent(new Event('input',{bubbles:true}));}catch(_){}}
function tabCancelSearch(event){
 if(event){event.preventDefault();event.stopPropagation();}
 const input=tabSearchInput;
 if(input){if(String(input.value||''))tabSetValue(input,'');if(input.blur)input.blur();}
 const own=document.querySelector('[data-native-hidden="search-cancel"]');if(own&&own.click)own.click();
 tabSearchActive();}
function tabScanSearch(){
 const input=document.querySelector(TAB_SEARCH);tabSearchInput=input||null;
 if(!input){tabSearchActive();return;}
 tabSet(input,'data-native-search-input');
 // The rounded field: the outermost ancestor (≤ 5 levels) 28–52 px tall, narrower than the viewport, holding only this input.
 const width=window.innerWidth||0;let field=null,node=input.parentElement;
 for(let depth=0;node&&depth<5&&node!==document.body;depth++,node=node.parentElement){
  if(node.querySelectorAll('input,textarea').length!==1)break;
  const r=tabRect(node);if(r.height>=28&&r.height<=52&&r.width<=width-16)field=node;
 }
 let cancel=null;
 if(field){
  tabSet(field,'data-native-search-field');
  // Instagram can draw its own "Search" label over the field as well as the input placeholder: one label only.
  // The placeholder stays (ours to guarantee); the overlay text is marked and hidden by the skin.
  let overlay=false;
  for(const node of field.querySelectorAll('span,div,label')){
   if(node===input||node.querySelector('*')||tabText(node).toLowerCase()!=='search')continue;
   tabSet(node,'data-native-search-label');overlay=true;
  }
  if(overlay&&!input.getAttribute('placeholder'))input.setAttribute('placeholder','Search');
  const row=field.parentElement;
  if(row&&row!==document.body&&!row.querySelector('main,article')){
   tabSet(row,'data-native-search-row');
   for(const child of Array.from(row.children||[]))if(child.hasAttribute&&child.hasAttribute('data-native-search-cancel'))cancel=child;
   if(!cancel){cancel=document.createElement('button');cancel.type='button';cancel.textContent='Cancel';cancel.setAttribute('data-native-search-cancel','');
    cancel.addEventListener('click',tabCancelSearch);row.insertBefore(cancel,field.nextSibling);}
  }
 }
 // Instagram's own Cancel near the top is replaced by ours (ours clicks it, so its state resets too).
 if(cancel)for(const control of document.querySelectorAll('button,[role="button"]')){
  if(control===cancel||!/^cancel$/i.test(tabText(control)))continue;
  if(control.getAttribute('data-native-hidden')!=='search-cancel'&&tabRect(control).top>160)continue;
  tabSet(control,'data-native-hidden','search-cancel');
 }
 // Result rows: profile links with a picture; the text equal to the handle is the username, the next text the full name.
 for(const link of document.querySelectorAll('a[href]')){
  const handle=tabHandle(link);const img=handle&&link.querySelector('img');if(!img||link.contains(input)||link.closest('[data-native-hidden]'))continue;
  tabSet(link,'data-native-search-result');
  const avatar=tabAvatarBlock(img,link);if(avatar){tabSet(avatar,'data-native-search-avatar');tabZoom(avatar,img,44);}
  let named=false;
  for(const text of link.querySelectorAll('span,div')){
   if(text.querySelector('span,div,img'))continue;const value=tabText(text);if(!value)continue;
   if(!named&&value.toLowerCase()===handle){tabSet(text,'data-native-search-username');named=true;}
   else if(named){tabSet(text,'data-native-search-secondary');break;}
  }
 }
 tabSearchActive();
}
if(role==='page'){
 for(const type of ['focusin','focusout','input'])document.addEventListener(type,()=>{if(tabSearchInput)setTimeout(tabSearchActive,0);},true);
 // DEBUG outline capture trigger only (native ignores it in release): the search field gained focus.
 document.addEventListener('focusin',event=>{if(tabSearchInput&&event&&event.target===tabSearchInput)post('searchFocus');},true);
 // Dragging the results dismisses the keyboard, like native Search (the query and Cancel stay).
 let touchY=null;
 document.addEventListener('touchstart',event=>{touchY=event.touches&&event.touches[0]?event.touches[0].clientY:null;},{passive:true,capture:true});
 document.addEventListener('touchmove',event=>{const input=tabSearchInput;
  if(touchY==null||!input||document.activeElement!==input||!event.touches||!event.touches[0])return;
  if(Math.abs(event.touches[0].clientY-touchY)>10&&!(event.target&&event.target.closest&&event.target.closest('[data-native-search-row]'))){touchY=null;if(input.blur)input.blur();}
 },{passive:true,capture:true});
}

// Notifications: activity rows (avatar, username, time, trailing thumbnail or Follow button).
function tabScanActivity(){
 const main=document.querySelector('main')||document.body;if(!main)return;const width=window.innerWidth||0;
 for(const link of main.querySelectorAll('a[href]')){
  if(link.hasAttribute('data-native-activity-avatar'))continue;
  const img=link.querySelector('img');if(!img||!tabHandle(link)||link.closest('[data-native-hidden]'))continue;
  // The row: the nearest full-width ancestor 40–150 px tall.
  let row=null,node=link.parentElement;
  for(let depth=0;node&&depth<7&&node!==main;depth++,node=node.parentElement){
   if(node.querySelector('article'))break;const r=tabRect(node);
   if(r.width>=width*0.85&&r.height>=40&&r.height<=150){row=node;break;}
  }
  if(!row)continue;
  tabSet(row,'data-native-activity-row');tabSet(link,'data-native-activity-avatar');tabZoom(link,img,44);
  for(const other of row.querySelectorAll('a[href]')){if(other===link)continue;
   if(/\/(p|reel)\//.test(other.getAttribute('href')||'')&&other.querySelector('img'))tabSet(other,'data-native-activity-thumb');
   else if(tabHandle(other)&&!other.querySelector('img'))tabSet(other,'data-native-activity-user');}
  for(const button of row.querySelectorAll('button,[role="button"]')){const text=tabText(button);
   if(TAB_PROFILE_BUTTON.test(text)&&!(button.parentElement&&button.parentElement.closest('[data-native-follow-button]')))tabSet(button,'data-native-follow-button',TAB_FOLLOW_PRIMARY.test(text)?'primary':'secondary');}
 }
}
/** Instagram's unread-activity indicator on its notifications link (hidden web header): a label or a red dot. */
function tabUnread(){
 for(const link of document.querySelectorAll('a[href*="/accounts/activity"],a[href^="/notifications"],a[href^="https://www.instagram.com/notifications"]')){
  const labels=[link,...link.querySelectorAll('[aria-label]')].map(n=>n.getAttribute('aria-label')||'').join(' ')+' '+tabText(link);
  if(/\b(unread|new notifications?|\d+\s+notifications?)\b/i.test(labels))return true;
  if(typeof getComputedStyle==='function')for(const node of Array.from(link.querySelectorAll('div,span')).slice(0,40)){
   const rgb=opaqueRGB(getComputedStyle(node).backgroundColor);if(rgb&&rgb[0]>=200&&rgb[1]<=90&&rgb[2]<=110)return true;}
 }
 return false;
}

// Profile (own and other profiles alike, by page kind): header, buttons, counts, tab strip without Reels, grid.
let tabSwitcher=null;
function tabScanProfile(){
 let header=null;
 for(const candidate of document.querySelectorAll('header'))if(candidate.querySelector('img[alt*="profile picture" i]')&&candidate.querySelector('h1,h2')){header=candidate;break;}
 if(header){
  tabSet(header,'data-native-profile-header');
  const img=header.querySelector('img[alt*="profile picture" i]');const avatar=tabAvatarBlock(img,header);
  if(avatar){tabSet(avatar,'data-native-profile-avatar');tabZoom(avatar,img,90);}
  const scope=header.parentElement||header;
  for(const control of scope.querySelectorAll('button,a,[role="button"]')){const text=tabText(control);
   if(text.length>30||!TAB_PROFILE_BUTTON.test(text)||control.closest('[role="dialog"],[role="tablist"]'))continue;
   if(control.parentElement&&control.parentElement.closest('[data-native-profile-button]'))continue;
   tabSet(control,'data-native-profile-button',TAB_FOLLOW_PRIMARY.test(text)?'primary':'secondary');}
  for(const node of header.querySelectorAll('a,li,span')){
   if(!TAB_COUNT.test(tabText(node)))continue;
   if(Array.from(node.children||[]).some(child=>TAB_COUNT.test(tabText(child))))continue;
   tabSet(node,'data-native-profile-count');}
 }
 for(const list of document.querySelectorAll('[role="tablist"]')){
  const tabs=Array.from(list.querySelectorAll('a,[role="tab"]'));if(tabs.length<2||tabs.length>6)continue;
  tabSet(list,'data-native-profile-tabs');
  for(const tab of tabs){
   const reels=!!tab.querySelector('svg[aria-label="Reels"]')||/\/reels\/?(\?|$)/.test(tab.getAttribute('href')||'')||/^reels$/i.test(tab.getAttribute('aria-label')||tabText(tab));
   const slot=tab.parentElement&&tab.parentElement!==list&&tab.parentElement.children.length===1?tab.parentElement:tab;
   if(reels)tabSet(slot,'data-native-hidden','reels-tab');else{tabSet(slot,'data-native-profile-tab',tab.getAttribute('aria-selected')==='true'?'selected':'');}
  }
 }
 for(const tile of document.querySelectorAll('a[href]')){
  if(tile.hasAttribute('data-native-grid-tile'))continue;
  const href=tile.getAttribute('href')||'';if(!/\/(p|reel)\/|applink\.instagram\.com/.test(href)||!tile.querySelector('img'))continue;
  if(tile.closest('header,[role="dialog"],[data-native-hidden]'))continue;
  const cell=tile.parentElement,row=cell&&cell.parentElement;if(!row)continue;
  const cells=Array.from(row.children||[]).filter(child=>child.querySelector&&child.querySelector('a[href] img'));if(cells.length<2||cells.length>4)continue;
  tabSet(tile,'data-native-grid-tile');tabSet(cell,'data-native-grid-cell');tabSet(row,'data-native-grid-row');tabSet(row.parentElement,'data-native-grid');
  // The aspect box: a padding-based ratio element inside the tile (set to 3:4 portrait by the skin).
  for(const box of tile.querySelectorAll('div')){const css=typeof getComputedStyle==='function'?getComputedStyle(box):null;
   if(css&&/%$|[1-9]/.test(css.paddingBottom||'')&&parseFloat(css.height)===0){tabSet(box,'data-native-grid-ratio');break;}
   if(/padding-bottom:\s*[\d.]+%/.test(box.getAttribute('style')||'')){tabSet(box,'data-native-grid-ratio');break;}}
 }
}
/** Own-profile web top bar (settings, New post, username switcher): hidden like other web headers; remembers the switcher. */
function tabScanProfileTopBar(){
 if(!layout.hideChrome)return;const width=window.innerWidth||0;
 for(const seed of document.querySelectorAll('svg[aria-label]')){
  if(!TAB_TOP_BAR_SEED.test(seed.getAttribute('aria-label')||''))continue;
  if(seed.closest('[data-native-profile-header],[role="dialog"],main header'))continue;
  let best=null,node=seed.parentElement;
  for(let depth=0;node&&depth<8&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article,input,[role="tablist"],img[alt*="profile picture" i],[data-native-profile-header]'))break;
   const r=tabRect(node);if(r.top<=2&&r.width>=width*0.9&&r.height>=30&&r.height<=90)best=node;
  }
  if(best){tabSet(best,'data-native-hidden','header');break;}
 }
 const bar=document.querySelector('[data-native-hidden="header"]');tabSwitcher=null;
 if(bar)for(const control of bar.querySelectorAll('button,a,[role="button"]')){
  if(control.querySelector('svg[aria-label*="chevron" i],svg[aria-label*="switch account" i]')||/switch account/i.test(control.getAttribute('aria-label')||'')){tabSwitcher=control;break;}}
}

// App-install prompts: the logged-out "See full profile in the app" dialog and the sign-up footer.
// Dialogs with inputs, forms or long text are never touched (login challenges, confirmations).
function tabIsAppPrompt(dialog){
 if(dialog.querySelector('input,textarea,select,form,[contenteditable]'))return false;
 const text=tabText(dialog);if(text.length>400||!TAB_APP_TEXT.test(text))return false;
 if(dialog.querySelector('a[href*="applink.instagram.com"],a[href*="apps.apple.com"],a[href^="itms"]'))return true;
 return Array.from(dialog.querySelectorAll('a,button,[role="button"],[role="link"]')).some(control=>TAB_APP_CONTROL.test(tabText(control)));
}
function tabScanPrompts(){
 for(const dialog of document.querySelectorAll('[role="dialog"]')){
  if(dialog.closest('[data-native-hidden]')||!tabIsAppPrompt(dialog))continue;
  // The dialog's overlay layer: the outermost fixed or tabindex=-1 ancestor that is not page content.
  let overlay=dialog,node=dialog.parentElement;
  for(let depth=0;node&&depth<6&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article,[role="tablist"],header'))break;
   if(tabPosition(node)==='fixed'||node.getAttribute('tabindex')==='-1')overlay=node;
  }
  tabSet(overlay,'data-native-hidden','app-dialog');tabSet(document.documentElement,'data-native-app-dialog','hidden');
 }
 for(const link of document.querySelectorAll('a[href^="/accounts/signup"],a[href^="https://www.instagram.com/accounts/signup"]')){
  if(!/^sign up( for instagram)?$/i.test(tabText(link))||link.closest('[data-native-hidden],[role="dialog"]'))continue;
  let node=link.parentElement;
  for(let depth=0;node&&depth<8&&node!==document.body;depth++,node=node.parentElement){
   if(node.querySelector('main,article,input,img,[role="tablist"],header'))break;
   const position=tabPosition(node);
   if(['fixed','sticky','absolute'].includes(position)&&/get the full experience/i.test(tabText(node))){tabSet(node,'data-native-hidden','signup-banner');break;}
  }
 }
}
function scanTabs(){
 if(role!=='page')return;
 try{const kind=tabPageKind();tabScanPrompts();
  if(kind==='search')tabScanSearch();else if(kind==='activity')tabScanActivity();else if(kind==='profile'){tabScanProfile();tabScanProfileTopBar();}
  else if(kind==='inbox')tabInboxQueue();
 }catch(_){}
}
if(role==='page')window.__instagramTabs=Object.freeze({
 switchAccount(){const control=tabSwitcher&&tabSwitcher.isConnected!==false?tabSwitcher:null;if(!control||!control.click)return false;control.click();return true;},
 unread(){try{return tabUnread();}catch(_){return false;}},
 cancelSearch(){tabCancelSearch();return true;},
 hasSearchField(){return !!document.querySelector(TAB_SEARCH);}
});
// Messages inbox (message notifications): thread rows -> `inboxState {threads:[{id,unread,name}]}` for native.
// Runs on the visible Messages tab and in the hidden background-refresh web view (which never reaches `ready`
// reliably, so it depends on the document being complete, not on readiness). Unread signals, in order, with
// fallbacks in docs/DOM-NOTES.md: an "unread" label, a small solid blue dot, a bold preview line.
const INBOX_INTERVAL_MS=1000,INBOX_MAX_THREADS=50,INBOX_NAME_MAX=80,INBOX_LEAF_LIMIT=40;
const INBOX_UNREAD_LABEL=/\bunread\b/i;
let inboxAt=-Infinity,inboxQueued=false,inboxKey='';
/** The thread id a row link opens (`/direct/t/<id>/`), or null. */
function inboxThreadID(link){const href=link&&link.getAttribute&&link.getAttribute('href');if(!href)return null;
 try{const u=new URL(href,'https://www.instagram.com');if(!HOSTS.includes(u.hostname))return null;
  const m=u.pathname.match(/^\/direct\/t\/([A-Za-z0-9_.-]{1,64})\/?$/);return m?m[1]:null;}catch(_){return null;}}
/** Text-bearing leaf elements of a row in document order (no icons, scripts or styles). */
function inboxLeaves(row){
 const out=[];const nodes=(row.children&&row.children.length)?Array.from(row.querySelectorAll('*')):[row];
 for(const node of nodes){if(out.length>=INBOX_LEAF_LIMIT)break;
  if((node.children&&node.children.length>0)||/^(svg|img|script|style|path)$/i.test(node.tagName||''))continue;
  if(tabText(node))out.push(node);}
 return out;}
/** The row of a thread link: the link itself when it holds the text, else the nearest ancestor holding only this thread link. */
function inboxRow(link){
 let row=link;
 for(let depth=0;depth<5&&inboxLeaves(row).length===0&&row.parentElement&&row.parentElement!==document.body;depth++){
  const parent=row.parentElement;if(Array.from(parent.querySelectorAll('a[href*="/direct/t/"]')).length>1)break;row=parent;}
 return row;}
function inboxWeight(node){const w=typeof getComputedStyle==='function'?String(getComputedStyle(node).fontWeight||''):'';
 return /^bold/i.test(w)?700:(parseInt(w,10)||0);}
function inboxUnread(row,leaves){
 // 1. An explicit label: aria-label/title containing "unread" on the row or any descendant, or a leaf reading just "Unread".
 for(const node of [row,...Array.from(row.querySelectorAll('[aria-label],[title]'))]){
  if(INBOX_UNREAD_LABEL.test((node.getAttribute('aria-label')||'')+' '+(node.getAttribute('title')||'')))return true;}
 if(leaves.some(leaf=>/^(\d+\s+)?unread( messages?)?$/i.test(tabText(leaf))))return true;
 // 2. A small solid blue dot (Instagram blue, about 8 px) with no children.
 if(typeof getComputedStyle==='function')for(const node of row.querySelectorAll('div,span,i')){
  if(node.children&&node.children.length>0)continue;const r=tabRect(node);
  if(r.width<4||r.width>16||r.height<4||r.height>16||Math.abs(r.width-r.height)>2)continue;
  const rgb=opaqueRGB(getComputedStyle(node).backgroundColor);if(rgb&&rgb[2]>=200&&rgb[2]>rgb[0]+60&&rgb[2]>rgb[1])return true;}
 // 3. A bold preview line: the second text leaf (after the title) at weight 600 or more.
 return leaves.length>=2&&inboxWeight(leaves[1])>=600;}
/** Thread rows of the inbox in order: first row per thread id, at most INBOX_MAX_THREADS. */
function tabScanInbox(){
 const threads=[],seen=new Set();
 for(const link of document.querySelectorAll('a[href*="/direct/t/"]')){
  if(threads.length>=INBOX_MAX_THREADS)break;
  const id=inboxThreadID(link);if(!id||seen.has(id)||link.closest('[data-native-hidden]'))continue;seen.add(id);
  const row=inboxRow(link),leaves=inboxLeaves(row);
  threads.push({id,unread:inboxUnread(row,leaves),name:Array.from(leaves.length?tabText(leaves[0]):'').slice(0,INBOX_NAME_MAX).join('').trim()});
 }
 return threads;}
function tabPostInbox(){
 inboxAt=now();if(role!=='page'||classify(location.pathname).kind!=='inbox')return;
 if(!(readySent||document.readyState==='complete'))return;
 const threads=tabScanInbox();if(!threads.length)return;
 const key=JSON.stringify(threads);if(key===inboxKey)return;inboxKey=key;post('inboxState',{threads});}
/** Throttled to one scan per INBOX_INTERVAL_MS; leaving the inbox forgets the last state so re-entering reports again. */
function tabInboxQueue(){
 if(role!=='page')return;
 if(classify(location.pathname).kind!=='inbox'){inboxKey='';return;}
 if(inboxQueued)return;
 const wait=inboxAt+INBOX_INTERVAL_MS-now();
 if(wait<=0){tabPostInbox();return;}
 inboxQueued=true;setTimeout(()=>{inboxQueued=false;tabPostInbox();},wait);}
// Its own observer: the shared chrome scan runs from requestAnimationFrame, which a hidden web view may not get.
// `load` too: rows rendered before the document completes would otherwise wait for a later mutation.
if(role==='page'&&typeof MutationObserver==='function')new MutationObserver(tabInboxQueue).observe(document,{childList:true,subtree:true});
if(role==='page')window.addEventListener('load',tabInboxQueue);
// --- end Tabs ---

let chromeQueued=false;
function onMutation(){
 if(role==='tray'){scanTray();return;}
 if(followingBar&&layout.hideChrome&&(!followingBar.isConnected||followingBar.getAttribute('data-native-hidden')!=='following-bar')&&isHome()){followingBar=null;findFollowingBar();}
 queueFrame();
 if(!chromeQueued){chromeQueued=true;const run=()=>{chromeQueued=false;applyLayout();scanChrome();scanTabs();markHeaderSpacers();requestTheme();postRoute();};
  if(typeof requestAnimationFrame==='function')requestAnimationFrame(run);else setTimeout(run,16);}
}
new MutationObserver(onMutation).observe(document,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',onMutation);
window.addEventListener('load',onMutation);
if(role==='page')window.addEventListener('scroll',probeFollowingBar,{passive:true});
postRoute();onMutation();
})();
