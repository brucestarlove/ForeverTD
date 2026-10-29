-- Content.lua - the shapes of towers, creeps and campaigns, and the registry the campaign files fill (pure Lua 5.1,
-- no WoW calls). Each campaign (Campaigns\*.lua) brings its own five towers, its hero, its creeps and its levels;
-- Story.lua holds what's said; Levels.lua indexes it all. Balance is a data change; tools/sim.lua plays every level.
--
-- Units, so the engine stays in whole numbers (whole numbers survive SavedVariables exactly):
--   range, splash, speed, shot speed, aura and reveal are in milli-cells (1000 = one 36 px board cell);
--   cd (cooldown), slowTicks, stun and ticks are engine ticks (30 a game second), and dot seconds are game seconds;
--   since 0.4.3 normal speed plays Engine.PACE (2) game seconds a real second, so every time the UI shows (and every
--   time written in a blurb) is half of these: a cd of 60 shows as "every 1.0 s"; dmg and hp are hit points;
--   slow, armor, resist, haste, might, holy, airBonus and pct fields are percentages.
--
-- A tower: { name, role, icon, alt (a fallback icon), damage = "physical" | "magic", air (hits flyers), shot (shot
-- speed), blurb, ranks = { r1, r2, r3 } (ranks[1].cost builds it, ranks[n].cost upgrades to n), specs = { A, B } }.
-- Roles: ranged, control, area, siege and signature; every campaign has one of each, in that order of unlocking
-- (more or less), so a player who learned one campaign can read another.
-- Rank and specialization fields (Engine.lua has the rules): dmg, range, cd, multi, splash, pulse, chain + jump +
-- falloff, slow + slowTicks, stun (after which the creep can't be stunned again for Engine.STEADY ticks),
-- dot = { dmg, seconds }, spread, vuln = { pct, ticks }, bane = { dmg, ticks }, holy, airBonus, bonusVsSlowed,
-- crit = { pct, mult }, misfire, haste/might + aura, reveal, regrow.
-- A specialization is rank 3's numbers with its own changes (name, short, cost, blurb...); the post-pass turns the
-- two into ranks 4 and 5. Armory tiers 3 and 5 open them.
-- A hero: a tower with hero = true, one rank (cost 0), npc (its 3D portrait), and ability = { kind, cd, first, ... }.
--
-- A creep: { name, icon, alt, npc (3D, bosses), hp, speed (milli-cells a tick; 33 is about a cell a second), armor,
-- resist, bounty, lives (lost when it gets through, default 1), air, stealth, undead, demon, boss, size (token
-- pixels, default 24), regen (health a second), heal = { pct, range, every }, split = { creep, count },
-- ability = { kind = "stomp" | "summon" | "blink", every, first, ... }, enrage = { below, pct }, note }.
local _, ns = ...
ns = ns or {}
local Content = { towers = {}, creeps = {}, campaigns = {}, towerOrder = {} }
ns.Content = Content

Content.ICON = "Interface\\Icons\\"
Content.ROLES = { "ranged", "control", "area", "siege", "signature" }
Content.ROLE_NAME = { ranged = "Ranged", control = "Control", area = "Area", siege = "Siege",
    signature = "Signature", hero = "Hero" }

-- A wave group for the level tables: `count` creeps, one every `gap` ticks, starting `delay` ticks into the wave,
-- with `hp` percent health (default 100), on path `path` (default: by type).
function Content.Group(creep, count, gap, delay, hp, path)
    return { creep = creep, count = count, gap = gap, delay = delay or 0, hp = hp or 100, path = path }
end

-- A campaign file registers itself: { id, name, title, faction, color = { r, g, b }, crest (icon), crestAlt, blurb,
-- unlock = nil | { stars = n }, roster = { { kind, joinsAtLevel }, ... }, hero = { kind, at }, levels = { ... } }.
function Content.Campaign(def)
    def.index = #Content.campaigns + 1
    Content.campaigns[def.index] = def
    return def
end

-- Tower-wide fields copied into every rank that doesn't set its own.
local FLAGS = { "damage", "air", "pulse", "shot", "jump", "falloff", "holy", "airBonus" }

local finished = false

-- Called once every campaign file has loaded (Levels.lua does it): every rank carries its tower's flags, ranks 4
-- and 5 are the specializations, each tower knows its campaign, and towerOrder lists every tower by campaign.
function Content.Finish()
    if finished then return end
    finished = true
    for _, tower in pairs(Content.towers) do
        for _, r in ipairs(tower.ranks) do
            for _, k in ipairs(FLAGS) do
                if r[k] == nil then r[k] = tower[k] end
            end
        end
        for i, spec in ipairs(tower.specs or {}) do
            local r = {}
            for k, v in pairs(tower.ranks[3]) do r[k] = v end
            for k, v in pairs(spec) do r[k] = v end
            r.spec = i
            tower.ranks[3 + i] = r
        end
    end
    for _, camp in ipairs(Content.campaigns) do
        camp.towers, camp.joins = {}, {}
        for i, entry in ipairs(camp.roster) do
            local kind = entry[1]
            camp.towers[i], camp.joins[kind] = kind, entry[2]
            Content.towers[kind].campaign = camp.id
            Content.towerOrder[#Content.towerOrder + 1] = kind
        end
        if camp.hero then Content.towers[camp.hero.kind].campaign = camp.id end
    end
end

-- Short words for what makes a creep different, for the wave preview and tooltips.
function Content.Tags(kind)
    local C = Content.creeps[kind]
    local tags = {}
    if C.boss then tags[#tags + 1] = "boss" end
    if C.air then tags[#tags + 1] = "flying" end
    if C.stealth then tags[#tags + 1] = "stealthed" end
    if (C.armor or 0) >= 30 then tags[#tags + 1] = "armoured" end
    if (C.resist or 0) >= 30 then tags[#tags + 1] = "warded" end
    if C.speed >= 50 then tags[#tags + 1] = "fast" end
    if C.undead then tags[#tags + 1] = "undead" end
    if C.demon then tags[#tags + 1] = "demon" end
    if C.regen then tags[#tags + 1] = "regenerates" end
    if C.heal then tags[#tags + 1] = "heals" end
    if C.split then tags[#tags + 1] = "splits" end
    local A = C.ability
    if A then
        tags[#tags + 1] = A.kind == "stomp" and "stuns towers" or A.kind == "summon" and "calls help"
            or A.kind == "blink" and "blinks ahead" or A.kind
    end
    if C.enrage then tags[#tags + 1] = "enrages" end
    return table.concat(tags, ", ")
end

return Content
