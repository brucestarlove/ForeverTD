-- Campaigns\Forsaken.lua - The Forsaken: "The Dark Lady's Will". Tirisfal Glades, Silverpine Forest and the
-- Hillsbrad Foothills, ending at Shadowfang Keep. Free of the Lich King, the Forsaken defend what's left of
-- Lordaeron against the Scarlet Crusade, Arugal's worgen and the Alliance, with dark rangers, necromancers,
-- apothecaries, meat wagons and banshees, and Sylvanas Windrunner. The words are in Story.lua. Names and numbers are
-- drafts.
local _, ns = ...
local Content = ns.Content
local ICON, G = Content.ICON, Content.Group
local T, C = Content.towers, Content.creeps

------------------------------------------------------------------------------------------------------------------------
-- Towers

T.ranger = {
    name = "Dark Ranger", role = "ranged", icon = ICON .. "Ability_Marksmanship", damage = "physical", air = true,
    shot = 480,
    blurb = "Fast black-fletched arrows. Hits flying creeps.",
    ranks = {
        { cost = 55, dmg = 7, range = 2300, cd = 16 },
        { cost = 45, dmg = 11, range = 2400, cd = 14 },
        { cost = 80, dmg = 17, range = 2500, cd = 12 },
    },
    specs = {
        { name = "Black Arrow", cost = 130, dmg = 18, dot = { dmg = 10, seconds = 4 }, reveal = 2500,
            blurb = "Shadow-tipped arrows: 40 more damage over 2 seconds. Reveals stealthed creeps near it." },
        { name = "Volley", cost = 140, dmg = 15, multi = 3, blurb = "Shoots three targets at once." },
    },
}

T.necromancer = {
    name = "Necromancer", role = "control", icon = ICON .. "Spell_Shadow_DeathCoil", damage = "magic", air = true,
    shot = 320,
    blurb = "Shadow bolts that cripple: they slow. Hits flying creeps.",
    ranks = {
        { cost = 75, dmg = 7, range = 2200, cd = 30, slow = 35, slowTicks = 60 },
        { cost = 55, dmg = 11, range = 2300, cd = 28, slow = 45, slowTicks = 70 },
        { cost = 90, dmg = 17, range = 2400, cd = 26, slow = 55, slowTicks = 80 },
    },
    specs = {
        { name = "Cripple", cost = 130, dmg = 20, slow = 75, slowTicks = 60,
            blurb = "Cripples its target: 75% slower." },
        { name = "Corpse Explosion", short = "Corpses", cost = 140, bane = { dmg = 30, ticks = 120 },
            blurb = "Creeps it hits explode when they die, hurting those around them." },
    },
}

T.apothecary = {
    name = "Apothecary", role = "area", icon = ICON .. "Spell_Shadow_PlagueCloud",
    alt = ICON .. "Spell_Shadow_CurseOfTounges",
    damage = "magic", pulse = true,
    blurb = "A cauldron of the New Plague: hurts every ground creep near it, and leaves it plagued.",
    ranks = {
        { cost = 90, dmg = 4, range = 1600, cd = 40, dot = { dmg = 4, seconds = 4 } },
        { cost = 70, dmg = 7, range = 1700, cd = 38, dot = { dmg = 6, seconds = 4 } },
        { cost = 110, dmg = 11, range = 1800, cd = 34, dot = { dmg = 9, seconds = 4 } },
    },
    specs = {
        { name = "Blight", cost = 140, dot = { dmg = 12, seconds = 4 }, spread = true, reveal = 1800,
            blurb = "A stronger plague that jumps to the next creep when its host dies. Reveals stealthed creeps near "
                .. "it." },
        { name = "Virulence", cost = 140, dmg = 18, vuln = { pct = 20, ticks = 120 },
            blurb = "Plagued creeps take 20% more damage from everything." },
    },
}

