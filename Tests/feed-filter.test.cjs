const {test}=require('node:test');
const assert=require('node:assert/strict');
const {handle,official,profileHandle,code,classify,route,ingest,parse}=require('../Resources/FeedFilter.js');
const following=new Set(['alice']);
test('membership requires positive evidence and explicit negative overrides snapshot',()=>{
 assert.equal(classify({authors:['alice']},following),true);
 assert.equal(classify({authors:['alice']},new Set(),{author:'alice',following:true}),true);
 assert.equal(classify({authors:['alice']},following,{author:'alice',following:false}),false);
 assert.equal(classify({authors:['alice']},new Set()),false);
 assert.equal(classify({authors:['alice','bob']},following),true);
 assert.equal(classify({authors:[],caption:'alice'},following),false);
});
test('existing JSON media metadata distinguishes following from followers',()=>{
 const r=new Map();ingest({items:[{code:'ABC',user:{username:'alice',friendship_status:{following:true}},product_type:'feed',media_type:2},{shortcode:'DEF',owner:{username:'bob',edge_followed_by:{count:500}}}]},r);
 assert.equal(r.get('ABC').following,true);assert.equal(r.get('ABC').unknownVideo,false);assert.equal(r.get('DEF').following,null);
 ingest({item:{code:'ABC',user:{username:'alice',is_following:false}}},r);assert.equal(r.get('ABC').following,false);
});
test('ads nested injection, suggestions, Reels and unknown videos override following',()=>{
 for(const obj of [{is_ad:true},{product_type:'clips'},{media_type:2},{is_suggested:true}]){
  const r=new Map();ingest({code:'ABC',user:{username:'alice',is_following:true},...obj},r);
  assert.equal(classify({authors:['alice']},following,r.get('ABC')),false);
 }
 const r=new Map();ingest({ad_media:{code:'ABC',user:{username:'alice',is_following:true}}},r);assert.equal(r.get('ABC').bad,true);
 assert.equal(classify({authors:['alice'],video:true},following),false);
 assert.equal(classify({authors:['alice'],video:true},following,{author:'alice',following:true,unknownVideo:false}),true);
});
test('bounded parsing and exact official origins',()=>{
 assert.equal(parse('x'),false);assert.equal(parse(' '.repeat(1500001)),false);
 assert.equal(official('https://www.instagram.com/api/path'),true);
 for(const u of ['http://instagram.com/','https://evil.example/','https://instagram.com:8443/','https://u@instagram.com/'])assert.equal(official(u),false);
 assert.equal(profileHandle('/alice/'),'alice');assert.equal(profileHandle('/p/ABC/'),null);assert.equal(code('/p/ABC/'),'ABC');
});
test('original profile, inbox, stories and settings navigation preserved',()=>{
 for(const p of ['/alice/','/direct/inbox/','/stories/alice/','/accounts/edit/','/p/ABC/'])assert.notEqual(route(p),'blocked');
 for(const p of ['/reels/','/reel/ABC/','/tv/ABC/','/clips/'])assert.equal(route(p),'blocked');
});
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require.resolve('../Resources/FeedFilter.js'),'utf8');
function fixture({path='/',lang='en',rootPresent=true,mainPresent=true,password=false,articles=[],jsonScripts=[],fetchImpl=null,navLinks=[],loginLink=false}={}) {
  let observer;
  const events = {};
  const statuses = [];
  const attrs = new Map(lang ? [['lang',lang]] : []);
  const root = {getAttribute:k=>attrs.get(k)||null,setAttribute:(k,v)=>attrs.set(k,v),removeAttribute:k=>attrs.delete(k),appendChild:s=>{s.parentNode=root;root.styleText=s.textContent;}};
  const main = {contains:a=>articles.includes(a) && !a.outside,querySelectorAll:()=>articles.filter(a=>a.div).map(a=>({getAttribute:()=>'/p/ABC/',closest:()=>null,parentElement:a.linkParent||a}))};
  for(const a of articles)if(a.div)a.parentElement=main;
  const document = {
    documentElement:rootPresent?root:null,
    createElement:()=>({textContent:'',parentNode:null}),
    querySelector:s=>s==='main'?(mainPresent?main:null):s==='main a[href^="/accounts/login"]'?(loginLink?{}:null):s==='input[type="password"]'?(password?{}:null):null,
    querySelectorAll:s=>s==='article'?articles.filter(a=>!a.div):s==='script[type="application/json"]'?jsonScripts:s==='a[href]'?navLinks:[],addEventListener:(k,f)=>events[k]=f
  };
  const location = {protocol:'https:',port:'',hostname:'www.instagram.com',pathname:path,origin:'https://www.instagram.com',href:'https://www.instagram.com'+path};
  const window = {__followingPolicy:{handles:['alice'],revision:1},webkit:{messageHandlers:{followingStatus:{postMessage:p=>statuses.push(p)}}},addEventListener:(k,f)=>events[k]=f};
  if(fetchImpl)window.fetch=fetchImpl;window.top=window;
  let historyCalls=0,scrollCalls=0,now=0;const timers=[];window.innerHeight=800;window.scrollBy=()=>{scrollCalls++;};const context = {window,document,location,URL,Set,Date:{now:()=>now},setTimeout:fn=>{timers.push(fn);return timers.length;},Element:class {},queueMicrotask,MutationObserver:class {constructor(f){observer=f;}observe(){}},history:{pushState(){historyCalls++;},replaceState(){historyCalls++;}}};
  vm.runInNewContext(source,context);
  return {document,root,attrs,statuses,events,window,context,historyCalls:()=>historyCalls,scrollCalls:()=>scrollCalls,runTimer:async()=>{now+=1500;const fn=timers.shift();if(fn)fn();await Promise.resolve();},mutate:async()=>{observer();await Promise.resolve();}};
}
function post(author='alice',text='A photo') {
  const attributes = new Map();
  const p = {author,text,video:false,reel:false,header:true,outside:false,
    contains:a=>false,
    get textContent(){return this.text;},
    getAttribute:k=>attributes.get(k)||null,setAttribute:(k,v)=>attributes.set(k,v),
    querySelectorAll(s) {if(s==='header,[data-testid="sponsored-label"],[aria-label="Sponsored"]')return this.disclosure?[{querySelectorAll:()=>[{textContent:this.disclosure}]}]:[];if(s==='a[href]'||s==='a[href*="/p/"]') return [{getAttribute:()=>'/p/ABC/'},{getAttribute:()=>'/p/ABC/'}];if(s==='h2 a[href],h3 a[href]'&&this.heading)return [{getAttribute:()=>'/'+this.author+'/',textContent:this.author,closest:()=>null}];return [];},
    querySelector(s) {
      if(s==='img,video,a[href*="/p/"]'||s==='img,video')return {};
      if(s==='header,h2,h3')return this.header||this.heading?{}:null;
      if(s==='header') return this.header?{querySelectorAll:()=>[{getAttribute:()=>'/'+this.author+'/',textContent:this.author,closest:()=>null}],contains:()=>true}:null;
      if(s==='video') return this.video?{}:null;
      return this.reel?{}:null;
    }};
  return p;
}

