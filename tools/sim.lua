-- tools/sim.lua - the balance simulator: the real engine plays every level headless with scripted strategies.
-- Usage, from the repository folder:   lua tools/sim.lua              every level, Normal and Heroic
--                                      lua tools/sim.lua horde-3      one level
--                                      lua tools/sim.lua horde        one campaign
--                                      lua tools/sim.lua --headroom [horde]   how much tougher the creeps could be
--                                      lua tools/sim.lua --waves [horde]      the same for each wave on its own
--                                      lua tools/sim.lua --shape [horde]      each wave into its band (M.Band)
--                                      lua tools/sim.lua --keep before.txt [horde]   each wave kept as it was
--                                      lua tools/sim.lua --tune [horde]       new waves for M.FLOOR (minutes)
--                                      lua tools/sim.lua --scale 90 [horde]   every wave's health x 90%
-- (--tune, --shape, --keep and --scale print the new waves; add --write to put them in the campaign files.)
-- Each level is played with the towers (and hero) its campaign has when you first reach it, and no research unless
-- the run is given some (opts.armory; M.RESEARCH is what the balance assumes at each level). The checks a level must
-- pass (tests/test_sim.lua runs them too), on Normal: "greedy" (a sensible newcomer's build) wins with the research
-- M.RESEARCH assumes there, and still wins with the creeps at M.Floor percent health (a newcomer's margin); "sharp",
-- a stand-in for a good player (it tries each purchase on a copy of the game and buys what works; slow), wins with no
-- research at all; "none" (no towers) and "two scouts" (two of the campaign's first tower) lose.
local M = {}

local root = ((arg and arg[0] or ""):match("^(.-)[\\/]?tools[\\/]sim%.lua$") or ".")
if root == "" then root = "." end

-- The pure game files, in TOC order: everything from the top of the TOC down to Meta.lua.
function M.Files(base)
    local files = {}
    for line in io.lines((base or root) .. "/ForeverTD/ForeverTD.toc") do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then
            files[#files + 1] = line:gsub("\\", "/")
            if line == "Meta.lua" then break end
        end
    end
    return files
end

-- Loads the pure game files in TOC order into a fresh namespace.
function M.Load(base)
    local ns = {}
    for _, file in ipairs(M.Files(base)) do
        assert(loadfile((base or root) .. "/ForeverTD/" .. file))("ForeverTD", ns)
    end
    return ns
end

-- Buildable cells ranked for a tower kind: how much of the paths it can reach from there.
local function RankCells(ns, state, kind)
    local Engine, Content = ns.Engine, ns.Content
    local level, geo = state._level, state._geo
    local T, S = Content.towers[kind], Engine.Stats(state, kind, 1)
    local cells = {}
    for r = 1, level.rows do
        for c = 1, level.cols do
            if not Engine.IsRoad(state, c, r) and not Engine.IsBlocked(state, c, r) then
                local x, y, score = c * 1000 - 500, r * 1000 - 500, 0
                for _, path in ipairs(geo.paths) do
                    if not path.air or T.air then
                        for d = 0, path.len, 250 do
                            local px, py = Engine.PathXY(path, d)
                            if (px - x) ^ 2 + (py - y) ^ 2 <= S.range ^ 2 then score = score + 1 end
                        end
                    end
                end
                cells[#cells + 1] = { c = c, r = r, score = score }
            end
        end
    end
    table.sort(cells, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.r ~= b.r then return a.r < b.r end
        return a.c < b.c
    end)
    return cells
end

local function Place(ns, state, kind, ranked)
    ranked[kind] = ranked[kind] or RankCells(ns, state, kind)
    for _, cell in ipairs(ranked[kind]) do
        if not ns.Engine.TowerAt(state, cell.c, cell.r) then
            return { kind = "place", tower = kind, c = cell.c, r = cell.r }
        end
    end
end

-- The first wave with stealthed creeps in it (or a boss that calls them), or nil.
local function FirstStealth(ns, level)
    for w, wave in ipairs(level.waves) do
        for _, grp in ipairs(wave) do
            local C = ns.Content.creeps[grp.creep]
            if C.stealth then return w end
            local A = C.ability
            if A and A.kind == "summon" and ns.Content.creeps[A.creep].stealth then return w end
        end
    end
end

-- When a player uses the hero's ability, now that it comes back only every three minutes (0.4.3): for a boss, or
-- when a creep is most of the way down its road (the defence is slipping). Casting it the moment the board is busy
-- wastes it on an easy wave, which is how the bots played while it came back every 45 seconds.
local function Danger(ns, state)
    local paths = state._geo.paths
    for _, c in ipairs(state.creeps) do
        if ns.Content.creeps[c.kind].boss or c.d * 10 >= paths[c.path].len * 6 then return true end
    end
    return false
end

-- A strategy is a function(ns, state) called every tick; it may Apply actions. New(...) builds one per run.
M.strategies = {}

M.strategies["none"] = function()
    return function(ns, state)
        if #state.active == 0 then ns.Engine.Apply(state, { kind = "wave" }) end
    end
end

M.strategies["two scouts"] = function()
    local built, ranked = 0, {}
    return function(ns, state)
        local Engine = ns.Engine
        local kind = state.loadout.towers[1]
        if built < 2 then
            local action = Place(ns, state, kind, ranked)
            if action and Engine.Apply(state, action)[1].kind == "placed" then built = built + 1 end
        end
        if #state.active == 0 then Engine.Apply(state, { kind = "wave" }) end
    end
end

-- A sensible player: a mixed build by role on the best cells, a revealer early when stealthed creeps are coming
-- (its third tower, or its second when they come in the first three waves, as the level's briefing warns),
-- the hero as soon as there is one (and its ability for a boss or when the defence slips: Danger), upgrading every
-- third purchase once four towers stand. opts.favour (a role) makes every other tower it builds that role: another
-- style of play, for M.Styles. opts.resume: it picks up a game in progress, counting what stands as bought (M.Waves).
local CYCLE = { "ranged", "siege", "control", "ranged", "area", "signature", "siege", "ranged", "area", "control" }
M.strategies["greedy"] = function(opts)
    opts = opts or {}
    local cycle = CYCLE
    if opts.favour then
        cycle = {}
        for _, role in ipairs(CYCLE) do cycle[#cycle + 1], cycle[#cycle + 2] = opts.favour, role end
    end
    local ranked, purchases, builds = {}, 0, 0
    local byRole, revealer, stealth, soon
    return function(ns, state)
        local Engine, Content = ns.Engine, ns.Content
        if not byRole then
            byRole = {}
            for _, kind in ipairs(state.loadout.towers) do
                byRole[Content.towers[kind].role] = kind
                if not revealer and Engine.Stats(state, kind, 1).reveal then revealer = kind end
            end
            stealth = FirstStealth(ns, state._level)
            soon = stealth and stealth <= 3
            for _, t in ipairs(opts.resume and state.towers or {}) do
                if not Content.towers[t.kind].hero then
                    builds, purchases = builds + 1, purchases + math.min(t.rank, 4) -- a specialization is a 4th
                end
            end
        end
        local hero = state.loadout.hero
        if hero and not opts.noHero and not state.heroId then
            local action = Place(ns, state, hero, ranked)
            if action then Engine.Apply(state, action) end
        end
        if state.heroId and state.abilityCd == 0 and not opts.noHero and Danger(ns, state) then
            Engine.Apply(state, { kind = "ability" })
        end
        for _ = 1, 4 do -- a few purchases a tick at most
            local action, cost
            if purchases >= 4 and purchases % 3 == 2 then
                local low
                for _, t in ipairs(state.towers) do
                    if Engine.UpgradeCost(state, t) and (not low or t.rank < low.rank) then low = t end
                end
                if low then action, cost = { kind = "upgrade", id = low.id }, Engine.UpgradeCost(state, low) end
                if not low then -- every tower is rank 3: take a specialization the Armory has opened
                    for _, t in ipairs(state.towers) do
                        local i = t.id % 2 + 1
                        local S, open = Engine.Spec(state, t.kind, i)
                        if not open then i, S, open = 1, Engine.Spec(state, t.kind, 1) end
                        if t.rank == 3 and S and open then
                            action, cost = { kind = "upgrade", id = t.id, spec = i }, S.cost
                            break
                        end
                    end
                end
            end
            if not action then
                local kind
                local hasRevealer = false
                for _, t in ipairs(state.towers) do
                    if Engine.Stats(state, t.kind, t.rank).reveal and not Content.towers[t.kind].hero then
                        hasRevealer = true
                    end
                end
                if stealth and revealer and not hasRevealer and builds >= (soon and 1 or 2) then kind = revealer end
                for i = 0, #cycle - 1 do
                    if kind then break end
                    kind = byRole[cycle[(builds + i) % #cycle + 1]]
                end
                kind = kind or state.loadout.towers[1]
                action = Place(ns, state, kind, ranked)
                cost = Engine.Stats(state, kind, 1).cost
            end
            if not action or state.gold < cost then break end
            if Engine.Apply(state, action)[1].kind == "rejected" then break end
            purchases = purchases + 1
            if action.kind == "place" then builds = builds + 1 end
        end
        if #state.active == 0 then Engine.Apply(state, { kind = "wave" }) end
    end
end

-- The hero on its best cell, and its ability when there's danger (as greedy plays it).
local function UseHero(ns, state, ranked, opts)
    local Engine = ns.Engine
    local hero = state.loadout.hero
    if not hero or opts.noHero then return end
    if not state.heroId then
        local action = Place(ns, state, hero, ranked)
        if action then Engine.Apply(state, action) end
    end
    if state.heroId and state.abilityCd == 0 and Danger(ns, state) then Engine.Apply(state, { kind = "ability" }) end
end

-- Plays the next wave out on a copy of the game, after `actions` (nil: as it stands), buying nothing else, with the
-- wave's creeps `margin` percent as tough (to build a little ahead of the waves, as a good player does). The score
-- is lower for a better defence: each life lost counts 1000, then every creep adds how far along its road it got
-- (0..1) before it died. Returns nil if an action is refused.
local function Rollout(ns, state, actions, opts, margin)
    local Engine = ns.Engine
    local copy = assert(Engine.Restore(Engine.Snapshot(state)))
    copy.loadout.hpPct = math.floor(copy.loadout.hpPct * margin / 100)
    for _, action in ipairs(actions or {}) do
        if Engine.Apply(copy, action)[1].kind == "rejected" then return nil end
    end
    local lives, paths, far, ranked = copy.lives, copy._geo.paths, {}, {}
    Engine.Apply(copy, { kind = "wave" })
    local limit = copy.tick + 30 * 60 * 5
    while not copy.over and #copy.active > 0 and copy.tick < limit do
        UseHero(ns, copy, ranked, opts)
        Engine.Tick(copy)
        for _, c in ipairs(copy.creeps) do far[c.id] = c.d / paths[c.path].len end
    end
    local score = 1000 * (lives - copy.lives)
    for _, f in pairs(far) do score = score + f end
    return score
end

-- What a sharp player could buy now with `gold`: each tower on its few best free cells, each upgrade, each opened
-- specialization, and when `fill`, as many of one tower as it can afford (on its best cells); `revealer` may use
-- `extra` gold more. { { key, actions, cost }, ... }
local function Candidates(ns, state, ranked, cellsPerKind, gold, revealer, extra, fill)
    local Engine, Content = ns.Engine, ns.Content
    local list = {}
    for _, kind in ipairs(state.loadout.towers) do
        local cost, budget = Engine.Stats(state, kind, 1).cost, gold + (kind == revealer and extra or 0)
        if not Content.towers[kind].hero and cost <= budget then
            ranked[kind] = ranked[kind] or RankCells(ns, state, kind)
            local cells, most, n = {}, fill and math.floor(budget / cost) or 0, 0
            for _, cell in ipairs(ranked[kind]) do
                if n >= math.max(cellsPerKind, most) then break end
                if not Engine.TowerAt(state, cell.c, cell.r) then
                    n = n + 1
                    local action = { kind = "place", tower = kind, c = cell.c, r = cell.r }
                    if n <= cellsPerKind then
                        list[#list + 1] = { key = kind .. cell.c .. "," .. cell.r, actions = { action }, cost = cost }
                    end
                    if n <= most then cells[n] = action end
                end
            end
            if #cells >= 2 then list[#list + 1] = { key = kind .. "*", actions = cells, cost = cost * #cells } end
        end
    end
    for _, t in ipairs(state.towers) do
        local cost = Engine.UpgradeCost(state, t)
        if cost and cost <= gold then
            list[#list + 1] = { key = "up" .. t.id .. "." .. t.rank, actions = { { kind = "upgrade", id = t.id } },
                cost = cost }
        end
        if t.rank == 3 then
            for i = 1, 2 do
                local S, open = Engine.Spec(state, t.kind, i)
                if S and open and S.cost <= gold then
                    list[#list + 1] = { key = "spec" .. t.id .. "." .. i,
                        actions = { { kind = "upgrade", id = t.id, spec = i } }, cost = S.cost }
                end
            end
        end
    end
    return list
end

-- Whether a wave after `wave` has stealthed creeps in it (or a boss that calls them).
local function StealthAfter(ns, level, wave)
    local creeps = ns.Content.creeps
    for w = wave + 1, #level.waves do
        for _, grp in ipairs(level.waves[w]) do
            local C = creeps[grp.creep]
            local A = C.ability
            if C.stealth or (A and A.kind == "summon" and creeps[A.creep].stealth) then return true end
        end
    end
    return false
end

-- A sharp player, a stand-in for a good human: between waves it tries every purchase it can afford, plays the next
-- wave out on a copy of the game for each, and buys whatever helps most per gold, again and again until nothing it
-- can afford helps. So it finds the junctions, stacks its towers where the roads meet and upgrades the ones that
-- pay. While the next wave would still cost lives it keeps buying even when no single purchase helps on its own
-- (one tower that kills splitting spiders lets more hatchlings through than none), and while stealthed creeps are
-- still to come it keeps the price of a revealing tower in hand until it has one, as a player reading the wave
-- list would. It shops for a wave a little tougher than the one coming (opts.margin, 130%), so it builds ahead.
-- It never calls waves early, never sells, and buys nothing mid-wave. opts.cells: cells tried per tower (2). To save
-- time, within one shopping trip it tries first what helped most the time before, and stops once nothing left could
-- beat the best so far (what a purchase is worth for the same wave only shrinks as the defence grows, more or less).
M.strategies["sharp"] = function(opts)
    opts = opts or {}
    local ranked, cells, margin = {}, opts.cells or 2, opts.margin or 130
    local revealer
    return function(ns, state)
        local Engine = ns.Engine
        UseHero(ns, state, ranked, opts)
        if #state.active > 0 or state.over then return end
        if revealer == nil then
            revealer = false
            for _, kind in ipairs(state.loadout.towers) do
                if not revealer and Engine.Stats(state, kind, 1).reveal then revealer = kind end
            end
        end
        local worth = {}
        while true do
            local reserve = 0
            if revealer and StealthAfter(ns, state._level, state.wave) then
                reserve = Engine.Stats(state, revealer, 1).cost
                for _, t in ipairs(state.towers) do
                    if Engine.Stats(state, t.kind, t.rank).reveal then reserve = 0 end
                end
            end
            local base = Rollout(ns, state, nil, opts, margin)
            local candidates = Candidates(ns, state, ranked, cells, state.gold - reserve, revealer, reserve,
                base >= 1000)
            if #candidates == 0 then break end
            for _, cand in ipairs(candidates) do cand.worth = worth[cand.key] or math.huge end
            table.sort(candidates, function(a, b)
                if a.worth ~= b.worth then return a.worth > b.worth end
                return a.key < b.key
            end)
            local best, bestValue, least, leastScore = nil, 0, nil, nil
            for _, cand in ipairs(candidates) do
                if best and bestValue >= cand.worth then break end
                local score = Rollout(ns, state, cand.actions, opts, margin)
                local value = score and (base - score) / cand.cost or -math.huge
                worth[cand.key] = value
                if value > bestValue then best, bestValue = cand, value end
                if score and (not leastScore or score < leastScore) then least, leastScore = cand, score end
            end
            if not best and base >= 1000 then best = least end
            if not best then break end
            worth[best.key] = nil
            for _, action in ipairs(best.actions) do Engine.Apply(state, action) end
        end
        Engine.Apply(state, { kind = "wave" })
    end
end

-- The profile of a player who has just reached `level`: every earlier level of its campaign won, nothing bought
-- (or Armory tier `armory` everywhere).
function M.Profile(ns, level, armory)
    local Meta = ns.Meta
    local profile = Meta.Prepare({}).profile
    local camp = ns.Levels.Campaign(level)
    for n = 1, level.number - 1 do
        profile.levels[camp.levels[n].id] = { stars = 1, heroicStars = 0, wins = 1, plays = 1 }
    end
    -- a campaign that opens by stars: earn them in the other campaigns first
    local need = camp.unlock and camp.unlock.stars or 0
    for _, other in ipairs(ns.Levels.list) do
        if Meta.TotalStars(profile) >= need then break end
        if other.campaign ~= camp.id then
            profile.levels[other.id] = { stars = 3, heroicStars = 0, wins = 1, plays = 1 }
        end
    end
    for _, kind in ipairs(ns.Content.towerOrder) do profile.armory[kind] = armory end
    return profile
end

-- Plays one run to the end. Returns a result table. `snapshotAt` (a tick) round-trips the state through
-- Snapshot/Restore there, as a /reload mid-wave would. opts: seed, armory (research tier everywhere), noHero,
-- snapshotAt, transform, maxTicks, hpPct (creep health in percent of Normal's, for M.Headroom).
function M.Play(ns, levelId, difficulty, strategyName, opts)
    opts = opts or {}
    local Engine, Meta = ns.Engine, ns.Meta
    local level = ns.Levels.byId[levelId]
    local profile = M.Profile(ns, level, opts.armory)
    local loadout = Meta.Loadout(profile, difficulty, levelId)
    if opts.hpPct then loadout.hpPct = math.floor(loadout.hpPct * opts.hpPct / 100) end
    local state = assert(Engine.New(levelId, loadout, opts.seed or 7))
    local step = M.strategies[strategyName](opts)
    local peakCreeps, peakShots, float = 0, 0, 0
    local limit = opts.maxTicks or 30 * 60 * 30
    while not state.over and state.tick < limit do
        local wave = state.wave
        step(ns, state)
        if state.wave > wave and state.gold > float then float = state.gold end -- unspent as a wave starts
        Engine.Tick(state)
        if opts.snapshotAt and state.tick == opts.snapshotAt then
            state = assert(Engine.Restore(opts.transform and opts.transform(Engine.Snapshot(state))
                or Engine.Snapshot(state)))
        end
        if #state.creeps > peakCreeps then peakCreeps = #state.creeps end
        if #state.shots > peakShots then peakShots = #state.shots end
    end
    return {
        level = levelId, difficulty = difficulty, result = state.over or "timeout",
        strategy = strategyName .. (opts.armory and (" +R" .. opts.armory) or "") .. (opts.noHero and " -hero" or ""),
        lives = state.lives, maxLives = state.maxLives, wave = state.wave, ticks = state.tick, gold = state.gold,
        float = float,
        kills = state.stats.kills, leaks = state.stats.leaks, towers = #state.towers, peakCreeps = peakCreeps,
        peakShots = peakShots, stars = Meta.Stars(state.over == "won", state.lives, state.maxLives),
        hero = state.heroId ~= nil, final = Engine.Snapshot(state),
    }
end

-- The checks every level must pass on Normal: a list of failure strings (empty = fine).
function M.Check(ns, levelId)
    local failures = {}
    local level = ns.Levels.byId[levelId]
    local tier = M.Research(level)
    local greedy = M.Play(ns, levelId, "normal", "greedy", M.WithResearch(level))
    if greedy.result ~= "won" then
        failures[#failures + 1] = string.format("%s: greedy should win Normal with research tier %d, got %s at wave %d",
            levelId, tier, greedy.result, greedy.wave)
    end
    local floor = M.Floor(level)
    local margin = floor and M.Play(ns, levelId, "normal", "greedy", M.WithResearch(level, { hpPct = floor }))
    if margin and margin.result ~= "won" then
        failures[#failures + 1] = string.format("%s: greedy should still win with creeps at %d%% (a newcomer's "
            .. "margin, research tier %d), got %s at wave %d", levelId, floor, tier, margin.result, margin.wave)
    end
    local skilled = M.Play(ns, levelId, "normal", "sharp")
    if skilled.result ~= "won" then
        failures[#failures + 1] = string.format("%s: sharp should win Normal with no research at all, got %s at "
            .. "wave %d", levelId, skilled.result, skilled.wave)
    end
    for _, name in ipairs({ "none", "two scouts" }) do
        local r = M.Play(ns, levelId, "normal", name, M.WithResearch(level))
        if r.result ~= "lost" then
            failures[#failures + 1] = levelId .. ": '" .. name .. "' should lose, got " .. r.result
        end
    end
    return failures
end

-- How much tougher the creeps could be before `strategyName` stops winning with at least `stars` stars on Normal:
-- the most creep health it manages, in percent of Normal's. It steps up from 100 by 5 and stops at the first step it
-- fails (at most 300): winning isn't monotonic in creep health (a boss leaks all or nothing; a draft of 0.4.4's
-- Tiragarde Keep was won at 150% and lost at 140%), so a binary search could overstate it. nil if it can't even
-- manage 100. A level with lots of headroom for the sharp player is one a good human finds too easy.
function M.Headroom(ns, levelId, strategyName, stars, opts)
    local function Passes(pct)
        local o = {}
        for k, v in pairs(opts or {}) do o[k] = v end
        o.hpPct = pct
        return M.Play(ns, levelId, "normal", strategyName, o).stars >= (stars or 1)
    end
    if not Passes(100) then return nil end
    local pct = 100
    while pct < 300 and Passes(pct + 5) do pct = pct + 5 end
    return pct
end

-- Plays wave `w` out on a copy of `snap` (taken as greedy called it, before that tick ran) with its creeps `pct`
-- percent as tough, greedy (with `opts`) going on from there, buying as it goes. Returns the lives the wave cost.
local function WaveOut(ns, snap, w, pct, opts)
    local Engine = ns.Engine
    local copy = assert(Engine.Restore(snap))
    copy.loadout.hpPct = math.floor(copy.loadout.hpPct * pct / 100)
    local o = { resume = true }
    for k, v in pairs(opts) do o[k] = v end
    local step, lives, limit = M.strategies.greedy(o), copy.lives, copy.tick + 30 * 60 * 6
    local function Running()
        for _, a in ipairs(copy.active) do if a.wave == w then return true end end
        return false
    end
    while not copy.over and Running() and copy.tick < limit do
        Engine.Tick(copy)
        step(ns, copy)
    end
    return lives - copy.lives
end

-- Each wave's own headroom, to find the waves far easier or harder than the rest of their level (Bruce, 2026-10-22,
-- Shadowglen: "the first wave is simply zero chance of losing with just 1 tower up. but then it gets crazy hard where
-- wave 5/6 just blew past me with all my gold spent"). Greedy (a newcomer, with `opts`) plays the level; as each wave
-- is called, a copy plays that wave out from there, greedy buying as it goes, and the toughest creep health (in
-- percent, steps of 5, 20 to 1000) it holds without losing a life is the wave's headroom (0: not even 20). Returns
-- { { headroom, lost (lives the wave cost in greedy's own run), gold (unspent at the call) }, ... } and the result.
function M.Waves(ns, levelId, opts)
    opts = opts or {}
    local Engine, Meta = ns.Engine, ns.Meta
    local level = ns.Levels.byId[levelId]
    local loadout = Meta.Loadout(M.Profile(ns, level, opts.armory), "normal", levelId)
    if opts.hpPct then loadout.hpPct = math.floor(loadout.hpPct * opts.hpPct / 100) end
    local state = assert(Engine.New(levelId, loadout, opts.seed or 7))
    local step = M.strategies.greedy(opts)
    local rows, before = {}, state.lives
    while not state.over and state.tick < 30 * 60 * 30 do
        local wave = state.wave
        step(ns, state)
        if state.wave > wave then
            if rows[wave] then rows[wave].lost = before - state.lives end
            before = state.lives
            local snap = Engine.Snapshot(state)
            local function Holds(pct) return WaveOut(ns, snap, state.wave, pct, opts) == 0 end
            local lo, hi = 0, 100
            if Holds(100) then
                lo, hi = 100, 200
                while hi <= 1000 and Holds(hi) do lo, hi = hi, hi + 100 end
            elseif Holds(20) then
                lo = 20
            else
                hi = 0
            end
            while hi - lo > 5 and hi <= 1000 do
                local mid = math.floor((lo + hi) / 10) * 5
                if mid <= lo then mid = lo + 5 end
                if Holds(mid) then lo = mid else hi = mid end
            end
            rows[state.wave] = { headroom = lo, lost = 0, gold = state.gold }
        end
        Engine.Tick(state)
    end
    if rows[state.wave] then rows[state.wave].lost = before - state.lives end
    return rows, state.over
end

-- Creep health has three layers (Levels.lua): the level's (`waves.hp`), each wave's (`hp`) and a group's own. The
-- tools change the first two and leave a group's own to the level's design.

-- The 0.4.1 tuning knob, on the waves' layer: the first wave as it was and the last `pct` percent tougher, the waves
-- between in proportion (whole percents). Changes the level in place, from its loaded numbers.
local loaded = {}
function M.Scale(level, pct)
    local base = loaded[level]
    if not base then
        base = {}
        for w, wave in ipairs(level.waves) do base[w] = wave.hp or 100 end
        loaded[level] = base
    end
    local last = #level.waves
    for w, wave in ipairs(level.waves) do
        local share = last > 1 and (w - 1) / (last - 1) or 1
        wave.hp = math.max(5, math.floor(base[w] * (100 + pct * share) / 100 + 0.5))
    end
end

-- The plain knob, for fine-tuning by feel ("this level is 10% too hard"): the level's own health times `pct`
-- percent, so every wave's too. Changes the level in place; M.Scale starts again from the result.
function M.Multiply(level, pct)
    level.waves.hp = math.max(5, math.floor((level.waves.hp or 100) * pct / 100 + 0.5))
    loaded[level] = nil
end

-- The balance targets, by level number: the creep health greedy (a sensible newcomer, building a mix) must still
-- beat on Normal, in percent. Bruce, 2026-10-19: "slightly challenging, but not too much to send people away"
-- (0.4.1), then "like 10% too hard all across the board", "i want to encourage some creativity with tower usage.
-- not always mixmax" (0.4.2: every target +10, the first levels +15), then after replaying the Horde on 0.4.2: the
-- levels up to Skull Rock "a bit too easy", Razorfen Kraul easy, Ragefire Chasm "perfect" (0.4.3: income -20%,
-- heroes' abilities every 3 minutes, and these targets back down; from level 5 a real player has research, so the
-- zero-research margin there is small). The starting campaigns give a newcomer the most room; the later ones assume
-- they've learned. Levels with two roads get M.TWO_LANES more ("the maps with 2 lanes especially can be slightly
-- more difficult by its design"): a person has to split their towers, while the bots place them perfectly. The
-- margins are greedy's with the research M.RESEARCH assumes. The Forsaken's first four "felt perfect" to Bruce
-- (2026-10-22) at 120, 115, 105 and 105 (Brill has two roads), so theirs came down to match: by the last campaign
-- (55 stars to open) a player has learned.
M.FLOOR = {
    horde = { 135, 125, 120, 115, 110, 110, 110, 110 }, alliance = { 135, 125, 120, 115, 110, 110, 110, 110 },
    sentinels = { 125, 120, 115, 110, 110, 110, 110, 110 }, forsaken = { 120, 110, 105, 105, 110, 110, 110, 110 },
}
M.TWO_LANES = 5
M.THREE_STARS = 105 -- and the better bot must still keep every life with this much (3 stars stay possible)

-- The research the balance assumes a player has when starting each level (Bruce, 2026-10-22: "assume just sub-par
-- typical research", after his Armory upgrades made the later levels "wildly out of balance"). Research is per tower
-- and he spends Warmarks as he earns them, on the campaign he is playing (he reached the Sentinels with 20 banked),
-- so every campaign starts from none. Armory tier n on every tower (tier 1: +10% damage; tier 2: +10% range too;
-- tier 3 opens a specialization; tier 4: +10% damage more and -10% build cost). The second half of every campaign
-- still played too easy for him (2026-10-23, Shadowfang Keep: "definitely too easy with way too much gold surplus
-- (so also consider the rest of the 2nd half of normal campaign with this)"), with tier 3 on the towers he uses and
-- their specializations: so levels 5-6 assume tier 2, and levels 7-8 tier 4, whose stats stand in for tier 3 and a
-- specialization (the bots seldom specialize). With no research at all, good play still wins every level (M.Check
-- holds the sharp bot to that).
local CURVE = { 0, 0, 1, 1, 2, 2, 4, 4 }
M.RESEARCH = { horde = CURVE, alliance = CURVE, sentinels = CURVE, forsaken = CURVE }

function M.Research(level)
    local r = M.RESEARCH[level.campaign]
    return r and r[level.number] or 0
end

-- opts (a copy) for a player who has the research M.RESEARCH assumes at this level.
function M.WithResearch(level, opts)
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    if M.Research(level) > 0 then o.armory = M.Research(level) end
    return o
end

-- How many ground roads a level has (flyers' paths don't count).
function M.Lanes(level)
    local n = 0
    for _, path in ipairs(level.paths) do if not path.air then n = n + 1 end end
    return n
end

-- A level's floor: its M.FLOOR, and M.TWO_LANES more with two roads or more. nil for a level with no target.
function M.Floor(level)
    local floor = M.FLOOR[level.campaign] and M.FLOOR[level.campaign][level.number]
    return floor and floor + (M.Lanes(level) > 1 and M.TWO_LANES or 0)
end

-- How many styles of play win on Normal (with `opts`: the research M.WithResearch gives, say): greedy as it is, and
-- greedy favouring each role the level has (every other tower that role). Bruce wants room for creative builds, not
-- only the best one. Returns wins, styles, and the roles whose style lost.
function M.Styles(ns, levelId, opts)
    local level = ns.Levels.byId[levelId]
    local loadout = ns.Meta.Loadout(M.Profile(ns, level), "normal", levelId)
    local wins, styles, lost = 0, 0, {}
    local roles = { false }
    for _, kind in ipairs(loadout.towers) do roles[#roles + 1] = ns.Content.towers[kind].role end
    for _, role in ipairs(roles) do
        styles = styles + 1
        local o = {}
        for k, v in pairs(opts or {}) do o[k] = v end
        o.favour = role or nil
        if M.Play(ns, levelId, "normal", "greedy", o).result == "won" then
            wins = wins + 1
        else
            lost[#lost + 1] = role or "mixed"
        end
    end
    return wins, styles, lost
end

-- What a good player could do: the better of greedy and sharp at keeping every life (sharp only when greedy can't
-- reach `need`, to save time).
function M.Skilled3(ns, levelId, need, opts)
    local g = M.Headroom(ns, levelId, "greedy", 3, opts)
    if g and g >= need then return g end
    local s = M.Headroom(ns, levelId, "sharp", 3, opts)
    if not g or (s and s > g) then return s end
    return g
end

-- Tunes a level in place: the most `pct` (from -50 to 150, in steps of 5) that leaves greedy winning with
-- `floor` percent creep health, then up to 30 less while the better bot can't keep every life at M.THREE_STARS
-- percent. If that's out of reach, the toughest step where it can keep every life at all (100%); if even that is,
-- the trouble is elsewhere (an early wave, which this knob leaves alone, or a boss): it goes back to the first
-- answer, and the level needs a look by hand. Returns pct.
function M.Tune(ns, levelId, floor)
    local level = ns.Levels.byId[levelId]
    local research = M.WithResearch(level)
    local function Holds(pct)
        M.Scale(level, pct)
        local h = M.Headroom(ns, levelId, "greedy", 1, research)
        return h ~= nil and h >= floor
    end
    local lo, hi = -50, 150
    if Holds(hi) then
        lo = hi
    elseif Holds(lo) then
        while hi - lo > 5 do
            local mid = math.floor((lo + hi) / 10) * 5
            if mid <= lo then mid = lo + 5 end
            if Holds(mid) then lo = mid else hi = mid end
        end
    end
    local first, lowest, possible = lo, math.max(-50, lo - 30), nil
    while true do
        M.Scale(level, lo)
        local s = M.Skilled3(ns, levelId, M.THREE_STARS, research)
        if s and s >= M.THREE_STARS then return lo end
        possible = possible or (s and lo)
        if lo <= lowest then break end
        lo = math.max(lowest, lo - 10)
    end
    lo = possible or first
    M.Scale(level, lo)
    return lo
end

-- The band M.Shape keeps wave `w`'s own headroom (M.Waves) in: the opening third 140-175 (Bruce on Shadowglen,
-- 2026-10-22: "the first wave is simply zero chance of losing with just 1 tower up"), the middle 100-225 (no wave
-- that "just blew past me with all my gold spent"), the last wave 100-150 (a climax, never the easiest).
function M.Band(level, w)
    local n = #level.waves
    if w <= math.ceil(n / 3) then return 140, 175 end
    if w == n then return 100, 150 end
    return 100, 225
end

-- The band M.Shape keeps wave `w`'s own headroom in when it keeps a level as it was through a change to the towers
-- (0.4.7: the shorter reach): `keep` is the level's M.Waves rows from before the change, and the band is within 15
-- points (or 8%) of the wave's headroom then, never under 100 if it held at normal health then. M.Shape also keeps the
-- lives the wave costs greedy's own run to at most one more than then.
function M.KeepBand(keep, w)
    local h = keep[w].headroom
    local half = math.max(15, h * 0.08)
    return h >= 100 and math.max(100, h - half) or h - 5, h + half
end

local function Steps(x) return math.floor(x * 40 + 0.5) / 40 end -- a factor, in steps of 2.5%

-- Sets a level's own health (`waves.hp`, so every wave's) until greedy's M.Headroom, with the research the balance
-- assumes, is within 5 of `target`: damped steps, easing first if greedy can't win at all. At most `tries` steps.
-- Returns the headroom it reached.
function M.Fit(ns, levelId, target, tries)
    local level = ns.Levels.byId[levelId]
    local research = M.WithResearch(level)
    local base, f = level.waves.hp or 100, 1
    local function Apply() level.waves.hp = math.max(5, math.floor(base * f + 0.5)) end
    local function Now() return M.Headroom(ns, levelId, "greedy", 1, research) end
    local now = Now()
    for _ = 0, tries or 3 do
        while not now and f > 0.4 do
            f = f - 0.025
            Apply()
            now = Now()
        end
        if not now or math.abs(now - target) <= 5 then break end
        local was = f
        f = Steps(f * (now / target) ^ 0.8)
        if f == was then break end
        Apply()
        now = Now()
    end
    return now
end

-- The guards, on the level's own health: eases it in steps of 2.5% until greedy, with the research the balance
-- assumes, wins with the creeps at M.Floor, and sharp wins with no research at all. Returns how many steps it took.
function M.Guard(ns, levelId)
    local level = ns.Levels.byId[levelId]
    local base, floor, steps = level.waves.hp or 100, M.Floor(level), 0
    while steps < 24 and not (M.Play(ns, levelId, "normal", "greedy", M.WithResearch(level, { hpPct = floor }))
        .result == "won" and M.Play(ns, levelId, "normal", "sharp").result == "won") do
        steps = steps + 1
        level.waves.hp = math.max(5, math.floor(base * (1 - 0.025 * steps) + 0.5))
    end
    return steps
end

-- Reshapes a level in place (0.4.4): each wave's own health (`hp`) so its headroom for greedy, with the research the
-- balance assumes, sits in its M.Band, and the level's (M.Fit) so greedy's M.Headroom stays at `target` (default:
-- what it is now). Steps are damped and the waves measured again after each change, because a wave isn't independent
-- of the ones before it: a leak there costs bounty, and a hero's 3-minute ability spent there is missing later. Then
-- M.Guard. With `keep` (M.Waves rows from before a change), each wave goes back to its own numbers instead
-- (M.KeepBand). Returns each wave's factor and how many rounds it took.
function M.Shape(ns, levelId, target, keep)
    local level = ns.Levels.byId[levelId]
    local research = M.WithResearch(level)
    local base, m = {}, {}
    for w, wave in ipairs(level.waves) do base[w], m[w] = wave.hp or 100, 1 end
    local function Apply()
        for w, wave in ipairs(level.waves) do wave.hp = math.max(5, math.floor(base[w] * m[w] + 0.5)) end
        loaded[level] = nil
    end
    target = target or M.Headroom(ns, levelId, "greedy", 1, research) or M.Floor(level) or 100
    local function Step() -- one look at every wave; false when they're all in their bands
        local rows, changed = M.Waves(ns, levelId, research), false
        local function Set(w, f) -- a step that rounds to no change isn't one
            f = Steps(f)
            if f ~= m[w] then m[w], changed = f, true end
        end
        for w = 1, #level.waves do
            local r = rows[w]
            if not r then break end
            local lo, hi
            if keep then lo, hi = M.KeepBand(keep, w) else lo, hi = M.Band(level, w) end
            if r.headroom > hi then
                Set(w, m[w] * math.min(2.5, (r.headroom / (hi - 5)) ^ 0.7))
            elseif r.headroom < lo then
                Set(w, m[w] * math.max(0.6, math.min(0.975, (math.max(r.headroom, 20) / (lo + 5)) ^ 0.7)))
                break -- the waves after it were played on from its leaks: measure them again first
            elseif keep and r.lost > keep[w].lost + 1 then
                Set(w, m[w] * 0.95)
                break
            end
        end
        Apply()
        return changed
    end
    M.Fit(ns, levelId, target, 3)
    local rounds = 0
    while rounds < 12 and Step() do
        rounds = rounds + 1
        M.Fit(ns, levelId, target, 2)
    end
    M.Guard(ns, levelId)
    return m, rounds
end

-- A level's waves as campaign-file source (16-space indent, wrapped at 120 columns): the level's own health, then
-- each wave's with its groups (a group's own health only where it isn't 100).
function M.WavesText(level)
    local lines = { "            waves = {", "                hp = " .. (level.waves.hp or 100) .. "," }
    for _, wave in ipairs(level.waves) do
        local line = "                { hp = " .. (wave.hp or 100) .. ","
        for g, grp in ipairs(wave) do
            local args = { string.format("%q", grp.creep), grp.count, grp.gap }
            local delay, hp = grp.delay or 0, grp.hp or 100
            if grp.path then
                args[4], args[5], args[6] = delay, hp, grp.path
            elseif hp ~= 100 then
                args[4], args[5] = delay, hp
            elseif delay ~= 0 then
                args[4] = delay
            end
            local piece = " G(" .. table.concat(args, ", ") .. ")" .. (g < #wave and "," or " },")
            if #line + #piece > 120 then
                lines[#lines + 1] = line
                line = "                   " .. piece
            else
                line = line .. piece
            end
        end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = "            },"
    return table.concat(lines, "\n")
end

-- Writes a level's waves (as they are in memory) into its campaign file (or `path`), in place of the old block,
-- with LF endings.
-- io.open, tried a few times: on Windows a file the game client is reading can refuse for a moment ("Invalid
-- argument").
local function Open(path, mode)
    local f, err
    for _ = 1, 10 do
        f, err = io.open(path, mode)
        if f then return f end
        local t = os.clock()
        while os.clock() - t < 0.3 do end
    end
    error(err)
end

function M.WriteWaves(level, path)
    path = path or (root .. "/ForeverTD/Campaigns/" .. level.campaign:gsub("^%l", string.upper) .. ".lua")
    local f = Open(path, "rb")
    local s = f:read("*a")
    f:close()
    local start = assert(s:find("            waves = {", assert(s:find('id = "' .. level.id .. '"', 1, true)), true))
    local i, depth = s:find("{", start, true), 0
    repeat
        local ch = s:sub(i, i)
        if ch == "{" then depth = depth + 1 elseif ch == "}" then depth = depth - 1 end
        i = i + 1
    until depth == 0
    assert(s:sub(i, i) == ",", level.id .. ": the waves block should end with },")
    f = Open(path, "wb")
    f:write(s:sub(1, start - 1), M.WavesText(level), s:sub(i + 1))
    f:close()
end

function M.Line(r)
    return string.format("%-12s %-7s %-17s %-5s lives %2d/%d  stars %d  wave %2d  %4.1f min  gold %4d  kills %3d  "
        .. "leaks %2d  towers %2d  peak creeps %2d shots %2d", r.level, r.difficulty, r.strategy, r.result, r.lives,
        r.maxLives, r.stars, r.wave, r.ticks / 30 / 60, r.gold, r.kills, r.leaks, r.towers, r.peakCreeps, r.peakShots)
end

local args = { ... }
if args[1] == "--lib" then return M end

local ns = M.Load()
local headroom, tune, scale = args[1] == "--headroom", args[1] == "--tune", args[1] == "--scale" and tonumber(args[2])
local waves, shape = args[1] == "--waves", args[1] == "--shape"
local keepFile = args[1] == "--keep" and args[2]
if headroom or tune or waves or shape then table.remove(args, 1) end
if keepFile then table.remove(args, 1); table.remove(args, 1) end
if scale then table.remove(args, 1); table.remove(args, 1) end
local write = args[#args] == "--write"
if write then args[#args] = nil end
local ids = {}
for _, l in ipairs(ns.Levels.list) do
    if not args[1] or l.id == args[1] or l.campaign == args[1] then ids[#ids + 1] = l.id end
end
if scale then -- lua tools/sim.lua --scale <pct> [campaign or level] [--write]: every wave's health times pct%
    for _, id in ipairs(ids) do
        local level = ns.Levels.byId[id]
        M.Multiply(level, scale)
        print(string.format("@@ %s x%d%%", id, scale))
        print(M.WavesText(level))
        if write then M.WriteWaves(level) end
    end
    os.exit(0)
end
if shape then -- lua tools/sim.lua --shape [campaign or level] [--write]: each wave in its band (minutes a level)
    for _, id in ipairs(ids) do
        local level = ns.Levels.byId[id]
        local research = M.WithResearch(level)
        local target = M.Headroom(ns, id, "greedy", 1, research)
        local m, rounds = M.Shape(ns, id, target)
        local cells = {}
        for w, r in ipairs(M.Waves(ns, id, research)) do cells[w] = r.headroom .. "" end
        for w = 1, #m do m[w] = string.format("%.2f", m[w]) end
        print(string.format("@@ %s level hp %d, waves x[%s] in %d rounds: greedy (research tier %d) %s (was %s), "
            .. "waves [%s]", id, level.waves.hp or 100, table.concat(m, " "), rounds, M.Research(level),
            tostring(M.Headroom(ns, id, "greedy", 1, research)), tostring(target), table.concat(cells, " ")))
        print(M.WavesText(level))
        if write then M.WriteWaves(level) end
        io.stdout:flush()
    end
    os.exit(0)
end
if keepFile then -- lua tools/sim.lua --keep before.txt [campaign or level] [--write]: each wave as it was before
    local before = {}
    for line in io.lines(keepFile) do
        local id, margin, cells = line:match("^(%S+)%s+tier %d+%s+margin (%d+)%s+%a+%s+(.*)$")
        if id then
            local rows = {}
            for cell in cells:gmatch("%S+") do
                rows[#rows + 1] = { headroom = tonumber(cell:match("^(%d+)")),
                    lost = tonumber(cell:match("/(%d+)") or "0") }
            end
            before[id] = { margin = tonumber(margin), rows = rows }
        end
    end
    for _, id in ipairs(ids) do
        local level, b = ns.Levels.byId[id], before[id]
        if b and #b.rows == #level.waves then
            local m, rounds = M.Shape(ns, id, b.margin, b.rows)
            local research = M.WithResearch(level)
            local cells = {}
            for w, r in ipairs(M.Waves(ns, id, research)) do
                cells[w] = r.headroom .. (r.lost > 0 and ("/" .. r.lost) or "")
            end
            for w = 1, #m do m[w] = string.format("%.2f", m[w]) end
            print(string.format("@@ %s level hp %d, waves x[%s] in %d rounds: greedy (research tier %d) %s (was %d), "
                .. "waves [%s]", id, level.waves.hp or 100, table.concat(m, " "), rounds, M.Research(level),
                tostring(M.Headroom(ns, id, "greedy", 1, research)), b.margin, table.concat(cells, " ")))
            print(M.WavesText(level))
            if write then M.WriteWaves(level) end
        else
            print("@@ " .. id .. ": not in " .. keepFile .. " (or its waves changed), left as it is")
        end
        io.stdout:flush()
    end
    os.exit(0)
end
if tune then -- lua tools/sim.lua --tune [campaign or level] [--write]: each level's new waves (--write: into its file)
    for _, id in ipairs(ids) do
        local level = ns.Levels.byId[id]
        local pct = M.Tune(ns, id, M.Floor(level))
        print(string.format("@@ %s %d greedy %s, skilled 3 stars %s (research tier %d)", id, pct,
            tostring(M.Headroom(ns, id, "greedy", 1, M.WithResearch(level))),
            tostring(M.Skilled3(ns, id, 999, M.WithResearch(level))), M.Research(level)))
        print(M.WavesText(level))
        if write then M.WriteWaves(level) end
        io.stdout:flush()
    end
    os.exit(0)
end
if waves then -- lua tools/sim.lua --waves [campaign or level]
    print("Each wave's headroom for greedy with the research M.RESEARCH assumes: the toughest creep health (percent)")
    print("it holds without losing a life, going on from the towers it has as the wave is called and buying as it")
    print("goes (under 100: it leaks at Normal's), and after a slash the lives the wave cost in its own run, if any;")
    print("! marks a wave outside its M.Band (the opening third 140-175, the middle 100-225, the last 100-150); the")
    print("margin is the level's (M.Headroom). Save this before changing a tower, and --keep it after.")
    for _, id in ipairs(ids) do
        local level = ns.Levels.byId[id]
        local rows, result = M.Waves(ns, id, M.WithResearch(level))
        local cells = {}
        for w, r in ipairs(rows) do
            local lo, hi = M.Band(level, w)
            cells[w] = r.headroom .. (r.lost > 0 and ("/" .. r.lost) or "") .. ((r.headroom < lo or r.headroom > hi)
                and "!" or "")
        end
        print(string.format("%-12s tier %d  margin %s  %-5s %s", id, M.Research(level),
            tostring(M.Headroom(ns, id, "greedy", 1, M.WithResearch(level))), result or "?", table.concat(cells, " ")))
        io.stdout:flush()
    end
    os.exit(0)
end
if headroom then -- lua tools/sim.lua --headroom [campaign or level]
    print("Creep health each bot still beats on Normal (win / 3 stars); greedy's lives at 100%; how many styles of")
    print("play win (greedy, and greedy favouring each role, with the research M.RESEARCH assumes); the most gold the")
    print("sharp bot leaves unspent at a wave; and greedy's win with that research (the Armory tier everywhere)")
    print("level        greedy win 3-star   sharp win 3-star   greedy lives   styles   sharp unspent   research")
    local function H(v) return v and string.format("%3d%%", v) or "lost" end
    for _, id in ipairs(ids) do
        local level = ns.Levels.byId[id]
        local g, s = M.Play(ns, id, "normal", "greedy"), M.Play(ns, id, "normal", "sharp")
        local wins, styles, lost = M.Styles(ns, id, M.WithResearch(level))
        local researched = H(M.Headroom(ns, id, "greedy", 1, M.WithResearch(level)))
        print(string.format("%-12s       %s   %s         %s   %s       %2d/%d       %d/%d     %4d   tier %d: %s  %s",
            id,
            H(M.Headroom(ns, id, "greedy", 1)), H(M.Headroom(ns, id, "greedy", 3)),
            H(M.Headroom(ns, id, "sharp", 1)), H(M.Headroom(ns, id, "sharp", 3)), g.lives, g.maxLives, wins, styles,
            s.float, M.Research(level), researched, #lost > 0 and ("(lost: " .. table.concat(lost, ", ") .. ")") or ""))
        io.stdout:flush()
    end
    os.exit(0)
end
local failed = 0
for _, id in ipairs(ids) do
    for _, difficulty in ipairs({ "normal", "heroic" }) do
        for _, name in ipairs({ "none", "two scouts", "greedy" }) do
            print(M.Line(M.Play(ns, id, difficulty, name)))
        end
        if difficulty == "normal" and ns.Levels.byId[id].number >= ns.Levels.Campaign(ns.Levels.byId[id]).hero.at then
            print(M.Line(M.Play(ns, id, difficulty, "greedy", { noHero = true }))) -- how much the hero carries
        end
        print(M.Line(M.Play(ns, id, difficulty, "greedy", { armory = 3 }))) -- Armory tier 3 everywhere
    end
    for _, f in ipairs(M.Check(ns, id)) do print("FAIL " .. f); failed = failed + 1 end
end
print(failed == 0 and "all checks pass" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
