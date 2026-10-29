-- Campaigns\Sentinels.lua - The Sentinels: "Wrath of the Wild". Teldrassil, Darkshore and Ashenvale, down to
-- Blackfathom Deeps. Corruption creeps through the night elves' forests: satyrs in the shadows, the Twilight's
-- Hammer on the shore, and the Warsong Clan's axes in Ashenvale. Sentinel archers, dryads, moonwells, ancients and
-- the druids of the talon answer, with Tyrande Whisperwind. The words are in Story.lua. Names and numbers are drafts.
local _, ns = ...
local Content = ns.Content
local ICON, G = Content.ICON, Content.Group
local T, C = Content.towers, Content.creeps

------------------------------------------------------------------------------------------------------------------------
-- Towers

T.archer = {
    name = "Sentinel Archer", role = "ranged", icon = ICON .. "Ability_UpgradeMoonGlaive", damage = "physical",
    air = true, shot = 450,
    blurb = "Heavy single arrows. Hits flying creeps.",
    ranks = {
        { cost = 50, dmg = 11, range = 2300, cd = 32 },
        { cost = 45, dmg = 17, range = 2400, cd = 28 },
        { cost = 80, dmg = 27, range = 2500, cd = 24 },
    },
    specs = {
        { name = "Trueshot", cost = 120, dmg = 33, range = 2700, crit = { pct = 25, mult = 250 },
            blurb = "A little more reach, and one arrow in four is a critical hit for 2.5x damage." },
        { name = "Moonglaive", cost = 140, dmg = 24, chain = 3, jump = 1500, falloff = 80,
            blurb = "Glaives that bounce to three more creeps." },
    },
}

T.dryad = {
    name = "Dryad", role = "control", icon = ICON .. "Spell_Nature_StrangleVines",
    alt = ICON .. "Spell_Nature_Regeneration",
    damage = "magic", air = true, shot = 350,
    blurb = "Slow Poison: spears that slow and poison. Hits flying creeps.",
    ranks = {
        { cost = 75, dmg = 6, range = 2200, cd = 28, slow = 30, slowTicks = 75, dot = { dmg = 2, seconds = 3 } },
        { cost = 55, dmg = 10, range = 2300, cd = 26, slow = 40, slowTicks = 80, dot = { dmg = 3, seconds = 3 } },
        { cost = 90, dmg = 15, range = 2400, cd = 24, slow = 50, slowTicks = 90, dot = { dmg = 5, seconds = 3 } },
    },
    specs = {
        { name = "Entangling Roots", short = "Roots", cost = 130, dmg = 40, cd = 60, stun = 30,
            blurb = "Slower, heavier spears that root their target: it can't move for half a second." },
        { name = "Envenom", cost = 140, dot = { dmg = 12, seconds = 4 }, slow = 55,
            blurb = "A stronger poison: 48 more damage over 2 seconds." },
    },
}

T.moonwell = {
    name = "Moonwell", role = "area", icon = ICON .. "Spell_Nature_StarFall", damage = "magic", pulse = true,
    air = true,
    blurb = "Pulses of moonlight that hurt every creep near it, flyers too.",
    ranks = {
        { cost = 95, dmg = 7, range = 1600, cd = 36 },
        { cost = 70, dmg = 12, range = 1700, cd = 34 },
        { cost = 110, dmg = 19, range = 1800, cd = 30 },
    },
    specs = {
        { name = "Moonfire", cost = 140, dmg = 30, reveal = 1800,
            blurb = "A brighter pulse, and its light reveals stealthed creeps." },
        { name = "Rejuvenation", short = "Rejuvenate", cost = 130, regrow = 3,
            blurb = "Each wave you clear restores a life, up to three a level." },
    },
}

T.ancient = {
    name = "Ancient Protector", role = "siege", icon = ICON .. "Spell_Nature_Thorns",
    alt = ICON .. "Spell_Nature_Regeneration",
    damage = "physical", shot = 140,
    blurb = "An ancient that hurls boulders. Splash; ground only.",
    ranks = {
        { cost = 105, dmg = 23, range = 2600, cd = 58, splash = 1050 },
        { cost = 80, dmg = 36, range = 2700, cd = 54, splash = 1150 },
        { cost = 130, dmg = 56, range = 2800, cd = 50, splash = 1350 },
    },
    specs = {
        { name = "Ancient of War", short = "Of War", cost = 150, dmg = 120, splash = 1700, cd = 64,
            blurb = "Huge boulders that crush a wide area." },
        { name = "Rootgrasp", cost = 140, dmg = 60, stun = 30, slow = 40, slowTicks = 60,
            blurb = "Roots the creep it hits for half a second, and slows everything it splashes." },
    },
}

