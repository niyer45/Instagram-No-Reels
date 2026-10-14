/* Local Instagram presentation filter. Observes existing responses; makes no requests. */
(function () {
'use strict';
const schemaSamples=[],paginationSignals=[];let includeOlder=typeof location!=='undefined'&&new URL(location.href).searchParams.has('variant')&&!['following','home'].includes(new URL(location.href).searchParams.get('variant'));
const LIMIT=1500000, records=new Map(), RESERVED=new Set(['accounts','direct','explore','reels','reel','p','stories','about','legal','challenge','developer','tv','clips','settings','notifications','create']);
function handle(v){if(typeof v!=='string')return null;v=v.trim().replace(/^@/,'').toLowerCase();return /^[a-z0-9._]{1,30}$/.test(v)&&!RESERVED.has(v)?v:null;}
function official(href){if(typeof href!=='string'||!href)return false;try{const u=new URL(href,'https://www.instagram.com');return u.protocol==='https:'&&!u.port&&!u.username&&!u.password&&['instagram.com','www.instagram.com'].includes(u.hostname);}catch(_){return false;}}
function profileHandle(href){if(!official(href))return null;const m=new URL(href,'https://www.instagram.com').pathname.match(/^\/([\w.]+)\/?$/);return m?handle(m[1]):null;}
function code(href){
 if(!official(href))return null;
 try{
  const parts=new URL(href,'https://www.instagram.com').pathname.split('/').filter(Boolean);
  const offset=parts[0]==='p'?0:handle(parts[0])&&parts[1]==='p'?1:-1;
  if(offset<0||!parts[offset+1]||! /^[\w-]+$/.test(parts[offset+1]))return null;
  const suffix=parts.slice(offset+2);
  if(!suffix.length||(suffix.length===1&&['liked_by','comments','embed'].includes(suffix[0]))||(suffix.length===2&&suffix[0]==='c'&&/^[\w-]+$/.test(suffix[1])))return parts[offset+1];
  return null;
 }catch(_){return null;}
}
function route(p){if(/^\/(reels?|tv|clips)(\/|$)/.test(p))return 'blocked';if(/^\/(accounts|challenge|checkpoint|consent|oauth|two_factor)(\/|$)/.test(p))return 'login';if(/^\/explore(?:\/|$)/.test(p))return 'search';return p==='/'?'feed':'other';}
function ingest(value,target=records){
 let visited=0;const seen=new Set();
 function walk(x,depth,inheritedBad=false){
  if(!x||typeof x!=='object'||depth>24||++visited>20000||seen.has(x))return;seen.add(x);
  const pagingKeys=['more_available','has_more','has_next_page','next_max_id','end_cursor'].filter(k=>Object.prototype.hasOwnProperty.call(x,k));
  if(pagingKeys.length&&paginationSignals.length<12)paginationSignals.push({keys:pagingKeys,more:typeof x.more_available==='boolean'?x.more_available:typeof x.has_next_page==='boolean'?x.has_next_page:typeof x.has_more==='boolean'?x.has_more:null,cursor:!!(x.next_max_id||x.end_cursor)});
  const intrinsic=x.is_ad===true||(x.ad_id!=null&&!['','0',0].includes(x.ad_id))||x.sponsored===true;
  const placement=inheritedBad||x.is_suggested===true||x.is_recommended===true;
  const bad=intrinsic||placement;
  const user=x.user||x.owner;const author=handle(user?.username);const shortcode=typeof x.code==='string'?x.code:typeof x.shortcode==='string'?x.shortcode:null;
  if(shortcode&&/^[\w-]{1,100}$/.test(shortcode)&&author){
   if(schemaSamples.length<3){const friendship=user?.friendship_status||x.friendship_status;schemaSamples.push({mediaFields:Object.keys(x).slice(0,40),userFields:Object.keys(user).slice(0,30),friendshipFields:friendship&&typeof friendship==='object'?Object.keys(friendship).slice(0,20):[],followFieldTypes:{user_is_following:typeof user.is_following,owner_followed_by_viewer:typeof user.followed_by_viewer,root_is_following:typeof x.is_following,friendship_following:typeof friendship?.following}});}
   const fs=user?.friendship_status||x.friendship_status;
   const raw=typeof fs?.following==='boolean'?fs.following:typeof user?.is_following==='boolean'?user.is_following:typeof x.is_following==='boolean'?x.is_following:typeof user?.followed_by_viewer==='boolean'?user.followed_by_viewer:null;
   const old=target.get(shortcode);const product=x.product_type;const timestamp=Number(x.taken_at??x.taken_at_timestamp);const takenAt=Number.isFinite(timestamp)&&timestamp>0?timestamp:null;
   const item={takenAt:takenAt??old?.takenAt??null,author,following:raw,reel:product==='clips'||product==='reels',labelsVerified:x.is_ad===false&&x.is_suggested===false,productType:product,mediaType:x.media_type,intrinsic,placement,unknownVideo:x.media_type===2&&product!=='feed'&&product!=='igtv',bad};
   if(old&&old.author===author){item.following=raw===null?old.following:raw;item.productType=product===undefined?old.productType:product;item.mediaType=x.media_type===undefined?old.mediaType:x.media_type;
    item.unknownVideo=item.mediaType===2&&!['feed','igtv'].includes(item.productType);
    item.intrinsic ||=old.intrinsic;item.reel ||=old.reel;
    item.placement=placement?true:x.is_suggested===false||x.is_recommended===false?false:old.placement;
    item.bad=item.intrinsic||item.placement;}
   target.set(shortcode,item);if(target.size>3000)target.delete(target.keys().next().value);
  }
  for(const [key,v]of Object.entries(x))if(v&&typeof v==='object')walk(v,depth+1,placement||intrinsic||/suggested|recommend|ad_media/i.test(key));
 }
 walk(value,0);return target;
}
function parse(text,target){
 if(typeof text!=='string'||text.length>LIMIT)return false;
 const cleaned=text.trim().replace(/^for\s*\(;;\);\s*/,'').replace(/^\)\]\}',?\s*/,'');
 try{ingest(JSON.parse(cleaned),target);return true;}catch(_){}
 let parsed=false;const lines=cleaned.split('\n');if(lines.length>2000)return false;
 for(const line of lines){if(!line.trim())continue;try{ingest(JSON.parse(line.trim().replace(/^for\s*\(;;\);\s*/,'')),target);parsed=true;}catch(_){}}
 return parsed;
}
function paginationTarget(x){return !!(x.underMain&&!x.inPost&&x.empty&&!x.media&&(x.tag==='DIV'||x.progress)&&x.height<=48&&x.bottom>=x.viewport-400&&x.top<=x.viewport+600);}
function shouldContinueScroll({mode,down,nearEnd,reachedCutoff}){return mode==='feed'&&down&&nearEnd&&reachedCutoff;}
function safeHeaderTitle(node){
 return ['SPAN','H1','H2','P'].includes(node.tagName)&&(node.children?.length??0)===0&&(node.textContent||'').trim()==='Following';
}
function caughtUp(items,now=Date.now()/1000){
 const eligible=items.filter(x=>x.following===true&&!x.bad&&!x.reel&&!x.unknownVideo);
 return eligible.some(x=>Number.isFinite(x.takenAt)&&x.takenAt<now-2*86400);
}
function classify(f,allowed,metadata,browsing=false){
 if(f.ambiguousIdentity||f.reel||f.promotional||f.suggested||metadata?.bad||metadata?.reel||(!browsing&&metadata?.unknownVideo))return false;
 if(browsing)return true;
 const authors=[...new Set((f.authors||[]).map(handle).filter(Boolean))];
 if(!authors.length)return false;const author=metadata?metadata.author:authors[0];
 if(metadata&&!authors.includes(author))return false;
 if(metadata?.following===false)return false;
 if(f.video&&!metadata)return false;
 if(!includeOlder&&metadata?.takenAt&&metadata.takenAt<Date.now()/1000-2*86400)return false;
 return metadata?.following===true||allowed.has(author);
}
if(typeof module!=='undefined'&&module.exports){module.exports={handle,official,profileHandle,code,route,ingest,parse,classify,caughtUp,safeHeaderTitle,shouldContinueScroll,paginationTarget};return;}
if(window.top!==window||!official(location.href))return;
const originalObservers=[];let OriginalIntersectionObserver=null,paginationObserver=null,paginationIntent=false,paginationBridges=0,paginationBatches=0,lastPaginationBatch=null;
if(typeof window.IntersectionObserver==='function'){
 const Original=window.IntersectionObserver;OriginalIntersectionObserver=Original;
 window.IntersectionObserver=class extends Original{
  constructor(callback,options){super(callback,options);this.originalCallback=callback;this.originalTargets=new Set();if(originalObservers.length<80)originalObservers.push(this);}
  observe(target){this.originalTargets.add(target);return super.observe(target);}
  unobserve(target){this.originalTargets.delete(target);return super.unobserve(target);}
  disconnect(){this.originalTargets.clear();return super.disconnect();}
 };
}
let queued=false,lastStatus='',observer;
let lastScrollY=0;
const style=document.createElement('style');style.textContent='html[data-instagram-search-idle="yes"] [role="progressbar"],html[data-instagram-search-idle="yes"] [data-visualcompletion="loading-state"],html[data-instagram-search-idle="yes"] [aria-label="Loading..."],html[data-instagram-search-idle="yes"] [aria-label="Loading"]{display:none!important}[data-instagram-search-caught-up]{position:fixed;left:0;right:0;top:var(--instagram-search-content-top,72px);z-index:2;pointer-events:none;text-align:center}[data-instagram-search-caught-up] img{display:block;width:min(100%,400px);height:auto;margin:24px auto 0}#splash-screen{display:none!important;visibility:hidden!important}html{color-scheme:light dark}body{overflow-anchor:none!important}[data-instagram-bottom]{display:flex!important;align-items:center!important;justify-content:space-between!important}[data-instagram-bottom]>[data-instagram-nav-item]{flex:1!important;display:flex!important;align-items:center!important;justify-content:center!important}[data-following-approved="no"]{visibility:hidden!important;pointer-events:none!important}[data-following-approved="no"][data-following-pending="no"]{display:block!important;visibility:hidden!important;height:1px!important;min-height:1px!important;max-height:1px!important;overflow:hidden!important;margin:0!important;padding:0!important;pointer-events:none!important}html[data-following-mode="blocked"] body{visibility:hidden!important}a[href^="/reels"],a[href^="/reel/"],a[href^="/tv/"]{display:none!important}html[data-following-mode="search"] a[href*="/p/"],html[data-following-mode="search"] a[href*="/reel/"],html[data-following-mode="search"] video,html[data-following-mode="search"] article,html[data-following-mode="search"] [data-instagram-search-media]{display:none!important}';
function attachStyle(){if(document.documentElement&&!style.parentNode)document.documentElement.appendChild(style);}
function schedule(){if(!queued){queued=true;queueMicrotask(scan);}}
function acceptText(text){if(parse(text))schedule();}
// Observe only responses generated by Instagram itself. Return original fetch promptly.
if(typeof window.fetch==='function'){
 const original=window.fetch;
 window.fetch=function(...args){const promise=original.apply(this,args);promise.then(response=>{
  const href=response.url|| (typeof args[0]==='string'?args[0]:args[0]?.url);
  if(!official(href)||!(/json|javascript|text\/plain/i.test(response.headers?.get('content-type')||'')))return;
  const length=Number(response.headers?.get('content-length'));if(length>LIMIT)return;
  try{const clone=response.clone();if(clone.body?.getReader){(async()=>{const reader=clone.body.getReader();const chunks=[];let size=0;for(;;){const r=await reader.read();if(r.done)break;size+=r.value.byteLength;if(size>LIMIT){await reader.cancel();return;}chunks.push(r.value);}const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}acceptText(new TextDecoder().decode(bytes));})().catch(()=>{});}else clone.text().then(acceptText).catch(()=>{});}catch(_){}
 },()=>{});return promise;};
}
if(window.XMLHttpRequest){const original=window.XMLHttpRequest.prototype.open;window.XMLHttpRequest.prototype.open=function(...args){
 const href=args[1];this.addEventListener('load',()=>{if(!official(this.responseURL||href))return;try{if(this.responseType==='json')ingest(this.response);else if(!this.responseType||this.responseType==='text')acceptText(this.responseText);schedule();}catch(_){}},{once:true});return original.apply(this,args);};}
