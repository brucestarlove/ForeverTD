-- Dev/AssetList.lua - candidate client assets for an Azeroth-themed tower defense, for the dev browsers to check.
-- Nothing here is shipped art: these are names and IDs of files already inside the WoW client, which the addon points
-- at. Icon paths and NPC IDs were written from memory of the original game, so treat every entry as a guess until
-- the browser has shown it: /td icons and /td creatures record what really loaded in ForeverTDDB.dev.checked.
local _, ns = ...
ns = ns or {}
local AssetList = {}
ns.AssetList = AssetList

local function Icon(name, note) return { name = note, file = "Interface\\Icons\\" .. name } end

AssetList.icons = {
    -- Towers, themed on class abilities
    Icon("Ability_Marksmanship", "Archer: marksmanship"),
    Icon("INV_Weapon_Bow_02", "Archer: bow"),
    Icon("INV_Weapon_Rifle_01", "Dwarven rifleman"),
    Icon("Ability_TrueShot", "Archer: trueshot"),
    Icon("Ability_UpgradeMoonGlaive", "Multi-shot"),
    Icon("Ability_ImpalingBolt", "Arcane shot"),
    Icon("Spell_Frost_FrostBolt02", "Frost mage: frostbolt"),
    Icon("Spell_Frost_FrostNova", "Frost nova (slow)"),
    Icon("Spell_Frost_IceStorm", "Blizzard (area slow)"),
    Icon("Spell_Frost_ChainsOfIce", "Chains of ice"),
    Icon("Spell_Fire_FlameBolt", "Fire mage: fireball"),
    Icon("Spell_Fire_Fireball02", "Fireball, alternate"),
    Icon("Spell_Fire_SelfDestruct", "Flamestrike (area)"),
    Icon("Spell_Fire_SearingTotem", "Searing totem"),
    Icon("Spell_Nature_Lightning", "Shaman: lightning bolt"),
    Icon("Spell_Nature_ChainLightning", "Chain lightning (bounces)"),
    Icon("Spell_Nature_StoneClawTotem", "Stoneclaw totem"),
    Icon("Spell_Nature_StrengthOfEarthTotem02", "Earth totem"),
    Icon("Spell_Holy_HolyBolt", "Priest: holy bolt"),
    Icon("Spell_Holy_HolySmite", "Smite"),
    Icon("Spell_Holy_InnerFire", "Consecration-like aura"),
    Icon("Spell_Holy_SealOfMight", "Paladin: seal of might (buff)"),
    Icon("Spell_Shadow_ShadowBolt", "Warlock: shadow bolt"),
    Icon("Spell_Shadow_CurseOfTounges", "Curse (slow)"),
    Icon("Spell_Shadow_DeathCoil", "Death coil"),
    Icon("Spell_Nature_StarFall", "Druid: moonfire"),
    Icon("Spell_Nature_Polymorph", "Polymorph (sheep!)"),
    Icon("Ability_ThunderClap", "Warrior: thunder clap (area)"),
    Icon("Ability_Warrior_Sunder", "Sunder armor"),
    Icon("INV_Misc_Bomb_01", "Engineer: bomb"),
    Icon("INV_Misc_Bomb_04", "Engineer: bomb, alternate"),
    Icon("INV_Sword_04", "Footman sword"),
    -- Creeps
    Icon("Ability_Hunter_Pet_Wolf", "Creep: wolf"),
    Icon("Ability_Hunter_Pet_Boar", "Creep: boar"),
    Icon("Ability_Hunter_Pet_Spider", "Creep: spider"),
    Icon("Ability_Hunter_Pet_Bear", "Creep: bear"),
    Icon("Ability_Hunter_Pet_Raptor", "Creep: raptor"),
    Icon("Ability_Hunter_Pet_Scorpid", "Creep: scorpid"),
    Icon("Ability_Hunter_Pet_Vulture", "Creep: vulture (flying)"),
    Icon("Ability_Hunter_Pet_Bat", "Creep: bat (flying)"),
    Icon("Ability_Hunter_Pet_Crocolisk", "Creep: crocolisk"),
    Icon("Ability_Hunter_Pet_Gorilla", "Creep: gorilla"),
    Icon("INV_Misc_Head_Murloc_01", "Creep: murloc"),
    Icon("INV_Misc_Head_Dragon_01", "Boss: dragon"),
    Icon("Spell_Shadow_RaiseDead", "Creep: undead"),
    Icon("INV_Misc_Bone_HumanSkull_01", "Creep: skeleton"),
    Icon("INV_Misc_Head_Human_01", "Creep: Defias (0.2)"),
    Icon("Ability_Hunter_Pet_Hyena", "Boss: Hogger (0.2)"),
    Icon("Ability_Druid_CatForm", "Creep: nightsaber (0.2)"),
    Icon("Spell_Nature_Regeneration", "Creep: timberling (0.2)"),
    Icon("Ability_Hunter_Pet_Owl", "Creep: owl, flying (0.2)"),
    -- Interface
    Icon("INV_Misc_Coin_01", "Gold"),
    Icon("INV_Misc_Coin_03", "Silver"),
    Icon("INV_Misc_Coin_05", "Copper"),
    Icon("Spell_Holy_SealOfSacrifice", "Lives"),
    Icon("Ability_Rogue_Sprint", "Fast forward"),
    Icon("Spell_Nature_TimeStop", "Pause"),
    Icon("INV_Misc_Rune_01", "Hearthstone (quit)"),
    Icon("INV_Misc_QuestionMark", "Unknown"),
    -- Whole textures for boards and panels (not icons)
    { name = "Rock background", file = "Interface\\FrameGeneral\\UI-Background-Rock" },
    { name = "Marble background", file = "Interface\\FrameGeneral\\UI-Background-Marble" },
    { name = "Dialog background", file = "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { name = "Parchment", file = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal" },
}