T.talon = {
    name = "Druid of the Talon", role = "signature", icon = ICON .. "Spell_Nature_FaerieFire",
    alt = ICON .. "Spell_Nature_StarFall", damage = "magic", air = true, shot = 450,
    blurb = "Faerie Fire: creeps it hits take 25% more damage from everything. Reveals stealthed creeps near it. "
        .. "Hits flying creeps.",
    ranks = {
        { cost = 100, dmg = 6, range = 2300, cd = 24, vuln = { pct = 25, ticks = 120 }, reveal = 2300 },
        { cost = 75, dmg = 10, range = 2400, cd = 22, vuln = { pct = 25, ticks = 120 }, reveal = 2400 },
        { cost = 120, dmg = 16, range = 2500, cd = 20, vuln = { pct = 30, ticks = 150 }, reveal = 2500 },
    },
    specs = {
        { name = "Cyclone", cost = 140, dmg = 20, cd = 40, stun = 45,
            blurb = "Lifts its target in a cyclone: helpless for 0.75 seconds." },
        { name = "Faerie Swarm", short = "Swarm", cost = 140, multi = 3,
            blurb = "Faerie Fire on three creeps at once." },
    },
}

T.tyrande = {
    name = "Tyrande Whisperwind", role = "hero", hero = true, npc = 7999, icon = ICON .. "Ability_Mount_WhiteTiger",
    alt = ICON .. "Ability_TrueShot", damage = "physical", air = true, shot = 500,
    blurb = "High Priestess of Elune. Towers near her hit 10% harder.",
    ranks = { { cost = 0, dmg = 14, range = 2600, cd = 18, might = 10, aura = 2500 } },
    ability = { kind = "starfall", name = "Starfall", range = 3000, dmg = 25, every = 30, ticks = 150, cd = 10800,
        first = 300, blurb = "Stars fall on every creep within 3 cells of Tyrande, twice a second for 2.5 seconds." },
}

------------------------------------------------------------------------------------------------------------------------
-- Creeps

local FLY = "Flying: only towers that hit air can reach it."
local ARMOUR = "Armoured: physical hits do half damage."
local STEALTH = "Stealthed: towers can't see it unless a revealing tower is near."

C.grell = { name = "Grellkin", icon = ICON .. "Spell_Nature_NatureTouchDecay",
    alt = ICON .. "Spell_Nature_Regeneration",
    hp = 14, speed = 36, bounty = 1, size = 18, note = "Fel-tainted sprites: weak, but many." }
C.nightsaber = { name = "Nightsaber", icon = ICON .. "Ability_Druid_CatForm", alt = ICON .. "Ability_Hunter_Pet_Wolf",
    hp = 26, speed = 48, bounty = 4, note = "Fast." }
C.furbolg = { name = "Gnarlpine Mystic", icon = ICON .. "Ability_Hunter_Pet_Bear",
    hp = 44, speed = 25, bounty = 6, heal = { pct = 8, range = 1600, every = 75 },
    note = "Healer: mends creeps around it. Kill it first." }
C.timberling = { name = "Timberling", icon = ICON .. "Spell_Nature_Regeneration",
    hp = 60, speed = 24, resist = 30, regen = 4, bounty = 5, note = "Warded and regenerates." }
C.owl = { name = "Strigid Owl", icon = ICON .. "Ability_Hunter_Pet_Owl", alt = ICON .. "Ability_Hunter_Pet_Vulture",
    air = true, hp = 24, speed = 40, bounty = 5, note = FLY }
C.spider = { name = "Webwood Lurker", npc = 30, icon = ICON .. "Ability_Hunter_Pet_Spider",
    hp = 48, speed = 25, bounty = 3, split = { creep = "spiderling", count = 3 },
    note = "Splits into three hatchlings when killed." }
