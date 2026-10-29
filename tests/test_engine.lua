-- Engine tests: the pure game files in TOC order, in a sandbox that hides io/os/require and can trap math.random.
local stub = require("wowstub")

local function load(T, trapRandom)
    local env = stub.env()
    if trapRandom then
        -- Determinism guard: rules code must use the engine's seeded PRNG, never math.random.
        local trapped = {}
        for k, v in pairs(math) do trapped[k] = v end
        trapped.random = function() error("math.random called from rules code", 2) end
        trapped.randomseed = trapped.random
        env.math = trapped
    end
    local ns = {}
    for _, file in ipairs(assert(loadfile(T.base .. "/tools/sim.lua"))("--lib").Files(T.base)) do
        stub.load(T.base .. "/ForeverTD/" .. file, "ForeverTD", ns, env)
    end
    return ns, ns.Engine
end

local function sim(T) return assert(loadfile(T.base .. "/tools/sim.lua"))("--lib") end

-- A straight 10-cell road along row 2 of a 10x3 board, registered so Restore can find it.
local function line(ns, waves, extra)
    local level = { id = "test-line", cols = 10, rows = 3, gold = 1000, lives = 5, length = "short",
        paths = { { { 0, 2 }, { 11, 2 } }, { air = true, { 0, 1 }, { 11, 1 } } }, airPath = 2,
        waves = waves or { { { creep = "boar", count = 1, gap = 1, delay = 0, hp = 100 } } } }
    for k, v in pairs(extra or {}) do level[k] = v end
    ns.Levels.byId[level.id] = level
    return level
end
local function G(creep, count, gap, hp)
    return { creep = creep, count = count, gap = gap or 1, delay = 0, hp = hp or 100 }
end

local function ticks(Engine, state, n) for _ = 1, n do Engine.Tick(state) end end

local tests = {}

tests["every level is valid, and validation catches a diagonal road"] = function(T)
    local ns, Engine = load(T)
    for _, level in ipairs(ns.Levels.list) do
        T.eq(table.concat(Engine.ValidateLevel(level), "; "), "", level.id)
    end
    local bad = line(ns)
    bad.paths[1] = { { 0, 1 }, { 5, 3 } }
    T.ok(#Engine.ValidateLevel(bad) > 0, "diagonal ground path refused")
end

tests["same seed and actions replay identically, and rules never call math.random"] = function(T)
    local ns = load(T, true)
    local S = sim(T)
    local a = S.Play(ns, "horde-2", "normal", "greedy", { seed = 42 })
    local b = S.Play(ns, "horde-2", "normal", "greedy", { seed = 42 })
    T.eq(a.result, "won", "greedy wins")
    T.eq(T.dump(a.final), T.dump(b.final), "replay")
end

tests["PRNG stays exact and in range"] = function(T)
    local _, Engine = load(T)
    local rng = Engine.NewRng(0) -- seed 0 must not lock the generator at zero
    for _ = 1, 10000 do
        local r = Engine.Random(rng, 6)
        T.ok(r >= 1 and r <= 6 and r == math.floor(r), "range")
    end
    T.ok(rng.s > 0 and rng.s < 2147483647, "state in range")
end

-- SavedVariables-style round trip: written out as Lua source, read back by running it.
local function serialize(v)
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end
local function reload(snap) return assert(loadstring("return " .. serialize(snap)))() end

tests["a save mid-wave restores to exactly the same game (the easy-in-and-out test)"] = function(T)
    local ns = load(T)
    local S = sim(T)
    -- a plain level, then one level of each campaign with its hero in play (Bloodlust, Divine Shield, Starfall,
    -- Wailing Arrow), so cooldowns, curses, plagues and boss timers are all mid-flight at some of these ticks
    for _, id in ipairs({ "horde-2", "horde-6", "alliance-6", "sentinels-5", "forsaken-5" }) do
        local whole = S.Play(ns, id, "normal", "greedy")
        for _, at in ipairs({ 1, 400, 2345, 5000 }) do -- before, during and late in the waves
            local split = S.Play(ns, id, "normal", "greedy", { snapshotAt = at, transform = reload })
            T.eq(T.dump(split.final), T.dump(whole.final), id .. " saved and restored at tick " .. at)
        end
    end
end

tests["snapshots hold only whole numbers, strings and booleans"] = function(T)
    local ns, Engine = load(T)
    local S = sim(T)
    local state = Engine.New("horde-2", nil, 5)
    local step = S.strategies.greedy()
    for _ = 1, 6000 do
        step(ns, state)
        Engine.Tick(state)
        if state.tick > 900 and #state.creeps > 0 and #state.shots > 0 then break end
    end
    T.ok(#state.creeps > 0 and #state.shots > 0, "mid-wave, with shots in the air")
    local function plain(v)
        local t = type(v)
        if t == "table" then
            for k, x in pairs(v) do plain(k); plain(x) end
        elseif t == "number" then
            T.ok(v == math.floor(v), "whole number, got " .. v)
        else
            T.ok(t == "string" or t == "boolean", "SavedVariables-safe type: " .. t)
        end
    end
    plain(Engine.Snapshot(state))
end

tests["creeps walk the waypoints and cost lives at the end"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns)
    level.paths[1] = { { 0, 1 }, { 3, 1 }, { 3, 3 }, { 11, 3 } }
    local state = Engine.New(level)
    local path = state._geo.paths[1]
    T.eq(path.len, 3000 + 2000 + 8000, "length")
    local x, y = Engine.PathXY(path, 3000)
    T.eq(x, 2500, "corner x"); T.eq(y, 500, "corner y")
    x, y = Engine.PathXY(path, 4000)
    T.eq(x, 2500, "down the column x"); T.eq(y, 1500, "down the column y")
    T.ok(Engine.IsRoad(state, 3, 2) and Engine.IsRoad(state, 1, 1) and not Engine.IsRoad(state, 1, 2), "road cells")
    Engine.Apply(state, { kind = "wave" })
    ticks(Engine, state, math.ceil(path.len / ns.Content.creeps.boar.speed) + 2)
    T.eq(state.lives, 4, "a leak costs a life")
    T.eq(state.over, "won", "the only wave is over, with lives left")
end

tests["towers shoot the creep closest to getting through, and only archers and frost hit air"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 2), G("vulture", 1) } })
    local function first(kind)
        local state = Engine.New(level)
        Engine.Apply(state, { kind = "wave" })
        ticks(Engine, state, 2) -- both boars and the vulture are out
        local byKind = {}
        for _, c in ipairs(state.creeps) do byKind[#byKind + 1] = c end
        byKind[1].d, byKind[2].d, byKind[3].d = 4000, 6000, 5000 -- boar, vulture, boar: all in range of (5, 3)
        Engine.Apply(state, { kind = "place", tower = kind, c = 5, r = 3 })
        local out = Engine.Tick(state, {})
        for _, e in ipairs(out) do
            if e.kind == "fire" then return Engine.Creep(state, state.shots[#state.shots].target).kind,
                state.shots[#state.shots].target, byKind end
        end
    end
    local kind, id, creeps = first("archer")
    T.eq(kind, "vulture", "archer: the flyer is furthest along")
    T.eq(id, creeps[2].id, "archer target")
    kind, id, creeps = first("engineer")
    T.eq(kind, "boar", "engineer: ground only")
    T.eq(id, creeps[3].id, "engineer: the further boar")
end

tests["frost slows, and the stronger slow wins"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("scorpid", 1, 1, 1000) } })
    local plain, slowed = Engine.New(level), Engine.New(level)
    Engine.Apply(slowed, { kind = "place", tower = "frost", c = 2, r = 3 })
    for _, s in ipairs({ plain, slowed }) do Engine.Apply(s, { kind = "wave" }); ticks(Engine, s, 150) end
    local cp, cs = plain.creeps[1], slowed.creeps[1]
    T.ok(cs.d < cp.d, "slowed creep is behind: " .. cs.d .. " vs " .. cp.d)
    T.eq(cs.slow, ns.Content.towers.frost.ranks[1].slow, "slow percent")
    cs.slow, cs.slowEnd = 90, slowed.tick + 100 -- a stronger slow from elsewhere isn't overwritten by a weaker bolt
    ticks(Engine, slowed, 40)
    T.eq(cs.slow, 90, "kept the stronger slow")
end

tests["armour halves physical hits, magic ignores it, and splash hits a crowd"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("scorpid", 3, 2, 1000) } })
    local state = Engine.New(level)
    Engine.Apply(state, { kind = "place", tower = "engineer", c = 3, r = 1 })
    Engine.Apply(state, { kind = "wave" })
    local hp = ns.Content.creeps.scorpid.hp * 10
    local blasted
    for _ = 1, 120 do
        for _, e in ipairs(Engine.Tick(state, {})) do if e.kind == "blast" then blasted = true end end
        if blasted then break end
    end
    T.ok(blasted, "a bomb landed")
    local dmg = Engine.Stats(state, "engineer", 1).dmg
    local hurt = 0
    for _, c in ipairs(state.creeps) do if c.hp < hp then hurt = hurt + 1; T.eq(hp - c.hp, dmg / 2, "half") end end
    T.ok(hurt >= 2, "splash hit more than one creep: " .. hurt)
    local priest = Engine.New(level)
    Engine.Apply(priest, { kind = "place", tower = "priest", c = 2, r = 1 })
    Engine.Apply(priest, { kind = "wave" })
    ticks(Engine, priest, 60)
    T.eq(hp - priest.creeps[1].hp >= Engine.Stats(priest, "priest", 1).dmg, true, "magic: full damage")
