import {DatabaseSync} from 'node:sqlite';
import {mkdir,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {backupData} from './backup.mjs';
export async function prepareMigration(source,destination){
 await backupData(source,destination);
 const db=new DatabaseSync(join(destination,'accounts.sqlite'));
 try{
  if(!db.prepare('SELECT count(*) AS count FROM users').get().count)throw Error('Create your local account before migrating.');
  db.exec('CREATE TABLE IF NOT EXISTS installation(key TEXT PRIMARY KEY,value TEXT);');
  db.prepare('INSERT INTO installation VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run('chatgpt-host-id',`urn:uuid:${randomUUID()}`);
  db.exec('DELETE FROM sessions; PRAGMA wal_checkpoint(TRUNCATE);');
 }finally{db.close();}
 await writeFile(join(destination,'MIGRATION.txt'),'Private Bite by Bite account snapshot. Contains encrypted credentials and their encryption key. Transfer only over SSH. The VM has a distinct host ID. Do not restart the laptop copy: the VM must own future ChatGPT token refreshes.\n',{mode:0o600});
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 if(!process.argv.includes('--source-stopped')){console.error('Stop npm start first. Then run: node scripts/prepare-migration.mjs --source-stopped');process.exitCode=1;}
 else try{const root=resolve('migration');await mkdir(root,{recursive:true,mode:0o700});const destination=join(root,new Date().toISOString().replace(/[:.]/g,'-'));await prepareMigration(resolve('data'),destination);console.log(`Migration snapshot ready: ${destination}`);console.log('Transfer it over SSH and keep the laptop server stopped to avoid competing ChatGPT token refreshes.');}catch{console.error('Migration preparation failed. Check that you have an existing local account and writable destination.');process.exitCode=1;}
}
