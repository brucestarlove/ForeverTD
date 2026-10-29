-- Board.lua - the board of one level, drawn inside the game window: the zone's map art, the road, towers, creep
-- tokens, shots and effects. It draws the engine's state and events and never decides anything; clicks go to
-- Board.onClick (set by Ui.lua). Every frame, texture and line is pooled, and a frame's update allocates nothing.
--
-- Effects (Board.OnEvents turns the engine's events into them): jagged lightning bolts that flicker between the
-- creeps chain lightning jumps to, impact sparks for every shot, explosions with a fireball, a shockwave and smoke,
-- rings of sparkles for pulses, falling stars, plague wisps, tower muzzle flashes, creeps that shrink and fade when
-- they die, a shake of the board for the biggest blasts and boss stomps, and floating numbers. All of it is capped
-- (MAX_SPRITES, MAX_BOLTS, MAX_FLOATERS: the oldest gives way), and Board.fx = 1 keeps only the essentials.
-- Textures come from the client: a white disc (the round portrait mask), the cooldown star (Interface\Cooldown\star4,
-- used by several Forever game addons) and solid colour; lines are Line regions (another Forever game draws its
-- grid with them on this client).
local _, ns = ...
local Engine, Content, Levels = ns.Engine, ns.Content, ns.Levels
local Board = {}
ns.Board = Board

local CELL = 36
Board.CELL = CELL
local PX = CELL / Engine.CELL -- pixels per milli-cell
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a white disc; also the round token mask
local STAR = "Interface\\Cooldown\\star4"
local FALLBACK_ART = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"
local MAX_TILES, MAX_SPRITES, MAX_UNDER, MAX_BOLTS, MAX_FLOATERS, MAX_SEGMENTS = 64, 160, 40, 28, 20, 6
local floor, min, max, sqrt, sin, cos, pi = math.floor, math.min, math.max, math.sqrt, math.sin, math.cos, math.pi

local frame, art, under, towersLayer, tokensLayer, over
local paint -- the board's own Board.Paint target
local tokens, freeTokens, dying = {}, {}, {} -- creep id -> token frame; tokens fading out
local views, freeViews = {}, {}     -- tower id -> { textures }
local shotTex, shotsShown = {}, 0
local pools = { under = { list = {}, next = 1 }, over = { list = {}, next = 1 } } -- sprites under and over tokens
local bolts, boltNext = {}, 1
local floaters, floatNext = {}, 1
local hover, ring, auraRing, ghost, ward
local state, artFor
local drawn = {} -- what the hover was last drawn for, so a still cursor costs nothing
local gen = 0
local shake = { until_ = 0, power = 0, x = 0, y = 0 }
local anchor = { x = 0, y = 0 } -- where Ui put the board, so a shake can return it exactly
local tint = { 0.12, 0.12, 0.12 } -- the campaign's colour, darkened, for tower frames

Board.placing = nil   -- tower kind being placed, or nil
Board.selected = nil  -- selected tower id, or nil
Board.onClick = function() end
Board.fx = 2          -- 2: every effect; 1: the essentials (Options: Effects)

-- A small seeded generator for the look of things (bolt kinks, sparkle angles). Presentation only: it never touches
-- the game, which has its own (Engine.Random).
local seed = 4242
local function Rand()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
end

local function At(region, x, y) -- centre a region on board pixel (x, y), measured from the top left
    region:ClearAllPoints()
    region:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
end

local function CellCentre(c, r) return (c - 0.5) * CELL, (r - 0.5) * CELL end

local function Layer(level)
    local f = CreateFrame("Frame", nil, frame)
    f:SetAllPoints(frame)
    f:SetFrameLevel(frame:GetFrameLevel() + level)
    return f
end

local function Disc(layer, sub)
    local t = layer:CreateTexture(nil, "ARTWORK", nil, sub or 0)
    t:SetTexture(CIRCLE)
    return t
end

function Board.Create(parent)
    frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(16 * CELL, 10 * CELL)
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    art, under, towersLayer = Layer(1), Layer(2), Layer(3)
    tokensLayer, over = Layer(5), Layer(8)
    art.dim = art:CreateTexture(nil, "BORDER")
    art.dim:SetAllPoints(frame)
    art.dim:SetColorTexture(0, 0, 0, 0.18)
    paint = { layer = art, anchor = frame, tiles = {}, cells = {}, shown = 0, dim = art.dim }
    hover = under:CreateTexture(nil, "ARTWORK")
    hover:SetSize(CELL, CELL)
    hover:Hide()
    ring = Disc(under, 1)
    ring:Hide()
    auraRing = Disc(under, 2)
    auraRing:Hide()
    ward = Disc(under, 3) -- Divine Shield's glow where the road leaves the board
    ward:SetBlendMode("ADD")
    ward:Hide()
    ghost = over:CreateTexture(nil, "OVERLAY")
    ghost:SetSize(CELL - 6, CELL - 6)
    ghost:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost:SetAlpha(0.6)
    ghost:Hide()
    frame:SetScript("OnMouseUp", function(_, button)
        local c, r = Board.CursorCell()
        if c then Board.onClick(c, r, button) end
    end)
    Board.frame = frame
    return frame
end

-- Where the board sits in its parent (Ui calls this instead of SetPoint, so a shake can put it back).
function Board.Place(parent, x, y)
    anchor.parent, anchor.x, anchor.y = parent, x, y
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

-- The cell under the cursor, or nil.
function Board.CursorCell()
    if not state then return nil end
    local level = state._level
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return nil end
    local c, r = floor((x / scale - left) / CELL) + 1, floor((top - y / scale) / CELL) + 1
    if c < 1 or r < 1 or c > level.cols or r > level.rows then return nil end
    return c, r
end

-- Paints a level's picture and road into p = { layer = frame to draw on, anchor = frame to align to, tiles = {},
-- cells = {}, shown = 0, dim = texture or nil }, scaled to w pixels wide. The board uses it, and so do the menu's
-- level thumbnails. The picture is level.art.file (an image of our own), or the zone's painted map art cropped to
-- level.art (the same tiling as Dev/Maps.lua, which showed it works), or parchment when the client has no map art.
function Board.Paint(p, level, w)
    for _, t in ipairs(p.tiles) do t:Hide() end
    local a = level.art or { left = 0, top = 0, width = 1 }
    if p.dim then p.dim:SetColorTexture(0, 0, 0, a.dim or 0.18) end
    local function Tile(i)
        local t = p.tiles[i] or p.layer:CreateTexture(nil, "BACKGROUND")
        p.tiles[i] = t
        t:ClearAllPoints()
        t:Show()
        return t
    end
    local function Whole(file, coords)
        local t = Tile(1)
        t:SetTexture(file)
        if coords then t:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else t:SetTexCoord(0, 1, 0, 1) end
        t:SetAllPoints(p.anchor)
    end
    local layers, files
    if not a.file and C_Map and type(C_Map.GetMapArtLayers) == "function" then
        local okL, l = pcall(C_Map.GetMapArtLayers, level.map)
        local okT, f = pcall(C_Map.GetMapArtLayerTextures, level.map, 1)
        layers, files = okL and l or nil, okT and f or nil
    end
    local layer = type(layers) == "table" and layers[1]
    if a.file then
        Whole(a.file, a.coords)
    elseif not (layer and type(files) == "table" and #files > 0) then
        Whole(FALLBACK_ART)
    else
        local s = w / (a.width * layer.layerWidth)
        local cols = math.ceil(layer.layerWidth / layer.tileWidth)
        local tw, th = layer.tileWidth * s, layer.tileHeight * s
        local ox, oy = a.left * layer.layerWidth * s, a.top * layer.layerHeight * s
        for i = 1, min(#files, MAX_TILES) do
            local t = Tile(i)
            t:SetTexture(files[i])
            t:SetTexCoord(0, 1, 0, 1)
            t:SetSize(tw, th)
            t:SetPoint("TOPLEFT", p.anchor, "TOPLEFT", ((i - 1) % cols) * tw - ox, -(floor((i - 1) / cols) * th - oy))
        end
    end
    local geo, size, n = Engine.Geometry(level), w / level.cols, 0
    for r = 1, level.rows do
        for c = 1, level.cols do
            local key = (r - 1) * level.cols + c
            if geo.road[key] or geo.blocked[key] then
                n = n + 1
                local t = p.cells[n] or p.layer:CreateTexture(nil, "ARTWORK")
                p.cells[n] = t
                t:SetSize(size, size)
                t:ClearAllPoints()
                t:SetPoint("CENTER", p.anchor, "TOPLEFT", (c - 0.5) * size, -(r - 0.5) * size)
                if geo.road[key] then t:SetColorTexture(0.16, 0.1, 0.04, 0.55) else t:SetColorTexture(0, 0, 0, 0.55) end
                t:Show()
            end
        end
    end
    for i = n + 1, p.shown do p.cells[i]:Hide() end
    p.shown = n
end

------------------------------------------------------------------------------------------------------------------------
-- Icons: the first of an icon and its fallback that the client has (Content's `alt` fields), checked once each.
local iconOK = {}
local probe
local function Has(path)
    if not path then return false end
    local known = iconOK[path]
    if known ~= nil then return known end
    local id
    if GetFileIDFromPath then
        local ok, v = pcall(GetFileIDFromPath, path)
        id = ok and v or nil
    else -- ask a hidden texture what the path resolved to
        probe = probe or UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        probe:SetTexture(nil)
        probe:SetTexture(path)
        id = probe.GetTextureFileID and probe:GetTextureFileID()
    end
    known = id ~= nil and id ~= 0
    iconOK[path] = known
    return known
end

-- The icon to show for a tower, creep, campaign crest or anything with { icon, alt }: the first the client has.
function Board.Icon(def, field, altField)
    local main, alt = def[field or "icon"], def[altField or "alt"]
    if Has(main) or not alt then return main end
    return Has(alt) and alt or main
end

------------------------------------------------------------------------------------------------------------------------
-- Creep tokens

local function ReleaseToken(t)
    t:Hide()
    freeTokens[#freeTokens + 1] = t
end

local function NewToken()
    local t = CreateFrame("Frame", nil, tokensLayer)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetTexture(CIRCLE)
    t.bg:SetAllPoints(t)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("CENTER")
    t.mask = t:CreateMaskTexture()
    t.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t.mask:SetAllPoints(t.icon)
    t.icon:AddMaskTexture(t.mask)
    t.barBg = t:CreateTexture(nil, "OVERLAY")
    t.barBg:SetColorTexture(0, 0, 0, 0.85)
    t.barBg:SetPoint("TOP", t, "BOTTOM", 0, 2)
    t.bar = t:CreateTexture(nil, "OVERLAY", nil, 1)
    t.bar:SetPoint("LEFT", t.barBg, "LEFT", 1, 0)
    t.bar:SetHeight(2)
    return t
end

local BAR = { normal = { 0.25, 0.9, 0.2 }, boss = { 1, 0.6, 0.2 }, plague = { 0.75, 0.95, 0.15 } }

local function BindToken(t, c)
    local C = Content.creeps[c.kind]
    local size = C.size or 24
    t:SetSize(size, size)
    t:SetAlpha(1)
    t.size = size
    t.icon:SetSize(size - 4, size - 4)
    t.icon:SetTexture(Board.Icon(C))
    t.icon:SetVertexColor(1, 1, 1)
    t.icon:SetDesaturated(false)
    if C.boss then t.bg:SetVertexColor(1, 0.82, 0)
    elseif C.air then t.bg:SetVertexColor(0.55, 0.8, 1)
    elseif C.stealth then t.bg:SetVertexColor(0.3, 0.12, 0.4)
    else t.bg:SetVertexColor(0.08, 0.08, 0.08) end
    t.barBg:SetSize(size, 4)
    t.boss = C.boss
    t.hp, t.look, t.hidden, t.barLook = nil, nil, nil, nil
    t:Show()
end

------------------------------------------------------------------------------------------------------------------------
-- Tower views

local function ReleaseView(id, v)
    for _, tex in ipairs(v.all) do tex:Hide() end
    views[id] = nil
    freeViews[#freeViews + 1] = v
end

-- Rank pips: gold, or a specialization's colour (rank 4 = first, rank 5 = second).
local SPEC_COLOR = { [0] = { 1, 0.82, 0 }, [4] = { 1, 0.45, 0.1 }, [5] = { 0.35, 0.8, 1 } }

local function NewView()
    local v = {}
    v.sel = towersLayer:CreateTexture(nil, "BACKGROUND")
    v.sel:SetSize(CELL, CELL)
    v.sel:SetColorTexture(1, 0.82, 0, 0.9)
    v.border = towersLayer:CreateTexture(nil, "BORDER")
    v.border:SetSize(CELL - 4, CELL - 4)
    v.icon = towersLayer:CreateTexture(nil, "ARTWORK")
    v.icon:SetSize(CELL - 8, CELL - 8)
    v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.flash = towersLayer:CreateTexture(nil, "ARTWORK", nil, 2) -- the muzzle flash when it fires
    v.flash:SetSize(CELL - 8, CELL - 8)
    v.flash:SetColorTexture(1, 1, 1, 1)
    v.flash:SetBlendMode("ADD")
    v.flash:SetAlpha(0)
    v.stun = towersLayer:CreateTexture(nil, "OVERLAY", nil, 2) -- stars over a stunned tower
    v.stun:SetTexture(STAR)
    v.stun:SetSize(22, 22)
    v.stun:SetVertexColor(1, 0.9, 0.4)
    v.stun:SetBlendMode("ADD")
    v.pips = {}
    v.all = { v.sel, v.border, v.icon, v.flash, v.stun }
    for i = 1, 3 do
        local p = towersLayer:CreateTexture(nil, "OVERLAY")
        p:SetSize(6, 3)
        v.pips[i] = p
        v.all[#v.all + 1] = p
    end
    v.flashAt = -1
    return v
end

-- Tower views follow state.towers; called after builds, upgrades, sales, selection and restores.
function Board.SyncTowers()
    if not state then return end
    gen = gen + 1
    for _, t in ipairs(state.towers) do
        local v = views[t.id]
        if not v then
            v = table.remove(freeViews) or NewView()
            views[t.id] = v
            v.flashAt, v.stunned = -1, nil
        end
        v.gen = gen
        local x, y = CellCentre(t.c, t.r)
        for _, tex in ipairs(v.all) do At(tex, x, y) end
        At(v.stun, x + 9, y - 11)
        local T = Content.towers[t.kind]
        v.icon:SetTexture(Board.Icon(T))
        v.hero = T.hero
        if T.hero then v.border:SetColorTexture(1, 0.75, 0.15, 1)
        else v.border:SetColorTexture(tint[1], tint[2], tint[3], 0.95) end
        v.lust = nil -- the frame colour was just reset: Board.Update paints Bloodlust's red again if it's running
        local color = SPEC_COLOR[t.rank] or SPEC_COLOR[0]
        for i, p in ipairs(v.pips) do
            At(p, x - 10 + (i - 1) * 10, y + 13)
            if i <= t.rank then p:SetColorTexture(color[1], color[2], color[3], 1)
            else p:SetColorTexture(0.25, 0.25, 0.25, 1) end
            p:SetShown(not T.hero)
        end
        v.border:Show(); v.icon:Show(); v.flash:Show()
        v.stun:SetShown(v.stunned == true)
        v.sel:SetShown(t.id == Board.selected)
    end
    for id, v in pairs(views) do
        if v.gen ~= gen then ReleaseView(id, v) end
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Effects: sprites (a texture that grows, drifts, spins and fades), bolts (jagged lines), floating text, shakes.

-- Looks: texture, blend mode, layer ("under" the tokens or "over" them), and how it grows.
local LOOK = {
    disc = { tex = CIRCLE, blend = "BLEND", layer = "under" },
    glow = { tex = CIRCLE, blend = "ADD", layer = "over" },
    star = { tex = STAR, blend = "ADD", layer = "over" },
    smoke = { tex = CIRCLE, blend = "BLEND", layer = "over" },
}

-- One sprite: `look` (a LOOK key), centred on (x, y) px, from size s0 to s1 over `life` seconds, colour r g b,
-- starting alpha a, drifting vx, vy px a second, spinning `spin` radians a second, starting after `delay`.
-- Each layer has its own ring of sprites; the oldest gives way.
local function Sprite(look, x, y, s0, s1, life, r, g, b, a, now, vx, vy, spin, delay)
    local L = LOOK[look]
    local pool = pools[L.layer]
    local s = pool.list[pool.next]
    if not s then
        local layer = L.layer == "under" and under or over
        s = { tex = layer:CreateTexture(nil, "ARTWORK", nil, L.layer == "under" and 4 or 1), until_ = 0 }
        pool.list[pool.next] = s
    end
    pool.next = pool.next % (L.layer == "under" and MAX_UNDER or MAX_SPRITES) + 1
    if s.lookName ~= look then
        s.lookName = look
        s.tex:SetTexture(L.tex)
        s.tex:SetBlendMode(L.blend)
    end
    s.x, s.y, s.s0, s.s1, s.a = x, y, s0, s1, a or 0.8
    s.vx, s.vy, s.spin = vx or 0, vy or 0, spin or 0
    s.start = now + (delay or 0)
    s.until_ = s.start + life
    s.tex:SetVertexColor(r, g, b)
    s.tex:SetSize(s0, s0)
    s.tex:SetAlpha(delay and delay > 0 and 0 or s.a)
    s.rot0 = spin and spin ~= 0 and Rand() * 6.28 or 0 -- spinning things start at a random angle
    if s.tex.SetRotation then s.tex:SetRotation(s.rot0) end
    At(s.tex, x, y)
    s.tex:Show()
    return s
end

-- A ring of sparkles flying out from (x, y) to radius r (px).
local function SparkRing(x, y, r, n, rr, gg, bb, life, now, size)
    local turn = Rand() * 2 * pi
    for i = 1, n do
        local a = turn + (i - 1) * 2 * pi / n
        local speed = r / life
        local s = size or 12
        Sprite("star", x, y, s, s * 0.6, life, rr, gg, bb, 0.95, now, cos(a) * speed, sin(a) * speed)
    end
end

-- Lightning: jagged segments (a wide glow and a bright core) from (x1, y1) to (x2, y2) px, flickering, re-kinked
-- once halfway. `straight` draws a clean arc instead (a bouncing glaive).
local hasLines

local function NewBolt()
    local b = { glow = {}, core = {}, px = {}, py = {}, n = 0, until_ = 0 }
    for i = 1, MAX_SEGMENTS do
        local g = over:CreateLine(nil, "OVERLAY", nil, 3)
        local c = over:CreateLine(nil, "OVERLAY", nil, 4)
        for _, l in ipairs({ g, c }) do
            l:SetColorTexture(1, 1, 1, 1)
            if l.SetBlendMode then l:SetBlendMode("ADD") end
            l:Hide()
        end
        if g.SetThickness then g:SetThickness(7); c:SetThickness(2) end
        b.glow[i], b.core[i] = g, c
    end
    return b
end

local function Kink(b)
    local dx, dy = b.x2 - b.x1, b.y2 - b.y1
    local dist = sqrt(dx * dx + dy * dy)
    local nx, ny = dist > 0 and -dy / dist or 0, dist > 0 and dx / dist or 0
    local amp = b.straight and 0 or min(11, dist * 0.2)
    b.px[1], b.py[1] = b.x1, b.y1
    for k = 1, b.n - 1 do
        local f, off = k / b.n, (Rand() - 0.5) * 2 * amp
        b.px[k + 1], b.py[k + 1] = b.x1 + dx * f + nx * off, b.y1 + dy * f + ny * off
    end
    b.px[b.n + 1], b.py[b.n + 1] = b.x2, b.y2
    for k = 1, b.n do
        local g, c = b.glow[k], b.core[k]
        local ax, ay, bx, by = b.px[k], -b.py[k], b.px[k + 1], -b.py[k + 1]
        g:SetStartPoint("TOPLEFT", frame, ax, ay); g:SetEndPoint("TOPLEFT", frame, bx, by)
        c:SetStartPoint("TOPLEFT", frame, ax, ay); c:SetEndPoint("TOPLEFT", frame, bx, by)
    end
end

local function Bolt(x1, y1, x2, y2, r, g, b, life, now, straight, thick)
    if hasLines == nil then hasLines = over.CreateLine ~= nil end
    if not hasLines then -- no Line regions on this client: dots along the way
        local n = 5
        for i = 1, n do
            local f = (i - 0.5) / n
            Sprite("glow", x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 9, 4, life, r, g, b, 0.9, now)
        end
        return
    end
    local bolt = bolts[boltNext]
    if not bolt then
        bolt = NewBolt()
        bolts[boltNext] = bolt
    end
    boltNext = boltNext % MAX_BOLTS + 1
    local dx, dy = x2 - x1, y2 - y1
    local dist = sqrt(dx * dx + dy * dy)
    bolt.n = straight and 1 or max(2, min(MAX_SEGMENTS, floor(dist / 18)))
    bolt.x1, bolt.y1, bolt.x2, bolt.y2, bolt.straight = x1, y1, x2, y2, straight
    bolt.start, bolt.until_, bolt.kinked = now, now + life, false
    local glowA = Board.fx >= 2 and 0.5 or 0
    for k = 1, MAX_SEGMENTS do
        local gl, co = bolt.glow[k], bolt.core[k]
        if k <= bolt.n then
            gl:SetVertexColor(r * 0.55, g * 0.65, b)
            co:SetVertexColor(0.75 + r * 0.25, 0.8 + g * 0.2, 1)
            if gl.SetThickness then gl:SetThickness((thick or 1) * 7); co:SetThickness((thick or 1) * 2) end
            gl:SetAlpha(glowA); co:SetAlpha(1)
            gl:Show(); co:Show()
        else
            gl:Hide(); co:Hide()
        end
    end
    Kink(bolt)
end

local FONT = { small = "GameFontNormalSmall", normal = "GameFontNormal", large = "GameFontNormalLarge" }

local function Floater(x, y, text, now, size, life)
    local f = floaters[floatNext]
    if not f then
        f = { text = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") }
        floaters[floatNext] = f
    end
    floatNext = floatNext % MAX_FLOATERS + 1
    local font = FONT[size or "small"]
    if f.font ~= font then
        f.font = font
        f.text:SetFontObject(font)
    end
    f.x, f.y, f.start, f.until_ = x, y, now, now + (life or 0.9)
    f.text:SetText(text)
    f.text:SetAlpha(1)
    At(f.text, x, y)
    f.text:Show()
end

local function Shake(power, length, now)
    if Board.fx < 2 then return end
    if now + length > shake.until_ then shake.until_ = now + length end
    shake.power = max(shake.power, power)
end

------------------------------------------------------------------------------------------------------------------------
-- What each tower's shots look like, and what their hits, pulses and blasts look like.

local LIGHTNING = { 0.55, 0.75, 1 }
local SHOT = {
    -- arrows and axes: a short streak; bolts and spells: a glowing orb
    archer = { kind = "streak", color = { 1, 0.95, 0.75 } },
    headhunter = { kind = "streak", color = { 0.9, 0.85, 0.7 } },
    rifleman = { kind = "streak", color = { 1, 0.85, 0.4 } },
    ranger = { kind = "streak", color = { 0.7, 0.45, 0.95 } },
    tyrande = { kind = "streak", color = { 0.85, 0.9, 1 } },
    sylvanas = { kind = "streak", color = { 0.6, 0.35, 0.85 } },
    frost = { kind = "orb", color = { 0.55, 0.85, 1 }, size = 9 },
    witchdoctor = { kind = "orb", color = { 0.6, 1, 0.45 }, size = 9 },
    necromancer = { kind = "orb", color = { 0.55, 0.3, 0.8 }, size = 9 },
    dryad = { kind = "orb", color = { 0.5, 0.95, 0.4 }, size = 8 },
    talon = { kind = "orb", color = { 0.95, 0.5, 1 }, size = 9 },
    banshee = { kind = "orb", color = { 0.75, 0.55, 1 }, size = 9 },
    paladin = { kind = "orb", color = { 1, 0.9, 0.45 }, size = 10 },
    bolvar = { kind = "orb", color = { 1, 0.9, 0.45 }, size = 11 },
    shaman = { kind = "spark", color = LIGHTNING, size = 8 },
    thrall = { kind = "spark", color = LIGHTNING, size = 9 },
    engineer = { kind = "lob", icon = "Interface\\Icons\\INV_Misc_Bomb_01", size = 12 },
    catapult = { kind = "lob", color = { 1, 0.55, 0.15 }, size = 11 },
    ancient = { kind = "lob", color = { 0.55, 0.45, 0.3 }, size = 12 },
    meatwagon = { kind = "lob", color = { 0.55, 0.75, 0.3 }, size = 11 },
}
local DEFAULT_SHOT = { kind = "orb", color = { 1, 0.95, 0.7 }, size = 7 }

-- Impact colours for single hits, by tower.
local HIT = {
    frost = { 0.6, 0.9, 1 }, witchdoctor = { 0.55, 1, 0.45 }, necromancer = { 0.6, 0.35, 0.9 },
    dryad = { 0.5, 1, 0.4 }, talon = { 1, 0.45, 1 }, banshee = { 0.8, 0.55, 1 }, paladin = { 1, 0.85, 0.4 },
    bolvar = { 1, 0.85, 0.4 }, ranger = { 0.75, 0.45, 1 }, sylvanas = { 0.7, 0.4, 1 },
}

-- Pulses: colour and style ("sparks", "quake", "snow", "plague", "wail").
local PULSE = {
    priest = { 1, 0.9, 0.45 }, priest4 = { 1, 0.95, 0.6, style = "nova" }, priest5 = { 0.6, 0.3, 1 },
    frost5 = { 0.6, 0.85, 1, style = "snow" }, earthshaker = { 0.85, 0.6, 0.3, style = "quake" },
    earthshaker4 = { 0.8, 0.55, 0.3, style = "quake" }, earthshaker5 = { 0.95, 0.65, 0.3, style = "quake" },
    moonwell = { 0.6, 0.75, 1 }, moonwell4 = { 0.75, 0.85, 1, style = "nova" },
    apothecary = { 0.6, 0.95, 0.2, style = "plague" },
    banshee5 = { 0.75, 0.5, 1, style = "wail" }, paladin5 = { 1, 0.85, 0.35, style = "nova" },
}

-- Blasts: colour of the fire (by tower).
local BLAST = {
    engineer = { 1, 0.55, 0.15 }, catapult = { 1, 0.45, 0.1 }, ancient = { 0.65, 0.55, 0.35 },
    meatwagon = { 0.55, 0.85, 0.25 },
}

local function Hit(e, now)
    local x, y = e.x * PX, e.y * PX
    local look = SHOT[e.tower] or DEFAULT_SHOT
    if look.kind == "spark" then -- the shaman's (and Thrall's) chain lightning starts from the tower itself
        local big = e.rank == 4
        Bolt(e.sx * PX, e.sy * PX, x, y, LIGHTNING[1], LIGHTNING[2], LIGHTNING[3], 0.32, now, false, big and 1.3)
        Sprite("glow", x, y, 26, 10, 0.25, 0.7, 0.85, 1, 0.9, now)
        Sprite("star", x, y, 30, 14, 0.22, 0.85, 0.95, 1, 1, now, 0, 0, 6)
        Sprite("glow", e.sx * PX, e.sy * PX, 22, 30, 0.2, 0.55, 0.75, 1, 0.8, now)
        return
    end
    local c = HIT[e.tower]
    if c then -- spells: a burst in the spell's colour
        Sprite("star", x, y, 22, 12, 0.22, c[1], c[2], c[3], 1, now, 0, 0, 4)
        if Board.fx >= 2 then Sprite("glow", x, y, 18, 26, 0.25, c[1], c[2], c[3], 0.6, now) end
    else -- arrows, axes and bullets: a small bright spark
        Sprite("star", x, y, 14, 6, 0.14, 1, 0.95, 0.8, 0.9, now)
    end
end

local function Pulse(e, now)
    local x, y, r = e.x * PX, e.y * PX, e.r * PX
    local c = PULSE[e.tower .. (e.rank or "")] or PULSE[e.tower] or { 1, 0.9, 0.45 }
    local style = c.style
    Sprite("disc", x, y, r * 0.8, r * 2, 0.4, c[1], c[2], c[3], 0.4, now)
    if Board.fx < 2 then return end
    Sprite("glow", x, y, r * 0.5, r * 1.2, 0.25, c[1], c[2], c[3], 0.45, now)
    SparkRing(x, y, r, style == "nova" and 16 or 10, c[1], c[2], c[3], 0.35, now, style == "nova" and 14 or 10)
    if style == "quake" then
        for _ = 1, 6 do -- dust kicked up
            local a, d = Rand() * 2 * pi, Rand() * r
            Sprite("smoke", x + cos(a) * d, y + sin(a) * d, 10, 22, 0.6, 0.55, 0.42, 0.28, 0.5, now, 0, -12)
        end
        if e.tower == "earthshaker" and e.rank == 5 then Shake(2, 0.15, now) end
    elseif style == "snow" then
        for _ = 1, 8 do
            local a, d = Rand() * 2 * pi, Rand() * r
            Sprite("star", x + cos(a) * d, y + sin(a) * d - 10, 9, 5, 0.6, 0.85, 0.95, 1, 0.9, now, 0, 30, 2)
        end
    elseif style == "plague" then
        for _ = 1, 5 do
            local a, d = Rand() * 2 * pi, Rand() * r * 0.8
            Sprite("smoke", x + cos(a) * d, y + sin(a) * d, 12, 26, 0.8, 0.45, 0.75, 0.15, 0.45, now, 0, -10)
        end
    elseif style == "wail" then
        SparkRing(x, y, r * 0.6, 8, 0.85, 0.7, 1, 0.45, now, 16)
    end
end

local function Blast(e, now)
    local x, y, r = e.x * PX, e.y * PX, e.r * PX
    local c = BLAST[e.tower] or { 1, 0.5, 0.1 }
    local big = (e.r or 0) >= 1600
    Sprite("glow", x, y, r * 0.6, r * 1.1, 0.18, 1, 0.95, 0.7, 1, now) -- the flash
    Sprite("disc", x, y, r * 0.9, r * 2.1, 0.35, c[1], c[2], c[3], 0.55, now) -- the fireball
    Sprite("star", x, y, r * 1.2, r * 0.6, 0.25, 1, 0.85, 0.5, 1, now, 0, 0, 3)
    if Board.fx < 2 then return end
    SparkRing(x, y, r * 1.1, big and 12 or 8, c[1], c[2] * 0.8, c[3] * 0.6, 0.3, now, 9)
    for _ = 1, big and 5 or 3 do -- smoke drifting up
        local a = Rand() * 2 * pi
        Sprite("smoke", x + cos(a) * r * 0.3, y + sin(a) * r * 0.3, r * 0.5, r * 0.9, 0.9, 0.12, 0.1, 0.08, 0.45,
            now, 0, -14, 0, 0.08)
    end
    if big then Shake(2.5, 0.2, now) end
end

local function Killed(e, now)
    local x, y = e.x * PX, e.y * PX
    if e.boss then
        Sprite("glow", x, y, 30, 90, 0.6, 1, 0.85, 0.3, 0.9, now)
        SparkRing(x, y, 70, 16, 1, 0.82, 0.2, 0.6, now, 18)
        Floater(x, y - 22, "|cffffd200Boss defeated!|r", now, "large", 1.6)
        Shake(3, 0.3, now)
    else
        Sprite("star", x, y, 26, 10, 0.25, 1, 1, 0.9, 0.9, now, 0, 0, 5)
    end
    if e.gold > 0 then Floater(x, y - 10, "|cffffd200+" .. e.gold .. "|r", now) end
end

-- The hero abilities' moments.
local function Ability(e, now)
    local x, y, r = e.x * PX, e.y * PX, (e.r or 0) * PX
    if e.ability == "bloodlust" then
        Sprite("disc", x, y, 40, 16 * CELL, 0.7, 1, 0.25, 0.1, 0.45, now)
        SparkRing(x, y, 5 * CELL, 18, 1, 0.35, 0.15, 0.6, now, 16)
        Floater(x, y - 24, "|cffff4020Bloodlust!|r", now, "large", 1.5)
    elseif e.ability == "shield" then
        Sprite("glow", x, y, 30, 120, 0.6, 1, 0.85, 0.35, 0.9, now)
        SparkRing(x, y, 3 * CELL, 14, 1, 0.9, 0.5, 0.5, now, 14)
        Floater(x, y - 24, "|cffffe080Divine Shield!|r", now, "large", 1.5)
    elseif e.ability == "starfall" then
        Sprite("disc", x, y, r * 0.5, r * 2, 0.6, 0.6, 0.7, 1, 0.35, now)
        Floater(x, y - 24, "|cffb0c8ffStarfall!|r", now, "large", 1.5)
    elseif e.ability == "wail" then
        Sprite("disc", x, y, r * 0.4, r * 2, 0.5, 0.6, 0.35, 0.9, 0.5, now)
        SparkRing(x, y, r, 18, 0.8, 0.6, 1, 0.4, now, 16)
        SparkRing(x, y, r * 0.6, 12, 0.6, 0.4, 0.9, 0.5, now, 12)
        Floater(x, y - 24, "|cffc090ffWailing Arrow!|r", now, "large", 1.5)
        Shake(2, 0.2, now)
    end
end

-- Effects and floating numbers for the engine's events.
function Board.OnEvents(events, now)
    local towersChanged = false
    for _, e in ipairs(events) do
        local k = e.kind
        if k == "hit" then
            Hit(e, now)
        elseif k == "zap" then
            local x1, y1, x, y = e.x1 * PX, e.y1 * PX, e.x * PX, e.y * PX
            if e.damage == "physical" then -- a bouncing glaive: a clean silver arc
                Bolt(x1, y1, x, y, 0.9, 0.9, 1, 0.2, now, true, 0.6)
                Sprite("star", x, y, 16, 8, 0.18, 0.9, 0.95, 1, 0.9, now, 0, 0, 8)
            else
                Bolt(x1, y1, x, y, LIGHTNING[1], LIGHTNING[2], LIGHTNING[3], 0.32, now)
                Sprite("glow", x, y, 24, 10, 0.25, 0.7, 0.85, 1, 0.9, now)
                Sprite("star", x, y, 26, 12, 0.2, 0.85, 0.95, 1, 1, now, 0, 0, 6)
            end
        elseif k == "fire" then
            local v = views[e.id]
            if v then v.flashAt = now end
        elseif k == "pulse" then
            local v = views[e.id]
            if v then v.flashAt = now end
            Pulse(e, now)
        elseif k == "blast" then
            Blast(e, now)
        elseif k == "misfire" then
            Sprite("smoke", e.x * PX, e.y * PX, 14, 28, 0.5, 0.45, 0.45, 0.45, 0.6, now, 0, -10)
            Floater(e.x * PX, e.y * PX - 10, "|cff999999fizzle|r", now)
        elseif k == "crit" then
            Sprite("star", e.x * PX, e.y * PX, 34, 14, 0.25, 1, 0.6, 0.25, 1, now, 0, 0, 8)
            Floater(e.x * PX, e.y * PX - 14, "|cffff8040CRIT!|r", now, "normal")
        elseif k == "healed" then
            Sprite("disc", e.x * PX, e.y * PX, e.r * PX * 0.5, e.r * PX * 2, 0.45, 0.3, 1, 0.4, 0.35, now)
            if Board.fx >= 2 then SparkRing(e.x * PX, e.y * PX, e.r * PX * 0.7, 6, 0.4, 1, 0.5, 0.4, now, 9) end
        elseif k == "killed" then
            Killed(e, now)
        elseif k == "leaked" then
            local x, y = e.x * PX, e.y * PX
            if e.warded then
                Sprite("glow", x, y, 20, 60, 0.4, 1, 0.85, 0.35, 0.9, now)
                Floater(x, y - 12, "|cffffe080shielded|r", now)
            else
                Sprite("glow", x, y, 24, 70, 0.4, 1, 0.15, 0.1, 0.8, now)
                Floater(x, y - 12, "|cffff4040-" .. e.lives .. "|r", now, "normal")
            end
        elseif k == "spread" then -- a plague wisp to the next host
            local x1, y1, x, y = e.x1 * PX, e.y1 * PX, e.x * PX, e.y * PX
            Sprite("glow", x1, y1, 12, 8, 0.3, 0.6, 1, 0.2, 0.9, now, (x - x1) / 0.3, (y - y1) / 0.3)
        elseif k == "burst" then
            local x, y, r = e.x * PX, e.y * PX, e.r * PX
            Sprite("disc", x, y, r * 0.6, r * 1.8, 0.35, 0.45, 0.8, 0.2, 0.55, now)
            Sprite("star", x, y, r, r * 0.5, 0.25, 0.7, 1, 0.4, 1, now, 0, 0, 4)
        elseif k == "regrow" then
            local x, y = e.x * PX, e.y * PX
            for i = 1, 5 do Sprite("star", x + (i - 3) * 5, y, 10, 6, 0.8, 0.5, 1, 0.4, 0.9, now, 0, -22, 2) end
            Floater(x, y - 18, "|cff60ff60+1 life|r", now, "normal")
        elseif k == "stomp" then
            local x, y, r = e.x * PX, e.y * PX, e.r * PX
            Sprite("disc", x, y, r * 0.4, r * 2, 0.45, 0.75, 0.5, 0.25, 0.5, now)
            SparkRing(x, y, r, 12, 0.9, 0.65, 0.3, 0.4, now, 12)
            Shake(3, 0.25, now)
        elseif k == "summon" then
            Sprite("star", e.x * PX, e.y * PX, 50, 20, 0.6, 0.7, 0.4, 1, 0.9, now, 0, 0, 5)
            Sprite("glow", e.x * PX, e.y * PX, 20, 50, 0.5, 0.6, 0.3, 0.9, 0.6, now)
        elseif k == "blink" then
            Sprite("glow", e.x1 * PX, e.y1 * PX, 40, 10, 0.4, 0.6, 0.35, 1, 0.9, now)
            Sprite("glow", e.x * PX, e.y * PX, 10, 44, 0.4, 0.6, 0.35, 1, 0.9, now)
            Bolt(e.x1 * PX, e.y1 * PX, e.x * PX, e.y * PX, 0.65, 0.4, 1, 0.3, now, true, 0.8)
        elseif k == "enraged" then
            Sprite("glow", e.x * PX, e.y * PX, 30, 60, 0.6, 1, 0.15, 0.1, 0.8, now)
            Floater(e.x * PX, e.y * PX - 22, "|cffff3020Enraged!|r", now, "normal", 1.3)
        elseif k == "ability" then
            Ability(e, now)
        elseif k == "starfall" then
            local x, y, r = e.x * PX, e.y * PX, e.r * PX
            for _ = 1, Board.fx >= 2 and 7 or 3 do -- stars falling where the creeps are
                local a, d = Rand() * 2 * pi, sqrt(Rand()) * r
                local sx, sy = x + cos(a) * d, y + sin(a) * d
                Sprite("star", sx, sy - 40, 18, 10, 0.35, 0.8, 0.85, 1, 1, now, 0, 115, 6)
                Sprite("glow", sx, sy, 10, 26, 0.3, 0.6, 0.7, 1, 0.8, now, 0, 0, 0, 0.3)
            end
        elseif k == "placed" or k == "upgraded" or k == "sold" then
            towersChanged = true
            if k == "upgraded" or (k == "placed" and e.hero) then
                local v = views[e.id]
                if v then v.flashAt = now end
            end
        end
    end
    if towersChanged then Board.SyncTowers() end
end

------------------------------------------------------------------------------------------------------------------------

-- A shot's look, set once per texture per kind.
local function ShotLook(tex, kind)
    if tex.kind == kind then return end
    tex.kind = kind
    local look = SHOT[kind] or DEFAULT_SHOT
    tex.look = look
    if look.icon then
        tex:SetTexture(look.icon)
        tex:SetVertexColor(1, 1, 1)
        tex:SetBlendMode("BLEND")
        tex:SetSize(look.size, look.size)
    elseif look.kind == "streak" then
        tex:SetTexture(STAR)
        tex:SetVertexColor(look.color[1], look.color[2], look.color[3])
        tex:SetBlendMode("ADD")
        tex:SetSize(11, 11)
    else
        tex:SetTexture(CIRCLE)
        tex:SetVertexColor(look.color[1], look.color[2], look.color[3])
        tex:SetBlendMode(look.kind == "lob" and "BLEND" or "ADD")
        tex:SetSize(look.size, look.size)
    end
    if tex.SetRotation then tex:SetRotation(0) end
end

local function DrawHover()
    local c, r
    if frame:IsMouseOver() then c, r = Board.CursorCell() end
    local kind = Board.placing
    if drawn.c == c and drawn.r == r and drawn.kind == kind and drawn.gold == state.gold
        and drawn.selected == Board.selected and drawn.towers == #state.towers then
        return
    end
    drawn.c, drawn.r, drawn.kind, drawn.gold = c, r, kind, state.gold
    drawn.selected, drawn.towers = Board.selected, #state.towers
    auraRing:Hide()
    if kind and c then
        local ok = Engine.CanBuild(state, kind, c, r)
        hover:SetColorTexture(ok and 0.2 or 1, ok and 1 or 0.2, 0.2, 0.3)
        At(hover, CellCentre(c, r))
        hover:Show()
        ghost:SetTexture(Board.Icon(Content.towers[kind]))
        At(ghost, CellCentre(c, r))
        ghost:Show()
        local S = Engine.Stats(state, kind, 1)
        local range = S.range * PX
        ring:SetSize(range * 2, range * 2)
        ring:SetVertexColor(1, 1, 1, 0.14)
        At(ring, CellCentre(c, r))
        ring:Show()
        if S.aura then
            auraRing:SetSize(S.aura * PX * 2, S.aura * PX * 2)
            auraRing:SetVertexColor(0.3, 1, 0.4, 0.1)
            At(auraRing, CellCentre(c, r))
            auraRing:Show()
        end
        return
    end
    hover:Hide()
    ghost:Hide()
    local t = Board.selected
    for _, tower in ipairs(state.towers) do
        if tower.id == t then
            local S = Engine.Stats(state, tower.kind, tower.rank)
            local range = S.range * PX
            ring:SetSize(range * 2, range * 2)
            ring:SetVertexColor(1, 0.82, 0, 0.14)
            At(ring, CellCentre(tower.c, tower.r))
            ring:Show()
            if S.aura then
                auraRing:SetSize(S.aura * PX * 2, S.aura * PX * 2)
                auraRing:SetVertexColor(0.3, 1, 0.4, 0.1)
                At(auraRing, CellCentre(tower.c, tower.r))
                auraRing:Show()
            end
            return
        end
    end
    ring:Hide()
end

-- How a creep's icon is tinted: frozen, slowed, cursed, poisoned or plain.
local LOOK_COLOR = {
    frozen = { 0.85, 0.95, 1 }, slowed = { 0.55, 0.75, 1 }, cursed = { 0.95, 0.55, 1 }, poisoned = { 0.7, 1, 0.45 },
    plain = { 1, 1, 1 },
}

local function CreepLook(c, tick)
    if c.stunEnd >= tick then return "frozen" end
    if c.slowEnd >= tick then return c.slow >= 100 and "frozen" or "slowed" end -- (a stun saved by 0.4.0 was a slow)
    if c.vulnEnd >= tick then return "cursed" end
    if c.dotEnd >= tick then return "poisoned" end
    return "plain"
end

-- Draws the state `alpha` (0..1) of the way to the next tick. Called every frame while the window is open.
function Board.Update(alpha, now)
    if not state then return end
    gen = gen + 1
    local tick = state.tick
    for _, c in ipairs(state.creeps) do
        local t = tokens[c.id]
        if not t then
            t = table.remove(freeTokens) or NewToken()
            tokens[c.id] = t
            BindToken(t, c)
        end
        t.gen = gen
        local x, y = Engine.CreepXY(state, c, alpha)
        t.px, t.py = x * PX, y * PX
        t:SetPoint("CENTER", frame, "TOPLEFT", t.px, -t.py)
        if t.hp ~= c.hp then
            t.hp = c.hp
            t.bar:SetWidth(max(1, (t.size - 2) * c.hp / c.maxHp))
        end
        local look = CreepLook(c, tick)
        if look ~= t.look then
            t.look = look
            local col = LOOK_COLOR[look]
            t.icon:SetVertexColor(col[1], col[2], col[3])
        end
        local barLook = t.boss and "boss" or (c.dotEnd >= tick and "plague" or "normal")
        if barLook ~= t.barLook then
            t.barLook = barLook
            local col = BAR[barLook]
            t.bar:SetColorTexture(col[1], col[2], col[3], 1)
        end
        local hidden = not Engine.Seen(c)
        if hidden ~= t.hidden then
            t.hidden = hidden
            t:SetAlpha(hidden and 0.35 or 1)
            t.icon:SetDesaturated(hidden)
        end
    end
    for id, t in pairs(tokens) do -- gone this tick: fade out where it was
        if t.gen ~= gen then
            tokens[id] = nil
            t.dieAt = now
            dying[#dying + 1] = t
        end
    end
    for i = #dying, 1, -1 do
        local t = dying[i]
        local p = (now - t.dieAt) / 0.28
        if p >= 1 or Board.fx < 2 then
            table.remove(dying, i)
            ReleaseToken(t)
        else
            local s = t.size * (1 - 0.6 * p)
            t:SetSize(s, s)
            t:SetAlpha((1 - p) * (t.hidden and 0.35 or 1))
        end
    end
    local n = 0
    for _, s in ipairs(state.shots) do
        n = n + 1
        local tex = shotTex[n]
        if not tex then
            tex = over:CreateTexture(nil, "OVERLAY")
            shotTex[n] = tex
        end
        ShotLook(tex, s.tower)
        local tx, ty = s.ax, s.ay
        local target = Engine.Creep(state, s.target)
        if target then tx, ty = Engine.CreepXY(state, target, alpha) end
        local p = min(1, max(0, (tick + alpha - s.fire) / (s.land - s.fire)))
        local x, y = (s.sx + (tx - s.sx) * p) * PX, (s.sy + (ty - s.sy) * p) * PX
        local look = tex.look
        if look.kind == "lob" then -- thrown high: an arc, spinning
            y = y - sin(p * pi) * 14
            if tex.SetRotation then tex:SetRotation(p * 9) end
        elseif look.kind == "streak" and tex.SetRotation then
            tex:SetRotation(p * 3)
        end
        At(tex, x, y)
        tex:Show()
    end
    for i = n + 1, shotsShown do shotTex[i]:Hide() end
    shotsShown = n
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool.list) do
            if s.until_ > 0 then
                if now >= s.until_ then
                    s.tex:Hide()
                    s.until_ = 0
                elseif now >= s.start then
                    local t = now - s.start
                    local p = t / (s.until_ - s.start)
                    local size = s.s0 + (s.s1 - s.s0) * (1 - (1 - p) * (1 - p))
                    s.tex:SetSize(size, size)
                    s.tex:SetAlpha(s.a * (1 - p * p))
                    if s.vx ~= 0 or s.vy ~= 0 then At(s.tex, s.x + s.vx * t, s.y + s.vy * t) end
                    if s.spin ~= 0 and s.tex.SetRotation then s.tex:SetRotation(s.rot0 + s.spin * t) end
                end
            end
        end
    end
    for _, b in ipairs(bolts) do
        if b.until_ > 0 then
            if now >= b.until_ then
                for k = 1, b.n do b.glow[k]:Hide(); b.core[k]:Hide() end
                b.until_ = 0
            else
                local p = (now - b.start) / (b.until_ - b.start)
                if not b.kinked and p > 0.45 then -- crackle: a new shape halfway through
                    b.kinked = true
                    Kink(b)
                end
                local flicker = (1 - p) * (0.55 + 0.45 * Rand())
                local glowA = Board.fx >= 2 and 0.5 * flicker or 0
                for k = 1, b.n do
                    b.core[k]:SetAlpha(flicker)
                    b.glow[k]:SetAlpha(glowA)
                end
            end
        end
    end
    for _, f in ipairs(floaters) do
        if f.until_ > 0 then
            if now >= f.until_ then
                f.text:Hide()
                f.until_ = 0
            else
                local p = (now - f.start) / (f.until_ - f.start)
                At(f.text, f.x, f.y - 16 * p)
                f.text:SetAlpha(1 - p * p)
            end
        end
    end
    for _, t in ipairs(state.towers) do -- muzzle flashes, Bloodlust's glow, and boss stuns
        local v = views[t.id]
        if v and v.flashAt >= 0 then
            local p = (now - v.flashAt) / 0.16
            if p >= 1 then
                v.flash:SetAlpha(0)
                v.flashAt = -1
            else
                v.flash:SetAlpha(0.55 * (1 - p))
            end
        end
        local stunned = t.stunEnd >= tick
        if v and stunned ~= v.stunned then
            v.stunned = stunned
            v.stun:SetShown(stunned)
            if stunned then v.icon:SetVertexColor(0.55, 0.55, 0.7) else v.icon:SetVertexColor(1, 1, 1) end
        end
        if v and stunned and v.stun.SetRotation then v.stun:SetRotation(now * 4) end
        local lust = v and state.lustEnd >= tick and not v.hero
        if v and lust ~= v.lust then
            v.lust = lust
            if lust then v.border:SetColorTexture(0.9, 0.15, 0.05, 1)
            elseif v.hero then v.border:SetColorTexture(1, 0.75, 0.15, 1)
            else v.border:SetColorTexture(tint[1], tint[2], tint[3], 0.95) end
        end
    end
    local warded = state.wardEnd >= tick
    if warded then
        local geo = state._geo.paths[1]
        local x, y = geo.x[#geo.x] * PX, geo.y[#geo.y] * PX
        local pulse = 0.5 + 0.25 * sin(now * 8)
        ward:SetSize(3 * CELL, 3 * CELL)
        ward:SetVertexColor(1, 0.85, 0.35)
        ward:SetAlpha(pulse)
        At(ward, min(max(x, 0), state._level.cols * CELL), min(max(y, 0), state._level.rows * CELL))
    end
    ward:SetShown(warded)
    if anchor.parent then
        if now < shake.until_ then
            shake.x, shake.y = (Rand() - 0.5) * 2 * shake.power, (Rand() - 0.5) * 2 * shake.power
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", anchor.parent, "TOPLEFT", anchor.x + shake.x, anchor.y + shake.y)
        elseif shake.power > 0 then
            shake.power = 0
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", anchor.parent, "TOPLEFT", anchor.x, anchor.y)
        end
    end
    DrawHover()
end

-- A new or restored run: lay the art and road once per level, drop everything drawn for the old state.
function Board.SetState(s)
    state = s
    drawn.c = -1
    Board.placing, Board.selected = nil, nil
    for id, t in pairs(tokens) do
        tokens[id] = nil
        ReleaseToken(t)
    end
    for i = #dying, 1, -1 do ReleaseToken(dying[i]); dying[i] = nil end
    for i = 1, shotsShown do shotTex[i]:Hide() end
    shotsShown = 0
    for _, pool in pairs(pools) do
        for _, e in ipairs(pool.list) do e.tex:Hide(); e.until_ = 0 end
    end
    for _, b in ipairs(bolts) do
        for k = 1, MAX_SEGMENTS do b.glow[k]:Hide(); b.core[k]:Hide() end
        b.until_ = 0
    end
    for _, f in ipairs(floaters) do f.text:Hide(); f.until_ = 0 end
    ward:Hide()
    shake.until_ = 0
    if not s then return end
    local level = s._level
    local camp = Levels.Campaign(level)
    local c = camp and camp.color or { 0.3, 0.3, 0.3 }
    tint[1], tint[2], tint[3] = c[1] * 0.45, c[2] * 0.45, c[3] * 0.45
    for _, v in pairs(views) do v.lust = nil end
    frame:SetSize(level.cols * CELL, level.rows * CELL)
    if artFor ~= level.id then
        Board.Paint(paint, level, level.cols * CELL)
        artFor = level.id
    end
    Board.SyncTowers()
end

-- The creep whose token is under the cursor, or nil.
function Board.HoverCreep()
    if not state or not frame:IsMouseOver() then return nil end
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return nil end
    x, y = x / scale - left, top - y / scale
    local best, bestD
    for _, c in ipairs(state.creeps) do
        local t = tokens[c.id]
        if t then
            local dx, dy, r = c._x * PX - x, c._y * PX - y, t.size / 2 + 2
            local d = dx * dx + dy * dy
            if d <= r * r and (not bestD or d < bestD) then best, bestD = c, d end
        end
    end
    return best
end

-- /td fx: a few seconds of the big effects on the board, to judge how they look (presentation only: these are
-- made-up events, and the game never hears of them). Positions are in milli-cells, as the engine's events are.
local SHOWCASE = {
    { 0.0, { kind = "hit", tower = "shaman", rank = 1, sx = 2500, sy = 5500, x = 5500, y = 4500 } },
    { 0.0, { kind = "zap", x1 = 5500, y1 = 4500, x = 7500, y = 5500, damage = "magic" } },
    { 0.0, { kind = "zap", x1 = 7500, y1 = 5500, x = 9500, y = 4500, damage = "magic" } },
    { 0.0, { kind = "zap", x1 = 9500, y1 = 4500, x = 11500, y = 5500, damage = "magic" } },
    { 0.7, { kind = "blast", tower = "catapult", rank = 5, x = 8000, y = 7500, r = 1700 } },
    { 1.3, { kind = "pulse", tower = "earthshaker", rank = 5, x = 4000, y = 2500, r = 1900 } },
    { 1.8, { kind = "pulse", tower = "priest", rank = 4, x = 12000, y = 2500, r = 2100 } },
    { 2.3, { kind = "pulse", tower = "frost", rank = 5, x = 13000, y = 7500, r = 2300 } },
    { 2.8, { kind = "ability", ability = "starfall", x = 8000, y = 5000, r = 3000 } },
    { 2.9, { kind = "starfall", x = 8000, y = 5000, r = 3000 } },
    { 3.4, { kind = "starfall", x = 8000, y = 5000, r = 3000 } },
    { 3.9, { kind = "killed", id = 0, x = 8000, y = 5000, gold = 100, boss = true } },
    { 4.4, { kind = "ability", ability = "bloodlust", x = 2500, y = 5500 } },
}

function Board.Showcase()
    if not state then return false end
    for _, step in ipairs(SHOWCASE) do
        local e = step[2]
        C_Timer.After(step[1], function() if state then Board.OnEvents({ e }, GetTime()) end end)
    end
    return true
end

-- Live counts for /td diag: tokens, shots, effects (sprites and bolts) running.
function Board.Counts()
    local t, e = 0, 0
    for _ in pairs(tokens) do t = t + 1 end
    for _, pool in pairs(pools) do
        for _, x in ipairs(pool.list) do if x.until_ > 0 then e = e + 1 end end
    end
    for _, b in ipairs(bolts) do if b.until_ > 0 then e = e + 1 end end
    return t, shotsShown, e
end

return Board
