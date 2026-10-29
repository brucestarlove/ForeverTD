// ForeverTD's logo: one moment of a real level, drawn the way the game draws its
// board, inside WoW's gold dialog border.
//   - Every measure and colour on the board is Board.lua's (0.4.8): 36 px cells,
//     tower frames 32 and icons 28 (cropped 0.08-0.92), round creep tokens with
//     a 4 px health bar, road cells at 0.55, the gold selection and range ring,
//     rank pips, the campaign's colour darkened for frames, gold for heroes.
//   - The bolts follow Engine.lua: the tower hits the creep in range that's
//     closest to getting through, and each jump goes to the nearest creep not
//     yet hit within its reach. A scene names the shot; the bolts aren't drawn
//     by hand.
//   - One liberty: the game flickers its lightning; a still gets a soft glow
//     and a kink every ~10 game px instead of one frame's few.
import { createRequire } from 'node:module';
import path from 'node:path';
import { CACHE } from './fetch.mjs';
import { gradedMap } from './grade.mjs';
const require = createRequire(import.meta.url);
const sharp = require('sharp');

const cache = (f) => path.join(CACHE, f);

// Board.lua
const CELL = 36;                                  // game px per cell
const GOLD = [1, 0.82, 0];                        // selection, range ring
const HERO = [1, 0.75, 0.15];                     // a hero's frame
const GREY_PIP = [0.25, 0.25, 0.25];
const PIP = { 0: [1, 0.82, 0], 4: [1, 0.45, 0.1], 5: [0.35, 0.8, 1] }; // ranks 1-3 gold; 4, 5 the specializations
const ROAD = [0.16, 0.1, 0.04];                   // road cells, at 0.55
const DISC = { normal: [0.08, 0.08, 0.08], boss: [1, 0.82, 0], air: [0.55, 0.8, 1], stealth: [0.3, 0.12, 0.4] };
const BAR = [0.25, 0.9, 0.2];                     // health
const LIGHTNING = [0.55, 0.75, 1];                // chain lightning; a glaive is silver (0.9, 0.9, 1), straight, 0.6 wide
const CAMPAIGN = { horde: [0.78, 0.18, 0.1], alliance: [0.2, 0.42, 0.9], sentinels: [0.55, 0.35, 0.85], forsaken: [0.35, 0.75, 0.3] };
const WINDOW = [0.04, 0.04, 0.05];                // Ui.lua's backdrop

const rgb = (c) => `rgb(${c.map((v) => Math.round(v * 255)).join(',')})`;
const b64 = (buf) => `data:image/png;base64,${buf.toString('base64')}`;
const svg = (px, view, body) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 ${view} ${view}">${body}</svg>`);

/** An icon as the game shows it, at `px` device pixels: a tower's cropped to 0.08-0.92, a creep's whole. */
async function icon(name, px, crop) {
  let img = sharp(cache(`icon-${name}.png`));
  if (crop) img = img.extract({ left: 5, top: 5, width: 54, height: 54 });
  return img.resize(Math.round(px), Math.round(px), { kernel: 'lanczos3' }).png().toBuffer();
}

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

