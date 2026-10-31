import {randomBytes,randomUUID,createHash,createPublicKey,verify} from 'node:crypto';

const ISSUER='https://auth.openai.com',RESOURCE='https://api.openai.com/v1';
const SCOPES='openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
const random=()=>randomBytes(32).toString('base64url');
const scopeList=value=>typeof value==='string'?value.split(/\s+/).filter(Boolean):[];
function requirePlanScopes(scopes){if(!scopes.includes('chatgpt.tokens.use.direct')||!scopes.includes('resource.invoke'))throw Error('ChatGPT plan permission was not granted. Connect again and approve use of your Plus plan.');}
export async function validateIdToken(token,{clientId,nonce,subject,fetcher=fetch}){
 if(typeof token!=='string'||token.length>50000)throw Error('Invalid ChatGPT identity response.');
 const parts=token.split('.');if(parts.length!==3)throw Error('Invalid ChatGPT identity response.');
 const header=JSON.parse(Buffer.from(parts[0],'base64url').toString()),claims=JSON.parse(Buffer.from(parts[1],'base64url').toString());
 if(header.alg!=='RS256'||typeof header.kid!=='string')throw Error('Unsupported ChatGPT identity signature.');
 const metadataResponse=await fetcher(`${ISSUER}/.well-known/openid-configuration`,{signal:AbortSignal.timeout(15000)});if(!metadataResponse.ok)throw Error('Cannot verify the ChatGPT connection. Try again.');const metadata=await metadataResponse.json();
 if(metadata.issuer!==ISSUER||new URL(metadata.jwks_uri).origin!==ISSUER)throw Error('Invalid ChatGPT discovery document.');
 const response=await fetcher(metadata.jwks_uri,{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Cannot verify the ChatGPT connection. Try again.');
 const jwk=(await response.json()).keys?.find(k=>k.kid===header.kid&&k.kty==='RSA'&&(!k.use||k.use==='sig')&&(!k.alg||k.alg==='RS256'));
 if(!jwk||!verify('RSA-SHA256',Buffer.from(`${parts[0]}.${parts[1]}`),createPublicKey({key:jwk,format:'jwk'}),Buffer.from(parts[2],'base64url')))throw Error('ChatGPT identity signature could not be verified.');
 const now=Date.now()/1000,audience=Array.isArray(claims.aud)?claims.aud:[claims.aud];
 if(claims.iss!==ISSUER||!audience.includes(clientId)||!Number.isFinite(claims.exp)||claims.exp<=now||(claims.nbf&&claims.nbf>now+60)||typeof claims.sub!=='string'||!claims.sub||(nonce!==undefined&&claims.nonce!==nonce)||(subject&&claims.sub!==subject)||(audience.length>1&&claims.azp!==clientId))throw Error('ChatGPT identity validation failed. Please reconnect.');
 return claims;
}

export function createChatGPT({store,fetcher=fetch}){
 const pending=new Map(),refreshing=new Map(),generation=new Map();
 const hostId=store.installation('chatgpt-host-id',()=>`urn:uuid:${randomUUID()}`);
 function status(userId){const r=store.getChatGPT(userId);return {connected:!!r?.accessToken,connecting:[...pending.values()].some(p=>p.userId===userId&&p.expires>Date.now()),email:r?.email||null,model:r?.model||null};}
 async function begin(userId,port){
  for(const [key,p] of pending)if(p.expires<Date.now()||p.userId===userId)pending.delete(key);
  cancel(userId);
  const previous=store.getChatGPT(userId),state=random(),verifier=random(),nonce=random(),redirectUri=`http://127.0.0.1:${port}/auth/callback`;
  const p={userId,generation:generation.get(userId),verifier,nonce,redirectUri,clientId:previous?.clientId||null,subject:previous?.subject||null,expires:Date.now()+600000};pending.set(state,p);
  const url=new URL(`${ISSUER}/api/accounts/authorize`);
  const params={client_id:p.clientId||'dynamic_agent_client',ext_agent_host_id:hostId,response_type:'code',redirect_uri:redirectUri,scope:SCOPES,resource:RESOURCE,state,nonce,code_challenge_method:'S256',code_challenge:createHash('sha256').update(verifier).digest('base64url')};
  if(!p.clientId)params.agent_name_hint='Bite by Bite';
  if(previous?.idToken)params.id_token_hint=previous.idToken;
  if(previous?.email)params.login_hint=previous.email;
  for(const [k,v] of Object.entries(params))url.searchParams.set(k,v);
  return {url:url.toString()};
 }
 async function callback(params){
  const state=params.get('state'),p=pending.get(state);if(!p||p.expires<Date.now())throw Error('This connection attempt expired or is invalid. Return to Bite by Bite and try again.');pending.delete(state);
  if(params.get('error'))throw Error('ChatGPT connection was not approved. Return to the app and try again.');
  const issued=params.get('client_id')||p.clientId;
  if(!issued||issued==='dynamic_agent_client'||(p.clientId&&issued!==p.clientId)||!params.get('code'))throw Error('ChatGPT registration is incomplete. Please connect again.');
  // Retain the issued registration even if an authorization code expires.
  const previous=store.getChatGPT(p.userId)||{};store.setChatGPT(p.userId,{...previous,clientId:issued});
  const tokens=await tokenRequest({grant_type:'authorization_code',client_id:issued,code:params.get('code'),code_verifier:p.verifier,redirect_uri:p.redirectUri,resource:RESOURCE});
  const claims=await validateIdToken(tokens.id_token,{clientId:issued,nonce:p.nonce,subject:p.subject,fetcher});
  const scopes=scopeList(tokens.scope);requirePlanScopes(scopes);
  if(typeof tokens.access_token!=='string'||!tokens.access_token||!Number.isFinite(tokens.expires_in)||tokens.expires_in<=0)throw Error('ChatGPT did not return usable plan access.');
  if(generation.get(p.userId)!==p.generation)throw Error('This connection attempt was cancelled. Return to the app and connect again.');
  store.setChatGPT(p.userId,{clientId:issued,subject:claims.sub,email:typeof claims.email==='string'?claims.email:null,idToken:tokens.id_token,accessToken:tokens.access_token,refreshToken:tokens.refresh_token||null,expiresAt:Date.now()+tokens.expires_in*1000,scopes,model:previous.model||null});
  return p.userId;
 }
 async function tokenRequest(body){const response=await fetcher(`${ISSUER}/api/accounts/oauth/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(body),signal:AbortSignal.timeout(30000)});if(!response.ok)throw Error('ChatGPT authorization expired or was rejected. Connect again to renew it.');return response.json();}
 async function access(userId){
  let r=store.getChatGPT(userId);if(!r?.accessToken)throw Error('Continue with ChatGPT to connect your Plus plan.');requirePlanScopes(r.scopes||[]);
  if(r.expiresAt>Date.now()+60000)return r;
  if(refreshing.has(userId))return refreshing.get(userId);
  const task=(async()=>{if(!r.refreshToken)throw Error('Your ChatGPT connection expired. Continue with ChatGPT again.');const tokens=await tokenRequest({grant_type:'refresh_token',client_id:r.clientId,refresh_token:r.refreshToken,resource:RESOURCE});
   const scopes=tokens.scope===undefined?r.scopes:scopeList(tokens.scope);requirePlanScopes(scopes);
   if(tokens.id_token)await validateIdToken(tokens.id_token,{clientId:r.clientId,subject:r.subject,fetcher});
   if(typeof tokens.access_token!=='string'||!Number.isFinite(tokens.expires_in)||tokens.expires_in<=0)throw Error('ChatGPT access could not be renewed. Please reconnect.');
   const fresh={...r,accessToken:tokens.access_token,refreshToken:tokens.refresh_token||r.refreshToken,idToken:tokens.id_token||r.idToken,expiresAt:Date.now()+tokens.expires_in*1000,scopes};
   // A disconnect during renewal must not recreate the connection.
   if(store.getChatGPT(userId)?.accessToken!==r.accessToken)throw Error('The ChatGPT connection changed. Please try again.');
   store.setChatGPT(userId,fresh);return fresh;
  })();refreshing.set(userId,task);try{return await task;}finally{refreshing.delete(userId);}
 }
 async function models(userId){const r=await access(userId),response=await fetcher(`${RESOURCE}/models`,{headers:{Authorization:`Bearer ${r.accessToken}`},signal:AbortSignal.timeout(20000)});if(!response.ok)throw Error('Cannot load models for your ChatGPT plan. Reconnect or try again later.');const data=await response.json(),models=(data.models||[]).filter(m=>m.visibility==='list'&&typeof m.slug==='string').map(m=>({id:m.slug,name:m.display_name||m.slug}));if(!models.length)throw Error('Your ChatGPT account did not offer a usable model.');return models;}
 async function selectModel(userId,model){const available=await models(userId);if(!available.some(m=>m.id===model))throw Error('Select a model offered by your ChatGPT plan.');const r=store.getChatGPT(userId);store.setChatGPT(userId,{...r,model});}
 async function analyze(userId,input){
  const r=await access(userId),available=await models(userId),model=available.find(m=>m.id===r.model)?.id||available[0].id;
  const response=await fetcher(`${RESOURCE}/responses`,{method:'POST',headers:{Authorization:`Bearer ${r.accessToken}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(90000),body:JSON.stringify({model,store:false,stream:true,input,text:{format:{type:'json_object'}}})});
  if(!response.ok)throw Error(response.status===429?'Your ChatGPT plan usage limit was reached. Wait for it to reset or check your plan’s usage settings.':response.status===401?'Your ChatGPT connection expired. Continue with ChatGPT again.':'ChatGPT could not estimate this photo. Try a model that supports images or reconnect.');
  return readResponseStream(response);
 }
 async function disconnect(userId){cancel(userId);const r=store.getChatGPT(userId);if(!r)return {revoked:true};
  store.setChatGPT(userId,{clientId:r.clientId,subject:r.subject,email:r.email,model:r.model});
  if(!r.refreshToken)return {revoked:false};
  try{const metadataResponse=await fetcher(`${ISSUER}/.well-known/openid-configuration`,{signal:AbortSignal.timeout(15000)}),metadata=await metadataResponse.json();if(new URL(metadata.revocation_endpoint).origin!==ISSUER)throw Error();const response=await fetcher(metadata.revocation_endpoint,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:r.refreshToken,token_type_hint:'refresh_token',client_id:r.clientId}),signal:AbortSignal.timeout(15000)});return {revoked:response.status===200};}catch{return {revoked:false};}
 }
 function cancel(userId){generation.set(userId,(generation.get(userId)||0)+1);for(const [state,p] of pending)if(p.userId===userId)pending.delete(state);}
 return {status,begin,callback,analyze,models,selectModel,disconnect,cancel};
}

