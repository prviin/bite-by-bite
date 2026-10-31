import test from 'node:test';
import assert from 'node:assert/strict';
import {validEntry} from '../public/core.js';
import {normalizeNutrients,summarizeNutrients} from '../public/nutrition.js';
import {defaultWellness,validateWellness,waterTotal,movementDue} from '../public/wellness.js';

test('nutrient summaries separate unknown amounts from zero and count only food',()=>{
 const summary=summarizeNutrients([{type:'food',nutrients:{protein:12.2,fiber:0,sugar:3,carbs:25,fat:4}},{type:'food',nutrients:{protein:5.1,carbs:10}},{type:'food'},{type:'activity',nutrients:{protein:100}}]);
 assert.equal(summary.meals,3);assert.deepEqual(summary.values.protein,{grams:17.3,logged:2});assert.deepEqual(summary.values.fiber,{grams:0,logged:1});assert.deepEqual(summary.values.carbs,{grams:35,logged:2});assert.deepEqual(summarizeNutrients([{type:'food'}]).values.fat,{grams:null,logged:0});
});
test('old meals are valid and new nutrients reject impossible payloads',()=>{
 const entry={id:'a',type:'food',date:'2026-10-31',name:'Meal',calories:500};assert.ok(validEntry(entry));assert.ok(validEntry({...entry,nutrients:{protein:0,fat:null}}));
 for(const nutrients of [{protein:-1},{carbs:Infinity},{fat:'3'},{sugar:2001},[],{oil:5}]){assert.equal(validEntry({...entry,nutrients}),false);assert.throws(()=>normalizeNutrients(nutrients));}
 assert.deepEqual(normalizeNutrients(undefined),{protein:null,fiber:null,sugar:null,fat:null,carbs:null});
});
test('water and supplement records validate per date without changing calorie entries',()=>{
 const w=defaultWellness();w.water=[{id:'a',date:'2026-10-31',ml:250},{id:'b',date:'2026-11-01',ml:500}];w.supplements=[{id:'z',name:'My zinc',archived:false}];w.taken=[{date:'2026-10-31',supplementId:'z'}];
 assert.deepEqual(validateWellness(w),w);assert.equal(waterTotal(w,['2026-10-31']),250);assert.equal(waterTotal(w,['2026-10-31','2026-11-01']),750);
 assert.deepEqual(validateWellness(undefined),defaultWellness());
 for(const patch of [{water:[{id:'a',date:'2026-02-30',ml:250}]},{water:[{id:'a',date:'2026-10-31',ml:-100}]},{waterGoal:0},{taken:[{date:'2026-10-31',supplementId:'missing'}]},{taken:[...w.taken,...w.taken]},{supplements:[{id:'z',name:''}]}])assert.throws(()=>validateWellness({...w,...patch}));
 assert.equal(validateWellness({...w,supplements:[{...w.supplements[0],archived:true}]}).taken.length,1);
});
test('movement timer respects interval, opt-in, quiet hours, snooze, and check-ins',()=>{
 const now=new Date(2026,9,31,12,0).getTime(),session=now-60*60000,r={...defaultWellness().reminder,enabled:true};
 assert.equal(movementDue(r,now,session),true);assert.equal(movementDue({...r,enabled:false},now,session),false);assert.equal(movementDue(r,now,now-59*60000),false);assert.equal(movementDue({...r,lastMovedAt:now-5*60000},now,session),false);assert.equal(movementDue({...r,snoozedUntil:now+15*60000},now,session),false);assert.equal(movementDue({...r,snoozedUntil:now},now,session),true);assert.equal(movementDue(r,new Date(2026,9,31,21).getTime(),session),false);
 for(const reminder of [{minutes:0},{minutes:241},{startHour:20,endHour:9},{enabled:'yes'}])assert.throws(()=>validateWellness({...defaultWellness(),reminder}));
});