test('actual DOM scan and observer revoke authors and video without membership evidence',async()=>{
 const a=post();const f=fixture({articles:[a]});assert.equal(a.getAttribute('data-following-approved'),'yes');
 a.author='bob';await f.mutate();assert.equal(a.getAttribute('data-following-approved'),'no');
 a.author='alice';a.video=true;await f.mutate();assert.equal(a.getAttribute('data-following-approved'),'no');
});
test('unknown attribution, ads and caption spoofs remain individually hidden',()=>{
 const a=post('bob','alice liked this');const b=post('alice','Sponsored');b.disclosure='Sponsored';const c=post();c.header=false;
 const f=fixture({articles:[a,b,c]});for(const p of [a,b,c])assert.equal(p.getAttribute('data-following-approved'),'no');
 assert.equal(f.attrs.get('data-following-mode'),'feed');
});
test('document-start root bootstrap and policy revocation',async()=>{
 const a=post();const f=fixture({rootPresent:false,articles:[a]});assert.equal(f.statuses.length,0);
 f.document.documentElement=f.root;await f.mutate();assert.equal(a.getAttribute('data-following-approved'),'yes');
 f.window.__followingPolicy={handles:[],revision:2};f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'no');assert.equal(f.statuses.at(-1).state,'needsFollowing');
});
test('initial application/json supplies automatic membership without imported list',()=>{
 const a=post();const f=fixture({articles:[a],jsonScripts:[{textContent:JSON.stringify({items:[{code:'ABC',user:{username:'alice',friendship_status:{following:true}}}]})}]});
 f.window.__followingPolicy={handles:[]};f.events['following-policy-change']();
 assert.equal(a.getAttribute('data-following-approved'),'yes');assert.equal(f.statuses.at(-1).metadataRecords,1);
});
test('fetch wrapper returns original promise and observes only official existing JSON',async()=>{
 const a=post();let calls=0;
 const response={url:'https://www.instagram.com/existing-response',headers:{get:k=>k==='content-type'?'application/json':null},clone:()=>({text:async()=>JSON.stringify({code:'ABC',user:{username:'alice',is_following:true}})})};
 const promise=Promise.resolve(response);
 const f=fixture({articles:[a],fetchImpl:()=>{calls++;return promise;}});f.window.__followingPolicy={handles:[]};f.events['following-policy-change']();
 assert.equal(a.getAttribute('data-following-approved'),'no');assert.equal(f.window.fetch('/existing-response'),promise);
 await Promise.resolve();await Promise.resolve();await Promise.resolve();await Promise.resolve();
 assert.equal(calls,1);assert.equal(a.getAttribute('data-following-approved'),'yes');
 assert.equal(f.statuses.at(-1).haveFollowing,true);
});
test('headerless heading attribution and modern div post candidates are recognized',()=>{
 const a=post();a.header=false;a.heading=true;a.div=true;
 const f=fixture({articles:[a]});assert.equal(a.getAttribute('data-following-approved'),'yes');assert.equal(f.statuses.at(-1).postCandidates,1);
});
test('membership-null metadata requests evidence, language hides only posts, inbox articles preserved',()=>{
 const a=post();const f=fixture({articles:[a],jsonScripts:[{textContent:JSON.stringify({code:'ABC',user:{username:'alice'}})}]});
 f.window.__followingPolicy={handles:[]};f.events['following-policy-change']();assert.equal(f.statuses.at(-1).reason,'following-unavailable');
 const b=post();const g=fixture({lang:'fr',articles:[b]});assert.equal(b.getAttribute('data-following-approved'),'no');assert.equal(g.attrs.get('data-following-mode'),'feed');assert.equal(g.statuses.at(-1).reason,'unsupported-language');
 const c=post();const h=fixture({path:'/direct/inbox/',articles:[c]});assert.equal(c.getAttribute('data-following-approved'),null);
});
test('fresh follow evidence replaces stale negative evidence and changed JSON scripts reparse',()=>{
 const r=new Map();ingest({code:'ABC',user:{username:'alice',is_following:false}},r);ingest({code:'ABC',user:{username:'alice',is_following:true}},r);assert.equal(r.get('ABC').following,true);
 const script={textContent:JSON.stringify({code:'ABC',user:{username:'alice',is_following:false}})};const a=post();const f=fixture({articles:[a],jsonScripts:[script]});assert.equal(a.getAttribute('data-following-approved'),'no');
 script.textContent=JSON.stringify({code:'ABC',user:{username:'alice',is_following:true}});f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'yes');
});
test('organic caption label words are not ad disclosures',()=>{
 const a=post('alice','I hate sponsored posts and advertisements. Suggested for you is annoying.');
 const f=fixture({articles:[a]});assert.equal(a.getAttribute('data-following-approved'),'yes');
 a.disclosure='Sponsored';f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'no');
});
test('profile grid tiles remain untouched while feed divs are filtered',()=>{
 const a=post();a.div=true;a.header=false;
 const f=fixture({path:'/alice/',articles:[a]});assert.equal(a.getAttribute('data-following-approved'),null);assert.equal(f.statuses.at(-1).postCandidates,0);
});
test('partial video records preserve known product and following, fresh following wins',()=>{
 const r=new Map();ingest({code:'ABC',product_type:'feed',media_type:2,user:{username:'alice',is_following:true}},r);
 ingest({code:'ABC',media_type:2,user:{username:'alice'}},r);assert.equal(r.get('ABC').unknownVideo,false);assert.equal(r.get('ABC').following,true);
 ingest({code:'ABC',user:{username:'alice',is_following:false}},r);assert.equal(r.get('ABC').following,false);
 ingest({code:'ABC',user:{username:'alice',is_following:true}},r);assert.equal(r.get('ABC').following,true);
});
test('GraphQL followed_by_viewer indicates membership, follows_viewer does not',()=>{
 const r=new Map();ingest({shortcode:'ABC',owner:{username:'alice',followed_by_viewer:true,follows_viewer:false}},r);assert.equal(r.get('ABC').following,true);
 ingest({shortcode:'DEF',owner:{username:'bob',follows_viewer:true}},r);assert.equal(r.get('DEF').following,null);
});
test('placement suggestion clears on explicit safe feed, intrinsic ads stay excluded, zero ad ID safe',()=>{
 const r=new Map();ingest({suggested_posts:[{code:'ABC',user:{username:'alice',is_following:true}}]},r);assert.equal(r.get('ABC').bad,true);
 ingest({code:'ABC',is_suggested:false,user:{username:'alice'}},r);assert.equal(r.get('ABC').bad,false);
 ingest({code:'ABC',is_ad:true,user:{username:'alice'}},r);ingest({code:'ABC',user:{username:'alice'}},r);assert.equal(r.get('ABC').bad,true);
 ingest({media_or_ad:{code:'DEF',ad_id:'0',user:{username:'bob',is_following:true}}},r);assert.equal(r.get('DEF').bad,false);
});
test('avatar in first attribution row does not disqualify followed author',()=>{
 const a=post();a.header=false;a.firstElementChild={querySelector:()=>null,querySelectorAll:()=>[{getAttribute:()=>'/alice/',textContent:'alice'}]};
 const f=fixture({articles:[a]});assert.equal(a.getAttribute('data-following-approved'),'yes');
});
test('div detection climbs past media caption links to validated author boundary',()=>{
 const card=post();card.div=true;card.heading=true;card.header=false;
 const inner=post('bob','caption');inner.header=false;inner.parentElement=card;card.linkParent=inner;card.contains=()=>true;
 const f=fixture({articles:[card]});assert.equal(card.getAttribute('data-following-approved'),'yes');assert.equal(f.statuses.at(-1).postCandidates,1);
});
test('bounded parser accepts anti-prefix JSON and newline incremental records',()=>{
 const r=new Map();assert.equal(parse('  for (;;);\n'+JSON.stringify({code:'ABC',user:{username:'alice',is_following:true}}),r),true);
 assert.equal(parse(JSON.stringify({code:'DEF',user:{username:'bob',is_following:false}})+'\n'+JSON.stringify({code:'GHI',user:{username:'carol'}}),r),true);
 assert.equal(r.get('ABC').following,true);assert.equal(r.get('DEF').following,false);assert.equal(r.get('GHI').following,null);
});
test('javascript MIME existing response ingests and diagnostics contain structure only',async()=>{
 const response={url:'https://www.instagram.com/existing-response',headers:{get:k=>k==='content-type'?'application/x-javascript':null},clone:()=>({text:async()=>JSON.stringify({code:'ABC',media_type:1,user:{username:'alice',is_following:true,friendship_status:{following:true}}})})};
 const a=post();const f=fixture({articles:[a],fetchImpl:()=>Promise.resolve(response)});f.window.fetch('/existing-response');
 await Promise.resolve();await Promise.resolve();await Promise.resolve();await Promise.resolve();
 const d=f.window.__instagramFilterDiagnostics();assert.equal(d.recordFollowingTrue,1);assert.equal(d.matchedRecords,1);
 assert.ok(d.schemas[0].userFields.includes('is_following'));
 const text=JSON.stringify(d);assert.equal(text.includes('alice'),false);assert.equal(text.includes('ABC'),false);assert.equal(text.includes('https:'),false);
});
test('username-prefixed post links match exact shortcode without accepting arbitrary suffixes or external URLs',()=>{
 assert.equal(code('/alice/p/ABC/'),'ABC');assert.equal(code('/alice/p/ABC/comments/'),'ABC');assert.equal(code('https://evil.example/alice/p/ABC/'),null);
 assert.equal(code('/accounts/p/ABC/'),null);
});
test('collaborator header allows metadata owner among attribution candidates only',()=>{
 assert.equal(classify({authors:['alice','bob']},new Set(),{author:'bob',following:true}),true);
 assert.equal(classify({authors:['alice','bob']},following,{author:'carol',following:true}),false);
 assert.equal(classify({authors:['alice','bob']},following,{author:'bob',following:false}),false);
});
test('nested modern attribution row with avatars and collaborators excludes later comment links',()=>{
 const a=post();a.header=false;
 const link=name=>({getAttribute:()=>'/'+name+'/',textContent:name});
 const row={tagName:'DIV',children:[],querySelector:()=>null,querySelectorAll:()=>[link('alice'),link('bob')]};
 const wrapper={tagName:'DIV',children:[row,{tagName:'DIV'},{tagName:'DIV'}],querySelector:()=>null,querySelectorAll:()=>[link('alice'),link('bob'),...Array.from({length:6},()=>link('carol'))]};
 a.children=[wrapper];a.firstElementChild=wrapper;
 const old=a.querySelectorAll;a.querySelectorAll=function(s){if(s==='a[href]')return [{getAttribute:()=>'/bob/p/ABC/'}];return old.call(this,s);};
 const f=fixture({articles:[a],jsonScripts:[{textContent:JSON.stringify({code:'ABC',user:{username:'bob',is_following:true}})}]});
 f.window.__followingPolicy={handles:[]};f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'yes');
});
test('public post identity subroutes map only recognized exact suffixes',()=>{
 for(const suffix of ['liked_by/','comments/','c/123/','embed/'])assert.equal(code('/p/ABC/'+suffix),'ABC');
 for(const suffix of ['unknown/','comments/123/','c/123/extra/'])assert.equal(code('/p/ABC/'+suffix),null);
 assert.equal(code('/bob/p/ABC/liked_by/'),'ABC');
});
test('subroute identity requires scoped attribution; captions and multiple post IDs cannot approve',()=>{
 const a=post();const prior=a.querySelectorAll;a.querySelectorAll=function(s){if(s==='a[href]')return [{getAttribute:()=>'/alice/p/ABC/liked_by/'}];return prior.call(this,s);};
 const f=fixture({articles:[a],jsonScripts:[{textContent:JSON.stringify({code:'ABC',user:{username:'alice',is_following:true}})}]});assert.equal(a.getAttribute('data-following-approved'),'yes');
 a.header=false;a.text='alice caption';f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'no');
 a.header=true;a.querySelectorAll=function(s){if(s==='a[href]')return [{getAttribute:()=>'/p/ABC/'},{getAttribute:()=>'/p/DEF/'}];return prior.call(this,s);};f.events['following-policy-change']();assert.equal(a.getAttribute('data-following-approved'),'no');
});
test('blocked SPA history destinations are rejected before navigation; other history preserved',()=>{
 const f=fixture();f.context.history.pushState({},'','/reels/');f.context.history.replaceState({},'','/clips/');assert.equal(f.historyCalls(),0);
 f.context.history.pushState({},'','/direct/inbox/');assert.equal(f.historyCalls(),1);
});
test('logged-out landing recognized by original login link without password field',()=>{
 const f=fixture({loginLink:true});assert.equal(f.statuses.at(-1).state,'login');assert.equal(f.statuses.at(-1).reason,'login');
});
test('Following hint uses only exact official site-provided root variant link',()=>{
 const link=href=>({getAttribute:()=>href});
 const f=fixture({navLinks:[link('/?variant=following&unwanted=private-value')]});const d=f.window.__instagramFilterDiagnostics();assert.equal(d.followingFeedAvailable,true);assert.equal(d.followingRoute,'/?variant=following');assert.equal(JSON.stringify(d).includes('private-value'),false);
 const g=fixture({navLinks:[link('https://evil.example/?variant=following'),link('/alice/?variant=following')]});assert.equal(g.window.__instagramFilterDiagnostics().followingFeedAvailable,false);
});
test('SECTION caption links never become author attribution',()=>{
 const a=post();a.header=false;const caption={tagName:'SECTION',children:[],querySelector:()=>null,querySelectorAll:()=>[{getAttribute:()=>'/alice/',textContent:'alice'}]};
 a.children=[caption];a.firstElementChild=caption;const f=fixture({articles:[a]});assert.equal(a.getAttribute('data-following-approved'),'no');
});
test('exact accessible Reels buttons blocked, caption words and unrelated buttons preserved',()=>{
 const f=fixture();let prevented=0;
 const button={getAttribute:()=> 'Reels'};const target=new f.context.Element();target.closest=s=>s==='button,[role="button"]'?button:null;
 f.events.click({target,preventDefault(){prevented++;},stopImmediatePropagation(){}});assert.equal(prevented,1);
 button.getAttribute=()=> 'Share sponsored reels discussion';f.events.click({target,preventDefault(){prevented++;},stopImmediatePropagation(){}});assert.equal(prevented,1);
});
test('feed filtering never scrolls the page automatically',async()=>{
 const f=fixture({articles:[post('bob')]});
 for(let i=0;i<8;i++)await f.runTimer();assert.equal(f.scrollCalls(),0);
 assert.ok(f.root.styleText.includes('overflow-anchor:none!important'));
});
test('intrinsically excluded Reels without membership do not report following-unavailable',()=>{
 const a=post();a.reel=true;const f=fixture({articles:[a]});f.window.__followingPolicy={handles:[]};f.events['following-policy-change']();
 assert.notEqual(f.statuses.at(-1).reason,'following-unavailable');assert.equal(a.getAttribute('data-following-approved'),'no');
});

