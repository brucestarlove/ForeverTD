-- Campaigns\Horde.lua - The Horde: "Blood and Thunder". Durotar, the Barrens and the depths beneath Orgrimmar.
-- Thrall's young nation defends its new homeland: Darkspear headhunters and witch doctors, tauren earthshakers, orc
-- catapults and the shamans of the elements, against the Razormane, the Kul Tiras marines, the Burning Blade and
-- the Kolkar. The words (briefings, battle cries, epilogues) are in Story.lua. Names and numbers are drafts.
local _, ns = ...
local Content = ns.Content
local ICON, G = Content.ICON, Content.Group
local T, C = Content.towers, Content.creeps

------------------------------------------------------------------------------------------------------------------------
-- Towers

T.headhunter = {
    name = "Headhunter", role = "ranged", icon = ICON .. "INV_ThrowingAxe_01", alt = ICON .. "INV_Sword_04",
    damage = "physical", air = true, shot = 420,
    blurb = "A Darkspear troll who throws axes, fast. Hits flying creeps.",
    ranks = {
        { cost = 55, dmg = 8, range = 2200, cd = 17 },
        { cost = 45, dmg = 12, range = 2300, cd = 15 },
        { cost = 85, dmg = 19, range = 2400, cd = 13 },
    },
    specs = {
        { name = "Berserker", cost = 130, dmg = 14, cd = 7, blurb = "Throws twice as fast." },
        { name = "Envenomed Spears", short = "Envenomed", cost = 140, dmg = 18, dot = { dmg = 8, seconds = 4 },
            blurb = "Poisoned spears: 32 more damage over 2 seconds." },
    },
}

T.witchdoctor = {
    name = "Witch Doctor", role = "control", icon = ICON .. "Spell_Shadow_CurseOfTounges", damage = "magic",
    air = true, shot = 300,
    blurb = "Voodoo bolts that slow. Hits flying creeps.",
    ranks = {
        { cost = 70, dmg = 7, range = 2200, cd = 30, slow = 35, slowTicks = 60 },
        { cost = 55, dmg = 11, range = 2300, cd = 28, slow = 45, slowTicks = 70 },
        { cost = 90, dmg = 17, range = 2400, cd = 26, slow = 55, slowTicks = 80 },
    },
    specs = {
        { name = "Hex", cost = 130, dmg = 40, cd = 60, stun = 24,
            blurb = "Slower, heavier bolts that hex: the creep can't move for 0.4 seconds. It aims at creeps that "
                .. "aren't hexed yet." },
        { name = "Voodoo Curse", short = "Voodoo", cost = 140, vuln = { pct = 25, ticks = 120 },
            blurb = "Cursed creeps take 25% more damage from everything for 2 seconds." },
    },
}

T.earthshaker = {
    name = "Tauren Earthshaker", role = "area", icon = ICON .. "Ability_WarStomp", alt = ICON .. "Ability_ThunderClap",
    damage = "physical", pulse = true,
    blurb = "War Stomp: hurts every ground creep near it and stuns them for a moment. A creep that shakes off a stun "
        .. "can't be stunned again for half a second.",
    ranks = {
        { cost = 90, dmg = 10, range = 1600, cd = 63, stun = 10 },
        { cost = 70, dmg = 17, range = 1700, cd = 63, stun = 12 },
        { cost = 110, dmg = 30, range = 1800, cd = 63, stun = 15 },
    },
    specs = {
        { name = "Earthquake", cost = 140, dmg = 20, cd = 66, stun = false, slow = 45, slowTicks = 75,
            blurb = "A quake that hurts and slows everything near it, instead of stunning." },
        { name = "Thunder Clap", short = "Thunder Clap", cost = 150, dmg = 58, stun = 20,
            blurb = "A crushing stomp: twice the damage, and a longer stun." },
    },
}

T.catapult = {
    name = "Orc Catapult", role = "siege", icon = ICON .. "Spell_Fire_Fireball02", damage = "physical", shot = 150,
    blurb = "Slow flaming boulders that splash. Ground only.",
    ranks = {
        { cost = 100, dmg = 22, range = 2600, cd = 56, splash = 1000 },
        { cost = 80, dmg = 35, range = 2700, cd = 52, splash = 1100 },
        { cost = 130, dmg = 54, range = 2800, cd = 48, splash = 1300 },
    },
    specs = {
        { name = "Burning Oil", cost = 140, dmg = 50, dot = { dmg = 6, seconds = 4 },
            blurb = "Everything splashed burns: 24 more damage over 2 seconds." },
        { name = "Goblin Sapper", short = "Goblin", cost = 150, dmg = 110, splash = 1700, misfire = 10,
            blurb = "Huge goblin blasts, but one in ten fizzles." },
    },
}