end

tests["gold: building, upgrading, selling at 70%, bounties and wave bonuses"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 1) }, { G("boar", 1) } }, { gold = 200, earlyBonus = 10,
        waveBonus = { base = 10, step = 5 } })
    local state = Engine.New(level)
    local cost = Engine.Stats(state, "archer", 1).cost
    local placed = Engine.Apply(state, { kind = "place", tower = "archer", c = 5, r = 3 })[1]
    T.eq(placed.kind, "placed", "placed")
    T.eq(state.gold, 200 - cost, "paid")
    local up = Engine.UpgradeCost(state, state.towers[1])
    Engine.Apply(state, { kind = "upgrade", id = placed.id })
    T.eq(state.gold, 200 - cost - up, "upgrade paid")
    for _, why in ipairs({ { 5, 2, "road" }, { 5, 3, "occupied" }, { 0, 1, "bounds" }, { 2.5, 1, "bounds" } }) do
        T.eq(Engine.Apply(state, { kind = "place", tower = "archer", c = why[1], r = why[2] })[1].reason, why[3],
            why[3])
    end
    T.eq(Engine.Apply(state, { kind = "place", tower = "nope", c = 1, r = 1 })[1].reason, "locked", "unknown tower")
    for _, bad in ipairs({ "x", {}, { kind = "teleport" }, { kind = "sell", id = 999 } }) do
        T.eq(Engine.Apply(state, bad)[1].kind, "rejected", "bad action " .. T.dump(bad))
    end
    local before = state.gold
    local cut = function(n) return math.floor(n * Engine.INCOME / 100) end
    T.eq(Engine.Apply(state, { kind = "wave" })[1].bonus, 0, "first call isn't early")
    T.eq(Engine.Apply(state, { kind = "wave" })[1].bonus, cut(10), "second call is early: Engine.INCOME percent")
    T.eq(state.gold, before + cut(10), "early bonus paid")
    ticks(Engine, state, 600)
    T.eq(state.over, "won", "both boars dead")
    local earned = 10 + 2 * ns.Content.creeps.boar.bounty + (10 + 5) + (10 + 10)
    T.eq(state.gold, before + cut(earned), "bounties and bonuses, Engine.INCOME percent of them")
    T.eq(state.purse, earned * Engine.INCOME % 100, "and what doesn't make a coin waits in the purse")
    local s2 = Engine.New(level)
    Engine.Apply(s2, { kind = "place", tower = "archer", c = 5, r = 3 })
    Engine.Apply(s2, { kind = "upgrade", id = s2.towers[1].id })
    local spent = s2.towers[1].spent
    T.eq(Engine.Apply(s2, { kind = "sell", id = s2.towers[1].id })[1].gold, math.floor(spent * 0.7), "70%")
    T.eq(Engine.TowerAt(s2, 5, 3), nil, "cell free again")
    T.eq(Engine.Apply(state, { kind = "wave" })[1].reason, "over", "nothing after the end")
end

