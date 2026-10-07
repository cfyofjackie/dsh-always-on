import {readFile,writeFile,copyFile,access} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const lab=resolve(root,'playground/pet-design');
const destination=resolve(root,'macos/Resources/characters');
const json=async path=>JSON.parse(await readFile(path,'utf8'));
async function validateBundled(){
 const data=await json(resolve(destination,'life.json'));
 if(data.schemaVersion!==1||data.clips.length!==4)throw Error('Invalid life animations');
 for(const [i,clip] of data.clips.entries()){
  if(clip.animation!==['rice','toy','pet','whale'][i]||clip.frames.length!==[24,23,8,24][i]||clip.frames.length!==clip.durations.length||clip.durations.some(x=>!Number.isFinite(x)||x<=0))throw Error('Invalid life clip');
  for(const f of clip.frames){if(!/^[a-z0-9-]+\.png$/.test(f.file))throw Error('Invalid asset path');await access(resolve(destination,f.file));}
 }
}
try {await access(resolve(lab,'motion-rice/timing.mjs'));await access(resolve(lab,'motion-toy/recovered-frames.json'));await access(resolve(lab,'motion-life-fixed/frames.json'));}
catch(error){if(error.code!=='ENOENT')throw error;await validateBundled();console.log('Keeping bundled approved life animations (no local lab).');process.exit(0);}
const data=await json(resolve(lab,'motion-v2/assets/atlas-data.json'));
const rice=await import(pathToFileURL(resolve(lab,'motion-rice/timing.mjs')));
const toy=await import(pathToFileURL(resolve(lab,'motion-toy/timing.mjs')));
const recovered=await json(resolve(lab,'motion-toy/recovered-frames.json'));
const clips=[];
for(const id of ['rice','toy']){
 const atlas=data.atlases[id],order=id==='rice'?atlas.frames.map((_,i)=>i):toy.ORDER;
 const frames=order.map(index=>{
  const fix=id==='toy'?recovered.frames[String(index+1)]:null;
  const f=fix||atlas.frames[index];
  return {file:fix?`life-toy-${index+1}.png`:`life-${id}.png`,sourcePose:index+1,
   x:fix?0:f.x,y:fix?0:f.y,width:f.w,height:f.h,anchorX:f.anchorX,footY:f.footY};
 });
 clips.push({animation:id,normalHeight:atlas.normalHeight,durations:(id==='rice'?rice.RETIMED:toy.HOLDS).map(x=>x/1000),rest:id==='rice'?rice.REST_BY_PROFILE.retimed/1000:2,frames});
 await copyFile(resolve(lab,'motion-v2',atlas.file),resolve(destination,`life-${id}.png`));
}
for(const number of [16,17])await copyFile(resolve(lab,'motion-toy',recovered.frames[String(number)].file),resolve(destination,`life-toy-${number}.png`));
const fixed=await json(resolve(lab,'motion-life-fixed/frames.json'));
const timing=await import(pathToFileURL(resolve(lab,'motion-v2/timing.mjs')));
for(const id of ['pet','whale']){
 const motion=fixed.clips[id],frames=[];
 for(const [index,f] of motion.frames.entries()){
  const file=`life-${id}-${String(index+1).padStart(2,'0')}.png`;
  await copyFile(resolve(lab,'motion-life-fixed',f.file),resolve(destination,file));
  frames.push({file,sourcePose:index+1,x:0,y:0,width:f.w,height:f.h,anchorX:f.anchorX,footY:f.footY});
 }
 clips.push({animation:id,normalHeight:motion.normalHeight,durations:timing.FRAME_MS[id].map(ms=>ms/1000),rest:2,frames});
}
await writeFile(resolve(destination,'life.json'),JSON.stringify({schemaVersion:1,clips},null,2)+'\n');
await validateBundled();
console.log('Synced four approved life animations (79 poses), including head-pat (8 / 2.2s) and whale-pat (24 / 5.4s). Laboratory preserved.');
