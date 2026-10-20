// Home web "Following" bar detection of Resources/Bridge.js, run against a small fake DOM.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');

// --- Minimal DOM: elements, text, rects, computed position/background, and a selector matcher. ---
function splitTop(text,separator){const out=[];let depth=0,quote=null,current='';
 for(const ch of text){if(quote){if(ch===quote)quote=null;current+=ch;continue;}
  if(ch==='"'||ch==="'"){quote=ch;current+=ch;continue;}
  if(ch==='['||ch==='(')depth++;if(ch===']'||ch===')')depth--;
  if(depth===0&&separator.test(ch)){if(current.trim())out.push(current.trim());current='';continue;}current+=ch;}
 if(current.trim())out.push(current.trim());return out;}
function compound(text){const tag=(text.match(/^[a-z][\w-]*|^\*/i)||[''])[0].toLowerCase();const attrs=[];
 const re=/\[([\w-]+)(?:([\^*$]?=)"([^"]*)")?(\s+i)?\]/g;let m;while((m=re.exec(text)))attrs.push({name:m[1],op:m[2],value:m[3],i:!!m[4]});
 return {tag:tag==='*'?'':tag,attrs};}
function matchCompound(el,c){
 if(!el||!el.tagName)return false;if(c.tag&&el.tagName.toLowerCase()!==c.tag)return false;
 for(const a of c.attrs){let v=el.getAttribute(a.name);if(v==null)return false;if(!a.op)continue;let want=a.value;if(a.i){v=v.toLowerCase();want=want.toLowerCase();}
  if(a.op==='='&&v!==want)return false;if(a.op==='^='&&!v.startsWith(want))return false;if(a.op==='*='&&!v.includes(want))return false;if(a.op==='$='&&!v.endsWith(want))return false;}
 return true;}
function matches(el,selector){return splitTop(selector,/,/).some(complex=>{const parts=splitTop(complex,/\s/).map(compound);
 if(!matchCompound(el,parts.at(-1)))return false;let node=el.parentElement;
 for(let i=parts.length-2;i>=0;i--){while(node&&!matchCompound(node,parts[i]))node=node.parentElement;if(!node)return false;node=node.parentElement;}
 return true;});}
class El{
 constructor(tag,attrs={},children=[],opts={}){this.tagName=tag.toUpperCase();this.attrs=new Map(Object.entries(attrs));this.children=[];this.parentElement=null;
  this.rect=opts.rect||{top:0,left:0,width:0,height:0};this.text=opts.text||'';this.css=opts.css||{};this.style={setProperty(k,v){this[k]=v;}};this.listeners={};this.value=opts.value||'';this.clicked=0;this.events=[];
  for(const child of children)this.appendChild(child);}
 appendChild(child){child.parentElement=this;this.children.push(child);return child;}
 insertBefore(child,ref){child.parentElement=this;const i=ref?this.children.indexOf(ref):-1;if(i<0)this.children.push(child);else this.children.splice(i,0,child);return child;}
 get nextSibling(){const siblings=this.parentElement?this.parentElement.children:[];return siblings[siblings.indexOf(this)+1]||null;}
 get nextElementSibling(){return this.nextSibling;}
 get previousElementSibling(){const s=this.parentElement?this.parentElement.children:[];return s[s.indexOf(this)-1]||null;}
 get textContent(){return [this.text,...this.children.map(c=>c.textContent)].filter(Boolean).join(' ');}
 set textContent(v){this.text=String(v);}
 getAttribute(k){return this.attrs.has(k)?this.attrs.get(k):null;}
 setAttribute(k,v){this.attrs.set(k,String(v));}
 hasAttribute(k){return this.attrs.has(k);}
 removeAttribute(k){this.attrs.delete(k);}
 getBoundingClientRect(){const r=this.rect;return {top:r.top||0,left:r.left||0,width:r.width||0,height:r.height||0,bottom:(r.top||0)+(r.height||0)};}
 descendants(){const out=[];const walk=n=>{for(const c of n.children){out.push(c);walk(c);}};walk(this);return out;}
 querySelectorAll(selector){return this.descendants().filter(e=>matches(e,selector));}
 querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
 matches(selector){return matches(this,selector);}
 closest(selector){let n=this;while(n&&n.tagName){if(matches(n,selector))return n;n=n.parentElement;}return null;}
 contains(other){while(other){if(other===this)return true;other=other.parentElement;}return false;}
 addEventListener(type,f){(this.listeners[type]=this.listeners[type]||[]).push(f);}
 click(){this.clicked++;for(const f of this.listeners.click||[])f({preventDefault(){},stopPropagation(){}});}
 dispatchEvent(event){this.events.push(event.type);return true;}
 get isConnected(){return this.connected!==false;}
}
const h=(tag,attrs,children,opts)=>new El(tag,attrs||{},children||[],opts||{});

