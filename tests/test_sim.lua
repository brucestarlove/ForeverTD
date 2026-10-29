-- The balance checks, as tests: every level's Normal is won by a sensible build with the research the balance
-- assumes there (with a newcomer's margin), won with no research at all by good play, and lost with no towers or
-- with too few. tools/sim.lua prints the details. And the tuner.
local tests = {}

tests["every Normal level: won with the research it assumes (and a newcomer's margin), won with none by good play, "
    .. "and lost without defending"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local failures = {}
    for _, level in ipairs(ns.Levels.list) do
        for _, f in ipairs(S.Check(ns, level.id)) do failures[#failures + 1] = f end
    end
    T.eq(table.concat(failures, "; "), "", "balance checks")
end

tests["the tuner toughens the later waves, and writes every level's waves back byte for byte"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local level = ns.Levels.byId["horde-1"]
    local first, last = level.waves[1].hp, level.waves[#level.waves].hp
    S.Scale(level, 50)
    T.eq(level.waves[1].hp, first, "the first wave as it was")
    T.eq(level.waves[#level.waves].hp, math.floor(last * 1.5 + 0.5), "the last one 50% tougher")
    S.Scale(level, 0)
    T.eq(level.waves[#level.waves].hp, last, "and back")
    local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/ForeverTD-waves-test.lua"
    for _, camp in ipairs(ns.Levels.campaigns) do
        local path = T.base .. "/ForeverTD/Campaigns/" .. camp.id:gsub("^%l", string.upper) .. ".lua"
        local f = assert(io.open(path, "rb"))
        local original = f:read("*a")
        f:close()
        f = assert(io.open(tmp, "wb"))
        f:write(original)
        f:close()
        for _, l in ipairs(camp.levels) do S.WriteWaves(l, tmp) end
        f = assert(io.open(tmp, "rb"))
        local written = f:read("*a")
        f:close()
        T.ok(written == original, camp.id .. ": unchanged waves written back identically")
    end
    os.remove(tmp)
end

tests["each wave on its own: a headroom that agrees with the bot's own run, and doesn't see later waves"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local Engine = ns.Engine
    -- greedy picked up in the middle of a game plays on exactly as the one that started it
    local razorHill = ns.Levels.byId["horde-2"]
    local state = Engine.New("horde-2", ns.Meta.Loadout(S.Profile(ns, razorHill), "normal", "horde-2"), 7)
    local step = S.strategies.greedy({})
    repeat
        step(ns, state)
        if state.wave < 5 then Engine.Tick(state) end
    until state.wave >= 5
    local copy, resumed = assert(Engine.Restore(Engine.Snapshot(state))), S.strategies.greedy({ resume = true })
    local function Board(s)
        local t = {}
        for i, tower in ipairs(s.towers) do t[i] = tower.kind .. tower.rank .. "@" .. tower.c .. "," .. tower.r end
        return table.concat(t, " ") .. " gold " .. s.gold .. " lives " .. s.lives .. " wave " .. s.wave
    end
    for _ = 1, 30 * 60 * 3 do
        Engine.Tick(state)
        step(ns, state)
        Engine.Tick(copy)
        resumed(ns, copy)
    end
    T.eq(Board(copy), Board(state), "the same towers, gold and lives three minutes on")
    local leaked, held = 0, 0
    for _, pct in ipairs({ 100, 150, 200 }) do
        local rows = S.Waves(ns, "horde-1", { hpPct = pct })
        for w, r in ipairs(rows) do
            T.ok(r.headroom % 5 == 0 and r.headroom >= 0 and r.headroom <= 1000, "a headroom in steps of 5")
            -- the copy goes on exactly as the bot did, so at the same health it loses what the bot's run lost
            T.eq(r.headroom >= 100, r.lost == 0, pct .. "%, wave " .. w .. ": holds at 100% when the run lost none")
            if r.lost > 0 then leaked = leaked + 1 else held = held + 1 end
        end
    end
    T.ok(leaked > 0 and held > 0, "waves that leaked and waves that held (" .. leaked .. ", " .. held .. ")")
    local level = ns.Levels.byId["horde-1"]
    local before = S.Waves(ns, "horde-1")
    level.waves[4].hp = level.waves[4].hp * 2
    local after = S.Waves(ns, "horde-1")
    for w = 1, 3 do T.eq(after[w].headroom, before[w].headroom, "wave " .. w .. " as it was") end
    T.ok(after[4].headroom < before[4].headroom, "wave 4 twice as tough: less headroom")
end

tests["the reshaper puts a wave that's far too easy back in its band, and leaves the others"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local level = ns.Levels.byId["sentinels-1"]
    local target = S.Headroom(ns, "sentinels-1", "greedy", 1, S.WithResearch(level))
    local function Tough(w) return level.waves[w].hp * level.waves.hp / 100 end -- the wave's and the level's
    local before = {}
    for w in ipairs(level.waves) do before[w] = Tough(w) end
    level.waves[1].hp = math.floor(level.waves[1].hp * 0.4 + 0.5) -- "zero chance of losing with just 1 tower up"
    T.ok(S.Waves(ns, "sentinels-1", S.WithResearch(level))[1].headroom > select(2, S.Band(level, 1)),
        "the first wave far too easy now")
    S.Shape(ns, "sentinels-1", target)
    local rows = S.Waves(ns, "sentinels-1", S.WithResearch(level))
    local lo, hi = S.Band(level, 1)
    T.ok(rows[1].headroom >= lo and rows[1].headroom <= hi, "back in its band: " .. rows[1].headroom)
    T.ok(math.abs(Tough(1) / before[1] - 1) <= 0.25, "about as tough as it was")
    for w = 2, #level.waves do T.ok(math.abs(Tough(w) / before[w] - 1) <= 0.15, "wave " .. w .. " about as it was") end
end

tests["through a change to the towers, the reshaper keeps each wave as it was (--keep)"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local function Band(h) return table.concat({ S.KeepBand({ { headroom = h } }, 1) }, "-") end
    T.eq(Band(150), "135-165", "a band around the wave's headroom before")
    T.eq(Band(105), "100-120", "never under 100 if it held at normal health")
    T.eq(Band(80), "75-95", "and 5 under if it didn't")
    local id = "forsaken-1"
    local research = S.WithResearch(ns.Levels.byId[id])
    local margin, before = S.Headroom(ns, id, "greedy", 1, research), S.Waves(ns, id, research)
    for _, tower in pairs(ns.Content.towers) do -- every tower reaches 15% less, as 0.4.7 brought them in
        for _, r in ipairs(tower.ranks) do r.range = math.floor(r.range * 0.85) end
    end
    local function Kept(rows) -- (the guards may ease the whole level a step after: a little room above)
        for w, r in ipairs(rows) do
            local lo, hi = S.KeepBand(before, w)
            if r.headroom < lo or r.headroom > hi + 10 or r.lost > before[w].lost + 1 then return false, w end
        end
        return true
    end
    T.ok(not Kept(S.Waves(ns, id, research)), "the shorter reach moved some wave")
    S.Shape(ns, id, margin, before)
    local kept, w = Kept(S.Waves(ns, id, research))
    T.ok(kept, "every wave back as it was" .. (w and (" (not wave " .. w .. ")") or ""))
    T.ok(math.abs(S.Headroom(ns, id, "greedy", 1, research) - margin) <= 10, "and the level's margin")
end

tests["--keep also holds the lives a wave that leaks costs"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local id = "forsaken-3" -- Agamand Mills: one wave costs the newcomer bot a life or two
    local research = S.WithResearch(ns.Levels.byId[id])
    local margin, rows = S.Headroom(ns, id, "greedy", 1, research), S.Waves(ns, id, research)
    local leaky, keep = nil, {}
    for w, r in ipairs(rows) do
        if r.lost >= 2 then leaky = w end
        keep[w] = { headroom = r.headroom, lost = r.lost }
    end
    T.ok(leaky, id .. ": a wave that costs two lives or more (pick another level if it no longer leaks)")
    keep[leaky].lost = 0 -- as if it had cost none before: its headroom is in its band, its lives aren't
    S.Shape(ns, id, margin, keep)
    T.ok(S.Waves(ns, id, research)[leaky].lost <= 1, "now it costs a life at most")
end

tests["the newcomer bot builds a revealer before stealthed creeps, sooner when they come early"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    -- Sentinel Hill's footpads come in wave 3, the Sepulcher's worgen in wave 4
    for _, case in ipairs({ { "alliance-5", "paladin", 2 }, { "forsaken-4", "banshee", 3 } }) do
        local r = S.Play(ns, case[1], "normal", "greedy")
        local built = {}
        for _, t in ipairs(r.final.towers) do
            if not ns.Content.towers[t.kind].hero then built[#built + 1] = t.kind end
        end
        T.eq(built[case[3]], case[2], case[1] .. ": the revealer is tower " .. case[3])
        for i = 1, case[3] - 1 do T.ok(built[i] ~= case[2], case[1] .. ": and not before") end
    end
end

tests["fine-tuning by feel, two-road targets, and styles of play"] = function(T)
    local S = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local ns = S.Load(T.base)
    local level = ns.Levels.byId["horde-2"]
    local was, waves = level.waves.hp, {}
    for w, wave in ipairs(level.waves) do waves[w] = wave.hp end
    S.Multiply(level, 90)
    T.eq(level.waves.hp, math.floor(was * 0.9 + 0.5), "the level's own health x90%")
    for w, wave in ipairs(level.waves) do T.eq(wave.hp, waves[w], "wave " .. w .. ": its own as it was") end
    local grp = level.waves[1][1]
    T.eq(ns.Engine.GroupHpPct(level, 1, grp, 100), math.floor(grp.hp * waves[1] * level.waves.hp / 10000),
        "so every creep 10% weaker")
    local one, two = ns.Levels.byId["horde-1"], ns.Levels.byId["horde-4"] -- Valley of Trials has a flyers' path too
    T.eq(S.Lanes(one) .. "," .. S.Lanes(two), "1,2", "roads counted, flyers' paths not")
    T.eq(S.Floor(one), S.FLOOR.horde[1], "one road: the level's target")
    T.eq(S.Floor(two), S.FLOOR.horde[4] + S.TWO_LANES, "two roads: more room")
    local counts = {}
    for _, favour in ipairs({ false, "control" }) do
        local r = S.Play(ns, "horde-1", "normal", "greedy", { favour = favour or nil })
        local n = 0
        for _, t in ipairs(r.final.towers) do if t.kind == "witchdoctor" then n = n + 1 end end
        counts[#counts + 1] = n
    end
    T.ok(counts[2] > counts[1], "favouring control builds more witch doctors (" .. table.concat(counts, " vs ") .. ")")
    local wins, styles = S.Styles(ns, "horde-1")
    T.eq(styles, 3, "Valley of Trials: the mixed build, and one leaning on each of its two towers")
    T.ok(wins >= 1 and wins <= styles, "wins counted")
end

return tests
