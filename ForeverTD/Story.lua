-- Story.lua - everything the campaigns say, as plain text (pure Lua 5.1, no WoW calls): each campaign's opening and
-- closing words, and for each level a briefing, battle cries at chosen waves, a line when the boss appears, and a few
-- words after a victory. Edit freely: names, lines and speakers are drafts for Bruce.
--   Story.speakers[name]  = { npc (3D portrait in briefings), icon, alt }; a boss speaks with its own creep's face
--   Story.campaigns[id]   = { intro = { speaker, text }, outro = { speaker, text } }
--   Story.levels[id]      = { briefing = { speaker, text }, barks = { [wave] = { speaker, text } },
--                             boss = { speaker, text }, victory = text }
-- Keep briefings under about 330 characters and battle cries under about 85, so they fit their panels.
local _, ns = ...
ns = ns or {}
local Story = { campaigns = {}, levels = {}, speakers = {} }
ns.Story = Story

local ICON = "Interface\\Icons\\"
local function Who(npc, icon, alt) return { npc = npc, icon = ICON .. icon, alt = alt and ICON .. alt } end

Story.speakers = {
    -- the Horde
    ["Thrall"] = Who(4949, "Spell_Nature_BloodLust", "Spell_Nature_Lightning"),
    ["Gornek"] = Who(3143, "INV_Misc_Head_Orc_01", "INV_Sword_04"),
    ["Orgnil Soulscar"] = Who(3142, "INV_Misc_Head_Orc_01", "INV_Sword_04"),
    ["Vol'jin"] = Who(10540, "INV_Misc_Head_Troll_01", "Spell_Shadow_CurseOfTounges"),
    ["Master Gadrin"] = Who(3188, "Spell_Shadow_CurseOfTounges"),
    ["Thork"] = Who(3429, "INV_Misc_Head_Orc_01", "INV_Sword_04"),
    ["Neeru Fireblade"] = Who(3216, "Spell_Shadow_ShadowBolt"),
    -- the Alliance
    ["Bolvar Fordragon"] = Who(1748, "Spell_Holy_DivineIntervention", "Spell_Holy_HolyBolt"),
    ["Marshal McBride"] = Who(197, "INV_Misc_Head_Human_01", "INV_Sword_04"),
    ["Marshal Dughan"] = Who(240, "INV_Misc_Head_Human_01", "INV_Sword_04"),
    ["Warden Thelwater"] = Who(1719, "INV_Misc_Head_Human_01", "INV_Sword_04"),
    ["Gryan Stoutmantle"] = Who(234, "INV_Misc_Head_Human_01", "INV_Sword_04"),
    ["Commander Ebonlocke"] = Who(264, "INV_Misc_Head_Human_01", "INV_Sword_04"),
    -- the Sentinels
    ["Tyrande Whisperwind"] = Who(7999, "Ability_Mount_WhiteTiger", "Ability_TrueShot"),
    ["Conservator Ilthalaine"] = Who(2079, "Spell_Nature_Regeneration"),
    ["Sentinel Kyra Starsong"] = Who(2081, "Ability_UpgradeMoonGlaive"),
    ["Fandral Staghelm"] = Who(3516, "Spell_Nature_Regeneration"),
    ["Sentinel Glynda Nal'Shea"] = Who(2930, "Ability_UpgradeMoonGlaive"),
    ["Thundris Windweaver"] = Who(3649, "Spell_Nature_StarFall"),
    ["Raene Wolfrunner"] = Who(3691, "Ability_UpgradeMoonGlaive"),
    ["Delgren the Purifier"] = Who(3663, "Spell_Nature_StarFall"),
    -- the Forsaken
    ["Sylvanas Windrunner"] = Who(10181, "Spell_Shadow_ShadowWordPain", "Spell_Shadow_ShadowBolt"),
    ["Executor Arren"] = Who(1570, "Spell_Shadow_RaiseDead"),
    ["Apothecary Johaan"] = Who(1518, "Spell_Shadow_PlagueCloud", "Spell_Shadow_CurseOfTounges"),
    ["Coleman Farthing"] = Who(1500, "Spell_Shadow_RaiseDead"),
    ["High Executor Hadrec"] = Who(1952, "Spell_Shadow_RaiseDead"),
    ["High Executor Darthalia"] = Who(2215, "Spell_Shadow_RaiseDead"),
    ["Varimathras"] = Who(2425, "Spell_Shadow_SummonFelHunter", "Spell_Shadow_ShadowBolt"),
}

-- Who's talking: a known speaker, else the creep of that name (bosses speak with their own face), else a question
-- mark.
function Story.Speaker(name)
    local s = Story.speakers[name]
    if s then return s end
    local creeps = ns.Content and ns.Content.creeps or {}
    for _, C in pairs(creeps) do
        if C.name == name then
            s = { npc = C.npc, icon = C.icon, alt = C.alt }
            Story.speakers[name] = s
            return s
        end
    end
    return { icon = ICON .. "INV_Misc_QuestionMark" }
