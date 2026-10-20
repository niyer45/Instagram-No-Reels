// Search, Notifications and Profile tab behaviour of Resources/Bridge.js (the "Tabs" region), run
// against a small fake DOM that supports the selectors the region uses.
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
 get isConnected(){return true;}
}
const h=(tag,attrs,children,opts)=>new El(tag,attrs||{},children||[],opts||{});

function page(pathname,build,{hideChrome=true}={}){
 const html=h('html'),body=h('body');html.appendChild(body);
 const posted=[],listeners={},frames=[];
 const document={documentElement:html,body,readyState:'complete',title:'Instagram',activeElement:body,
  querySelector:s=>html.querySelector(s),querySelectorAll:s=>html.querySelectorAll(s),createElement:t=>h(t),
  addEventListener:(k,f)=>{(listeners['doc:'+k]=listeners['doc:'+k]||[]).push(f);}};
 const location={pathname,search:'',get href(){return 'https://www.instagram.com'+this.pathname+this.search;}};
 const window={innerWidth:390,innerHeight:844,__instagramBoot:{role:'page',headerHeight:0,hideChrome},webkit:{messageHandlers:{instagram:{postMessage:m=>posted.push(m)}}},addEventListener(){}};
 window.top=window;
 const context={window,document,location,history:{pushState(){},replaceState(){}},URL,WeakSet,Event:class{constructor(type){this.type=type;}},
  setTimeout:f=>{f();return 0;},requestAnimationFrame:f=>frames.push(f),performance:{now:()=>0},
  getComputedStyle:n=>({display:'block',visibility:'visible',opacity:'1',position:n.css.position||'static',backgroundColor:n.css.backgroundColor||'rgba(0, 0, 0, 0)',pointerEvents:'auto',paddingBottom:n.css.paddingBottom||'0px',paddingTop:n.css.paddingTop||'0px',height:n.css.height||'auto'}),
  MutationObserver:class{constructor(f){listeners.mutation=f;}observe(){}}};
 build(body,document);
 vm.runInNewContext(source,context);
 const scan=()=>{listeners.mutation();for(let i=0;i<3;i++){const run=frames.splice(0);for(const f of run)f();}};
 scan();
 return {html,body,document,window,listeners,scan,tabs:window.__instagramTabs,
  fire:(type,event)=>{for(const f of listeners['doc:'+type]||[])f(event||{});}};
}

test('the page kind is exposed on the root so the skin applies by kind, not by tab',()=>{
 for(const [route,kind] of [['/alice/','profile'],['/alice/tagged/','profile'],['/explore/','search'],['/accounts/activity/','activity'],['/p/ABC/','post']]){
  const p=page(route,()=>{});assert.equal(p.html.getAttribute('data-native-page'),kind,route);
 }
});

function searchPage(extra=()=>{}){
 return page('/explore/',(body)=>{
  const input=h('input',{placeholder:'Search',type:'text','aria-label':'Search input'},[],{rect:{top:12,width:300,height:20}});
  const field=h('div',{},[h('svg',{'aria-label':'Search'}),input],{rect:{top:8,left:16,width:358,height:36}});
  const row=h('div',{},[field],{rect:{top:0,width:390,height:52}});
  body.appendChild(row);
  const own=h('div',{role:'button'},[],{text:'Cancel',rect:{top:14,width:60,height:20}});row.appendChild(own);
  const main=h('main');body.appendChild(main);
  const img=h('img',{alt:"alice's profile picture"},[],{rect:{width:32,height:32}});
  body.appendChild(h('nav',{'data-native-hidden':'tabbar'},[h('a',{href:'/me/'},[h('img',{alt:"me's profile picture"},[],{rect:{width:24,height:24}})])]));
  const result=h('a',{href:'/alice/'},[h('div',{},[img],{rect:{width:32,height:32}}),h('div',{},[h('div',{},[h('span',{},[],{text:'alice'}),h('svg',{'aria-label':'Verified'})]),h('span',{},[],{text:'Alice Example'})],{rect:{width:300,height:40}})],{rect:{width:390,height:60}});
  main.appendChild(result);
  const lower=h('button',{},[],{text:'Cancel',rect:{top:400,width:60,height:30}});main.appendChild(lower);
  extra(body,main);
 });
}

