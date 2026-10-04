import {readFile, writeFile, copyFile, mkdir, access} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const lab = resolve(root, 'playground/pet-design');
const destination = resolve(root, 'macos/Resources/characters');
async function readData(file, variable) {
  const text = (await readFile(file, 'utf8')).trim();
  const prefix = `window.${variable} = `;
  if (!text.startsWith(prefix) || !text.endsWith(';')) throw new Error(`Invalid ${variable} data`);
  return JSON.parse(text.slice(prefix.length, -1));
}
// Public clones contain the selected runtime assets, while local experiment archives remain private.
try { await access(resolve(lab, 'production.json')); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  const manifest = JSON.parse(await readFile(resolve(destination, 'character.json'), 'utf8'));
  if (manifest.schemaVersion !== 1 || manifest.states?.length !== 5 ||
      manifest.states.reduce((n, state) => n + state.frames.length, 0) !== 20 ||
      !/^[a-z][a-z0-9-]+\.png$/.test(manifest.atlas)) throw new Error('Invalid bundled character assets');
  await access(resolve(destination, manifest.atlas));
  console.log('Local art laboratory is not included. Keeping the committed five-state runtime assets.');
  process.exit(0);
}
const selection = JSON.parse(await readFile(resolve(lab, 'production.json'), 'utf8'));
if (!/^[a-z][a-z0-9-]+$/.test(selection.selected)) throw new Error('Invalid character selection');
const atlases = await readData(resolve(lab, 'assets/atlas-data.js'), 'PET_ATLASES');
const motions = await readData(resolve(lab, 'assets/motion-data.js'), 'PET_MOTIONS');
const atlas = atlases[selection.selected];
const stateIDs = ['idle', 'working', 'waiting', 'success', 'error'];
if (!atlas || atlas.frames.length !== 20 || motions.length !== 5) throw new Error('Incomplete character atlas');
const states = motions.map((motion, index) => {
  if (motion.id !== stateIDs[index] || motion.durations.length !== 4 || motion.hops.length !== 4 || motion.durations.some(d=>!Number.isFinite(d)||d<=0)) throw new Error('Invalid motion data');
  const frames = atlas.frames.slice(index*4,index*4+4).map(f=>{
    const [left,top,right,bottom] = f.bounds;
    const frame = {x:f.x+left,y:f.y+top,width:right-left,height:bottom-top};
    if (frame.width<=0 || frame.height<=0 || frame.x<0 || frame.y<0 || frame.x+frame.width>atlas.width || frame.y+frame.height>atlas.height) throw new Error('Frame outside atlas');
    return frame;
  });
  return {state:motion.id,durations:motion.durations.map(ms=>ms/1000),hops:motion.hops,frames};
});
const manifest = {schemaVersion:1,id:selection.selected,name:selection.name,atlas:`${selection.selected}.png`,atlasWidth:atlas.width,atlasHeight:atlas.height,canvasSize:selection.canvasSize,padding:selection.padding,states};
await mkdir(destination,{recursive:true});
await copyFile(resolve(lab,'assets',manifest.atlas),resolve(destination,manifest.atlas));
await writeFile(resolve(destination,'character.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Synced ${manifest.name}: ${states.length} states / ${states.reduce((n,s)=>n+s.frames.length,0)} frames. Playground source preserved.`);