tests["regeneration, healers and splitters"] = function(T)
    local ns, Engine = load(T)
    local C = ns.Content.creeps
    -- every split names a real creep
    for kind, c in pairs(C) do
        if c.split then T.ok(C[c.split.creep] ~= nil, kind .. " splits into a known creep") end
    end
    local level = line(ns, { { G("timberling", 1, 1, 1000) } })
    local s = Engine.New(level)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 1)
    local t = s.creeps[1]
    t.hp = 100
    ticks(Engine, s, 30)
    T.eq(t.hp, 100 + C.timberling.regen * 10, "regen once a second, scaled with its health")
    t.hp = t.maxHp - 1
    ticks(Engine, s, 30)
    T.eq(t.hp, t.maxHp, "never above full")
    local heal = line(ns, { { G("furbolg", 1), G("boar", 1) } })
    local h = Engine.New(heal)
    Engine.Apply(h, { kind = "wave" })
    ticks(Engine, h, 1)
    local mystic, boar = h.creeps[1], h.creeps[2]
    boar.hp, mystic.hp = 1, 1
    local healed
    for _ = 1, C.furbolg.heal.every do
        for _, e in ipairs(Engine.Tick(h, {})) do if e.kind == "healed" then healed = e end end
    end
    T.ok(healed, "the mystic healed")
    T.eq(boar.hp, 1 + math.max(1, math.floor(boar.maxHp * C.furbolg.heal.pct / 100)), "the boar got pct of its health")
    T.eq(mystic.hp, 1, "a healer doesn't heal itself")
    local split = line(ns, { { G("spider", 1) } })
    local sp = Engine.New(split)
    Engine.Apply(sp, { kind = "wave" })
    ticks(Engine, sp, 40)
    local mother = sp.creeps[1]
    mother.hp = 1
    Engine.Apply(sp, { kind = "place", tower = "archer", c = 2, r = 3 })
    local before = sp.stats.kills
    for _ = 1, 60 do Engine.Tick(sp); if sp.stats.kills > before then break end end
    T.eq(#sp.creeps, C.spider.split.count, "three hatchlings")
    for _, c in ipairs(sp.creeps) do
        T.eq(c.kind, "spiderling", "hatchling")
        T.ok(c.d <= mother.d, "born where the mother died, or just behind")
    end
    T.eq(#sp.active, 1, "the wave isn't over while the hatchlings live")
    T.eq(sp.active[1].alive, 3, "and counts them")
end

-- A tower of `kind` on (c, r), upgraded to rank 3 and then to specialization `spec` (if given).
local function tower(Engine, s, kind, c, r, spec)
    local id = Engine.Apply(s, { kind = "place", tower = kind, c = c, r = r })[1].id
    Engine.Apply(s, { kind = "upgrade", id = id })
    Engine.Apply(s, { kind = "upgrade", id = id })
    if spec then return id, Engine.Apply(s, { kind = "upgrade", id = id, spec = spec })[1] end
    return id
end

-- Every tower, both specializations researched.
local ALL = { towers = {}, specs = {} }
local function All(ns)
    for i, kind in ipairs(ns.Content.towerOrder) do ALL.towers[i], ALL.specs[kind] = kind, 2 end
    return ALL
end

-- Ticks until `kind` events appear (or `limit` ticks); returns those events.
local function until_(Engine, s, kind, limit)
    for _ = 1, limit or 300 do
        local found = {}
        for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == kind then found[#found + 1] = e end end
        if #found > 0 then return found end
    end
    return {}
end

tests["specializations need research, and each one works"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 3, 1, 1000), G("vulture", 1, 1, 1000) } }, { gold = 5000 })
    -- without research: refused; with it: rank 4 or 5
    All(ns)
    local s = Engine.New(level)
    local _, e = tower(Engine, s, "archer", 2, 3, 1)
    T.eq(e.reason, "research", "not researched")
    s = Engine.New(level, ALL)
    _, e = tower(Engine, s, "ranger", 2, 3, 2)
    T.eq(e.kind .. e.rank, "upgraded5", "Volley is rank 5")
    T.eq(Engine.Apply(s, { kind = "upgrade", id = e.id })[1].reason, "max", "nothing after a specialization")
    -- Volley: three targets at once
    s = Engine.New(level, ALL)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 3)
    tower(Engine, s, "ranger", 2, 3, 2)
    Engine.Tick(s)
    T.eq(#s.shots, 3, "three shots in one volley")
    -- Blizzard: a pulse that slows ground and air
    s = Engine.New(level, ALL)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 3)
    tower(Engine, s, "frost", 1, 1, 2)
    T.ok(#until_(Engine, s, "pulse") > 0, "Blizzard pulses")
    for _, c in ipairs(s.creeps) do T.eq(c.slow, 55, c.kind .. " slowed") end
    -- Shadow Word: damage over time after the priest is gone
    s = Engine.New(level, ALL)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 3)
    local priest = tower(Engine, s, "priest", 2, 3, 2)
    until_(Engine, s, "pulse")
    local boar = s.creeps[1]
    T.eq(boar.dot, 8, "cursed")
    Engine.Apply(s, { kind = "sell", id = priest })
    local hp = boar.hp
    ticks(Engine, s, 30)
    T.eq(hp - boar.hp, 8, "8 damage in a second")
    -- Gnomish Freeze Ray: the bomb's target is frozen
    s = Engine.New(level, ALL)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 3)
    tower(Engine, s, "engineer", 2, 3, 2)
    T.ok(#until_(Engine, s, "blast") > 0, "a bomb landed")
    local frozen = 0
    for _, c in ipairs(s.creeps) do if c.stunEnd >= s.tick then frozen = frozen + 1 end end
    T.eq(frozen, 1, "one creep frozen")
    -- Windfury: a neighbour fires 25% faster
    s = Engine.New(level, ALL)
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 3)
    tower(Engine, s, "shaman", 3, 3, 2)
    local archer = Engine.Apply(s, { kind = "place", tower = "archer", c = 4, r = 3 })[1].id
    for _ = 1, 60 do
        local fired
        for _, ev in ipairs(Engine.Tick(s, {})) do if ev.kind == "fire" and ev.id == archer then fired = true end end
        if fired then break end
    end
    for _, t in ipairs(s.towers) do
        if t.id == archer then
            T.eq(t.cd, math.floor(ns.Content.towers.archer.ranks[1].cd * 75 / 100), "archer cooldown shortened")
        end
    end
end