-- Creatures by NPC ID (the client fetches the model; a card game on Forever loads its portraits this way).
-- Grouped by where they live, for zone-themed levels.
local function NPC(id, name, zone) return { npc = id, name = name, zone = zone } end

AssetList.creatures = {
    NPC(6, "Kobold Vermin", "Elwynn Forest"),
    NPC(257, "Kobold Worker", "Elwynn Forest"),
    NPC(80, "Kobold Laborer", "Elwynn Forest"),
    NPC(475, "Kobold Tunneler", "Elwynn Forest"),
    NPC(38, "Defias Thug", "Elwynn Forest"),
    NPC(116, "Defias Bandit", "Elwynn Forest"),
    NPC(299, "Young Wolf", "Elwynn Forest"),
    NPC(69, "Timber Wolf", "Elwynn Forest"),
    NPC(525, "Mangy Wolf", "Elwynn Forest"),
    NPC(113, "Stonetusk Boar", "Elwynn Forest"),
    NPC(30, "Forest Spider", "Elwynn Forest"),
    NPC(46, "Murloc Forager", "Elwynn Forest"),
    NPC(735, "Murloc Streamrunner", "Elwynn Forest"),
    NPC(117, "Riverpaw Gnoll", "Elwynn Forest"),
    NPC(448, "Hogger (boss)", "Elwynn Forest"),
    NPC(36, "Harvest Golem", "Westfall"),
    NPC(114, "Harvest Watcher", "Westfall"),
    NPC(124, "Riverpaw Brute", "Westfall"),
    NPC(154, "Fleshripper", "Westfall"),
    NPC(639, "Edwin VanCleef (boss)", "The Deadmines"),
    NPC(3098, "Mottled Boar", "Durotar"),
    NPC(3101, "Vile Familiar", "Durotar"),
    NPC(3124, "Scorpid Worker", "Durotar"),
    NPC(3111, "Razormane Quilboar", "Durotar"),
    NPC(3204, "Gazz'uz (boss candidate)", "Durotar"),
    NPC(3192, "Lieutenant Benedict (boss candidate)", "Durotar"),
    NPC(2039, "Ursal the Mauler (boss candidate)", "Teldrassil"),
    NPC(2038, "Lord Melenas (boss candidate)", "Teldrassil"),
    NPC(2955, "Plainstrider", "Mulgore"),
    NPC(2958, "Prairie Wolf", "Mulgore"),
    NPC(1116, "Rockjaw Trogg", "Dun Morogh"),
    NPC(706, "Frostmane Troll Whelp", "Dun Morogh"),
    NPC(1129, "Black Bear", "Khaz Modan"), -- ID as another Forever game records it
    NPC(48, "Skeletal Warrior", "Duskwood"),
    NPC(412, "Stitches (boss)", "Duskwood"),
    NPC(10184, "Onyxia (boss)", "Onyxia's Lair"),
    NPC(11502, "Ragnaros (boss)", "Molten Core"),
}

