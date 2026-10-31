import {dateKey,periodDates} from './core.js';
import {validateWellness,waterTotal,movementDue} from './wellness.js';
const $=id=>document.getElementById(id);
const element=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const uid=()=>crypto.randomUUID?.()||Date.now().toString(36)+Math.random().toString(36).slice(2);
export function setupHabits({getState,getUser,getDate,getView,persist,render,toast}){
 let sessionStarted=Date.now(),lastUser=null,notified=null;
 const wellness=()=>validateWellness(getState().wellness);
 async function save(w){try{const clean=validateWellness(w);if(await persist({...getState(),wellness:clean})){render();return true;}render();return false;}catch(e){toast(e.message);render();return false;}}
 function renderHabits(){
  const user=getUser();if(user!==lastUser){lastUser=user;sessionStarted=Date.now();notified=null;}
  if(!user){$('movement-alert').hidden=true;$('water-log').replaceChildren();$('supplement-list').replaceChildren();$('water-total').textContent='0 ml';$('water-goal-description').textContent='';$('habit-period-summary').textContent='';$('supplement-count').textContent='0 taken';$('water-progress').hidden=true;return;}
  const w=wellness(),date=getDate(),dates=periodDates(date,getView()),dayTotal=waterTotal(w,[date]);
  $('habits-date').textContent=new Date(date+'T12:00:00').toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric',year:'numeric'});
  $('water-total').textContent=`${dayTotal.toLocaleString()} ml`;
  $('water-goal-description').textContent=w.waterGoal?`of your ${w.waterGoal.toLocaleString()} ml personal goal`:'Set your personal water goal in Settings';
  $('water-progress').max=w.waterGoal||Math.max(1,dayTotal);$('water-progress').value=dayTotal;$('water-progress').hidden=!w.waterGoal;
  $('habit-period-summary').textContent=getView()==='day'?'':`Selected ${getView()}: ${waterTotal(w,dates).toLocaleString()} ml water · ${w.taken.filter(t=>dates.includes(t.date)).length} supplement check-ins`;
  const water=$('water-log');water.replaceChildren();w.water.filter(e=>e.date===date).forEach(e=>{const row=element('div',undefined,'water-log-row'),remove=element('button','Remove');remove.type='button';remove.setAttribute('aria-label',`Remove ${e.ml} ml water entry`);remove.onclick=()=>save({...wellness(),water:wellness().water.filter(x=>x.id!==e.id)});row.append(element('span',`${e.ml.toLocaleString()} ml`),remove);water.append(row);});
  const list=$('supplement-list');list.replaceChildren();const taken=new Set(w.taken.filter(t=>t.date===date).map(t=>t.supplementId)),visible=w.supplements.filter(s=>!s.archived||taken.has(s.id));
  if(!visible.length)list.append(element('p','Add the supplements you already take, then tick them for each day.','help'));
  visible.forEach(s=>{const row=element('div',undefined,'supplement-row'),label=element('label',undefined,'check'),input=document.createElement('input');input.type='checkbox';input.checked=taken.has(s.id);input.onchange=async()=>{const current=wellness(),taken=current.taken.filter(t=>!(t.date===date&&t.supplementId===s.id));if(input.checked)taken.push({date,supplementId:s.id});input.disabled=true;await save({...current,taken});};label.append(input,element('span',s.name+(s.archived?' (archived)':'')));row.append(label);if(!s.archived){const archive=element('button','Archive');archive.type='button';archive.setAttribute('aria-label',`Archive ${s.name}, keeping past check-ins`);archive.onclick=()=>save({...wellness(),supplements:wellness().supplements.map(x=>x.id===s.id?{...x,archived:true}:x)});row.append(archive);}list.append(row);});
  $('supplement-count').textContent=`${taken.size} taken`;
  checkMovement();
 }
 async function addWater(ml){if(!Number.isInteger(ml)||ml<1||ml>5000){toast('Enter water between 1 and 5,000 ml.');return false;}const w=wellness();if(await save({...w,water:[...w.water,{id:uid(),date:getDate(),ml}]})){toast('Water added');return true;}return false;}
 document.querySelectorAll('[data-water]').forEach(b=>b.onclick=()=>addWater(Number(b.dataset.water)));
 $('water-form').onsubmit=async e=>{e.preventDefault();if(await addWater(Number($('water-amount').value)))$('water-amount').value='';};
 $('supplement-form').onsubmit=async e=>{e.preventDefault();const name=$('supplement-name').value.trim(),w=wellness();if(!name)return;if(w.supplements.some(s=>!s.archived&&s.name.toLowerCase()===name.toLowerCase())){toast('That supplement is already in your list.');return;}if(await save({...w,supplements:[...w.supplements,{id:uid(),name,archived:false}]})){$('supplement-name').value='';toast('Supplement added to your checklist');}};
 async function moved(){const w=wellness();if(await save({...w,reminder:{...w.reminder,lastMovedAt:Date.now(),snoozedUntil:null}})){notified=null;toast('Movement check-in saved');}}
 $('moved-button').onclick=moved;$('movement-done').onclick=moved;
 $('movement-snooze').onclick=async()=>{const w=wellness();if(await save({...w,reminder:{...w.reminder,snoozedUntil:Date.now()+15*60000}}))notified=null;};
 function checkMovement(){
  if(!getUser()||document.visibilityState!=='visible'){$('movement-alert').hidden=true;return;}
  const w=wellness(),due=movementDue(w.reminder,Date.now(),sessionStarted);$('movement-alert').hidden=!due;
  $('movement-status').textContent=w.reminder.enabled?`Check-in reminder every ${w.reminder.minutes} min, ${String(w.reminder.startHour).padStart(2,'0')}:00–${String(w.reminder.endHour).padStart(2,'0')}:00. Timer resets when you tap “I moved” or add today’s activity.`:'Movement check-ins are off. Turn them on in Settings.';
  if(!due)return;
  $('movement-message').textContent=`It’s been at least ${w.reminder.minutes} minutes since your movement timer started or your last check-in. If you’ve been sitting, take a short walk or stretch when it suits you.`;
  const token=`${getUser()}:${w.reminder.lastMovedAt??sessionStarted}:${w.reminder.snoozedUntil}`;
  if(notified!==token&&'Notification' in window&&Notification.permission==='granted'){
   notified=token;navigator.serviceWorker?.ready.then(r=>r.showNotification('Bite by Bite · Time for a movement break?',{body:'If you’ve been sitting for a while, a short walk or stretch could be a welcome break.',tag:'bite-movement'})).catch(()=>{});
  }
 }
 setInterval(()=>{checkMovement();},30000);document.addEventListener('visibilitychange',checkMovement);
 return {
  render:renderHabits,
  fillSettings(){const w=wellness();$('water-goal-input').value=w.waterGoal??'';$('movement-enabled').checked=w.reminder.enabled;$('movement-minutes').value=w.reminder.minutes;$('movement-start').value=w.reminder.startHour;$('movement-end').value=w.reminder.endHour;},
  settingsData(){const w=wellness(),enabled=$('movement-enabled').checked;return validateWellness({...w,waterGoal:$('water-goal-input').value===''?null:Number($('water-goal-input').value),reminder:{...w.reminder,enabled,minutes:Number($('movement-minutes').value),startHour:Number($('movement-start').value),endHour:Number($('movement-end').value),lastMovedAt:enabled&&!w.reminder.enabled?Date.now():w.reminder.lastMovedAt,snoozedUntil:enabled&&!w.reminder.enabled?null:w.reminder.snoozedUntil}});}
 };
}