end

local C, L = Story.campaigns, Story.levels

------------------------------------------------------------------------------------------------------------------------
-- The Horde: Blood and Thunder

C.horde = {
    intro = { "Thrall", "The Horde crossed the sea to find a home. Durotar is harsh land, but it is ours, and every "
        .. "clan that would take it from us will learn what the Horde is. Lok'tar ogar!" },
    outro = { "Thrall", "The Burning Blade is broken, the Razormane and the Kolkar beaten back, and Durotar is ours. "
        .. "Rest, champion. The Horde owes you its home." },
}

L["horde-1"] = {
    briefing = { "Gornek", "Welcome to the Valley of Trials, young one. Every orc and troll who would serve the "
        .. "Horde is tested here. The boars and scorpids are bad enough, but now the Burning Blade's imps creep out of "
        .. "the caves. Darkspear headhunters and witch doctors stand with you. Show us what you can do." },
    barks = {
        [1] = { "Gornek", "Here they come. Headhunters, on the high ground!" },
        [2] = { "Gornek", "Imps! The Burning Blade's familiars. Small, but there are many." },
        [4] = { "Gornek", "Vultures above! Only some of your towers can reach the sky." },
        [6] = { "Gornek", "One last push. Hold the valley!" },
    },
    victory = "The valley holds. Gornek sends you east with a nod: Razor Hill needs every blade it can get.",
}

L["horde-2"] = {
    briefing = { "Orgnil Soulscar", "Razor Hill is the first town the Horde built on this shore, and the "
        .. "Razormane want it burned. Their warlord drives boars and scorpids up the road ahead of his raiders. The "
        .. "tauren of Mulgore have sent us an Earthshaker. When the warlord stomps, the earth will answer." },
    barks = {
        [1] = { "Orgnil Soulscar", "Quilboar on the road! Hold them at the bends." },
        [5] = { "Orgnil Soulscar", "Vultures circling. They fly straight over the walls." },
        [10] = { "Orgnil Soulscar", "The Warlord himself! Spread your towers: his stomp stuns anything close." },
    },
    boss = { "Razormane Warlord", "Razor Hill will burn, greenskins!" },
    victory = "The warlord falls in the dust of Razor Hill. Word comes up the coast: the Darkspear need help at "
        .. "Sen'jin.",
}

L["horde-3"] = {
    briefing = { "Vol'jin", "My people found safety in Durotar, but not all of us. The witch doctor Zalazane has "
        .. "hexed our kin on the Echo Isles, and now he sends them against Sen'jin with the makrura from the shallows. "
        .. "Bring your catapults, mon. We save who we can." },
    barks = {
        [1] = { "Master Gadrin", "Hexed trolls! They heal their wounds. Burn them down fast." },
        [2] = { "Vol'jin", "Makrura shells are thick. Boulders, not arrows!" },
        [6] = { "Vol'jin", "Zalazane comes himself. Keep your towers apart: his voodoo freezes them." },
    },
    boss = { "Zalazane", "The loa have abandoned you, Vol'jin!" },
    victory = "Zalazane flees back across the water, his curse broken for now. The Darkspear will remember who stood "
        .. "with them.",
}

L["horde-4"] = {
    briefing = { "Thrall", "Admiral Proudmoore's marines still hold Tiragarde Keep on our coast, and now they march "
        .. "on our farms. I would rather have peace with the humans, but not at the cost of our home. Their armour "
        .. "turns aside axes. Take a shaman: the storm cares nothing for steel." },
    barks = {
        [1] = { "Thrall", "Sailors first. Their marines will follow." },
        [3] = { "Orgnil Soulscar", "Kul Tiras marines: heavy plate. Lightning finds the gaps." },
        [10] = { "Thrall", "Lieutenant Benedict leads the last assault. He'll call his marines to him." },
    },
    boss = { "Lieutenant Benedict", "For Kul Tiras! For the Admiral!" },
    victory = "Benedict's marines fall back behind their walls. Thrall sends word: \"Well fought. Come to Skull "
        .. "Rock. The Burning Blade has shown its face.\"",
}

L["horde-5"] = {
    briefing = { "Thrall", "The Burning Blade is a cult of orcs who still worship the demons that once enslaved us. "
        .. "They hide in the caves of Skull Rock, summoning imps and voidwalkers. This time I fight beside you. Their "
        .. "warlocks ward themselves against magic: let axes and boulders do the work." },
    barks = {
        [1] = { "Thrall", "Imps first. The Blade sends its familiars ahead." },
        [2] = { "Thrall", "Cultists! Warded against spells. Axes, stones, stomps!" },
        [4] = { "Thrall", "Voidwalkers: demons made of shadow. They are slow; make them pay for it." },
        [7] = { "Thrall", "When the moment comes, I will call the Bloodlust. Watch the towers roar." },
        [10] = { "Thrall", "Gazz'uz! He'll fill the road with imps. Strike him down!" },
    },
    boss = { "Gazz'uz", "The Blade will have your soul, Warchief!" },
    victory = "Gazz'uz dies screaming a name: Taragaman. Thrall's face darkens. \"Whatever the Blade is planning, it "
        .. "is bigger than one cave.\"",
}

