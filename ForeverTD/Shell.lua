-- Shell.lua - the WoW-facing glue: the run's life (start, step, finish), SavedVariables, combat and /td.
-- Keep it thin: rules live in Engine.lua, progress in Meta.lua, drawing in Board.lua and Ui.lua.
local ADDON, ns = ...
local Engine, Meta, Levels, Board, Ui = ns.Engine, ns.Meta, ns.Levels, ns.Board, ns.Ui

local Game = { speed = 1, paused = false }
ns.Game = Game
-- Game.db: ForeverTDDB after Meta.Prepare (a scratch table when the file is from a newer version: never saved).
-- Game.state: the engine state of the level on the board. Game.result: the end screen's summary once it's over.

local window = Ui.window
local clock = { acc = 0 } -- fixed-step accumulator for Engine.Advance
local out = {}            -- the frame's events, reused
local closedByCombat = false
local AUTO_TICKS = 5 * Engine.HZ -- with auto waves on, the next wave starts this long after the board clears
local idle = 0                   -- ticks the board has been clear

local function Seed() return (GetServerTime() % 2147483646) + 1 end

local function Attach(state)
    Game.state, Game.result = state, nil
    clock.acc, idle = 0, 0
    Board.SetState(state)
    Ui.OnRun()
end

-- Starts a level, replacing any run in progress (which then earns nothing). A level not yet won opens with its
-- briefing (when the story is on); nothing moves until the first wave anyway.
function Game.Start(levelId, difficulty)
    local db = Game.db
    difficulty = difficulty or "normal"
    if not (db and Meta.DifficultyUnlocked(db.profile, levelId, difficulty)) then return false end
    local loadout = Meta.Loadout(db.profile, difficulty, levelId)
    local state = Engine.New(levelId, loadout, Seed())
    if not state then return false end
    db.run = { runId = Meta.NewRunId(db.profile), level = levelId, difficulty = difficulty, loadout = loadout }
    Game.lastLevel, Game.lastDifficulty = levelId, difficulty
    Game.paused = false
    Attach(state)
    if db.settings.story and not Meta.Cleared(db.profile, levelId) then
        Ui.ShowBriefing(Levels.byId[levelId], function() db.profile.seen[levelId] = true end)
    end
    return true
end

-- The result goes into the profile the moment the level ends, before anything is shown (and only once).
local function Finish()
    local s, db = Game.state, Game.db
    local run = db.run
    local summary = run and Meta.Commit(db.profile, { runId = run.runId, level = s.level, difficulty =
        run.difficulty, won = s.over == "won", lives = s.lives, maxLives = s.maxLives, kills = s.stats.kills })
    db.run = nil
    Game.result = summary or { stars = Meta.Stars(s.over == "won", s.lives, s.maxLives), previousStars = 0 }
    Game.unsaved = true
    Ui.ShowEnd(Game.result, s)
end

local function Dispatch(events)
    Board.OnEvents(events, GetTime())
    Ui.OnEvents(events)
    if Game.state.over and not Game.result then Finish() end
end

function Game.Act(action)
    if not Game.state then return nil end
    local events = Engine.Apply(Game.state, action)
    Dispatch(events)
    return events
end

-- Spends Warmarks (Meta.Buy): returns the cost, or nil and why not.
function Game.Buy(what, key)
    local cost, why = Meta.Buy(Game.db.profile, what, key)
    if cost then
        Game.unsaved = true
        Ui.Sound("LOOT_WINDOW_COIN_SOUND")
    end
    return cost, why
end

function Game.SetPaused(on)
    Game.paused = on and Game.state ~= nil and not Game.state.over
    Ui.ShowPaused(Game.paused)
    Ui.Refresh()
end

-- Between waves, with more to come?
local function Waiting(s) return not s.over and s.wave > 0 and s.wave < #s._level.waves and #s.active == 0 end

-- Seconds until auto waves start the next one, or nil.
function Game.AutoIn()
    local s = Game.state
    if not (s and Game.db and Game.db.settings.autoWaves and Waiting(s)) then return nil end
    return math.ceil((AUTO_TICKS - idle) / (Engine.HZ * Engine.PACE))
end

local function ApplySettings()
    window:SetScale(Game.db.settings.scale)
    Board.fx = Game.db.settings.effects and 2 or 1
end