T.meatwagon = {
    name = "Meat Wagon", role = "siege", icon = ICON .. "Spell_Shadow_CallofBone",
    alt = ICON .. "INV_Misc_Bone_HumanSkull_01",
    damage = "physical", shot = 150,
    blurb = "Hurls diseased corpses: splash, and a little plague. Ground only.",
    ranks = {
        { cost = 100, dmg = 18, range = 2600, cd = 58, splash = 1000, dot = { dmg = 3, seconds = 3 } },
        { cost = 80, dmg = 29, range = 2700, cd = 54, splash = 1100, dot = { dmg = 4, seconds = 3 } },
        { cost = 130, dmg = 45, range = 2800, cd = 50, splash = 1300, dot = { dmg = 6, seconds = 3 } },
    },
    specs = {
        { name = "Plague Cart", cost = 140, dot = { dmg = 10, seconds = 4 }, spread = true,
            blurb = "A plague that jumps from corpse to creep." },
        { name = "Exhume Corpses", short = "Exhume", cost = 150, dmg = 100, splash = 1700,
            blurb = "Heavier loads: huge splashes." },
    },
}

T.banshee = {
    name = "Banshee", role = "signature", icon = ICON .. "Spell_Shadow_Possession",
    alt = ICON .. "Spell_Shadow_DeathCoil",
    damage = "magic", air = true, shot = 400,
    blurb = "Curses: creeps it hits take 15% more damage from everything (20% at rank 3). Its wail reveals stealthed "
        .. "creeps near it. "
        .. "Hits flying creeps.",
    ranks = {
        { cost = 100, dmg = 5, range = 2300, cd = 24, vuln = { pct = 15, ticks = 120 }, reveal = 2300 },
        { cost = 75, dmg = 9, range = 2400, cd = 22, vuln = { pct = 18, ticks = 120 }, reveal = 2400 },
        { cost = 120, dmg = 14, range = 2500, cd = 20, vuln = { pct = 20, ticks = 150 }, reveal = 2500 },
    },
    specs = {
        { name = "Curse of Agony", short = "Agony", cost = 140, dot = { dmg = 8, seconds = 4 },
            blurb = "The curse also burns: 32 more damage over 2 seconds." },
        { name = "Wail", cost = 150, pulse = true, dmg = 10, range = 2000, cd = 45, vuln = { pct = 20, ticks = 150 },
            blurb = "A wail that curses every creep near it, flyers too." },
    },
}

T.sylvanas = {
    name = "Sylvanas Windrunner", role = "hero", hero = true, npc = 10181, icon = ICON .. "Spell_Shadow_ShadowWordPain",
    alt = ICON .. "Spell_Shadow_ShadowBolt", damage = "physical", air = true, shot = 520,
    blurb = "The Banshee Queen. Her black arrows poison, and towers near her hit 10% harder.",
    ranks = { { cost = 0, dmg = 15, range = 2600, cd = 18, dot = { dmg = 6, seconds = 4 }, might = 10,
        aura = 2500 } },
    ability = { kind = "wail", name = "Wailing Arrow", range = 3000, dmg = 60, silence = 240, stun = 30, cd = 10800,
        first = 300, blurb = "Every creep within 3 cells takes 60 damage, freezes for half a second, and can't heal "
            .. "or regenerate for 4 seconds." },
}

------------------------------------------------------------------------------------------------------------------------
-- Creeps (Skeletal Warriors and Rotting Ghouls come from Alliance.lua: the Scourge haunts both)

local FLY = "Flying: only towers that hit air can reach it."
local ARMOUR = "Armoured: physical hits do half damage."
local WARD = "Warded: magic does half damage."
local STEALTH = "Stealthed: towers can't see it unless a revealing tower is near."

C.convert = { name = "Scarlet Convert", icon = ICON .. "INV_Misc_Head_Human_01", alt = ICON .. "INV_Sword_04",
    hp = 30, speed = 32, bounty = 3 }
C.zombie = { name = "Mindless Zombie", icon = ICON .. "Spell_Shadow_AnimateDead",
    alt = ICON .. "Spell_Shadow_RaiseDead",
    undead = true, hp = 34, speed = 21, bounty = 2, note = "Undead: slow, but they keep coming." }
C.duskbat = { name = "Duskbat", icon = ICON .. "Ability_Hunter_Pet_Bat", air = true, hp = 22, speed = 42, bounty = 4,
    note = FLY }
C.zealot = { name = "Scarlet Zealot", icon = ICON .. "Spell_Holy_HolySmite", hp = 44, speed = 28, resist = 50,
    bounty = 5, note = WARD }