C.spiderling = { name = "Webwood Hatchling", icon = ICON .. "Ability_Hunter_Pet_Spider",
    hp = 12, speed = 37, bounty = 1, size = 16 }
C.ursal = { name = "Ursal the Mauler", npc = 2039, icon = ICON .. "Ability_Hunter_Pet_Bear", boss = true,
    hp = 1300, speed = 16, armor = 30, resist = 10, bounty = 100, lives = 10, size = 36,
    heal = { pct = 4, range = 2000, every = 90 }, note = "Boss. Heals creeps around him." }

C.satyr = { name = "Satyr Shadowstalker", icon = ICON .. "Spell_Shadow_SummonFelHunter",
    alt = ICON .. "Spell_Shadow_ShadowBolt", stealth = true, demon = true, hp = 42, speed = 34, bounty = 6,
    note = "A demon in the shadows. " .. STEALTH }
C.melenas = { name = "Lord Melenas", npc = 2038, icon = ICON .. "Spell_Shadow_SummonFelHunter",
    alt = ICON .. "Spell_Shadow_ShadowBolt", boss = true, demon = true, hp = 1200, speed = 17, resist = 30,
    bounty = 80, lives = 10, size = 34,
    ability = { kind = "summon", creep = "satyr", count = 2, every = 300, first = 150 },
    note = "Boss. The satyr lord of Fel Rock calls stealthed satyrs." }

C.blackwood = { name = "Blackwood Pathfinder", icon = ICON .. "Ability_Hunter_Pet_Bear", hp = 48, speed = 28,
    armor = 20, bounty = 4, note = "A corrupted furbolg." }
C.greymist = { name = "Greymist Murloc", icon = ICON .. "INV_Misc_Head_Murloc_01", hp = 15, speed = 36, bounty = 1,
    size = 20, note = "Swarm: weak, but many." }
C.crawler = { name = "Encrusted Tide Crawler", icon = ICON .. "Ability_Hunter_Pet_Crab",
    alt = ICON .. "Ability_Hunter_Pet_Scorpid", hp = 52, speed = 22, armor = 55, bounty = 5, note = ARMOUR }
C.murkdeep = { name = "Murkdeep", npc = 10323, icon = ICON .. "INV_Misc_Head_Murloc_01", boss = true,
    hp = 1300, speed = 17, armor = 30, bounty = 80, lives = 10, size = 32,
    ability = { kind = "summon", creep = "greymist", count = 4, every = 300, first = 150 },
    note = "Boss. The murloc chieftain calls his tribe." }

C.twilight = { name = "Twilight Disciple", icon = ICON .. "Spell_Shadow_Twilight",
    alt = ICON .. "Spell_Shadow_ShadowBolt",
    hp = 44, speed = 27, resist = 50, bounty = 6, heal = { pct = 6, range = 1500, every = 90 },
    note = "Warded, and heals creeps around it." }
C.highborne = { name = "Cursed Highborne", icon = ICON .. "Spell_Shadow_DetectInvisibility",
    alt = ICON .. "Spell_Frost_FrostNova", air = true, hp = 34, speed = 36, resist = 40, bounty = 6,
    note = "A drifting ghost: flying and warded." }
C.delmanis = { name = "Delmanis the Hated", npc = 3662, icon = ICON .. "Spell_Shadow_ShadowWordPain",
    alt = ICON .. "Spell_Shadow_ShadowBolt", boss = true, hp = 1500, speed = 16, resist = 40, bounty = 90, lives = 10,
    size = 34, ability = { kind = "blink", every = 330, first = 240, distance = 2500 },
    note = "Boss. A Twilight's Hammer warlock who blinks ahead along the road." }

C.grunt = { name = "Warsong Grunt", icon = ICON .. "INV_Misc_Head_Orc_01", alt = ICON .. "INV_Sword_04",
    hp = 70, speed = 27, armor = 40, bounty = 5, note = ARMOUR }