function Game.SetOption(name, value)
    if name == "scale" then value = math.max(0.6, math.min(1.6, math.floor((tonumber(value) or 1) * 10 + 0.5) / 10)) end
    Game.db.settings[name] = value
    ApplySettings()
    Ui.Refresh()
    if Ui.menu:IsShown() then Ui.RefreshMenu() end
end

function Game.ToggleSpeed()
    Game.speed = Game.speed == 2 and 1 or 2
    Ui.Refresh()
end

-- SavedVariables reach disk only at /reload or logout; a client crash loses everything since.
function Game.Save() ReloadUI() end

-- OnUpdate runs only while the window is shown: closing it pauses the game, mid-wave included. It's guarded: the
-- first unexpected error pauses the game, prints one line and goes once to the client's error handler (BugGrabber
-- keeps it, with its stack); then the loop stands still until the window is reopened or the UI reloaded, instead of
-- failing every frame.
local frameElapsed, broken = 0, false
local function Frame()
    local elapsed = frameElapsed
    local s = Game.state
    if s and not Game.paused and not s.over then
        for i = #out, 1, -1 do out[i] = nil end
        local steps = Engine.Advance(s, clock, elapsed, Game.speed * Engine.PACE, out)
        if #out > 0 then Dispatch(out) end
        if steps > 0 and Game.db.settings.autoWaves and Waiting(s) then
            idle = idle + steps
            if idle >= AUTO_TICKS then
                idle = 0
                Game.Act({ kind = "wave" })
            end
        elseif steps > 0 then
            idle = 0
        end
    end
    local now = GetTime()
    if s then Board.Update(clock.acc / Engine.STEP, now) end
    Ui.Update(now)
end

local function Report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
    return err
end

window:SetScript("OnUpdate", function(_, elapsed)
    if broken then return end
    frameElapsed = elapsed
    if xpcall(Frame, Report) then return end
    broken = true
    Game.paused = Game.state ~= nil and not Game.state.over
    pcall(Ui.ShowPaused, Game.paused)
    print("|cffffd200ForeverTD|r hit an error and paused. Your progress is safe: type /reload, and please report it.")
end)

-- Reopening never springs the game back to life: it waits behind "click to resume".
window:HookScript("OnShow", function()
    broken = false -- and a guarded error gets another try
    if Game.state and not Game.state.over then
        Game.SetPaused(true)
    elseif not Game.state then
        Ui.ShowMenu(true)
    end
end)

local function Save()
    local db = Game.db
    if not db or Game.readOnly then return end
    db.settings.speed = Game.speed
    if db.run and Game.state and not Game.state.over then db.run.snapshot = Engine.Snapshot(Game.state) end
end

local function Load()
    ForeverTDDB = ForeverTDDB or {}
    local db = Meta.Prepare(ForeverTDDB)
    if not db then
        print("|cffffd200ForeverTD|r: this save comes from a newer version of the addon; nothing will be saved.")
        db, Game.readOnly = Meta.Prepare({}), true
    end
    Game.db = db
    Game.speed = db.settings.speed == 2 and 2 or 1
    ApplySettings()
    local run = db.run
    if run then
        local state, why = Engine.Restore(run.snapshot)
        if state then
            Game.lastLevel, Game.lastDifficulty = run.level, run.difficulty
            Game.paused = true
            Attach(state)
        else
            db.run = nil
            print("|cffffd200ForeverTD|r: the level in progress couldn't be resumed (" .. tostring(why) .. ").")
        end
    end
    Ui.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")          -- also fires on /reload: the last chance to write SavedVariables
events:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat
events:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        Load()
    elseif event == "PLAYER_LOGOUT" then
        Save()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if window:IsShown() then closedByCombat = true; window:Hide() end -- pause and get out of the way
    elseif event == "PLAYER_REGEN_ENABLED" then
        if closedByCombat then closedByCombat = false; window:Show() end
    end
end)

