import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from '../server.mjs';
async function withServer(options,fn){const dataDir=await mkdtemp(join(tmpdir(),'bite-test-')),server=createServer({...options,dataDir});await new Promise((r,j)=>{server.once('error',j);server.listen(0,'127.0.0.1',r);});try{await fn(`http://127.0.0.1:${server.address().port}`,dataDir);}finally{await new Promise(r=>server.close(r));await rm(dataDir,{recursive:true,force:true});}}
async function auth(url,username='alice',path='register'){const r=await fetch(url+'/api/'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password:'a secure password 123'})});assert.equal(r.status,200);return r.headers.get('set-cookie').split(';')[0];}
const post=(cookie,body,method='POST')=>({method,headers:{Cookie:cookie,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('requires login, keeps separate journals, restores login, and revokes logout',()=>withServer({apiKey:''},async url=>{
 assert.equal((await fetch(url)).status,200);assert.equal((await fetch(url+'/api/me')).status,401);assert.equal((await fetch(url+'/.env')).status,404);
 const alice=await auth(url),bob=await auth(url,'bobby');
 const me=await (await fetch(url+'/api/me',{headers:{Cookie:alice}})).json();
 const entry={id:'a',type:'food',date:'2026-10-31',name:'Lunch',calories:500};
 assert.equal((await fetch(url+'/api/data',post(alice,{...me.data,entries:[entry]},'PUT'))).status,200);
 assert.equal((await (await fetch(url+'/api/me',{headers:{Cookie:bob}})).json()).data.entries.length,0);
 const login=await auth(url,'alice','login');assert.equal((await (await fetch(url+'/api/me',{headers:{Cookie:login}})).json()).data.entries[0].name,'Lunch');
 await fetch(url+'/api/logout',post(alice,{}));assert.equal((await fetch(url+'/api/me',{headers:{Cookie:alice}})).status,401);
 assert.equal((await fetch(url+'/api/login',post('',{username:'alice',password:'wrong password'}))).status,400);
}));
test('photo key is isolated, encrypted, and used in real provider request shape',()=>withServer({apiKey:'',fetcher:async(url,options)=>{assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(options.headers.Authorization,'Bearer sk-test-key-with-enough-length');const body=JSON.parse(options.body);assert.equal(body.input[0].content[1].type,'input_image');assert.equal(body.store,false);return Response.json({output:[{content:[{type:'output_text',text:JSON.stringify({name:'Lunch',calories:510.4,notes:'Approximate portion'})}]}]});}},async(url,dataDir)=>{
 const alice=await auth(url),bob=await auth(url,'bobby');
 assert.deepEqual(await (await fetch(url+'/api/status',{headers:{Cookie:alice}})).json(),{photoEnabled:false});
 assert.equal((await fetch(url+'/api/analyze',post(alice,{image:'data:image/jpeg;base64,YWJj'}))).status,503);
 assert.equal((await fetch(url+'/api/photo-key',post(alice,{key:'sk-test-key-with-enough-length'},'PUT'))).status,200);
 const response=await fetch(url+'/api/analyze',post(alice,{image:'data:image/jpeg;base64,YWJj'}));assert.equal(response.status,200);assert.equal((await response.json()).calories,510);
 assert.equal((await (await fetch(url+'/api/status',{headers:{Cookie:bob}})).json()).photoEnabled,false);
 const me=await (await fetch(url+'/api/me',{headers:{Cookie:alice}})).text();assert.ok(!me.includes('sk-test'));
 const {DatabaseSync}=await import('node:sqlite');const db=new DatabaseSync(join(dataDir,'accounts.sqlite'));assert.ok(!db.prepare('SELECT api_key FROM users WHERE username=?').get('alice').api_key.includes('sk-test'));db.close();
 await fetch(url+'/api/photo-key',post(alice,{key:''},'PUT'));assert.equal((await (await fetch(url+'/api/status',{headers:{Cookie:alice}})).json()).photoEnabled,false);
}));
test('rejects CSRF, invalid journals, bad images, and malformed provider output',()=>withServer({apiKey:'test',fetcher:async()=>Response.json({output:[]})},async url=>{
 const cookie=await auth(url);
 assert.equal((await fetch(url+'/api/analyze',{...post(cookie,{}),headers:{Cookie:cookie,Origin:'https://other.example'}})).status,403);
 assert.equal((await fetch(url+'/api/analyze',post(cookie,{image:'https://example.com/image'}))).status,400);
 assert.equal((await fetch(url+'/api/analyze',post(cookie,{image:'data:image/png;base64,YWJj'}))).status,502);
 assert.equal((await fetch(url+'/api/data',post(cookie,{entries:[{}],goal:2000,weight:70},'PUT'))).status,400);
}));
test('journal and sessions survive server restart',()=>withServer({apiKey:''},async(url,dataDir)=>{
 const cookie=await auth(url);const second=createServer({apiKey:'',dataDir});await new Promise(r=>second.listen(0,'127.0.0.1',r));try{const r=await fetch(`http://127.0.0.1:${second.address().port}/api/me`,{headers:{Cookie:cookie}});assert.equal(r.status,200);assert.equal((await r.json()).username,'alice');}finally{await new Promise(r=>second.close(r));}
}));

test('nutrients, water, supplements and reminder settings persist only for their owner',()=>withServer({apiKey:''},async url=>{
 const alice=await auth(url),bob=await auth(url,'bobby');const me=await(await fetch(url+'/api/me',{headers:{Cookie:alice}})).json();
 const {defaultWellness}=await import('../public/wellness.js');const wellness=defaultWellness();wellness.waterGoal=1800;wellness.water=[{id:'cup',date:'2026-10-31',ml:250}];wellness.supplements=[{id:'vit',name:'My vitamin',archived:false}];wellness.taken=[{date:'2026-10-31',supplementId:'vit'}];wellness.reminder={...wellness.reminder,enabled:true,minutes:45};
 const entry={id:'meal',type:'food',date:'2026-10-31',name:'Lunch',calories:500,nutrients:{protein:25,fiber:4,sugar:6,fat:20,carbs:55}};
 const response=await fetch(url+'/api/data',post(alice,{...me.data,entries:[entry],wellness},'PUT'));assert.equal(response.status,200);assert.deepEqual((await response.json()).wellness,wellness);
 const cookie=await auth(url,'alice','login'),data=(await(await fetch(url+'/api/me',{headers:{Cookie:cookie}})).json()).data;assert.deepEqual(data.entries[0].nutrients,entry.nutrients);assert.deepEqual(data.wellness,wellness);
 const other=(await(await fetch(url+'/api/me',{headers:{Cookie:bob}})).json()).data;assert.equal(other.entries.length,0);assert.equal(other.wellness,undefined);
 assert.equal((await fetch(url+'/api/data',post(alice,{...data,wellness:{...wellness,taken:[{date:'2026-10-31',supplementId:'foreign'}]}},'PUT'))).status,400);
 assert.equal((await fetch(url+'/api/data',post(alice,{...data,entries:[{...entry,nutrients:{protein:-10}}]},'PUT'))).status,400);
 assert.deepEqual((await(await fetch(url+'/api/me',{headers:{Cookie:alice}})).json()).data.wellness,wellness);
}));
test('photo estimates return all five nutrient fields',()=>withServer({apiKey:'test',fetcher:async()=>Response.json({output:[{content:[{type:'output_text',text:JSON.stringify({name:'Meal',calories:450,notes:'Estimated serving',nutrients:{protein:20,fiber:4,sugar:3,fat:15,carbs:50}})}]}]})},async url=>{
 const cookie=await auth(url);const response=await fetch(url+'/api/analyze',post(cookie,{image:'data:image/jpeg;base64,YWJj'}));assert.equal(response.status,200);assert.deepEqual((await response.json()).nutrients,{protein:20,fiber:4,sugar:3,fat:15,carbs:50});
}));

test('malformed provider nutrient values are rejected',()=>withServer({apiKey:'test',fetcher:async()=>Response.json({output:[{content:[{type:'output_text',text:JSON.stringify({name:'Meal',calories:450,notes:'Estimated',nutrients:{protein:-2}})}]}]})},async url=>{const cookie=await auth(url);const response=await fetch(url+'/api/analyze',post(cookie,{image:'data:image/jpeg;base64,YWJj'}));assert.equal(response.status,502);}));

test('Plus connection HTTP flow binds the journal owner and uses no paid API fallback',()=>withServer({apiKey:'paid-key-must-not-be-used',fetcher:async(url,options={})=>{
 const {sign}=await import('node:crypto');
 if(url.endsWith('/.well-known/openid-configuration'))return Response.json({issuer:'https://auth.openai.com',jwks_uri:'https://auth.openai.com/jwks'});
 if(url.endsWith('/jwks'))return Response.json({keys:[plusFixture.jwk]});
 if(url.endsWith('/oauth/token')){const p=new URLSearchParams(options.body);assert.equal(p.get('client_id'),'oaiapp_integration');assert.equal(p.get('redirect_uri'),plusFixture.redirectUri);const header=Buffer.from(JSON.stringify({alg:'RS256',kid:'integration'})).toString('base64url'),payload=Buffer.from(JSON.stringify({iss:'https://auth.openai.com',aud:'oaiapp_integration',sub:'verified-user',nonce:plusFixture.nonce,exp:Date.now()/1000+3600,email:'person@example.test'})).toString('base64url');return Response.json({access_token:'plan-token',refresh_token:'renewal-token',id_token:`${header}.${payload}.${sign('RSA-SHA256',Buffer.from(`${header}.${payload}`),plusFixture.privateKey).toString('base64url')}`,scope:'resource.invoke chatgpt.tokens.use.direct',expires_in:3600});}
 if(url.endsWith('/models'))return Response.json({models:[{slug:'vision-model',display_name:'Vision model',visibility:'list'}]});
 if(url.endsWith('/responses')){assert.equal(options.headers.Authorization,'Bearer plan-token');const request=JSON.parse(options.body);assert.equal(request.stream,true);assert.equal(request.max_output_tokens,undefined);if(plusFixture.quota)return new Response('',{status:429});const result={name:'Meal',calories:400,notes:'Approximate',nutrients:{protein:20,carbs:40,fat:15,fiber:4,sugar:2}};return new Response(`data: ${JSON.stringify({type:'response.output_text.delta',delta:JSON.stringify(result)})}\n\ndata: ${JSON.stringify({type:'response.completed'})}\n\n`);}
 throw Error('Unexpected request');
}},async(url,dataDir)=>{
 const {generateKeyPairSync}=await import('node:crypto'),{privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});plusFixture={privateKey,jwk:{...publicKey.export({format:'jwk'}),kid:'integration',alg:'RS256'}};
 assert.equal((await fetch(url+'/api/chatgpt/connect',post('',{}))).status,401);
 const alice=await auth(url),bob=await auth(url,'bobby');
 const {request}=await import('node:http');const remoteHostStatus=await new Promise((resolve,reject)=>{const req=request(url+'/api/chatgpt/connect',{method:'POST',headers:{Cookie:alice,Host:'remote.example'}},res=>{res.resume();res.on('end',()=>resolve(res.statusCode));});req.on('error',reject);req.end();});assert.equal(remoteHostStatus,403);
 const start=await(await fetch(url+'/api/chatgpt/connect',post(alice,{}))).json(),params=new URL(start.url).searchParams;plusFixture.nonce=params.get('nonce');plusFixture.redirectUri=params.get('redirect_uri');
 assert.equal(plusFixture.redirectUri,url+'/auth/callback');
 const callback=await fetch(url+'/auth/callback?'+new URLSearchParams({state:params.get('state'),code:'code',client_id:'oaiapp_integration'}));assert.equal(callback.status,200);
 const info=await(await fetch(url+'/api/chatgpt/connection',{headers:{Cookie:alice}})).json();assert.equal(info.connected,true);assert.equal(JSON.stringify(info).includes('plan-token'),false);
 assert.equal((await(await fetch(url+'/api/chatgpt/connection',{headers:{Cookie:bob}})).json()).connected,false);
 assert.equal((await(await fetch(url+'/api/status',{headers:{Cookie:alice}})).json()).provider,'chatgpt');
 const result=await fetch(url+'/api/analyze',post(alice,{image:'data:image/jpeg;base64,YWJj'}));assert.equal(result.status,200);assert.equal((await result.json()).calories,400);
 plusFixture.quota=true;const limited=await fetch(url+'/api/analyze',post(alice,{image:'data:image/jpeg;base64,YWJj'}));assert.equal(limited.status,502);assert.match((await limited.json()).error,/usage limit/);
 const {DatabaseSync}=await import('node:sqlite'),db=new DatabaseSync(join(dataDir,'accounts.sqlite'));const record=db.prepare('SELECT record FROM chatgpt_connections').get().record;assert.ok(!record.includes('plan-token'));assert.ok(!record.includes('renewal-token'));db.close();
}));
let plusFixture;

test('private deployment closes registration while existing accounts can still sign in',()=>withServer({apiKey:''},async(url,dataDir)=>{
 await auth(url);const server=createServer({apiKey:'',dataDir,registrationOpen:false});await new Promise(r=>server.listen(0,'127.0.0.1',r));const privateUrl=`http://127.0.0.1:${server.address().port}`;try{
 assert.deepEqual(await(await fetch(privateUrl+'/api/config')).json(),{registrationOpen:false});assert.equal((await fetch(privateUrl+'/api/register',post('',{username:'new-person',password:'secure password 123'}))).status,403);await auth(privateUrl,'alice','login');
 }finally{await new Promise(r=>server.close(r));}
}));