T.shaman = {
    name = "Shaman", role = "signature", icon = ICON .. "Spell_Nature_ChainLightning", damage = "magic", air = true,
    shot = 600, jump = 1600, falloff = 70,
    blurb = "Chain lightning that jumps from creep to creep, weaker each jump. Hits flying creeps.",
    ranks = {
        { cost = 120, dmg = 12, range = 2200, cd = 40, chain = 2 },
        { cost = 90, dmg = 18, range = 2300, cd = 38, chain = 3 },
        { cost = 140, dmg = 28, range = 2400, cd = 36, chain = 3 },
    },
    specs = {
        { name = "Elemental Fury", short = "Elemental", cost = 140, dmg = 32, chain = 6,
            blurb = "Lightning jumps to six more creeps." },
        { name = "Windfury Totem", short = "Windfury", cost = 130, haste = 25, aura = 2500,
            blurb = "Other towers within 2.5 cells fire 25% faster." },
    },
}

T.thrall = {
    name = "Thrall", role = "hero", hero = true, npc = 4949, icon = ICON .. "Spell_Nature_BloodLust",
    alt = ICON .. "Spell_Nature_Lightning", damage = "magic", air = true, shot = 600, jump = 1600, falloff = 70,
    blurb = "Warchief of the Horde. He calls chain lightning, and towers near him fire 10% faster.",
    ranks = { { cost = 0, dmg = 16, range = 2400, cd = 30, chain = 2, haste = 10, aura = 2500 } },
    ability = { kind = "bloodlust", name = "Bloodlust", pct = 50, ticks = 240, cd = 10800, first = 300,
        blurb = "Every tower fires 50% faster for 4 seconds." },
}

------------------------------------------------------------------------------------------------------------------------
-- Creeps (icons marked "alt" fall back to a verified one if the client lacks the first)

local FLY = "Flying: only towers that hit air can reach it."

C.boar = { name = "Mottled Boar", npc = 3098, icon = ICON .. "Ability_Hunter_Pet_Boar",
    hp = 30, speed = 33, bounty = 3 }
C.scorpid = { name = "Scorpid Worker", npc = 3124, icon = ICON .. "Ability_Hunter_Pet_Scorpid",
    hp = 46, speed = 26, armor = 50, bounty = 5, note = "Armoured: physical hits do half damage." }
C.raptor = { name = "Bloodtalon Raptor", icon = ICON .. "Ability_Hunter_Pet_Raptor", hp = 22, speed = 49, bounty = 4,
    note = "Fast." }
C.vulture = { name = "Carrion Vulture", icon = ICON .. "Ability_Hunter_Pet_Vulture", air = true,
    hp = 26, speed = 38, bounty = 5, note = FLY }
C.imp = { name = "Vile Familiar", npc = 3101, icon = ICON .. "Spell_Shadow_SummonImp",
    alt = ICON .. "Spell_Fire_FlameBolt", demon = true, hp = 12, speed = 40, bounty = 1, size = 18,
    note = "A swarm of little demons." }
C.razormane = { name = "Razormane Raider", npc = 3111, icon = ICON .. "Ability_Hunter_Pet_Boar", hp = 36, speed = 31,
    armor = 20, bounty = 3 }
C.warlord = { name = "Razormane Warlord", npc = 3111, icon = ICON .. "Ability_Hunter_Pet_Boar", boss = true,
    hp = 1500, speed = 16, armor = 25, resist = 25, bounty = 80, lives = 10, size = 34,
    ability = { kind = "stomp", every = 360, first = 240, range = 1800, ticks = 60 },
    note = "Boss. War Stomp stuns the towers near him. Costs 10 lives if he gets through." }

C.troll = { name = "Hexed Troll", icon = ICON .. "INV_Misc_Head_Troll_01", alt = ICON .. "Spell_Nature_Polymorph",
    hp = 36, speed = 34, regen = 3, bounty = 3, note = "Regenerates." }
