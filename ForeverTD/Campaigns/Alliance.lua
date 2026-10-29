-- Campaigns\Alliance.lua - The Alliance: "Shadows over Stormwind". Elwynn Forest, Stormwind, Westfall, Duskwood and
-- the Deadmines. While the king is missing, the Defias Brotherhood rises from the farms of Westfall; dwarven
-- riflemen, Kirin Tor mages, priests of the Light, gnomish engineers and the paladins of the Silver Hand hold the
-- line. The words are in Story.lua. Names and numbers are drafts.
local _, ns = ...
local Content = ns.Content
local ICON, G = Content.ICON, Content.Group
local T, C = Content.towers, Content.creeps

------------------------------------------------------------------------------------------------------------------------
-- Towers

T.rifleman = {
    name = "Dwarven Rifleman", role = "ranged", icon = ICON .. "INV_Weapon_Rifle_01", damage = "physical", air = true,
    shot = 650,
    blurb = "Long-range rifle shots that hit hard. Hits flying creeps.",
    ranks = {
        { cost = 60, dmg = 13, range = 2400, cd = 26 },
        { cost = 50, dmg = 20, range = 2500, cd = 24 },
        { cost = 90, dmg = 32, range = 2600, cd = 22 },
    },
    specs = {
        { name = "Marksman", cost = 120, dmg = 36, range = 2800, crit = { pct = 25, mult = 250 },
            blurb = "A little more reach, and one shot in four is a critical hit for 2.5x damage." },
        { name = "Gyrocopter", cost = 130, cd = 16, airBonus = 100,
            blurb = "A gnomish gyrocopter crew: fires faster, and does double damage to flyers." },
    },
}

T.frost = {
    name = "Frost Mage", role = "control", icon = ICON .. "Spell_Frost_FrostBolt02", damage = "magic", air = true,
    shot = 300,
    blurb = "A Kirin Tor mage: weak bolts that slow. Hits flying creeps.",
    ranks = {
        { cost = 70, dmg = 6, range = 2200, cd = 30, slow = 35, slowTicks = 60 },
        { cost = 55, dmg = 10, range = 2300, cd = 28, slow = 45, slowTicks = 70 },
        { cost = 90, dmg = 15, range = 2400, cd = 26, slow = 55, slowTicks = 80 },
    },
    specs = {
        { name = "Shatter", cost = 120, dmg = 20, bonusVsSlowed = 150,
            blurb = "Bolts do 2.5x damage to creeps that are already slowed." },
        { name = "Blizzard", cost = 140, pulse = true, dmg = 13, range = 2000, cd = 40, slow = 55, slowTicks = 60,
            blurb = "A storm that hurts and slows everything near it, flyers included." },
    },
}

T.engineer = {
    name = "Gnomish Engineer", role = "siege", icon = ICON .. "INV_Misc_Bomb_01", damage = "physical", shot = 160,
    blurb = "Slow bombs that splash. Ground only.",
    ranks = {
        { cost = 100, dmg = 20, range = 2600, cd = 54, splash = 1000 },
        { cost = 80, dmg = 32, range = 2700, cd = 50, splash = 1100 },
        { cost = 130, dmg = 50, range = 2800, cd = 46, splash = 1300 },
    },
    specs = {
        { name = "Dwarven Mortar", short = "Mortar", cost = 150, dmg = 90, splash = 1600, cd = 66,
            blurb = "A dwarven mortar: slow, huge blasts." },
        { name = "Gnomish Freeze Ray", short = "Freeze Ray", cost = 150, dmg = 45, cd = 40, stun = 30,
            blurb = "Bombs freeze the creep they hit for half a second." },
    },
}

