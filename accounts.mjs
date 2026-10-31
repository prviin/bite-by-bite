import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {randomBytes,createHash,scrypt as scryptCb,timingSafeEqual,createCipheriv,createDecipheriv} from 'node:crypto';
import {promisify} from 'node:util';
import {join} from 'node:path';
import {validateWellness} from './public/wellness.js';
import {validEntry,estimatePlan} from './public/core.js';
const scrypt=promisify(scryptCb),hash=s=>createHash('sha256').update(s).digest('hex');
export function accounts(directory){
 mkdirSync(directory,{recursive:true,mode:0o700});
 const secretPath=join(directory,'encryption.key');let key;try{key=readFileSync(secretPath);}catch{key=randomBytes(32);writeFileSync(secretPath,key,{mode:0o600,flag:'wx'});}
 const db=new DatabaseSync(join(directory,'accounts.sqlite'));db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, username TEXT UNIQUE, password TEXT, data TEXT, api_key TEXT); CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT,expires INTEGER);');
 const encrypt=s=>{const iv=randomBytes(12),c=createCipheriv('aes-256-gcm',key,iv),body=Buffer.concat([c.update(s,'utf8'),c.final()]);return Buffer.concat([iv,c.getAuthTag(),body]).toString('base64');};
 const decrypt=s=>{if(!s)return '';const b=Buffer.from(s,'base64'),c=createDecipheriv('aes-256-gcm',key,b.subarray(0,12));c.setAuthTag(b.subarray(12,28));return Buffer.concat([c.update(b.subarray(28)),c.final()]).toString();};
 db.exec('CREATE TABLE IF NOT EXISTS chatgpt_connections(user_id TEXT PRIMARY KEY, record TEXT); CREATE TABLE IF NOT EXISTS installation(key TEXT PRIMARY KEY, value TEXT);');
 return {db,
  installation(key,create){const row=db.prepare('SELECT value FROM installation WHERE key=?').get(key);if(row)return row.value;const value=create();db.prepare('INSERT INTO installation VALUES(?,?)').run(key,value);return value;},
  getChatGPT(userId){const row=db.prepare('SELECT record FROM chatgpt_connections WHERE user_id=?').get(userId);return row?JSON.parse(decrypt(row.record)):null;},
  setChatGPT(userId,record){db.prepare('INSERT INTO chatgpt_connections VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET record=excluded.record').run(userId,encrypt(JSON.stringify(record)));},
  user(req){const token=(req.headers.cookie||'').split(';').map(s=>s.trim()).find(s=>s.startsWith('bite_session='))?.slice(13);return token?db.prepare('SELECT users.* FROM users JOIN sessions ON users.id=sessions.user_id WHERE sessions.token=? AND expires>?').get(hash(token),Date.now()):null;},
  async authenticate(username,password,register){
   username=String(username||'').trim().toLowerCase();if(!/^[a-z0-9_.-]{3,40}$/.test(username)||typeof password!=='string'||password.length<10||password.length>256)throw Error('Use a 3–40 character username and a password of 10–256 characters.');
   let user=db.prepare('SELECT * FROM users WHERE username=?').get(username);
   if(register){if(user)throw Error('That username is unavailable.');const salt=randomBytes(16).toString('hex'),derived=await scrypt(password,salt,64),id=randomBytes(16).toString('hex');try{db.prepare('INSERT INTO users VALUES(?,?,?,?,?)').run(id,username,`${salt}:${derived.toString('hex')}`,JSON.stringify({entries:[],goal:2000,weight:70,profile:null,notifications:true}),null);}catch{throw Error('That username is unavailable.');}user=db.prepare('SELECT * FROM users WHERE id=?').get(id);}
   else {const [salt,stored]=(user?.password||`${'0'.repeat(32)}:${'0'.repeat(128)}`).split(':'),derived=await scrypt(password,salt,64);if(!timingSafeEqual(derived,Buffer.from(stored,'hex'))||!user)throw Error('Username or password is incorrect.');}
   const token=randomBytes(32).toString('hex');db.prepare('DELETE FROM sessions WHERE expires<?').run(Date.now());db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(hash(token),user.id,Date.now()+30*86400000);return {user,token};
  },
  logout(req){const token=(req.headers.cookie||'').split(';').map(s=>s.trim()).find(s=>s.startsWith('bite_session='))?.slice(13);if(token)db.prepare('DELETE FROM sessions WHERE token=?').run(hash(token));},
  save(user,data){if(!data||!Array.isArray(data.entries)||data.entries.length>20000||!data.entries.every(validEntry)||new Set(data.entries.map(e=>e.id)).size!==data.entries.length||!Number.isFinite(data.goal)||data.goal<1||data.goal>20000||!Number.isFinite(data.weight)||data.weight<20||data.weight>500)throw Error('Invalid journal data.');if(data.profile){estimatePlan(data.profile);if(data.profile.weight!==data.weight)throw Error('Profile weight does not match.');}const clean={entries:data.entries,goal:data.goal,weight:data.weight,profile:data.profile||null,notifications:!!data.notifications,wellness:validateWellness(data.wellness)};db.prepare('UPDATE users SET data=? WHERE id=?').run(JSON.stringify(clean),user.id);return clean;},
  setKey(user,value){if(typeof value!=='string'||(value&&!/^sk-[\w-]{15,250}$/.test(value)))throw Error('Enter a valid OpenAI API key.');db.prepare('UPDATE users SET api_key=? WHERE id=?').run(value?encrypt(value):null,user.id);},
  getKey(user){return decrypt(user.api_key);}
 };
}
