const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),test=require('node:test'),path=require('node:path');
test('story routing preserves the original viewer, confirms signed-in viewing once, restores tray on close',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../Resources/Bridge.js'),'utf8');
 const posted=[],location={pathname:'/',search:'',get href(){return 'https://www.instagram.com'+this.pathname;}};let callback,style,clicks=0;
 const button={textContent:'View story',click(){clicks++}};
 const dialog={textContent:'Want to view the story signed in?',querySelectorAll(){return [button]}};let showDialog=false;
 const root={appendChild(n){n.parentNode=this},getAttribute(){return null},setAttribute(){},style:{setProperty(){}}};
 const document={documentElement:root,createElement(){return style={}},querySelector(){return null},querySelectorAll(q){return q==='[role="dialog"]'&&showDialog?[dialog]:[]},addEventListener(){}};
 const window={innerWidth:400,__instagramBoot:{role:'tray'},webkit:{messageHandlers:{instagram:{postMessage(x){posted.push(x)}}}},addEventListener(){}};window.top=window;
 const history={pushState(a,b,url){location.pathname=new URL(url,location.href).pathname},replaceState(a,b,url){location.pathname=new URL(url,location.href).pathname}};
 vm.runInNewContext(source,{document,window,history,location,URL,WeakSet,setTimeout:()=>0,MutationObserver:class{constructor(fn){callback=fn}observe(){}}});
 const of=type=>posted.filter(m=>m.type===type);
 history.pushState({},'', '/stories/test/123/');assert.equal(style.disabled,true);showDialog=true;callback();callback();assert.equal(clicks,1);
 history.pushState({},'', '/');assert.equal(style.disabled,false);assert.deepEqual(of('storyViewer').map(m=>m.open),[false,true,false]);
 history.pushState({},'', '/me/');assert.deepEqual(of('navigate').map(m=>m.url),['https://www.instagram.com/me/']);assert.equal(location.pathname,'/');
 history.pushState({},'', '/reels/');assert.equal(location.pathname,'/');assert.equal(of('navigate').length,1);
});
