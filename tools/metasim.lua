-- tools/metasim.lua - the Warmarks economy over time: a simulated player plays the campaigns and spends as they go.
-- Usage, from the repository folder:   lua tools/metasim.lua
-- It uses the real Meta.lua (rewards, unlocks, prices, purchases) with a simple model of a player, so changing a
-- reward or a price shows its effect on pacing. DESIGN.md section 8's targets: early on, something worth buying
-- every couple of levels; everything bought in roughly 15 hours once the campaign is full size.
local M = {}

local root = ((arg and arg[0] or ""):match("^(.-)[\\/]?tools[\\/]metasim%.lua$") or ".")
if root == "" then root = "." end

M.MINUTES = { short = 3, standard = 6, siege = 8 } -- one attempt, about
M.MAX_HOURS = 40

function M.Load(base)
    local sim = assert(loadfile((base or root) .. "/tools/sim.lua"))("--lib")
    return sim.Load(base or root)
end

-- Average Armory tier over the towers this profile has.
local function Research(ns, profile)
    local sum, n = 0, 0
    for _, kind in ipairs(ns.Content.towerOrder) do
        if ns.Meta.TowerUnlocked(profile, kind) then
            sum, n = sum + ns.Meta.ArmoryTier(profile, kind), n + 1
        end
    end
    return n > 0 and sum / n or 0
end

-- What the player plays next: a new level, then missing Normal stars, then Heroics they can win, else a replay.
local function Choose(ns, profile)
    local Meta, best = ns.Meta, nil
    for _, level in ipairs(ns.Levels.list) do
        local r = profile.levels[level.id]
        if Meta.LevelUnlocked(profile, level) and (not r or r.stars < 3) then return level, "normal" end
    end
    for _, level in ipairs(ns.Levels.list) do
        local r = profile.levels[level.id]
        if Meta.DifficultyUnlocked(profile, level.id, "heroic") and r.heroicStars < 3
            and Research(ns, profile) >= 2 then
            return level, "heroic"
        end
        if Meta.LevelUnlocked(profile, level) then best = level end
    end
    return best, "normal"
end

-- The player's result: Normal is 2 stars the first time and 3 after; Heroic needs research.
local function Outcome(ns, profile, level, difficulty)
    local r = profile.levels[level.id]
    if difficulty == "normal" then return true, (r and r.wins > 0) and 20 or 12 end
    local research = Research(ns, profile)
    if research < 2 then return false, 0 end
    return true, research >= 4 and 20 or research >= 3 and 12 or 5
end

-- Buys the cheapest thing available, again and again, while Warmarks last.
local function Shop(ns, profile)
    local Meta, bought = ns.Meta, {}
    while true do
        local best, bestCost
        for _, kind in ipairs(ns.Content.towerOrder) do
                local cost = Meta.Price(profile, "armory", kind)
            if cost and (not bestCost or cost < bestCost) then best, bestCost = { "armory", kind }, cost end
        end
        for _, s in ipairs(Meta.SUPPLIES) do
            local cost = Meta.Price(profile, "supply", s.key)
            if cost and (not bestCost or cost < bestCost) then best, bestCost = { "supply", s.key }, cost end
        end
        if not best or profile.warmarks < bestCost then return bought, best == nil end
        Meta.Buy(profile, best[1], best[2])
        bought[#bought + 1] = best[1] .. ":" .. best[2]
    end
end

-- Plays until everything is bought (or M.MAX_HOURS). Returns a summary and the per-play log.
function M.Run(ns)
    local Meta = ns.Meta
    local profile = Meta.Prepare({}).profile
    local minutes, plays, log = 0, 0, {}
    local firstPurchase, purchases, done = nil, 0, false
    while minutes < M.MAX_HOURS * 60 and not done do
        local level, difficulty = Choose(ns, profile)
        local won, lives = Outcome(ns, profile, level, difficulty)
        plays = plays + 1
        minutes = minutes + M.MINUTES[level.length]
        local summary = Meta.Commit(profile, { runId = "sim" .. plays, level = level.id, difficulty = difficulty,
            won = won, lives = lives, maxLives = 20, kills = 0 })
        local bought
        bought, done = Shop(ns, profile)
        purchases = purchases + #bought
        if #bought > 0 and not firstPurchase then firstPurchase = plays end
        log[#log + 1] = string.format("%5.1f h  play %3d  %-12s %-6s %-4s +%3d Warmarks (%4d left)  %s",
            minutes / 60, plays, level.id, difficulty, won and "won" or "lost", summary.reward.total,
            profile.warmarks, table.concat(bought, " "))
    end
    return { hours = minutes / 60, plays = plays, purchases = purchases, firstPurchase = firstPurchase,
        everything = done, profile = profile }, log
end

local args = { ... }
if args[1] == "--lib" then return M end

local summary, log = M.Run(M.Load())
for _, line in ipairs(log) do print(line) end
print(string.format("\n%d purchases; first after play %s; %s after %.1f hours (%d plays).", summary.purchases,
    tostring(summary.firstPurchase), summary.everything and "everything bought" or "NOT everything bought",
    summary.hours, summary.plays))