L["horde-6"] = {
    briefing = { "Thork", "The Crossroads is where the Horde's roads meet: north to Orgrimmar, south through the "
        .. "Barrens, west to Mulgore. The Kolkar centaurs want it, and Barak Kodobane rides at their head. His "
        .. "outriders are fast and his harpies faster. Lose the Crossroads and we lose the Barrens." },
    barks = {
        [1] = { "Thork", "Kolkar outriders! Slow them, or they'll ride right through." },
        [2] = { "Thork", "Razormane raiders, riding with the centaurs." },
        [3] = { "Thork", "Witchwing harpies overhead!" },
        [4] = { "Thork", "Stormers: centaur shamans, warded against lightning." },
        [10] = { "Thork", "Barak Kodobane! Wound him and he goes wild. Finish it fast." },
    },
    boss = { "Barak Kodobane", "The Barrens belong to the Kolkar!" },
    victory = "The centaur charge breaks at the Crossroads. The caravans roll again, and the Razormane in the south "
        .. "have taken notice.",
}

L["horde-7"] = {
    briefing = { "Thrall", "The Razormane we drove from Durotar have gone home to the Kraul, a maze of giant thorns "
        .. "where their crone, Charlga Razorflank, works her magic. Her thornweavers heal every quilboar near them. "
        .. "Strike at the heart of the thorns and the raids end." },
    barks = {
        [1] = { "Thrall", "Razormane, back for more." },
        [2] = { "Thrall", "Razorfen defenders: thick hides and thicker skulls." },
        [3] = { "Thrall", "Thornweavers! They mend the others. Kill them first." },
        [10] = { "Thrall", "Charlga calls her weavers. Burn through the thorns!" },
    },
    boss = { "Charlga Razorflank", "The thorns will drink your blood!" },
    victory = "Charlga's thorns wither. Among her things, a letter in the Burning Blade's hand: the cult is "
        .. "gathering beneath Orgrimmar itself.",
}

L["horde-8"] = {
    briefing = { "Neeru Fireblade", "Beneath the capital lies Ragefire Chasm, a cave of fire and rock. The Searing "
        .. "Blade, the cult's deepest cell, have opened it to a demon: Taragaman the Hungerer. If he breaks out, "
        .. "Orgrimmar burns. Everything you have learned, we need now." },
    barks = {
        [1] = { "Neeru Fireblade", "Imps by the dozen. The cult is spending everything it has." },
        [2] = { "Thrall", "Earthborers, out of the deep rock. Armoured like dwarves." },
        [3] = { "Neeru Fireblade", "Searing Blade warlocks: warded. Axes and boulders!" },
        [8] = { "Thrall", "Hold, Horde! We are almost through!" },
        [15] = { "Thrall", "Taragaman! His fire stuns everything near him. For the Horde!" },
    },
    boss = { "Taragaman the Hungerer", "Your souls will feed me for an age!" },
    victory = "Taragaman's fire goes out. Above, Orgrimmar sleeps, never knowing how close it came.",
}

------------------------------------------------------------------------------------------------------------------------
-- The Alliance: Shadows over Stormwind

C.alliance = {
    intro = { "Bolvar Fordragon", "King Varian has vanished, and Stormwind's armies are spread thin. In the "
        .. "farmlands, a brotherhood of masked men grows bolder by the day. Hold the kingdom together until the king "
        .. "returns. Stormwind is counting on you." },
    outro = { "Bolvar Fordragon", "Westfall can plant again, and Stormwind can sleep. As for that letter... leave it "
        .. "with me. Some shadows reach higher than the Deadmines." },
}

L["alliance-1"] = {
    briefing = { "Marshal McBride", "Northshire Abbey has stood in peace for years. This week the kobolds of Echo "
        .. "Ridge Mine boiled out like ants, and Defias cutthroats have been seen in the woods. A dwarven rifleman and "
        .. "a Kirin Tor mage have answered the call. Keep the road to the abbey clear." },
    barks = {
        [1] = { "Marshal McBride", "Kobolds! They'll shout about candles. Don't let them through." },
        [2] = { "Marshal McBride", "Wolves from the hills. Fast ones. Use the frost!" },
        [3] = { "Marshal McBride", "Defias thugs, wearing their red masks openly now." },
        [6] = { "Marshal McBride", "The last of them. Hold the valley!" },
    },
    victory = "Northshire is quiet again. Marshal McBride frowns over a captured red mask: \"They're organised. Get "
        .. "to Goldshire.\"",
}

