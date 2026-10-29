-- Meta.lua - the save file and the progress between levels, in pure Lua 5.1 (no WoW calls): the profile, stars,
-- Warmarks, what's unlocked, prices and loadouts. Warmarks buy Armory research (per tower) and Supplies.
--
-- Progress through a campaign opens its levels one after another; a campaign's towers and hero join at the level
-- its roster says, so every campaign starts with two towers and grows. Campaigns open by stars in total.
--
-- ForeverTDDB (the SavedVariables table) after Meta.Prepare:
--   schema    Meta.SCHEMA
--   profile   warmarks, runs (a counter for run IDs), claimed (recent run IDs already paid, oldest first),
--             levels[id] = { stars, heroicStars, wins, plays }, stats, armory[kind] = research tier 0-5,
--             supplies = { gold = 0-3, lives = 0-2 }, seen[levelId] = true once its briefing was shown,
--             sandbox (true: every campaign, level, tower and Heroic open, for trying things out; /td sandbox)
--   run       the level in progress, or nil: { runId, level, difficulty, loadout, snapshot (Engine.Snapshot) }
--   settings  speed (1 or 2; since 0.4.3 1x is the old 2x: Engine.PACE), sound, autoWaves, story, effects
--             (booleans), scale (window size, 0.6-1.6), paced (true once a speed saved before 0.4.3 was mapped)
--   legacy    0.1-0.3's profile and run, set aside untouched when this version first loads (schema 1 saves)
--   dev       the dev tools' data (Dev/Dev.lua owns it; Meta never touches it)
local _, ns = ...
ns = ns or {}
local Content, Levels = ns.Content, ns.Levels
local Meta = {}
ns.Meta = Meta

Meta.SCHEMA = 2 -- 1 was 0.1-0.3 (three zones, one shared tower list)
Meta.MAX_CLAIMED = 50
Meta.DIFFICULTY = {
    normal = { name = "Normal", hpPct = 100, goldPct = 100 },
    heroic = { name = "Heroic", hpPct = 130, goldPct = 80, rewardPct = 150 },
}
Meta.REWARD = { short = 30, standard = 60, siege = 90 } -- Warmarks for a win, by level length
Meta.STAR_REWARD = 15                                  -- per star earned for the first time
Meta.LOSS_PCT = 25                                     -- a loss still pays a quarter of a win
Meta.FINALE_BONUS = 100                                -- the first win of a campaign's last level