// Home web "Following" bar detection (Resources/Bridge.js findFollowingBar), against the fake DOM above (copied from tabs.test.cjs).
function page(pathname,build,{search='',headerHeight=44,scrollY=0}={}){
 const html=h('html'),body=h('body');html.appendChild(body);
 const listeners={},frames=[],posted=[];
 let stack=()=>[];
 const document={documentElement:html,body,readyState:'complete',title:'Instagram',activeElement:body,
  querySelector:s=>html.querySelector(s),querySelectorAll:s=>html.querySelectorAll(s),createElement:t=>h(t),
  elementsFromPoint:(x,y)=>stack(x,y),
  addEventListener:(k,f)=>{(listeners['doc:'+k]=listeners['doc:'+k]||[]).push(f);}};
 const location={pathname,search,get href(){return 'https://www.instagram.com'+this.pathname+this.search;}};
 const window={innerWidth:390,innerHeight:844,scrollY,__instagramBoot:{role:'page',headerHeight,hideChrome:true},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},
  addEventListener(k,f){(listeners['win:'+k]=listeners['win:'+k]||[]).push(f);}};
 window.top=window;
 const context={window,document,location,history:{pushState(){},replaceState(){}},URL,WeakSet,Event:class{constructor(type){this.type=type;}},
  setTimeout:f=>{f();return 0;},requestAnimationFrame:f=>frames.push(f),performance:{now:()=>0},
  getComputedStyle:n=>({display:'block',visibility:'visible',opacity:'1',position:n.css.position||'static',backgroundColor:'rgba(0, 0, 0, 0)',pointerEvents:'auto',paddingBottom:'0px',paddingTop:n.css.paddingTop||'0px',height:'auto'}),
  MutationObserver:class{constructor(f){listeners.mutation=f;}observe(){}}};
 const api={html,body,document,window,listeners,setStack:f=>{stack=f;}};
 build(body,api);
 vm.runInNewContext(source,context);
 api.flush=()=>{for(let i=0;i<3;i++){const run=frames.splice(0);for(const f of run)f();}};
 api.scan=()=>{listeners.mutation();api.flush();};
 api.scan();
 return api;
}
const mark=el=>el.getAttribute('data-native-hidden');
const label=(text)=>h('span',{},[],{text,rect:{top:10,left:150,width:60,height:20}});
function fixedFixture(body,api){
 const bar=h('div',{},[h('div',{},[label('Following'),h('svg',{'aria-label':'Chevron'})],{rect:{top:10,width:200,height:20}})],{rect:{top:0,left:0,width:390,height:44},css:{position:'fixed'}});
 const articles=[h('article',{},[h('span',{},[],{text:'post'})],{rect:{top:44,width:390,height:500}})];
 const main=h('main',{},articles,{rect:{top:44,width:390,height:1200}});
 const spacer=h('div',{},[main],{rect:{top:0,width:390,height:1300},css:{paddingTop:'44px'}});
 body.appendChild(bar);body.appendChild(spacer);
 Object.assign(api,{bar,spacer,main,articles});
}
const home=(build,opts)=>page('/',build,{search:'?variant=following',...opts});

test('the fixed Following bar is marked, its padding spacer is collapsed, the feed is untouched',()=>{
 const p=home((body,api)=>fixedFixture(body,api));
 assert.equal(mark(p.bar),'following-bar');
 assert.equal(p.bar.getAttribute('data-native-bar-height'),'44');
 assert.equal(p.spacer.getAttribute('data-native-header-spacer'),'');
 assert.equal(mark(p.main),null);assert.equal(mark(p.articles[0]),null);assert.equal(mark(p.spacer),null);
 assert.equal(p.html.querySelector('[data-native-hidden="header"]'),null,'not confused with the wordmark header');
});

test('a sticky in-flow Following bar below the header reservation is marked',()=>{
 const p=home((body)=>{
  body.appendChild(h('div',{},[h('div',{},[label('Following')])],{rect:{top:44,width:390,height:48},css:{position:'sticky'}}));
  body.appendChild(h('main',{},[h('article')],{rect:{top:92,width:390,height:900}}));
 });
 assert.equal(mark(p.body.children[0]),'following-bar');
 assert.equal(mark(p.body.children[1]),null);
});

