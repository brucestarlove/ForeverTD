-- Levels.lua - the index of every campaign's levels (pure Lua 5.1, no WoW calls). The levels themselves are data in
-- the campaign files (Campaigns\*.lua); this file finishes the content, numbers the levels in campaign order and
-- attaches their story (Story.lua). Tests check every level with Engine.ValidateLevel, and tools/sim.lua proves
-- each one winnable on Normal with the research the balance assumes, and by good play with none.
--
-- A level:
--   id         "horde-3": the campaign and its place in it (records in the save are keyed by it)
--   zone       the place, for titles ("Durotar"); name ("Sen'jin Village")
--   map        uiMapID of the zone whose painted map is the board (Durotar 1411...); parchment if the client lacks it
--   length     "short" (6 waves), "standard" (10) or "siege" (15): sets the Warmarks reward (Meta.lua)
--   art        the board's picture. With `map` set, a crop of that zone's map art, as fractions of the art's width
--              and height: { left, top, width } (the crop is 0.9375 x width tall, so top + 0.9375 x width <= 1). Or
--              your own image, stretched over the board: { file = "Interface\\AddOns\\ForeverTD\\Media\\name" }
--              (PNG/TGA/JPG; new files need a client restart), with optional coords = { left, right, top, bottom }
--              (0..1). dim = 0..1 darkens it (default 0.18).
--   cols, rows the grid (16 x 10 fits the window)
--   paths[i]   waypoints as { col, row } cell coordinates; 0 or cols+1 starts or ends just off the board. Ground paths
--              must run in straight lines along rows or columns (the road); `air = true` paths fly anywhere and leave
--              the cells below free to build on.
--   airPath    which path flying creeps take (needed when a wave has flyers)
--   blocked    cells nothing can be built on, { { col, row }, ... }
--   gold, lives, earlyBonus (gold for calling a wave early), waveBonus = { base, step } (gold when a wave clears)
--   waves[i]   a list of groups, Content.Group(creep, count, gap, delay, hp, path): `count` creeps, one every `gap`
--              ticks, starting `delay` ticks into the wave, on path `path` (default: by type).
--   creep health, in three layers that multiply (each a whole percent, 100 unless set; Engine.GroupHpPct):
--              `waves.hp`, the whole level's (the knob for "this level is too easy": tools/sim.lua --scale);
--              each wave's `hp`, its place in the level's climb (tools/sim.lua --shape keeps each wave in its band);
--              and a group's `hp` (G's fifth number), only where a group is meant to differ from its wave (a boss).
--   unlock     extra gates beyond "win the previous level": { stars = n } (n stars in total)
-- Levels.lua adds: campaign (its id), number (1, 2... within it), index (in Levels.list), story (Story.lua).
local _, ns = ...
ns = ns or {}
local Content = ns.Content
local Levels = {}
ns.Levels = Levels

Content.Finish()

local Story = ns.Story or { campaigns = {}, levels = {} }
Levels.list, Levels.byId, Levels.campaigns, Levels.campaignById = {}, {}, Content.campaigns, {}
for _, camp in ipairs(Content.campaigns) do
    Levels.campaignById[camp.id] = camp
    camp.story = Story.campaigns[camp.id] or {}
    for n, level in ipairs(camp.levels) do
        level.campaign, level.number = camp.id, n
        level.index = #Levels.list + 1
        Levels.list[level.index] = level
        Levels.byId[level.id] = level
        level.story = Story.levels[level.id] or {}
    end
end

function Levels.Campaign(level) return level and Levels.campaignById[level.campaign] end

-- The next level in the same campaign, or nil after its finale.
function Levels.Next(level)
    local camp = Levels.Campaign(level)
    return camp and camp.levels[level.number + 1]
end

-- The level before it in its campaign, or nil for the first.
function Levels.Previous(level)
    local camp = Levels.Campaign(level)
    return camp and level.number > 1 and camp.levels[level.number - 1] or nil
end

-- The tower kinds that join a campaign at this level ("new tower!"), in roster order.
function Levels.NewTowers(level)
    local camp, list = Levels.Campaign(level), {}
    for _, kind in ipairs(camp.towers) do
        if camp.joins[kind] == level.number then list[#list + 1] = kind end
    end
    return list
end

-- The creep kinds met for the first time in this campaign at this level, in the order they appear.
function Levels.NewCreeps(level)
    local camp, seen, list = Levels.Campaign(level), {}, {}
    for n = 1, level.number - 1 do
        for _, wave in ipairs(camp.levels[n].waves) do
            for _, grp in ipairs(wave) do seen[grp.creep] = true end
        end
    end
    for _, wave in ipairs(level.waves) do
        for _, grp in ipairs(wave) do
            if not seen[grp.creep] then
                seen[grp.creep] = true
                list[#list + 1] = grp.creep
            end
        end
    end
    return list
end

-- The level's boss (its creep kind): the last one to come, so a mid-level boss doesn't take the credit. Or nil.
function Levels.Boss(level)
    local boss
    for _, wave in ipairs(level.waves) do
        for _, grp in ipairs(wave) do
            if Content.creeps[grp.creep] and Content.creeps[grp.creep].boss then boss = grp.creep end
        end
    end
    return boss
end

return Levels