tests["chance-based specializations follow the seed: crits and misfires"] = function(T)
    local ns, Engine = load(T, true)
    All(ns)
    local level = line(ns, { { G("boar", 60, 15, 3000) } }, { gold = 5000, lives = 1000 })
    local function count(kind, spec, event)
        local s = Engine.New(level, ALL, 99)
        Engine.Apply(s, { kind = "wave" })
        tower(Engine, s, kind, 3, 3, spec)
        local n, shots = 0, 0
        for _ = 1, 2000 do
            for _, e in ipairs(Engine.Tick(s, {})) do
                if e.kind == event then n = n + 1 end
                if e.kind == "fire" then shots = shots + 1 end
            end
        end
        return n, shots
    end
    local crits, shots = count("archer", 1, "crit")
    T.ok(crits > 0 and crits < shots, "some crits: " .. crits .. " of " .. shots)
    T.eq(count("archer", 1, "crit"), crits, "the same seed gives the same crits")
    local misfires, bombs = count("catapult", 2, "misfire") -- the Goblin Sapper
    T.ok(misfires > 0 and misfires < bombs, "some misfires: " .. misfires .. " of " .. bombs)
end

tests["the shaman's lightning jumps, weaker each time"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 4, 2, 1000) } }, { gold = 5000 })
    local s = Engine.New(level, All(ns))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 8)
    Engine.Apply(s, { kind = "place", tower = "shaman", c = 2, r = 3 })
    local zaps = until_(Engine, s, "zap")
    T.eq(#zaps, ns.Content.towers.shaman.ranks[1].chain, "two jumps at rank 1")
    local full = s.creeps[1].maxHp
    local hurt = {}
    for _, c in ipairs(s.creeps) do if c.hp < full then hurt[#hurt + 1] = full - c.hp end end
    table.sort(hurt)
    T.eq(#hurt, 3, "three creeps hit")
    T.ok(hurt[1] < hurt[3], "the last jump hurts least")
end

tests["a loadout's extra lives and research bonuses"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, nil, { lives = 5 })
    local s = Engine.New(level, { towers = { "archer" }, lives = 2,
        bonus = { archer = { dmgPct = 120, rangePct = 110, costPct = 90 } } })
    T.eq(s.lives .. "/" .. s.maxLives, "7/7", "lives")
    local base = ns.Content.towers.archer.ranks[1]
    local S = Engine.Stats(s, "archer", 1)
    T.eq(S.dmg .. "," .. S.range .. "," .. S.cost, math.floor(base.dmg * 1.2) .. "," .. math.floor(base.range * 1.1)
        .. "," .. math.floor(base.cost * 0.9), "bonuses")
end

tests["creep health: the level's, the wave's and the group's own, multiplied, then the difficulty's"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 1, 1, 50) }, { G("boar", 1, 1) } })
    T.eq(Engine.GroupHpPct(level, 1, level.waves[1][1], 100), 50, "a group's own, by default the only layer")
    level.waves.hp, level.waves[1].hp = 120, 150
    T.eq(Engine.GroupHpPct(level, 1, level.waves[1][1], 100), 90, "50% x 150% x 120% = 90%")
    T.eq(Engine.GroupHpPct(level, 2, level.waves[2][1], 130), 156, "another wave: 120% x Heroic's 130%")
    local s = Engine.New(level, { towers = {}, hpPct = 100 })
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 2)
    T.eq(s.creeps[1].maxHp, math.floor(ns.Content.creeps.boar.hp * 90 / 100), "the creep spawns that tough")
    T.eq(#Engine.ValidateLevel(level), 0, "whole percents are fine")
    level.waves[2].hp = 0
    level.waves.hp = 99.5
    T.eq(#Engine.ValidateLevel(level), 2, "a wave's 0 and a level's 99.5 are not")
end

tests["a run saved by 0.1.0 (creeps without scale or cd) still resumes"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New("horde-2")
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 40)
    local snap = Engine.Snapshot(s)
    for _, c in ipairs(snap.creeps) do c.scale, c.cd = nil, nil end
    local back = assert(Engine.Restore(snap))
    local level = ns.Levels.byId["horde-2"]
    local C, pct = ns.Content.creeps[back.creeps[1].kind], Engine.GroupHpPct(level, 1, level.waves[1][1], 100)
    T.eq(back.creeps[1].scale, math.floor(math.max(1, math.floor(C.hp * pct / 100)) * 100 / C.hp),
        "scale rebuilt from its health (to the percent its whole hit points allow)")
    ticks(Engine, back, 100)
    T.ok(back.tick == 140, "plays on")
end

tests["a snapshot without 0.4's newer fields (heroes, curses, plague, boss timers) still resumes"] = function(T)
    local _, Engine = load(T)
    local s = Engine.New("horde-2", nil, 3)
    s.wave = #s._level.waves - 1
    Engine.Apply(s, { kind = "wave" }) -- the Warlord's wave: a boss with an ability timer
    Engine.Apply(s, { kind = "place", tower = "earthshaker", c = 3, r = 4 })
    s.lives = 999
    for _ = 1, 400 do
        Engine.Tick(s)
        local boss = false
        for _, c in ipairs(s.creeps) do if c.kind == "warlord" then boss = true end end
        if boss then break end
    end
    local snap = Engine.Snapshot(s)
    for _, c in ipairs(snap.creeps) do
        for _, k in ipairs({ "acd", "vuln", "vulnEnd", "bane", "baneEnd", "silenceEnd", "raged", "spread" }) do
            c[k] = nil
        end
    end
    for _, t in ipairs(snap.towers) do t.stunEnd, t.regrown = nil, nil end
    snap.abilityCd, snap.lust, snap.lustEnd, snap.wardEnd = nil, nil, nil, nil
    local back = assert(Engine.Restore(snap))
    local tick = back.tick
    for _ = 1, 400 do Engine.Tick(back) end
    T.eq(back.tick, tick + 400, "plays on, the boss's stomp timer and all")
end

tests["heroic loadout: tougher creeps, less gold, and only allowed towers"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 1) } }, { gold = 100 })
    local state = Engine.New(level, { towers = { "archer" }, hpPct = 140, goldPct = 80 })
    T.eq(state.gold, 80, "gold")
    T.eq(Engine.Apply(state, { kind = "place", tower = "frost", c = 1, r = 1 })[1].reason, "locked", "not in loadout")
    Engine.Apply(state, { kind = "wave" })
    Engine.Tick(state)
    T.eq(state.creeps[1].hp, math.floor(ns.Content.creeps.boar.hp * 1.4), "hp")
end

