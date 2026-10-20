// Minimal fake DOM (elements, text, rects, selector matcher) for tests that run Resources/Bridge.js; copied from home-chrome.test.cjs.
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
module.exports={El,h,matches};