C.makrura = { name = "Makrura Clacker", icon = ICON .. "Ability_Hunter_Pet_Crab",
    alt = ICON .. "Ability_Hunter_Pet_Scorpid", hp = 44, speed = 24, armor = 50, bounty = 4,
    note = "Armoured: physical hits do half damage." }
C.zalazane = { name = "Zalazane", npc = 3205, icon = ICON .. "INV_Misc_Head_Troll_01",
    alt = ICON .. "Spell_Shadow_CurseOfTounges", boss = true, hp = 1100, speed = 17, resist = 30, regen = 10,
    bounty = 70, lives = 10, size = 34,
    ability = { kind = "stomp", every = 300, first = 150, range = 2000, ticks = 60 },
    note = "Boss. His voodoo hexes the towers near him." }

C.sailor = { name = "Kul Tiras Sailor", icon = ICON .. "INV_Misc_Head_Human_02", alt = ICON .. "INV_Sword_04",
    hp = 30, speed = 33, bounty = 3 }
C.marine = { name = "Kul Tiras Marine", icon = ICON .. "INV_Misc_Head_Human_01", alt = ICON .. "INV_Sword_04",
    hp = 58, speed = 26, armor = 50, bounty = 5, note = "Armoured: physical hits do half damage." }
C.benedict = { name = "Lieutenant Benedict", npc = 3192, icon = ICON .. "INV_Misc_Head_Human_01",
    alt = ICON .. "INV_Sword_04", boss = true, hp = 1400, speed = 16, armor = 40, bounty = 80, lives = 10, size = 34,
    ability = { kind = "summon", creep = "marine", count = 2, every = 360, first = 200 },
    note = "Boss. Calls marines to his side." }

C.cultist = { name = "Burning Blade Cultist", icon = ICON .. "Spell_Fire_Immolation",
    alt = ICON .. "Spell_Fire_FlameBolt", hp = 46, speed = 27, resist = 50, bounty = 5,
    note = "Warded: magic does half damage." }
C.voidwalker = { name = "Voidwalker", icon = ICON .. "Spell_Shadow_SummonVoidWalker",
    alt = ICON .. "Spell_Shadow_ShadowBolt", demon = true, hp = 130, speed = 19, armor = 40, bounty = 9, size = 28,
    note = "A demon: armoured and slow." }
C.gazzuz = { name = "Gazz'uz", npc = 3204, icon = ICON .. "Spell_Shadow_SummonImp",
    alt = ICON .. "Spell_Fire_SelfDestruct", boss = true, hp = 1300, speed = 16, resist = 40, bounty = 80, lives = 10,
    size = 34,
    ability = { kind = "summon", creep = "imp", count = 4, every = 240, first = 150 },
    note = "Boss. A Burning Blade warlock who summons imps." }

C.centaur = { name = "Kolkar Outrunner", icon = ICON .. "INV_Misc_Head_Centaur_01",
    alt = ICON .. "Ability_Rogue_Sprint", hp = 32, speed = 48, bounty = 4, note = "Fast." }
C.stormer = { name = "Kolkar Stormer", icon = ICON .. "Spell_Nature_Lightning", hp = 44, speed = 28, resist = 40,
    bounty = 5, note = "Warded: magic does much less." }
C.harpy = { name = "Witchwing Harpy", icon = ICON .. "INV_Misc_Head_Harpy_01",
    alt = ICON .. "Ability_Hunter_Pet_Vulture", air = true, hp = 28, speed = 40, bounty = 5, note = FLY }
C.kodobane = { name = "Barak Kodobane", npc = 3394, icon = ICON .. "INV_Misc_Head_Centaur_01",
    alt = ICON .. "Ability_Hunter_Pet_Raptor", boss = true, hp = 1500, speed = 18, bounty = 90, lives = 10, size = 34,
    enrage = { below = 50, pct = 160 }, note = "Boss. Enrages when hurt: much faster below half health." }

C.defender = { name = "Razorfen Defender", icon = ICON .. "INV_Misc_Head_Quilboar_01",
    alt = ICON .. "Ability_Hunter_Pet_Boar", hp = 74, speed = 23, armor = 45, bounty = 6,
    note = "Armoured: physical hits do half damage." }
