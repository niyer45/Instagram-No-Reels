const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');

// A profile page whose readiness probe passes, with a controllable clock and timers and a
// counter on elementsFromPoint (the expensive part of theme sampling).
function page(){
 let clock=0,samples=0,background='rgb(12, 16, 20)';const timers=[],frames=[],posted=[],listeners={};
 const main={querySelectorAll:()=>[],querySelector:()=>null,textContent:'x'};
 const root={getAttribute:()=>null,setAttribute(){},style:{setProperty(){}},appendChild(){}};
 const document={documentElement:root,readyState:'complete',title:'Instagram',body:null,
  querySelector:s=>s==='main'?main:s.startsWith('main header')?{}:null,querySelectorAll:()=>[],createElement:()=>({}),
  addEventListener:(k,f)=>{listeners['doc:'+k]=f;},elementsFromPoint:()=>{samples++;return [];}};
 const location={pathname:'/alice/',search:'',get href(){return 'https://www.instagram.com'+this.pathname+this.search;}};
 const history={pushState(a,b,u){const x=new URL(u,location.href);location.pathname=x.pathname;location.search=x.search;},replaceState(){}};
 const window={innerWidth:400,innerHeight:800,__instagramBoot:{role:'page'},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},addEventListener(){}};
 window.top=window;
 const context={window,document,location,history,URL,WeakSet,setTimeout:(f,ms)=>{timers.push({at:clock+(ms||0),f});return timers.length;},
  requestAnimationFrame:f=>frames.push(f),performance:{now:()=>clock},
  getComputedStyle:()=>({display:'block',visibility:'visible',opacity:'1',position:'static',pointerEvents:'auto',backgroundColor:background}),
  MutationObserver:class{constructor(f){listeners.mutation=f;}observe(){}}};
 vm.runInNewContext(source,context);
 const flush=(n=1)=>{for(let i=0;i<n;i++){const run=frames.splice(0);for(const f of run)f();}};
 return {
  get samples(){return samples;},history,posted,
  set background(v){background=v;},
  flush,
  // One DOM change and the animation frame that handles it.
  mutate(){listeners.mutation();flush();},
  advance(ms){clock+=ms;for(const t of timers.filter(t=>t.at<=clock).sort((a,b)=>a.at-b.at)){timers.splice(timers.indexOf(t),1);t.f();}},
  themes:()=>posted.filter(m=>m.type==='theme').map(m=>m.backgroundRGB.join(','))};
}

test('theme is not sampled on DOM changes before the page is ready',()=>{
 const p=page();
 // The initial mutation run queues readiness frames; readiness needs six stable frames.
 for(let i=0;i<4;i++)p.mutate();
 assert.equal(p.samples,0);
 p.flush(6);assert.equal(p.samples,1,'sampled once when ready');
});

test('DOM-change sampling after ready is throttled to one per 500 ms with a trailing sample',()=>{
 const p=page();p.flush(8);assert.equal(p.samples,1);
 // Ready also re-samples 300, 1000 and 2500 ms later (stylesheets can restyle without mutations).
 p.advance(2500);assert.equal(p.samples,4);
 for(let i=0;i<30;i++)p.mutate();
 assert.equal(p.samples,4,'a burst right after a sample waits for the interval');
 p.advance(499);assert.equal(p.samples,4);
 p.advance(1);assert.equal(p.samples,5,'one trailing sample for the whole burst');
 p.advance(600);const settled=p.samples;
 p.mutate();assert.equal(p.samples,settled+1,'a change after a quiet interval samples at once');
 // Changes every 50 ms (e.g. infinite scroll) sample once per 500 ms.
 for(let i=0;i<9;i++){p.advance(50);p.mutate();}
 assert.equal(p.samples,settled+1);
 p.advance(50);assert.equal(p.samples,settled+2);
 for(let i=0;i<20;i++){p.advance(50);p.mutate();}
 assert.equal(p.samples,settled+4);
});

test('a route change samples on its first DOM change without waiting for the interval',()=>{
 const p=page();p.flush(8);p.mutate();const before=p.samples;
 p.history.pushState({},'','/alice/tagged/');
 p.mutate();assert.equal(p.samples,before+1);
 p.mutate();assert.equal(p.samples,before+1,'later changes on the same route are throttled again');
});

test('a background change after ready still reaches native within the interval',()=>{
 const p=page();p.flush(8);assert.deepEqual(p.themes(),['12,16,20']);
 p.advance(3000);p.mutate();
 p.background='rgb(31, 31, 32)';p.mutate();p.mutate();
 assert.deepEqual(p.themes(),['12,16,20']);
 p.advance(500);assert.deepEqual(p.themes(),['12,16,20','31,31,32']);
});
