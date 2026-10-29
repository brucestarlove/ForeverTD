-- Shell and UI smoke tests: load the game's TOC files (not Dev/) under stubs and drive them like a player would.
-- This catches load-time errors, broken wiring and save/restore mistakes - not how anything looks in the client.
local stub = require("wowstub")

local function GameFiles(T)
    local files = {}
    for line in io.lines(T.base .. "/ForeverTD/ForeverTD.toc") do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") and not line:find("^Dev") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

local function bootWith(T, setup, saved, event)
    stub.frames, stub.timers, stub.printed, stub.now = {}, {}, {}, 0
    local env = stub.env()
    env.ForeverTDDB = saved
    if setup then setup(env) end
    local ns = {}
    for _, file in ipairs(GameFiles(T)) do stub.load(T.base .. "/ForeverTD/" .. file, "ForeverTD", ns, env) end
    stub.fire("ADDON_LOADED", event or "ForeverTD")
    return env, ns
end
local function boot(T, saved, event) return bootWith(T, nil, saved, event) end

local function frames(env, n, dt)
    for _ = 1, n do
        stub.now = stub.now + (dt or 1 / 60)
        env.ForeverTDFrame:Run("OnUpdate", dt or 1 / 60)
    end
end

-- Left-clicks board cell (c, r) through the cursor, as the client would deliver it.
local function click(ns, c, r, button)
    local board = ns.Board.frame
    board.left, board.top, board.scale = 100, 600, 1
    stub.cursorX, stub.cursorY = 100 + (c - 0.5) * 36, 600 - (r - 0.5) * 36
    board:Run("OnMouseUp", button or "LeftButton")
end

local function relog(T, env)
    stub.fire("PLAYER_LOGOUT")
    return boot(T, env.ForeverTDDB)
end

-- A save that has won the first n-1 levels of a campaign (so level n and its towers are open).
local function Reached(campId, n, extra)
    local levels = {}
    for i = 1, n - 1 do levels[campId .. "-" .. i] = { stars = 3, heroicStars = 0, wins = 1, plays = 1 } end
    local db = { schema = 2, profile = { levels = levels }, settings = {} }
    for k, v in pairs(extra or {}) do db.settings[k] = v end
    return db
end

local function Count(kind)
    local n = 0
    for _, f in ipairs(stub.frames) do if f.kind == kind then n = n + 1 end end
    return n
end

