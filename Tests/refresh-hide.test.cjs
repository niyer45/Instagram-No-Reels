// Pull-to-refresh hiding in Resources/Bridge.js: the `refreshing` layout flag and its failsafe, `data-native-stories`,
// and detection of Instagram's own stories row (hidden while the native tray is active).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {h}=require('./fake-dom.cjs');
const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');

function page(pathname,build=()=>{},{boot={},search='?variant=following'}={}){
 const html=h('html'),body=h('body');html.appendChild(body);
 const listeners={},frames=[],posted=[],timers=[];
 const document={documentElement:html,body,readyState:'complete',title:'Instagram',activeElement:body,
  querySelector:s=>html.querySelector(s),querySelectorAll:s=>html.querySelectorAll(s),createElement:t=>h(t),elementsFromPoint:()=>[],
  addEventListener:(k,f)=>{(listeners['doc:'+k]=listeners['doc:'+k]||[]).push(f);}};
 const location={pathname,search,get href(){return 'https://www.instagram.com'+this.pathname+this.search;}};
 const window={innerWidth:390,innerHeight:844,scrollY:0,__instagramBoot:{role:'page',headerHeight:44,hideChrome:true,...boot},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},
  addEventListener(k,f){(listeners['win:'+k]=listeners['win:'+k]||[]).push(f);}};
 window.top=window;
 const context={window,document,location,history:{pushState(){},replaceState(){}},URL,WeakSet,Event:class{constructor(type){this.type=type;}},
  setTimeout:(f,ms)=>{timers.push({f,ms,live:true});return timers.length;},clearTimeout:id=>{if(timers[id-1])timers[id-1].live=false;},
  requestAnimationFrame:f=>frames.push(f),performance:{now:()=>0},
  getComputedStyle:n=>({display:'block',visibility:'visible',opacity:'1',position:n.css.position||'static',backgroundColor:'rgba(0, 0, 0, 0)',pointerEvents:'auto',paddingBottom:'0px',paddingTop:'0px',height:'auto'}),
  MutationObserver:class{constructor(f){listeners.mutation=f;}observe(){}}};
 const api={html,body,window,timers,posted};
 build(body,api);
 vm.runInNewContext(source,context);
 api.scan=()=>{listeners.mutation();for(let i=0;i<3;i++)for(const f of frames.splice(0))f();};
 api.scan();
 return api;
}
const REFRESHING='data-native-refreshing';
const link=(href,rect)=>h('a',{href},[],{rect});
const rowOf=(n=5,top=60)=>h('div',{},Array.from({length:n},(_,i)=>link('/stories/user'+(i+1)+'/1/',{top,left:12+i*76,width:72,height:72})),{rect:{top,left:0,width:390,height:100}});
const marked=el=>el.getAttribute('data-native-stories-row')!==null;

test('boot refreshing sets data-native-refreshing at document start and layout({refreshing:false}) removes it',()=>{
 const p=page('/',()=>{},{boot:{refreshing:true}});
 assert.equal(p.html.getAttribute(REFRESHING),'');
 p.window.__instagram.layout({headerHeight:44});
 assert.equal(p.html.getAttribute(REFRESHING),'','other layout values keep it');
 p.window.__instagram.layout({refreshing:false});
 assert.equal(p.html.getAttribute(REFRESHING),null);
 p.window.__instagram.layout({refreshing:true});
 assert.equal(p.html.getAttribute(REFRESHING),'');
 const quiet=page('/');assert.equal(quiet.html.getAttribute(REFRESHING),null);
});

test('the 25 s failsafe reveals a document native never cleared, and clearing cancels it',()=>{
 const p=page('/',()=>{},{boot:{refreshing:true}});
 const failsafe=p.timers.filter(t=>t.live&&t.ms===25000);
 assert.equal(failsafe.length,1);
 failsafe[0].f();
 assert.equal(p.html.getAttribute(REFRESHING),null);
 p.scan();assert.equal(p.html.getAttribute(REFRESHING),null,'stays revealed');
 const q=page('/',()=>{},{boot:{refreshing:true}});
 q.window.__instagram.layout({refreshing:false});
 assert.equal(q.timers.filter(t=>t.live&&t.ms===25000).length,0);
});

