import { build } from 'esbuild';
import { mkdir, writeFile } from 'node:fs/promises';
await mkdir('lib', { recursive: true });
await build({ entryPoints: ['src/index.ts'], outfile: 'lib/index.js', bundle: true, platform: 'node', format: 'esm', target: 'node24' });
const client = await build({ entryPoints: ['src/client.ts'], bundle: true, platform: 'browser', format: 'cjs', target: 'es2022', write: false });
await writeFile('lib/client.js', `window.__ModuleLoader__.load({id:"dsh-always-on",factory:(require)=>{var module={exports:{}};var exports=module.exports;\n${client.outputFiles[0].text}\nreturn module.exports;}});\n`);
await build({ entryPoints: ['src/model.ts', 'src/bridge.ts', 'src/navigation.ts', 'src/view.ts'], outdir: 'lib', platform: 'node', format: 'esm', target: 'node24' });