T.priest = {
    name = "Holy Priest", role = "area", icon = ICON .. "Spell_Holy_HolyBolt", damage = "magic", pulse = true,
    holy = 50,
    blurb = "A holy pulse that hurts every ground creep near it, undead and demons half again as much.",
    ranks = {
        { cost = 90, dmg = 9, range = 1600, cd = 36 },
        { cost = 70, dmg = 15, range = 1700, cd = 34 },
        { cost = 110, dmg = 24, range = 1800, cd = 30 },
    },
    specs = {
        { name = "Holy Nova", cost = 130, dmg = 34, air = true,
            blurb = "A stronger pulse that also hits flying creeps." },
        { name = "Shadow Word", cost = 140, dmg = 18, dot = { dmg = 8, seconds = 4 },
            blurb = "The pulse leaves a curse: 32 more damage over 2 seconds." },
    },
}

T.paladin = {
    name = "Paladin", role = "signature", icon = ICON .. "Spell_Holy_SealOfMight", damage = "magic", shot = 380,
    holy = 100,
    blurb = "A knight of the Silver Hand. Towers near it hit harder, its light reveals stealthed creeps near it, and "
        .. "its hammer smites undead and demons for double damage. Ground only.",
    ranks = {
        { cost = 110, dmg = 10, range = 1800, cd = 28, might = 10, aura = 2200, reveal = 2200 },
        { cost = 85, dmg = 16, range = 1900, cd = 26, might = 15, aura = 2300, reveal = 2300 },
        { cost = 130, dmg = 25, range = 2000, cd = 24, might = 20, aura = 2500, reveal = 2500 },
    },
    specs = {
        { name = "Crusader Aura", short = "Crusader", cost = 150, might = 35, aura = 2800,
            blurb = "Towers near it hit 35% harder." },
        { name = "Consecration", cost = 150, pulse = true, dmg = 24, range = 1900, cd = 30, holy = 150,
            blurb = "Holy ground: burns every ground creep near it, undead and demons hardest." },
    },
}

T.bolvar = {
    name = "Bolvar Fordragon", role = "hero", hero = true, npc = 1748, icon = ICON .. "Spell_Holy_DivineIntervention",
    alt = ICON .. "Spell_Holy_HolyBolt", damage = "magic", shot = 420, holy = 100,
    blurb = "Highlord of Stormwind. His hammer smites undead, and towers near him hit 10% harder. Ground only.",
    ranks = { { cost = 0, dmg = 22, range = 2000, cd = 26, might = 10, aura = 2500 } },
    ability = { kind = "shield", name = "Divine Shield", ticks = 300, cd = 10800, first = 300,
        blurb = "For 5 seconds, creeps that get through cost no lives." },
}

------------------------------------------------------------------------------------------------------------------------
-- Creeps

local FLY = "Flying: only towers that hit air can reach it."
local ARMOUR = "Armoured: physical hits do half damage."
local STEALTH = "Stealthed: towers can't see it unless a revealing tower is near."

C.kobold = { name = "Kobold Vermin", npc = 6, icon = ICON .. "INV_Misc_Head_Kobold_01",
    alt = ICON .. "INV_Misc_Bone_HumanSkull_01", hp = 16, speed = 34, bounty = 1, size = 20,
    note = "Swarm: weak, but many. \"You no take candle!\"" }
C.geomancer = { name = "Kobold Geomancer", icon = ICON .. "Spell_Fire_FlameBolt", hp = 30, speed = 27, bounty = 4,
    heal = { pct = 8, range = 1500, every = 80 }, note = "Healer: mends creeps around it. Kill it first." }
C.murloc = { name = "Murloc Streamrunner", npc = 735, icon = ICON .. "INV_Misc_Head_Murloc_01",
    hp = 14, speed = 36, bounty = 1, size = 20, note = "Swarm: weak, but many." }
C.wolf = { name = "Timber Wolf", npc = 69, icon = ICON .. "Ability_Hunter_Pet_Wolf", hp = 24, speed = 47, bounty = 3,
    note = "Fast." }