test('data-native-stories follows storiesSlot and storiesHeight on the page role only',()=>{
 const p=page('/',()=>{},{boot:{storiesSlot:true,storiesHeight:96}});
 assert.equal(p.html.getAttribute('data-native-stories'),'tray');
 p.window.__instagram.layout({storiesHeight:0});assert.equal(p.html.getAttribute('data-native-stories'),null);
 p.window.__instagram.layout({storiesHeight:90});assert.equal(p.html.getAttribute('data-native-stories'),'tray');
 assert.equal(page('/',()=>{},{boot:{storiesSlot:false,storiesHeight:96}}).html.getAttribute('data-native-stories'),null);
 assert.equal(page('/',()=>{},{boot:{storiesSlot:true,storiesHeight:0}}).html.getAttribute('data-native-stories'),null);
 assert.equal(page('/',()=>{},{boot:{role:'tray',storiesSlot:true,storiesHeight:96}}).html.getAttribute('data-native-stories'),null);
});

test('a full-width row of five story links is marked as the stories row, not hidden by itself',()=>{
 let row;
 const p=page('/',(body)=>{row=rowOf();body.appendChild(row);body.appendChild(h('main',{},[h('article',{},[],{rect:{top:160,width:390,height:500}})],{rect:{top:160,width:390,height:900}}));});
 assert.ok(marked(row));
 assert.equal(row.getAttribute('data-native-hidden'),null);
 assert.equal(p.body.children[1].getAttribute('data-native-stories-row'),null);
});

test('the outermost qualifying container is marked, not an inner wrapper',()=>{
 let outer,inner;
 page('/',(body)=>{inner=rowOf();outer=h('div',{},[inner],{rect:{top:60,left:0,width:390,height:110}});body.appendChild(outer);});
 assert.ok(marked(outer));assert.ok(!marked(inner));
});

test('story rings in cards, rows in approved cards, containers with a post link and other pages stay unmarked',()=>{
 let single,cardRow,mixed;
 page('/',(body)=>{
  single=link('/stories/alice/',{top:100,width:42,height:42});
  body.appendChild(h('article',{},[h('header',{},[single],{rect:{top:60,width:390,height:60}})],{rect:{top:60,width:390,height:500}}));
  cardRow=rowOf(5,600);
  body.appendChild(h('div',{'data-following-approved':'yes'},[cardRow],{rect:{top:600,width:390,height:150}}));
  mixed=h('div',{},[...rowOf(5,800).children,link('/p/ABC/',{top:800,width:10,height:10})],{rect:{top:800,left:0,width:390,height:100}});
  body.appendChild(mixed);
 });
 assert.ok(!marked(single.parentElement));assert.ok(!marked(cardRow));assert.ok(!marked(mixed));
 const profile=page('/alice/',(body)=>body.appendChild(rowOf()),{search:''});
 assert.equal(profile.html.querySelector('[data-native-stories-row]'),null);
});

test('too short, too tall or narrow containers and single items are not rows',()=>{
 for(const rect of [{top:60,left:0,width:390,height:20},{top:60,left:0,width:390,height:400},{top:60,left:0,width:150,height:100}]){
  const p=page('/',(body)=>{const r=rowOf();r.rect=rect;body.appendChild(r);});
  assert.equal(p.html.querySelector('[data-native-stories-row]'),null,JSON.stringify(rect));
 }
 const one=page('/',(body)=>body.appendChild(rowOf(1)));
 assert.equal(one.html.querySelector('[data-native-stories-row]'),null);
});

test('a mark is dropped once the container holds a post',()=>{
 let row;
 const p=page('/',(body)=>{row=rowOf();body.appendChild(row);});
 assert.ok(marked(row));
 row.appendChild(h('article'));p.scan();
 assert.ok(!marked(row));
});