L["alliance-2"] = {
    briefing = { "Marshal Dughan", "Murlocs have come up out of Crystal Lake by the hundred, right to Goldshire's "
        .. "doors. They're weak alone, but they never come alone. A gnomish engineer just rode in from Ironforge with "
        .. "a cart full of bombs. I think you know what to do." },
    barks = {
        [1] = { "Marshal Dughan", "Here they come, gurgling all the way. Splash them!" },
        [3] = { "Marshal Dughan", "Defias among the murlocs. Someone's herding them." },
        [4] = { "Marshal Dughan", "That's not a wave, that's a flood!" },
        [6] = { "Marshal Dughan", "One more flood. Hold Goldshire!" },
    },
    victory = "Goldshire's inn opens its doors again. Marshal Dughan has new orders: Hogger's gnolls are on the move "
        .. "at Forest's Edge.",
}

L["alliance-3"] = {
    briefing = { "Marshal Dughan", "Hogger. Every child in Elwynn knows the name. The big gnoll has gathered the "
        .. "Riverpaw, and he's coming from the west and the south at once. A priest from Northshire brings the Light: "
        .. "a holy pulse that scours the road. Don't let Hogger reach the town." },
    barks = {
        [1] = { "Marshal Dughan", "Murlocs again, on both roads. Watch where they meet." },
        [3] = { "Marshal Dughan", "Defias on the south road!" },
        [10] = { "Marshal Dughan", "HOGGER! He heals, and he goes berserk when he's hurt. Bring him down!" },
    },
    boss = { "Hogger", "Grrr... fresh meat!" },
    victory = "Hogger is finally down. The Defias with his gnolls carried orders signed with a black mark. Bolvar "
        .. "Fordragon wants you in Stormwind.",
}

L["alliance-4"] = {
    briefing = { "Warden Thelwater", "The Stockade's prisoners have risen, and the Defias inside are leading them. "
        .. "Bazil Thredd, the Brotherhood's man on the inside, is opening cell after cell. Stop them before they pour "
        .. "into the Mage Quarter. Every one of them, we put away once already." },
    barks = {
        [1] = { "Warden Thelwater", "Convicts! They're in the canals!" },
        [2] = { "Warden Thelwater", "Defias thugs among them. Somebody armed them from outside." },
        [3] = { "Warden Thelwater", "Kobold geomancers! They heal the rest. Kill them first." },
        [6] = { "Warden Thelwater", "Thredd himself! He'll keep opening cells until he falls." },
    },
    boss = { "Bazil Thredd", "The Brotherhood remembers the masons Stormwind cheated!" },
    victory = "Bazil Thredd talks, eventually: the Defias are the stonemasons who rebuilt Stormwind and were never "
        .. "paid. Their leader waits in Westfall.",
}

L["alliance-5"] = {
    briefing = { "Gryan Stoutmantle", "Westfall was Stormwind's breadbasket. Now the farms burn, the harvest "
        .. "golems run wild and the Defias rule the roads. My People's Militia holds Sentinel Hill, barely. Their "
        .. "footpads move unseen; a paladin's light will show them. And watch the sky for fleshrippers." },
    barks = {
        [1] = { "Gryan Stoutmantle", "Defias thugs. The usual." },
        [2] = { "Gryan Stoutmantle", "Pillagers: warded against magic. Let the rifles talk." },
        [3] = { "Gryan Stoutmantle", "Footpads! You won't see them until the paladin's light finds them." },
        [4] = { "Gryan Stoutmantle", "Fleshrippers, circling over the fields." },
        [5] = { "Gryan Stoutmantle", "Harvest watchers. Steel scarecrows, and tough." },
        [10] = { "Gryan Stoutmantle", "Everything they've got. Hold the hill!" },
    },
    victory = "Sentinel Hill holds, and the People's Militia cheers. Gryan points south: \"Moonbrook. That's where "
        .. "they're coming from.\"",
}

L["alliance-6"] = {
    briefing = { "Bolvar Fordragon", "I came to see this Brotherhood for myself. Moonbrook was a village; now it is "
        .. "the Defias stronghold, and they have stolen a gnomish harvester, the Foe Reaper 4000, to lead their "
        .. "attack. Stand with me. When it matters most, my Divine Shield will hold the line." },
    barks = {
        [1] = { "Bolvar Fordragon", "For Stormwind! Let them come." },
        [4] = { "Gryan Stoutmantle", "Fleshrippers! The whole sky's black with them." },
        [8] = { "Bolvar Fordragon", "If they break through, I will shield the road. Fight on." },
        [10] = { "Bolvar Fordragon", "The Foe Reaper! Its slam stuns towers. Spread out!" },
    },
    boss = { "Foe Reaper 4000", "HARVEST. HARVEST. HARVEST." },
    victory = "The Foe Reaper lies in pieces, and in its wreck, a map of the old mines under Moonbrook: the "
        .. "Deadmines. But first, Duskwood is begging for help.",
}