C.outrider = { name = "Warsong Outrider", icon = ICON .. "Ability_Mount_BlackDireWolf",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", hp = 40, speed = 46, bounty = 5, note = "Wolf riders: fast." }
C.windrider = { name = "Wind Rider", icon = ICON .. "Ability_Hunter_Pet_WindSerpent",
    alt = ICON .. "Ability_Hunter_Pet_Vulture", air = true, hp = 38, speed = 40, bounty = 6, note = FLY }
C.logshredder = { name = "Warsong Shredder", icon = ICON .. "INV_Misc_Gear_01", alt = ICON .. "Ability_Warrior_Sunder",
    hp = 150, speed = 17, armor = 60, bounty = 10, size = 30, note = "A logging machine: heavily armoured." }
C.overlord = { name = "Warsong Overlord", icon = ICON .. "INV_Misc_Head_Orc_01", alt = ICON .. "INV_Sword_04",
    boss = true, hp = 2200, speed = 16, armor = 40, bounty = 110, lives = 15, size = 36,
    ability = { kind = "stomp", every = 330, first = 200, range = 2000, ticks = 60 },
    enrage = { below = 40, pct = 150 },
    note = "Boss. His war stomp stuns towers, and he enrages when hurt." }

C.naga = { name = "Blackfathom Tide Priestess", icon = ICON .. "INV_Misc_Fish_14",
    alt = ICON .. "Spell_Frost_FrostBolt02",
    hp = 46, speed = 26, resist = 40, bounty = 6, heal = { pct = 8, range = 1600, every = 75 },
    note = "Naga healer, warded. Kill her first." }
C.myrmidon = { name = "Blackfathom Myrmidon", icon = ICON .. "INV_Spear_04", alt = ICON .. "INV_Sword_04",
    hp = 60, speed = 30, armor = 30, bounty = 5, note = "Armoured." }
C.snapjaw = { name = "Murkshallow Snapjaw", icon = ICON .. "Ability_Hunter_Pet_Turtle",
    alt = ICON .. "Ability_Hunter_Pet_Crocolisk", hp = 70, speed = 23, armor = 60, bounty = 6, note = ARMOUR }
C.akumai = { name = "Aku'mai", npc = 4829, icon = ICON .. "Ability_Hunter_Pet_Crocolisk", boss = true,
    hp = 3000, speed = 13, armor = 30, resist = 30, bounty = 150, lives = 15, size = 40,
    ability = { kind = "summon", creep = "snapjaw", count = 2, every = 450, first = 240 },
    enrage = { below = 50, pct = 170 },
    note = "Boss. The hydra of the Deeps calls snapjaws, and enrages when hurt." }

------------------------------------------------------------------------------------------------------------------------
-- Levels

Content.Campaign {
    id = "sentinels", name = "The Sentinels", title = "Wrath of the Wild", faction = "Alliance",
    color = { 0.55, 0.35, 0.85 }, crest = ICON .. "Ability_Mount_WhiteTiger",
        crestAlt = ICON .. "Spell_Nature_StarFall",
    blurb = "Corruption creeps through the night elves' forests, from Teldrassil to the black depths of Ashenvale.",
    unlock = { stars = 30 },
    roster = { { "archer", 1 }, { "dryad", 1 }, { "moonwell", 2 }, { "ancient", 3 }, { "talon", 4 } },
    hero = { kind = "tyrande", at = 5 },
    levels = {
        {
            id = "sentinels-1", zone = "Teldrassil", name = "Shadowglen", map = 1438, length = "short",
            art = { left = 0.28, top = 0.12, width = 0.6 },
            blurb = "Grellkin swarm down the glen's steps. The inner corners see two runs of road: build there.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 5, 2 }, { 5, 5 }, { 10, 5 }, { 10, 8 }, { 17, 8 } },
            },
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 105,
                { hp = 105, G("grell", 14, 36) },
                { hp = 95, G("grell", 12, 30), G("grell", 10, 20, 420) },
                { hp = 125, G("nightsaber", 10, 54) },
                { hp = 134, G("grell", 16, 26), G("nightsaber", 8, 50, 240) },
                { hp = 188, G("grell", 20, 20), G("nightsaber", 10, 40, 420) },
                { hp = 210, G("nightsaber", 10, 36), G("grell", 30, 14, 300), G("nightsaber", 12, 30, 780) },
            },
        },
        {
            id = "sentinels-2", zone = "Darnassus", name = "Temple Gardens", map = 1457, length = "short",
            blurb = "The Gnarlpine have turned on Darnassus. Their mystics heal the pack: kill them first.",
            art = { left = 0.2, top = 0.2, width = 0.6 },
            cols = 16, rows = 10,
            paths = {
                { { 0, 8 }, { 3, 8 }, { 3, 2 }, { 9, 2 }, { 9, 8 }, { 14, 8 }, { 14, 3 }, { 17, 3 } },
                { air = true, { 0, 1 }, { 17, 10 } },
            },
            airPath = 2,
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 95,
                { hp = 75, G("nightsaber", 8, 40) },
                { hp = 85, G("furbolg", 4, 50, 0, 82), G("nightsaber", 8, 30, 40) },
                { hp = 102, G("owl", 8, 36), G("furbolg", 4, 50, 120) },
                { hp = 120, G("nightsaber", 14, 22), G("furbolg", 5, 44, 60) },
                { hp = 121, G("owl", 10, 30), G("timberling", 6, 44, 90) },
                { hp = 161, G("furbolg", 8, 36), G("nightsaber", 14, 18, 40), G("owl", 8, 28, 300) },
            },
        },
        {
            id = "sentinels-3", zone = "Darnassus", name = "Cenarion Enclave", map = 1457, length = "standard",
            blurb = "Webwood lurkers split into hatchlings when they die. Ursal the Mauler leads the last charge.",
            art = { left = 0.3, top = 0.3, width = 0.6 },
            cols = 16, rows = 10,
            paths = {
                { { 0, 5 }, { 4, 5 }, { 4, 2 }, { 13, 2 }, { 13, 9 }, { 7, 9 }, { 7, 11 } },
                { air = true, { 8, 0 }, { 8, 11 } },
            },
            airPath = 2,
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 101,
                { hp = 55, G("spider", 6, 50) },
                { hp = 40, G("nightsaber", 10, 22), G("spider", 4, 44, 120) },
                { hp = 75, G("furbolg", 4, 44), G("timberling", 4, 56, 60) },
                { hp = 97, G("owl", 8, 30), G("spider", 6, 40, 60) },
                { hp = 122, G("nightsaber", 16, 14), G("furbolg", 5, 40, 40) },
                { hp = 65, G("timberling", 6, 44), G("spider", 8, 34, 90) },
                { hp = 120, G("owl", 12, 24), G("furbolg", 6, 34, 90) },
                { hp = 141, G("spider", 12, 26), G("nightsaber", 14, 14, 150) },
                { hp = 132, G("timberling", 8, 34), G("furbolg", 6, 32, 30), G("owl", 12, 22, 180) },
                { hp = 128, G("spider", 8, 30), G("ursal", 1, 1, 150, 53), G("nightsaber", 12, 14, 300) },
            },
        },
        {
            id = "sentinels-4", zone = "Teldrassil", name = "Fel Rock", map = 1438, length = "short",
            art = { left = 0.22, top = 0.06, width = 0.6 },
            blurb = "Satyrs creep unseen around Fel Rock. Put a druid of the talon where it sees two roads.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 12, 2 }, { 12, 5 }, { 4, 5 }, { 4, 8 }, { 17, 8 } },
            },
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 100,
                { hp = 150, G("grell", 16, 30) },
                { hp = 73, G("grell", 14, 24), G("nightsaber", 6, 40, 300) },
                { hp = 140, G("satyr", 6, 60) },
                { hp = 81, G("satyr", 10, 40, 0, 88), G("grell", 12, 24, 120, 128) },
                { hp = 160, G("satyr", 8, 40, 0, 84), G("grell", 24, 16, 60, 122), G("nightsaber", 8, 30, 420) },
                { hp = 99, G("satyr", 6, 40, 0, 89), G("melenas", 1, 1, 150, 48), G("grell", 16, 20, 300, 113) },
            },
        },
        {
            id = "sentinels-5", zone = "Darkshore", name = "Auberdine", map = 1439, length = "standard",
            art = { left = 0.06, top = 0.17, width = 0.6 },
            blurb = "Murlocs land on two beaches at once. Both roads meet by the docks: hold the junction.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 6, 2 }, { 6, 5 }, { 12, 5 }, { 12, 2 }, { 15, 2 }, { 15, 11 } },
                { { 0, 9 }, { 6, 9 }, { 6, 5 }, { 12, 5 }, { 12, 2 }, { 15, 2 }, { 15, 11 } },
            },
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 107,
                { hp = 420, G("greymist", 10, 30, 0, 100, 1), G("greymist", 10, 30, 150, 100, 2) },
                { hp = 195, G("blackwood", 6, 50, 0, 100, 1) },
                { hp = 150, G("crawler", 5, 60, 0, 100, 2) },
                { hp = 290, G("greymist", 12, 22, 0, 100, 1), G("greymist", 12, 22, 60, 100, 2) },
                { hp = 147, G("blackwood", 8, 40, 0, 100, 1), G("crawler", 5, 50, 120, 100, 2) },
                { hp = 217, G("greymist", 18, 18, 0, 131, 2), G("blackwood", 8, 40, 200, 78, 1) },
                { hp = 212, G("crawler", 8, 44, 0, 80, 1), G("greymist", 16, 16, 90, 134, 2) },
                { hp = 202, G("blackwood", 10, 34, 0, 100, 2), G("crawler", 6, 44, 60, 100, 1),
                    G("greymist", 12, 18, 300, 156, 1) },
                { hp = 259, G("greymist", 14, 20, 0, 129, 1), G("greymist", 14, 20, 0, 129, 2),
                    G("crawler", 8, 40, 200, 81, 2), G("blackwood", 8, 36, 300, 89, 1) },
                { hp = 319, G("greymist", 14, 18, 0, 122, 2), G("murkdeep", 1, 1, 120, 31, 1),
                    G("blackwood", 8, 36, 450, 88, 2) },
            },
        },
        {
            id = "sentinels-6", zone = "Darkshore", name = "The Master's Glaive", map = 1439, length = "standard",
            art = { left = 0.08, top = 0.4375, width = 0.6 },
            blurb = "The road bends around the fallen glaive. Delmanis blinks ahead: build all along it.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 8 }, { 13, 8 }, { 13, 2 }, { 0, 2 } },
                { air = true, { 17, 5 }, { 0, 5 } },
            },
            airPath = 2,
            blocked = { { 3, 5 }, { 4, 5 }, { 5, 5 }, { 6, 5 }, { 7, 5 }, { 8, 5 }, { 9, 5 }, { 10, 4 }, { 10, 5 },
                { 10, 6 } },
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 94,
                { hp = 259, G("twilight", 8, 60) },
                { hp = 251, G("highborne", 8, 54, 0, 87), G("blackwood", 6, 50, 200, 112) },
                { hp = 158, G("satyr", 8, 54), G("twilight", 5, 60, 240) },
                { hp = 209, G("twilight", 10, 44), G("highborne", 8, 40, 180) },
                { hp = 138, G("satyr", 12, 36), G("blackwood", 8, 44, 120, 121) },
                { hp = 184, G("highborne", 12, 34), G("twilight", 8, 46, 180) },
                { hp = 239, G("satyr", 12, 32), G("twilight", 8, 44, 90), G("greymist", 18, 16, 420, 144) },
                { hp = 274, G("blackwood", 12, 34), G("highborne", 12, 28, 120), G("twilight", 8, 44, 360) },
                { hp = 207, G("satyr", 12, 30), G("twilight", 10, 36, 120), G("highborne", 10, 30, 420) },
                { hp = 216, G("delmanis", 1, 1, 0, 30), G("twilight", 6, 46, 240), G("satyr", 10, 32, 600),
                    G("highborne", 10, 30, 750) },
            },
        },
        {
            id = "sentinels-7", zone = "Ashenvale", name = "Astranaar", map = 1440, length = "standard",
            art = { left = 0.05, top = 0.2, width = 0.6 },
            blurb = "The Warsong march on two roads. Between them one tower covers both, but mind the Overlord.",
            cols = 16, rows = 10,
            paths = {
                { { 17, 2 }, { 13, 2 }, { 13, 4 }, { 3, 4 }, { 3, 1 }, { 0, 1 } },
                { { 17, 9 }, { 13, 9 }, { 13, 7 }, { 3, 7 }, { 3, 10 }, { 0, 10 } },
                { air = true, { 17, 10 }, { 0, 1 } },
            },
            airPath = 3,
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 83,
                { hp = 59, G("outrider", 10, 44, 0, 100, 1) },
                { hp = 50, G("grunt", 8, 56, 0, 100, 2) },
                { hp = 67, G("windrider", 8, 48), G("outrider", 6, 40, 180, 100, 2) },
                { hp = 70, G("grunt", 6, 50, 0, 100, 1), G("outrider", 8, 34, 150, 100, 2) },
                { hp = 87, G("logshredder", 3, 100, 0, 84, 2), G("outrider", 10, 34, 180, 117, 1) },
                { hp = 106, G("windrider", 10, 36), G("grunt", 8, 44, 150, 100, 2) },
                { hp = 102, G("outrider", 10, 28, 0, 100, 1), G("outrider", 10, 28, 90, 100, 2),
                    G("logshredder", 2, 90, 330, 100, 1) },
                { hp = 127, G("grunt", 10, 38, 0, 100, 1), G("logshredder", 3, 80, 90, 83, 2),
                    G("windrider", 8, 36, 330) },
                { hp = 123, G("logshredder", 4, 80, 0, 100, 1), G("grunt", 10, 38, 90, 100, 2),
                    G("outrider", 10, 26, 330, 100, 1), G("windrider", 8, 34, 480) },
                { hp = 133, G("overlord", 1, 1, 0, 32, 2), G("grunt", 8, 40, 600, 100, 1),
                    G("outrider", 10, 26, 900, 100, 2), G("windrider", 8, 34, 750) },
            },
        },
        {
            id = "sentinels-8", zone = "Ashenvale", name = "Blackfathom Deeps", map = 1440, length = "siege",
            art = { left = 0.0, top = 0.0, width = 0.6 },
            blurb = "The road circles a flooded pool, and later a side channel opens. Guard the way out.",
            cols = 16, rows = 10,
            paths = {
                { { 6, 0 }, { 6, 2 }, { 4, 2 }, { 4, 8 }, { 11, 8 }, { 11, 2 }, { 9, 2 }, { 9, 0 } },
                { { 16, 11 }, { 16, 5 }, { 11, 5 }, { 11, 2 }, { 9, 2 }, { 9, 0 } },
            },
            blocked = { { 7, 4 }, { 8, 4 }, { 6, 5 }, { 7, 5 }, { 8, 5 }, { 9, 5 }, { 7, 6 }, { 8, 6 } },
            gold = 155, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 98,
                { hp = 80, G("myrmidon", 8, 30) },
                { hp = 78, G("naga", 5, 40), G("myrmidon", 6, 30, 60) },
                { hp = 100, G("snapjaw", 5, 44) },
                { hp = 98, G("twilight", 6, 32), G("myrmidon", 8, 26, 80) },
                { hp = 173, G("satyr", 8, 32), G("naga", 3, 40, 140) },
                { hp = 131, G("myrmidon", 10, 26, 0, 100, 2), G("snapjaw", 4, 44, 80) },
                { hp = 146, G("snapjaw", 6, 40), G("naga", 6, 40, 40) },
                { hp = 188, G("satyr", 10, 26), G("twilight", 6, 32, 100) },
                { hp = 179, G("myrmidon", 12, 22), G("myrmidon", 8, 26, 100, 100, 2) },
                { hp = 185, G("snapjaw", 8, 36), G("naga", 6, 36, 40) },
                { hp = 212, G("twilight", 8, 28), G("satyr", 10, 24, 100), G("myrmidon", 8, 26, 200, 100, 2) },
                { hp = 215, G("snapjaw", 10, 32), G("naga", 8, 32, 40) },
                { hp = 212, G("myrmidon", 14, 20), G("satyr", 10, 24, 100, 100, 2) },
                { hp = 221, G("snapjaw", 8, 32), G("naga", 6, 32, 40), G("twilight", 6, 32, 200),
                    G("myrmidon", 10, 24, 200, 100, 2) },
                { hp = 240, G("akumai", 1, 1, 0, 25), G("satyr", 8, 30, 600), G("myrmidon", 10, 30, 750, 100, 2) },
            },
        },
    },
}
