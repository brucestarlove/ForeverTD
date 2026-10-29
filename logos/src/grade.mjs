// A zone's classic map, stitched from its 4 x 3 tiles (1002 x 668 of the 1024 x
// 768 used) and graded to look as ForeverTD's board shows it in WoW: Forever.
//
// The grade was measured on Bruce's in-game screenshots (2026-10-24: Tiragarde
// Keep for Durotar, The Master's Glaive for Darkshore) against the same tiles:
// land and sea were sampled apart, away from road cells, pieces and labels, and
// each is matched channel by channel (mean and spread). A pixel blends the two
// grades by how land-like it is: blue/red 0.32 or less is land, 0.68 or more sea.
// The numbers are frozen here, so a rebuild doesn't need the screenshots.
import { createRequire } from 'node:module';
import path from 'node:path';
import { CACHE } from './fetch.mjs';
const require = createRequire(import.meta.url);
const sharp = require('sharp');

// [mean, spread] per channel (r, g, b): the tiles' own, and the screenshot's.
const GRADES = {
  Durotar: {
    land: { from: [[155.72, 107.48, 34.2], [22.07, 22.03, 14.41]], to: [[124.03, 82.47, 19.23], [15.4, 15.31, 9.21]] },
    sea: { from: [[129.93, 125.64, 103.98], [14.2, 14.85, 14.23]], to: [[108.03, 103.3, 83.86], [11.71, 13.66, 15.39]] },
  },
  Darkshore: {
    land: { from: [[144.75, 96.44, 17.3], [12.69, 12.64, 11.67]], to: [[123.62, 79.03, 7.35], [14.74, 13.62, 7.76]] },
    sea: { from: [[141.35, 128.15, 101.45], [10.36, 10.59, 11.39]], to: [[116.13, 106.03, 79.17], [14.52, 15.4, 13.1]] },
  },
};

const map = (v, k, g) => (v - g.from[0][k]) / g.from[1][k] * g.to[1][k] + g.to[0][k];

/** The graded map as raw-encoded PNG bytes, 1024 x 768 (the map art is the top-left 1002 x 668). */
export async function gradedMap(zone) {
  const G = GRADES[zone];
  if (!G) throw new Error(`no grade for ${zone}: measure one from a screenshot of its board`);
  const tiles = [];
  for (let i = 0; i < 12; i++) tiles.push({ input: path.join(CACHE, `map-${zone}-${i + 1}.png`), left: (i % 4) * 256, top: Math.floor(i / 4) * 256 });
  const { data, info } = await sharp({ create: { width: 1024, height: 768, channels: 4, background: '#000' } })
    .composite(tiles).raw().toBuffer({ resolveWithObject: true });
  const out = Buffer.alloc(data.length);
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], b = data[i + 2];
    const w = Math.min(1, Math.max(0, (0.68 - (r > 0 ? b / r : 1)) / (0.68 - 0.32)));
    for (let k = 0; k < 3; k++) {
      const sea = map(data[i + k], k, G.sea), land = map(data[i + k], k, G.land);
      out[i + k] = Math.max(0, Math.min(255, Math.round(sea + (land - sea) * w)));
    }
    out[i + 3] = data[i + 3];
  }
  return sharp(out, { raw: { width: info.width, height: info.height, channels: 4 } }).png().toBuffer();
}