tests["frame rate does not change the outcome, and a long hitch is clamped"] = function(T)
    local _, Engine = load(T)
    local function run(frames, dt)
        local state, clock = Engine.New("horde-2", nil, 7), { acc = 0 }
        Engine.Apply(state, { kind = "place", tower = "archer", c = 3, r = 3 })
        Engine.Apply(state, { kind = "wave" })
        for i = 1, frames do Engine.Advance(state, clock, dt(i)) end
        return state.tick, T.dump(Engine.Snapshot(state))
    end
    -- Exact binary fractions, so both totals match, ending mid-step (see the toy's version of this test).
    local ticksA, a = run(1281, function() return 1 / 64 end)
    local pattern = { 3 / 64, 1 / 64, 2 / 64, 2 / 64 }
    local ticksB, b = run(641, function(i) return i <= 640 and pattern[(i - 1) % 4 + 1] or 1 / 64 end)
    T.eq(ticksA, ticksB, "tick count")
    T.eq(a, b, "state")
    local state, clock = Engine.New("horde-2"), { acc = 0 }
    T.ok(Engine.Advance(state, clock, 5.0) <= math.ceil(Engine.MAX_FRAME / Engine.STEP), "5 s hitch clamped")
    T.eq(Engine.Advance(state, clock, -1), 0, "negative elapsed ignored")
    T.eq(Engine.Advance(state, clock, "junk"), 0, "non-number elapsed ignored")
    local fast = Engine.New("horde-2")
    T.eq(Engine.Advance(fast, { acc = 0 }, 0.2, 2), 12, "2x speed runs twice the steps")
end

-- The damage the first landed shot of `kind` does to a lone creep, set up by `setup(state)` if given.
local function FirstHit(ns, Engine, level, kinds, kind, setup)
    local s = Engine.New(level, { towers = kinds })
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 1)
    if setup then setup(s) end
    Engine.Apply(s, { kind = "place", tower = kind, c = 2, r = 3 })
    until_(Engine, s, "hit")
    local c = s.creeps[1]
    return c.maxHp - c.hp, s
end

tests["stealthed creeps can't be hit until a revealing tower is near them"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("footpad", 1, 1, 1000) } })
    local kinds = { "archer", "paladin" }
    local s = Engine.New(level, { towers = kinds })
    Engine.Apply(s, { kind = "place", tower = "archer", c = 3, r = 3 })
    Engine.Apply(s, { kind = "wave" })
    local fired = false
    for _ = 1, 90 do for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == "fire" then fired = true end end end
    T.ok(not fired, "the archer can't see the footpad")
    T.eq(s.creeps[1].hp, s.creeps[1].maxHp, "untouched")
    T.ok(not Engine.Seen(s.creeps[1]), "unseen")
    s = Engine.New(level, { towers = kinds })
    Engine.Apply(s, { kind = "place", tower = "archer", c = 3, r = 3 })
    Engine.Apply(s, { kind = "place", tower = "paladin", c = 4, r = 1 })
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 90)
    T.ok(Engine.Seen(s.creeps[1]), "the paladin's light reveals it")
    T.ok(s.creeps[1].hp < s.creeps[1].maxHp, "and it gets hit")
end

tests["curses: a cursed creep takes more damage from everything"] = function(T)
    local ns, Engine = load(T)
    local level = line(ns, { { G("boar", 1, 1, 1000) } })
    T.eq(FirstHit(ns, Engine, level, { "archer" }, "archer"), 11, "plain")
    T.eq(FirstHit(ns, Engine, level, { "archer" }, "archer", function(s)
        s.creeps[1].vuln, s.creeps[1].vulnEnd = 50, 10000
    end), 16, "50% more, rounded down")
    local _, s = FirstHit(ns, Engine, level, { "banshee" }, "banshee")
    T.eq(s.creeps[1].vuln, ns.Content.towers.banshee.ranks[1].vuln.pct, "the banshee curses what it hits")
    T.ok(s.creeps[1].vulnEnd > s.tick, "for a while")
end

tests["damage over time: poisoned shots, and a plague that jumps when its host dies"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 1, 1, 1000) } }, { gold = 5000 }), All(ns))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 1)
    tower(Engine, s, "ranger", 2, 3, 1) -- Black Arrow
    until_(Engine, s, "hit")
    T.eq(s.creeps[1].dot, 10, "a black arrow poisons")
    local p = Engine.New(line(ns, { { G("boar", 2, 10) } }))
    Engine.Apply(p, { kind = "wave" })
    ticks(Engine, p, 12)
    local host, behind = p.creeps[1], p.creeps[2]
    host.dot, host.dotEnd, host.spread, host.hp = 9, p.tick + 100, 1, 1
    T.eq(#until_(Engine, p, "spread", 40), 1, "the plague jumped")
    T.eq(behind.dot .. "/" .. behind.spread, "9/1", "to the next boar, and it can jump again")
    T.ok(behind.dotEnd > p.tick, "with the time it had left")
end

tests["corpse explosion: a creep the necromancer marked bursts when it dies"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 2, 6, 300) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 8)
    local marked, other = s.creeps[1], s.creeps[2]
    marked.bane, marked.baneEnd, marked.hp = 30, s.tick + 100, 1
    marked.dot, marked.dotEnd = 1, s.tick + 100 -- the plague finishes it at the next whole second
    T.eq(#until_(Engine, s, "burst", 40), 1, "one burst")
    T.eq(other.maxHp - other.hp, 30, "the creep beside it took 30")
end

tests["income: one-coin bounties still add up, exactly, and a save keeps the purse"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("imp", 10, 4) } }, { gold = 500 }))
    Engine.Apply(s, { kind = "place", tower = "headhunter", c = 1, r = 1 })
    Engine.Apply(s, { kind = "place", tower = "headhunter", c = 2, r = 3 })
    local gold, paid, restored = s.gold, 0, false
    Engine.Apply(s, { kind = "wave" })
    for _ = 1, 900 do
        for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == "killed" then paid = paid + e.gold end end
        if s.stats.kills >= 3 and not restored then
            restored = true
            s = assert(Engine.Restore(Engine.Snapshot(s))) -- a /reload partway: the purse is saved
        end
    end
    T.ok(restored and s.stats.kills >= 5, "imps killed on both sides of the reload (" .. s.stats.kills .. ")")
    T.eq(paid, math.floor(s.stats.kills * ns.Content.creeps.imp.bounty * Engine.INCOME / 100),
        "one-coin bounties pay Engine.INCOME percent over time (" .. paid .. " for " .. s.stats.kills .. ")")
    T.eq(s.gold - gold, paid, "and the gold says so")