C.crusader = { name = "Scarlet Crusader", icon = ICON .. "INV_Shield_06", alt = ICON .. "INV_Sword_04",
    hp = 60, speed = 26, armor = 50, bounty = 5, note = ARMOUR }
C.friar = { name = "Scarlet Friar", icon = ICON .. "Spell_Holy_Heal", alt = ICON .. "Spell_Holy_InnerFire",
    hp = 36, speed = 27, bounty = 6, heal = { pct = 8, range = 1600, every = 75 },
    note = "Healer: mends creeps around it. Kill it first." }
C.captain = { name = "Captain Perrine", icon = ICON .. "INV_Shield_06", alt = ICON .. "Spell_Holy_SealOfMight",
    boss = true, hp = 1300, speed = 17, armor = 40, resist = 20, bounty = 80, lives = 10, size = 34,
    ability = { kind = "summon", creep = "crusader", count = 2, every = 360, first = 200 },
    note = "Boss. A Scarlet captain who calls crusaders to her." }
C.devlin = { name = "Devlin Agamand", npc = 1657, icon = ICON .. "Spell_Shadow_RaiseDead", boss = true, undead = true,
    hp = 1300, speed = 17, regen = 12, bounty = 80, lives = 10, size = 34,
    ability = { kind = "summon", creep = "zombie", count = 3, every = 300, first = 150 },
    note = "Boss. The risen heir of Agamand Mills: regenerates, and raises zombies." }

C.gnoll = { name = "Rot Hide Gnoll", icon = ICON .. "Ability_Hunter_Pet_Hyena", alt = ICON .. "Ability_Hunter_Pet_Wolf",
    undead = true, hp = 44, speed = 30, bounty = 4, note = "Undead gnolls of Silverpine." }
C.conjuror = { name = "Dalaran Conjuror", icon = ICON .. "Spell_Arcane_Blink", alt = ICON .. "Spell_Frost_FrostBolt02",
    hp = 40, speed = 27, resist = 60, bounty = 5, note = "Warded: magic does much less." }
C.darkrunner = { name = "Moonrage Darkrunner", icon = ICON .. "Ability_Mount_WhiteDireWolf",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", stealth = true, hp = 50, speed = 41, regen = 3, bounty = 6,
    note = "A worgen: fast, regenerates, and stealthed. " .. STEALTH }
C.sonofarugal = { name = "Son of Arugal", npc = 2529, icon = ICON .. "Ability_Mount_WhiteDireWolf",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", boss = true, hp = 1300, speed = 20, regen = 10, bounty = 80, lives = 10,
    size = 34, enrage = { below = 50, pct = 150 }, note = "Boss. A great worgen: regenerates, and enrages when hurt." }
C.packleader = { name = "Bloodfang Packleader", icon = ICON .. "Ability_Mount_WhiteDireWolf",
    alt = ICON .. "Ability_Hunter_Pet_Wolf", boss = true, hp = 1200, speed = 19, regen = 8, bounty = 70, lives = 10,
    size = 32, ability = { kind = "summon", creep = "darkrunner", count = 2, every = 300, first = 150 },
    note = "Boss. Howls for his pack." }

C.farmer = { name = "Hillsbrad Farmer", icon = ICON .. "INV_Misc_Head_Human_01", alt = ICON .. "INV_Sword_04",
    hp = 26, speed = 32, bounty = 2 }
C.guard = { name = "Southshore Guard", icon = ICON .. "INV_Sword_04", hp = 70, speed = 26, armor = 50, bounty = 5,
    note = ARMOUR }
C.gryphon = { name = "Gryphon Rider", icon = ICON .. "Ability_Hunter_Pet_Owl",
    alt = ICON .. "Ability_Hunter_Pet_Vulture",
    air = true, hp = 44, speed = 40, bounty = 6, note = FLY }
C.redpath = { name = "Marshal Redpath", icon = ICON .. "INV_Sword_04", boss = true, hp = 1600, speed = 17, armor = 40,
    bounty = 90, lives = 10, size = 34,
    ability = { kind = "summon", creep = "guard", count = 2, every = 330, first = 200 },
    note = "Boss. Southshore's marshal calls his guards." }