test('an in-flow bar that is neither fixed nor sticky is marked too',()=>{
 const p=home((body)=>{
  body.appendChild(h('div',{},[label('Following')],{rect:{top:44,width:390,height:48}}));
  body.appendChild(h('main',{},[h('article')],{rect:{top:92,width:390,height:900}}));
 });
 assert.equal(mark(p.body.children[0]),'following-bar');
});

test('structural fallback: a fixed full-width bar found through elementsFromPoint is marked even with another label',()=>{
 const p=home((body,api)=>{
  const text=label('For you ▾');
  const bar=h('div',{},[h('div',{},[text],{rect:{top:10,width:100,height:20}})],{rect:{top:0,width:390,height:50},css:{position:'fixed'}});
  body.appendChild(bar);body.appendChild(h('main',{},[h('article')],{rect:{top:0,width:390,height:900}}));
  api.bar=bar;api.text=text;api.setStack(()=>[api.text,bar,body,api.html]);
 });
 assert.equal(mark(p.bar),'following-bar');
 assert.equal(mark(p.body.children[1]),null);
});

test('a bar that appears after scrolling is caught by the throttled scroll probe',()=>{
 const p=home((body,api)=>{
  const bar=h('div',{},[label('Menu')],{rect:{top:0,width:390,height:50},css:{position:'fixed'}});
  api.bar=bar;api.late=bar;
  body.appendChild(h('main',{},[h('article')],{rect:{top:0,width:390,height:900}}));
 });
 assert.equal(mark(p.bar),null);
 p.body.appendChild(p.bar);p.setStack(()=>[p.bar]);
 for(const f of p.listeners['win:scroll'])f();
 assert.equal(mark(p.bar),'following-bar');
});

test('negatives: follow button in a post, profile pages, tall containers, story/image bars stay unmarked',()=>{
 const card=home((body)=>{
  const button=h('span',{},[],{text:'Following',rect:{top:10,width:80,height:30}});
  body.appendChild(h('article',{},[h('div',{},[button],{rect:{top:44,width:390,height:44}})],{rect:{top:44,width:390,height:500}}));
 });
 assert.equal(card.html.querySelector('[data-native-hidden]'),null);

 const profile=page('/alice/',(body)=>body.appendChild(h('div',{},[label('Following')],{rect:{top:0,width:390,height:44},css:{position:'fixed'}})));
 assert.equal(profile.html.querySelector('[data-native-hidden="following-bar"]'),null);

 const tall=home((body)=>body.appendChild(h('div',{},[h('div',{},[label('Following')],{rect:{top:44,width:390,height:300}})],{rect:{top:44,width:390,height:300}})));
 assert.equal(tall.html.querySelector('[data-native-hidden="following-bar"]'),null);

 for(const extra of [()=>h('a',{href:'/stories/alice/'}),()=>h('img',{src:'x'})]){
  const p=home((body,api)=>{
   const bar=h('div',{},[label('Following'),extra()],{rect:{top:0,width:390,height:50},css:{position:'fixed'}});
   body.appendChild(bar);api.setStack(()=>[bar]);
  });
  assert.equal(p.html.querySelector('[data-native-hidden="following-bar"]'),null);
 }
});

test('re-render: a replaced bar is marked synchronously in the mutation callback, before any frame',()=>{
 const p=home((body,api)=>fixedFixture(body,api));
 assert.equal(mark(p.bar),'following-bar');
 const fresh=h('div',{},[h('div',{},[label('Following')],{rect:{top:10,width:200,height:20}})],{rect:{top:0,width:390,height:44},css:{position:'fixed'}});
 p.body.children.splice(0,1,fresh);fresh.parentElement=p.body;p.bar.connected=false;
 p.listeners.mutation();
 assert.equal(mark(fresh),'following-bar');
 // A bar whose attribute React stripped is re-marked too.
 fresh.removeAttribute('data-native-hidden');p.listeners.mutation();
 assert.equal(mark(fresh),'following-bar');
});

test('an empty sibling of the hidden fixed bar with the bar\'s height is marked as a spacer',()=>{
 const p=home((body)=>{
  body.appendChild(h('div',{},[label('Following')],{rect:{top:0,width:390,height:44},css:{position:'fixed'}}));
  body.appendChild(h('div',{},[],{rect:{top:0,width:390,height:45}}));
  body.appendChild(h('div',{},[],{rect:{top:0,width:390,height:12}}));
  body.appendChild(h('main',{},[h('article')],{rect:{top:44,width:390,height:900}}));
 });
 assert.equal(mark(p.body.children[0]),'following-bar');
 assert.equal(mark(p.body.children[1]),'following-spacer');
 assert.equal(mark(p.body.children[2]),null,'different height');
 assert.equal(mark(p.body.children[3]),null);
});