end

tests["War Stomp stuns every ground creep near the earthshaker"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 2, 2, 1000) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 30)
    Engine.Apply(s, { kind = "place", tower = "earthshaker", c = 1, r = 3 })
    T.ok(#until_(Engine, s, "pulse") > 0, "stomped")
    for _, c in ipairs(s.creeps) do T.ok(c.stunEnd >= s.tick, "stunned") end
    local boar = s.creeps[1]
    local d = boar.d
    ticks(Engine, s, 1)
    T.eq(boar.d, d, "a stunned creep doesn't move")
end

tests["after a stun the creep is steady for a second: a second earthshaker can't hold it down"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 1, 1, 10000) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 30)
    Engine.Apply(s, { kind = "place", tower = "earthshaker", c = 1, r = 3 })
    until_(Engine, s, "pulse")
    local boar = s.creeps[1]
    local stunEnd = boar.stunEnd
    T.eq(boar.steadyEnd, stunEnd + Engine.STEADY, "stunned, then steady")
    Engine.Apply(s, { kind = "place", tower = "earthshaker", c = 2, r = 1 })
    local hp = boar.hp
    T.ok(#until_(Engine, s, "pulse", 2) > 0, "the second earthshaker stomps at once")
    T.ok(boar.hp < hp, "it hurts the boar")
    T.eq(boar.stunEnd, stunEnd, "but the boar shrugs off the stun")
    local stunnedAt
    for _ = 1, 200 do
        Engine.Tick(s)
        if boar.stunEnd ~= stunEnd then stunnedAt = s.tick; break end
    end
    T.ok(stunnedAt and stunnedAt > stunEnd + Engine.STEADY, "the next stomp after the steady second stuns again")
end

tests["a stun leaves a slow running underneath"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 1, 1, 10000) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 30)
    local boar = s.creeps[1]
    Engine.Apply(s, { kind = "place", tower = "witchdoctor", c = 1, r = 1 })
    until_(Engine, s, "hit")
    local slowEnd = boar.slowEnd
    T.eq(boar.slow, 35, "slowed by the witch doctor")
    Engine.Apply(s, { kind = "place", tower = "earthshaker", c = 1, r = 3 })
    until_(Engine, s, "pulse")
    T.ok(boar.stunEnd >= s.tick, "then stunned")
    T.ok(boar.slow == 35 and boar.slowEnd >= slowEnd, "and still slowed")
    ticks(Engine, s, boar.stunEnd - s.tick + 1)
    local d = boar.d
    ticks(Engine, s, 1)
    T.eq(boar.d - d, math.floor(33 * 65 / 100), "it walks on at the slowed speed")
end

tests["a tower that stuns aims at a creep it can still stun"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 2, 20, 10000) } }, { gold = 5000 }), All(ns))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 40)
    local lead, behind = s.creeps[1], s.creeps[2]
    lead.steadyEnd = s.tick + 300 -- as if it had just shaken off a stun
    tower(Engine, s, "witchdoctor", 2, 3, 1) -- Hex
    until_(Engine, s, "hit")
    T.ok(behind.stunEnd >= s.tick, "it hexed the boar behind")
    T.ok(lead.stunEnd < s.tick, "not the steady one in front")
    lead.steadyEnd = 0
    behind.steadyEnd = s.tick + 300
    until_(Engine, s, "hit")
    T.ok(lead.stunEnd >= s.tick, "and when the one behind is steady, the one in front")
end