C.protector = { name = "Dalaran Protector", icon = ICON .. "INV_Shield_06", alt = ICON .. "INV_Sword_04",
    hp = 70, speed = 25, armor = 50, bounty = 5, note = ARMOUR }
C.ataeric = { name = "Archmage Ataeric", icon = ICON .. "Spell_Arcane_Blink", alt = ICON .. "Spell_Frost_FrostBolt02",
    boss = true, hp = 1500, speed = 16, resist = 60, bounty = 90, lives = 10, size = 34,
    ability = { kind = "summon", creep = "conjuror", count = 2, every = 330, first = 200 },
    note = "Boss. A Dalaran archmage, warded, who conjures help." }

C.arugal = { name = "Archmage Arugal", npc = 4275, icon = ICON .. "Spell_Shadow_GatherShadows",
    alt = ICON .. "Spell_Shadow_ShadowBolt", boss = true, hp = 2800, speed = 15, resist = 40, bounty = 150, lives = 15,
    size = 36, ability = { kind = "blink", every = 330, first = 240, distance = 3000 },
    note = "Boss. The mad archmage who brought the worgen: he blinks ahead along the road." }

------------------------------------------------------------------------------------------------------------------------
-- Levels

Content.Campaign {
    id = "forsaken", name = "The Forsaken", title = "The Dark Lady's Will", faction = "Horde",
    color = { 0.35, 0.75, 0.3 }, crest = ICON .. "Spell_Shadow_RaiseDead", crestAlt = ICON .. "Spell_Shadow_DeathCoil",
    blurb = "Free of the Lich King, the Forsaken hold the ruins of Lordaeron against the Scarlet Crusade, Arugal's "
        .. "worgen and the Alliance.",
    unlock = { stars = 55 },
    roster = { { "ranger", 1 }, { "necromancer", 1 }, { "apothecary", 2 }, { "meatwagon", 3 }, { "banshee", 4 } },
    hero = { kind = "sylvanas", at = 5 },
    levels = {
        -- 1. Three lanes stacked down the graveyard: a tower between two of them shoots both.
        {
            id = "forsaken-1", zone = "Tirisfal Glades", name = "Deathknell", map = 1420, length = "short",
            art = { left = 0.02, top = 0.38, width = 0.6 },
            blurb = "Mindless zombies shamble on Deathknell. Build between the lanes to shoot at two at once.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 10, 2 }, { 10, 5 }, { 4, 5 }, { 4, 8 }, { 12, 8 }, { 12, 11 } },
                { air = true, { 0, 10 }, { 17, 1 } },
            },
            airPath = 2,
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 90,
                { hp = 95, G("zombie", 10, 30) },
                { hp = 100, G("convert", 10, 26), G("zombie", 8, 30, 60) },
                { hp = 125, G("duskbat", 8, 34, 0, 80), G("zombie", 10, 26, 45) },
                { hp = 155, G("zombie", 18, 16), G("convert", 10, 22, 90) },
                { hp = 175, G("convert", 14, 18), G("duskbat", 10, 26, 60) },
                { hp = 197, G("zombie", 22, 14), G("duskbat", 10, 24, 90), G("convert", 14, 16, 180) },
            },
        },
        -- 2. Two roads meet head-on in Brill's square, then march east together.
        {
            id = "forsaken-2", zone = "Tirisfal Glades", name = "Brill", map = 1420, length = "standard",
            art = { left = 0.31, top = 0.24, width = 0.6 },
            blurb = "The Crusade marches on Brill from two roads. Kill the friars first, or they heal the rest.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 8, 2 }, { 8, 6 }, { 13, 6 }, { 13, 3 }, { 17, 3 } },
                { { 4, 11 }, { 4, 9 }, { 8, 9 }, { 8, 6 }, { 13, 6 }, { 13, 3 }, { 17, 3 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 93,
                { hp = 75, G("convert", 8, 34) },
                { hp = 70, G("zealot", 5, 50), G("convert", 6, 30, 90, 100, 2) },
                { hp = 70, G("crusader", 5, 50, 0, 100, 2), G("convert", 6, 30, 150) },
                { hp = 75, G("crusader", 6, 45), G("friar", 3, 90, 60) },
                { hp = 65, G("convert", 16, 20), G("zealot", 8, 34, 60, 100, 2) },
                { hp = 95, G("zealot", 10, 30), G("crusader", 5, 40, 90, 100, 2), G("friar", 3, 80, 120, 100, 2) },
                { hp = 112, G("crusader", 8, 34), G("friar", 3, 80, 60), G("convert", 14, 20, 30, 100, 2) },
                { hp = 124, G("zealot", 12, 26, 0, 100, 2), G("convert", 16, 18, 60), G("friar", 4, 70, 90, 100, 2) },
                { hp = 139, G("crusader", 10, 30), G("zealot", 12, 26, 30, 100, 2), G("friar", 4, 70, 120) },
                { hp = 144, G("captain", 1, 1, 120, 49), G("crusader", 8, 34), G("friar", 4, 60, 150),
                    G("zealot", 12, 26, 60, 100, 2) },
            },
        },
        -- 3. A tight serpentine through the mill fields: the dead bunch up at every bend, ready for the wagon.
        {
            id = "forsaken-3", zone = "Tirisfal Glades", name = "Agamand Mills", map = 1420, length = "short",
            art = { left = 0.15, top = 0.04, width = 0.6 },
            blurb = "The Agamands' dead crowd the mill lanes. Lob a meat wagon at the bends where they bunch up.",
            cols = 16, rows = 10,
            paths = {
                { { 2, 0 }, { 2, 6 }, { 5, 6 }, { 5, 2 }, { 8, 2 }, { 8, 6 }, { 11, 6 }, { 11, 2 }, { 17, 2 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 100,
                { hp = 94, G("zombie", 16, 24) },
                { hp = 101, G("skeleton", 8, 40, 0, 84), G("zombie", 10, 24, 90, 119) },
                { hp = 107, G("ghoul", 8, 40, 0, 82), G("zombie", 12, 22, 60, 121) },
                { hp = 190, G("zombie", 24, 16), G("skeleton", 8, 36, 120, 84) },
                { hp = 152, G("skeleton", 12, 30), G("ghoul", 10, 32, 60) },
                { hp = 170, G("devlin", 1, 1, 120, 24), G("ghoul", 8, 30), G("zombie", 18, 18, 60),
                    G("skeleton", 8, 34, 240) },
            },
        },
        -- 4. The road comes down past the Sepulcher, loops and crosses itself: a banshee in the loop sees most of it.
        {
            id = "forsaken-4", zone = "Silverpine Forest", name = "The Sepulcher", map = 1421, length = "standard",
            art = { left = 0.14, top = 0.14, width = 0.6 },
            blurb = "Worgen stalk unseen through Silverpine. Put a banshee inside the loop to reveal them.",
            cols = 16, rows = 10,
            paths = {
                { { 11, 0 }, { 11, 8 }, { 5, 8 }, { 5, 5 }, { 17, 5 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 79,
                { hp = 121, G("gnoll", 10, 30) },
                { hp = 141, G("conjuror", 8, 36), G("gnoll", 8, 30, 90) },
                { hp = 154, G("gnoll", 12, 26), G("conjuror", 6, 36, 120) },
                { hp = 138, G("darkrunner", 6, 50) },
                { hp = 185, G("gnoll", 14, 22), G("darkrunner", 6, 45, 120, 81) },
                { hp = 201, G("conjuror", 12, 28), G("darkrunner", 8, 40, 90) },
                { hp = 229, G("darkrunner", 12, 32), G("gnoll", 12, 24, 60) },
                { hp = 295, G("gnoll", 18, 18), G("conjuror", 10, 28, 90), G("darkrunner", 8, 36, 180, 85) },
                { hp = 286, G("darkrunner", 16, 26), G("conjuror", 12, 26, 60) },
                { hp = 241, G("sonofarugal", 1, 1, 120, 40), G("gnoll", 14, 22), G("darkrunner", 12, 30, 90) },
            },
        },
        -- 5. Two village streets close in on the square, and the road runs back out between them.
        {
            id = "forsaken-5", zone = "Silverpine Forest", name = "Pyrewood Village", map = 1421, length = "short",
            art = { left = 0.16, top = 0.4375, width = 0.6 },
            blurb = "Pyrewood's villagers turn at nightfall. Set Sylvanas between the streets: she sees them all.",
            cols = 16, rows = 10,
            paths = {
                { { 3, 0 }, { 3, 2 }, { 13, 2 }, { 13, 5 }, { 0, 5 } },
                { { 3, 11 }, { 3, 8 }, { 13, 8 }, { 13, 5 }, { 0, 5 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 15, step = 5 },
            waves = {
                hp = 67,
                { hp = 166, G("gnoll", 10, 30), G("gnoll", 8, 34, 60, 100, 2) },
                { hp = 248, G("darkrunner", 5, 45, 0, 74), G("gnoll", 10, 30, 60, 100, 2) },
                { hp = 229, G("gnoll", 14, 22, 0, 110), G("darkrunner", 5, 45, 90, 75, 2) },
                { hp = 152, G("darkrunner", 6, 40, 0, 87), G("darkrunner", 6, 40, 30, 87, 2),
                    G("gnoll", 10, 26, 150, 117) },
                { hp = 180, G("gnoll", 16, 18, 0, 100, 2), G("darkrunner", 6, 36, 60, 70), G("gnoll", 12, 22, 150) },
                { hp = 159, G("packleader", 1, 1, 120, 37), G("gnoll", 14, 20, 0, 100, 2),
                    G("darkrunner", 6, 34, 60, 67), G("darkrunner", 5, 36, 200, 67, 2), G("gnoll", 12, 22, 240) },
            },
        },
        -- 6. The road loops round Tarren Mill's hill and back out west, lanes far apart; gryphons cut straight across.
        {
            id = "forsaken-6", zone = "Hillsbrad Foothills", name = "Tarren Mill", map = 1424, length = "standard",
            art = { left = 0.32, top = 0.0, width = 0.6 },
            blurb = "Southshore rides on Tarren Mill. The road loops round the hill; gryphons fly straight across.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 2 }, { 13, 2 }, { 13, 8 }, { 0, 8 } },
                { air = true, { 0, 10 }, { 17, 1 } },
            },
            airPath = 2,
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 108,
                { hp = 141, G("farmer", 16, 22) },
                { hp = 77, G("guard", 6, 45, 0, 77), G("farmer", 12, 22, 60, 132) },
                { hp = 156, G("gryphon", 6, 50, 0, 67), G("farmer", 14, 20, 60, 124) },
                { hp = 122, G("farmer", 24, 14, 0, 125), G("guard", 6, 40, 120, 63) },
                { hp = 131, G("guard", 10, 36), G("gryphon", 6, 45, 120, 84) },
                { hp = 195, G("gryphon", 10, 36, 0, 67), G("farmer", 20, 16, 60, 128) },
                { hp = 183, G("farmer", 28, 12, 0, 136), G("guard", 10, 34, 90, 76), G("gryphon", 6, 40, 200, 63) },
                { hp = 180, G("guard", 14, 30), G("gryphon", 10, 34, 60, 83) },
                { hp = 239, G("gryphon", 12, 30, 0, 67), G("farmer", 24, 14, 30, 146), G("guard", 10, 32, 120, 84) },
                { hp = 252, G("redpath", 1, 1, 120, 18), G("guard", 10, 32, 0, 85), G("gryphon", 10, 34, 90, 65),
                    G("farmer", 20, 14, 200, 149) },
            },
        },
        -- 7. The road forks around Ambermill's tower and rejoins: mages take the north fork, shields the south.
        {
            id = "forsaken-7", zone = "Silverpine Forest", name = "Ambermill", map = 1421, length = "standard",
            art = { left = 0.33, top = 0.36, width = 0.6 },
            blurb = "Conjurors take the north fork and protectors the south: arrows north, plague south.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 5 }, { 4, 5 }, { 4, 2 }, { 12, 2 }, { 12, 5 }, { 17, 5 } },
                { { 0, 5 }, { 4, 5 }, { 4, 8 }, { 12, 8 }, { 12, 5 }, { 17, 5 } },
            },
            blocked = { { 8, 4 }, { 7, 5 }, { 8, 5 }, { 9, 5 }, { 8, 6 } },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 95,
                { hp = 160, G("conjuror", 10, 32) },
                { hp = 77, G("protector", 6, 45, 0, 100, 2), G("conjuror", 6, 36, 90) },
                { hp = 90, G("gnoll", 12, 24), G("gnoll", 12, 24, 30, 100, 2) },
                { hp = 72, G("conjuror", 12, 28), G("protector", 8, 40, 60, 100, 2) },
                { hp = 124, G("darkrunner", 8, 40), G("gnoll", 12, 22, 60, 100, 2) },
                { hp = 129, G("protector", 10, 34, 0, 100, 2), G("conjuror", 12, 26, 30), G("darkrunner", 6, 40, 150) },
                { hp = 160, G("gnoll", 20, 16), G("protector", 10, 32, 60, 100, 2), G("conjuror", 8, 30, 120) },
                { hp = 165, G("darkrunner", 12, 30, 0, 100, 2), G("conjuror", 14, 24, 30) },
                { hp = 178, G("conjuror", 16, 22), G("protector", 14, 28, 0, 100, 2), G("darkrunner", 8, 34, 150) },
                { hp = 198, G("ataeric", 1, 1, 120, 48), G("conjuror", 12, 26), G("protector", 12, 30, 30, 100, 2),
                    G("darkrunner", 8, 34, 200, 100, 2) },
            },
        },
        -- 8. Two roads meet below the keep, then climb its switchbacks to the gate: long enough to outlast a blink.
        {
            id = "forsaken-8", zone = "Silverpine Forest", name = "Shadowfang Keep", map = 1421, length = "siege",
            art = { left = 0.15, top = 0.39, width = 0.6 },
            blurb = "Storm Arugal's keep. He blinks ahead along the road: keep towers near the top of the climb.",
            cols = 16, rows = 10,
            paths = {
                { { 0, 9 }, { 7, 9 }, { 7, 7 }, { 7, 4 }, { 2, 4 }, { 2, 2 }, { 14, 2 }, { 14, 0 } },
                { { 12, 11 }, { 12, 7 }, { 7, 7 }, { 7, 4 }, { 2, 4 }, { 2, 2 }, { 14, 2 }, { 14, 0 } },
            },
            gold = 160, lives = 20, earlyBonus = 10, waveBonus = { base = 10, step = 3 },
            waves = {
                hp = 101,
                { hp = 226, G("gnoll", 12, 30) },
                { hp = 150, G("skeleton", 8, 40, 0, 100, 2), G("gnoll", 10, 30, 150) },
                { hp = 161, G("darkrunner", 8, 40), G("gnoll", 10, 28, 120, 100, 2) },
                { hp = 160, G("ghoul", 10, 36, 0, 100, 2), G("skeleton", 8, 38, 150) },
                { hp = 165, G("conjuror", 10, 32), G("darkrunner", 8, 38, 150, 100, 2) },
                { hp = 191, G("gnoll", 20, 18), G("ghoul", 8, 34, 200, 100, 2) },
                { hp = 202, G("darkrunner", 12, 32), G("skeleton", 10, 34, 120, 100, 2) },
                { hp = 218, G("packleader", 1, 1, 90, 39), G("gnoll", 14, 22), G("ghoul", 8, 32, 200, 100, 2) },
                { hp = 280, G("conjuror", 14, 26, 0, 100, 2), G("skeleton", 12, 30, 150) },
                { hp = 297, G("darkrunner", 16, 26), G("ghoul", 12, 28, 150, 100, 2) },
                { hp = 337, G("gnoll", 24, 16, 0, 100, 2), G("conjuror", 12, 26, 200) },
                { hp = 306, G("skeleton", 14, 26), G("darkrunner", 14, 26, 150, 100, 2) },
                { hp = 385, G("ghoul", 16, 24), G("conjuror", 14, 24, 120, 100, 2), G("darkrunner", 10, 30, 300) },
                { hp = 419, G("darkrunner", 20, 20), G("skeleton", 14, 26, 150, 100, 2), G("gnoll", 16, 18, 300) },
                { hp = 436, G("arugal", 1, 1, 150, 15), G("darkrunner", 14, 24), G("conjuror", 12, 26, 200, 100, 2),
                    G("ghoul", 12, 26, 400, 100, 2) },
            },
        },
    },
}