L["alliance-7"] = {
    briefing = { "Commander Ebonlocke", "Darkshire is dying. The dead walk out of Raven Hill, worgen hunt the woods, "
        .. "and something worse is coming: Stitches, an abomination sewn together by a necromancer, marching on our "
        .. "gate. The Light is strongest against the dead. Use it." },
    barks = {
        [1] = { "Commander Ebonlocke", "Skeletons! The Light hurts the dead the most." },
        [3] = { "Commander Ebonlocke", "Nightbane worgen! Fast, and hidden in the dark." },
        [10] = { "Commander Ebonlocke", "Stitches! Gods, it's huge. Don't let it reach the gate!" },
    },
    boss = { "Stitches", "Stitches... hungry!" },
    victory = "Stitches falls in the mud outside Darkshire. The night watch will sleep tonight, for the first time in "
        .. "weeks.",
}

L["alliance-8"] = {
    briefing = { "Gryan Stoutmantle", "The Deadmines. Edwin VanCleef built half of Stormwind with his own hands, and "
        .. "when the nobles wouldn't pay, he built an army instead. His goblins are building a warship down there. "
        .. "Goblins, blackguards in the shadows, Sneed's shredder: end it, for Westfall." },
    barks = {
        [1] = { "Gryan Stoutmantle", "Into the mines. Watch every shadow." },
        [2] = { "Gryan Stoutmantle", "Goblins: VanCleef pays them well. Armoured, too." },
        [6] = { "Gryan Stoutmantle", "Blackguards: stealthed, and armoured too." },
        [8] = { "Gryan Stoutmantle", "Sneed's shredder! Heavy steel, coming slow." },
        [15] = { "Gryan Stoutmantle", "VanCleef! He'll call his blackguards and fight like a cornered wolf." },
    },
    boss = { "Edwin VanCleef", "None may challenge the Brotherhood!" },
    victory = "VanCleef is dead and the Brotherhood broken. On his body, an unsent letter to a noble lady of "
        .. "Stormwind's court. Who was paying him?",
}

------------------------------------------------------------------------------------------------------------------------
-- The Sentinels: Wrath of the Wild

C.sentinels = {
    intro = { "Tyrande Whisperwind", "Elune's light still shines on Teldrassil, but the forests below are sick. "
        .. "Satyrs whisper in the shadows, the Twilight's Hammer gathers on the shore, and orcs cut our trees in "
        .. "Ashenvale. The Sentinels will answer. Will you lead them?" },
    outro = { "Tyrande Whisperwind", "The forests will heal. They always do, in time. Thank you, friend of the "
        .. "Sentinels. Elune watches over you." },
}

L["sentinels-1"] = {
    briefing = { "Conservator Ilthalaine", "Shadowglen was the first place to wake beneath the World Tree. Now "
        .. "fel-tainted grellkin crawl out of Shadowthread Cave, and the young nightsabers have gone wild. A Sentinel "
        .. "archer and a dryad will hold the glade with you. Learn the forest's rhythm." },
    barks = {
        [1] = { "Conservator Ilthalaine", "Grellkin. Tiny, ugly, and many." },
        [2] = { "Conservator Ilthalaine", "More of them. They breed in the dark of the cave." },
        [3] = { "Conservator Ilthalaine", "Nightsabers! The dryad's poison will slow them." },
        [6] = { "Conservator Ilthalaine", "The last of them. Hold the glade!" },
    },
    victory = "Shadowglen is calm again, but the taint came from somewhere. Sentinel Kyra Starsong sends word: the "
        .. "Gnarlpine have turned.",
}

L["sentinels-2"] = {
    briefing = { "Sentinel Kyra Starsong", "The Gnarlpine furbolgs were our friends once. Something has driven "
        .. "them mad, and their mystics heal the pack as it runs. A moonwell's light reaches even the owls above. Kill "
        .. "the mystics first, and the rest will break." },
    barks = {
        [1] = { "Sentinel Kyra Starsong", "Nightsabers in the gardens!" },
        [2] = { "Sentinel Kyra Starsong", "Gnarlpine mystics! They mend the others. Target them!" },
        [3] = { "Sentinel Kyra Starsong", "Strigid owls, off the lake. The moonwell can reach them." },
        [5] = { "Sentinel Kyra Starsong", "Timberlings: bark-skinned and slow to die." },
    },
    victory = "The Gnarlpine scatter into the trees. Kyra kneels by a fallen mystic: \"Fel. Someone poisoned "
        .. "them.\"",
}