test('caught-up requires dated eligible older feed content, never missing data or Reels',()=>{
 const {caughtUp}=require('../Resources/FeedFilter.js');const now=2000000;
 assert.equal(caughtUp([],now),false);
 assert.equal(caughtUp([{following:true,takenAt:now-86400}],now),false);
 assert.equal(caughtUp([{following:true,takenAt:now-3*86400,reel:true}],now),false);
 assert.equal(caughtUp([{following:false,takenAt:now-3*86400}],now),false);
 assert.equal(caughtUp([{following:true,takenAt:now-3*86400}],now),true);
});

test('header customization accepts only leaf title text and never a page container',()=>{
 const {safeHeaderTitle}=require('../Resources/FeedFilter.js');
 assert.equal(safeHeaderTitle({tagName:'DIV',children:[],textContent:'Following'}),false);
 assert.equal(safeHeaderTitle({tagName:'SPAN',children:[{}],textContent:'Following'}),false);
 assert.equal(safeHeaderTitle({tagName:'SPAN',children:[],textContent:'Following'}),true);
 assert.equal(safeHeaderTitle({tagName:'SPAN',children:[],textContent:'Some Following caption'}),false);
});

test('unresolved cards retain layout until authoritative membership arrives',async()=>{
 const a=post('bob');const script={textContent:'{}'};const f=fixture({articles:[a],jsonScripts:[script]});
 assert.equal(a.getAttribute('data-following-approved'),'no');assert.equal(a.getAttribute('data-following-pending'),'yes');
 script.textContent=JSON.stringify({code:'ABC',user:{username:'bob',is_following:false},media_type:1});await f.mutate();
 assert.equal(a.getAttribute('data-following-approved'),'no');assert.equal(a.getAttribute('data-following-pending'),'no');
});

