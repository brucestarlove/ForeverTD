-- Dev tools under stubs: load every file the TOC lists, in TOC order, then drive the bench, browsers and probe.
-- This checks wiring, pooling, saving and the "build nothing until opened" promise. It can't check how anything
-- looks or performs in the client; that is the in-game checklist's job.
local stub = require("wowstub")

local function TocFiles(T)
    local files = {}
    for line in io.lines(T.base .. "/ForeverTD/ForeverTD.toc") do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

local function boot(T, setup)
    stub.frames, stub.timers, stub.printed, stub.now = {}, {}, {}, 0
    local env = stub.env()
    if setup then setup(env) end
    local ns = {}
    for _, file in ipairs(TocFiles(T)) do stub.load(T.base .. "/ForeverTD/" .. file, "ForeverTD", ns, env) end
    stub.fire("ADDON_LOADED", "ForeverTD")
    return env, ns
end

local function Count(kind)
    local n = 0
    for _, f in ipairs(stub.frames) do if f.kind == kind then n = n + 1 end end
    return n
end

local function FindFrame(pred)
    for _, f in ipairs(stub.frames) do if pred(f) then return f end end
end

local function FindText(pattern)
    for _, f in ipairs(stub.frames) do
        if f.kind == "FontString" and type(f.text) == "string" and f.text:find(pattern, 1, true) then return f end
    end
end

local function Frames(env, n)
    for _ = 1, n do env.ForeverTDDevFrame:Run("OnUpdate", 1 / 30) end
end

local tests = {}

