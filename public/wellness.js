import {dateKey} from './core.js';
export function defaultWellness(){return {water:[],waterGoal:null,supplements:[],taken:[],reminder:{enabled:false,minutes:60,startHour:9,endHour:20,lastMovedAt:null,snoozedUntil:null}};}
const validDate=d=>typeof d==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(d)&&dateKey(new Date(`${d}T12:00:00`))===d;
const id=v=>typeof v==='string'&&v.length>0&&v.length<=100;
export function validateWellness(value){
 if(value===undefined)return defaultWellness();
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Invalid habit data.');
 const w={...defaultWellness(),...value,reminder:{...defaultWellness().reminder,...value.reminder}};
 if(!Array.isArray(w.water)||w.water.length>20000||!w.water.every(e=>e&&id(e.id)&&validDate(e.date)&&Number.isInteger(e.ml)&&e.ml>0&&e.ml<=5000)||new Set(w.water.map(e=>e.id)).size!==w.water.length)throw Error('Water entries need a valid date and 1–5,000 ml.');
 if(w.waterGoal!==null&&(!Number.isInteger(w.waterGoal)||w.waterGoal<100||w.waterGoal>10000))throw Error('Choose a water goal from 100 to 10,000 ml, or leave it blank.');
 if(!Array.isArray(w.supplements)||w.supplements.length>200||!w.supplements.every(e=>e&&id(e.id)&&typeof e.name==='string'&&e.name.trim().length>0&&e.name.length<=80&&(e.archived===undefined||typeof e.archived==='boolean'))||new Set(w.supplements.map(e=>e.id)).size!==w.supplements.length)throw Error('Invalid supplement list.');
 const ids=new Set(w.supplements.map(e=>e.id));
 if(!Array.isArray(w.taken)||w.taken.length>50000||!w.taken.every(e=>e&&validDate(e.date)&&ids.has(e.supplementId))||new Set(w.taken.map(e=>`${e.date}:${e.supplementId}`)).size!==w.taken.length)throw Error('Invalid daily supplement checklist.');
 const r=w.reminder;
 if(typeof r.enabled!=='boolean'||!Number.isInteger(r.minutes)||r.minutes<15||r.minutes>240||!Number.isInteger(r.startHour)||!Number.isInteger(r.endHour)||r.startHour<0||r.endHour>24||r.startHour>=r.endHour||![r.lastMovedAt,r.snoozedUntil].every(v=>v===null||(Number.isSafeInteger(v)&&v>=0&&v<=8640000000000000)))throw Error('Choose a movement interval of 15–240 minutes and a valid daytime window.');
 return {water:w.water,waterGoal:w.waterGoal,supplements:w.supplements,taken:w.taken,reminder:r};
}
export function waterTotal(w,dates){return w.water.filter(e=>dates.includes(e.date)).reduce((sum,e)=>sum+e.ml,0);}
export function movementDue(reminder,now,sessionStarted){const date=new Date(now),hour=date.getHours();return reminder.enabled&&hour>=reminder.startHour&&hour<reminder.endHour&&now>=(reminder.snoozedUntil||0)&&now-(reminder.lastMovedAt??sessionStarted)>=reminder.minutes*60000;}