C.thornweaver = { name = "Razorfen Thornweaver", icon = ICON .. "Spell_Nature_Thorns",
    alt = ICON .. "Spell_Nature_Regeneration", hp = 40, speed = 26, bounty = 6,
    heal = { pct = 8, range = 1600, every = 75 }, note = "Healer: mends creeps around it. Kill it first." }
C.charlga = { name = "Charlga Razorflank", npc = 4421, icon = ICON .. "INV_Misc_Head_Quilboar_01",
    alt = ICON .. "Ability_Hunter_Pet_Boar", boss = true, hp = 1500, speed = 16, armor = 20, resist = 20,
    bounty = 100, lives = 10, size = 34,
    ability = { kind = "summon", creep = "thornweaver", count = 2, every = 450, first = 240 },
    note = "Boss. The Crone of the Kraul calls thornweavers to heal her." }

C.earthborer = { name = "Earthborer", icon = ICON .. "INV_Misc_MonsterClaw_02",
    alt = ICON .. "Ability_Hunter_Pet_Scorpid", hp = 80, speed = 22, armor = 50, bounty = 6,
    note = "Armoured: physical hits do half damage." }
C.searingblade = { name = "Searing Blade Warlock", icon = ICON .. "Spell_Shadow_ShadowBolt", hp = 52, speed = 27,
    resist = 50, bounty = 6, note = "Warded: magic does half damage." }
C.taragaman = { name = "Taragaman the Hungerer", npc = 11520, icon = ICON .. "Spell_Shadow_SummonInfernal",
    alt = ICON .. "Spell_Fire_SelfDestruct", boss = true, demon = true, hp = 2400, speed = 15, armor = 30,
    resist = 30, bounty = 120, lives = 15, size = 38,
    ability = { kind = "stomp", every = 270, first = 180, range = 2200, ticks = 60 },
    enrage = { below = 40, pct = 150 },
    note = "Boss. A demon of fire: his Fire Nova stuns towers, and he enrages when hurt." }

------------------------------------------------------------------------------------------------------------------------
-- Levels (see Levels.lua for every field). Normal must be won by tools/sim.lua's "greedy" with zero upgrades.