local DEFAULTS = {
    profile = {
        warmarks = 0, runs = 0, claimed = {}, levels = {}, stats = { won = 0, lost = 0, kills = 0 }, armory = {},
        supplies = { gold = 0, lives = 0 }, seen = {},
    },
    settings = { speed = 1, sound = true, autoWaves = false, story = true, effects = true, scale = 1,
        paced = true },
}

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            Fill(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

-- Brings a saved table up to the current schema, in place, keeping everything it doesn't own (the dev data).
-- Returns db, or nil and a reason when the file comes from a newer version (then nothing should write to it).
function Meta.Prepare(db)
    if type(db) ~= "table" then return nil, "missing" end
    local schema = tonumber(db.schema) or 0
    if schema > Meta.SCHEMA then return nil, "newer" end
    if schema < 1 then
        db.save = nil -- the starter toy's game (0.0.x); its board can't become a level
    end
    if schema == 1 then
        -- 0.1-0.3: three zones and one tower list. The campaigns start fresh; the old progress is kept aside.
        if type(db.profile) == "table" or type(db.run) == "table" then
            db.legacy = { schema = 1, profile = db.profile, run = db.run }
        end
        db.profile, db.run = nil, nil
    end
    if type(db.settings) == "table" and db.settings.paced == nil then
        db.settings.speed = 1 -- 0.4.3: normal speed is the old 2x, so an old 2x (or 1x) becomes the new 1x
    end
    if type(db.settings) == "table" then db.settings.keys = nil end -- 0.4.8: no keys, so no setting for them
    db.schema = Meta.SCHEMA
    Fill(db, DEFAULTS)
    if db.run ~= nil and type(db.run) ~= "table" then db.run = nil end
    return db
end

function Meta.Record(profile, levelId)
    local r = profile.levels[levelId]
    if not r then
        r = { stars = 0, heroicStars = 0, wins = 0, plays = 0 }
        profile.levels[levelId] = r
    end
    return r
end

function Meta.TotalStars(profile)
    local n = 0
    for _, level in ipairs(Levels.list) do
        local r = profile.levels[level.id]
        if r then n = n + (r.stars or 0) + (r.heroicStars or 0) end
    end
    return n
end

-- Stars in a campaign: Normal, Heroic, and the most there are of each.
function Meta.CampaignStars(profile, camp)
    local normal, heroic = 0, 0
    for _, level in ipairs(camp.levels) do
        local r = profile.levels[level.id]
        if r then normal, heroic = normal + (r.stars or 0), heroic + (r.heroicStars or 0) end
    end
    return normal, heroic, 3 * #camp.levels
end

-- 3 stars: no lives lost. 2: at least half left. 1: any win.
function Meta.Stars(won, lives, maxLives)
    if not won then return 0 end
    if lives >= maxLives then return 3 end
    if lives * 2 >= maxLives then return 2 end
    return 1
end

function Meta.Cleared(profile, levelId)
    local r = profile.levels[levelId]
    return r ~= nil and (r.stars or 0) > 0
end

function Meta.CampaignUnlocked(profile, camp)
    if type(camp) == "string" then camp = Levels.campaignById[camp] end
    if not camp then return false end
    if profile.sandbox then return true end
    local u = camp.unlock
    return not (u and u.stars and Meta.TotalStars(profile) < u.stars)
end

-- A level opens once its campaign is open and the level before it is won (and any extra gate it has).
function Meta.LevelUnlocked(profile, level)
    if type(level) == "string" then level = Levels.byId[level] end
    if not level then return false end
    if profile.sandbox then return true end
    if not Meta.CampaignUnlocked(profile, level.campaign) then return false end
    local previous = Levels.Previous(level)
    if previous and not Meta.Cleared(profile, previous.id) then return false end
    local u = level.unlock
    if u and u.stars and Meta.TotalStars(profile) < u.stars then return false end
    return true
end

-- Why a level is locked, as data: { campaignStars = n } or { level = previousLevel } or { stars = n }, or nil.
function Meta.LockReason(profile, level)
    local camp = Levels.Campaign(level)
    if not Meta.CampaignUnlocked(profile, camp) then return { campaignStars = camp.unlock.stars } end
    local previous = Levels.Previous(level)
    if previous and not Meta.Cleared(profile, previous.id) then return { level = previous } end
    if level.unlock and level.unlock.stars and Meta.TotalStars(profile) < level.unlock.stars then
        return { stars = level.unlock.stars }
    end
end

-- Heroic opens with 3 stars on Normal.
function Meta.DifficultyUnlocked(profile, levelId, difficulty)
    if difficulty == "normal" then return Meta.LevelUnlocked(profile, levelId) end
    if difficulty == "heroic" then
        if profile.sandbox then return Levels.byId[levelId] ~= nil end
        local r = profile.levels[levelId]
        return r ~= nil and (r.stars or 0) >= 3
    end
    return false
end

-- A tower (or hero) is yours once you reach the level of its campaign that it joins at.
function Meta.TowerUnlocked(profile, kind)
    local tower = Content.towers[kind]
    if not tower then return false end
    local camp = Levels.campaignById[tower.campaign]
    if not camp then return false end
    local at = tower.hero and camp.hero.at or camp.joins[kind]
    local level = at and camp.levels[at]
    return level ~= nil and Meta.LevelUnlocked(profile, level)
end

-- The first level of a campaign not yet won (or its last), for the menu to open on.
function Meta.NextLevel(profile, camp)
    for _, level in ipairs(camp.levels) do
        if not Meta.Cleared(profile, level.id) then return level end
    end
    return camp.levels[#camp.levels]
end

-- The Armory: five research tiers per tower. Small stat steps, capped (+20% damage, +10% range, -10% build
-- cost in all), and the two specializations at tiers 3 and 5. Normal's later levels expect a little of it (a tier or
-- two: tools/sim.lua's M.RESEARCH), and good play wins every level with none.
Meta.ARMORY = {
    { cost = 30, dmgPct = 10, text = "+10% damage" },
    { cost = 60, rangePct = 10, text = "+10% range" },
    { cost = 120, spec = 1 },
    { cost = 200, dmgPct = 10, costPct = -10, text = "+10% damage, -10% build cost" },
    { cost = 320, spec = 2 },
}

-- Supplies (DESIGN.md's Quartermaster): small conveniences for every campaign, capped.
Meta.SUPPLIES = {
    { key = "gold", name = "War Chest", costs = { 100, 200, 300 }, step = 5, icon = "INV_Misc_Coin_02",
        text = "+5% starting gold in every level" },
    { key = "lives", name = "Militia", costs = { 150, 300 }, step = 1, icon = "INV_Sword_04",
        text = "+1 life in every level" },
}
local SUPPLY = {}
for _, s in ipairs(Meta.SUPPLIES) do SUPPLY[s.key] = s end

function Meta.ArmoryTier(profile, kind) return profile.armory[kind] or 0 end

-- What a tier gives, in words: the tier's text, or its specialization's name and blurb.
function Meta.TierText(kind, tier)
    local t = Meta.ARMORY[tier]
    if t.spec then
        local spec = Content.towers[kind].specs and Content.towers[kind].specs[t.spec]
        return spec and ("Specialization: " .. spec.name) or "Specialization", spec and spec.blurb or ""
    end
    return t.text, ""
end

-- The price of the next step of something, or nil and why not: ("armory", kind) or ("supply", key).
function Meta.Price(profile, what, key)
    if what == "armory" then
        local tower = Content.towers[key]
        if not tower or tower.hero then return nil, "unknown" end
        if not Meta.TowerUnlocked(profile, key) then return nil, "locked" end
        local next = Meta.ARMORY[Meta.ArmoryTier(profile, key) + 1]
        if not next then return nil, "max" end
        return next.cost
    elseif what == "supply" then
        local s = SUPPLY[key]
        if not s then return nil, "unknown" end
        local cost = s.costs[(profile.supplies[key] or 0) + 1]
        if not cost then return nil, "max" end
        return cost
    end
    return nil, "unknown"
end

-- Spends Warmarks on one step. Returns the cost, or nil and a reason ("warmarks", "max", "locked", "unknown").
function Meta.Buy(profile, what, key)
    local cost, why = Meta.Price(profile, what, key)
    if not cost then return nil, why end
    if profile.warmarks < cost then return nil, "warmarks" end
    profile.warmarks = profile.warmarks - cost
    if what == "armory" then
        profile.armory[key] = Meta.ArmoryTier(profile, key) + 1
    else
        profile.supplies[key] = (profile.supplies[key] or 0) + 1
    end
    return cost
end

-- What a run of `levelId` starts with: its campaign's towers this profile has reached (in roster order), the hero
-- if he or she has joined, the difficulty's modifiers, research bonuses (bonus[kind] = { dmgPct, rangePct,
-- costPct }), opened specializations (specs[kind] = 0-2) and supplies.
function Meta.Loadout(profile, difficulty, levelId)
    local d = Meta.DIFFICULTY[difficulty] or Meta.DIFFICULTY.normal
    local level = Levels.byId[levelId]
    local camp = Levels.Campaign(level)
    local towers, bonus, specs, hero = {}, {}, {}, nil
    for _, kind in ipairs(camp and camp.towers or {}) do
        if Meta.TowerUnlocked(profile, kind) then towers[#towers + 1] = kind end
        local b = { dmgPct = 100, rangePct = 100, costPct = 100 }
        for tier = 1, Meta.ArmoryTier(profile, kind) do
            local t = Meta.ARMORY[tier]
            b.dmgPct = b.dmgPct + (t.dmgPct or 0)
            b.rangePct = b.rangePct + (t.rangePct or 0)
            b.costPct = b.costPct + (t.costPct or 0)
            if t.spec then specs[kind] = t.spec end
        end
        bonus[kind] = b
    end
    if camp and camp.hero and Meta.TowerUnlocked(profile, camp.hero.kind) then hero = camp.hero.kind end
    local supplies = profile.supplies
    return { towers = towers, hero = hero, difficulty = Meta.DIFFICULTY[difficulty] and difficulty or "normal",
        hpPct = d.hpPct, goldPct = math.floor(d.goldPct * (100 + SUPPLY.gold.step * (supplies.gold or 0)) / 100),
        lives = SUPPLY.lives.step * (supplies.lives or 0), bonus = bonus, specs = specs }
end

function Meta.NewRunId(profile)
    profile.runs = (profile.runs or 0) + 1
    return "run" .. profile.runs
end

local function Claimed(profile, runId)
    for _, id in ipairs(profile.claimed) do
        if id == runId then return true end
    end
    return false
end

-- Warmarks for a result, and why: { total, base, firstClear, starBonus, finale }.
function Meta.Reward(level, difficulty, won, stars, previousStars)
    local d = Meta.DIFFICULTY[difficulty] or Meta.DIFFICULTY.normal
    local base = math.floor((Meta.REWARD[level.length] or Meta.REWARD.standard) * (d.rewardPct or 100) / 100)
    if not won then
        local total = math.floor(base * Meta.LOSS_PCT / 100)
        return { total = total, base = total, firstClear = 0, starBonus = 0, finale = 0 }
    end
    local firstClear = previousStars == 0 and base or 0
    local starBonus = math.max(0, stars - previousStars) * Meta.STAR_REWARD
    local camp = Levels.Campaign(level)
    local finale = (firstClear > 0 and difficulty ~= "heroic" and camp and camp.levels[#camp.levels] == level)
        and Meta.FINALE_BONUS or 0
    return { total = base + firstClear + starBonus + finale, base = base, firstClear = firstClear,
        starBonus = starBonus, finale = finale }
end

-- Writes a finished run into the profile, once: a second call with the same runId changes nothing and returns nil,
-- "claimed" (a reload in the middle can't pay twice). result = { runId, level, difficulty, won, lives, maxLives,
-- kills }. Returns a summary for the end screen: { stars, previousStars, reward, newBest, opened }, where opened
-- lists what this result unlocked: { levels = { level }, towers = { kind }, campaigns = { camp } }.
function Meta.Commit(profile, result)
    local level = Levels.byId[result.level]
    if not level then return nil, "level" end
    if not result.runId or Claimed(profile, result.runId) then return nil, "claimed" end
    local before = Meta.Openings(profile)
    local claimed = profile.claimed
    claimed[#claimed + 1] = result.runId
    while #claimed > Meta.MAX_CLAIMED do table.remove(claimed, 1) end
    local record = Meta.Record(profile, level.id)
    local field = result.difficulty == "heroic" and "heroicStars" or "stars"
    local previous = record[field] or 0
    local stars = Meta.Stars(result.won, result.lives, result.maxLives)
    local reward = Meta.Reward(level, result.difficulty, result.won, stars, previous)
    record.plays = record.plays + 1
    if result.won then record.wins = record.wins + 1 end
    if stars > previous then record[field] = stars end
    profile.warmarks = profile.warmarks + reward.total
    local s = profile.stats
    if result.won then s.won = s.won + 1 else s.lost = s.lost + 1 end
    s.kills = s.kills + (result.kills or 0)
    return { stars = stars, previousStars = previous, reward = reward, newBest = stars > previous,
        opened = Meta.Opened(before, Meta.Openings(profile)) }
end

-- Everything open right now (levels, towers, campaigns), as sets, so Commit can say what a result unlocked.
function Meta.Openings(profile)
    local o = { levels = {}, towers = {}, campaigns = {} }
    for _, camp in ipairs(Levels.campaigns) do
        if Meta.CampaignUnlocked(profile, camp) then o.campaigns[camp.id] = true end
        for _, level in ipairs(camp.levels) do
            if Meta.LevelUnlocked(profile, level) then o.levels[level.id] = true end
        end
        for _, kind in ipairs(camp.towers) do
            if Meta.TowerUnlocked(profile, kind) then o.towers[kind] = true end
        end
        if camp.hero and Meta.TowerUnlocked(profile, camp.hero.kind) then o.towers[camp.hero.kind] = true end
    end
    return o
end

function Meta.Opened(before, after)
    local opened = { levels = {}, towers = {}, campaigns = {} }
    for _, camp in ipairs(Levels.campaigns) do
        if after.campaigns[camp.id] and not before.campaigns[camp.id] then
            opened.campaigns[#opened.campaigns + 1] = camp
        end
        for _, level in ipairs(camp.levels) do
            if after.levels[level.id] and not before.levels[level.id] then opened.levels[#opened.levels + 1] = level end
        end
        local kinds = {}
        for _, kind in ipairs(camp.towers) do kinds[#kinds + 1] = kind end
        if camp.hero then kinds[#kinds + 1] = camp.hero.kind end
        for _, kind in ipairs(kinds) do
            if after.towers[kind] and not before.towers[kind] then opened.towers[#opened.towers + 1] = kind end
        end
    end
    return opened
end

return Meta
