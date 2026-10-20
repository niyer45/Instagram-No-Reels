const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {classify,decide,readiness,official,opaqueRGB,surfaceRGB,avatarURL,shapePath}=require('../Resources/Bridge.js');
const fixtures=JSON.parse(fs.readFileSync(path.join(__dirname,'route-fixtures.json'),'utf8'));
const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');

test('route classification matches the shared native fixture table',()=>{
 for(const [p,kind,identity] of fixtures.classify)assert.deepEqual(classify(p),{kind,identity},p);
});
test('navigate decisions match the shared native fixture table',()=>{
 for(const [current,target,role,result] of fixtures.decide)assert.equal(decide(current,target,role),result,current+' -> '+target+' ('+role+')');
});
test('relative, hash and malformed targets resolve against the current page',()=>{
 assert.equal(decide('https://www.instagram.com/alice/','/bob/'),'native');
 assert.equal(decide('https://www.instagram.com/alice/','#top'),'stay');
 assert.equal(decide('https://www.instagram.com/alice/','http://[bad'),'pass');
 assert.equal(decide('https://www.instagram.com/alice/','javascript:void(0)'),'pass');
 assert.equal(decide('https://www.instagram.com/alice/','https://www.instagram.com:8443/bob/'),'pass');
});
test('readiness waits for kind-specific content and falls back once settled',()=>{
 const base={complete:true,elapsed:100,loading:false,mainMedia:false,loginForm:false,approvedPosts:0,caughtUp:false,articles:0,profileHeader:false,mainContent:false,searchStable:false};
 assert.equal(readiness('home',base),false);
 assert.equal(readiness('home',{...base,approvedPosts:1}),true);
 assert.equal(readiness('home',{...base,caughtUp:true}),true);
 assert.equal(readiness('home',{...base,elapsed:5000}),false);
 assert.equal(readiness('home',{...base,elapsed:8000}),true);
 assert.equal(readiness('home',{...base,elapsed:8000,complete:false}),false);
 assert.equal(readiness('profile',{...base,profileHeader:true}),true);
 assert.equal(readiness('profile',{...base,profileHeader:true,loading:true}),false);
 assert.equal(readiness('post',{...base,articles:1}),true);
 assert.equal(readiness('search',{...base,searchStable:true}),true);
 assert.equal(readiness('inbox',{...base,mainContent:true}),true);
 assert.equal(readiness('inbox',{...base,mainContent:true,loading:true}),false);
 assert.equal(readiness('inbox',{...base,elapsed:4000}),true);
 for(const kind of ['home','search','profile','inbox'])assert.equal(readiness(kind,{...base,complete:false,loginForm:true}),true);
});
test('theme colours accept opaque values only and avatars accept Instagram CDN URLs only',()=>{
 assert.deepEqual(opaqueRGB('rgb(12, 16, 20)'),[12,16,20]);
 assert.deepEqual(opaqueRGB('rgba(0, 0, 0, 1)'),[0,0,0]);
 assert.equal(opaqueRGB('rgba(0, 0, 0, 0)'),null);assert.equal(opaqueRGB('transparent'),null);
 assert.equal(avatarURL('https://scontent-lhr8-1.cdninstagram.com/v/t51/a.jpg?x=1'),'https://scontent-lhr8-1.cdninstagram.com/v/t51/a.jpg?x=1');
 assert.ok(avatarURL('https://instagram.fxyz1-1.fna.fbcdn.net/a.jpg'));
 for(const bad of ['http://scontent.cdninstagram.com/a.jpg','https://evilcdninstagram.com/a.jpg','https://cdninstagram.com.evil.example/a.jpg','data:image/png;base64,AA'])assert.equal(avatarURL(bad),null,bad);
 assert.equal(official('https://www.instagram.com/x'),true);assert.equal(official('https://instagram.com.evil.example/'),false);
});
test('theme sampling sees full-width pointer-events:none background layers that hit-testing skips',()=>{
 const style=new Map();const styleOf=n=>style.get(n)||{backgroundColor:'rgba(0, 0, 0, 0)',pointerEvents:'auto'};
 const html={},body={},mount={},content={},grey={},overlay={},hidden={};
 html.children=[body];body.children=[mount];mount.children=[grey,content];content.children=[];
 style.set(html,{backgroundColor:'rgb(12, 16, 20)'});style.set(body,{backgroundColor:'rgb(12, 16, 20)'});
 style.set(grey,{backgroundColor:'rgb(31, 31, 32)',pointerEvents:'none'});
 const covers=new Set([grey,overlay,hidden]);const isSurface=n=>covers.has(n);
 // Meta's login page: the hit stack is transparent wrappers, body and html; the grey layer is not in it.
 assert.deepEqual(surfaceRGB([content,mount,body,html],styleOf,isSurface),[31,31,32]);
 // Without such a layer the first opaque node in the stack still wins.
 mount.children=[content];assert.deepEqual(surfaceRGB([content,mount,body,html],styleOf,isSurface),[12,16,20]);
 // Hit-testable, translucent, hidden or non-covering children are ignored.
 style.set(overlay,{backgroundColor:'rgb(255, 255, 255)',pointerEvents:'auto'});
 style.set(hidden,{backgroundColor:'rgb(255, 255, 255)',pointerEvents:'none',visibility:'hidden'});
 const narrow={};style.set(narrow,{backgroundColor:'rgb(255, 255, 255)',pointerEvents:'none'});
 const tint={};covers.add(tint);style.set(tint,{backgroundColor:'rgba(255, 255, 255, 0.5)',pointerEvents:'none'});
 mount.children=[overlay,hidden,narrow,tint,content];assert.deepEqual(surfaceRGB([content,mount,body,html],styleOf,isSurface),[12,16,20]);
 assert.equal(surfaceRGB([content],styleOf,isSurface),null);
});

