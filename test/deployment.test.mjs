import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {accounts} from '../accounts.mjs';
import {backupData} from '../scripts/backup.mjs';
import {prepareMigration} from '../scripts/prepare-migration.mjs';

test('backup preserves encrypted account data and migration assigns a distinct VM host',async()=>{
 const root=await mkdtemp(join(tmpdir(),'bite-deployment-'));try{
  const source=join(root,'source'),store=accounts(source),{user}=await store.authenticate('alice','a secure password 123',true);
  const host=store.installation('chatgpt-host-id',()=> 'urn:uuid:laptop');store.setChatGPT(user.id,{clientId:'oaiapp_private',accessToken:'private-token',refreshToken:'private-refresh'});
  store.save(user,{entries:[{id:'meal',type:'food',date:'2026-10-31',name:'Lunch',calories:500,nutrients:{protein:20}}],goal:2000,weight:70});store.db.close();
  const backup=join(root,'backup');await backupData(source,backup);const saved=accounts(backup);assert.equal(saved.getChatGPT(user.id).accessToken,'private-token');assert.equal(saved.db.prepare('SELECT count(*) AS n FROM sessions').get().n,1);saved.db.close();
  const destination=join(root,'vm');await prepareMigration(source,destination);const vm=accounts(destination);assert.notEqual(vm.installation('chatgpt-host-id',()=> 'wrong'),host);assert.equal(vm.getChatGPT(user.id).refreshToken,'private-refresh');assert.equal(vm.db.prepare('SELECT count(*) AS n FROM sessions').get().n,0);assert.equal(JSON.parse(vm.db.prepare('SELECT data FROM users').get().data).entries[0].nutrients.protein,20);vm.db.close();
  const original=accounts(source);assert.equal(original.installation('chatgpt-host-id',()=> 'wrong'),host);assert.equal(original.db.prepare('SELECT count(*) AS n FROM sessions').get().n,1);original.db.close();
  assert.equal((await stat(join(destination,'encryption.key'))).mode&0o777,0o600);assert.equal((await stat(destination)).mode&0o777,0o700);
 }finally{await rm(root,{recursive:true,force:true});}
});