L["sentinels-3"] = {
    briefing = { "Fandral Staghelm", "Webwood spiders have come up through the roots into the Cenarion Enclave "
        .. "itself, and Ursal the Mauler, chief of the maddened Gnarlpine, charges behind them. Kill a lurker and its "
        .. "hatchlings pour out. An Ancient Protector has uprooted itself to defend us." },
    barks = {
        [1] = { "Fandral Staghelm", "Webwood lurkers. When they die, their young pour out." },
        [3] = { "Fandral Staghelm", "Gnarlpine and timberlings, side by side." },
        [10] = { "Fandral Staghelm", "Ursal! He heals those around him. Bring him down!" },
    },
    boss = { "Ursal the Mauler", "The forest is ours now, elf!" },
    victory = "Ursal falls, and the Enclave is saved. Fandral is grim: \"The corruption came from Fel Rock. Satyrs.\"",
}

L["sentinels-4"] = {
    briefing = { "Tyrande Whisperwind", "Satyrs were night elves once, before they gave themselves to demons. Lord "
        .. "Melenas leads them in the cave called Fel Rock, and they move in shadow, unseen. The druids of the talon "
        .. "will light them up with Faerie Fire. Then they can be struck like anything else." },
    barks = {
        [1] = { "Tyrande Whisperwind", "Grellkin first. The satyrs send their pets ahead." },
        [2] = { "Tyrande Whisperwind", "Nightsabers among the grellkin, maddened by the fel." },
        [3] = { "Tyrande Whisperwind", "Satyrs! You can't hit what you can't see. Get the druid close." },
        [6] = { "Tyrande Whisperwind", "Lord Melenas. He calls more satyrs out of the dark." },
    },
    boss = { "Lord Melenas", "Your goddess is blind, priestess!" },
    victory = "Melenas is slain and Fel Rock cleansed. Tyrande looks across the sea to Darkshore: \"The rot goes "
        .. "deeper than Teldrassil. I'm coming with you.\"",
}

L["sentinels-5"] = {
    briefing = { "Sentinel Glynda Nal'Shea", "Auberdine is our only harbour on the mainland, and the coast has gone "
        .. "mad. The Blackwood furbolgs ate tainted food and turned, the Greymist murlocs are swarming, and tide "
        .. "crawlers came up out of the sea. With the High Priestess here, we will not fall." },
    barks = {
        [1] = { "Sentinel Glynda Nal'Shea", "Murlocs! The whole shoreline is moving." },
        [2] = { "Sentinel Glynda Nal'Shea", "Blackwood furbolgs, mad with corruption." },
        [3] = { "Sentinel Glynda Nal'Shea", "Tide crawlers. Hard shells, slow legs." },
        [10] = { "Tyrande Whisperwind", "Murkdeep calls his tribe. Starfall will meet them." },
    },
    boss = { "Murkdeep", "Mrgllglglgl!" },
    victory = "Murkdeep's tribe slips back into the sea. Thundris Windweaver has news: the Twilight's Hammer is "
        .. "digging at the Master's Glaive.",
}

L["sentinels-6"] = {
    briefing = { "Thundris Windweaver", "The Master's Glaive is an old demon's blade, sunk in the earth since the War "
        .. "of the Ancients. The Twilight's Hammer has come to dig it up, and the ghosts of the highborne drift around "
        .. "it, warded and angry. Their master, Delmanis the Hated, steps through shadow." },
    barks = {
        [1] = { "Thundris Windweaver", "Twilight disciples. Warded, and they heal each other." },
        [2] = { "Thundris Windweaver", "Cursed highborne! Ghosts in the air." },
        [3] = { "Tyrande Whisperwind", "Satyrs again, hiding among them." },
        [10] = { "Thundris Windweaver", "Delmanis! He blinks ahead along the road. Don't let him slip past!" },
    },
    boss = { "Delmanis the Hated", "The old gods are waking, child!" },
    victory = "Delmanis falls beside the Glaive. His notes speak of a temple in Ashenvale, and of orcs cutting a road "
        .. "straight to it.",
}

L["sentinels-7"] = {
    briefing = { "Raene Wolfrunner", "The Warsong Clan has come to Ashenvale with axes and shredders, cutting our "
        .. "oldest trees for lumber. Hellscream's people killed the demigod Cenarius here once; they will not take the "
        .. "forest too. Make them remember why these woods are feared." },
    barks = {
        [1] = { "Raene Wolfrunner", "Wolf riders! Fast. Slow them!" },
        [2] = { "Raene Wolfrunner", "Warsong grunts. Heavy armour: the talon's curse will help." },
        [3] = { "Raene Wolfrunner", "Wind riders above the canopy!" },
        [5] = { "Raene Wolfrunner", "Shredders. Steel monsters that eat trees." },
        [10] = { "Raene Wolfrunner", "The Warsong Overlord! His stomp stuns towers. Spread out!" },
    },
    boss = { "Warsong Overlord", "Your trees will burn, and so will you!" },
    victory = "The Warsong fall back to their camps. Delgren the Purifier sends word: the Twilight's Hammer has "
        .. "opened Blackfathom Deeps.",
}

