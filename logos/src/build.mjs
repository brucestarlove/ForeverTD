// Builds every scene in scenes/ into ../forevertd-<scene>-512.png.
//   cd logos/src && npm install && npm run build
// It downloads the WoW textures it needs first (fetch.mjs), and stops if a
// scene's pieces crowd each other or the board's edge (closer than 8 px).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchAll } from './fetch.mjs';
import { crowding, render, shotBolts } from './compose.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
console.log(`fetched ${await fetchAll()} new textures`);
let failed = false;
for (const f of fs.readdirSync(path.join(HERE, 'scenes')).filter((f) => f.endsWith('.json')).sort()) {
  const name = f.replace(/\.json$/, '');
  const scene = JSON.parse(fs.readFileSync(path.join(HERE, 'scenes', f), 'utf8'));
  const crowded = crowding(scene);
  console.log(`${name}: ${shotBolts(scene).map((b) => `${b.from} > ${b.to}`).join(', ')}`);
  if (crowded.length) {
    for (const c of crowded) console.log(`  crowded: ${c}`);
    failed = true;
    continue;
  }
  const out = path.join(HERE, '..', `forevertd-${name}-512.png`);
  fs.writeFileSync(out, await render(scene));
  console.log(`  ${path.relative(path.join(HERE, '..'), out)}`);
}
process.exit(failed ? 1 : 0);