/** A bolt from a to b: kinks up to the game's min(11, 0.2 x length) game px, one every ~10. A glaive flies straight. */
function boltPath(a, b, gp, seed, straight) {
  if (straight) return `M${a[0].toFixed(2)} ${a[1].toFixed(2)} L${b[0].toFixed(2)} ${b[1].toFixed(2)}`;
  const r = rng(seed);
  const dx = b[0] - a[0], dy = b[1] - a[1], dist = Math.hypot(dx, dy);
  const n = Math.max(3, Math.min(14, Math.round(dist / gp / 10)));
  const amp = Math.min(11, (dist / gp) * 0.2) * gp;
  const nx = -dy / dist, ny = dx / dist;
  const pts = [a];
  for (let k = 1; k < n; k++) {
    const f = k / n, side = k % 2 ? 1 : -1;
    const off = side * (0.35 + 0.65 * r()) * amp * Math.sin(Math.PI * f) ** 0.5;
    pts.push([a[0] + dx * f + nx * off, a[1] + dy * f + ny * off]);
  }
  pts.push(b);
  return pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`).join(' ');
}

/** WoW's backdrop border from its 8-segment edge file (left, right, top, bottom, then the corners), edges tiled. */
async function border(size, edge) {
  const file = cache('UI-DialogBox-Gold-Border.png');
  const seg = async (i, rotate) => {
    let buf = await sharp(file).extract({ left: i * 32, top: 0, width: 32, height: 32 }).png().toBuffer();
    if (rotate) buf = await sharp(buf).rotate(90).png().toBuffer();
    return sharp(buf).resize(edge, edge, { kernel: 'lanczos3' }).png().toBuffer();
  };
  const [L, R, T, B, TL, TR, BL, BR] = [await seg(0), await seg(1), await seg(2, true), await seg(3, true), await seg(4), await seg(5), await seg(6), await seg(7)];
  const comp = [];
  const span = size - 2 * edge;
  for (let o = 0; o < span; o += edge) {
    const len = Math.min(edge, span - o);
    const cut = (buf, vertical) => (len === edge ? buf : sharp(buf).extract(vertical ? { left: 0, top: 0, width: edge, height: len } : { left: 0, top: 0, width: len, height: edge }).png().toBuffer());
    comp.push({ input: await cut(L, true), left: 0, top: edge + o });
    comp.push({ input: await cut(R, true), left: size - edge, top: edge + o });
    comp.push({ input: await cut(T, false), left: edge + o, top: 0 });
    comp.push({ input: await cut(B, false), left: edge + o, top: size - edge });
  }
  comp.push({ input: TL, left: 0, top: 0 }, { input: TR, left: size - edge, top: 0 }, { input: BL, left: 0, top: size - edge }, { input: BR, left: size - edge, top: size - edge });
  return sharp({ create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).composite(comp).png().toBuffer();
}

// ---- Engine.lua's rules ----

/** Road cells in walking order -> a polyline through their centres, entering from beyond the first. */
function roadLine(road) {
  const c = road.map(([x, y]) => [x + 0.5, y + 0.5]);
  return [[2 * c[0][0] - c[1][0], 2 * c[0][1] - c[1][1]], ...c];
}

/** How far along the road a point is, in cells: more is closer to getting through. */
function progress(line, [x, y]) {
  let best = Infinity, at = 0, run = 0;
  for (let i = 0; i < line.length - 1; i++) {
    const [ax, ay] = line[i], [bx, by] = line[i + 1];
    const dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy);
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (len * len)));
    const d = Math.hypot(ax + dx * t - x, ay + dy * t - y);
    if (d < best) { best = d; at = run + t * len; }
    run += len;
  }
  return at;
}

/** Targets(): the creep in range closest to getting through. Chain(): then the nearest not yet hit within `jump`. */
export function shotBolts(scene) {
  const s = scene.shot;
  const tower = scene.towers.find((t) => t.id === s.tower);
  const tc = [tower.at[0] + 0.5, tower.at[1] + 0.5];
  const line = roadLine(scene.road);
  const inRange = scene.creeps.filter((c) => Math.hypot(c.at[0] - tc[0], c.at[1] - tc[1]) <= s.range);
  if (!inRange.length) return [];
  const first = inRange.reduce((a, b) => (progress(line, b.at) > progress(line, a.at) ? b : a));
  const bolts = [{ from: tower.id, to: first.id, seed: 7, spin: 10 }];
  const hit = new Set([first.id]);
  let from = first;
  for (let k = 0; k < s.chain; k++) {
    let best, bestD = Infinity;
    for (const c of scene.creeps) {
      if (hit.has(c.id)) continue;
      const d = Math.hypot(c.at[0] - from.at[0], c.at[1] - from.at[1]);
      if (d <= s.jump && d < bestD) { best = c; bestD = d; }
    }
    if (!best) break;
    bolts.push({ from: from.id, to: best.id, seed: 3 + k * 2, spin: 35 + k * 25 });
    hit.add(best.id);
    from = best;
  }
  return bolts;
}

/** Pieces closer than `min` logo px to each other or to the board's edge (towers with their selection, tokens with their bars). */
export function crowding(scene, min = 8) {
  const S = scene.size, inset = scene.frame.edge * scene.frame.inset;
  const u = (S - 2 * inset) / scene.cells, gp = u / CELL;
  const boxes = [];
  for (const t of scene.towers) {
    const h = (t.selected ? CELL : CELL - 4) * gp / 2, cx = inset + (t.at[0] + 0.5) * u, cy = inset + (t.at[1] + 0.5) * u;
    boxes.push({ id: t.id, x0: cx - h, x1: cx + h, y0: cy - h, y1: cy + h });
  }
  for (const c of scene.creeps) {
    const r = (c.size ?? 24) * gp / 2, cx = inset + c.at[0] * u, cy = inset + c.at[1] * u;
    boxes.push({ id: c.id, x0: cx - r, x1: cx + r, y0: cy - r, y1: cy + r + 2 * gp });
  }
  const out = [];
  for (let i = 0; i < boxes.length; i++) {
    const a = boxes[i];
    const edge = Math.min(a.x0 - inset, a.y0 - inset, S - inset - a.x1, S - inset - a.y1);
    if (edge < min) out.push(`${a.id} is ${edge.toFixed(1)} px from the board's edge`);
    for (let j = i + 1; j < boxes.length; j++) {
      const b = boxes[j];
      const gap = Math.hypot(Math.max(0, b.x0 - a.x1, a.x0 - b.x1), Math.max(0, b.y0 - a.y1, a.y0 - b.y1));
      if (gap < min) out.push(`${a.id} and ${b.id}: ${gap.toFixed(1)} px apart`);
    }
  }
  return out;
}

