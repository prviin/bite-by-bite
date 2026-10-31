import {DatabaseSync,backup} from 'node:sqlite';
import {mkdir,copyFile,chmod} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
export async function backupData(source,destination){
 source=resolve(source);destination=resolve(destination);
 await mkdir(destination,{mode:0o700});
 const db=new DatabaseSync(join(source,'accounts.sqlite'),{readOnly:true});
 try{await backup(db,join(destination,'accounts.sqlite'));await chmod(join(destination,'accounts.sqlite'),0o600);await copyFile(join(source,'encryption.key'),join(destination,'encryption.key'));await chmod(join(destination,'encryption.key'),0o600);}finally{db.close();}
 return destination;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const source=process.argv[2]||'/app/data',root=process.argv[3]||'/backups',name=new Date().toISOString().replace(/[:.]/g,'-');
 try{await mkdir(root,{recursive:true,mode:0o700});const destination=await backupData(source,join(root,name));console.log(`Backup created: ${destination}`);}catch{console.error('Backup failed. Check source database and destination permissions.');process.exitCode=1;}
}
