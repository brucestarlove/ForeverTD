-- Engine.lua - the rules of one level, in pure Lua 5.1. No WoW API calls in this file, ever: WoW loads it through
-- the TOC, and tests/run.lua and tools/sim.lua load the very same file under plain Lua.
--
-- The game is a fixed 30 Hz step over plain data, so the same level, loadout, seed and actions always play the same
-- game, and a snapshot taken at any tick (mid-wave included) restores to exactly that game. Everything stored is a
-- whole number: positions in milli-cells, time in ticks. Fields starting with "_" are rebuilt on restore, never saved.
--
-- What towers can do (all of it is data in the campaign files): single shots, several targets (multi), splash,
-- pulses that hit everything near the tower, chain lightning or bouncing glaives (chain), slows and stuns (a stunned
-- creep is steady for a second afterwards, so stuns can't be chained, and stunning towers aim elsewhere), damage
-- over time that can jump to the next creep when its host dies (dot, spread), curses that make a creep take more
-- damage (vuln), corpses that explode (bane), bonus damage against undead and demons (holy), flyers (airBonus) or
-- slowed creeps, crits and misfires (seeded), auras that make nearby towers fire faster (haste) or hit harder
-- (might), revealing stealthed creeps (reveal), and restoring lives when a wave is cleared (regrow).
-- A hero is a free tower, one per level, with an ability on a long cooldown (Bloodlust, Divine Shield, Starfall,
-- Wailing Arrow). Bosses can stun towers (stomp), call help (summon), jump ahead (blink) and enrage.
local _, ns = ...
ns = ns or {}
local Content, Levels = ns.Content, ns.Levels
local Engine = {}
ns.Engine = Engine

Engine.SCHEMA = 3          -- 2 was 0.1-0.3 (before the campaigns). Bump when the snapshot shape changes
Engine.HZ = 30
Engine.STEP = 1 / 30       -- fixed simulation step, seconds (never the frame's elapsed)
Engine.MAX_FRAME = 0.25    -- a hitch never feeds the simulation more than this much time
Engine.CELL = 1000         -- milli-cells per cell
Engine.SELL_PCT = 70       -- refund when a tower is sold, % of everything spent on it
Engine.SPREAD = 1500       -- how far a plague jumps when its host dies
Engine.BURST = 1200        -- the reach of an exploding corpse
Engine.MAX_HASTE = 75      -- fire-rate bonuses (auras and Bloodlust together) stop here, %
Engine.STEADY = 30         -- after a stun wears off, the creep can't be stunned again for this long (ticks)
Engine.INCOME = 80         -- percent of every bounty, wave bonus and early-call bonus that's paid (0.4.3: income -20%)
Engine.PACE = 2            -- normal speed (1x) plays this many game seconds a real second (0.4.3: the old 2x)

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local CELL = Engine.CELL

-- Seeded PRNG (Park-Miller "minimal standard"): every product stays below 2^46, exact in Lua's doubles.
-- Never call math.random in engine code: the same seed and actions must always replay the same game.
local MOD, MUL = 2147483647, 16807

function Engine.NewRng(seed)
    local s = floor(tonumber(seed) or 1) % MOD
    if s <= 0 then s = s + MOD - 1 end
    return { s = s }
end

function Engine.Random(rng, n) -- 1..n
    rng.s = (rng.s * MUL) % MOD
    return 1 + (rng.s % n)
end

local function CellKey(level, c, r) return (r - 1) * level.cols + c end

-- Level geometry, worked out once per level table: path points and lengths, road and blocked cells.
local geometry = {}

function Engine.Geometry(level)
    local g = geometry[level]
    if g then return g end
    g = { paths = {}, road = {}, blocked = {} }
    for p, pts in ipairs(level.paths) do
        local path = { air = pts.air == true, x = {}, y = {}, cum = { 0 }, len = 0 }
        for i, pt in ipairs(pts) do
            path.x[i], path.y[i] = pt[1] * CELL - CELL / 2, pt[2] * CELL - CELL / 2
            if i > 1 then
                local dx, dy = path.x[i] - path.x[i - 1], path.y[i] - path.y[i - 1]
                path.len = path.len + floor(sqrt(dx * dx + dy * dy) + 0.5)
                path.cum[i] = path.len
                if not path.air then -- mark the road: every cell from the previous waypoint to this one
                    local c0, r0, c1, r1 = pts[i - 1][1], pts[i - 1][2], pt[1], pt[2]
                    local steps = max(math.abs(c1 - c0), math.abs(r1 - r0))
                    for s = 0, steps do
                        local c = c0 + (steps > 0 and (c1 - c0) * s / steps or 0)
                        local r = r0 + (steps > 0 and (r1 - r0) * s / steps or 0)
                        if c >= 1 and c <= level.cols and r >= 1 and r <= level.rows then
                            g.road[CellKey(level, c, r)] = true
                        end
                    end
                end
            end
        end
        g.paths[p] = path
    end
    for _, cell in ipairs(level.blocked or {}) do g.blocked[CellKey(level, cell[1], cell[2])] = true end
    geometry[level] = g
    return g
end

-- A point `d` milli-cells along a path.
function Engine.PathXY(path, d)
    local xs, ys, cum = path.x, path.y, path.cum
    if d <= 0 then return xs[1], ys[1] end
    for i = 2, #xs do
        if d <= cum[i] then
            local seg = cum[i] - cum[i - 1]
            local t = seg > 0 and (d - cum[i - 1]) / seg or 0
            return xs[i - 1] + (xs[i] - xs[i - 1]) * t, ys[i - 1] + (ys[i] - ys[i - 1]) * t
        end
    end
    return xs[#xs], ys[#ys]
end

-- A level's problems as readable strings (empty when it's fine). Tests run it over every level.
function Engine.ValidateLevel(level)
    local problems = {}
    local function bad(msg) problems[#problems + 1] = level.id .. ": " .. msg end
    if not (level.cols and level.rows and level.gold and level.lives and level.waves and level.paths) then
        bad("missing cols, rows, gold, lives, waves or paths")
        return problems
    end
    for p, pts in ipairs(level.paths) do
        if #pts < 2 then bad("path " .. p .. " needs two points") end
        for i = 2, #pts do
            if not pts.air and pts[i][1] ~= pts[i - 1][1] and pts[i][2] ~= pts[i - 1][2] then
                bad("ground path " .. p .. " bends diagonally at point " .. i)
            end
        end
    end
    if level.airPath and not level.paths[level.airPath] then bad("airPath " .. level.airPath .. " doesn't exist") end
    local function Percent(v) return v == nil or (type(v) == "number" and v >= 1 and v == floor(v)) end
    if not Percent(level.waves.hp) then bad("the level's hp must be a whole percent") end
    for w, wave in ipairs(level.waves) do
        if #wave == 0 then bad("wave " .. w .. " is empty") end
        if not Percent(wave.hp) then bad("wave " .. w .. ": hp must be a whole percent") end
        for _, grp in ipairs(wave) do
            if not Content.creeps[grp.creep] then bad("wave " .. w .. ": unknown creep " .. tostring(grp.creep)) end
            if not (grp.count and grp.count >= 1 and grp.gap and grp.gap >= 1) then
                bad("wave " .. w .. ": count and gap must be at least 1")
            end
            if not Percent(grp.hp) then bad("wave " .. w .. ": a group's hp must be a whole percent") end
            if grp.path and not level.paths[grp.path] then bad("wave " .. w .. ": no path " .. grp.path) end
            local C = Content.creeps[grp.creep]
            if C and C.air and not grp.path and not level.airPath then
                bad("wave " .. w .. ": " .. grp.creep .. " flies but the level has no airPath")
            end
        end
    end
    return problems
end

-- Effective tower stats for this run: Content's numbers with the loadout's research bonuses (the Armory).
local function BuildStats(loadout)
    local stats = {}
    for kind, tower in pairs(Content.towers) do
        local b = loadout.bonus and loadout.bonus[kind] or {}
        local dmgPct, rangePct, costPct = b.dmgPct or 100, b.rangePct or 100, b.costPct or 100
        stats[kind] = {}
        for rank, s in ipairs(tower.ranks) do
            local e = {}
            for k, v in pairs(s) do e[k] = v end
            e.dmg = floor(s.dmg * dmgPct / 100)
            e.range = floor(s.range * rangePct / 100)
            e.cost = floor(s.cost * costPct / 100)
            if s.reveal then e.reveal = floor(s.reveal * rangePct / 100) end
            stats[kind][rank] = e
        end
    end
    return stats
end

local function AbilityStart(C) return C.ability and (C.ability.first or C.ability.every) or 0 end

-- Rebuilds the "_" fields from the saved ones, and gives fields added since older snapshots their defaults.
local function Index(state)
    local level = Levels.byId[state.level]
    state._level, state._geo = level, Engine.Geometry(level)
    state.loadout.specs = state.loadout.specs or {}
    state._stats = BuildStats(state.loadout)
    state._allowed = {}
    for _, kind in ipairs(state.loadout.towers) do state._allowed[kind] = true end
    if state.loadout.hero then state._allowed[state.loadout.hero] = true end
    state._byId, state._cells, state._births, state._bursts = {}, {}, {}, {}
    state.abilityCd = state.abilityCd or 0
    state.lust, state.lustEnd, state.wardEnd = state.lust or 0, state.lustEnd or 0, state.wardEnd or 0
    state.regrown = state.regrown or 0
    state.purse = state.purse or 0
    local alive = {}
    for _, c in ipairs(state.creeps) do if not c.dead then alive[#alive + 1] = c end end
    state.creeps = alive
    for _, a in ipairs(state.active) do assert(level.waves[a.wave], "wave " .. tostring(a.wave)) end
    for _, c in ipairs(state.creeps) do
        local C = Content.creeps[c.kind]
        state._byId[c.id] = c
        c.scale = c.scale or floor(c.maxHp * 100 / C.hp)
        c.cd = c.cd or 0
        c.stunEnd, c.steadyEnd = c.stunEnd or 0, c.steadyEnd or 0
        c.dot, c.dotEnd, c.spread = c.dot or 0, c.dotEnd or 0, c.spread or 0
        c.vuln, c.vulnEnd = c.vuln or 0, c.vulnEnd or 0
        c.bane, c.baneEnd = c.bane or 0, c.baneEnd or 0
        c.silenceEnd, c.raged = c.silenceEnd or 0, c.raged or 0
        c.acd = c.acd or AbilityStart(C)
        c._x, c._y = Engine.PathXY(state._geo.paths[c.path], c.d)
    end
    for _, t in ipairs(state.towers) do
        assert(state._stats[t.kind] and state._stats[t.kind][t.rank], "tower " .. tostring(t.kind))
        state._cells[CellKey(level, t.c, t.r)] = t
        t.stunEnd = t.stunEnd or 0
    end
    return state
end

-- Every tower allowed, no hero, nothing researched: what the engine assumes without a loadout.
function Engine.DefaultLoadout()
    local towers = {}
    for i, kind in ipairs(Content.towerOrder) do towers[i] = kind end
    return { towers = towers, difficulty = "normal", hpPct = 100, goldPct = 100 }
end

-- A new run of `level` (a Levels entry or its id). The loadout is copied in, so the run carries everything it
-- depends on besides the static content.
function Engine.New(level, loadout, seed)
    if type(level) == "string" then level = Levels.byId[level] end
    if not level then return nil, "level" end
    loadout = loadout or Engine.DefaultLoadout()
    local copy = { towers = {}, difficulty = loadout.difficulty or "normal", hpPct = loadout.hpPct or 100,
        goldPct = loadout.goldPct or 100, lives = loadout.lives or 0, bonus = {}, specs = {}, hero = loadout.hero }
    for i, kind in ipairs(loadout.towers or {}) do copy.towers[i] = kind end
    for kind, n in pairs(loadout.specs or {}) do copy.specs[kind] = n end
    for kind, b in pairs(loadout.bonus or {}) do
        copy.bonus[kind] = { dmgPct = b.dmgPct, rangePct = b.rangePct, costPct = b.costPct }
    end
    local state = {
        schema = Engine.SCHEMA, level = level.id, seed = seed or 1, rng = Engine.NewRng(seed),
        tick = 0, gold = floor(level.gold * copy.goldPct / 100), lives = level.lives + copy.lives,
        maxLives = level.lives + copy.lives,
        wave = 0, active = {}, creeps = {}, towers = {}, shots = {}, nextId = 1, over = false,
        loadout = copy, stats = { kills = 0, leaks = 0, built = 0, spent = 0 }, purse = 0,
    }
    return Index(state)
end

local function Push(out, e) if out then out[#out + 1] = e end end

function Engine.TowerAt(state, c, r) return state._cells[CellKey(state._level, c, r)] end
function Engine.IsRoad(state, c, r) return state._geo.road[CellKey(state._level, c, r)] == true end
function Engine.IsBlocked(state, c, r) return state._geo.blocked[CellKey(state._level, c, r)] == true end
function Engine.Creep(state, id) return state._byId[id] end
function Engine.Stats(state, kind, rank) return state._stats[kind] and state._stats[kind][rank] end
function Engine.TowerXY(t) return t.c * CELL - CELL / 2, t.r * CELL - CELL / 2 end

-- Whether a creep can be seen: stealthed creeps can't be hit until a revealing tower is near them.
function Engine.Seen(c) return c._seen ~= false end
local Seen = Engine.Seen
local function Air(c) return Content.creeps[c.kind].air == true end

-- The placed hero (a tower), or nil.
function Engine.Hero(state)
    if not state.heroId then return nil end
    for _, t in ipairs(state.towers) do
        if t.id == state.heroId then return t end
    end
end

function Engine.UpgradeCost(state, t)
    if t.rank >= 3 then return nil end
    local s = state._stats[t.kind][t.rank + 1]
    return s and s.cost or nil
end

-- Specialization i (1 or 2) of a tower kind: its stats (with .name and .cost), and whether this run may take it.
function Engine.Spec(state, kind, i)
    local s = state._stats[kind] and state._stats[kind][3 + i]
    if not s then return nil end
    return s, (state.loadout.specs[kind] or 0) >= i
end

function Engine.SellValue(t) return floor(t.spent * Engine.SELL_PCT / 100) end

-- Whether a tower of `kind` could go on cell (c, r) now: true, or false and a reason.
function Engine.CanBuild(state, kind, c, r)
    local level = state._level
    if state.over then return false, "over" end
    if type(c) ~= "number" or type(r) ~= "number" or c ~= floor(c) or r ~= floor(r)
        or c < 1 or r < 1 or c > level.cols or r > level.rows then
        return false, "bounds"
    end
    if Engine.IsRoad(state, c, r) then return false, "road" end
    if Engine.IsBlocked(state, c, r) then return false, "blocked" end
    if Engine.TowerAt(state, c, r) then return false, "occupied" end
    if not state._allowed[kind] then return false, "locked" end
    if Content.towers[kind].hero and state.heroId then return false, "hero" end
    if state.gold < state._stats[kind][1].cost then return false, "gold" end
    return true
end

local function Reject(reason) return { { kind = "rejected", reason = reason } } end

local function ActiveWave(state, w)
    for _, a in ipairs(state.active) do
        if a.wave == w then return a end
    end
end

local function InRange(c, x, y, range)
    local dx, dy = c._x - x, c._y - y
    return dx * dx + dy * dy <= range * range
end

local function Remove(state, c)
    c.dead = true
    state._byId[c.id] = nil
    local a = ActiveWave(state, c.wave)
    if a then a.alive = a.alive - 1 end
end

-- Damage over time: a stronger (or equal) one replaces the one running and restarts its clock.
local function Dot(state, c, dmg, ticks, spread)
    if c.dotEnd < state.tick or dmg >= c.dot then
        c.dot, c.dotEnd, c.spread = dmg, state.tick + ticks, spread and 1 or 0
    end
end

-- A curse: the creep takes `pct`% more damage from everything while it lasts.
local function Curse(state, c, V)
    if c.vulnEnd < state.tick or V.pct >= c.vuln then c.vuln, c.vulnEnd = V.pct, state.tick + V.ticks end
end

-- A dying plague host passes what's left of its plague to the nearest creep.
local function Spread(state, from, out)
    local best, bestD
    for _, c in ipairs(state.creeps) do
        if not c.dead and c ~= from then
            local dx, dy = c._x - from._x, c._y - from._y
            local d = dx * dx + dy * dy
            if d <= Engine.SPREAD * Engine.SPREAD and (not bestD or d < bestD) then best, bestD = c, d end
        end
    end
    if not best then return end
    Dot(state, best, from.dot, from.dotEnd - state.tick, true)
    Push(out, { kind = "spread", x1 = from._x, y1 = from._y, x = best._x, y = best._y })
end

-- Gold earned in play (a bounty, a wave bonus, an early call): Engine.INCOME percent of it, exactly over time, as
-- what doesn't make a whole coin waits in state.purse (hundredths of a coin). Returns the whole gold paid now.
local function Earn(state, amount)
    local cents = state.purse + amount * Engine.INCOME
    local paid = floor(cents / 100)
    state.purse = cents - paid * 100
    state.gold = state.gold + paid
    return paid
end

local function Hurt(state, c, dmg, damageType, out)
    if c.dead then return end
    local C = Content.creeps[c.kind]
    local cut = damageType == "magic" and (C.resist or 0) or (C.armor or 0)
    local amount = max(1, floor(dmg * (100 - cut) / 100))
    if c.vulnEnd >= state.tick then amount = floor(amount * (100 + c.vuln) / 100) end
    c.hp = c.hp - amount
    if c.hp <= 0 then
        local paid = Earn(state, C.bounty)
        state.stats.kills = state.stats.kills + 1
        Remove(state, c)
        Push(out, { kind = "killed", id = c.id, creep = c.kind, x = c._x, y = c._y, gold = paid,
            boss = C.boss == true })
        if C.split then -- born at the end of the tick, a little behind one another
            local births = state._births
            for i = 1, C.split.count do
                births[#births + 1] = { kind = C.split.creep, path = c.path, d = max(0, c.d - (i - 1) * 150),
                    scale = c.scale, wave = c.wave }
            end
        end
        if c.spread == 1 and c.dotEnd > state.tick then Spread(state, c, out) end
        if c.bane > 0 and c.baneEnd >= state.tick then -- explodes once the tick's shots are done
            local q = state._bursts
            q[#q + 1] = { x = floor(c._x), y = floor(c._y), dmg = c.bane }
        end
    end
end

-- A creep enters `d` milli-cells along `path`. `scale` is its health in percent of the base (wave x difficulty).
local function NewCreep(state, kind, path, d, scale, wave, out)
    local C = Content.creeps[kind]
    local hp = max(1, floor(C.hp * scale / 100))
    local c = { id = state.nextId, kind = kind, path = path, d = d, hp = hp, maxHp = hp, wave = wave, scale = scale,
        slow = 0, slowEnd = 0, stunEnd = 0, steadyEnd = 0, cd = C.heal and C.heal.every or 0, dot = 0, dotEnd = 0,
        spread = 0, vuln = 0, vulnEnd = 0, bane = 0, baneEnd = 0, silenceEnd = 0, raged = 0, acd = AbilityStart(C) }
    state.nextId = state.nextId + 1
    c._x, c._y = Engine.PathXY(state._geo.paths[path], d)
    if C.stealth then c._seen = false end
    state.creeps[#state.creeps + 1] = c
    state._byId[c.id] = c
    local a = ActiveWave(state, wave)
    if a then a.alive = a.alive + 1 end
    Push(out, { kind = "spawn", id = c.id, creep = kind })
end

-- A group's creep health in percent of its creep's: three layers multiplied (the level's `waves.hp`, its wave's `hp`
-- and its own, each 100 unless set: Levels.lua), then the difficulty's `hpPct`, with one rounding at the end.
function Engine.GroupHpPct(level, w, grp, hpPct)
    local waves = level.waves
    return floor(grp.hp * (waves[w].hp or 100) * (waves.hp or 100) * (hpPct or 100) / 1000000)
end

local function Spawn(state, a, grp, out)
    local C = Content.creeps[grp.creep]
    local path = grp.path or (C.air and state._level.airPath) or 1
    a.pending = a.pending - 1
    NewCreep(state, grp.creep, path, 0, Engine.GroupHpPct(state._level, a.wave, grp, state.loadout.hpPct), a.wave, out)
end

-- A slow: the stronger one wins, and an equal one refreshes.
local function Chill(state, c, pct, ticks)
    if c.slowEnd < state.tick or c.slow <= pct then c.slow, c.slowEnd = pct, state.tick + ticks end
end

-- A stun (a hex, roots, a freeze): the creep can't move for `ticks`, then it's steady for Engine.STEADY ticks and
-- shrugs off any stun until that's over, so two stunning towers can't hold it down between them. Its slow keeps
-- running underneath. Returns whether it took.
local function Stun(state, c, ticks)
    if c.steadyEnd >= state.tick then return false end
    c.stunEnd = state.tick + ticks
    c.steadyEnd = c.stunEnd + Engine.STEADY
    return true
end

-- Speed this tick, after enrage and any slow; nothing while stunned.
local function Speed(state, c)
    if c.stunEnd >= state.tick then return 0 end
    local C = Content.creeps[c.kind]
    local speed = C.speed
    if C.enrage and c.hp * 100 < c.maxHp * C.enrage.below then speed = floor(speed * C.enrage.pct / 100) end
    if c.slowEnd >= state.tick then speed = floor(speed * (100 - c.slow) / 100) end
    return speed
end

-- A boss's ability, when its timer runs out: stun the towers near it, call help, or jump ahead along the road.
local function BossAbility(state, c, A, out)
    local tick = state.tick
    if A.kind == "stomp" then
        for _, t in ipairs(state.towers) do
            local tx, ty = Engine.TowerXY(t)
            local dx, dy = tx - c._x, ty - c._y
            if dx * dx + dy * dy <= A.range * A.range then t.stunEnd = tick + A.ticks end
        end
        Push(out, { kind = "stomp", id = c.id, creep = c.kind, x = c._x, y = c._y, r = A.range })
    elseif A.kind == "summon" then
        local births = state._births
        for i = 1, A.count do
            births[#births + 1] = { kind = A.creep, path = c.path, d = max(0, c.d - i * 300), scale = c.scale,
                wave = c.wave }
        end
        Push(out, { kind = "summon", id = c.id, creep = c.kind, x = c._x, y = c._y })
    elseif A.kind == "blink" then
        local path = state._geo.paths[c.path]
        local x1, y1 = c._x, c._y
        c.d = min(path.len - 1, c.d + A.distance)
        c._x, c._y = Engine.PathXY(path, c.d)
        Push(out, { kind = "blink", id = c.id, creep = c.kind, x1 = x1, y1 = y1, x = c._x, y = c._y })
    end
end

-- Regeneration and damage over time (once a second), healers and bosses (each on its own timer), and Starfall.
-- A silenced creep (Wailing Arrow) neither heals nor uses its ability.
local function Abilities(state, out)
    local tick = state.tick
    local second = tick % Engine.HZ == 0
    for _, c in ipairs(state.creeps) do
        local C = Content.creeps[c.kind]
        local silenced = c.silenceEnd >= tick
        if not c.dead and second and C.regen and not silenced and c.hp < c.maxHp then
            c.hp = min(c.maxHp, c.hp + max(1, floor(C.regen * c.scale / 100)))
        end
        if not c.dead and second and c.dotEnd >= tick then Hurt(state, c, c.dot, "magic", out) end
        local heal = C.heal
        if not c.dead and heal and not silenced then
            c.cd = c.cd - 1
            if c.cd <= 0 then
                c.cd = heal.every
                local healed = false
                for _, o in ipairs(state.creeps) do
                    if o ~= c and not o.dead and o.hp < o.maxHp and o.silenceEnd < tick
                        and InRange(o, c._x, c._y, heal.range) then
                        o.hp = min(o.maxHp, o.hp + max(1, floor(o.maxHp * heal.pct / 100)))
                        healed = true
                    end
                end
                if healed then Push(out, { kind = "healed", id = c.id, x = c._x, y = c._y, r = heal.range }) end
            end
        end
        if not c.dead and C.ability and not silenced then
            c.acd = c.acd - 1
            if c.acd <= 0 then
                c.acd = C.ability.every
                BossAbility(state, c, C.ability, out)
            end
        end
        if not c.dead and C.enrage and c.raged == 0 and c.hp * 100 < c.maxHp * C.enrage.below then
            c.raged = 1
            Push(out, { kind = "enraged", id = c.id, creep = c.kind, x = c._x, y = c._y })
        end
    end
    local fall = state.fall
    if fall then
        if tick > fall.stop then
            state.fall = nil
        elseif (tick - fall.start) % fall.every == 0 then
            for _, c in ipairs(state.creeps) do
                if not c.dead and Seen(c) and InRange(c, fall.x, fall.y, fall.r) then
                    Hurt(state, c, fall.dmg, "magic", out)
                end
            end
            Push(out, { kind = "starfall", x = fall.x, y = fall.y, r = fall.r })
        end
    end
end

-- Which stealthed creeps a revealing tower can see this tick (rebuilt every tick, so it's never saved).
local function Reveal(state)
    local any = false
    for _, c in ipairs(state.creeps) do
        if Content.creeps[c.kind].stealth then c._seen, any = false, true end
    end
    if not any then return end
    for _, t in ipairs(state.towers) do
        local S = state._stats[t.kind][t.rank]
        if S.reveal then
            local x, y = Engine.TowerXY(t)
            for _, c in ipairs(state.creeps) do
                if c._seen == false and not c.dead and InRange(c, x, y, S.reveal) then c._seen = true end
            end
        end
    end
end

-- Bonus damage from what the target is: undead and demons (holy), flyers (airBonus), already slowed (or stunned)
-- creeps.
local function Bonus(state, S, c, dmg)
    local C = Content.creeps[c.kind]
    local pct = 100
    if S.holy and (C.undead or C.demon) then pct = pct + S.holy end
    if S.airBonus and C.air then pct = pct + S.airBonus end
    if S.bonusVsSlowed and (c.slowEnd >= state.tick or c.stunEnd >= state.tick) then pct = pct + S.bonusVsSlowed end
    if pct == 100 then return dmg end
    return floor(dmg * pct / 100)
end

-- What a hit leaves on a creep. Splash victims get everything but the stun (that's for the creep the bomb hit).
local function Afflict(state, S, c, splashed)
    if S.slow then Chill(state, c, S.slow, S.slowTicks) end
    if S.stun and not splashed then Stun(state, c, S.stun) end
    if S.dot then Dot(state, c, S.dot.dmg, S.dot.seconds * Engine.HZ, S.spread) end
    if S.vuln then Curse(state, c, S.vuln) end
    if S.bane then c.bane, c.baneEnd = S.bane.dmg, state.tick + S.bane.ticks end
end

-- Lightning jumps from creep to creep (a glaive bounces): each time to the nearest one not yet hit within S.jump,
-- a little weaker.
local function Chain(state, from, dmg, S, out)
    local hit = { [from.id] = true }
    local x, y = from._x, from._y
    for _ = 1, S.chain do
        dmg = floor(dmg * S.falloff / 100)
        if dmg < 1 then return end
        local best, bestD
        for _, c in ipairs(state.creeps) do
            if not c.dead and not hit[c.id] and Seen(c) then
                local dx, dy = c._x - x, c._y - y
                local d = dx * dx + dy * dy
                if d <= S.jump * S.jump and (not bestD or d < bestD) then best, bestD = c, d end
            end
        end
        if not best then return end
        hit[best.id] = true
        Push(out, { kind = "zap", x1 = x, y1 = y, x = best._x, y = best._y, damage = S.damage })
        x, y = best._x, best._y
        Hurt(state, best, Bonus(state, S, best, dmg), S.damage, out)
    end
end

local function Land(state, s, out)
    local S = state._stats[s.tower][s.rank]
    local c = state._byId[s.target]
    if S.misfire and Engine.Random(state.rng, 100) <= S.misfire then
        local x, y = s.ax, s.ay
        if c then x, y = c._x, c._y end
        Push(out, { kind = "misfire", x = x, y = y })
        return
    end
    local base = S.dmg
    if S.crit and Engine.Random(state.rng, 100) <= S.crit.pct then
        base = floor(base * S.crit.mult / 100)
        if c then Push(out, { kind = "crit", x = c._x, y = c._y }) end
    end
    if s.pct and s.pct ~= 100 then base = floor(base * s.pct / 100) end
    if S.splash then
        local x, y = s.ax, s.ay
        if c then x, y = c._x, c._y end
        if c and S.stun then Stun(state, c, S.stun) end
        for _, other in ipairs(state.creeps) do
            if not other.dead and Seen(other) and not Air(other) and InRange(other, x, y, S.splash) then
                local dmg = Bonus(state, S, other, base)
                Afflict(state, S, other, true)
                Hurt(state, other, dmg, S.damage, out)
            end
        end
        Push(out, { kind = "blast", x = x, y = y, r = S.splash, tower = s.tower, rank = s.rank })
    elseif c then
        local dmg = Bonus(state, S, c, base)
        Afflict(state, S, c)
        Push(out, { kind = "hit", tower = s.tower, rank = s.rank, x = c._x, y = c._y, sx = s.sx, sy = s.sy })
        Hurt(state, c, dmg, S.damage, out)
        if S.chain then Chain(state, c, base, S, out) end
    end
end

-- Corpses that explode (bane), each hurting the creeps around it; one can set off the next.
local function Bursts(state, out)
    local q = state._bursts
    local i = 1
    while i <= #q do -- a burst can set off another: it joins the end of the queue and goes off this tick too
        local b = q[i]
        i = i + 1
        for _, c in ipairs(state.creeps) do
            if not c.dead and Seen(c) and not Air(c) and InRange(c, b.x, b.y, Engine.BURST) then
                Hurt(state, c, b.dmg, "magic", out)
            end
        end
        Push(out, { kind = "burst", x = b.x, y = b.y, r = Engine.BURST })
    end
    for k = #q, 1, -1 do q[k] = nil end
end

-- The targets a tower would pick: the `n` creeps in range closest to getting through (ties: the oldest). A tower
-- that stuns (`stuns`) picks among the creeps a stun would take on first, and only then the steady ones.
local picked = {}
local function Picked(c)
    for i = 1, #picked do if picked[i] == c then return true end end
    return false
end
local function Targets(state, x, y, range, hitsAir, n, stuns)
    for i = #picked, 1, -1 do picked[i] = nil end
    local paths, tick = state._geo.paths, state.tick
    for _ = 1, n do
        local best, bestLeft, fresh, freshLeft
        for _, c in ipairs(state.creeps) do
            if not c.dead and Seen(c) and (hitsAir or not Air(c)) and InRange(c, x, y, range)
                and not Picked(c) then
                local left = paths[c.path].len - c.d
                if not bestLeft or left < bestLeft then best, bestLeft = c, left end
                if stuns and c.steadyEnd < tick and (not freshLeft or left < freshLeft) then
                    fresh, freshLeft = c, left
                end
            end
        end
        best = fresh or best
        if not best then break end
        picked[#picked + 1] = best
    end
    return picked
end

-- The best aura of `field` ("haste" or "might") that reaches (x, y), from any tower but `t` itself.
local function Aura(state, t, field, x, y)
    local best = 0
    for _, o in ipairs(state.towers) do
        if o ~= t then
            local O = state._stats[o.kind][o.rank]
            local v = O[field]
            if v and v > best then
                local ox, oy = Engine.TowerXY(o)
                if (ox - x) * (ox - x) + (oy - y) * (oy - y) <= O.aura * O.aura then best = v end
            end
        end
    end
    return best
end

-- Cooldown after firing, shortened by the best haste aura in reach and by Bloodlust.
local function Cooldown(state, t, S, x, y)
    local haste = Aura(state, t, "haste", x, y)
    if state.lustEnd >= state.tick then haste = haste + state.lust end
    haste = min(Engine.MAX_HASTE, haste)
    return haste > 0 and max(1, floor(S.cd * (100 - haste) / 100)) or S.cd
end

local function Fire(state, t, out)
    local S = state._stats[t.kind][t.rank]
    local x, y = Engine.TowerXY(t)
    local hitsAir = S.air == true
    local pct = 100 + Aura(state, t, "might", x, y)
    if S.pulse then
        local hit = false
        local base = pct ~= 100 and floor(S.dmg * pct / 100) or S.dmg
        for _, c in ipairs(state.creeps) do
            if not c.dead and Seen(c) and (hitsAir or not Air(c)) and InRange(c, x, y, S.range) then
                hit = true
                local dmg = Bonus(state, S, c, base)
                Afflict(state, S, c)
                Hurt(state, c, dmg, S.damage, out)
            end
        end
        if hit then
            t.cd = Cooldown(state, t, S, x, y)
            Push(out, { kind = "pulse", id = t.id, tower = t.kind, rank = t.rank, x = x, y = y, r = S.range })
        end
        return
    end
    local targets = Targets(state, x, y, S.range, hitsAir, S.multi or 1, S.stun)
    if #targets == 0 then return end
    for _, c in ipairs(targets) do
        local dx, dy = c._x - x, c._y - y
        local travel = max(1, math.ceil(sqrt(dx * dx + dy * dy) / S.shot))
        state.shots[#state.shots + 1] = { id = state.nextId, tower = t.kind, rank = t.rank, from = t.id,
            target = c.id, fire = state.tick, land = state.tick + travel, sx = x, sy = y,
            ax = floor(c._x), ay = floor(c._y), pct = pct }
        state.nextId = state.nextId + 1
    end
    t.cd = Cooldown(state, t, S, x, y)
    Push(out, { kind = "fire", id = t.id, tower = t.kind, rank = t.rank })
end

local function Compact(list)
    local n = 0
    for i = 1, #list do
        local v = list[i]
        list[i] = nil
        if not v.dead then n = n + 1; list[n] = v end
    end
end

-- Creeps born this tick (splits, summons), entering the board.
local function Births(state, out)
    local births = state._births
    for i = 1, #births do
        local b = births[i]
        births[i] = nil
        NewCreep(state, b.kind, b.path, b.d, b.scale, b.wave, out)
    end
end

-- The hero's ability. Returns its events. It runs between ticks, so whatever it kills is settled at once (corpses
-- burst, splitters split, the dead leave the list): nothing waits in the unsaved "_" queues.
local function Cast(state, hero)
    local out = {}
    local A = Content.towers[hero.kind].ability
    local x, y = Engine.TowerXY(hero)
    local tick = state.tick
    if A.kind == "bloodlust" then
        state.lust, state.lustEnd = A.pct, tick + A.ticks
    elseif A.kind == "shield" then
        state.wardEnd = tick + A.ticks
    elseif A.kind == "starfall" then
        state.fall = { x = x, y = y, r = A.range, dmg = A.dmg, every = A.every, start = tick + 1,
            stop = tick + A.ticks }
    elseif A.kind == "wail" then
        for _, c in ipairs(state.creeps) do
            if not c.dead and Seen(c) and InRange(c, x, y, A.range) then
                c.silenceEnd = tick + A.silence
                if A.stun then Stun(state, c, A.stun) end
                Hurt(state, c, A.dmg, "magic", out)
            end
        end
    end
    state.abilityCd = A.cd
    Bursts(state, out)
    Births(state, out)
    Compact(state.creeps)
    table.insert(out, 1, { kind = "ability", ability = A.kind, hero = hero.kind, id = hero.id, x = x, y = y,
        r = A.range or 0, ticks = A.ticks or 0 })
    return out
end

-- Player intent -> validated state change. Returns a list of events for the presentation layer. Never errors on
-- bad input. Actions: { kind = "place", tower, c, r }, { kind = "upgrade", id, spec = nil | 1 | 2 },
-- { kind = "sell", id }, { kind = "wave" } (start the next wave; early calls pay level.earlyBonus),
-- { kind = "ability" } (the hero's ability, when it's ready).
function Engine.Apply(state, action)
    if type(action) ~= "table" then return Reject("invalid") end
    if state.over then return Reject("over") end
    if action.kind == "place" then
        local ok, why = Engine.CanBuild(state, action.tower, action.c, action.r)
        if not ok then return Reject(why) end
        local cost = state._stats[action.tower][1].cost
        local t = { id = state.nextId, kind = action.tower, c = action.c, r = action.r, rank = 1, cd = 0, spent = cost,
            stunEnd = 0 }
        state.nextId = state.nextId + 1
        state.gold = state.gold - cost
        state.stats.built, state.stats.spent = state.stats.built + 1, state.stats.spent + cost
        state.towers[#state.towers + 1] = t
        state._cells[CellKey(state._level, t.c, t.r)] = t
        local T = Content.towers[t.kind]
        if T.hero then
            state.heroId = t.id
            state.abilityCd = T.ability.first or floor(T.ability.cd / 3)
        end
        return { { kind = "placed", id = t.id, tower = t.kind, hero = T.hero == true } }
    elseif action.kind == "upgrade" or action.kind == "sell" then
        local t, index
        for i, tower in ipairs(state.towers) do
            if tower.id == action.id then t, index = tower, i end
        end
        if not t then return Reject("missing") end
        if action.kind == "sell" then
            if Content.towers[t.kind].hero then return Reject("hero") end
            local refund = Engine.SellValue(t)
            state.gold = state.gold + refund
            table.remove(state.towers, index)
            state._cells[CellKey(state._level, t.c, t.r)] = nil
            return { { kind = "sold", id = t.id, gold = refund } }
        end
        local cost, rank = Engine.UpgradeCost(state, t), t.rank + 1
        if action.spec then -- a rank-3 tower takes specialization 1 or 2, if the Armory has opened it
            local S, open = nil, false
            if t.rank == 3 and (action.spec == 1 or action.spec == 2) then
                S, open = Engine.Spec(state, t.kind, action.spec)
            end
            if not S then return Reject("max") end
            if not open then return Reject("research") end
            cost, rank = S.cost, 3 + action.spec
        end
        if not cost then return Reject("max") end
        if state.gold < cost then return Reject("gold") end
        state.gold, t.rank, t.spent = state.gold - cost, rank, t.spent + cost
        state.stats.spent = state.stats.spent + cost
        return { { kind = "upgraded", id = t.id, rank = t.rank } }
    elseif action.kind == "wave" then
        local waves = state._level.waves
        if state.wave >= #waves then return Reject("nowaves") end
        local early = #state.active > 0
        state.wave = state.wave + 1
        local pending = 0
        for _, grp in ipairs(waves[state.wave]) do pending = pending + grp.count end
        state.active[#state.active + 1] = { wave = state.wave, t = 0, pending = pending, alive = 0 }
        local bonus = early and Earn(state, state._level.earlyBonus or 0) or 0
        return { { kind = "waveStart", wave = state.wave, bonus = bonus } }
    elseif action.kind == "ability" then
        local hero = Engine.Hero(state)
        if not hero then return Reject("nohero") end
        if state.abilityCd > 0 then return Reject("cooldown") end
        return Cast(state, hero)
    end
    return Reject("unknown")
end

-- One fixed step of simulation. Appends events to `out` (optional) and returns it.
function Engine.Tick(state, out)
    if state.over then return out end
    state.tick = state.tick + 1
    local tick, level, paths = state.tick, state._level, state._geo.paths
    if state.abilityCd > 0 then state.abilityCd = state.abilityCd - 1 end
    -- 1. spawns, from each running wave's own clock
    for _, a in ipairs(state.active) do
        for _, grp in ipairs(level.waves[a.wave]) do
            local k = a.t - grp.delay
            if k >= 0 and k % grp.gap == 0 and k / grp.gap < grp.count then Spawn(state, a, grp, out) end
        end
        a.t = a.t + 1
    end
    -- 2. movement, and creeps that get through (free while Divine Shield holds)
    for _, c in ipairs(state.creeps) do
        if not c.dead then -- (nothing dies between ticks now, but a corpse must never walk)
            c.d = c.d + Speed(state, c)
            local path = paths[c.path]
            if c.d >= path.len then
                local lost = Content.creeps[c.kind].lives or 1
                local warded = state.wardEnd >= tick
                if warded then lost = 0 end
                state.lives = max(0, state.lives - lost)
                state.stats.leaks = state.stats.leaks + 1
                Remove(state, c)
                Push(out, { kind = "leaked", id = c.id, creep = c.kind, lives = lost, warded = warded, x = c._x,
                    y = c._y })
            else
                c._x, c._y = Engine.PathXY(path, c.d)
            end
        end
    end
    Reveal(state) -- before anything aims: Starfall and towers see the same creeps
    Abilities(state, out)
    -- 3. shots that land this tick
    for _, s in ipairs(state.shots) do
        if s.land <= tick then
            s.dead = true
            Land(state, s, out)
        end
    end
    -- 4. towers (a stunned tower waits)
    for _, t in ipairs(state.towers) do
        if t.cd > 0 then t.cd = t.cd - 1 end
        if t.cd <= 0 and t.stunEnd < tick then Fire(state, t, out) end
    end
    Bursts(state, out)
    Births(state, out) -- creeps that split or were called this tick
    Compact(state.creeps)
    Compact(state.shots)
    -- 5. waves that are done (a tower that regrows restores a life: one a wave, its regrow a level), then the end
    for i = #state.active, 1, -1 do
        local a = state.active[i]
        if a.pending == 0 and a.alive <= 0 then
            table.remove(state.active, i)
            local wb = level.waveBonus
            local bonus = wb and Earn(state, wb.base + wb.step * a.wave) or 0
            Push(out, { kind = "waveCleared", wave = a.wave, bonus = bonus })
            local grower, most = nil, 0
            for _, t in ipairs(state.towers) do
                local S = state._stats[t.kind][t.rank]
                if S.regrow and S.regrow > most then grower, most = t, S.regrow end
            end
            if grower and state.regrown < most and state.lives > 0 and state.lives < state.maxLives then
                state.lives, state.regrown = state.lives + 1, state.regrown + 1
                local x, y = Engine.TowerXY(grower)
                Push(out, { kind = "regrow", id = grower.id, x = x, y = y })
            end
        end
    end
    if state.lives <= 0 then
        state.over = "lost"
        Push(out, { kind = "over", result = "lost" })
    elseif state.wave >= #level.waves and #state.active == 0 then
        state.over = "won"
        Push(out, { kind = "over", result = "won" })
    end
    return out
end

-- Frame time -> fixed steps. `clock` is the caller's { acc = 0 }; `speed` is 1 or 2. Clamped, so a 5-second hitch
-- is one bounded catch-up, and frame rate never changes the outcome. Returns the number of steps run.
function Engine.Advance(state, clock, elapsed, speed, out)
    clock.acc = clock.acc + min(max(tonumber(elapsed) or 0, 0), Engine.MAX_FRAME) * (speed or 1)
    local steps = 0
    while clock.acc >= Engine.STEP do
        clock.acc = clock.acc - Engine.STEP
        steps = steps + 1
        Engine.Tick(state, out)
    end
    return steps
end

-- Where to draw a creep, `alpha` (0..1) of the way to its next tick.
function Engine.CreepXY(state, c, alpha)
    if not alpha or alpha <= 0 then return c._x, c._y end
    return Engine.PathXY(state._geo.paths[c.path], c.d + Speed(state, c) * alpha)
end

-- What a wave holds, merged by creep type, in first-seen order: { { creep, count }, ... }.
function Engine.WaveSummary(level, w)
    local list, at = {}, {}
    for _, grp in ipairs(level.waves[w] or {}) do
        local i = at[grp.creep]
        if not i then
            i = #list + 1
            at[grp.creep] = i
            list[i] = { creep = grp.creep, count = 0 }
        end
        list[i].count = list[i].count + grp.count
    end
    return list
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then out[k] = Copy(x) end
    end
    return out
end

-- Plain data only (no functions, frames or "_" fields), safe for SavedVariables.
function Engine.Snapshot(state) return Copy(state) end

-- Snapshot -> state, or nil and a reason. Unknown schemas and levels are refused, not guessed at.
function Engine.Restore(snap)
    if type(snap) ~= "table" then return nil, "missing" end
    if snap.schema ~= Engine.SCHEMA then return nil, "schema " .. tostring(snap.schema) end
    if not Levels.byId[snap.level] then return nil, "level " .. tostring(snap.level) end
    local state = Copy(snap)
    local ok, err = pcall(Index, state)
    if not ok then return nil, "corrupt: " .. tostring(err) end
    Reveal(state) -- stealthed creeps stay hidden while the restored run waits, paused
    return state
end

return Engine