test('intentional profile and post browsing permits unfollowed-self and older photos while Reels stay blocked',()=>{
 assert.equal(classify({authors:['me']},new Set(),{author:'me',following:false,takenAt:1},true),true);
 assert.equal(classify({authors:['me'],reel:true},new Set(),{author:'me',following:false},true),false);
 assert.equal(classify({authors:['me']},new Set(),{author:'me',following:false},false),false);
});

test('Home click from profile always navigates to the Following feed',()=>{
 const f=fixture({path:'/me/'});let assigned=null,prevented=0;f.context.location.assign=url=>assigned=url;
 const a={href:'https://www.instagram.com/'};const target=new f.context.Element();target.closest=selector=>selector==='a[href]'?a:null;
 f.events.click({target,preventDefault(){prevented++},stopImmediatePropagation(){}});
 assert.equal(assigned,'https://www.instagram.com/?variant=following');assert.equal(prevented,1);
});

test('search is restored but its media grid is suppressed and Reels stay blocked',()=>{
 assert.equal(route('/explore/'),'search');assert.equal(route('/explore/search/'),'search');
 const f=fixture({path:'/explore/'});assert.equal(f.attrs.get('data-following-mode'),'search');
 assert.ok(f.root.styleText.includes('data-instagram-search-media'));
 assert.equal(route('/reels/'),'blocked');
});
test('continuous older feed loads only on user downward scrolling near its cutoff',()=>{
 const {shouldContinueScroll}=require('../Resources/FeedFilter.js');
 assert.equal(shouldContinueScroll({mode:'feed',down:true,nearEnd:true,reachedCutoff:true}),true);
 for(const x of [{mode:'search'},{down:false},{nearEnd:false},{reachedCutoff:false}])assert.equal(shouldContinueScroll({mode:'feed',down:true,nearEnd:true,reachedCutoff:true,...x}),false);
});