function page({path='/',role='page',boot={}}={}){
 const posted=[],listeners={},frames=[];
 const attrs=new Map(),styles=new Map();
 const root={getAttribute:k=>attrs.has(k)?attrs.get(k):null,setAttribute:(k,v)=>attrs.set(k,v),style:{setProperty:(k,v)=>styles.set(k,v)},appendChild(){}};
 const document={documentElement:root,readyState:'loading',title:'Instagram',body:null,
  querySelector:()=>null,querySelectorAll:()=>[],createElement:()=>({}),addEventListener:(k,f)=>{listeners['doc:'+k]=f;}};
 const location={pathname:path.split('?')[0],search:path.includes('?')?path.slice(path.indexOf('?')):'',get href(){return 'https://www.instagram.com'+this.pathname+this.search;}};
 const history={state:{entry:1},pushState(a,b,u){const x=new URL(u,location.href);location.pathname=x.pathname;location.search=x.search;this.state=a;},replaceState(a,b,u){const x=new URL(u,location.href);location.pathname=x.pathname;location.search=x.search;this.state=a;}};
 const dispatched=[];
 const window={innerWidth:400,innerHeight:800,__instagramBoot:{role,...boot},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},addEventListener:(k,f)=>{listeners['win:'+k]=f;},
  dispatchEvent(e){dispatched.push(e);if(listeners['win:'+e.type])listeners['win:'+e.type](e);return true;}};
 window.top=window;
 class Event{constructor(type){this.type=type;}}
 class PopStateEvent extends Event{constructor(type,init){super(type);this.state=init?init.state:null;}}
 const context={window,document,location,history,URL,WeakSet,Event,PopStateEvent,Element:class{},setTimeout:()=>0,requestAnimationFrame:f=>frames.push(f),
  performance:{now:()=>0},getComputedStyle:()=>({display:'block',visibility:'visible',opacity:'1',position:'static',backgroundColor:'rgb(12, 16, 20)'}),
  MutationObserver:class{constructor(f){listeners.mutation=f;}observe(){}}};
 vm.runInNewContext(source,context);
 return {posted,listeners,frames,attrs,styles,context,window,document,location,history,dispatched,
  click(href){let prevented=0;const link={href:new URL(href,location.href).href,getAttribute:()=>href};
   listeners['win:click']({target:{closest:s=>s==='a[href]'?link:null},preventDefault(){prevented++;},stopImmediatePropagation(){}});return prevented;},
  flush(n=1){for(let i=0;i<n;i++){const run=frames.splice(0);for(const f of run)f();}},
  of:type=>posted.filter(m=>m.type===type).map(m=>JSON.parse(JSON.stringify(m)))};
}

