import {validNutrients} from './nutrition.js';
export function dateKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
export function periodDates(key, period) {
  const day = new Date(`${key}T12:00:00`), start = new Date(day), end = new Date(day);
  if (period === 'week') { start.setDate(day.getDate()-((day.getDay()+6)%7)); end.setTime(start.getTime()); end.setDate(start.getDate()+6); }
  if (period === 'month') { start.setDate(1); end.setMonth(day.getMonth()+1,0); }
  const dates=[];
  for (let d=new Date(start); d<=end; d.setDate(d.getDate()+1)) dates.push(dateKey(d));
  return dates;
}
export function summarize(entries) {
  const food=entries.filter(e=>e.type==='food').reduce((s,e)=>s+e.calories,0);
  const activity=entries.filter(e=>e.type==='activity').reduce((s,e)=>s+e.calories,0);
  const adjustment=entries.filter(e=>e.type==='adjustment').reduce((s,e)=>s+e.calories,0);
  return {food,activity,adjustment,net:food+adjustment-activity};
}
export const activities = { 'Walking':3.5, 'Running':8, 'Cycling':6, 'Swimming':6, 'Strength training':3.5, 'Yoga':2.5, 'Dancing':5 };
export function activityCalories(activity, minutes, weight) { return Math.round(activities[activity]*3.5*weight/200*minutes); }
export function validEntry(e) { return e && typeof e.id==='string' && ['food','activity','adjustment'].includes(e.type) && typeof e.name==='string' && e.name.length>0 && /^\d{4}-\d{2}-\d{2}$/.test(e.date) && dateKey(new Date(`${e.date}T12:00:00`))===e.date && Number.isFinite(e.calories) && Math.abs(e.calories)<=50000 && (e.type==='adjustment'||e.calories>=0) && validNutrients(e.nutrients); }
export function estimatePlan(p){
 for(const [key,min,max] of [['age',18,100],['height',120,230],['weight',35,350],['targetWeight',35,350]])if(!Number.isFinite(p[key])||p[key]<min||p[key]>max)throw Error(`Enter ${key} between ${min} and ${max}.`);
 if(!['female','male'].includes(p.sex)||![0,.25,.5].includes(p.pace))throw Error('Choose a formula and weight-loss pace.');
 if(p.targetWeight/(p.height/100)**2<18.5)throw Error('This calculator does not set goals below the adult healthy-weight range.');
 if(p.excluded)throw Error('Automatic weight-loss targets are not available during pregnancy or breastfeeding. Use a clinician-agreed manual target.');
 if(p.targetWeight>p.weight)throw Error('Choose a goal at or below your current weight, or use a manual target.');
 const bmr=10*p.weight+6.25*p.height-5*p.age+(p.sex==='male'?5:-161),maintenance=Math.round(bmr*1.2),floor=p.sex==='male'?1500:1200;
 const deficit=p.targetWeight<p.weight?Math.min(p.pace*7700/7,maintenance*.2):0,target=Math.round(Math.max(floor,maintenance-deficit)),actual=Math.max(0,maintenance-target);
 return {maintenance,target,deficit:actual,weeks:actual>0?Math.ceil((p.weight-p.targetWeight)*7700/(actual*7)):null};
}
export function calorieAlert(entries,goal,day){const s=summarize(entries.filter(e=>e.date===day)),intake=Math.max(0,s.food+s.adjustment),percent=Math.round(intake/goal*100);return {intake,percent,level:intake>=goal?'100':intake>=goal*.85?'85':null};}