test('search hides a post tile while leaving account search results untouched',()=>{
 const marks=new Map();const tile={querySelector:()=>null,setAttribute:(k,v)=>marks.set(k,v)};
 const media={getAttribute:()=>'/p/ABC/',closest:()=>null,parentElement:tile};
 const accountMarks=new Map();const account={getAttribute:()=>'/alice/',closest:()=>null,parentElement:{querySelector:()=>null,setAttribute:(k,v)=>accountMarks.set(k,v)}};
 fixture({path:'/explore/',navLinks:[media,account]});assert.equal(marks.has('data-instagram-search-media'),true);assert.equal(accountMarks.size,0);
});

test('Home interception does not overwrite Instagram older-feed links',()=>{
 const f=fixture({path:'/?variant=following'});let assigned=null,prevented=0;f.context.location.assign=url=>assigned=url;
 const target=new f.context.Element();target.closest=s=>s==='a[href]'?{href:'https://www.instagram.com/?variant=past_posts'}:null;
 f.events.click({target,preventDefault(){prevented++},stopImmediatePropagation(){}});assert.equal(assigned,null);assert.equal(prevented,0);
});

test('pagination assist is limited to small empty end sentinels outside posts',()=>{
 const {paginationTarget}=require('../Resources/FeedFilter.js');const x={tag:'DIV',underMain:true,inPost:false,empty:true,media:false,height:0,top:730,bottom:730,viewport:778};
 assert.equal(paginationTarget(x),true);
 for(const change of [{underMain:false},{inPost:true},{media:true},{empty:false},{height:124},{top:2000,bottom:2000},{tag:'IMG'}])assert.equal(paginationTarget({...x,...change}),false);
});


