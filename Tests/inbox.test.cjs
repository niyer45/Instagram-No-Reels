// Inbox state detection of Resources/Bridge.js (Tabs region): `inboxState` for message notifications,
// run against a fixture inbox DOM built with the shared fake DOM.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {h}=require('./fake-dom.cjs');
const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');

/** Loads Bridge.js on `pathname`; `build(body)` makes the DOM. A manual clock and timer queue drive the throttle. */
function page(pathname,build,{readyState='complete'}={}){
 const html=h('html'),body=h('body');html.appendChild(body);
 const posted=[],listeners={},frames=[],timers=[],windowEvents={};let clock=0;
 const document={documentElement:html,body,readyState,title:'Instagram',activeElement:body,
  querySelector:s=>html.querySelector(s),querySelectorAll:s=>html.querySelectorAll(s),createElement:t=>h(t),addEventListener(){}};
 const location={pathname,search:'',get href(){return 'https://www.instagram.com'+this.pathname;}};
 const window={innerWidth:390,innerHeight:844,__instagramBoot:{role:'page',headerHeight:0,hideChrome:true},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},addEventListener(type,f){(windowEvents[type]=windowEvents[type]||[]).push(f);}};
 window.top=window;
 const observers=[];
 const context={window,document,location,history:{pushState(){},replaceState(){}},URL,WeakSet,Event:class{constructor(type){this.type=type;}},
  setTimeout:(f,ms)=>{timers.push({f,at:clock+(ms||0)});return timers.length;},requestAnimationFrame:f=>frames.push(f),performance:{now:()=>clock},
  getComputedStyle:n=>({display:'block',visibility:'visible',opacity:'1',position:n.css.position||'static',backgroundColor:n.css.backgroundColor||'rgba(0, 0, 0, 0)',pointerEvents:'auto',paddingBottom:'0px',paddingTop:'0px',height:'auto',fontWeight:n.css.fontWeight||'400'}),
  MutationObserver:class{constructor(f){this.f=f;observers.push(f);listeners.mutation=f;}observe(){}}};
 build(body,document);
 vm.runInNewContext(source,context);
 const flush=()=>{for(let i=0;i<3;i++){const run=frames.splice(0);for(const f of run)f();}};
 const advance=(ms,{frames:runFrames=true}={})=>{clock+=ms;for(const t of timers.splice(0)){if(t.at<=clock)t.f();else timers.push(t);}if(runFrames)flush();};
 const mutate=()=>{for(const f of observers)f();flush();};
 mutate();
 const states=()=>posted.filter(m=>m.type==='inboxState');
 /** The document completes: readyState becomes `complete` and window `load` fires (no mutation, no animation frame). */
 const complete=()=>{document.readyState='complete';for(const f of windowEvents.load||[])f();};
 return {body,posted,states,mutate,advance,html,complete};
}

const bold={fontWeight:'600'};
/** A row link: title, preview, time, and optional extras (an aria-labelled badge, a dot). */
function row(id,{title='Alice',preview='see you soon',unread='none',href}={}){
 const kids=[h('img',{alt:''}),h('span',{},[],{text:title}),h('span',{},[],{text:preview,css:unread==='bold'?bold:{}}),h('span',{},[],{text:'2h'})];
 if(unread==='label')kids.push(h('div',{'aria-label':'Unread'}));
 if(unread==='dot')kids.push(h('div',{},[],{rect:{width:8,height:8},css:{backgroundColor:'rgb(0, 149, 246)'}}));
 return h('a',{href:href||`/direct/t/${id}/`},kids);
}
const inbox=(...rows)=>body=>body.appendChild(h('main',{},rows));

test('an inbox page posts inboxState with id, unread and name for each thread row',()=>{
 const p=page('/direct/inbox/',inbox(row('111',{title:'Alice',unread:'label'}),row('222',{title:'Bob'}),row('333',{title:'Cy',unread:'dot'}),row('444',{title:'Di',unread:'bold'})));
 assert.equal(p.states().length,1);
 assert.deepEqual(JSON.parse(JSON.stringify(p.states()[0].threads)),[
  {id:'111',unread:true,name:'Alice'},{id:'222',unread:false,name:'Bob'},{id:'333',unread:true,name:'Cy'},{id:'444',unread:true,name:'Di'}]);
});