test('Search field gets the native skin and a Cancel that appears on focus or text',()=>{
 const p=searchPage();
 const input=p.document.querySelector('input');const field=input.parentElement;const row=field.parentElement;
 assert.equal(input.getAttribute('data-native-search-input'),'');
 assert.equal(field.getAttribute('data-native-search-field'),'');assert.equal(row.getAttribute('data-native-search-row'),'');
 const cancel=row.querySelector('[data-native-search-cancel]');assert.ok(cancel);assert.equal(cancel.textContent,'Cancel');
 assert.equal(row.children.indexOf(cancel),row.children.indexOf(field)+1,'Cancel sits right after the field');
 p.scan();assert.equal(row.querySelectorAll('[data-native-search-cancel]').length,1,'inserted once');
 // Instagram's own Cancel next to the field is replaced; an unrelated lower "Cancel" is not touched.
 assert.equal(row.querySelector('div[role="button"]').getAttribute('data-native-hidden'),'search-cancel');
 assert.equal(p.document.querySelector('main button').getAttribute('data-native-hidden'),null);
 assert.equal(p.html.getAttribute('data-native-search-active'),null);
 assert.equal(p.tabs.hasSearchField(),true,'native shows the idle state only when the field exists');
 assert.equal(page('/explore/',()=>{}).tabs.hasSearchField(),false,'the logged-out popular page has no field');
 p.document.activeElement=input;p.fire('focusin');assert.equal(p.html.getAttribute('data-native-search-active'),'yes');
 p.document.activeElement=p.body;p.fire('focusout');assert.equal(p.html.getAttribute('data-native-search-active'),null);
 input.value='al';p.fire('input');assert.equal(p.html.getAttribute('data-native-search-active'),'yes');
});

test('Instagram\'s overlay "Search" label is hidden so Search is drawn once, and the field keeps one magnifier and one Cancel',()=>{
 const p=searchPage((body)=>{
  const field=body.children[0].children[0];
  field.appendChild(h('span',{},[],{text:'Search',rect:{top:12,left:50,width:60,height:20}}));
 });
 const input=p.document.querySelector('input');const field=input.parentElement;
 const labels=field.querySelectorAll('[data-native-search-label]');
 assert.equal(labels.length,1,'Instagram\'s overlay label is marked (the skin hides it)');
 assert.equal(labels[0].textContent,'Search');assert.equal(input.getAttribute('placeholder'),'Search','the placeholder is the one visible label');
 assert.equal(input.getAttribute('data-native-search-label'),null);
 p.scan();p.scan();
 assert.equal(field.querySelectorAll('[data-native-search-label]').length,1);
 assert.equal(field.parentElement.querySelectorAll('[data-native-search-cancel]').length,1,'one Cancel');
 const bare=searchPage((body)=>{const f=body.children[0].children[0];f.children[1].removeAttribute('placeholder');f.appendChild(h('span',{},[],{text:'Search'}));});
 assert.equal(bare.document.querySelector('input').getAttribute('placeholder'),'Search','no placeholder: ours keeps exactly one label');
});

test('Cancel clears the query through an input event, blurs, resets Instagram state and hides itself',()=>{
 const p=searchPage();const input=p.document.querySelector('input');let blurred=0;input.blur=()=>{blurred++;p.document.activeElement=p.body;};
 p.document.activeElement=input;input.value='alice';p.fire('input');
 const own=p.document.querySelector('[data-native-hidden="search-cancel"]');
 p.document.querySelector('[data-native-search-cancel]').click();
 assert.equal(input.value,'');assert.deepEqual(input.events,['input']);assert.equal(blurred,1);assert.equal(own.clicked,1);
 assert.equal(p.html.getAttribute('data-native-search-active'),null);
 assert.equal(p.tabs.cancelSearch(),true);
});