Content.Campaign {
    id = "horde", name = "The Horde", title = "Blood and Thunder", faction = "Horde", color = { 0.78, 0.18, 0.1 },
    crest = ICON .. "INV_BannerPVP_01", crestAlt = ICON .. "Spell_Nature_BloodLust",
    blurb = "Thrall's young nation holds its new homeland: Durotar, the Barrens and the caverns under Orgrimmar.",
    roster = { { "headhunter", 1 }, { "witchdoctor", 1 }, { "earthshaker", 2 }, { "catapult", 3 }, { "shaman", 4 } },
    hero = { kind = "thrall", at = 5 },
    levels = {
        {
            id = "horde-1", zone = "Durotar", name = "Valley of Trials", map = 1411, length = "short",
            blurb = "Your first stand: boars, imps and scorpids on one road. Witch doctors slow; axes finish.",
            art = { left = 0.14, top = 0.38, width = 0.6 },
            cols = 16, rows = 10,
            paths = {
                { { 0, 8 }, { 6, 8 }, { 6, 3 }, { 11, 3 }, { 11, 6 }, { 17, 6 } },
                { air = true, { 0, 2 }, { 17, 9 } },
            },
            airPath = 2,
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 100,
                { hp = 80, G("boar", 8, 40) },
                { hp = 85, G("boar", 6, 34), G("imp", 12, 16, 220) },
                { hp = 90, G("scorpid", 5, 50), G("boar", 8, 30, 270) },
                { hp = 110, G("vulture", 9, 36), G("imp", 16, 14, 200) },
                { hp = 123, G("raptor", 14, 30), G("scorpid", 7, 42, 300) },
                { hp = 153, G("boar", 18, 22), G("vulture", 10, 32, 150), G("raptor", 10, 22, 420) },
            },
        },
        {
            id = "horde-2", zone = "Durotar", name = "Razor Hill", map = 1411, length = "standard",
            blurb = "Razormane raiders charge in tight packs down the switchbacks. A tauren's stomp hits them all.",
            art = { left = 0.22, top = 0.14, width = 0.6 },
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 4, 2 }, { 4, 8 }, { 8, 8 }, { 8, 3 }, { 12, 3 }, { 12, 8 }, { 17, 8 } },
                { air = true, { 0, 5 }, { 17, 5 } },
            },
            airPath = 2,
            blocked = { { 15, 1 }, { 16, 1 }, { 16, 2 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 83,
                { hp = 90, G("boar", 8, 30) },
                { hp = 82, G("razormane", 8, 28) },
                { hp = 85, G("boar", 8, 28), G("raptor", 5, 30, 120) },
                { hp = 67, G("scorpid", 5, 44, 0, 81), G("razormane", 8, 20, 120, 115) },
                { hp = 131, G("vulture", 8, 30, 0, 84), G("razormane", 10, 16, 90) },
                { hp = 139, G("raptor", 10, 18), G("scorpid", 6, 40, 60) },
                { hp = 169, G("razormane", 16, 14), G("vulture", 6, 30, 120) },
                { hp = 195, G("scorpid", 10, 32), G("raptor", 8, 20, 90), G("boar", 10, 14, 300) },
                { hp = 251, G("vulture", 10, 24), G("razormane", 14, 14, 60), G("scorpid", 6, 36, 200) },
                { hp = 253, G("warlord", 1, 1, 150, 36), G("razormane", 12, 16), G("raptor", 8, 20, 240) },
            },
        },
        {
            id = "horde-3", zone = "Durotar", name = "Sen'jin Village", map = 1411, length = "short",
            blurb = "Zalazane's hexed trolls wade in from the Echo Isles. They bunch up on the bends: splash them.",
            art = { left = 0.28, top = 0.42, width = 0.6 },
            cols = 16, rows = 10,
            -- From the beach (bottom right) the road doubles back twice: two pockets that see three legs each.
            paths = {
                { { 17, 8 }, { 9, 8 }, { 9, 5 }, { 13, 5 }, { 13, 2 }, { 3, 2 }, { 3, 7 }, { 0, 7 } },
            },
            blocked = { { 14, 10 }, { 15, 10 }, { 16, 10 }, { 16, 9 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 93,
                { hp = 83, G("troll", 8, 30) },
                { hp = 80, G("makrura", 6, 36), G("troll", 4, 30, 150) },
                { hp = 95, G("troll", 16, 14) },
                { hp = 105, G("makrura", 8, 30), G("troll", 10, 16, 120) },
                { hp = 135, G("troll", 14, 14), G("makrura", 8, 28, 90) },
                { hp = 145, G("zalazane", 1, 1, 120, 52), G("troll", 14, 14), G("makrura", 6, 30, 240) },
            },
        },
        {
            id = "horde-4", zone = "Durotar", name = "Tiragarde Keep", map = 1411, length = "standard",
            blurb = "Marines land at two docks and march as one. Armour shrugs off axes: bring lightning.",
            art = { left = 0.28, top = 0.29, width = 0.6 },
            cols = 16, rows = 10,
            -- Two docks on the east shore; their roads meet at (11, 5) and wind west to the Keep's gate.
            paths = {
                { { 17, 2 }, { 11, 2 }, { 11, 5 }, { 5, 5 }, { 5, 8 }, { 0, 8 } },
                { { 17, 9 }, { 11, 9 }, { 11, 5 }, { 5, 5 }, { 5, 8 }, { 0, 8 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 95,
                { hp = 121, G("sailor", 8, 26, 0, 100, 1) },
                { hp = 95, G("sailor", 6, 26, 0, 100, 1), G("sailor", 6, 26, 40, 100, 2) },
                { hp = 85, G("marine", 5, 40, 0, 100, 2) },
                { hp = 91, G("sailor", 12, 16, 0, 100, 1), G("marine", 4, 40, 60, 100, 2) },
                { hp = 102, G("marine", 6, 36, 0, 100, 1), G("sailor", 10, 18, 30, 100, 2) },
                { hp = 120, G("sailor", 14, 12, 0, 100, 1), G("sailor", 14, 12, 0, 100, 2) },
                { hp = 97, G("marine", 8, 32, 0, 100, 1), G("marine", 8, 32, 16, 100, 2) },
                { hp = 155, G("sailor", 16, 12, 0, 100, 1), G("marine", 8, 30, 30, 100, 2) },
                { hp = 165, G("marine", 10, 26, 0, 100, 1), G("sailor", 18, 12, 40, 100, 2) },
                { hp = 152, G("benedict", 1, 1, 150, 46, 1), G("marine", 6, 30, 0, 100, 1),
                    G("sailor", 16, 12, 0, 100, 2), G("marine", 6, 30, 240, 100, 2) },
            },
        },
        {
            id = "horde-5", zone = "Durotar", name = "Skull Rock", map = 1411, length = "standard",
            blurb = "The Burning Blade loops round Skull Rock. Wards blunt magic: axes and boulders matter.",
            art = { left = 0.25, top = 0.0, width = 0.6 },
            cols = 16, rows = 10,
            -- The road circles Skull Rock (unbuildable) and crosses itself at (6, 5) before it turns south.
            paths = {
                { { 0, 5 }, { 10, 5 }, { 10, 2 }, { 6, 2 }, { 6, 11 } },
            },
            blocked = { { 7, 3 }, { 8, 3 }, { 9, 3 }, { 7, 4 }, { 8, 4 }, { 9, 4 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 100,
                { hp = 645, G("imp", 16, 12) },
                { hp = 250, G("cultist", 8, 36) },
                { hp = 264, G("imp", 20, 10), G("cultist", 6, 34, 150) },
                { hp = 205, G("voidwalker", 4, 70) },
                { hp = 325, G("cultist", 12, 26), G("imp", 18, 10, 200, 86) },
                { hp = 263, G("voidwalker", 5, 60, 0, 86), G("imp", 24, 9, 90, 133) },
                { hp = 339, G("cultist", 14, 22, 0, 124), G("voidwalker", 4, 60, 150, 70) },
                { hp = 452, G("imp", 34, 7), G("cultist", 10, 24, 120) },
                { hp = 415, G("voidwalker", 7, 46, 0, 67), G("cultist", 14, 20, 90, 122), G("imp", 24, 8, 300) },
                { hp = 371, G("gazzuz", 1, 1, 150, 42), G("cultist", 12, 22, 0, 131), G("voidwalker", 5, 56, 280, 74) },
            },
        },
        {
            id = "horde-6", zone = "The Barrens", name = "The Crossroads", map = 1413, length = "standard",
            blurb = "Two roads cross at the Crossroads, and the Kolkar ride both. Guard the crossing.",
            art = { left = 0.22, top = 0.02, width = 0.6 },
            cols = 16, rows = 10,
            -- The west road runs east; the north road runs south; they cross at (7, 5). Harpies fly over both.
            paths = {
                { { 0, 2 }, { 7, 2 }, { 7, 8 }, { 17, 8 } },
                { { 13, 0 }, { 13, 5 }, { 2, 5 }, { 2, 11 } },
                { air = true, { 0, 9 }, { 17, 1 } },
            },
            airPath = 3,
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 105,
                { hp = 220, G("centaur", 10, 44, 0, 100, 1) },
                { hp = 100, G("razormane", 12, 40, 0, 100, 2), G("centaur", 10, 36, 200, 100, 1) },
                { hp = 240, G("harpy", 12, 40) },
                { hp = 138, G("stormer", 12, 44, 0, 100, 2), G("centaur", 14, 32, 150, 100, 1) },
                { hp = 184, G("harpy", 14, 36), G("razormane", 18, 30, 90, 100, 1) },
                { hp = 205, G("centaur", 22, 26, 0, 100, 2), G("stormer", 14, 40, 90, 100, 1) },
                { hp = 233, G("harpy", 18, 32), G("stormer", 16, 36, 90, 100, 2), G("centaur", 16, 28, 300, 100, 1) },
                { hp = 255, G("razormane", 26, 22, 0, 100, 1), G("centaur", 24, 24, 120, 100, 2) },
                { hp = 274, G("stormer", 18, 32, 0, 100, 1), G("harpy", 20, 26, 120),
                    G("centaur", 20, 22, 300, 100, 2) },
                { hp = 291, G("kodobane", 1, 1, 300, 53, 1), G("centaur", 18, 24, 0, 100, 2),
                    G("stormer", 14, 36, 90, 100, 1), G("harpy", 14, 28, 400) },
            },
        },
        {
            id = "horde-7", zone = "The Barrens", name = "Razorfen Kraul", map = 1413, length = "standard",
            blurb = "Thornweavers mend the quilboar behind their armoured defenders. Find them and kill them first.",
            art = { left = 0.12, top = 0.4375, width = 0.6 },
            cols = 16, rows = 10,
            -- A bramble maze: three tight legs one cell apart, so a tower between two legs reaches both.
            paths = {
                { { 0, 3 }, { 12, 3 }, { 12, 5 }, { 4, 5 }, { 4, 7 }, { 17, 7 } },
            },
            blocked = { { 6, 4 }, { 7, 4 }, { 10, 6 }, { 11, 6 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 103,
                { hp = 252, G("razormane", 12, 30) },
                { hp = 172, G("defender", 6, 44) },
                { hp = 175, G("thornweaver", 4, 50, 0, 86), G("razormane", 10, 26, 60) },
                { hp = 201, G("razormane", 16, 22), G("defender", 5, 44, 120) },
                { hp = 205, G("defender", 10, 38), G("thornweaver", 4, 70, 90) },
                { hp = 251, G("razormane", 22, 18), G("thornweaver", 5, 60, 60) },
                { hp = 247, G("defender", 12, 34), G("thornweaver", 6, 56, 100) },
                { hp = 306, G("razormane", 24, 16), G("defender", 10, 34, 90) },
                { hp = 308, G("defender", 14, 30), G("thornweaver", 6, 56, 90), G("razormane", 14, 18, 300) },
                { hp = 318, G("charlga", 1, 1, 200, 39), G("defender", 12, 32), G("thornweaver", 4, 70, 120) },
            },
        },
        {
            id = "horde-8", zone = "Orgrimmar", name = "Ragefire Chasm", map = 1454, length = "siege",
            blurb = "Two tunnels meet under Orgrimmar. Armoured borers, warded warlocks: mix axes and magic.",
            art = { left = 0.2, top = 0.22, width = 0.6 },
            cols = 16, rows = 10,
            -- Two tunnels (west and north) meet head-on at (9, 5) and wind together to the exit.
            paths = {
                { { 0, 2 }, { 6, 2 }, { 6, 5 }, { 9, 5 }, { 9, 8 }, { 14, 8 }, { 14, 3 }, { 17, 3 } },
                { { 12, 0 }, { 12, 5 }, { 9, 5 }, { 9, 8 }, { 14, 8 }, { 14, 3 }, { 17, 3 } },
            },
            blocked = { { 11, 6 }, { 11, 7 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 89,
                { hp = 540, G("imp", 16, 12, 0, 100, 1) },
                { hp = 195, G("earthborer", 6, 44, 0, 100, 2) },
                { hp = 210, G("searingblade", 8, 36, 0, 100, 1), G("imp", 12, 12, 120, 100, 2) },
                { hp = 385, G("imp", 20, 10, 0, 100, 1), G("imp", 16, 10, 40, 100, 2) },
                { hp = 145, G("voidwalker", 4, 64, 0, 100, 2), G("searingblade", 8, 34, 90, 121, 1) },
                { hp = 175, G("earthborer", 10, 36, 0, 100, 1), G("imp", 18, 10, 90, 100, 2) },
                { hp = 205, G("searingblade", 12, 30, 0, 100, 2), G("earthborer", 6, 40, 90, 100, 1) },
                { hp = 240, G("imp", 28, 8, 0, 100, 1), G("voidwalker", 5, 56, 60, 100, 2) },
                { hp = 264, G("voidwalker", 7, 50, 0, 100, 1), G("searingblade", 12, 28, 60, 100, 2) },
                { hp = 288, G("earthborer", 12, 32, 0, 100, 2), G("imp", 24, 8, 90, 100, 1) },
                { hp = 315, G("searingblade", 14, 26, 0, 100, 1), G("earthborer", 10, 32, 60, 100, 2) },
                { hp = 309, G("imp", 34, 7, 0, 100, 2), G("voidwalker", 7, 50, 60, 100, 1) },
                { hp = 359, G("voidwalker", 9, 44, 0, 100, 2), G("searingblade", 14, 26, 60, 100, 1) },
                { hp = 375, G("earthborer", 14, 28, 0, 100, 1), G("searingblade", 14, 26, 60, 100, 2),
                    G("imp", 24, 8, 300, 100, 1) },
                { hp = 318, G("taragaman", 1, 1, 240, 19, 1), G("searingblade", 12, 28, 0, 100, 2),
                    G("earthborer", 10, 32, 60, 100, 1), G("voidwalker", 5, 56, 360, 100, 2) },
            },
        },
    },
}