L["sentinels-8"] = {
    briefing = { "Delgren the Purifier", "Blackfathom Deeps was a temple to Elune. Now it is drowned and defiled: "
        .. "naga priestesses, the Twilight's Hammer, and in the deepest water a hydra called Aku'mai, servant of the "
        .. "old gods. Everything you learned in the forests, you'll need below. For Elune!" },
    barks = {
        [1] = { "Delgren the Purifier", "Naga myrmidons, out of the dark water." },
        [2] = { "Delgren the Purifier", "Tide priestesses: warded healers. Find them, kill them." },
        [3] = { "Delgren the Purifier", "Snapjaws: thick shells. Bring the ancients." },
        [5] = { "Tyrande Whisperwind", "Satyrs in the deep. Keep the druids close." },
        [8] = { "Delgren the Purifier", "Twilight disciples and satyrs together. Find the healers." },
        [15] = { "Tyrande Whisperwind", "Aku'mai! It calls its snapjaws, and rages when wounded." },
    },
    boss = { "Aku'mai", "*a sound like the sea itself, screaming*" },
    victory = "Aku'mai sinks into the black water, and the temple is quiet. In the silence, you could swear you hear "
        .. "Elune's light humming.",
}

------------------------------------------------------------------------------------------------------------------------
-- The Forsaken: The Dark Lady's Will

C.forsaken = {
    intro = { "Sylvanas Windrunner", "We were dead. The Lich King made us slaves. Now our minds are our own again, "
        .. "and the living want to finish what the Scourge began. We are the Forsaken. We will not be forsaken "
        .. "again." },
    outro = { "Sylvanas Windrunner", "The Crusade bleeds, Southshore cowers, and Arugal is dead. Lordaeron is ours, "
        .. "and we answer to no king, living or dead. Victory for the Forsaken." },
}

L["forsaken-1"] = {
    briefing = { "Executor Arren", "You've only just awoken, so listen. The Scarlet Crusade hunts our kind in "
        .. "Tirisfal, and the mindless dead, the ones who never came back to themselves, wander the fields. A dark "
        .. "ranger and a necromancer will stand with you. Hold Deathknell." },
    barks = {
        [1] = { "Executor Arren", "Mindless zombies. Slow, but they keep coming." },
        [2] = { "Executor Arren", "Scarlet converts. Fanatics." },
        [3] = { "Executor Arren", "Duskbats! Only the ranger and the necromancer can reach them." },
        [6] = { "Executor Arren", "Hold the gates of Deathknell!" },
    },
    victory = "Deathknell stands. Executor Arren sends you on to Brill: \"The Crusade is massing outside the town. "
        .. "Go.\"",
}

L["forsaken-2"] = {
    briefing = { "Apothecary Johaan", "The Scarlet Crusade calls us abominations, then marches on Brill to prove it. "
        .. "Zealots, crusaders in plate, friars to heal them. The Royal Apothecary Society has a gift for them: a "
        .. "plague cauldron. Let it bubble beside their road, and watch them rot." },
    barks = {
        [1] = { "Apothecary Johaan", "Converts in front. The real fanatics follow." },
        [2] = { "Apothecary Johaan", "Zealots! Warded against shadow magic." },
        [3] = { "Apothecary Johaan", "Crusaders in heavy plate." },
        [4] = { "Apothecary Johaan", "Friars. They heal the others. My plague doesn't care." },
        [10] = { "Apothecary Johaan", "Captain Perrine. She'll call her crusaders to her side." },
    },
    boss = { "Captain Perrine", "Purge the undead! Leave nothing!" },
    victory = "The Crusade breaks against Brill. Johaan is pleased: \"An excellent field test.\" Then a message from "
        .. "the Agamand Mills: the dead there are not Forsaken.",
}

L["forsaken-3"] = {
    briefing = { "Coleman Farthing", "The Agamands were a proud family. When the plague took them, they rose as "
        .. "Scourge, not as Forsaken, and Devlin, the eldest, leads the risen dead of the mills. Bring a meat wagon. "
        .. "Some things need to be put down for good." },
    barks = {
        [1] = { "Coleman Farthing", "Zombies, out of the fields." },
        [2] = { "Coleman Farthing", "Skeletal warriors: armoured bone." },
        [3] = { "Coleman Farthing", "Ghouls. They heal, unless you finish them." },
        [6] = { "Coleman Farthing", "Devlin Agamand. He raises more dead as he comes." },
    },
    boss = { "Devlin Agamand", "The Agamands... will rise... again..." },
    victory = "Devlin Agamand rests at last. In Silverpine, High Executor Hadrec has trouble: worgen.",
}

