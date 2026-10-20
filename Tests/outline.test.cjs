const {test}=require('node:test');
const assert=require('node:assert/strict');
const {hrefShape,safeLabel,outlineTree}=require('../Resources/Bridge.js');

/** Minimal fake element: real DOM elements offer getAttribute, getAttributeNames, children and textContent. */
function el(tag,attrs={},children=[],text='',style={}){
 const node={tagName:tag.toUpperCase(),children,textContent:text||children.map(c=>c.textContent).join(''),style,
  getAttribute:n=>Object.prototype.hasOwnProperty.call(attrs,n)?attrs[n]:null,getAttributeNames:()=>Object.keys(attrs)};
 return node;
}
const env=(extra={})=>({styleOf:n=>({position:'static',display:'block',visibility:'visible',opacity:'1',top:'auto',zIndex:'auto',...n.style}),rectOf:()=>({x:1.4,y:2.6,width:100.2,height:50.5}),...extra});

test('hrefShape reduces links to shapes without user content',()=>{
 const cases={
  '/':'/','/?variant=following':'/?variant=following','/?variant=zzz':'/?variant=<v>',
  '/accounts/login/?next=%2Falice%2F':'/accounts/login/?next=<v>','/alice/':'/<user>/','/alice/tagged/':'/<user>/tagged/',
  '/p/ABC_1/':'/p/<code>/','/alice/p/ABC/':'/<user>/p/<code>/','/p/ABC/comments/':'/p/<code>/comments/','/p/ABC/liked_by/':'/p/<code>/liked_by/',
  '/reel/ABC/':'/reel/<code>/','/stories/alice/123/':'/stories/<user>/<id>/','/stories/highlights/987/':'/stories/highlights/<id>/',
  '/direct/t/1234/':'/direct/t/<id>/','/direct/inbox/':'/direct/inbox/','/explore/tags/cats/':'/explore/tags/<tag>/',
  '/explore/locations/1/paris/':'/explore/locations/<id>/<x>/','/accounts/activity/':'/accounts/activity/',
  'https://www.instagram.com/alice/':'/<user>/','https://example.com/a?b=1':'<external>','https://l.instagram.com/?u=x':'<external>',
  'mailto:a@b.c':'<scheme>','tel:123':'<scheme>','instagram://user?username=a':'<scheme>','JavaScript:void(0)':'<script>','#top':'#',
 };
 for(const [href,shape] of Object.entries(cases))assert.equal(hrefShape(href),shape,href);
 assert.equal(hrefShape(null),null);
 assert.equal(hrefShape(''),null);
});

test('safeLabel keeps fixed UI labels and hides everything else',()=>{
 assert.equal(safeLabel('Like'),'Like');
 assert.equal(safeLabel('Back'),'Back');
 assert.equal(safeLabel("alice's profile picture"),'<other>');
 assert.equal(safeLabel(null),null);
 assert.equal(safeLabel(''),null);
});

function sampleTree(){
 const svg=el('svg',{'aria-label':'Like'},[el('path',{d:'M0 0'}),el('path',{d:'M1 1'})]);
 const post=el('article',{role:'article','data-native-hidden':'header','data-instagram-post':'1','data-testid':'secret-id','data-following-state':'x'},[
  el('a',{href:'/alice/'},[],'alice'),
  el('a',{href:'/p/ABC123/'}),
  el('img',{src:'https://scontent.cdninstagram.com/secret.jpg',alt:"alice's profile picture"}),
  el('div',{'aria-label':"alice's profile picture"},[],'alice posted a sunset caption'),
  el('script',{},[],'var token="alice"'),
  svg,
  el('span',{},[],' Following '),
 ],'alice posted a sunset caption',{position:'fixed',top:'0px',zIndex:'5',opacity:'0.5'});
 return el('body',{},[post]);
}

test('outlineTree records structure and leaks no content',()=>{
 const {nodes,truncated}=outlineTree(sampleTree(),env());
 const json=JSON.stringify({nodes,truncated});
 for(const word of ['alice','sunset','caption','ABC123','cdninstagram','secret','token'])assert.ok(!json.includes(word),word);
 assert.equal(truncated,false);
 assert.equal(nodes[0].tag,'body');
 assert.equal(nodes[0].d,0);
 const hrefs=nodes.filter(n=>n.tag==='a').map(n=>n.href);
 assert.deepEqual(hrefs,['/<user>/','/p/<code>/']);
 assert.equal(nodes.find(n=>n.tag==='div').aria,'<other>');
 assert.equal(nodes.find(n=>n.tag==='span').ui,'Following');
 assert.equal(nodes.find(n=>n.tag==='a').ui,undefined);
 assert.ok(!nodes.some(n=>n.tag==='script'));
 const svgAt=nodes.findIndex(n=>n.tag==='svg');
 assert.ok(svgAt>0);
 assert.equal(nodes[svgAt].aria,'Like');
 assert.equal(nodes[svgAt].n,2);
 assert.ok(!nodes.some(n=>n.tag==='path'));
 assert.deepEqual(nodes.map(n=>n.i),nodes.map((_,i)=>i));
});

