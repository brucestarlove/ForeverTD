// Downloads the WoW textures the scenes use into .cache/, from Gethe's mirror of
// the game's interface files (github.com/Gethe/wow-ui-textures):
//   - the zone map tiles from the `classic` branch: WoW: Forever paints the
//     classic world (a Tiragarde Keep screenshot matched them exactly);
//   - icons and UI art from `live`: WoW: Forever runs the retail client.
// Files already in .cache/ are kept.  node fetch.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CACHE = path.join(HERE, '.cache');
const RAW = 'https://raw.githubusercontent.com/Gethe/wow-ui-textures';

/** Every file the scenes need: [branch, path in the repo, file in .cache/]. */
export function wanted() {
  const files = [
    ['live', 'DialogFrame/UI-DialogBox-Gold-Border.PNG', 'UI-DialogBox-Gold-Border.png'],
    ['live', 'Cooldown/star4.PNG', 'star4.png'],
  ];
  const scenes = fs.readdirSync(path.join(HERE, 'scenes')).filter((f) => f.endsWith('.json'));
  const zones = new Set(), icons = new Set();
  for (const f of scenes) {
    const s = JSON.parse(fs.readFileSync(path.join(HERE, 'scenes', f), 'utf8'));
    zones.add(s.map.zone);
    for (const p of [...s.towers, ...s.creeps]) icons.add(p.icon);
  }
  for (const z of zones) for (let i = 1; i <= 12; i++) files.push(['classic', `WorldMap/${z}/${z}${i}.PNG`, `map-${z}-${i}.png`]);
  for (const n of icons) files.push(['live', `ICONS/${n}.PNG`, `icon-${n}.png`]);
  return files;
}

export async function fetchAll() {
  fs.mkdirSync(CACHE, { recursive: true });
  let got = 0;
  for (const [branch, from, to] of wanted()) {
    const dest = path.join(CACHE, to);
    if (fs.existsSync(dest)) continue;
    const res = await fetch(`${RAW}/${branch}/${from}`);
    if (!res.ok) throw new Error(`${branch}/${from}: ${res.status}`);
    fs.writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
    got++;
  }
  return got;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(`fetched ${await fetchAll()} files into .cache/`);
}