L["forsaken-4"] = {
    briefing = { "High Executor Hadrec", "The Sepulcher is our foothold in Silverpine, and the forest is crawling: "
        .. "Rot Hide gnolls, Dalaran's mages, and worst of all Arugal's worgen, who slip through the trees unseen. The "
        .. "banshees will wail them into the open. Hold, and the Dark Lady herself will come." },
    barks = {
        [1] = { "High Executor Hadrec", "Rot Hide gnolls. Undead, like us, but mindless." },
        [2] = { "High Executor Hadrec", "Dalaran conjurors: warded against our magic." },
        [4] = { "High Executor Hadrec", "Worgen! You'll only see them while a banshee is near." },
        [10] = { "High Executor Hadrec", "The Son of Arugal! He goes wild when he's hurt." },
    },
    boss = { "Son of Arugal", "*a howl that shakes the pines*" },
    victory = "The great worgen falls. Hadrec bows low: a dark rider is coming up the road. The Banshee Queen has "
        .. "arrived.",
}

L["forsaken-5"] = {
    briefing = { "Sylvanas Windrunner", "Pyrewood Village. By day, frightened humans. By night, Arugal's curse turns "
        .. "them into beasts, and night is falling. I will fight with you; when they press close, my Wailing Arrow "
        .. "will silence them. Do not hesitate. They stopped being people when the moon rose." },
    barks = {
        [1] = { "Sylvanas Windrunner", "Gnolls first. Arugal uses everything." },
        [2] = { "Sylvanas Windrunner", "The villagers are turning. Watch the shadows." },
        [4] = { "Sylvanas Windrunner", "More of them. Keep a banshee on the road." },
        [6] = { "Sylvanas Windrunner", "The packleader howls for his pack. Silence him." },
    },
    boss = { "Bloodfang Packleader", "*howls for the pack*" },
    victory = "Dawn finds Pyrewood quiet. Sylvanas turns east: \"Southshore's soldiers are marching on Tarren Mill. "
        .. "Let them come.\"",
}

L["forsaken-6"] = {
    briefing = { "High Executor Darthalia", "Tarren Mill and Southshore have hated each other since the day we took "
        .. "this town. Now Southshore's marshal marches on us with guards, farmers with pitchforks, and gryphon riders "
        .. "in the sky. They think we are monsters. Let us not disappoint them." },
    barks = {
        [1] = { "High Executor Darthalia", "Farmers with pitchforks. A mob, nothing more." },
        [2] = { "High Executor Darthalia", "Southshore guards, in plate." },
        [3] = { "High Executor Darthalia", "Gryphon riders! Bring them down out of the sky." },
        [10] = { "High Executor Darthalia", "Marshal Redpath leads them. He calls his guards to him." },
    },
    boss = { "Marshal Redpath", "For Southshore! Burn the undead!" },
    victory = "Southshore retreats behind its walls. Varimathras whispers to the Dark Lady: Dalaran's last mages hold "
        .. "Ambermill, and they are studying our plague.",
}

L["forsaken-7"] = {
    briefing = { "Varimathras", "My queen, the magi of Dalaran have not forgiven the plague, and at Ambermill they "
        .. "gather to undo it. Their conjurors are warded against our magic, their protectors wear heavy plate, and "
        .. "Archmage Ataeric conjures more help with every breath. Leave them nothing to learn from." },
    barks = {
        [1] = { "Varimathras", "Conjurors, my queen. Their wards turn our spells." },
        [2] = { "Varimathras", "Protectors. Plate and stubbornness." },
        [3] = { "Varimathras", "Rot Hide gnolls, scavenging the battlefield." },
        [5] = { "Varimathras", "Arugal's worgen, drawn by the fighting." },
        [10] = { "Varimathras", "Ataeric! Strike before he conjures an army." },
    },
    boss = { "Archmage Ataeric", "Dalaran will cleanse this blight!" },
    victory = "Ambermill burns. In Ataeric's papers, one name over and over: Arugal, who brought the worgen here from "
        .. "another world. He waits in Shadowfang Keep.",
}

L["forsaken-8"] = {
    briefing = { "Sylvanas Windrunner", "Archmage Arugal summoned the worgen to fight the Scourge, and lost his mind "
        .. "to them. Now he sits in Shadowfang Keep like a wolf king while his curse spreads through Silverpine. This "
        .. "ends today. His magic carries him ahead in flashes of shadow: cover the whole road." },
    barks = {
        [1] = { "Sylvanas Windrunner", "Into the keep." },
        [2] = { "Sylvanas Windrunner", "Skeletons. Arugal's guards died at their posts long ago." },
        [3] = { "Sylvanas Windrunner", "Worgen in the halls. Keep the banshees wailing." },
        [8] = { "Sylvanas Windrunner", "The packleader again. Arugal keeps his favourites close." },
        [12] = { "Sylvanas Windrunner", "Almost there. Do not falter." },
        [15] = { "Sylvanas Windrunner", "Arugal! He blinks ahead. Cover the whole road!" },
    },
    boss = { "Archmage Arugal", "You, too, shall serve!" },
    victory = "Arugal falls from his throne, and the worgen's howling fades. Sylvanas allows herself something close "
        .. "to a smile.",
}

return Story