test('outlineTree reports position, rect, flags and our own data names only',()=>{
 const {nodes}=outlineTree(sampleTree(),env());
 const article=nodes.find(n=>n.tag==='article');
 assert.equal(article.pos,'fixed');
 assert.equal(article.top,'0px');
 assert.equal(article.z,'5');
 assert.equal(article.opacity,'0.5');
 assert.equal(article.vis,undefined);
 assert.equal(article.hidden,'header');
 assert.equal(article.role,'article');
 assert.deepEqual(article.data,['data-native-hidden','data-instagram-post','data-following-state']);
 assert.equal(article.has,'ia');
 assert.equal(article.n,7);
 assert.deepEqual(article.rect,[1,3,100,51]);
 assert.equal(nodes[0].top,undefined);
 assert.equal(nodes[0].has,'ia');
 const hiddenEnv=outlineTree(el('body',{},[el('div',{},[],'',{display:'none'}),el('div',{},[],'',{opacity:'0'})]),env());
 assert.equal(hiddenEnv.nodes[1].vis,0);
 assert.equal(hiddenEnv.nodes[2].vis,0);
 assert.equal(hiddenEnv.nodes[1].opacity,undefined);
 assert.equal(hiddenEnv.nodes[2].opacity,'0');
});

test('outlineTree honours maxNodes and maxDepth',()=>{
 const wide=el('body',{},Array.from({length:10},()=>el('div')));
 const cut=outlineTree(wide,env({maxNodes:4}));
 assert.equal(cut.nodes.length,4);
 assert.equal(cut.truncated,true);
 assert.equal(outlineTree(wide,env({maxNodes:11})).truncated,false);
 const deep=el('body',{},[el('div',{},[el('div',{},[el('div',{},[el('div')])])])]);
 const shallow=outlineTree(deep,env({maxDepth:2}));
 assert.deepEqual(shallow.nodes.map(n=>n.d),[0,1,2]);
 assert.equal(shallow.nodes[2].n,1);
});

test('outlineSections yields main and bars sections without leaking text',()=>{
 const {outlineSections}=require('../Resources/Bridge.js');
 const { h }=require('./fake-dom.cjs');
 const nav=h('nav',{'aria-label':"alice's menu"},[h('a',{href:'/alice/'},[],{text:'alice'})],{css:{position:'relative'}});
 const fixed=h('div',{},[h('span',{},[],{text:'Following'}),h('img',{src:'https://scontent.cdninstagram.com/secret.jpg'})],{css:{position:'fixed'}});
 const inPost=h('nav',{},[],{});
 const main=h('main',{},[h('article',{},[inPost,h('a',{href:'/p/ABC123/'},[],{text:'sunset caption'})]),h('div',{},[],{css:{position:'sticky'}})]);
 const body=h('body',{},[fixed,h('section',{},[nav,main])]);
 const html=h('html',{},[body]);
 const env={styleOf:n=>({position:'static',display:'block',visibility:'visible',opacity:'1',top:'auto',zIndex:'auto',...n.css}),rectOf:()=>({x:0,y:44,width:402,height:45}),indexes:new Map()};
 const bodyTree=outlineTree(body,env);
 const s=outlineSections(html,env,bodyTree,env.indexes);
 assert.ok(s.main&&s.main.nodes[0].tag==='main'&&s.main.nodes[0].d===0);
 const kinds=s.bars.map(b=>b.kind);
 assert.ok(kinds.includes('nav'));assert.ok(kinds.includes('fixed'));assert.ok(kinds.includes('sticky'));
 assert.equal(s.bars.length,3,'nav in an article excluded');
 assert.ok(s.bars.every(b=>b.nodes.length>0&&Array.isArray(b.rect)&&'hidden' in b));
 const json=JSON.stringify(s);
 for(const word of ['alice','sunset','caption','ABC123','cdninstagram','secret','scontent'])assert.ok(!json.includes(word),word);
 const none=outlineSections(h('html',{},[h('body')]),env,{nodes:[]},new Map());
 assert.equal(none.main,null);assert.deepEqual(none.bars,[]);
});