export async function readResponseStream(response){
 if(!response.body)throw Error('ChatGPT returned no estimate.');
 const decoder=new TextDecoder();let buffer='',text='',completed=false,bytes=0;
 const event=block=>{const raw=block.split('\n').filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');if(!raw||raw==='[DONE]')return;const e=JSON.parse(raw);if(e.type==='response.output_text.delta')text+=e.delta||'';if(e.type==='response.completed'){if(e.response?.status&&e.response.status!=='completed')throw Error('ChatGPT did not finish its estimate.');completed=true;const full=(e.response?.output||[]).flatMap(o=>o.content||[]).filter(c=>c.type==='output_text').map(c=>c.text).join('');if(full)text=full;}if(['error','response.failed','response.incomplete'].includes(e.type))throw Error('ChatGPT did not finish this estimate. Try again.');};
 for await(const chunk of response.body){bytes+=chunk.length;if(bytes>2000000)throw Error('ChatGPT returned an unexpectedly large estimate.');buffer=(buffer+decoder.decode(chunk,{stream:true})).replace(/\r\n/g,'\n');let boundary;while((boundary=buffer.indexOf('\n\n'))>=0){event(buffer.slice(0,boundary));buffer=buffer.slice(boundary+2);}}
 buffer+=decoder.decode();if(buffer.trim())event(buffer);if(!completed||!text)throw Error('ChatGPT did not finish this estimate. Try again.');return JSON.parse(text);
}
