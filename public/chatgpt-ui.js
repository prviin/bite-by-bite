export function setupChatGPT({api,connectionStatus,getUser,toast}){
 const $=id=>document.getElementById(id);let timer=null,owner=null,loadingModels=false;
 function message(text){$('chatgpt-message').textContent=text;$('photo-chatgpt-message').textContent=text;}
 async function refresh({loadModels=false}={}){
  const s=await api('/api/chatgpt/connection');
  document.querySelectorAll('[data-chatgpt-connect]').forEach(b=>{b.textContent=s.connected?'Reconnect with ChatGPT':'Continue with ChatGPT';b.disabled=false;});
  $('chatgpt-disconnect').hidden=!s.connected;$('chatgpt-model-fields').hidden=!s.connected;
  message(s.connected?`Connected to ChatGPT${s.email?' as '+s.email:''}. Photo estimates use your ChatGPT plan limits.`:s.localSetup?'Connect your ChatGPT Plus or Pro plan. No OpenAI API key is needed for this option.':'To connect your Plus plan, open Bite by Bite on the Mac running this server first.');
  if(s.connected&&loadModels&&!loadingModels){loadingModels=true;try{const {models}=await api('/api/chatgpt/models'),select=$('chatgpt-model');select.replaceChildren();for(const m of models)select.append(new Option(m.name,m.id));if(s.model&&models.some(m=>m.id===s.model))select.value=s.model;message('ChatGPT plan connected. Select a model that accepts images; estimates use your plan allowance.');}catch(e){message(e.message);}finally{loadingModels=false;}}
  return s;
 }
 async function connect(){
  const user=getUser();if(!user)return;
  const popup=window.open('about:blank','bite-chatgpt-signin','width=620,height=780');
  if(!popup){message('Allow pop-ups for this app, then tap Continue with ChatGPT again.');return;}
  try{const data=await api('/api/chatgpt/connect',{method:'POST'});if(getUser()!==user){popup.close();return;}popup.location.href=data.url;owner=user;message('Finish sign-in and approve ChatGPT plan use in the opened window. Your meal photo stays here.');clearTimeout(timer);const deadline=Date.now()+600000;
   async function poll(){if(getUser()!==owner)return;try{const s=await api('/api/chatgpt/connection');if(s.connected&&!s.connecting){await connectionStatus();await refresh({loadModels:true});toast('ChatGPT connected. You can estimate your photo now.');return;}if(!s.connecting||popup.closed||Date.now()>deadline){message('The sign-in window closed or the connection was not completed. Try again and approve ChatGPT plan use.');return;}}catch(e){message(e.message);return;}timer=setTimeout(poll,2000);}timer=setTimeout(poll,1500);
  }catch(e){popup.close();message(e.message);}
 }
 document.querySelectorAll('[data-chatgpt-connect]').forEach(b=>b.onclick=connect);
 $('chatgpt-disconnect').onclick=async()=>{try{const result=await api('/api/chatgpt/disconnect',{method:'POST'});clearTimeout(timer);await connectionStatus();await refresh();message(result.revoked?'ChatGPT disconnected.':'Disconnected locally. Remote revocation was not confirmed; remove Bite by Bite in ChatGPT Settings → Usage to finish.');}catch(e){message(e.message);}};
 $('chatgpt-model').onchange=async()=>{try{await api('/api/chatgpt/model',{method:'PUT',body:JSON.stringify({model:$('chatgpt-model').value})});toast('ChatGPT model saved');}catch(e){message(e.message);}};
 return {refresh:options=>refresh(options).catch(e=>message(e.message))};
}
