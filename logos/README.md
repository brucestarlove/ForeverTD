# ForeverTD's logo

One moment of a real level, drawn the way the game draws its board, from WoW's own art, in WoW's gold dialog border. Bruce, 2026-10-24: "we use wow assets and it looks very pretty".

**The logo is `forevertd-horde-512.png`** (Bruce, 2026-10-24: "the Horde!"). It's the CurseForge page's logo, and lavitz.starlove.world shows it on ForeverTD's page and share card. The Sentinels' scene was the other candidate; it stays for a Sentinels post or banner.

| File | The moment |
| --- | --- |
| `forevertd-horde-512.png` | **The logo.** **Tiragarde Keep**, the Horde's fourth level, on Durotar's coast: Kul Tiras sailors and marines come up from the docks with Lieutenant Benedict near the front, and a Shaman's chain lightning runs down their column. Thrall and a Headhunter hold the road. |
| `forevertd-sentinels-512.png` | **The Master's Glaive**, the Sentinels' sixth level, on Darkshore's coast: a Sentinel Archer's moonglaive bounces from Delmanis the Hated to a flying Cursed Highborne, a Blackwood bear and a Greymist murloc. Tyrande and a Moonwell stand by. |

The addon's own icon in the AddOns list stays a stock WoW icon (`## IconTexture` in the TOC), so the addon still ships no art. If the logo changes, copy the new PNG to lavitz-site's `src/assets/work/forevertd-logo.png` too.

## Every piece could happen in the game

- **The board** is drawn with Board.lua's measures and colours (0.4.8): 36 px cells, tower frames in the campaign's colour darkened (a hero's in gold), icons cropped as the game crops them, round creep tokens on their discs (gold for a boss, blue for a flyer) with 4 px health bars, road cells at 0.55, the selected tower's gold square and range ring, rank pips (gold; blue for a second specialization).
- **The shot follows Engine.lua.** A tower hits the creep in range that's closest to getting through, and the lightning (or glaive) jumps to the nearest creep not yet hit within its reach. Each scene names its tower and shot; `compose.mjs` works out the bolts.
- **The scenes are legal:** the Shaman joins at level 4 and Thrall at 5, so he's there on a replay of Tiragarde Keep; the Archer's glaives bounce only with Moonglaive (rank 5); every creep is one its level sends. `scenes/*.json` says which.
- **One liberty:** the game flickers its lightning; a still gets a soft glow and a kink every ~10 game px instead of one frame's few.

## The art

All from Gethe's mirror of the game's interface files (github.com/Gethe/wow-ui-textures), downloaded at build time and not kept here:

- the zone map tiles, from the `classic` branch: WoW: Forever paints the classic world (Tiragarde Keep's board matched them exactly);
- the icons, the gold dialog border and the star sprite, from `live`: WoW: Forever runs the retail client.

The maps are graded to look as WoW: Forever shows them. The grade was measured on Bruce's screenshots of Tiragarde Keep and The Master's Glaive (land and sea apart, channel by channel) and is frozen in `src/grade.mjs`, so a rebuild doesn't need the screenshots. Another zone needs a screenshot of one of its boards first.

## Rebuild

```sh
cd logos/src
npm install        # sharp, for this folder only
npm run build      # downloads what it needs into .cache/, then writes ../forevertd-<scene>-512.png
```

The build stops if pieces come within 8 px of each other or of the board's edge. To change a logo, edit its scene: the map window (`map`: the zone, and a square of its 1002 x 668 map), the road cells in walking order, the towers and creeps (in cells), and the shot.
