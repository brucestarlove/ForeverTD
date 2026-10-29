-- Meta tests: the save file's shape and migrations, stars, Warmarks, unlocks, and paying a result only once.
local stub = require("wowstub")

local function load(T)
    local ns = {}
    for _, file in ipairs(assert(loadfile(T.base .. "/tools/sim.lua"))("--lib").Files(T.base)) do
        stub.load(T.base .. "/ForeverTD/" .. file, "ForeverTD", ns, stub.env())
    end
    return ns, ns.Meta
end

local function result(runId, won, lives, extra)
    local r = { runId = runId, level = "horde-2", difficulty = "normal", won = won, lives = lives, maxLives = 20,
        kills = 10 }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- A profile that has won every level of a campaign up to (not including) number n.
local function reached(Meta, ns, campId, n)
    local p = Meta.Prepare({}).profile
    local camp = ns.Levels.campaignById[campId]
    for i = 1, n - 1 do p.levels[camp.levels[i].id] = { stars = 1, heroicStars = 0, wins = 1, plays = 1 } end
    return p
end

local tests = {}

tests["prepare: the toy's save is dropped, dev data kept, defaults filled, newer files left alone"] = function(T)
    local _, Meta = load(T)
    local db = { save = { schema = 1, tick = 527 }, dev = { starred = { maps = { [1411] = "Durotar" } } } }
    T.eq(Meta.Prepare(db), db, "same table, changed in place")
    T.eq(db.save, nil, "toy save dropped")
    T.eq(db.dev.starred.maps[1411], "Durotar", "dev data untouched")
    T.eq(db.schema, Meta.SCHEMA, "schema")
    T.eq(db.profile.warmarks, 0, "profile")
    T.eq(db.settings.speed, 1, "settings")
    T.eq(db.settings.story, true, "story on by default")
    db.profile.warmarks = 55
    Meta.Prepare(db)
    T.eq(db.profile.warmarks, 55, "a second prepare keeps progress")
    local newer = { schema = Meta.SCHEMA + 1, profile = { warmarks = 9 } }
    local ok, why = Meta.Prepare(newer)
    T.eq(ok, nil, "refused")
    T.eq(why, "newer", "reason")
    T.eq(newer.profile.warmarks, 9, "untouched")
end

tests["0.4.3's pace: a speed saved before it becomes the new 1x once, and later choices stay"] = function(T)
    local _, Meta = load(T)
    local db = { schema = Meta.SCHEMA, profile = { warmarks = 5 }, settings = { speed = 2, scale = 1.6 } }
    Meta.Prepare(db)
    T.eq(db.settings.speed, 1, "the old 2x is the new normal speed")
    T.eq(db.settings.paced, true, "mapped once")
    T.eq(db.settings.scale, 1.6, "the rest kept")
    db.settings.speed = 2 -- the new 2x, chosen after
    Meta.Prepare(db)
    T.eq(db.settings.speed, 2, "a choice made since stays")
    local fresh = Meta.Prepare({})
    T.eq(fresh.settings.speed .. "/" .. tostring(fresh.settings.paced), "1/true", "a new save starts at 1x, mapped")
end

tests["a 0.3 save: its progress is set aside untouched, the campaigns start fresh, settings stay"] = function(T)
    local _, Meta = load(T)
    local old = { schema = 1, profile = { warmarks = 115, levels = { ["durotar-1"] = { stars = 3 } },
        armory = { frost = 3 } }, run = { runId = "run13", level = "durotar-1" },
        settings = { scale = 1.4, sound = false, speed = 2 }, dev = { probe = { toc = 16001 } } }
    Meta.Prepare(old)
    T.eq(old.schema, Meta.SCHEMA, "now schema " .. Meta.SCHEMA)
    T.eq(old.legacy.profile.warmarks, 115, "old Warmarks kept aside")
    T.eq(old.legacy.profile.levels["durotar-1"].stars, 3, "old stars kept aside")
    T.eq(old.legacy.run.level, "durotar-1", "the old run too")
    T.eq(old.profile.warmarks, 0, "a fresh profile")
    T.eq(old.run, nil, "no run to resume")
    T.eq(old.settings.scale .. "/" .. tostring(old.settings.sound), "1.4/false", "settings kept")
    T.eq(old.settings.story, true, "new settings filled")
    T.eq(old.dev.probe.toc, 16001, "dev data kept")
    Meta.Prepare(old)
    T.eq(old.legacy.profile.warmarks, 115, "a second prepare leaves the legacy alone")