test('Search results keep the link and badge and mark the avatar, username and full name',()=>{
 const p=searchPage();const link=p.document.querySelector('main a');
 assert.equal(p.document.querySelectorAll('[data-native-search-result]').length,1,'hidden web chrome is not a result');
 assert.equal(link.getAttribute('data-native-search-result'),'');assert.equal(link.getAttribute('href'),'/alice/');
 const avatar=p.document.querySelector('[data-native-search-avatar]');assert.equal(avatar.style.zoom,(44/32).toFixed(4));
 assert.equal(p.document.querySelector('[data-native-search-username]').textContent,'alice');
 assert.equal(p.document.querySelector('[data-native-search-secondary]').textContent,'Alice Example');
 assert.equal(p.document.querySelector('svg[aria-label="Verified"]').attrs.size,1,'badge untouched');
});

test('dragging Search results dismisses the keyboard but taps and the field itself do not',()=>{
 const p=searchPage();const input=p.document.querySelector('input');let blurred=0;input.blur=()=>{blurred++;};
 p.document.activeElement=input;
 p.fire('touchstart',{touches:[{clientY:300}]});p.fire('touchmove',{touches:[{clientY:305}],target:p.document.querySelector('main a')});assert.equal(blurred,0);
 p.fire('touchmove',{touches:[{clientY:330}],target:p.document.querySelector('main a')});assert.equal(blurred,1);
 p.fire('touchstart',{touches:[{clientY:20}]});p.fire('touchmove',{touches:[{clientY:60}],target:input});assert.equal(blurred,1);
});

test('activity rows mark avatar, username, time thumbnail and Follow buttons; the avatar is zoomed to 44',()=>{
 const p=page('/accounts/activity/',(body)=>{
  const main=h('main');body.appendChild(main);
  const row=(handle,trailing)=>h('div',{},[
   h('a',{href:`/${handle}/`},[h('img',{alt:`${handle}'s profile picture`},[],{rect:{width:40,height:40}})],{rect:{width:40,height:40}}),
   h('div',{},[h('a',{href:`/${handle}/`},[],{text:handle}),h('span',{},[],{text:'liked your photo.'}),h('time',{},[],{text:'2h'})],{rect:{width:250,height:36}}),
   trailing],{rect:{width:390,height:60}});
  main.appendChild(row('bob',h('a',{href:'/p/XYZ/'},[h('img',{alt:'post'})])));
  main.appendChild(row('carol',h('button',{},[h('div',{},[],{text:'Follow'})])));
  main.appendChild(row('dave',h('button',{},[],{text:'Following'})));
 });
 const rows=p.document.querySelectorAll('[data-native-activity-row]');assert.equal(rows.length,3);
 assert.equal(p.document.querySelector('[data-native-activity-avatar]').style.zoom,(44/40).toFixed(4));
 assert.deepEqual(p.document.querySelectorAll('[data-native-activity-user]').map(a=>a.getAttribute('href')),['/bob/','/carol/','/dave/']);
 assert.equal(p.document.querySelector('[data-native-activity-thumb]').getAttribute('href'),'/p/XYZ/');
 assert.deepEqual(p.document.querySelectorAll('[data-native-follow-button]').map(b=>b.getAttribute('data-native-follow-button')),['primary','secondary']);
});

test('unread activity comes from the notifications link label or a red dot, and is false otherwise',()=>{
 const plain=page('/',b=>b.appendChild(h('a',{href:'/notifications/'},[h('svg',{'aria-label':'Notifications'})])));
 assert.equal(plain.tabs.unread(),false);
 const labelled=page('/',b=>b.appendChild(h('a',{href:'/accounts/activity/','aria-label':'Notifications, 3 new notifications'})));
 assert.equal(labelled.tabs.unread(),true);
 const dot=page('/',b=>b.appendChild(h('a',{href:'/notifications/'},[h('svg',{'aria-label':'Notifications'}),h('div',{},[],{css:{backgroundColor:'rgb(255, 48, 64)'}})])));
 assert.equal(dot.tabs.unread(),true);
 const none=page('/',()=>{});assert.equal(none.tabs.unread(),false);
});