local function Models()
    local list = {}
    for _, f in ipairs(stub.frames) do if f.kind == "PlayerModel" then list[#list + 1] = f end end
    return list
end

-- Records every ClearModel and Hide on a model frame, so a test can check the crash rules.
local function Watch(model, log)
    model.ClearModel = function(self) log[#log + 1] = self:IsShown() and "shown" or "HIDDEN" end
    model.Hide = function() log[#log + 1] = "hide" end
end

local tests = {}

tests["loads, prepares its SavedVariables, and has a slash command and ESC"] = function(T)
    local env, ns = boot(T, nil)
    T.eq(env.ForeverTDDB.schema, ns.Meta.SCHEMA, "schema")
    T.eq(env.ForeverTDDB.profile.warmarks, 0, "profile")
    T.eq(env.SLASH_FOREVERTD1, "/td", "slash")
    T.eq(env.SLASH_FOREVERTD2, "/forevertd", "long slash")
    T.eq(env.UISpecialFrames[1], "ForeverTDFrame", "ESC closes the window")
    local _, ns2 = boot(T, nil, "SomeOtherAddon")
    T.eq(ns2.Game.db, nil, "someone else's ADDON_LOADED is ignored")
end

tests["the starter toy's save is dropped, a 0.3 save is set aside, and the dev data kept"] = function(T)
    local env = boot(T, { save = { schema = 1, tick = 527, towers = { 1, 2 } }, dev = { probe = { toc = 16001 } } })
    T.eq(env.ForeverTDDB.save, nil, "toy save gone")
    T.eq(env.ForeverTDDB.dev.probe.toc, 16001, "dev data kept")
    local old = boot(T, { schema = 1, profile = { warmarks = 115 }, run = { runId = "run13", level = "durotar-1" },
        settings = { scale = 1.4 } })
    T.eq(old.ForeverTDDB.legacy.profile.warmarks, 115, "0.3 progress kept aside")
    T.eq(old.ForeverTDDB.profile.warmarks, 0, "fresh start")
    T.eq(old.ForeverTDDB.settings.scale, 1.4, "settings kept")
end

tests["play: a briefing, a build, a wave; closing pauses; a reload resumes at the same tick"] = function(T)
    local env, ns = boot(T, nil)
    local G, window = ns.Game, env.ForeverTDFrame
    env.SlashCmdList.FOREVERTD("")
    T.ok(window:IsShown(), "open")
    T.ok(ns.Ui.menu:IsShown(), "no run yet: the menu shows")
    T.ok(G.Start("horde-1", "normal"), "started")
    T.ok(not ns.Ui.menu:IsShown(), "menu closed")
    T.ok(ns.Ui.BriefingShown(), "a first visit opens with its briefing")
    T.ok(not G.Start("horde-2", "normal"), "the second level is locked")
    ns.Ui.briefing.go:Run("OnClick", "LeftButton")
    T.ok(not ns.Ui.BriefingShown(), "To battle!")
    T.ok(G.db.profile.seen["horde-1"], "and it's marked as read")
    T.eq(ns.Ui.palette[1].kind, "headhunter", "the Horde's first tower")
    T.eq(ns.Ui.palette[2].kind, "witchdoctor", "and its second")
    T.ok(not ns.Ui.palette[3]:IsShown(), "only two at the start of the campaign")
    T.ok(not ns.Ui.heroButton:IsShown(), "no hero yet")
    ns.Ui.palette[1]:Run("OnClick")
    T.eq(ns.Board.placing, "headhunter", "placing")
    click(ns, 2, 1)
    T.eq(#G.state.towers, 1, "built by clicking the board")
    T.eq(G.state.towers[1].c .. "," .. G.state.towers[1].r, "2,1", "on the clicked cell")
    T.eq(ns.Board.placing, nil, "placing ends after a build")
    click(ns, 2, 1)
    T.eq(ns.Board.selected, G.state.towers[1].id, "clicking a tower selects it")
    G.Act({ kind = "wave" })
    frames(env, 120)
    local tick, want = G.state.tick, 2 * ns.Engine.HZ * ns.Engine.PACE
    T.ok(math.abs(tick - want) <= 1, "about " .. want .. " ticks in 2 seconds at normal speed, got " .. tick)
    T.ok(#G.state.creeps > 0, "creeps on the board")
    env.SlashCmdList.FOREVERTD("") -- close
    T.ok(not window:IsShown(), "closed")
    local env2, ns2 = relog(T, env)
    local save = env.ForeverTDDB.run
    T.eq(save.snapshot.tick, tick, "snapshot written at logout")
    T.eq(ns2.Game.state.tick, tick, "restored at the same tick")
    T.ok(ns2.Game.paused, "restored paused")
    env2.SlashCmdList.FOREVERTD("")
    T.ok(ns2.Ui.pausedOverlay:IsShown(), "click to resume")
    T.ok(not ns2.Ui.BriefingShown(), "no briefing for a resumed run")
    frames(env2, 30)
    T.eq(ns2.Game.state.tick, tick, "nothing moves while paused")
    ns2.Ui.pausedOverlay:Run("OnClick")
    frames(env2, 30)
    T.ok(ns2.Game.state.tick > tick, "resumed")
end

tests["combat closes the window, and it comes back paused"] = function(T)
    local env, ns = boot(T, nil)
    env.SlashCmdList.FOREVERTD("")
    ns.Game.Start("horde-1")
    stub.fire("PLAYER_REGEN_DISABLED")
    T.ok(not env.ForeverTDFrame:IsShown(), "hidden in combat")
    stub.fire("PLAYER_REGEN_ENABLED")
    T.ok(env.ForeverTDFrame:IsShown(), "back after combat")
    T.ok(ns.Game.paused, "paused")
end

tests["the end of a level is written into the profile once, and the run slot is freed"] = function(T)
    local env, ns = boot(T, nil)
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    ns.Ui.CloseBriefing()
    G.Act({ kind = "wave" })
    G.state.lives = 1
    frames(env, 60 * 40, 1 / 30) -- no towers: the boars get through
    T.eq(G.state.over, "lost", "lost")
    T.ok(ns.Ui.endOverlay:IsShown(), "end screen")
    T.eq(env.ForeverTDDB.run, nil, "run slot freed")
    local quarter = math.floor(ns.Meta.REWARD.short * ns.Meta.LOSS_PCT / 100)
    T.eq(env.ForeverTDDB.profile.warmarks, quarter, "a loss pays a quarter")
    T.eq(env.ForeverTDDB.profile.levels["horde-1"].plays, 1, "one play")
    frames(env, 60)
    T.eq(env.ForeverTDDB.profile.levels["horde-1"].plays, 1, "never counted twice")
    local env2, ns2 = relog(T, env)
    T.eq(env2.ForeverTDDB.profile.warmarks, quarter, "kept across a reload")
    T.eq(ns2.Game.state, nil, "no run to resume")
end

tests["a win: the victory words, what joins you, and the next level"] = function(T)
    local env, ns = boot(T, nil)
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    ns.Ui.CloseBriefing()
    G.state.wave = #G.state._level.waves -- every wave out and none left alive: the next tick wins
    frames(env, 4)
    T.ok(ns.Ui.endOverlay:IsShown(), "end screen")
    T.ok(ns.Ui.endOverlay.story:GetText():find("Razor Hill", 1, true), "the story goes on")
    T.ok(ns.Ui.endOverlay.lines:GetText():find("Tauren Earthshaker", 1, true), "the new tower is announced")
    T.ok(ns.Meta.LevelUnlocked(G.db.profile, "horde-2"), "the next level opens")
    G.Start("horde-2")
    ns.Ui.CloseBriefing()
    T.eq(ns.Ui.palette[3].kind, "earthshaker", "and the tower is in the palette")
end

tests["a save that can't be resumed is dropped with a message, not an error"] = function(T)
    local env, ns = boot(T, { schema = 2, run = { runId = "run1", level = "atlantis", snapshot = { schema = 3,
        level = "atlantis" } } })
    T.eq(env.ForeverTDDB.run, nil, "dropped")
    T.eq(ns.Game.state, nil, "no state")
    T.ok(stub.printed[1] and stub.printed[1]:find("couldn't be resumed", 1, true), "told the player")
end

tests["3D portraits: built only when needed, never hidden, cleared only while shown"] = function(T)
    local env, ns = boot(T, Reached("horde", 2, { story = false }))
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-2")
    frames(env, 10)
    T.eq(#Models(), 0, "no model without a boss or a briefing")
    G.state.wave = #G.state._level.waves - 1
    G.Act({ kind = "wave" }) -- the boss wave
    G.state.lives = 999
    frames(env, 200, 1 / 30)
    local model = Models()[1]
    T.ok(model, "portrait built for the boss")
    local log = {}
    Watch(model, log)
    env.SlashCmdList.FOREVERTD("") -- close the window with the boss alive
    T.eq(table.concat(log, ","), "shown", "cleared once, while its own frame is shown, and not hidden")
    T.ok(model:IsShown(), "still shown (alpha 0)")
    -- the briefing's speaker
    local env2, ns2 = boot(T, nil)
    env2.SlashCmdList.FOREVERTD("")
    ns2.Game.Start("horde-1")
    local speaker = Models()[1]
    T.ok(speaker, "the briefing shows its speaker in 3D")
    T.eq(speaker.npc, ns2.Story.speakers.Gornek.npc, "Gornek")
    local log2 = {}
    Watch(speaker, log2)
    ns2.Ui.briefing.go:Run("OnClick", "LeftButton")
    T.eq(table.concat(log2, ","), "shown", "released while shown when the briefing closes")
end

tests["battle cries at their waves, and only with the story on"] = function(T)
    local env, ns = boot(T, nil)
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    ns.Ui.CloseBriefing()
    G.Act({ kind = "wave" })
    T.ok(ns.Ui.bark:IsShown(), "a battle cry with wave 1")
    T.ok(ns.Ui.bark.text:GetText():find("Gornek", 1, true), "who says it")
    stub.now = stub.now + 7
    frames(env, 2)
    T.ok(not ns.Ui.bark:IsShown(), "it fades")
    env.SlashCmdList.FOREVERTD("story")
    T.eq(G.db.settings.story, false, "/td story turns it off")
    G.Act({ kind = "wave" })
    T.ok(not ns.Ui.bark:IsShown(), "silence")
end

tests["a boss speaks its own line as it arrives, and only its own"] = function(T)
    local env, ns = boot(T, Reached("horde", 2))
    env.SlashCmdList.FOREVERTD("")
    ns.Game.Start("horde-2")
    ns.Ui.CloseBriefing()
    ns.Ui.bark:Hide()
    ns.Ui.OnEvents({ { kind = "spawn", id = 900, creep = "hogger" } })
    T.ok(not ns.Ui.bark:IsShown(), "another boss doesn't speak Razor Hill's boss line")
    ns.Ui.OnEvents({ { kind = "spawn", id = 901, creep = "warlord" } })
    T.ok(ns.Ui.bark:IsShown() and ns.Ui.bark.text:GetText():find("Razormane Warlord", 1, true), "the Warlord does")
end

tests["the buttons, auto waves, sound and window size"] = function(T)
    local played = {}
    local env, ns = bootWith(T, function(env)
        env.SOUNDKIT = { READY_CHECK = 8960, LOOT_WINDOW_COIN_SOUND = 120 }
        env.PlaySound = function(id) played[#played + 1] = id end
    end, { schema = 2, settings = { story = false } })
    local G, window = ns.Game, env.ForeverTDFrame
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    ns.Ui.palette[1]:Run("OnClick", "LeftButton")
    T.eq(ns.Board.placing, "headhunter", "the palette picks the first tower")
    ns.Ui.waveButton:Run("OnClick", "LeftButton")
    T.eq(G.state.wave, 1, "the wave button starts a wave")
    T.eq(played[#played], 8960, "with a sound")
    env.SlashCmdList.FOREVERTD("sound")
    T.eq(G.db.settings.sound, false, "/td sound turns it off")
    local heard = #played
    G.Act({ kind = "place", tower = "headhunter", c = 2, r = 1 })
    T.eq(#G.state.towers, 1, "built")
    T.eq(#played, heard, "silently")
    ns.Ui.speedButton:Run("OnClick", "LeftButton")
    T.eq(G.speed, 2, "the speed button: 2x")
    env.SlashCmdList.FOREVERTD("auto")
    T.eq(G.db.settings.autoWaves, true, "/td auto")
    G.state.lives = 999
    local cleared
    for _ = 1, 60 * 30 do
        stub.now = stub.now + 1 / 30
        window:Run("OnUpdate", 1 / 30)
        if not cleared and #G.state.active == 0 then cleared = G.state.tick end
        if G.state.wave == 2 then break end
    end
    T.ok(cleared, "wave 1 ran out")
    T.eq(G.state.wave, 2, "auto waves started wave 2")
    -- (at 2x a frame holds two ticks, so the count can start one tick early)
    T.ok(G.state.tick - cleared >= 5 * 30 - 2, "after the 5-second countdown, got " .. (G.state.tick - cleared))
    G.SetOption("scale", 1.23)
    T.eq(G.db.settings.scale, 1.2, "scale rounds to a tenth")
    G.SetOption("scale", 9)
    T.eq(G.db.settings.scale, 1.6, "and is capped")
    env.SlashCmdList.FOREVERTD("effects")
    T.eq(G.db.settings.effects, false, "/td effects")
    T.eq(ns.Board.fx, 1, "just the essentials")
    local env2 = relog(T, env)
    T.eq(env2.ForeverTDDB.settings.autoWaves, true, "options are saved")
end

tests["an error in the frame loop pauses the game, is reported once, and waits for the window to reopen"] = function(T)
    local reported = {}
    local env, ns = bootWith(T, function(e)
        e.geterrorhandler = function() return function(err) reported[#reported + 1] = tostring(err) end end
    end, { schema = 2, settings = { story = false } })
    local G, window, Board = ns.Game, env.ForeverTDFrame, ns.Board
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    G.Act({ kind = "wave" })
    frames(env, 5)
    local update = Board.Update
    Board.Update = function() error("boom") end
    frames(env, 3)
    T.eq(#reported, 1, "the error goes to the client's handler once")
    T.ok(reported[1]:find("boom"), "the error itself: " .. reported[1])
    T.eq(G.paused, true, "the game paused")
    local said = 0
    for _, line in ipairs(stub.printed) do if line:find("hit an error and paused", 1, true) then said = said + 1 end end
    T.eq(said, 1, "one line in the chat")
    local tick = G.state.tick
    G.paused = false
    frames(env, 10)
    T.eq(G.state.tick, tick, "the loop stands still")
    T.eq(#reported, 1, "and says nothing more")
    Board.Update = update
    window:Hide()
    window:Show()
    G.SetPaused(false)
    frames(env, 10)
    T.ok(G.state.tick > tick, "reopened, it plays on")
end

tests["no keys: every key stays the player's, the game is played with the mouse"] = function(T)
    -- Bruce, 2026-10-23: keybinds "will likely interfere with people's gameplay if they are multitasking"
    local env, ns = boot(T, Reached("horde", 5, { story = false, keys = true }))
    local G = ns.Game
    T.eq(G.db.settings.keys, nil, "an old save's keys setting is gone")
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-5")
    ns.Ui.heroButton:Run("OnClick", "LeftButton")
    click(ns, 2, 1)
    G.SetPaused(true)
    ns.Ui.ShowMenu(true)
    ns.Menu.Page("options")
    for _, f in ipairs(stub.frames) do
        local what = tostring(f.name or f.kind)
        T.ok(not (f.scripts.OnKeyDown or f.scripts.OnKeyUp), what .. ": no key script")
        T.ok(not f.keyboard, what .. ": never takes the keyboard")
    end
    for _, row in ipairs(ns.Menu.optionRows) do T.ok(row.title:GetText() ~= "Keys", "no Keys option") end
    env.SlashCmdList.FOREVERTD("help")
    for _, line in ipairs(stub.printed) do T.ok(not line:find("keys", 1, true), "help without keys: " .. line) end
end

tests["the hero: placed free from its button, then its ability from the same button"] = function(T)
    local env, ns = boot(T, Reached("horde", 5, { story = false }))
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-5")
    T.eq(#G.state.loadout.towers, 5, "all five towers")
    T.ok(ns.Ui.heroButton:IsShown(), "the hero's button")
    T.eq(ns.Ui.heroButton.state:GetText(), "Place (free)", "it offers the hero")
    ns.Ui.heroButton:Run("OnClick", "LeftButton")
    T.eq(ns.Board.placing, "thrall", "placing Thrall")
    local gold = G.state.gold
    click(ns, 2, 1)
    T.ok(G.state.heroId, "on the field")
    T.eq(G.state.gold, gold, "for free")
    click(ns, 2, 1)
    ns.Ui.Refresh()
    T.eq(ns.Board.selected, G.state.heroId, "selected")
    local sell
    for _, f in ipairs(stub.frames) do if f.text and tostring(f.text):find("^Sell") then sell = f end end
    T.ok(not (sell and sell:IsShown()), "a hero can't be sold")
    G.state.abilityCd = 0
    ns.Ui.Refresh()
    T.eq(ns.Ui.heroButton.state:GetText(), "|cff40ff40Bloodlust: ready|r", "the ability is ready")
    ns.Ui.heroButton:Run("OnClick", "LeftButton")
    T.eq(ns.Board.placing, nil, "the hero isn't placed again")
    T.ok(G.state.lustEnd > G.state.tick, "the button: Bloodlust")
    T.ok(G.state.abilityCd > 0, "and the cooldown runs")
    ns.Ui.Refresh()
    T.eq(ns.Ui.heroButton.state:GetText(), "Bloodlust: 3:00", "counted in real minutes at normal speed")
    local lines = {}
    env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
    ns.Ui.heroButton:Run("OnEnter")
    local tip = table.concat(lines, "\n")
    T.ok(tip:find("Every 3 minutes.", 1, true), "the tooltip says so: " .. tip)
    T.ok(tip:find("every 0.50 s", 1, true), "and Thrall's own bolts are timed in real seconds: " .. tip)
end

-- A client map API with Durotar-sized art (1002x668 in 12 tiles of 256), as Bruce's client reported it.
local function FakeMaps(env)
    env.C_Map = {
        GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256,
            tileHeight = 256 } } end,
        GetMapArtLayerTextures = function()
            local files = {}
            for i = 1, 12 do files[i] = 100000 + i end
            return files
        end,
    }
end

tests["menu: four campaigns, chapters, the level's map and briefing, locks, and playing"] = function(T)
    local env, ns = bootWith(T, FakeMaps)
    local Menu, G = ns.Menu, ns.Game
    env.SlashCmdList.FOREVERTD("")
    T.ok(ns.Ui.menu:IsShown() and Menu.pages.campaign:IsShown(), "opens on the campaigns")
    T.eq(#Menu.banners, 4, "four campaigns")
    T.eq(Menu.chapters[1].level.id, "horde-1", "the Horde's chapters")
    local d = Menu.detail
    local shown = 0
    for _, t in ipairs(d.paint.tiles) do if t:IsShown() then shown = shown + 1 end end
    T.eq(shown, 12, "the level's map shows its 12 tiles")
    T.ok(d.paint.shown > 20, "and the road")
    T.ok(d.story:GetText():find("Gornek", 1, true), "and the briefing")
    T.ok(d.news:GetText():find("Headhunter", 1, true), "and who joins there")
    T.ok(d.normal:IsEnabled(), "Valley of Trials is open")
    T.ok(not d.heroic:IsEnabled(), "its Heroic isn't yet")
    Menu.chapters[2]:Run("OnClick", "LeftButton")
    T.ok(not d.normal:IsEnabled(), "Razor Hill waits for a win")
    T.ok(d.story:GetText():find("Valley of Trials", 1, true), "and says so")
    Menu.banners[3]:Run("OnClick", "LeftButton")
    T.eq(Menu.chapters[1].level.id, "sentinels-1", "the Sentinels' chapters")
    T.ok(not d.normal:IsEnabled(), "locked until 30 stars")
    Menu.banners[2]:Run("OnClick", "LeftButton")
    T.ok(d.normal:IsEnabled(), "the Alliance is open from the start")
    d.normal:Run("OnClick", "LeftButton")
    T.eq(G.state and G.state.level, "alliance-1", "started from the menu")
    T.ok(not ns.Ui.menu:IsShown(), "the menu closes")
    ns.Ui.ShowMenu(true)
    T.ok(G.paused, "opening the menu pauses the level")
    d.normal:Run("OnClick", "LeftButton")
    T.eq(G.state.tick, 0, "same run: starting another asks first")
    T.ok(ns.Ui.menu:IsShown(), "still in the menu, asking")
end

tests["armory: a tab per campaign, research with Warmarks, a specialization in a level"] = function(T)
    local env, ns = bootWith(T, nil, Reached("horde", 2, { story = false }))
    local Menu, G = ns.Menu, ns.Game
    G.db.profile.warmarks = 1000
    env.SlashCmdList.FOREVERTD("armory")
    T.ok(Menu.pages.armory:IsShown(), "/td armory opens the Armory")
    Menu.campTabs[1]:Run("OnClick", "LeftButton")
    local first = Menu.columns[1]
    T.eq(first.kind, "headhunter", "the Horde's towers")
    local cost = 0
    for tier = 1, 3 do
        first.buy:Run("OnClick", "LeftButton")
        cost = cost + ns.Meta.ARMORY[tier].cost
    end
    T.eq(G.db.profile.armory.headhunter, 3, "three tiers researched")
    T.eq(G.db.profile.warmarks, 1000 - cost, "paid")
    T.ok(G.unsaved, "unsaved progress marked")
    Menu.columns[5].buy:Run("OnClick", "LeftButton")
    T.eq(G.db.profile.armory.shaman, nil, "the shaman hasn't joined yet")
    Menu.campTabs[2]:Run("OnClick", "LeftButton")
    T.eq(Menu.columns[1].kind, "rifleman", "the Alliance tab")
    G.Start("horde-2")
    local id = G.Act({ kind = "place", tower = "headhunter", c = 2, r = 1 })[1].id
    G.state.gold = 1000
    G.Act({ kind = "upgrade", id = id })
    G.Act({ kind = "upgrade", id = id })
    ns.Board.selected = id
    ns.Ui.Refresh()
    local spec1, spec2 = ns.Ui.specButtons[1], ns.Ui.specButtons[2]
    T.ok(spec1:IsShown() and spec1:IsEnabled(), "Berserker on offer")
    T.ok(spec2:IsShown() and not spec2:IsEnabled(), "Envenomed Spears needs tier 5")
    spec1:Run("OnClick", "LeftButton")
    T.eq(G.state.towers[1].rank, 4, "Berserker taken")
end

tests["effects: lightning bolts and sparks for hits, and every pool stays capped"] = function(T)
    local env, ns = boot(T, Reached("horde", 5, { story = false }))
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-5")
    local lines = Count("Line")
    local events = {}
    for i = 1, 400 do
        events[#events + 1] = { kind = "hit", tower = "shaman", rank = 1, x = 2000 + i, y = 3000, sx = 1500, sy = 1500 }
        events[#events + 1] = { kind = "zap", x1 = 2000, y1 = 3000, x = 4000, y = 3500, damage = "magic" }
        events[#events + 1] = { kind = "blast", x = 5000, y = 5000, r = 1700, tower = "catapult", rank = 5 }
        events[#events + 1] = { kind = "pulse", id = 1, tower = "earthshaker", rank = 1, x = 3000, y = 3000, r = 1600 }
        events[#events + 1] = { kind = "killed", id = i, x = 3000, y = 3000, gold = 3, boss = i % 50 == 0 }
    end
    ns.Board.OnEvents(events, stub.now)
    T.ok(Count("Line") > lines, "lightning is drawn with lines")
    local created = Count("Line") + Count("Texture") + Count("FontString")
    ns.Board.OnEvents(events, stub.now + 0.1)
    frames(env, 30)
    T.eq(Count("Line") + Count("Texture") + Count("FontString"), created, "the second storm reuses the pools")
    local _, _, fx = ns.Board.Counts()
    T.ok(fx > 0, "effects are running")
    frames(env, 120)
    _, _, fx = ns.Board.Counts()
    T.eq(fx, 0, "and they all finish")
end

tests["/td fx shows the effects on the board, and asks for a level first"] = function(T)
    local env, ns = boot(T, nil)
    env.SlashCmdList.FOREVERTD("fx")
    T.ok(stub.printed[#stub.printed]:find("start a level first", 1, true), "no level: it says so")
    env.SlashCmdList.FOREVERTD("")
    ns.Game.Start("horde-1")
    local lines = Count("Line")
    env.SlashCmdList.FOREVERTD("fx")
    stub.now = 5
    stub.runTimers()
    T.ok(Count("Line") > lines, "lightning drawn")
    local _, _, fx = ns.Board.Counts()
    T.ok(fx > 0, "effects running")
    T.eq(ns.Game.state.stats.kills, 0, "the game heard nothing of it")
end

tests["review fixes: waves wait for the briefing, menu state"] = function(T)
    local env, ns = bootWith(T, FakeMaps)
    local G, Menu = ns.Game, ns.Menu
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-1")
    T.ok(not ns.Ui.waveButton:IsEnabled(), "no waves under the briefing")
    ns.Ui.CloseBriefing()
    T.ok(ns.Ui.waveButton:IsEnabled(), "and then there are")
    -- "Abandon it" never starts a level other than the one asked for
    ns.Ui.ShowMenu(true)
    Menu.banners[2]:Run("OnClick", "LeftButton")
    Menu.detail.normal:Run("OnClick", "LeftButton") -- alliance-1, while horde-1 runs: it asks first
    Menu.chapters[2]:Run("OnClick", "LeftButton")    -- then looks at another level
    Menu.abandonButton:Run("OnClick", "LeftButton")
    T.eq(G.state.level, "horde-1", "the old question was dropped: nothing started")
    T.eq(ns.Levels.Boss(ns.Levels.byId["alliance-8"]), "vancleef", "the finale's boss, not Sneed's Shredder")
    -- the Armory opens on the campaign being played
    G.Start("alliance-1")
    ns.Ui.ShowMenu(true, "armory")
    T.eq(Menu.columns[1].kind, "rifleman", "the Alliance's towers")
end

tests["a portrait that can't be released while off screen fades, then clears once it's back"] = function(T)
    local env, ns = boot(T, Reached("horde", 2, { story = false }))
    local G = ns.Game
    env.SlashCmdList.FOREVERTD("")
    G.Start("horde-2")
    G.state.wave = #G.state._level.waves - 1
    G.Act({ kind = "wave" })
    G.state.lives = 999
    frames(env, 200, 1 / 30)
    local model = Models()[1]
    T.ok(model and model.npc, "the boss portrait")
    local log, visible = {}, false
    Watch(model, log)
    model.IsVisible = function() return visible end -- the interface is hidden (Alt+Z)
    ns.Ui.models.boss.Release()
    T.eq(#log, 0, "nothing cleared while off screen")
    T.ok(model.releaseLater, "the release waits")
    visible = true
    model:Run("OnShow")
    T.eq(table.concat(log, ","), "shown", "cleared once it's on screen again")
end

tests["help, diag, and dev words without the dev files"] = function(T)
    local env = boot(T, nil)
    env.SlashCmdList.FOREVERTD("help")
    T.ok(#stub.printed >= 5, "help lines")
    env.SlashCmdList.FOREVERTD("diag")
    T.ok(stub.printed[#stub.printed]:find("creeps 0", 1, true), "diag line")
    env.SlashCmdList.FOREVERTD("bench") -- no Dev/ loaded: falls through to the window toggle
    T.ok(env.ForeverTDFrame:IsShown(), "game window toggled instead of an error")
end

return tests