tests["the TOC's files all load, and the dev tools build nothing until opened"] = function(T)
    local env, ns = boot(T)
    T.ok(#TocFiles(T) >= 9, "files listed")
    T.eq(#ns.Dev.order, 5, "five tabs")
    T.eq(Count("ModelScene") + Count("PlayerModel"), 0, "no models before a tab is opened")
    T.ok(not env.ForeverTDDevFrame:IsShown(), "dev window starts closed")
    env.SlashCmdList.FOREVERTD("dev")
    T.ok(env.ForeverTDDevFrame:IsShown(), "/td dev opens it")
    env.SlashCmdList.FOREVERTD("dev")
    T.ok(not env.ForeverTDDevFrame:IsShown(), "and closes it")
end

tests["the bench runs every scenario, saves the results and reuses its pools"] = function(T)
    local env, ns = boot(T)
    local scenarios = #ns.DevCore.SCENARIOS
    env.SlashCmdList.FOREVERTD("bench")
    local bench = ns.Dev.tabs.Bench
    T.ok(bench.Running(), "running")
    for _ = 1, 4000 do
        Frames(env, 1)
        if not bench.Running() then break end
    end
    local runs = env.ForeverTDDB.dev.benchRuns
    T.eq(#runs, 1, "one run saved")
    T.eq(#runs[1].results, scenarios, "a result per scenario")
    T.eq(runs[1].zone, "Elwynn Forest", "where it ran")
    T.eq(runs[1].results[#runs[1].results].loaded, 0, "models counted (none load under stubs)")
    local scenes = Count("ModelScene")
    T.eq(scenes, 51, "50 per-creep scenes plus one shared scene")
    env.SlashCmdList.FOREVERTD("bench")
    for _ = 1, 4000 do
        Frames(env, 1)
        if not bench.Running() then break end
    end
    T.eq(#runs, 2, "second run saved")
    T.eq(Count("ModelScene"), scenes, "second run reused every pooled scene")
    T.ok(FindText("Press Save (reload)"), "results shown, with the reminder to save")
end

tests["the bench fits each per-creep model to its frame, and leaves the shared scene's alone"] = function(T)
    local fitted = { per = {}, shared = {} }
    local env, ns = boot(T, function(e)
        local create = e.CreateFrame
        e.CreateFrame = function(kind, ...)
            local f = create(kind, ...)
            if kind == "ModelScene" then
                f.SetAllPoints = function(self) self.isShared = true end -- only the shared scene fills the board
                f.CreateActor = function(scene)
                    local a = stub.Frame.new("Actor")
                    a.IsLoaded = function() return true end
                    a.GetMaxBoundingBox = function() return -1.5, -0.4, 0, 1.5, 0.4, 1.2 end -- long, like a wolf
                    a.SetScale = function(self, s)
                        self.scaleSet = s
                        local list = scene.isShared and fitted.shared or fitted.per
                        list[#list + 1] = s
                    end
                    return a
                end
            end
            return f
        end
    end)
    env.SlashCmdList.FOREVERTD("bench")
    for _ = 1, 4000 do
        Frames(env, 1)
        if not ns.Dev.tabs.Bench.Running() then break end
    end
    local shrunk = 0
    for _, s in ipairs(fitted.per) do if s < 1 then shrunk = shrunk + 1 end end
    T.eq(shrunk, 5 + 20 + 50, "every per-creep model was shrunk once per load")
    for _, s in ipairs(fitted.shared) do T.eq(s, 1, "shared scene models keep their size") end
    T.ok(#fitted.shared > 0, "shared scene models were loaded")
end

tests["combat closes the dev window and aborts a bench without saving"] = function(T)
    local env, ns = boot(T)
    env.SlashCmdList.FOREVERTD("bench")
    Frames(env, 100)
    stub.fire("PLAYER_REGEN_DISABLED")
    T.ok(not env.ForeverTDDevFrame:IsShown(), "closed")
    T.ok(not ns.Dev.tabs.Bench.Running(), "bench stopped")
    T.eq(#env.ForeverTDDB.dev.benchRuns, 0, "nothing saved")
    stub.inCombat = true
    env.SlashCmdList.FOREVERTD("dev")
    T.ok(not env.ForeverTDDevFrame:IsShown(), "won't open in combat")
    stub.inCombat = false
end

tests["icons: all-icons mode merges the client's lists; clicking stars"] = function(T)
    local env = boot(T, function(e)
        e.GetMacroIcons = function(t) for i = 1, 150 do t[#t + 1] = 1000 + i end end
        e.GetMacroItemIcons = function(t) for i = 100, 250 do t[#t + 1] = 1000 + i end end
    end)
    env.SlashCmdList.FOREVERTD("icons all")
    T.ok(FindText("All icons   page 1 / 3   (250)"), "250 unique icons over 3 pages")
    local cell = FindFrame(function(f) return f.key == 1001 end)
    T.ok(cell, "a cell shows icon 1001")
    cell:Run("OnClick")
    T.eq(env.ForeverTDDB.dev.starred.icons[1001], "icon 1001", "starred")
    cell:Run("OnClick")
    T.eq(env.ForeverTDDB.dev.starred.icons[1001], nil, "unstarred")
end

tests["icons: every curated entry gets checked against the client"] = function(T)
    local env, ns = boot(T)
    env.SlashCmdList.FOREVERTD("icons")
    for page = 2, 5 do env.SlashCmdList.FOREVERTD("icons curated " .. page) end -- the curated list spans pages now
    local checked, n = env.ForeverTDDB.dev.checked.icons, 0
    for _ in pairs(checked) do n = n + 1 end
    T.eq(n, #ns.AssetList.icons, "one check per curated icon")
end

-- Models are watched for the two things that matter on this client: a model cleared while its cell is hidden, and a
-- cell hidden while it still holds a model (that pair crashed Forever twice on 2026-10-17).
local function WatchModels(log)
    return function(e)
        local create = e.CreateFrame
        e.CreateFrame = function(kind, ...)
            local f = create(kind, ...)
            if kind == "PlayerModel" then
                f.SetCreature = function(self, id) self.holding = id; log.asks = log.asks + 1 end
                f.ClearModel = function(self)
                    if not self.cell.shown then log.hiddenClears = log.hiddenClears + 1 end
                    self.holding = nil
                end
            elseif kind == "Button" then
                f.Hide = function(self)
                    if self.model and self.model.holding then log.hiddenHolding = log.hiddenHolding + 1 end
                    return stub.Frame.Hide(self)
                end
            end
            return f
        end
    end
end

tests["creatures: load after layout, ask again, never clear or hide a model unsafely"] = function(T)
    local log = { asks = 0, hiddenClears = 0, hiddenHolding = 0 }
    local env, ns = boot(T, WatchModels(log))
    env.SlashCmdList.FOREVERTD("creatures")
    T.eq(Count("PlayerModel"), 10, "one page of models")
    T.ok(FindText("Curated   page 1 / " .. math.ceil(#ns.AssetList.creatures / 10)), "the curated pages")
    T.eq(log.asks, 0, "nothing asked for in the frame the page was laid out")
    stub.runTimers() -- the next frame
    T.eq(log.asks, 10, "the whole page asked for")
    local first = FindFrame(function(f) return f.kind == "PlayerModel" end)
    first.GetModelFileID = function() return 12345 end
    first:Run("OnModelLoaded")
    local npc1, npc3 = "npc:" .. ns.AssetList.creatures[1].npc, "npc:" .. ns.AssetList.creatures[3].npc
    T.eq(env.ForeverTDDB.dev.checked.creatures[npc1], 12345, "loaded model recorded")
    stub.now = 1.5
    stub.runTimers()
    T.eq(log.asks, 19, "asked again only for the nine still missing")
    env.SlashCmdList.FOREVERTD("creatures starred") -- nothing starred: every cell empties and hides
    env.SlashCmdList.FOREVERTD("creatures curated") -- and fills again
    stub.now = 10
    stub.runTimers()
    T.eq(log.asks, 49, "the new page asked three times; the old pages' timers asked nothing")
    T.eq(env.ForeverTDDB.dev.checked.creatures[npc3], false, "still missing after the retries: no model")
    T.eq(log.hiddenClears, 0, "never cleared a hidden model")
    T.eq(log.hiddenHolding, 0, "never hid a cell holding a model")
end

tests["the Save button and /td save reload the UI"] = function(T)
    local env = boot(T)
    stub.reloads = 0
    env.SlashCmdList.FOREVERTD("dev")
    local save = FindFrame(function(f) return f.kind == "Button" and f.text == "Save (reload)" end)
    T.ok(save, "Save button")
    save:Run("OnClick")
    env.SlashCmdList.FOREVERTD("save")
    T.eq(stub.reloads, 2, "both reload")
end

tests["maps: finds continents and zones from the player's map and lays out a zone's tiles"] = function(T)
    local env = boot(T, function(e)
        e.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 } }
        local info = {
            [37] = { mapID = 37, name = "Elwynn Forest", mapType = 3, parentMapID = 13 },
            [13] = { mapID = 13, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
            [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 946 },
        }
        e.C_Map = {
            GetBestMapForUnit = function() return 37 end,
            GetMapInfo = function(id) return info[id] end,
            GetMapChildrenInfo = function(id)
                if id == 947 then return { info[13] } end
                if id == 13 then
                    return { { mapID = 52, name = "Westfall", mapType = 3 }, info[37],
                        { mapID = 1000, name = "A micro map", mapType = 5 } }
                end
                return {}
            end,
            GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256,
                tileHeight = 256 } } end,
            GetMapArtLayerTextures = function()
                local t = {}
                for i = 1, 12 do t[i] = 5000 + i end
                return t
            end,
        }
    end)
    env.SlashCmdList.FOREVERTD("maps")
    T.ok(FindText("(3 maps)"), "a continent and its two zones, micro maps skipped")
    local elwynn = FindFrame(function(f) return f.entry and f.entry.mapID == 37 end)
    T.ok(elwynn, "Elwynn listed")
    elwynn:Run("OnClick")
    local check = env.ForeverTDDB.dev.checked.maps[37]
    T.eq(check and check.tiles, 12, "12 tiles drawn")
    T.ok(FindText("Elwynn Forest (Eastern Kingdoms)"), "caption")
end

tests["maps: a client without C_Map says so instead of failing"] = function(T)
    local env = boot(T)
    env.SlashCmdList.FOREVERTD("maps")
    T.ok(FindText("No maps: C_Map is missing"), "explained")
end

tests["the probe saves its facts after one second"] = function(T)
    local env = boot(T)
    env.SlashCmdList.FOREVERTD("probe")
    T.eq(env.ForeverTDDB.dev.probe, nil, "not before the second is up")
    stub.now = 1.5
    stub.runTimers()
    local probe = env.ForeverTDDB.dev.probe
    T.eq(probe.toc, 16001, "interface")
    T.eq(probe.onUpdateCallsHiddenFrame, 0, "counted")
    T.eq(type(probe.methods.actor), "string", "widget methods checked")
    T.eq(probe.api.C_Timer, "table", "API presence")
    env.SlashCmdList.FOREVERTD("probe")
    local frames = #stub.frames
    stub.now = 3
    stub.runTimers()
    env.SlashCmdList.FOREVERTD("probe")
    T.eq(#stub.frames, frames, "probing again makes no new frames")
end

return tests