-- /td diag: this addon's CPU per frame from the client's profiler, and what's alive on the board.
local function Diag()
    local P, metrics = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    local function Metric(name)
        if not (P and type(P.GetAddOnMetric) == "function" and metrics and metrics[name]) then return nil end
        local ok, ms = pcall(P.GetAddOnMetric, ADDON, metrics[name])
        return ok and type(ms) == "number" and ms or nil
    end
    local recent, peak = Metric("RecentAverageTime"), Metric("PeakTime")
    local s = Game.state
    local tokens, shots, fx = Board.Counts()
    print(string.format("|cffffd200ForeverTD|r: %s ms per frame (recent), peak %s ms; creeps %d, shots %d, "
        .. "effects %d, towers %d; tick %d, speed %dx%s", recent and string.format("%.3f", recent) or "?",
        peak and string.format("%.2f", peak) or "?", tokens, shots, fx, s and #s.towers or 0, s and s.tick or 0,
        Game.speed, Game.paused and ", paused" or ""))
end

local HELP = {
    "/td - open or close the game (closing pauses it)",
    "/td levels - choose a level; /td armory - spend Warmarks on research",
    "/td new - restart the current level",
    "/td diag - CPU per frame and what's on the board",
    "/td sound, /td auto - turn sound or auto waves on and off",
    "/td story, /td effects - briefings and battle cries; full effects (off: just the essentials)",
    "/td scale 0.9 - window size (0.6 to 1.6)",
    "/td save - write everything to disk now (reloads the UI)",
    "/td sandbox - open every level and tower to try things out (again to close; progress is untouched)",
}
local DEV_HELP = { -- only while the dev tools are loaded (a players' copy leaves Dev\ out: tools/package.lua)
    "/td fx - a few seconds of the big effects on the board (start a level first)",
    "/td dev - dev tools: bench, icons, creatures, maps, probe",
}

-- The minimap's addon menu (the TOC's AddonCompartmentFunc, Retail's): a click opens or closes the game, as /td.
function ForeverTD_OnAddonCompartmentClick() SlashCmdList.FOREVERTD("") end
function ForeverTD_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(type(button) == "table" and button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverTD")
    GameTooltip:AddLine("Tower defense: click to play, or to close (closing pauses). /td help for more.", 1, 1, 1, true)
    GameTooltip:Show()
end
function ForeverTD_OnAddonCompartmentLeave() GameTooltip:Hide() end

SLASH_FOREVERTD1 = "/td"
SLASH_FOREVERTD2 = "/forevertd"
SlashCmdList.FOREVERTD = function(msg)
    msg = strtrim(string.lower(msg or ""))
    local word, rest = msg:match("^(%S*)%s*(.-)$")
    local OPTION = { sound = "sound", auto = "autoWaves", story = "story", effects = "effects" }
    if OPTION[word] and Game.db then
        Game.SetOption(OPTION[word], not Game.db.settings[OPTION[word]])
        print("|cffffd200ForeverTD|r " .. word .. ": " .. (Game.db.settings[OPTION[word]] and "on" or "off"))
    elseif word == "scale" and Game.db then
        Game.SetOption("scale", tonumber(rest) or 1)
        print("|cffffd200ForeverTD|r window size " .. Game.db.settings.scale)
    elseif word == "save" then
        Game.Save()
    elseif word == "fx" then
        if not Board.Showcase() then
            print("|cffffd200ForeverTD|r: start a level first (any level; /td sandbox opens them all), then /td fx.")
        elseif not window:IsShown() then
            window:Show()
        end
    elseif word == "sandbox" and Game.db then
        local p = Game.db.profile
        p.sandbox = not p.sandbox or nil
        print("|cffffd200ForeverTD|r sandbox: " .. (p.sandbox and "every campaign, level and tower is open for "
            .. "trying things out (type /td sandbox again to close them; your progress is untouched)" or "off"))
        Ui.RefreshMenu()
    elseif word == "help" then
        for _, line in ipairs(HELP) do print("|cffffd200ForeverTD|r " .. line) end
        for _, line in ipairs(ns.Dev and DEV_HELP or {}) do print("|cffffd200ForeverTD|r " .. line) end
    elseif word == "diag" then
        Diag()
    elseif ns.Dev and ns.Dev.Handles(word) then
        ns.Dev.Command(msg) -- dev tools are optional: the game works with Dev/ removed from the TOC
    elseif InCombatLockdown() then
        print("ForeverTD: not during combat.")
    elseif word == "new" or word == "levels" or word == "menu" or word == "armory" then
        window:Show()
        if word == "new" and Game.lastLevel and Game.Start(Game.lastLevel, Game.lastDifficulty) then return end
        Ui.ShowMenu(true, word == "armory" and "armory" or "campaign")
    else
        window:SetShown(not window:IsShown())
    end
end