test('read rows are not unread: a non-blue dot-sized element and a regular preview do not count',()=>{
 const grey=h('a',{href:'/direct/t/555/'},[h('span',{},[],{text:'Eve'}),h('span',{},[],{text:'ok',css:{fontWeight:'400'}}),h('div',{},[],{rect:{width:8,height:8},css:{backgroundColor:'rgb(120, 120, 120)'}})]);
 const p=page('/direct/inbox/',inbox(grey));
 assert.equal(p.states()[0].threads[0].unread,false);
});

test('names are trimmed and cut to 80 characters; a row without text has an empty name',()=>{
 const long='  '+'x'.repeat(120)+'  ';
 const bare=h('a',{href:'/direct/t/777/'},[h('img',{alt:''})]);
 const p=page('/direct/inbox/',inbox(row('666',{title:long}),bare));
 const [a,b]=p.states()[0].threads;
 assert.equal(a.name,'x'.repeat(80));assert.equal(b.name,'');
});

test('at most 50 threads are reported, duplicates and foreign links are skipped',()=>{
 const rows=[];for(let i=0;i<70;i++)rows.push(row(String(1000+i)));
 rows.splice(3,0,row('1000'),row('9',{href:'https://evil.example/direct/t/9/'}),h('a',{href:'/direct/t/bad id/'},[h('span',{},[],{text:'x'})]),h('a',{href:'/direct/inbox/'},[h('span',{},[],{text:'y'})]));
 const p=page('/direct/inbox/',inbox(...rows));
 const threads=p.states()[0].threads;
 assert.equal(threads.length,50);
 assert.equal(new Set(threads.map(t=>t.id)).size,50);
 assert.ok(threads.every(t=>/^[A-Za-z0-9_.-]+$/.test(t.id)));
});

test('no emission on non-inbox routes, threads, logged-out or empty inboxes',()=>{
 for(const route of ['/','/explore/','/alice/','/accounts/activity/','/direct/t/111/','/p/ABC/']){
  assert.equal(page(route,inbox(row('111',{unread:'label'}))).states().length,0,route);
 }
 assert.equal(page('/direct/inbox/',inbox()).states().length,0,'no thread rows, nothing to report');
});

test('nothing is posted before the document is complete',()=>{
 assert.equal(page('/direct/inbox/',inbox(row('111')),{readyState:'loading'}).states().length,0);
});

test('rows rendered before the document completes are posted on load, without a further mutation or frame',()=>{
 const p=page('/direct/inbox/',inbox(row('111',{unread:'label'})),{readyState:'loading'});
 assert.equal(p.states().length,0);
 p.advance(1500,{frames:false});
 assert.equal(p.states().length,0,'still loading: nothing to report');
 p.complete();p.advance(1000,{frames:false});
 assert.equal(p.states().length,1);
 assert.equal(p.states()[0].threads[0].unread,true);
});

test('state is re-posted only when it changes, at most once per second',()=>{
 const rows=[row('111'),row('222')];
 const p=page('/direct/inbox/',inbox(...rows));
 assert.equal(p.states().length,1);
 p.mutate();p.advance(1500);assert.equal(p.states().length,1,'unchanged state is not re-posted');
 rows[0].children[2].css=bold;                       // 111 becomes unread
 p.mutate();assert.equal(p.states().length,1,'inside the one-second window the change waits');
 p.advance(1200);assert.equal(p.states().length,2);
 assert.equal(p.states()[1].threads[0].unread,true);
 rows[1].children[2].css=bold;p.mutate();p.mutate();p.mutate();
 p.advance(1200);assert.equal(p.states().length,3,'a burst of changes yields one post');
});

test('messages carry no unexpected fields',()=>{
 const p=page('/direct/inbox/',inbox(row('111',{unread:'label'})));
 const message=p.states()[0];
 assert.deepEqual(Object.keys(message).sort(),['threads','type']);
 assert.deepEqual(Object.keys(message.threads[0]).sort(),['id','name','unread']);
});

test('a name is cut on character boundaries, not inside an emoji',()=>{
 const p=page('/direct/inbox/',inbox(row('888',{title:'a'.repeat(79)+'\u{1F600}\u{1F600}'})));
 const name=p.states()[0].threads[0].name;
 assert.equal(Array.from(name).length,80);assert.ok(name.endsWith('\u{1F600}'));assert.doesNotThrow(()=>encodeURIComponent(name));
});