-- Everything the campaigns point at joins the curated lists, so one pass of /td icons and /td creatures checks the
-- game's own icons (and their fallbacks), its heroes, bosses and storytellers. The game falls back to an `alt` icon
-- when the first is missing, but a model that never loads just leaves the round icon showing.
do
    local Content, Story = ns.Content, ns.Story
    local haveIcon, haveNpc = {}, {}
    for _, e in ipairs(AssetList.icons) do haveIcon[e.file] = true end
    for _, e in ipairs(AssetList.creatures) do haveNpc[e.npc] = true end
    local function AddIcon(file, note)
        if file and not haveIcon[file] then
            haveIcon[file] = true
            AssetList.icons[#AssetList.icons + 1] = { name = note, file = file }
        end
    end
    local function AddNpc(id, name, where)
        if id and not haveNpc[id] then
            haveNpc[id] = true
            AssetList.creatures[#AssetList.creatures + 1] = NPC(id, name, where)
        end
    end
    local function Sorted(t)
        local keys = {}
        for k in pairs(t or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
    end
    if Content then
        for _, camp in ipairs(Content.campaigns) do
            AddIcon(camp.crest, camp.name .. ": crest")
            AddIcon(camp.crestAlt, camp.name .. ": crest (fallback)")
            local kinds = {}
            for _, kind in ipairs(camp.roster) do kinds[#kinds + 1] = kind[1] end
            kinds[#kinds + 1] = camp.hero.kind
            for _, kind in ipairs(kinds) do
                local T = Content.towers[kind]
                AddIcon(T.icon, camp.name .. ": " .. T.name)
                AddIcon(T.alt, camp.name .. ": " .. T.name .. " (fallback)")
                if T.hero then AddNpc(T.npc, T.name .. " (hero)", camp.name) end
            end
        end
        for _, kind in ipairs(Sorted(Content.creeps)) do
            local C = Content.creeps[kind]
            AddIcon(C.icon, "Creep: " .. C.name)
            AddIcon(C.alt, "Creep: " .. C.name .. " (fallback)")
            if C.boss then AddNpc(C.npc, C.name .. " (boss)", "") end
        end
    end
    if Story then
        for _, name in ipairs(Sorted(Story.speakers)) do
            local s = Story.speakers[name]
            AddIcon(s.icon, "Speaker: " .. name)
            AddIcon(s.alt, "Speaker: " .. name .. " (fallback)")
            AddNpc(s.npc, name .. " (speaker)", "")
        end
    end
end

-- Creature displays that another Forever game loads as ModelScene actors on this client
-- (527 Murloc Streamrunner, 903 Mangy Wolf, 503 Stonetusk Boar). The bench's 3D
-- scenarios cycle through them, so a model that fails to load is the bench's fault, not the asset's.
AssetList.benchDisplays = { 527, 903, 503 }

-- Icons the 2D bench sprites cycle through (several files, so texture switching is part of the cost).
AssetList.benchIcons = {
    "Interface\\Icons\\INV_Misc_QuestionMark",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Shadow_ShadowBolt",
}

return AssetList