test('Search media markers are cleared when navigating to Profile and Home',async()=>{
 const marks=new Map();const tile={querySelector:()=>null,setAttribute:(k,v)=>marks.set(k,v),removeAttribute:k=>marks.delete(k)};
 const media={getAttribute:()=>'/p/ABC/',closest:()=>null,parentElement:tile};
 const f=fixture({path:'/explore/',navLinks:[media]});
 assert.equal(marks.has('data-instagram-search-media'),true);
 const original=f.document.querySelectorAll.bind(f.document);
 f.document.querySelectorAll=selector=>selector==='[data-instagram-search-media]'?(marks.has('data-instagram-search-media')?[tile]:[]):original(selector);
 for(const path of ['/alice/','/']){
  f.context.location.pathname=path;f.context.location.href='https://www.instagram.com'+path;
  await f.mutate();assert.equal(marks.has('data-instagram-search-media'),false);
 }
});


test('Home sends Search, Profile and Messages to native browsing without navigating its live page',()=>{
 const f=fixture({path:'/'});const opened=[];
 f.window.webkit.messageHandlers.followingOpenDestination={postMessage:x=>opened.push(x.url)};
 for(const path of ['/explore/','/alice/','/direct/inbox/']){
  let prevented=0;const target=new f.context.Element();target.closest=s=>s==='a[href]'?{href:'https://www.instagram.com'+path}:null;
  f.events.click({target,preventDefault(){prevented++},stopImmediatePropagation(){}});
  assert.equal(prevented,1);assert.equal(f.context.location.pathname,'/');
 }
 assert.deepEqual(opened,['https://www.instagram.com/explore/','https://www.instagram.com/alice/','https://www.instagram.com/direct/inbox/']);
});