// ---- Drawing ----

export async function render(scene) {
  const S = scene.size, X = scene.scale, D = S * X;
  const E = scene.frame.edge, inset = E * scene.frame.inset;
  const B = S - 2 * inset, u = B / scene.cells, gp = u / CELL;
  const P = ([c, r]) => [inset + c * u, inset + r * u];
  const centre = ([c, r]) => P([c + 0.5, r + 0.5]);
  const tint = CAMPAIGN[scene.campaign].map((v) => v * 0.45);

  const m = scene.map;
  const mapBuf = await sharp(await gradedMap(m.zone)).extract({ left: m.left, top: m.top, width: m.width, height: m.width })
    .resize(Math.round(B * X), Math.round(B * X), { kernel: 'lanczos3' }).png().toBuffer();

  const at = {};
  for (const c of scene.creeps) at[c.id] = { p: P(c.at), r: ((c.size ?? 24) * gp) / 2 };
  for (const t of scene.towers) at[t.id] = { p: centre(t.at), r: ((CELL - 4) * gp) / 2, square: true };
  /** From a's rim (a square's edge, for a tower) to b's, along the line between their centres. */
  const rims = (a, b) => {
    const A = at[a], Z = at[b];
    const dx = Z.p[0] - A.p[0], dy = Z.p[1] - A.p[1], d = Math.hypot(dx, dy), ux = dx / d, uy = dy / d;
    const ka = A.square ? Math.min(Math.abs(1 / ux || Infinity), Math.abs(1 / uy || Infinity)) * A.r : A.r;
    return [[A.p[0] + ux * ka * 0.98, A.p[1] + uy * ka * 0.98], [Z.p[0] - ux * Z.r * 0.92, Z.p[1] - uy * Z.r * 0.92]];
  };

  const defs = [`<clipPath id="board"><rect x="${inset}" y="${inset}" width="${B}" height="${B}"/></clipPath>`];
  const parts = [`<rect width="${S}" height="${S}" fill="${rgb(WINDOW)}"/>`, `<g clip-path="url(#board)">`];
  parts.push(`<image href="${b64(mapBuf)}" x="${inset}" y="${inset}" width="${B}" height="${B}" preserveAspectRatio="none"/>`);
  for (const cell of scene.road) {
    const [x, y] = P(cell);
    parts.push(`<rect x="${x}" y="${y}" width="${u}" height="${u}" fill="${rgb(ROAD)}" fill-opacity="0.55"/>`);
  }
  const ringAt = at[scene.shot.tower].p;
  parts.push(`<circle cx="${ringAt[0]}" cy="${ringAt[1]}" r="${scene.shot.range * u}" fill="${rgb(GOLD)}" fill-opacity="0.14"/>`);
  for (const t of scene.towers) {
    const [x, y] = centre(t.at);
    if (t.id === scene.shot.tower) parts.push(`<rect x="${x - u / 2}" y="${y - u / 2}" width="${u}" height="${u}" fill="${rgb(GOLD)}" fill-opacity="0.9"/>`);
    const f = (CELL - 4) * gp, s = (CELL - 8) * gp;
    parts.push(`<rect x="${x - f / 2}" y="${y - f / 2}" width="${f}" height="${f}" fill="${rgb(t.hero ? HERO : tint)}" fill-opacity="0.95"/>`);
    parts.push(`<image href="${b64(await icon(t.icon, s * X, true))}" x="${x - s / 2}" y="${y - s / 2}" width="${s}" height="${s}"/>`);
    if (!t.hero) {
      const lit = PIP[t.rank] ?? PIP[0];
      for (let i = 0; i < 3; i++) {
        const px = x + (-10 + i * 10) * gp, py = y + 13 * gp;
        parts.push(`<rect x="${px - 3 * gp}" y="${py - 1.5 * gp}" width="${6 * gp}" height="${3 * gp}" fill="${rgb(i < t.rank ? lit : GREY_PIP)}"/>`);
      }
    }
  }
  for (const [i, c] of scene.creeps.entries()) {
    const size = (c.size ?? 24) * gp, [x, y] = P(c.at), s = size - 4 * gp;
    parts.push(`<circle cx="${x}" cy="${y}" r="${size / 2}" fill="${rgb(DISC[c.boss ? 'boss' : c.air ? 'air' : c.stealth ? 'stealth' : 'normal'])}"/>`);
    defs.push(`<clipPath id="t${i}"><circle cx="${x}" cy="${y}" r="${s / 2}"/></clipPath>`);
    parts.push(`<image href="${b64(await icon(c.icon, s * X, false))}" x="${x - s / 2}" y="${y - s / 2}" width="${s}" height="${s}" clip-path="url(#t${i})"/>`);
    const by = y + size / 2 - 2 * gp;
    parts.push(`<rect x="${x - size / 2}" y="${by}" width="${size}" height="${4 * gp}" fill="#000" fill-opacity="0.85"/>`);
    parts.push(`<rect x="${x - size / 2 + gp}" y="${by + gp}" width="${(size - 2 * gp) * (c.hp ?? 1)}" height="${2 * gp}" fill="${rgb(BAR)}"/>`);
  }
  if (scene.vignette) {
    defs.push(`<radialGradient id="vig" cx="50%" cy="50%" r="72%"><stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="${scene.vignette}"/></radialGradient>`);
    parts.push(`<rect x="${inset}" y="${inset}" width="${B}" height="${B}" fill="url(#vig)"/>`);
  }
  parts.push(`</g>`);
  const board = await sharp(svg(D, S, `<defs>${defs.join('')}</defs>${parts.join('')}`)).png().toBuffer();

  // Light is added, as the game blends it: a blurred glow layer, then the cores, stars and flashes.
  const glow = [], core = [];
  const star = b64(await sharp(cache('star4.png')).png().toBuffer());
  const glaive = scene.shot.kind === 'glaive';
  const L = glaive ? [0.9, 0.9, 1] : LIGHTNING, w = glaive ? 0.6 : 1;
  const gl = [L[0] * 0.55, L[1] * 0.65, L[2]], co = [0.75 + L[0] * 0.25, 0.8 + L[1] * 0.2, 1];
  for (const bolt of shotBolts(scene)) {
    const [a, b] = rims(bolt.from, bolt.to);
    const d = boltPath(a, b, gp, bolt.seed, glaive);
    const line = (c, width, opacity = 1) => `<path d="${d}" fill="none" stroke="${rgb(c)}" stroke-opacity="${opacity}" stroke-width="${width * w * gp}" stroke-linecap="round" stroke-linejoin="round"/>`;
    glow.push(line(gl, 9));
    core.push(line(gl, 4, 0.7), line(co, 1.6));
    glow.push(`<circle cx="${b[0]}" cy="${b[1]}" r="${7 * gp}" fill="${rgb([0.7, 0.85, 1])}" fill-opacity="0.55"/>`);
    const st = 14 * gp;
    core.push(`<g transform="rotate(${bolt.spin} ${b[0]} ${b[1]})" opacity="0.85"><image href="${star}" x="${b[0] - st / 2}" y="${b[1] - st / 2}" width="${st}" height="${st}"/></g>`);
    if (at[bolt.from].square) glow.push(`<circle cx="${a[0]}" cy="${a[1]}" r="${8 * gp}" fill="${rgb(L)}" fill-opacity="0.6"/>`);
  }
  const light = (body) => svg(D, S, `<rect width="${S}" height="${S}" fill="#000"/><clipPath id="b"><rect x="${inset}" y="${inset}" width="${B}" height="${B}"/></clipPath><g clip-path="url(#b)">${body}</g>`);
  const glowLayer = await sharp(light(glow.join(''))).blur(Math.max(0.3, 5 * gp * X)).png().toBuffer();
  const coreLayer = await sharp(light(core.join(''))).png().toBuffer();
  const full = await sharp(board)
    .composite([{ input: glowLayer, blend: 'add' }, { input: coreLayer, blend: 'add' }, { input: await border(D, Math.round(E * X)) }])
    .png().toBuffer();
  return sharp(full).resize(S, S, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toBuffer();
}
