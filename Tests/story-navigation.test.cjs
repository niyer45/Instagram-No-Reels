const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),test=require('node:test'),path=require('node:path');
test('story routing preserves the original viewer, confirms signed-in viewing once, restores tray on close',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../Sources/InstagramSession.swift'),'utf8').match(/private static let storiesScript = #"""\n([\s\S]*?)\n    """#/)[1];
 const forwarded=[],events=[],location={pathname:'/',href:'https://www.instagram.com/'};let callback,style,clicks=0;
 const button={textContent:'View story',click(){clicks++}};
 const dialog={textContent:'Want to view the story signed in?',querySelectorAll(){return [button]}};let showDialog=false;
 const document={documentElement:{appendChild(n){n.parentNode=this}},createElement(){return style={}},querySelector(){return null},querySelectorAll(q){return q==='[role="dialog"]'&&showDialog?[dialog]:[]},addEventListener(){}};
 const window={innerWidth:400,webkit:{messageHandlers:{followingNavigate:{postMessage(x){forwarded.push(x.url)}},followingOpenStory:{postMessage(x){events.push(x.open)}},followingStoriesReady:{postMessage(){}}}},addEventListener(){}};
 const history={pushState(a,b,url){location.pathname=new URL(url,location.href).pathname},replaceState(a,b,url){location.pathname=new URL(url,location.href).pathname}};
 vm.runInNewContext(source,{document,window,history,location,URL,WeakSet,MutationObserver:class{constructor(fn){callback=fn}observe(){}}});
 history.pushState({},'', '/stories/test/123/');assert.equal(style.disabled,true);showDialog=true;callback();callback();assert.equal(clicks,1);
 history.pushState({},'', '/');assert.equal(style.disabled,false);assert.deepEqual(events,[false,true,false]);
 history.pushState({},'', '/me/');assert.deepEqual(forwarded,['https://www.instagram.com/me/']);assert.equal(location.pathname,'/');
});