test('Home from browsing requests native restoration without a document navigation',()=>{
 for(const path of ['/explore/','/alice/','/direct/inbox/']){
  const f=fixture({path});const opened=[];let assigned=false;
  f.window.webkit.messageHandlers.followingOpenDestination={postMessage:x=>opened.push(x.url)};
  f.context.location.assign=()=>assigned=true;
  const target=new f.context.Element();target.closest=s=>s==='a[href]'?{href:'https://www.instagram.com/'}:null;
  f.events.click({target,preventDefault(){},stopImmediatePropagation(){}});
  assert.deepEqual(opened,['https://www.instagram.com/']);assert.equal(assigned,false);
 }
});

test('Home catches programmatic tab routing before changing its history',()=>{
 const f=fixture({path:'/'});const opened=[];
 f.window.webkit.messageHandlers.followingOpenDestination={postMessage:x=>opened.push(x.url)};
 f.context.history.pushState({},'', '/explore/');
 assert.equal(f.historyCalls(),0);assert.deepEqual(opened,['https://www.instagram.com/explore/']);
});


test('Search shows the bundled static image only while idle and removes it for queries and other routes',async()=>{
 const f=fixture({path:'/explore/'});let banner=null,image=null;const input={value:'',getBoundingClientRect:()=>({bottom:56})};
 const original=f.document.querySelector.bind(f.document);
 f.document.querySelector=selector=>selector==='[data-instagram-search-caught-up]'?banner:selector.startsWith('input[placeholder')?input:original(selector);
 f.document.body={appendChild:node=>banner=node};
 f.document.createElement=tag=>tag==='img'?(image={}):{setAttribute(){},appendChild(){},style:{setProperty(){}},remove(){banner=null;}};
 f.window.__followingPolicy.searchCaughtUpImage='data:image/svg+xml;base64,PHN2Zy8+';
 await f.mutate();assert.ok(banner);assert.equal(image.src,f.window.__followingPolicy.searchCaughtUpImage);assert.equal(f.attrs.get('data-instagram-search-idle'),'yes');
 f.document.activeElement=input;await f.mutate();assert.equal(banner,null);
 f.document.activeElement=null;await f.mutate();assert.ok(banner);
 input.value='alice';await f.mutate();assert.equal(banner,null);assert.equal(f.attrs.has('data-instagram-search-idle'),false);
 input.value='';await f.mutate();assert.ok(banner);
 input.closest=()=>input;input.matches=()=>true;f.events.focusin({target:input});assert.equal(banner,null);await f.mutate();assert.equal(banner,null);
 f.context.location.pathname='/alice/';f.context.location.href='https://www.instagram.com/alice/';await f.mutate();assert.equal(banner,null);assert.equal(f.attrs.has('data-instagram-search-idle'),false);
});