C.defias = { name = "Defias Thug", npc = 38, icon = ICON .. "INV_Misc_Head_Human_01", alt = ICON .. "INV_Sword_04",
    hp = 70, speed = 27, armor = 30, bounty = 6, note = ARMOUR }
C.hogger = { name = "Hogger", npc = 448, icon = ICON .. "Ability_Hunter_Pet_Hyena",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", boss = true, hp = 1400, speed = 17, armor = 20, regen = 12, bounty = 90,
    lives = 10, size = 34, enrage = { below = 50, pct = 160 }, note = "Boss. Regenerates, and enrages when hurt." }

C.convict = { name = "Defias Convict", npc = 1711, icon = ICON .. "INV_Misc_Head_Human_01",
    alt = ICON .. "INV_Sword_04", hp = 40, speed = 31, bounty = 3 }
C.bazil = { name = "Bazil Thredd", npc = 1716, icon = ICON .. "Ability_BackStab", alt = ICON .. "INV_Sword_04",
    boss = true, hp = 900, speed = 18, armor = 20, bounty = 80, lives = 10, size = 32,
    ability = { kind = "summon", creep = "convict", count = 3, every = 300, first = 150 },
    note = "Boss. The Defias' man in the Stockade: he frees more prisoners." }

C.footpad = { name = "Defias Footpad", icon = ICON .. "Ability_Stealth", alt = ICON .. "Ability_Rogue_Sprint",
    stealth = true, hp = 38, speed = 36, bounty = 5, note = STEALTH }
C.pillager = { name = "Defias Pillager", icon = ICON .. "Spell_Fire_Fire", alt = ICON .. "Spell_Fire_FlameBolt",
    hp = 44, speed = 28, resist = 50, bounty = 5, note = "Warded: magic does half damage." }
C.golem = { name = "Harvest Watcher", npc = 114, icon = ICON .. "INV_Misc_Gear_01",
    alt = ICON .. "Ability_Warrior_Sunder", hp = 90, speed = 20, armor = 60, bounty = 7, size = 28, note = ARMOUR }
C.fleshripper = { name = "Fleshripper", npc = 154, icon = ICON .. "Ability_Hunter_Pet_Vulture", air = true,
    hp = 30, speed = 42, bounty = 5, note = FLY }
C.foereaper = { name = "Foe Reaper 4000", npc = 573, icon = ICON .. "INV_Misc_Gear_02",
    alt = ICON .. "Ability_Warrior_Sunder", boss = true, hp = 1800, speed = 15, armor = 60, bounty = 100, lives = 10,
    size = 36, ability = { kind = "stomp", every = 300, first = 180, range = 2000, ticks = 60 },
    note = "Boss. A runaway harvester: armoured, and its slam stuns the towers near it." }

C.skeleton = { name = "Skeletal Warrior", npc = 48, icon = ICON .. "INV_Misc_Bone_HumanSkull_01", undead = true,
    hp = 50, speed = 26, armor = 30, bounty = 4, note = "Undead and armoured." }
C.ghoul = { name = "Rotting Ghoul", icon = ICON .. "Spell_Shadow_RaiseDead", undead = true, hp = 60, speed = 30,
    regen = 4, bounty = 5, note = "Undead. Regenerates." }
C.nightbane = { name = "Nightbane Stalker", icon = ICON .. "Ability_Mount_BlackDireWolf",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", stealth = true, hp = 46, speed = 43, bounty = 6,
    note = "A worgen: fast and stealthed. " .. STEALTH }
C.stitches = { name = "Stitches", npc = 412, icon = ICON .. "Spell_Shadow_AbominationExplosion",
    alt = ICON .. "Spell_Shadow_RaiseDead", boss = true, undead = true, hp = 2600, speed = 12, armor = 30,
    bounty = 120, lives = 15, size = 40,
    ability = { kind = "stomp", every = 360, first = 240, range = 1800, ticks = 75 },
    note = "Boss. An abomination marching on Darkshire: huge, slow, and his cleave stuns towers." }