function profilePage(extra=()=>{}){
 return page('/alice/',(body)=>{
  const main=h('main');body.appendChild(main);
  const picture=h('img',{alt:"alice's profile picture"},[],{rect:{width:96,height:96}});
  const avatar=h('a',{href:'/alice/'},[h('span',{},[picture],{rect:{width:96,height:96}})],{rect:{width:111,height:111}});
  const counts=h('ul',{},[h('li',{},[h('span',{},[h('span',{},[],{text:'12'})],{text:''}),],{text:''}),h('li',{},[h('a',{href:'/alice/followers/'},[h('span',{title:'1,234'},[h('span',{},[],{text:'1,234'})])],{text:''})])]);
  counts.children[0].children[0].text='';counts.children[0].text='';
  counts.children[0].children[0].children[0].text='12';counts.children[0].appendChild(h('span',{},[],{text:'posts'}));
  counts.children[1].children[0].appendChild(h('span',{},[],{text:'followers'}));
  const header=h('header',{},[h('section',{},[avatar],{rect:{width:150,height:150}}),h('section',{},[h('h2',{},[],{text:'alice'}),counts],{rect:{width:250,height:120}})],{rect:{width:390,height:160}});
  const buttons=h('div',{},[h('div',{role:'button'},[h('div',{},[],{text:'Edit profile'})]),h('a',{href:'/alice/share/'},[],{text:'Share profile'})]);
  main.appendChild(h('div',{},[header,buttons]));
  const tab=(attrs,label,href)=>h('div',{},[h('a',{href,...attrs},[h('svg',label?{'aria-label':label}:{},[h('title',{},[],{text:label||'Posts'})])])]);
  main.appendChild(h('div',{role:'tablist'},[tab({'aria-selected':'true'},null,'/alice/'),tab({'aria-selected':'false'},'Reels','/alice/reels/'),tab({'aria-selected':'false'},null,'/alice/tagged/')]));
  const tile=code=>h('div',{},[h('a',{href:`/p/${code}/`},[h('div',{},[h('div',{style:'padding-bottom: 133.333%;'},[h('img',{alt:'post'})])])])]);
  main.appendChild(h('div',{},[h('div',{},[tile('A'),tile('B'),tile('C')]),h('div',{},[tile('D'),tile('E'),tile('F')])]));
  extra(body,main);
 });
}

test('profile header: 90 pt avatar with its ring, native buttons and counts',()=>{
 const p=profilePage();
 assert.equal(p.document.querySelector('header').getAttribute('data-native-profile-header'),'');
 const avatar=p.document.querySelector('[data-native-profile-avatar]');assert.equal(avatar.tagName,'A','the ring wrapper is zoomed with the picture');
 assert.equal(avatar.style.zoom,(90/96).toFixed(4));
 const buttons=p.document.querySelectorAll('[data-native-profile-button]');
 assert.deepEqual(buttons.map(b=>b.textContent),['Edit profile','Share profile'],'outermost control only');
 assert.ok(buttons.every(b=>b.getAttribute('data-native-profile-button')==='secondary'));
 assert.deepEqual(p.document.querySelectorAll('[data-native-profile-count]').map(n=>n.tagName),['LI','A']);
});

test('profile tab strip hides the Reels tab and the grid becomes 3:4 portrait tiles in rows',()=>{
 const p=profilePage();
 const list=p.document.querySelector('[role="tablist"]');assert.equal(list.getAttribute('data-native-profile-tabs'),'');
 assert.deepEqual(list.children.map(slot=>slot.getAttribute('data-native-hidden')),[null,'reels-tab',null]);
 assert.deepEqual(list.children.map(slot=>slot.getAttribute('data-native-profile-tab')),['selected',null,'']);
 assert.equal(p.document.querySelectorAll('[data-native-grid-tile]').length,6);
 assert.equal(p.document.querySelectorAll('[data-native-grid-row]').length,2);
 assert.equal(p.document.querySelectorAll('[data-native-grid-cell]').length,6);
 assert.equal(p.document.querySelectorAll('[data-native-grid-ratio]').length,6);
 assert.equal(p.document.querySelectorAll('[data-native-grid]').length,1);
 const css=fs.readFileSync(path.join(__dirname,'../Resources/NativeSkin.css'),'utf8');
 assert.match(css,/\[data-native-grid-ratio\] \{ padding-bottom: 133\.333% !important; height: 0 !important; \}/);
});