function facts(article){
 let links=[];const header=article.querySelector('header');
 if(header)links=[...header.querySelectorAll('a[href]')];
 else links=[...article.querySelectorAll('h2 a[href],h3 a[href]')].filter(a=>!a.closest('footer,[role="comment"],ul'));
 if(!links.length){
  // Modern markup: descend through wrappers to the first attribution branch.
  // A row may contain an avatar; the first sibling containing a post permalink
  // or substantial media establishes the boundary before caption/comments.
  let branch=article;for(let depth=0;depth<8;depth++){
   const children=[...(branch.children||[])];if(!children.length)break;
   const first=children[0];if(['LI','UL','FOOTER','SECTION'].includes(first.tagName))break;const firstLinks=[...first.querySelectorAll('a[href]')];
   const profileLinks=firstLinks.filter(a=>profileHandle(a.getAttribute('href'))===handle(a.textContent)&&profileHandle(a.getAttribute('href')));
   const hasPostLink=firstLinks.some(a=>code(a.getAttribute('href')));
   const hasComment=!!first.querySelector('li,ul,footer,section,[role="comment"]');
   if(profileLinks.length&&profileLinks.length<=4&&!hasPostLink&&!hasComment){links=profileLinks;break;}
   if(['LI','UL','FOOTER','SECTION'].includes(first.tagName))break;
   branch=first;
  }
  if(!links.length){const first=article.firstElementChild;if(first&&!['LI','UL','FOOTER','SECTION'].includes(first.tagName)&&!first.querySelector('a[href*="/p/"],video,li,ul,footer,section')){const rowLinks=[...first.querySelectorAll('a[href]')];if(rowLinks.length<=4)links=rowLinks;}}
 }
 const authors=links.filter(a=>profileHandle(a.getAttribute('href'))===handle(a.textContent)).map(a=>profileHandle(a.getAttribute('href'))).filter(Boolean);
 const labelRoots=[...article.querySelectorAll('header,[data-testid="sponsored-label"],[aria-label="Sponsored"]')];
 const labels=labelRoots.flatMap(n=>[...n.querySelectorAll('span,a')].map(x=>(x.textContent||'').trim().toLowerCase()));
 const promotional=labels.some(t=>['sponsored','paid partnership','advertisement'].includes(t));
 const suggested=labels.some(t=>['suggested for you','suggested post','recommended for you','because you follow'].includes(t));const identities=[...new Set([...article.querySelectorAll('a[href]')].map(a=>code(a.getAttribute('href'))).filter(Boolean))];const permalink=identities.length===1?identities[0]:null;
 return {authors,permalink,ambiguousIdentity:identities.length>1,video:!!article.querySelector('video'),reel:!!article.querySelector('a[href*="/reel/"],a[href*="/reels/"]'),promotional,suggested};
}
function candidates(){
 const main=document.querySelector('main');if(!main)return [];
 const found=new Set();
 for(const a of document.querySelectorAll('article'))if(main.contains(a)&&!(a.parentElement&&a.parentElement.closest('article'))&&a.querySelector('img,video,a[href*="/p/"]'))found.add(a);
 if(location.pathname!=='/'&&code(location.href)===null)return [...found];
 for(const link of main.querySelectorAll('a[href*="/p/"]')){
  if(!code(link.getAttribute('href')))continue;
  if(link.closest('article'))continue;
  let node=link.parentElement;let depth=0;let fallback=node;
  while(node&&node!==main&&depth++<8){
   const codes=new Set([...node.querySelectorAll('a[href*="/p/"]')].map(a=>code(a.getAttribute('href'))).filter(Boolean));
   if(codes.size>1||node.querySelectorAll('header').length>1)break;
   if(node.querySelector('img,video'))fallback=node;
   if(node.querySelector('img,video')&&facts(node).authors.length>0){found.add(node);break;}
   node=node.parentElement;
  }
  if(![...found].some(a=>a.contains(link))&&fallback&&fallback!==main&&fallback.querySelector('img,video'))found.add(fallback);
 }
 return [...found].filter(a=>![...found].some(b=>b!==a&&b.contains(a)));
}
const parsedScripts=new WeakMap();
function publishStoryPosition(){
 const slot=document.querySelector('[data-instagram-stories-slot]');if(!slot)return;
 const header=document.querySelector('header:not(article header),[role="banner"]');
 const r=slot.getBoundingClientRect();const headerBottom=header?Math.max(0,Math.min(120,header.getBoundingClientRect().bottom)):56;
 try{window.webkit.messageHandlers.followingStoriesPosition.postMessage({top:r.top,headerBottom});}catch(_){}
}
let searchReadySent=false,searchReadyRunning=false;
function publishStableSearch(){
 const bridge=window.webkit?.messageHandlers?.followingSearchReady;
 if(!bridge||searchReadySent||searchReadyRunning||route(location.pathname)!=='search')return;
 searchReadyRunning=true;let last=null,key='',frames=0;
 function frame(){
  if(route(location.pathname)!=='search'){searchReadyRunning=false;return;}
  const control=document.querySelector('input[placeholder*="Search" i],input[aria-label*="Search" i],input[type="search"],[role="combobox"]');
  const r=control?.getBoundingClientRect();const css=control?getComputedStyle(control):null;
  const image=document.querySelector('[data-instagram-search-caught-up] img');
  const ready=document.readyState==='complete'&&!!r&&r.width>0&&r.height>0&&css.display!=='none'&&css.visibility!=='hidden'&&css.opacity!=='0'&&(!image||image.complete&&image.naturalWidth>0);
  const next=ready?[r.top,r.left,r.width,r.height].map(Math.round).join(','):'';
  frames=ready&&control===last&&next===key?frames+1:0;last=control;key=next;
  if(frames>=24){searchReadySent=true;searchReadyRunning=false;bridge.postMessage({ready:true});return;}
  requestAnimationFrame(frame);
 }
 requestAnimationFrame(frame);
}
let searchEngaged=false;
function searchInteraction(event){
 if(route(location.pathname)!=='search')return;
 const control=event.target?.closest?.('input,textarea,[role="combobox"],button,[role="button"]');if(!control)return;
 const label=(control.getAttribute?.('aria-label')||control.textContent||'').trim();
 if(/^(cancel|back)$/i.test(label)){searchEngaged=false;schedule();return;}
 if(control.matches?.('input,textarea,[role="combobox"]')||/search/i.test(label)&&(control.getBoundingClientRect?.().top??Infinity)<160){searchEngaged=true;renderSearchPlaceholder('search');}
}
function renderSearchPlaceholder(mode){
 if(mode!=='search')searchEngaged=false;
 const root=document.documentElement;let banner=document.querySelector('[data-instagram-search-caught-up]');
 const input=mode==='search'?document.querySelector('input[placeholder*="Search" i],input[aria-label*="Search" i],input[type="search"],[role="combobox"]'):null;
 const idle=mode==='search'&&location.pathname.replace(/\/$/,'')==='/explore'&&!searchEngaged&&!(input&&document.activeElement===input)&&!(input?.value||'').trim()&&!document.querySelector('[role="dialog"]');
 if(!idle){root.removeAttribute('data-instagram-search-idle');if(banner)banner.remove();return;}
 root.setAttribute('data-instagram-search-idle','yes');
 const source=window.__followingPolicy?.searchCaughtUpImage;if(!source)return;
 if(!banner){banner=document.createElement('section');banner.setAttribute('data-instagram-search-caught-up','');
  const image=document.createElement('img');image.src=source;image.alt="You're all caught up. You've seen all new posts from the past 2 days.";image.width=400;image.height=280;
  banner.appendChild(image);(document.body||root).appendChild(banner);
 }
 const bottom=input?.getBoundingClientRect?.().bottom;
 if(banner.style)banner.style.setProperty('--instagram-search-content-top',Math.max(64,Number.isFinite(bottom)?bottom+8:64)+'px');
}
function refreshPaginationObservers(){
 if(!paginationIntent||(paginationBatches>=4&&lastPaginationBatch!==records.size)||route(location.pathname)!=='feed'||!OriginalIntersectionObserver)return;
 const root=document.documentElement,viewport=window.innerHeight||0;
 if(!root||root.scrollHeight-(window.scrollY||0)-viewport>600)return;
 if(!paginationObserver)paginationObserver=new OriginalIntersectionObserver(entries=>{
  for(const entry of entries)if(entry.isIntersecting){for(const owner of originalObservers){
   if(!owner.originalTargets.has(entry.target)||owner.lastPaginationRecords===records.size||(paginationBatches>=4&&lastPaginationBatch!==records.size))continue;
   if(lastPaginationBatch!==records.size){lastPaginationBatch=records.size;paginationBatches++;}
   owner.lastPaginationRecords=records.size;paginationBridges++;owner.originalCallback.call(owner,[entry],owner);
  }}
 },{rootMargin:'0px 0px 300px 0px'});
 for(const owner of originalObservers)for(const node of owner.originalTargets){const r=node.getBoundingClientRect();
  if(paginationTarget({tag:node.tagName,underMain:!!node.closest('main'),inPost:!!node.closest('article'),empty:!(node.textContent||'').trim(),media:!!node.querySelector('img,video'),progress:node.getAttribute('role')==='progressbar',height:r.height,top:r.top,bottom:r.bottom,viewport})&&owner.lastPaginationRecords!==records.size){paginationObserver.unobserve(node);paginationObserver.observe(node);}
 }
}
function continueOnIntent(down){
 const y=window.scrollY||0,root=document.documentElement;
 const nearEnd=root&&root.scrollHeight-y-(window.innerHeight||0)<600;
 if(down&&nearEnd){paginationIntent=true;refreshPaginationObservers();}
 if(down&&nearEnd&&route(location.pathname)==='feed'){const control=[...document.querySelectorAll('main a,main button,main [role="button"]')].find(n=>/^(view|see) older posts$/i.test((n.textContent||'').trim())&&!n.closest('article'));if(control&&!control.hasAttribute('data-instagram-auto-older')){control.setAttribute('data-instagram-auto-older','');includeOlder=true;control.click();return;}}
 if(!includeOlder&&shouldContinueScroll({mode:route(location.pathname),down,nearEnd:root&&root.scrollHeight-y-(window.innerHeight||0)<600,reachedCutoff:!!document.querySelector('[data-instagram-caught-up]')})){includeOlder=true;scan();}
}
let touchY=null;
window.addEventListener('touchstart',event=>{paginationBridges=0;paginationBatches=0;lastPaginationBatch=null;paginationIntent=false;touchY=event.touches?.[0]?.clientY??null;},{passive:true});
window.addEventListener('touchmove',event=>{const y=event.touches?.[0]?.clientY;if(event.isTrusted&&typeof y==='number'&&touchY!==null)continueOnIntent(y<touchY);touchY=y??null;},{passive:true});
window.addEventListener('wheel',event=>{if(event.isTrusted)continueOnIntent(event.deltaY>0);},{passive:true});
window.addEventListener('scroll',event=>{
 if(typeof requestAnimationFrame==='function')requestAnimationFrame(publishStoryPosition);else publishStoryPosition();
 const y=window.scrollY||0;if(event.isTrusted)continueOnIntent(y>lastScrollY);lastScrollY=y;
},{passive:true,capture:true});
function scan(){queued=false;attachStyle();
 for(const link of document.querySelectorAll('a[href]')){
  let u;try{u=new URL(link.getAttribute('href'),location.href);}catch(_){continue;}
  if(!official(u.href)||!/^\/direct(?:\/inbox)?\/?$/.test(u.pathname))continue;
  let nav=link.parentElement;
  for(let depth=0;nav&&depth<7;depth++,nav=nav.parentElement){
   const r=typeof nav.getBoundingClientRect==='function'?nav.getBoundingClientRect():null;
   const home=[...nav.querySelectorAll('a[href]')].find(a=>{try{return new URL(a.getAttribute('href'),location.href).pathname==='/';}catch(_){return false;}});
   if(home&&r&&r.top>(window.innerHeight||0)*0.65&&r.height<130){
    nav.setAttribute('data-instagram-bottom','');
    for(const child of [...nav.children]){
     const anchors=child.matches?.('a[href]')?[child]:[...child.querySelectorAll('a[href]')];
     const enabled=anchors.some(a=>{try{return route(new URL(a.getAttribute('href'),location.href).pathname)!=='blocked';}catch(_){return false;}});
     if(enabled){child.setAttribute('data-instagram-nav-item','');}else if(anchors.length){child.style.display='none';}
    }
    link.setAttribute('data-instagram-messages','');link.style.removeProperty('position');link.style.removeProperty('top');link.style.removeProperty('bottom');link.style.removeProperty('left');link.style.removeProperty('transform');
    break;
   }
  }
 }
const root=document.documentElement;if(!root)return;const mode=route(location.pathname);if(mode!=='search')for(const node of document.querySelectorAll('[data-instagram-search-media]'))node.removeAttribute('data-instagram-search-media');if(root.getAttribute('data-following-mode')!==mode)root.setAttribute('data-following-mode',mode);renderSearchPlaceholder(mode);publishStableSearch();
 for(const script of document.querySelectorAll('script[type="application/json"]'))if(script.textContent.length<=LIMIT&&parsedScripts.get(script)!==script.textContent){parsedScripts.set(script,script.textContent);parse(script.textContent);}
 const p=window.__followingPolicy;const allowed=new Set(Array.isArray(p?.handles)?p.handles.map(handle).filter(Boolean):[]);
 const postContext=mode==='feed'||code(location.href)!==null||profileHandle(location.href)!==null&&mode!=='login';
 const articles=postContext?candidates():[];
 if(mode==='search'){for(const link of document.querySelectorAll('a[href]')){if(!code(link.getAttribute('href'))&&!/\/reels?\//.test(link.getAttribute('href')||''))continue;const tile=link.closest('article')||link.parentElement;if(tile&&!tile.querySelector('input,[role="combobox"]'))tile.setAttribute('data-instagram-search-media','');}}
let shown=0,hidden=0,missing=false,unknown=false,language=false;
 const lang=(root.getAttribute('lang')||'en').toLowerCase();
 // Preserve profile grids, stories and settings. Filter actual post articles only.
 for(const article of articles){const f=facts(article);const metadata=f.permalink?records.get(f.permalink):null;const unsupportedLanguage=!/^en(?:-|$)/.test(lang)&&!metadata?.labelsVerified;const approved=!unsupportedLanguage&&classify(f,allowed,metadata,mode!=='feed');language ||=unsupportedLanguage;unknown ||=f.authors.length===0||f.ambiguousIdentity;const value=approved?'yes':'no';const pending=!approved&&(!metadata||f.authors.length===0)&&!f.reel&&!f.promotional&&!f.suggested;const pendingValue=pending?'yes':'no';if(article.getAttribute('data-following-pending')!==pendingValue)article.setAttribute('data-following-pending',pendingValue);if(article.getAttribute('data-following-approved')!==value)article.setAttribute('data-following-approved',value);if(approved)shown++;else{hidden++;if(!f.reel&&!f.promotional&&!f.suggested&&!f.ambiguousIdentity&&!metadata?.bad&&!metadata?.reel&&!metadata?.unknownVideo&&!(f.video&&!metadata)&&f.authors.length>0&&(!metadata||f.authors.includes(metadata.author))&&metadata?.following!==true&&metadata?.following!==false&&allowed.size===0)missing=true;}}
 if(!includeOlder&&mode==='feed'&&new URL(location.href).searchParams.get('variant')==='following'&&caughtUp(articles.map(a=>records.get(facts(a).permalink)).filter(Boolean))){
  const main=document.querySelector('main');
  if(main&&!main.querySelector('[data-instagram-caught-up]')){
   const banner=document.createElement('section');banner.setAttribute('data-instagram-caught-up','');banner.setAttribute('role','status');
   banner.style.cssText='text-align:center;padding:32px 18px;color:inherit';
   const icon=document.createElement('div');icon.textContent='✓';icon.style.cssText='margin:0 auto 18px;width:70px;height:70px;line-height:70px;border:3px solid #ed467b;border-radius:50%;font-size:38px;color:#ed467b';
   const title=document.createElement('h2');title.textContent="You're all caught up";
   const detail=document.createElement('p');detail.textContent="You've seen all new posts from the past 2 days.";detail.style.cssText='color:gray;font-size:16px';
   const older=document.createElement('button');older.textContent='View older posts';older.style.cssText='border:0;background:none;color:#3897f0;font-size:17px;font-weight:600;padding:10px';older.onclick=()=>{includeOlder=true;banner.remove();scan();};
   banner.appendChild(icon);banner.appendChild(title);banner.appendChild(detail);banner.appendChild(older);main.appendChild(banner);
  }
 }
 if(mode==='feed'&&new URL(location.href).searchParams.get('variant')==='following'&&window.__instagramStoriesHeight>0){
  const first=articles[0];let slot=document.querySelector('[data-instagram-stories-slot]');
  if(first&&!slot){const main=document.querySelector('main');let branch=first;while(branch.parentElement&&branch.parentElement!==main)branch=branch.parentElement;if(branch.parentElement===main){slot=document.createElement('div');slot.setAttribute('data-instagram-stories-slot','');main.insertBefore(slot,branch);}}
  if(slot){const height=Math.min(190,window.__instagramStoriesHeight)+'px';if(slot.style.height!==height)slot.style.height=height;publishStoryPosition();}
 }
 const positive=[...records.values()].some(x=>x.following===true);
 const login=mode==='login'||!!document.querySelector('input[type="password"]')||(!articles.length&&!records.size&&!!document.querySelector('main a[href^="/accounts/login"]'));
 const reason=mode==='blocked'?'blocked-route':login?'login':language?'unsupported-language':missing?'following-unavailable':unknown?'unrecognized-posts':!articles.length?(mode==='feed'?'no-posts':'filtered'):'filtered';
 const state=login?'login':missing?'needsFollowing':mode==='blocked'||language||unknown||(mode==='feed'&&!articles.length)?'unsupported':'filtered';
 const recordValues=[...records.values()];
 const recordTrue=recordValues.filter(x=>x.following===true).length,recordFalse=recordValues.filter(x=>x.following===false).length,recordUnknown=recordValues.filter(x=>x.following===null).length;
 const cardWithAuthor=articles.filter(a=>facts(a).authors.length===1).length;
 const followingFeedAvailable=[...document.querySelectorAll('a[href]')].some(a=>{try{const u=new URL(a.getAttribute('href'),location.href);return official(u.href)&&u.pathname==='/'&&u.searchParams.get('variant')==='following';}catch(_){return false;}});
 let backgroundRGB=null;
 if(typeof getComputedStyle==='function'){
  for(const node of [document.body,root])if(node){const value=getComputedStyle(node).backgroundColor;const m=value.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/);if(m&&(!m[4]||Number(m[4])===1)){backgroundRGB=m.slice(1,4).map(Number);break;}}
 }
 const payload={homeFeed:mode==='feed',backgroundRGB,state,followingFeedAvailable,shown,hidden,reason,recordTrue,recordFalse,recordUnknown,cardWithAuthor,metadataRecords:records.size,haveFollowing:allowed.size>0||positive,postCandidates:articles.length,articleCount:document.querySelectorAll('article').length,headerCount:document.querySelectorAll('article header').length,h2Count:document.querySelectorAll('main h2').length,permalinkCount:document.querySelectorAll('main a[href*="/p/"]').length};
 refreshPaginationObservers();
 const key=JSON.stringify(payload);if(key!==lastStatus){lastStatus=key;try{window.webkit.messageHandlers.followingStatus.postMessage(payload);}catch(_){}}
 // Place optional controls inside the original settings menu only.
 for(const menu of document.querySelectorAll('[role="menu"]'))if(/\b(settings|your activity)\b/i.test(menu.textContent||'')&&!menu.querySelector('[data-following-controls]')){const button=document.createElement('button');button.textContent='Following filter settings';button.setAttribute('data-following-controls','yes');button.onclick=()=>{try{window.webkit.messageHandlers.followingControls.postMessage({action:'open'});}catch(_){}};menu.appendChild(button);}
}

window.__instagramFilterDiagnostics=function(){
 const cards=candidates().slice(0,3);const allowed=new Set((window.__followingPolicy?.handles||[]).map(handle).filter(Boolean));const values=[...records.values()];
 function profileCount(n){return [...n.querySelectorAll('a[href]')].filter(a=>profileHandle(a.getAttribute('href'))===handle(a.textContent)&&profileHandle(a.getAttribute('href'))!==null).length;}
 function relativePath(a,card){const path=[];let node=a;while(node&&node!==card&&path.length<8){const parent=node.parentElement;if(!parent)break;path.unshift((node.tagName||'node')+':'+Array.prototype.indexOf.call(parent.children,node));node=parent;}return path.join('/');}
 const followingLinks=[...document.querySelectorAll('a[href]')].filter(a=>{try{const u=new URL(a.getAttribute('href'),location.href);return official(u.href)&&u.pathname==='/'&&u.searchParams.get('variant')==='following';}catch(_){return false;}});
 const followingLabels=[...document.querySelectorAll('nav a,nav button,header a,header button')].filter(a=>!a.closest('article')&&(a.textContent||'').trim()==='Following');
 return {paginationBridges,intersectionTargets:originalObservers.flatMap(o=>[...o.originalTargets].map(n=>{const r=n.getBoundingClientRect();return {tag:n.tagName,underMain:!!n.closest('main'),height:r.height,top:r.top,bottom:r.bottom,media:!!n.querySelector('img,video'),empty:!(n.textContent||'').trim(),progress:n.getAttribute('role')==='progressbar'};})).slice(-20),pagingSignals:paginationSignals,documentHeight:document.documentElement.scrollHeight||0,viewportHeight:window.innerHeight||0,windowScrollY:window.scrollY||0,scrollContainers:typeof getComputedStyle==='function'?[...document.querySelectorAll('main,main div')].slice(0,500).filter(n=>n.scrollHeight>n.clientHeight+100&&['auto','scroll'].includes(getComputedStyle(n).overflowY)).slice(0,5).map(n=>({tag:n.tagName,height:n.clientHeight,contentHeight:n.scrollHeight,top:n.scrollTop})):[],loadControls:[...document.querySelectorAll('main a,main button,main [role="button"]')].filter(n=>/^(view older posts|see older posts|load more|load more posts|see more posts)$/i.test((n.textContent||'').trim())).map(n=>({kind:(n.textContent||'').trim().toLowerCase(),disabled:!!n.disabled||n.getAttribute('aria-disabled')==='true'})),olderEnabled:includeOlder,datedRecords:values.filter(x=>x.takenAt).length,olderControls:document.querySelectorAll('[data-instagram-auto-older]').length,defaultFollowing:new URL(location.href).searchParams.get("variant")==="following",centeredMessages:document.querySelectorAll("[data-instagram-messages]").length,followingFeedAvailable:followingLinks.length>0,followingRoute:followingLinks.length?'/?variant=following':null,followingNavigationLabels:followingLabels.length,followingSelectedLabels:followingLabels.filter(a=>a.getAttribute('aria-current')==='page'||a.getAttribute('aria-selected')==='true').length,recordFollowingTrue:values.filter(x=>x.following===true).length,recordFollowingFalse:values.filter(x=>x.following===false).length,recordFollowingUnknown:values.filter(x=>x.following===null).length,matchedRecords:cards.filter(a=>records.has(facts(a).permalink)).length,codeMatches:cards.filter(a=>!!facts(a).permalink).length,attributionCandidates:cards.map(a=>facts(a).authors.length),permalinkPathShapes:[...document.querySelectorAll('main a[href*="/p/"]')].slice(0,8).map(a=>{const segments=new URL(a.getAttribute('href'),location.href).pathname.split('/').filter(Boolean);const index=segments.indexOf('p');const suffix=segments[index+2];return {segmentCount:segments.length,suffixKind:!suffix?'none':['liked_by','comments','c','embed'].includes(suffix)?suffix:'unknown',shape:segments.map((s,i)=>s==='p'?'p':i===0&&segments[1]==='p'?'username':'opaque').join('/')};}),cardsWithSingleAuthor:cards.filter(a=>facts(a).authors.length===1).length,
 cards:cards.map(card=>{const f=facts(card);const m=records.get(f.permalink);const authors=[...new Set(f.authors)];const reason=f.promotional||f.suggested||m?.bad?'blocked-ad':f.reel||m?.reel?'blocked-reel':!authors.length||f.ambiguousIdentity?'unknown-author':m&&!authors.includes(m.author)?'metadata-author-mismatch':m?.following===false?'not-followed':m?.unknownVideo||f.video&&!m?'unknown-video':classify(f,allowed,m)?'approved':'following-unavailable';return {matched:!!m,authorCount:authors.length,metadataFollow:typeof m?.following==='boolean'?m.following:null,reason,mediaType:m?.mediaType===1?'photo':m?.mediaType===2?'video':m?.mediaType===8?'carousel':'unknown',productType:['feed','clips','reels','igtv'].includes(m?.productType)?m.productType:'unknown',children:[...(card.children||[])].slice(0,12).map(child=>({tagName:child.tagName,childCount:(child.children||[]).length,media:!!child.querySelector('img,video'),matchingProfileAnchors:profileCount(child)})),profileAnchorPaths:[...card.querySelectorAll('a[href]')].filter(a=>profileHandle(a.getAttribute('href'))===handle(a.textContent)&&profileHandle(a.getAttribute('href'))!==null).slice(0,5).map(a=>relativePath(a,card))};}),schemas:schemaSamples};
};

observer=new MutationObserver(schedule);observer.observe(document,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['href','src','aria-label']});

document.addEventListener('input',schedule,true);document.addEventListener('pointerdown',searchInteraction,true);document.addEventListener('focusin',event=>{searchInteraction(event);schedule();},true);document.addEventListener('focusout',schedule,true);
window.addEventListener('following-policy-change',scan);window.addEventListener('popstate',scan);
function forwardNativeDestination(value){
 const bridge=window.webkit?.messageHandlers?.followingOpenDestination;
 if(!bridge)return false;
 try{const u=new URL(value,location.href);if(!official(u.href)||route(u.pathname)==='blocked')return false;
  const home=route(location.pathname)==='feed';
  if((window.__instagramPinnedSearch&&route(u.pathname)!=='search')||(!window.__instagramPinnedSearch&&u.pathname.replace(/\/$/,'')==='/explore')||(window.__instagramPinnedProfile&&u.pathname!==location.pathname)||(home&&u.pathname!=='/'&&!u.pathname.startsWith('/accounts/login'))||(!home&&u.pathname==='/')){bridge.postMessage({url:u.href});return true;}
 }catch(_){}return false;
}
for(const name of ['pushState','replaceState']){const original=history[name];history[name]=function(...args){if(args[2]!=null){try{const u=new URL(args[2],location.href);if(official(u.href)&&route(u.pathname)==='blocked')return;if(forwardNativeDestination(u.href))return;}catch(_){}}const result=original.apply(this,args);scan();return result;};}
document.addEventListener('click',event=>{searchInteraction(event);const target=event.target instanceof Element?event.target:null;const destination=target?.closest('a[href]');if(destination&&destination.closest?.('[data-instagram-bottom]')&&profileHandle(destination.href)&&window.webkit?.messageHandlers?.followingOpenDestination){window.webkit.messageHandlers.followingOpenDestination.postMessage({url:destination.href,tab:'profile'});event.preventDefault();event.stopImmediatePropagation();return;}if(destination&&forwardNativeDestination(destination.href)){event.preventDefault();event.stopImmediatePropagation();return;}const button=target?target.closest('button,[role="button"]'):null;if(button&&['Reels'].includes(button.getAttribute('aria-label'))){event.preventDefault();event.stopImmediatePropagation();return;}const a=event.target instanceof Element?event.target.closest('a[href]'):null;if(a){const home=new URL(a.href,location.href);if(official(home.href)&&home.pathname==='/'&&(!home.searchParams.has('variant')||home.searchParams.get('variant')==='home')){event.preventDefault();event.stopImmediatePropagation();location.assign('https://www.instagram.com/?variant=following');return;}}if(a&&route(new URL(a.href,location.href).pathname)==='blocked'){event.preventDefault();event.stopImmediatePropagation();}},true);
scan();
})();