C.goblin = { name = "Goblin Engineer", icon = ICON .. "INV_Misc_Head_Goblin_01", alt = ICON .. "INV_Misc_Bomb_04",
    hp = 50, speed = 30, armor = 40, bounty = 5, note = ARMOUR }
C.blackguard = { name = "Defias Blackguard", icon = ICON .. "Ability_Ambush", alt = ICON .. "Ability_Rogue_Sprint",
    stealth = true, hp = 70, speed = 30, armor = 30, bounty = 7, note = STEALTH }
C.shredder = { name = "Sneed's Shredder", npc = 642, icon = ICON .. "INV_Misc_Gear_03",
    alt = ICON .. "Ability_Warrior_Sunder", boss = true, hp = 900, speed = 17, armor = 50, bounty = 50, lives = 5,
    size = 32, note = "A goblin lumber shredder: heavily armoured." }
C.vancleef = { name = "Edwin VanCleef", npc = 639, icon = ICON .. "Ability_BackStab", alt = ICON .. "INV_Sword_04",
    boss = true, hp = 2400, speed = 18, armor = 30, bounty = 150, lives = 15, size = 36,
    ability = { kind = "summon", creep = "blackguard", count = 3, every = 360, first = 200 },
    enrage = { below = 30, pct = 150 },
    note = "Boss. The Defias Kingpin calls stealthed blackguards, and enrages when hurt." }

------------------------------------------------------------------------------------------------------------------------
-- Levels