end

tests["stars: 3 for no lives lost, 2 for half or more, 1 for any win"] = function(T)
    local _, Meta = load(T)
    T.eq(Meta.Stars(true, 20, 20), 3, "flawless")
    T.eq(Meta.Stars(true, 10, 20), 2, "half")
    T.eq(Meta.Stars(true, 9, 20), 1, "under half")
    T.eq(Meta.Stars(false, 20, 20), 0, "loss")
end

tests["a result is paid once: first clear, new stars, a quarter for a loss, and a campaign's finale"] = function(T)
    local ns, Meta = load(T)
    local p = Meta.Prepare({}).profile
    local first = assert(Meta.Commit(p, result("run1", true, 12)))
    T.eq(first.stars, 2, "stars")
    T.eq(first.reward.total, 60 + 60 + 2 * 15, "win + first clear + 2 new stars")
    T.eq(p.warmarks, 150, "banked")
    T.eq(Meta.Commit(p, result("run1", true, 12)), nil, "the same run can't pay twice")
    T.eq(p.warmarks, 150, "still 150")
    local better = assert(Meta.Commit(p, result("run2", true, 20)))
    T.eq(better.reward.total, 60 + 15, "no first-clear bonus again; one new star")
    T.eq(p.levels["horde-2"].stars, 3, "best kept")
    Meta.Commit(p, result("run3", true, 5))
    T.eq(p.levels["horde-2"].stars, 3, "a worse win doesn't lower it")
    local loss = assert(Meta.Commit(p, result("run4", false, 0)))
    T.eq(loss.reward.total, 15, "a loss pays 25%")
    T.eq(p.levels["horde-2"].plays, 4, "plays")
    T.eq(p.stats.won .. "/" .. p.stats.lost, "3/1", "stats")
    local heroic = assert(Meta.Commit(p, result("run5", true, 20, { difficulty = "heroic" })))
    T.eq(heroic.reward.total, 90 + 90 + 45, "heroic pays 1.5x, its own first clear and stars")
    T.eq(p.levels["horde-2"].heroicStars, 3, "heroic stars kept apart")
    for i = 6, 80 do Meta.Commit(p, result("run" .. i, false, 0)) end
    T.eq(#p.claimed, Meta.MAX_CLAIMED, "claimed list pruned")
    local camp = ns.Levels.campaignById.horde
    local last = camp.levels[#camp.levels]
    local finale = assert(Meta.Commit(p, result("run99", true, 20, { level = last.id })))
    T.eq(finale.reward.finale, Meta.FINALE_BONUS, "the campaign's last level pays a bonus the first time")
end

tests["unlocks: levels in order, towers and the hero as the campaign goes, campaigns by stars"] = function(T)
    local ns, Meta = load(T)
    local p = Meta.Prepare({}).profile
    T.ok(Meta.LevelUnlocked(p, "horde-1") and Meta.LevelUnlocked(p, "alliance-1"), "two campaigns open at once")
    T.ok(not Meta.LevelUnlocked(p, "horde-2"), "the second level waits")
    T.ok(not Meta.LevelUnlocked(p, "sentinels-1"), "the Sentinels need stars")
    T.ok(not Meta.CampaignUnlocked(p, "forsaken"), "the Forsaken need more")
    T.eq(Meta.LockReason(p, ns.Levels.byId["horde-2"]).level.id, "horde-1", "why: win the level before")
    T.eq(Meta.LockReason(p, ns.Levels.byId["sentinels-1"]).campaignStars, 30, "why: stars")
    local l = Meta.Loadout(p, "normal", "horde-1")
    T.eq(table.concat(l.towers, ","), "headhunter,witchdoctor", "two towers to start")
    T.eq(l.hero, nil, "no hero yet")
    local summary = assert(Meta.Commit(p, { runId = "r1", level = "horde-1", difficulty = "normal", won = true,
        lives = 20, maxLives = 20 }))
    T.ok(Meta.LevelUnlocked(p, "horde-2"), "the second level opens")
    T.eq(summary.opened.levels[1].id, "horde-2", "and the end screen hears of it")
    T.eq(summary.opened.towers[1], "earthshaker", "with the tower that joins there")
    T.ok(Meta.DifficultyUnlocked(p, "horde-1", "heroic"), "heroic at 3 stars")
    local camp = ns.Levels.campaignById.horde
    local q = reached(Meta, ns, "horde", camp.hero.at)
    l = Meta.Loadout(q, "heroic", camp.levels[camp.hero.at].id)
    T.eq(#l.towers, 5, "all five towers by the hero's level")
    T.eq(l.hero, "thrall", "and Thrall")
    T.eq(l.hpPct .. "/" .. l.goldPct, "130/80", "heroic modifiers")
    T.eq(Meta.Loadout(q, "normal", "alliance-1").hero, nil, "the Alliance has its own")
    for _, level in ipairs(ns.Levels.list) do
        if level.campaign ~= "sentinels" then
            p.levels[level.id] = { stars = 3, heroicStars = 0, wins = 1, plays = 1 }
        end
    end
    T.ok(Meta.CampaignUnlocked(p, "sentinels") and Meta.CampaignUnlocked(p, "forsaken"), "stars open the rest")
    T.ok(Meta.LevelUnlocked(p, "sentinels-1"), "and their first levels")
end

tests["sandbox: everything open for trying things out, and closed again without touching progress"] = function(T)
    local _, Meta = load(T)
    local p = Meta.Prepare({}).profile
    T.ok(not Meta.LevelUnlocked(p, "forsaken-8"), "locked")
    p.sandbox = true
    T.ok(Meta.LevelUnlocked(p, "forsaken-8") and Meta.CampaignUnlocked(p, "forsaken"), "open")
    T.ok(Meta.DifficultyUnlocked(p, "forsaken-8", "heroic"), "Heroic too")
    T.ok(Meta.TowerUnlocked(p, "banshee") and Meta.TowerUnlocked(p, "sylvanas"), "towers and heroes")
    T.eq(#Meta.Loadout(p, "normal", "forsaken-1").towers, 5, "the whole roster from level 1")
    p.sandbox = nil
    T.ok(not Meta.LevelUnlocked(p, "forsaken-8"), "closed again")
    T.eq(next(p.levels), nil, "no progress was written")
end

tests["spending: Armory tiers and supplies, each paid once and capped; only towers you have"] = function(T)
    local ns, Meta = load(T)
    local p = reached(Meta, ns, "horde", 5)
    p.warmarks = Meta.ARMORY[1].cost - 1
    T.eq(select(2, Meta.Buy(p, "armory", "headhunter")), "warmarks", "can't afford it")
    T.eq(p.warmarks, Meta.ARMORY[1].cost - 1, "nothing taken")
    p.warmarks = 5000
    local paid = 0
    for tier = 1, 5 do
        local cost = Meta.Buy(p, "armory", "headhunter")
        T.eq(cost, Meta.ARMORY[tier].cost, "tier " .. tier)
        paid = paid + cost
    end
    T.eq(select(2, Meta.Buy(p, "armory", "headhunter")), "max", "five tiers")
    T.eq(p.warmarks, 5000 - paid, "paid " .. paid)
    local l = Meta.Loadout(p, "normal", "horde-3")
    local b = l.bonus.headhunter
    T.eq(b.dmgPct .. "/" .. b.rangePct .. "/" .. b.costPct, "120/110/90", "capped bonuses")
    T.eq(l.specs.headhunter, 2, "both specializations")
    T.eq(l.specs.shaman, nil, "nothing for the shaman")
    T.eq(select(2, Meta.Buy(p, "armory", "banshee")), "locked", "no research on a tower you haven't met")
    T.eq(select(2, Meta.Buy(p, "armory", "thrall")), "unknown", "heroes aren't researched")
    for _ = 1, 3 do Meta.Buy(p, "supply", "gold") end
    for _ = 1, 2 do Meta.Buy(p, "supply", "lives") end
    T.eq(select(2, Meta.Buy(p, "supply", "gold")), "max", "three war chests")
    l = Meta.Loadout(p, "normal", "horde-3")
    T.eq(l.goldPct .. "/" .. l.lives, "115/2", "supplies in the loadout")
    T.eq(Meta.Loadout(p, "heroic", "horde-3").goldPct, math.floor(80 * 115 / 100), "heroic gold with supplies")
end

tests["the economy: a first purchase after the first win, and everything within reach"] = function(T)
    local M = assert(loadfile(T.base .. "/tools/metasim.lua"))("--lib")
    local summary = M.Run(M.Load(T.base))
    T.ok(summary.firstPurchase and summary.firstPurchase <= 2, "first purchase after play " ..
        tostring(summary.firstPurchase))
    T.ok(summary.everything, "everything bought within " .. M.MAX_HOURS .. " hours")
end

return tests