tests["auras and bonuses: a paladin's might, holy damage to undead, double damage to flyers"] = function(T)
    local ns, Engine = load(T)
    local flyer = line(ns, { { G("vulture", 1, 1, 1000) } }) -- only the rifleman can hit it, not the paladin
    T.eq(FirstHit(ns, Engine, flyer, { "rifleman", "paladin" }, "rifleman"), 13, "plain")
    T.eq(FirstHit(ns, Engine, flyer, { "rifleman", "paladin" }, "rifleman", function(s)
        Engine.Apply(s, { kind = "place", tower = "paladin", c = 3, r = 3 })
    end), 14, "10% harder next to a paladin")
    local s = Engine.New(line(ns, { { G("skeleton", 1, 1, 1000) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 10)
    Engine.Apply(s, { kind = "place", tower = "priest", c = 1, r = 3 })
    until_(Engine, s, "pulse")
    T.eq(s.creeps[1].maxHp - s.creeps[1].hp, math.floor(9 * 150 / 100), "holy: half again against undead")
    local g = Engine.New(line(ns, { { G("vulture", 1, 1, 1000) } }, { gold = 5000 }), All(ns))
    Engine.Apply(g, { kind = "wave" })
    ticks(Engine, g, 1)
    tower(Engine, g, "rifleman", 2, 3, 2) -- Gyrocopter
    until_(Engine, g, "hit")
    T.eq(g.creeps[1].maxHp - g.creeps[1].hp, 2 * Engine.Stats(g, "rifleman", 5).dmg, "double against flyers")
end

tests["Rejuvenation restores a life when a wave is cleared, up to three a level"] = function(T)
    local ns, Engine = load(T)
    local waves = {}
    for i = 1, 5 do waves[i] = { G("boar", 1) } end
    local s = Engine.New(line(ns, waves, { gold = 5000 }), All(ns))
    tower(Engine, s, "moonwell", 2, 3, 2)
    s.lives = 1
    local regrown = 0
    for _ = 1, 5 do
        Engine.Apply(s, { kind = "wave" })
        regrown = regrown + #until_(Engine, s, "regrow", 400)
    end
    T.eq(regrown, 3, "three times")
    T.eq(s.lives, 4, "three lives back")
end

tests["heroes: free, one per level, never sold, and the ability waits for its cooldown"] = function(T)
    local ns, Engine = load(T)
    local A = ns.Content.towers.thrall.ability
    local s = Engine.New(line(ns, { { G("boar", 10, 10, 1000) } }), { towers = { "headhunter" }, hero = "thrall" })
    local gold = s.gold
    T.eq(Engine.Apply(s, { kind = "ability" })[1].reason, "nohero", "no hero yet")
    local placed = Engine.Apply(s, { kind = "place", tower = "thrall", c = 2, r = 3 })[1]
    T.ok(placed.kind == "placed" and placed.hero, "placed as the hero")
    T.eq(s.gold, gold, "free")
    T.eq(Engine.Apply(s, { kind = "place", tower = "thrall", c = 4, r = 3 })[1].reason, "hero", "only one")
    T.eq(Engine.Apply(s, { kind = "sell", id = placed.id })[1].reason, "hero", "never sold")
    T.eq(Engine.Apply(s, { kind = "upgrade", id = placed.id })[1].reason, "max", "no ranks to buy")
    T.eq(Engine.Apply(s, { kind = "ability" })[1].reason, "cooldown", "not ready yet")
    T.eq(s.abilityCd, A.first, "ready after its first wait")
    ticks(Engine, s, A.first)
    T.eq(Engine.Apply(s, { kind = "ability" })[1].kind, "ability", "cast")
    T.eq(s.lustEnd .. "/" .. s.abilityCd, (s.tick + A.ticks) .. "/" .. A.cd, "Bloodlust runs, the cooldown starts")
    local hh = Engine.Apply(s, { kind = "place", tower = "headhunter", c = 7, r = 3 })[1].id -- beyond Thrall's aura
    Engine.Apply(s, { kind = "wave" })
    for _ = 1, 200 do
        local fired
        for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == "fire" and e.id == hh then fired = true end end
        if fired then break end
    end
    for _, t in ipairs(s.towers) do
        if t.id == hh then T.eq(t.cd, math.floor(17 * 50 / 100), "Bloodlust: 50% faster") end
    end
    local other = Engine.New(line(ns), { towers = { "headhunter" } })
    T.eq(Engine.Apply(other, { kind = "place", tower = "thrall", c = 2, r = 3 })[1].reason, "locked",
        "no hero without one in the loadout")
end

tests["hero abilities: Divine Shield, Starfall and Wailing Arrow"] = function(T)
    local ns, Engine = load(T)
    local function Ready(hero, waves)
        local s = Engine.New(line(ns, waves or { { G("scorpid", 3, 5, 1000) } }), { towers = {}, hero = hero })
        Engine.Apply(s, { kind = "place", tower = hero, c = 5, r = 3 })
        Engine.Apply(s, { kind = "wave" })
        ticks(Engine, s, 11)
        s.abilityCd = 0
        return s
    end
    local s = Ready("bolvar")
    Engine.Apply(s, { kind = "ability" })
    for _, c in ipairs(s.creeps) do c.d = s._geo.paths[1].len - 1 end
    local leaked = until_(Engine, s, "leaked", 5)
    T.ok(#leaked == 3 and leaked[1].warded, "three warded leaks")
    T.eq(s.lives, s.maxLives, "Divine Shield: no lives lost")
    s = Ready("tyrande")
    for _, c in ipairs(s.creeps) do c.d = 4500 end
    Engine.Apply(s, { kind = "ability" })
    local falls = 0
    for _ = 1, 160 do
        for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == "starfall" then falls = falls + 1 end end
    end
    T.eq(falls, 5, "Starfall: once a second for 5 seconds")
    T.eq(s.fall, nil, "and then it's over")
    s = Ready("sylvanas", { { G("ghoul", 3, 5, 1000) } })
    for _, c in ipairs(s.creeps) do c.d = 4500; c.hp = c.hp - 100 end
    Engine.Tick(s) -- they're beside her now
    s.abilityCd = 0
    local before = s.creeps[1].hp
    local cast = Engine.Apply(s, { kind = "ability" })
    T.eq(cast[1].ability, "wail", "Wailing Arrow")
    local c = s.creeps[1]
    T.eq(before - c.hp, ns.Content.towers.sylvanas.ability.dmg, "hurt")
    T.ok(c.stunEnd > s.tick and c.silenceEnd > s.tick, "frozen and silenced")
    local hp = c.hp
    ticks(Engine, s, 60)
    T.ok(c.hp <= hp, "a silenced ghoul doesn't regenerate")
end

tests["bosses: War Stomp stuns towers, summons call help, blink jumps ahead, enrage speeds up"] = function(T)
    local ns, Engine = load(T)
    local function Boss(kind)
        local s = Engine.New(line(ns, { { G(kind, 1) } }, { lives = 50 }))
        Engine.Apply(s, { kind = "wave" })
        ticks(Engine, s, 1)
        return s, s.creeps[1]
    end
    local s, boss = Boss("warlord")
    local archer = Engine.Apply(s, { kind = "place", tower = "archer", c = 1, r = 3 })[1].id
    boss.acd = 1
    T.eq(#until_(Engine, s, "stomp", 3), 1, "War Stomp")
    local stunned
    for _, t in ipairs(s.towers) do if t.id == archer then stunned = t end end
    T.ok(stunned.stunEnd > s.tick, "the archer is stunned")
    local fired = false
    for _ = 1, stunned.stunEnd - s.tick - 1 do
        for _, e in ipairs(Engine.Tick(s, {})) do if e.kind == "fire" and e.id == archer then fired = true end end
    end
    T.ok(not fired, "and holds its fire")
    s, boss = Boss("gazzuz")
    boss.acd = 1
    T.eq(#until_(Engine, s, "summon", 3), 1, "a summon")
    T.eq(#s.creeps, 1 + ns.Content.creeps.gazzuz.ability.count, "imps join him")
    T.eq(s.active[1].alive, #s.creeps, "and count in the wave")
    s, boss = Boss("arugal")
    boss.acd = 1
    local d = boss.d
    T.eq(#until_(Engine, s, "blink", 3), 1, "a blink")
    T.ok(boss.d >= d + ns.Content.creeps.arugal.ability.distance, "three cells ahead")
    s, boss = Boss("hogger")
    d = boss.d
    Engine.Tick(s)
    local step = boss.d - d
    boss.hp = math.floor(boss.maxHp / 3)
    T.eq(#until_(Engine, s, "enraged", 2), 1, "enraged")
    d = boss.d
    Engine.Tick(s)
    T.eq(boss.d - d, math.floor(step * ns.Content.creeps.hogger.enrage.pct / 100), "faster")
end

tests["stealth: no hero sees it; the revealing towers do, and three towers' first specializations"] = function(T)
    local ns = load(T)
    local seen = {}
    for kind, def in pairs(ns.Content.towers) do
        for rank, r in ipairs(def.ranks) do
            if r.reveal then
                T.ok(not def.hero, kind .. ": heroes don't reveal (Bruce: \"so ppl have to get the druid for those\")")
                seen[#seen + 1] = kind .. rank
            end
        end
    end
    table.sort(seen)
    T.eq(table.concat(seen, " "), "apothecary4 banshee1 banshee2 banshee3 banshee4 banshee5 moonwell4 paladin1 "
        .. "paladin2 paladin3 paladin4 paladin5 ranger4 talon1 talon2 talon3 talon4 talon5",
        "the Paladin, Banshee and Druid of the Talon at every rank; Moonfire, Black Arrow and Blight")
end

tests["every tower, hero and creep is complete, and every campaign has its five roles and a hero"] = function(T)
    local ns = load(T)
    local Content = ns.Content
    for kind, def in pairs(Content.towers) do
        T.ok(def.name and def.icon and def.blurb and def.role and def.damage, kind .. ": basics")
        T.ok(def.campaign, kind .. ": in a campaign")
        T.eq(#def.ranks, def.hero and 1 or 5, kind .. ": ranks")
        for rank, r in ipairs(def.ranks) do
            T.ok(r.cost and r.dmg and r.range and r.cd, kind .. " rank " .. rank .. ": numbers")
            if not r.pulse then T.ok(r.shot, kind .. " rank " .. rank .. ": a shot speed") end
            if r.chain then T.ok(r.jump and r.falloff, kind .. " rank " .. rank .. ": chain reach") end
            if r.haste or r.might then T.ok(r.aura, kind .. " rank " .. rank .. ": aura reach") end
        end
        if def.hero then T.ok(def.ability and def.ability.cd and def.ability.name, kind .. ": ability") end
    end
    for _, camp in ipairs(Content.campaigns) do
        local roles = {}
        for _, kind in ipairs(camp.towers) do roles[#roles + 1] = Content.towers[kind].role end
        table.sort(roles)
        local want = {}
        for i, role in ipairs(Content.ROLES) do want[i] = role end
        table.sort(want)
        T.eq(table.concat(roles, ","), table.concat(want, ","), camp.id .. ": one tower for each of the five roles")
        T.ok(Content.towers[camp.hero.kind].hero, camp.id .. ": a hero")
        T.eq(camp.joins[camp.towers[1]], 1, camp.id .. ": starts with its first tower")
        T.ok(#camp.levels >= 5 and #camp.levels <= 12, camp.id .. ": 5 to 12 levels")
    end
    for kind, C in pairs(Content.creeps) do
        T.ok(C.name and C.icon and C.hp and C.speed and C.bounty, kind .. ": basics")
        if C.ability then
            T.ok(C.ability.every, kind .. ": ability timer")
            if C.ability.kind == "summon" then T.ok(Content.creeps[C.ability.creep], kind .. ": summons a creep") end
        end
    end
end

tests["stale runs refused, no corpses after a wail, stealth hidden on restore, no regrow at 0 lives"] = function(T)
    local ns, Engine = load(T)
    -- a saved run whose tower or wave no longer exists is refused instead of erroring every frame
    local s = Engine.New("horde-2")
    Engine.Apply(s, { kind = "place", tower = "headhunter", c = 2, r = 1 })
    local snap = Engine.Snapshot(s)
    snap.towers[1].kind = "gone"
    T.eq(Engine.Restore(snap), nil, "an unknown tower kind")
    snap = Engine.Snapshot(s)
    snap.active = { { wave = 99, t = 0, pending = 0, alive = 0 } }
    T.eq(Engine.Restore(snap), nil, "a wave the level doesn't have")
    -- Wailing Arrow settles its kills at once: no corpse waits in the list for the next tick
    local w = Engine.New(line(ns, { { G("boar", 4, 2) } }), { towers = {}, hero = "sylvanas" })
    Engine.Apply(w, { kind = "place", tower = "sylvanas", c = 2, r = 3 })
    Engine.Apply(w, { kind = "wave" })
    ticks(Engine, w, 8)
    w.abilityCd = 0
    Engine.Apply(w, { kind = "ability" })
    for _, c in ipairs(w.creeps) do T.ok(not c.dead, "no dead creep left in the list") end
    -- stealthed creeps are hidden as soon as a run is restored, before any tick
    local h = Engine.New(line(ns, { { G("footpad", 1, 1, 1000) } }))
    Engine.Apply(h, { kind = "wave" })
    ticks(Engine, h, 30)
    local back = assert(Engine.Restore(Engine.Snapshot(h)))
    T.ok(not Engine.Seen(back.creeps[1]), "still unseen after a restore")
    -- a regrowing tower can't undo a defeat
    local d = Engine.New(line(ns, { { G("boar", 1) } }, { gold = 5000 }), All(ns))
    tower(Engine, d, "moonwell", 10, 1, 2) -- Rejuvenation, far from the road's start
    Engine.Apply(d, { kind = "wave" })
    d.lives = 1
    ticks(Engine, d, 2)
    d.creeps[1].d = d._geo.paths[1].len - 1
    ticks(Engine, d, 3)
    T.eq(d.over, "lost", "the last life is gone, and stays gone")
end

tests["corpse explosions set each other off in the same tick"] = function(T)
    local ns, Engine = load(T)
    local s = Engine.New(line(ns, { { G("boar", 3, 4, 300) } }))
    Engine.Apply(s, { kind = "wave" })
    ticks(Engine, s, 10)
    local a, b = s.creeps[1], s.creeps[2]
    for _, c in ipairs({ a, b }) do c.bane, c.baneEnd = 200, s.tick + 100 end
    a.hp, b.hp = 1, 50
    a.dot, a.dotEnd = 1, s.tick + 100
    local bursts = until_(Engine, s, "burst", 40)
    T.eq(#bursts, 2, "the second corpse goes off in the same tick as the first")
end

tests["restore refuses other schemas, unknown levels and broken data"] = function(T)
    local _, Engine = load(T)
    local snap = Engine.Snapshot(Engine.New("horde-2"))
    local function refused(mutate, word)
        local copy = Engine.Snapshot(Engine.Restore(snap))
        mutate(copy)
        local state, why = Engine.Restore(copy)
        T.eq(state, nil, word)
        T.ok(tostring(why):find(word, 1, true), word .. ": " .. tostring(why))
    end
    refused(function(s) s.schema = Engine.SCHEMA + 1 end, "schema")
    refused(function(s) s.schema = 1 end, "schema") -- the starter toy's snapshots
    refused(function(s) s.level = "atlantis" end, "level")
    refused(function(s) s.loadout = nil end, "corrupt")
    T.eq(Engine.Restore(nil), nil, "missing")
end

return tests