test('Profile tab taps request native cache selection even when Profile is already active',()=>{
 for(const path of ['/','/explore/','/alice/']){
  const f=fixture({path});const opened=[];let prevented=0;
  f.window.webkit.messageHandlers.followingOpenDestination={postMessage:x=>opened.push(x)};
  const link={href:'https://www.instagram.com/alice/',closest:s=>s==='[data-instagram-bottom]'?{}:null};
  const target=new f.context.Element();target.closest=s=>s==='a[href]'?link:null;
  f.events.click({target,preventDefault(){prevented++},stopImmediatePropagation(){}});
  assert.equal(opened.length,1);assert.equal(opened[0].tab,'profile');assert.equal(opened[0].url,link.href);assert.equal(prevented,1);
 }
});

test('Opening a post from the pinned Profile leaves its cached document untouched',()=>{
 const f=fixture({path:'/alice/'});f.window.__instagramPinnedProfile=true;const opened=[];
 f.window.webkit.messageHandlers.followingOpenDestination={postMessage:x=>opened.push(x.url)};
 const link={href:'https://www.instagram.com/p/ABC/',closest:()=>null};
 const target=new f.context.Element();target.closest=s=>s==='a[href]'?link:null;
 f.events.click({target,preventDefault(){},stopImmediatePropagation(){}});
 assert.deepEqual(opened,[link.href]);assert.equal(f.context.location.pathname,'/alice/');assert.equal(f.historyCalls(),0);
});


test('Search reveals only after a complete document and a stable original search control',async()=>{
 const f=fixture({path:'/explore/'});const frames=[];const ready=[];let control={getBoundingClientRect:()=>({top:8,left:16,width:320,height:44})};
 f.context.requestAnimationFrame=fn=>frames.push(fn);f.context.getComputedStyle=()=>({display:'block',visibility:'visible',opacity:'1',backgroundColor:'rgb(12, 16, 20)'});
 f.window.webkit.messageHandlers.followingSearchReady={postMessage:x=>ready.push(x)};
 const original=f.document.querySelector.bind(f.document);
 f.document.querySelector=s=>s.startsWith('input[placeholder')?control:original(s);
 f.document.readyState='loading';await f.mutate();
 for(let i=0;i<30;i++)frames.shift()();assert.equal(ready.length,0);
 f.document.readyState='complete';for(let i=0;i<15;i++)frames.shift()();assert.equal(ready.length,0);
 control={getBoundingClientRect:()=>({top:8,left:16,width:320,height:44})};
 for(let i=0;i<15;i++)frames.shift()();assert.equal(ready.length,0);
 for(let i=0;i<10;i++)frames.shift()();assert.equal(ready.length,1);
 await f.mutate();assert.equal(frames.length,0);assert.equal(ready.length,1);
});