Content.Campaign {
    id = "alliance", name = "The Alliance", title = "Shadows over Stormwind", faction = "Alliance",
    color = { 0.2, 0.42, 0.9 }, crest = ICON .. "INV_BannerPVP_02", crestAlt = ICON .. "Spell_Holy_SealOfMight",
    blurb = "With the king gone, the Defias Brotherhood rises from Westfall's farms. Hold Elwynn, Westfall and "
        .. "Duskwood, then end it in the Deadmines.",
    roster = { { "rifleman", 1 }, { "frost", 1 }, { "engineer", 2 }, { "priest", 3 }, { "paladin", 5 } },
    hero = { kind = "bolvar", at = 6 },
    levels = {
        {
            id = "alliance-1", zone = "Elwynn Forest", name = "Northshire Valley", map = 1429, length = "short",
            art = { left = 0.18, top = 0.12, width = 0.6 },
            blurb = "Kobolds pour out of Echo Ridge Mine. Riflemen in the bends cover the road twice.",
            cols = 16, rows = 10,
            paths = { { { 4, 0 }, { 4, 6 }, { 9, 6 }, { 9, 3 }, { 13, 3 }, { 13, 8 }, { 17, 8 } } },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 95,
                { hp = 114, G("kobold", 10, 26) },
                { hp = 83, G("kobold", 10, 28), G("wolf", 4, 40, 220) },
                { hp = 83, G("defias", 3, 80, 0, 86), G("kobold", 12, 18, 60, 115) },
                { hp = 119, G("wolf", 10, 24), G("kobold", 10, 16, 120) },
                { hp = 117, G("kobold", 20, 12, 0, 111), G("defias", 5, 60, 150, 90) },
                { hp = 141, G("wolf", 10, 20), G("kobold", 24, 10, 120), G("defias", 6, 50, 260) },
            },
        },
        {
            id = "alliance-2", zone = "Elwynn Forest", name = "Goldshire", map = 1429, length = "short",
            art = { left = 0.12, top = 0.36, width = 0.6 },
            blurb = "Murlocs are swarming up from the lake. Lots of small targets: splash them.",
            cols = 16, rows = 10,
            paths = { { { 3, 0 }, { 3, 4 }, { 8, 4 }, { 8, 2 }, { 13, 2 }, { 13, 7 }, { 6, 7 }, { 6, 11 } } },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 78,
                { hp = 263, G("murloc", 12, 14) },
                { hp = 150, G("wolf", 8, 22), G("murloc", 12, 12, 120) },
                { hp = 125, G("defias", 6, 40), G("murloc", 16, 10, 60, 120) },
                { hp = 176, G("murloc", 26, 8), G("wolf", 8, 20, 150) },
                { hp = 192, G("defias", 8, 30), G("wolf", 12, 16, 90) },
                { hp = 241, G("murloc", 32, 7), G("defias", 10, 28, 100), G("wolf", 10, 14, 260) },
            },
        },
        {
            id = "alliance-3", zone = "Elwynn Forest", name = "Forest's Edge", map = 1429, length = "standard",
            art = { left = 0.02, top = 0.42, width = 0.6 },
            blurb = "Two roads meet at the forest's edge, and Hogger is coming. Holy priests guard the joining.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 3 }, { 5, 3 }, { 5, 7 }, { 11, 7 }, { 11, 4 }, { 17, 4 } },
                { { 9, 11 }, { 9, 9 }, { 14, 9 }, { 14, 4 }, { 17, 4 } },
            },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 100,
                { hp = 160, G("murloc", 14, 18) },
                { hp = 65, G("wolf", 8, 26), G("murloc", 12, 16, 60, 100, 2) },
                { hp = 70, G("defias", 6, 40, 0, 100, 2), G("murloc", 16, 12, 40, 121) },
                { hp = 64, G("wolf", 12, 18), G("defias", 6, 40, 90, 100, 2) },
                { hp = 113, G("murloc", 30, 9, 0, 100, 2), G("defias", 6, 34, 120) },
                { hp = 119, G("wolf", 14, 16), G("wolf", 10, 18, 60, 100, 2) },
                { hp = 115, G("defias", 12, 30), G("murloc", 24, 10, 80, 117, 2) },
                { hp = 190, G("murloc", 36, 8), G("wolf", 12, 16, 120, 100, 2) },
                { hp = 129, G("defias", 14, 26, 0, 100, 2), G("wolf", 14, 14, 60), G("murloc", 20, 10, 200) },
                { hp = 122, G("hogger", 1, 1, 120, 42), G("defias", 10, 28), G("murloc", 24, 10, 60, 100, 2) },
            },
        },
        {
            id = "alliance-4", zone = "Stormwind City", name = "The Stockade", map = 1453, length = "short",
            art = { left = 0.11, top = 0.3, width = 0.6 },
            blurb = "The prisoners have broken out and split up. Kobold geomancers heal them: kill those first.",
            cols = 16, rows = 10,
            paths = {
                { { 1, 0 }, { 1, 5 }, { 3, 5 }, { 3, 3 }, { 11, 3 }, { 11, 5 }, { 14, 5 }, { 14, 8 }, { 17, 8 } },
                { { 1, 0 }, { 1, 5 }, { 3, 5 }, { 3, 7 }, { 11, 7 }, { 11, 5 }, { 14, 5 }, { 14, 8 }, { 17, 8 } },
            },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 88,
                { hp = 85, G("convict", 5, 60, 0, 100, 1), G("convict", 5, 60, 30, 100, 2) },
                { hp = 70, G("defias", 4, 70, 0, 100, 1), G("convict", 8, 40, 35, 100, 2) },
                { hp = 94, G("defias", 5, 60, 0, 100, 2), G("geomancer", 2, 120, 90, 100, 2),
                    G("convict", 8, 36, 20, 100, 1) },
                { hp = 120, G("convict", 10, 26, 0, 100, 1), G("convict", 10, 26, 13, 100, 2),
                    G("geomancer", 2, 100, 60, 100, 1) },
                { hp = 107, G("defias", 5, 50, 0, 100, 1), G("defias", 5, 50, 25, 100, 2),
                    G("geomancer", 2, 100, 80, 82, 1), G("geomancer", 2, 100, 130, 82, 2), G("convict", 10, 20, 220) },
                { hp = 103, G("bazil", 1, 1, 240, 66, 1), G("defias", 6, 45, 0, 100, 2),
                    G("convict", 10, 24, 0, 100, 1), G("convict", 10, 24, 300, 100, 2),
                    G("geomancer", 3, 90, 200, 80, 2) },
            },
        },
        {
            id = "alliance-5", zone = "Westfall", name = "Sentinel Hill", map = 1436, length = "standard",
            art = { left = 0.26, top = 0.21, width = 0.6 },
            blurb = "Defias footpads creep around the hill unseen. Only a paladin's light reveals them.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 8 }, { 5, 8 }, { 5, 3 }, { 11, 3 }, { 11, 7 }, { 17, 7 } },
                { air = true, { 0, 1 }, { 17, 10 } },
            },
            airPath = 2,
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 91,
                { hp = 60, G("defias", 5, 70) },
                { hp = 67, G("pillager", 8, 40) },
                { hp = 89, G("footpad", 6, 50) },
                { hp = 96, G("fleshripper", 6, 50), G("defias", 4, 50, 100) },
                { hp = 95, G("golem", 5, 70), G("footpad", 6, 40, 120) },
                { hp = 113, G("pillager", 10, 32), G("footpad", 8, 36, 60) },
                { hp = 111, G("fleshripper", 12, 30), G("golem", 6, 60, 60) },
                { hp = 135, G("defias", 10, 30), G("footpad", 10, 30, 120), G("pillager", 6, 36, 300) },
                { hp = 128, G("golem", 8, 50), G("fleshripper", 10, 30, 100), G("footpad", 10, 28, 200) },
                { hp = 149, G("defias", 10, 36), G("pillager", 10, 30, 60), G("footpad", 14, 24, 200),
                    G("golem", 6, 50, 300), G("fleshripper", 8, 30, 150) },
            },
        },
        {
            id = "alliance-6", zone = "Westfall", name = "Moonbrook", map = 1436, length = "standard",
            art = { left = 0.12, top = 0.38, width = 0.6 },
            blurb = "Two roads into the Defias stronghold. Bolvar's Divine Shield saves lives when it's busy.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 8, 2 }, { 8, 5 }, { 14, 5 }, { 14, 9 }, { 10, 9 }, { 10, 11 } },
                { { 3, 11 }, { 3, 7 }, { 8, 7 }, { 8, 5 }, { 14, 5 }, { 14, 9 }, { 10, 9 }, { 10, 11 } },
                { air = true, { 0, 1 }, { 17, 8 } },
            },
            airPath = 3,
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 100,
                { hp = 81, G("defias", 5, 60, 0, 100, 1), G("pillager", 4, 60, 30, 100, 2) },
                { hp = 115, G("footpad", 6, 44, 0, 100, 2), G("defias", 5, 50, 60, 100, 1) },
                { hp = 100, G("golem", 5, 60, 0, 100, 1), G("pillager", 8, 32, 60, 100, 2) },
                { hp = 105, G("fleshripper", 10, 30), G("footpad", 8, 32, 90, 100, 1) },
                { hp = 155, G("defias", 12, 28, 0, 100, 2), G("golem", 6, 50, 100, 100, 1) },
                { hp = 125, G("footpad", 12, 26, 0, 100, 1), G("footpad", 10, 28, 40, 100, 2),
                    G("fleshripper", 8, 30, 120) },
                { hp = 190, G("pillager", 14, 24, 0, 100, 2), G("golem", 8, 44, 60, 100, 1) },
                { hp = 167, G("defias", 14, 24, 0, 100, 1), G("footpad", 12, 24, 60, 100, 2),
                    G("fleshripper", 10, 26, 200) },
                { hp = 220, G("golem", 10, 40, 0, 100, 2), G("pillager", 12, 26, 60, 100, 1),
                    G("footpad", 12, 22, 240, 100, 2) },
                { hp = 220, G("foereaper", 1, 1, 200, 39, 1), G("golem", 6, 50, 0, 100, 2),
                    G("defias", 10, 30, 60, 100, 1), G("footpad", 12, 24, 300, 100, 2) },
            },
        },
        {
            id = "alliance-7", zone = "Duskwood", name = "Darkshire", map = 1431, length = "standard",
            art = { left = 0.4, top = 0.16, width = 0.6 },
            blurb = "The dead march on Darkshire, and worgen hunt unseen among them. Holy light burns the undead.",
            cols = 16, rows = 10,
            paths = { { { 0, 2 }, { 11, 2 }, { 11, 5 }, { 5, 5 }, { 5, 8 }, { 17, 8 } } },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 108,
                { hp = 250, G("skeleton", 8, 50) },
                { hp = 170, G("ghoul", 8, 45) },
                { hp = 190, G("nightbane", 6, 50), G("skeleton", 6, 50, 100) },
                { hp = 135, G("skeleton", 12, 34), G("ghoul", 6, 40, 150) },
                { hp = 150, G("nightbane", 10, 34), G("ghoul", 8, 36, 60) },
                { hp = 205, G("skeleton", 14, 26), G("nightbane", 8, 30, 150) },
                { hp = 220, G("ghoul", 14, 28), G("skeleton", 10, 28, 80) },
                { hp = 240, G("nightbane", 14, 28), G("skeleton", 12, 28, 100) },
                { hp = 238, G("ghoul", 14, 26), G("nightbane", 12, 28, 120), G("skeleton", 10, 26, 300) },
                { hp = 300, G("stitches", 1, 1, 200, 27), G("skeleton", 12, 28), G("ghoul", 10, 28, 100),
                    G("nightbane", 10, 28, 360) },
            },
        },
        {
            id = "alliance-8", zone = "Westfall", name = "The Deadmines", map = 1436, length = "siege",
            art = { left = 0.05, top = 0.4375, width = 0.55 },
            blurb = "Down the mine tunnels to VanCleef's ship. His blackguards hide: keep paladins along the way.",
            cols = 16, rows = 10,
            paths = { { { 1, 0 }, { 1, 8 }, { 5, 8 }, { 5, 2 }, { 9, 2 }, { 9, 8 }, { 13, 8 }, { 13, 3 }, { 17, 3 } } },
            gold = 175, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 112,
                { hp = 115, G("defias", 6, 40) },
                { hp = 115, G("goblin", 8, 32) },
                { hp = 95, G("footpad", 8, 30), G("defias", 6, 30, 45) },
                { hp = 97, G("pillager", 10, 26), G("goblin", 6, 28, 70) },
                { hp = 100, G("goblin", 10, 26), G("footpad", 8, 28, 100) },
                { hp = 139, G("blackguard", 6, 44), G("defias", 8, 30, 60) },
                { hp = 119, G("defias", 14, 20), G("pillager", 10, 22, 100) },
                { hp = 135, G("shredder", 1, 1, 90, 60), G("goblin", 10, 26), G("footpad", 8, 26, 200) },
                { hp = 158, G("goblin", 12, 22), G("blackguard", 8, 32, 100) },
                { hp = 196, G("blackguard", 10, 26), G("pillager", 12, 20, 60) },
                { hp = 270, G("pillager", 14, 18), G("goblin", 10, 22, 100), G("footpad", 10, 20, 200) },
                { hp = 290, G("footpad", 16, 16), G("defias", 12, 20, 60) },
                { hp = 231, G("goblin", 14, 18), G("blackguard", 10, 24, 80), G("pillager", 10, 20, 200) },
                { hp = 310, G("blackguard", 12, 22), G("goblin", 12, 20, 100), G("footpad", 12, 18, 260) },
                { hp = 268, G("vancleef", 1, 1, 120, 22), G("defias", 12, 22), G("goblin", 10, 24, 100),
                    G("blackguard", 8, 26, 300) },
            },
        },
    },
}