test('every message uses one handler with a type, and native layout reaches CSS variables',()=>{
 const p=page({path:'/alice/',boot:{headerHeight:44,hideChrome:true}});
 assert.deepEqual(p.of('route')[0],{type:'route',path:'/alice/',search:'',title:''});
 assert.equal(p.styles.get('--native-header-height'),'44px');assert.equal(p.attrs.get('data-native-chrome'),'hidden');
 p.window.__instagram.layout({headerHeight:0,storiesHeight:96,hideChrome:false});
 assert.equal(p.styles.get('--native-header-height'),'0px');assert.equal(p.styles.get('--native-stories-height'),'96px');assert.equal(p.attrs.get('data-native-chrome'),'web');
 p.window.__instagram.layout({headerHeight:Infinity});assert.equal(p.styles.get('--native-header-height'),'0px');
 assert.ok(p.posted.every(m=>typeof m.type==='string'));
});
test('Home sends Search, Profile and Messages to native without navigating its live page',()=>{
 const p=page({path:'/?variant=following'});
 for(const target of ['/explore/','/alice/','/direct/inbox/'])assert.equal(p.click(target),1);
 assert.equal(p.location.pathname,'/');
 assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/explore/','https://www.instagram.com/alice/','https://www.instagram.com/direct/inbox/']);
});
test('Home from another page is native; same-page variant links stay in the web view',()=>{
 for(const from of ['/explore/','/alice/','/direct/inbox/']){const p=page({path:from});assert.equal(p.click('/'),1);assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/']);}
 const home=page({path:'/?variant=following'});assert.equal(home.click('/?variant=past_posts'),0);assert.equal(home.of('navigate').length,0);
});
test('programmatic history changes to another page are performed natively before history changes',()=>{
 const p=page({path:'/'});p.history.pushState({},'','/explore/');
 assert.equal(p.location.pathname,'/');assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/explore/']);
 p.history.replaceState({},'','/reels/');assert.equal(p.location.pathname,'/');assert.equal(p.of('navigate').length,1);
 p.history.pushState({},'','/?variant=home');assert.equal(p.location.search,'?variant=home');
 assert.deepEqual(p.of('route').at(-1),{type:'route',path:'/',search:'?variant=home',title:''});
});
test('opening a post from a profile leaves the profile document untouched',()=>{
 const p=page({path:'/alice/'});assert.equal(p.click('/p/ABC/'),1);assert.equal(p.location.pathname,'/alice/');
 assert.equal(p.click('/alice/tagged/'),0);assert.equal(p.click('/alice/reels/'),1);assert.equal(p.of('navigate').length,1);
});
test('ready is reported once per document after the kind probe holds for several frames',()=>{
 const p=page({path:'/alice/'});let header=null;
 p.document.querySelector=s=>s==='main'?{querySelectorAll:()=>[],querySelector:()=>null,textContent:''}:s.startsWith('main header')?header:null;
 p.flush(3);assert.equal(p.of('ready').length,0);
 header={};p.flush(5);assert.equal(p.of('ready').length,0);p.flush(2);
 assert.deepEqual(p.of('ready'),[{type:'ready',kind:'profile'}]);assert.deepEqual(p.of('theme').at(-1),{type:'theme',backgroundRGB:[12,16,20]});
 p.listeners.mutation();p.flush(10);assert.equal(p.of('ready').length,1);
});
test('Search is ready only after a complete document and a stable original search control',()=>{
 const p=page({path:'/explore/'});let control={getBoundingClientRect:()=>({top:8,left:16,width:320,height:44})};
 p.document.querySelector=s=>s.startsWith('input[placeholder')?control:null;
 p.flush(30);assert.equal(p.of('ready').length,0);
 p.document.readyState='complete';p.flush(15);assert.equal(p.of('ready').length,0);
 control={getBoundingClientRect:()=>({top:8,left:16,width:320,height:44})};
 p.flush(15);assert.equal(p.of('ready').length,0);p.flush(10);assert.deepEqual(p.of('ready'),[{type:'ready',kind:'search'}]);
});
test('policy and refresh reach registered listeners; malformed policy JSON is ignored',()=>{
 const p=page();const seen=[];let refreshed=0;
 p.window.__instagram.on('policy',x=>seen.push(x.revision));p.window.__instagram.on('refresh',()=>refreshed++);
 p.window.__instagram.policy('{"handles":[],"revision":2}');p.window.__instagram.policy('{bad');p.window.__instagram.policy({handles:['a'],revision:3});p.window.__instagram.refresh();
 assert.deepEqual(seen,[2,3]);assert.equal(refreshed,1);assert.equal(p.window.__instagram.currentPolicy.revision,3);
});
test('the web tab bar is hidden and reports the signed-in avatar; the web header is hidden and titles the page',()=>{
 const p=page({path:'/direct/t/1/',boot:{headerHeight:44,hideChrome:true}});
 const tabAttrs=new Map(),headAttrs=new Map();
 const avatar={currentSrc:'https://scontent.cdninstagram.com/a.jpg'};
 const links=[{getAttribute:()=>'/'},{getAttribute:()=>'/explore/'},{getAttribute:()=>'/me/',querySelector:()=>avatar}].map(l=>({querySelector:()=>null,...l}));
 const tabBar={getAttribute:k=>tabAttrs.get(k)??null,setAttribute:(k,v)=>tabAttrs.set(k,v),querySelector:()=>null,querySelectorAll:s=>s==='a[href]'?links:[],getBoundingClientRect:()=>({top:760,height:50,width:400})};
 const explore={parentElement:tabBar};
 const heading={textContent:' Friend Name '};
 const header={getAttribute:k=>headAttrs.get(k)??null,setAttribute:(k,v)=>headAttrs.set(k,v),querySelector:s=>s==='h1,h2,[role="heading"]'?heading:null,getBoundingClientRect:()=>({top:0,width:400,height:44}),parentElement:null};
 const back={parentElement:header};
 p.document.querySelectorAll=s=>s.startsWith('a[href="/explore/"]')?[explore]:s.startsWith('svg[aria-label="Instagram"]')?[back]:[];
 p.listeners.mutation();p.flush(1);
 assert.equal(tabAttrs.get('data-native-hidden'),'tabbar');assert.equal(headAttrs.get('data-native-hidden'),'header');
 assert.deepEqual(p.of('avatar'),[{type:'avatar',url:avatar.currentSrc,username:'me'}]);
 assert.equal(p.of('route').at(-1).title,'Friend Name');
 p.listeners.mutation();p.flush(1);assert.equal(p.of('avatar').length,1);
});
test('wordmark shapes convert polygons and rects to path data and reject malformed points',()=>{
 const attrs=o=>k=>o[k];
 assert.equal(shapePath('path',attrs({d:'M0 0L1 1'})),'M0 0L1 1');
 assert.equal(shapePath('POLYGON',attrs({points:'0 106.31 15.08 106.31 15.08 8.46 0 11.82'})),'M0 106.31L15.08 106.31L15.08 8.46L0 11.82Z');
 assert.equal(shapePath('polyline',attrs({points:'0,0 2,3'})),'M0 0L2 3');
 assert.equal(shapePath('rect',attrs({x:'1',y:'2',width:'3',height:'4'})),'M1 2H4V6H1Z');
 for(const bad of [shapePath('polygon',attrs({points:'1 2 3'})),shapePath('polygon',attrs({points:'a b c d'})),shapePath('rect',attrs({width:'0',height:'4'})),shapePath('circle',attrs({}))])assert.equal(bad,null);
});
test('login content on any route (password form or logged-out landing) is reported as ready login',()=>{
 for(const [selector,path] of [['input[type="password"]','/?variant=following'],['a[href^="/accounts/login"]','/'],['a[href="/u/profile/"]','/?variant=following']]){
  const p=page({path});p.document.querySelector=s=>s.includes(selector)?{}:null;
  p.flush(7);assert.deepEqual(p.of('ready'),[{type:'ready',kind:'login'}],path);
 }
 const landing=page({path:'/?variant=following'});const login={textContent:' Log in ',closest:()=>null};
 landing.document.querySelectorAll=s=>s==='button,[role="button"]'?[{textContent:'Open Instagram',closest:()=>null},login]:[];
 landing.flush(7);assert.deepEqual(landing.of('ready'),[{type:'ready',kind:'login'}]);
 const menu=page({path:'/alice/'});menu.document.querySelectorAll=s=>s==='button,[role="button"]'?[{textContent:'Log in',closest:()=>({})}]:[];
 menu.flush(7);assert.equal(menu.of('ready').length,0);
 const signedIn=page({path:'/'});signedIn.document.querySelector=s=>s.includes('a[href^="/accounts/login"]')||s==='article'?{}:null;
 signedIn.flush(7);assert.equal(signedIn.of('ready').length,0);
});

// Navigation: cancelled history changes, tray login redirects, settings password pages.
function routeContent(p){
 const content={main:{querySelectorAll:()=>[],textContent:'',firstElementChild:{id:'profile'},querySelector:s=>s==='header'?content.header:s==='article'?content.article:null},header:{id:'header'},article:null};
 p.document.querySelector=s=>s==='main'?content.main:null;return content;
}
test('a cancelled history change that Instagram rendered in place is undone with a popstate for the unchanged location',()=>{
 const p=page({path:'/alice/'});const content=routeContent(p);
 p.history.pushState({entry:2},'','/p/ABC/');
 assert.equal(p.location.pathname,'/alice/');assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/p/ABC/']);
 // Instagram's router renders the post into the profile's main after its pushState returned.
 content.main.firstElementChild={id:'post'};content.header=null;content.article={id:'article'};
 p.flush(1);assert.equal(p.dispatched.length,0);p.flush(1);
 assert.equal(p.dispatched.length,1);assert.equal(p.dispatched[0].type,'popstate');assert.deepEqual(p.dispatched[0].state,{entry:1});
 assert.equal(p.location.pathname,'/alice/');
});
test('a cancelled history change that left the page alone dispatches nothing',()=>{
 const p=page({path:'/alice/'});routeContent(p);
 p.history.pushState({},'','/p/ABC/');p.flush(4);assert.equal(p.dispatched.length,0);
 p.history.replaceState({},'','/reels/');p.flush(4);assert.equal(p.dispatched.length,0);assert.equal(p.of('navigate').length,1);
});
test('content rendered before the cancelled pushState is compared with the state at the last touch',()=>{
 const p=page({path:'/?variant=following'});const content=routeContent(p);
 p.listeners['win:pointerdown']();
 content.main.firstElementChild={id:'thread'};
 p.history.pushState({},'','/direct/t/1/');p.flush(2);
 assert.equal(p.dispatched.length,1);assert.equal(p.location.pathname,'/');
 // Without a recent touch the baseline is the document at the cancel.
 const q=page({path:'/alice/'});const later=routeContent(q);later.main.firstElementChild={id:'changed-before'};
 q.history.pushState({},'','/bob/');q.flush(2);assert.equal(q.dispatched.length,0);
});
test('links are decided in the window capturing phase, before Instagram handlers',()=>{
 const p=page({path:'/alice/'});assert.equal(typeof p.listeners['win:click'],'function');assert.equal(p.listeners['doc:click'],undefined);
 assert.equal(p.click('https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2F'),0);assert.equal(p.of('navigate').length,0);
 assert.equal(p.click('/explore/search/keyword/?q=cats'),1);assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/explore/search/keyword/?q=cats']);
});
test('the tray never hands a login redirect to native',()=>{
 const p=page({path:'/',role:'tray'});
 p.history.replaceState({},'','/accounts/login/?next=%2F');p.history.pushState({},'','/challenge/1/');
 assert.equal(p.location.pathname,'/');assert.equal(p.of('navigate').length,0);
 p.history.pushState({},'','/alice/');assert.deepEqual(p.of('navigate').map(m=>m.url),['https://www.instagram.com/alice/']);
});
test('a settings page with password fields is ready as settings, not as login content',()=>{
 const p=page({path:'/accounts/password/change/'});p.document.querySelector=s=>s.includes('input[type="password"]')?{}:null;
 p.flush(7);assert.deepEqual(p.of('ready'),[{type:'ready',kind:'settings'}]);
 const reset=page({path:'/accounts/password/reset/'});reset.document.querySelector=s=>s.includes('input[type="password"]')?{}:null;
 reset.flush(7);assert.deepEqual(reset.of('ready'),[{type:'ready',kind:'login'}]);
});

// --- Home ---
function card(approved,pending,height){return {attrs:{'data-following-approved':approved,'data-following-pending':pending},height,
 getAttribute(k){return this.attrs[k]??null;},getBoundingClientRect(){return {top:0,height:this.height,width:400};}};}
test('Home reveals once the first post card at the top of the feed is approved and laid out',()=>{
 const p=page({path:'/',boot:{headerHeight:44,hideChrome:true,storiesSlot:true}});
 const collapsed=card('no','no',1),pending=card('no','yes',600),later=card('yes','no',600);
 p.document.querySelectorAll=s=>s==='[data-following-approved]'?[collapsed,pending,later]:[];
 // A later approved post is not enough while the top card is still unresolved (hidden but taking space).
 p.flush(12);assert.equal(p.of('ready').length,0);
 // Approved cards that have not been laid out yet do not count either.
 pending.attrs['data-following-approved']='yes';pending.attrs['data-following-pending']='no';pending.height=0;later.height=0;
 p.flush(12);assert.equal(p.of('ready').length,0);
 pending.height=600;p.flush(5);assert.equal(p.of('ready').length,0);p.flush(1);
 assert.deepEqual(p.of('ready'),[{type:'ready',kind:'home'}]);
});
test('Home still reveals for the caught-up card when no post is approved',()=>{
 const p=page({path:'/'});p.document.querySelector=s=>s==='[data-instagram-caught-up]'?{}:null;
 p.flush(6);assert.deepEqual(p.of('ready'),[{type:'ready',kind:'home'}]);
});
test('the tray closes Instagram\'s story viewer with its own Close control, else goes back',()=>{
 const p=page({path:'/stories/alice/123/',role:'tray'});let clicks=0,backs=0,icon=null;
 const control={click(){clicks++;}};
 p.document.querySelector=s=>s==='svg[aria-label="Close"]'?icon:null;p.history.back=()=>{backs++;};
 icon={closest:s=>s==='button,[role="button"],a[href]'?control:null};
 assert.equal(p.window.__instagramTray.closeViewer(),'clicked');assert.equal(clicks,1);assert.equal(backs,0);
 icon=null;assert.equal(p.window.__instagramTray.closeViewer(),'back');assert.equal(backs,1);
 p.location.pathname='/';assert.equal(p.window.__instagramTray.closeViewer(),'closed');assert.equal(clicks+backs,2);
 assert.equal(page({path:'/'}).window.__instagramTray,undefined);
});
test('the Home skin block scopes post-card rules to approved feed cards and uses no class selectors',()=>{
 const css=fs.readFileSync(path.join(__dirname,'../Resources/NativeSkin.css'),'utf8');
 const start=css.indexOf('/* === Home === */');assert.ok(start>0);
 // The block runs to the next "/* === Section === */" marker (Search, Notifications, Profile follow it).
 const next=css.indexOf('/* === ',start+1);
 const home=css.slice(start,next<0?css.length:next).replace(/\/\*[\s\S]*?\*\//g,'').replace(/url\("[^"]*"\)/g,'url()');
 const selectors=[...home.matchAll(/([^{}]+)\{/g)].map(m=>m[1].trim()).filter(s=>!s.startsWith('@'));
 assert.ok(selectors.length>10);
 for(const selector of selectors){
  for(const part of selector.split(/,(?![^(]*\))/).map(s=>s.trim())){
   assert.doesNotMatch(part.replace(/"[^"]*"/g,'""'),/\.[A-Za-z_-]/,'class selector: '+part);
   if(/\b(header|time|svg|form|a)\b/.test(part)&&!part.startsWith('[data-instagram-caught-up]'))assert.ok(part.startsWith('html[data-following-mode="feed"] [data-following-approved="yes"]'),'unscoped: '+part);
  }
 }
});

test('the strip a hidden fixed web header reserved is marked for collapse; ordinary spacing is left alone',()=>{
 const p=page({path:'/instagram/',boot:{headerHeight:44,hideChrome:true}});
 const el=(attrs,css)=>{const a=new Map(Object.entries(attrs));return {css,getAttribute:k=>a.has(k)?a.get(k):null,setAttribute:(k,v)=>a.set(k,v),hasAttribute:k=>a.has(k)};};
 const spacer=el({},{paddingTop:'60px'}),header=el({'data-native-hidden':'header'},{position:'fixed'});header.nextElementSibling=spacer;
 const tight=el({},{paddingTop:'12px'}),sticky=el({'data-native-hidden':'header'},{position:'sticky'}),after=el({},{paddingTop:'60px'});sticky.nextElementSibling=after;
 const plain=el({'data-native-hidden':'header'},{position:'fixed'});plain.nextElementSibling=tight;
 p.document.querySelectorAll=s=>s==='[data-native-hidden="header"]'?[header,sticky,plain]:[];
 p.context.getComputedStyle=n=>({display:'block',visibility:'visible',opacity:'1',position:'static',backgroundColor:'rgb(12, 16, 20)',paddingTop:'0px',...(n&&n.css)});
 p.listeners.mutation();p.flush(1);
 assert.equal(spacer.getAttribute('data-native-header-spacer'),'');
 assert.equal(after.getAttribute('data-native-header-spacer'),null);
 assert.equal(tight.getAttribute('data-native-header-spacer'),null);
 const css=fs.readFileSync(path.join(__dirname,'../Resources/NativeSkin.css'),'utf8');
 assert.match(css,/\[data-native-hidden="header"\] \+ \[data-native-header-spacer\] \{ padding-top: 0 !important; \}/);
});