test('the logged-out "See full profile in the app" dialog and sign-up overlay are hidden; real dialogs are not',()=>{
 const p=profilePage((body,main)=>{
  const promo=h('div',{role:'dialog'},[h('span',{},[],{text:'See full profile in the app'}),h('a',{href:'https://applink.instagram.com/alice/'},[],{text:'Open Instagram'}),h('a',{href:'/accounts/signup/phone'},[],{text:'Sign up'})]);
  body.appendChild(h('div',{tabindex:'-1'},[h('div',{},[promo])]));
  body.appendChild(h('div',{},[h('div',{role:'dialog'},[h('span',{},[],{text:'Unfollow alice?'}),h('button',{},[],{text:'Unfollow'}),h('button',{},[],{text:'Cancel'})])]));
  body.appendChild(h('div',{},[h('div',{role:'dialog'},[h('span',{},[],{text:'Use the app to see more. Enter the code we sent'}),h('input',{type:'text'}),h('a',{href:'https://applink.instagram.com/'},[],{text:'Open app'})])]));
  main.appendChild(h('div',{},[h('div',{},[h('span',{},[],{text:'Get the full experience'}),h('a',{href:'/accounts/signup/phone?next=%2Falice%2F'},[],{text:'Sign up for Instagram'})])],{css:{position:'absolute'}}));
  main.appendChild(h('p',{},[h('a',{href:'/accounts/signup/'},[],{text:'Sign up'})]));
 });
 const hidden=p.document.querySelectorAll('[data-native-hidden="app-dialog"]');
 assert.equal(hidden.length,1);assert.equal(hidden[0].getAttribute('tabindex'),'-1','the overlay layer, not just the card');
 assert.equal(p.html.getAttribute('data-native-app-dialog'),'hidden');
 const dialogs=p.document.querySelectorAll('[role="dialog"]');
 assert.equal(dialogs[1].closest('[data-native-hidden]'),null,'confirmation dialogs stay');
 assert.equal(dialogs[2].closest('[data-native-hidden]'),null,'dialogs with inputs stay');
 assert.equal(p.document.querySelectorAll('[data-native-hidden="signup-banner"]').length,1);
 assert.equal(p.document.querySelector('p a').closest('[data-native-hidden]'),null,'in-flow sign-up links stay');
});

test('the own-profile web top bar is hidden and its account switcher is reachable from native',()=>{
 const none=profilePage();assert.equal(none.tabs.switchAccount(),false);
 const p=profilePage(body=>{
  const chevron=h('div',{role:'button'},[h('span',{},[],{text:'alice'}),h('svg',{'aria-label':'Down chevron icon'})],{rect:{top:10,width:120,height:30}});
  const bar=h('div',{},[h('div',{},[h('svg',{'aria-label':'Settings'})],{rect:{top:8,width:40,height:40}}),chevron],{rect:{top:0,width:390,height:44}});
  body.insertBefore(bar,body.children[0]);
 });
 const bar=p.body.children[0];assert.equal(bar.getAttribute('data-native-hidden'),'header');
 assert.equal(p.document.querySelector('header').closest('[data-native-hidden]'),null,'the profile header itself stays');
 assert.equal(p.tabs.switchAccount(),true);assert.equal(bar.querySelector('[role="button"]').clicked,1);
});

test('the strip reserved by the own-profile web top bar collapses in the same scan that hides the bar',()=>{
 // Signed in, the own profile's top bar has no Instagram or Back glyph, so only the Tabs region finds it;
 // its spacer must be marked in that same pass, not only after a later DOM change.
 let bar,spacer;
 page('/me/',body=>{
  bar=h('div',{},[h('button',{},[h('svg',{'aria-label':'Options'})])],{rect:{top:0,width:390,height:44},css:{position:'fixed'}});
  spacer=h('div',{},[h('main',{},[],{rect:{top:60,width:390,height:700}})],{rect:{top:0,width:390,height:760},css:{paddingTop:'60px'}});
  body.appendChild(bar);body.appendChild(spacer);
 });
 assert.equal(bar.getAttribute('data-native-hidden'),'header');
 assert.equal(spacer.getAttribute('data-native-header-spacer'),'');
});
