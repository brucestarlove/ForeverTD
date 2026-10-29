-- Dev/Bench.lua - the performance bench (/td bench). It moves creeps along a lane the way the game will, at rising
-- counts, as 2D sprites and as 3D creatures, and measures this addon's Lua time and the whole frame's time for each.
-- About a minute. It answers PLATFORM-PRIMER §13's "frame cost of N moving pooled textures", and whether 3D creeps
-- are affordable. Objects are pooled and kept after a run (WoW never frees frames); /reload releases them.
local ADDON, ns = ...
local Dev, Core, List = ns.Dev, ns.DevCore, ns.AssetList

local Tab = {}
local BW, BH = Dev.CONTENT_W, Dev.CONTENT_H - 34 -- the board; a row of buttons sits under it
local SPRITE, BAR, MODEL = 24, 3, 56             -- creep icon, health bar and per-creep 3D frame sizes, in pixels
local SPEED = 0.05                               -- laps of the lane per second
local GROUND_W, GROUND_H = 20, 12                -- the shared 3D scene's ground, in model units
local CAM_DIST, CAM_PITCH, CAM_FOV = 4.5, 0.35, 40 -- each per-creep scene's camera
-- Model units a per-creep frame shows across, at the camera's target; a fitted model uses 85% of it.
local ROOM = 0.85 * 2 * CAM_DIST * math.tan(math.rad(CAM_FOV) / 2)
local floor = math.floor
local PathPoint, FacingYaw = Core.PathPoint, Core.FacingYaw

local board, results, runButton, stopButton, progress
local run, active, setupKB
local sprites, shots, modelFrames, actors = {}, {}, {}, {}
local scene

local function Pick(list, i) return list[(i - 1) % #list + 1] end

-- Pools: built on first need, reused by every later scenario and run.
local function Sprite(i)
    local s = sprites[i]
    if s then return s end
    s = CreateFrame("Frame", nil, board)
    s:SetSize(SPRITE, SPRITE + BAR + 1)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(SPRITE, SPRITE)
    s.icon:SetPoint("BOTTOM")
    s.icon:SetTexture(Pick(List.benchIcons, i))
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.back = s:CreateTexture(nil, "BACKGROUND")
    s.back:SetColorTexture(0, 0, 0, 0.8)
    s.back:SetSize(SPRITE, BAR)
    s.back:SetPoint("TOPLEFT")
    s.bar = s:CreateTexture(nil, "ARTWORK")
    s.bar:SetColorTexture(0.15, 0.9, 0.15, 1)
    s.bar:SetSize(SPRITE, BAR)
    s.bar:SetPoint("TOPLEFT")
    sprites[i] = s
    return s
end

local function Shot(j)
    local t = shots[j]
    if t then return t end
    t = board:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.85, 0.3, 1)
    t:SetSize(5, 5)
    t:SetBlendMode("ADD")
    shots[j] = t
    return t
end

local function ModelFrame(i)
    local f = modelFrames[i]
    if f then return f end
    f = CreateFrame("ModelScene", nil, board)
    f:SetSize(MODEL, MODEL)
    Dev.AimCamera(f, CAM_DIST, CAM_PITCH, 0.7, CAM_FOV)
    f.actor = f:CreateActor()
    modelFrames[i] = f
    return f
end

local function Scene()
    if scene then return scene end
    scene = CreateFrame("ModelScene", nil, board)
    scene:SetAllPoints(board)
    Dev.AimCamera(scene, 20, 0.95, 0, 36)
    return scene
end

local function Actor(i)
    local a = actors[i]
    if a then return a end
    a = Scene():CreateActor()
    actors[i] = a
    return a
end

local function LoadActor(actor, display)
    Dev.Call(actor, "SetScale", 1)
    Dev.Call(actor, "SetModelByCreatureDisplayID", display)
    Dev.Call(actor, "SetAnimation", 4, 0, 1, 0) -- 4 = walk; set again once loaded
    Dev.Call(actor, "Show")
end

-- A model's size once loaded: width, depth, height (see DevCore.Extent). Clients answer with six numbers or with two
-- vectors (handle both, as polished Forever games do).
local function Size(actor)
    local get = actor.GetMaxBoundingBox or actor.GetActiveBoundingBox
    if not get then return nil end
    local ok, x1, y1, z1, x2, y2, z2 = pcall(get, actor)
    if not ok then return nil end
    if type(x1) ~= "number" and type(x1) ~= "nil" and x1.GetXYZ then
        local lo, hi = x1, y1
        x1, y1, z1 = lo:GetXYZ()
        x2, y2, z2 = hi:GetXYZ()
    end
    return Core.Extent(x1, y1, z1, x2, y2, z2)
end

-- Shrinks a per-creep scene's model to fit its frame whatever way it faces (a wolf is long, a murloc is tall), and
-- aims the camera at its middle. Once per load, as soon as the model reports loaded.
local function Fit(f)
    local a = f.actor
    f.fitted = true
    local w, d, h = Size(a)
    if not w then return end
    local span = math.sqrt(w * w + d * d) -- its widest outline as it turns
    local scale = Core.FitScale(span, span, h, ROOM)
    Dev.Call(a, "SetScale", scale)
    Dev.AimCamera(f, CAM_DIST, CAM_PITCH, h * scale / 2, CAM_FOV)
end

local function ActorOf(kind, i)
    if kind == "modelframes" then return modelFrames[i].actor end
    return actors[i]
end

-- One frame of movement: every creep moves, every health bar changes width (a worst case; the game will only touch
-- bars that changed), every projectile moves. Only numbers in this loop, so it makes no garbage.
local function Move(kind, n, time)
    if kind == "sprites" then
        for i = 1, n do
            local s = sprites[i]
            local u, v = PathPoint(time * SPEED + i / n)
            s:SetPoint("CENTER", board, "TOPLEFT", u * BW, -v * BH)
            s.bar:SetWidth(SPRITE * (0.2 + 0.8 * ((i * 0.37 + time * 0.5) % 1)))
        end
        local m = floor(n / 2)
        for j = 1, m do
            local u, v = PathPoint(time * SPEED * 3 + j / m + 0.5 / n)
            shots[j]:SetPoint("CENTER", board, "TOPLEFT", u * BW, -v * BH)
        end
    elseif kind == "modelframes" then
        for i = 1, n do
            local f = modelFrames[i]
            local u, v, du, dv = PathPoint(time * SPEED + i / n)
            f:SetPoint("CENTER", board, "TOPLEFT", u * BW, -v * BH)
            f.actor:SetYaw(FacingYaw(du, dv))
            if not f.fitted and f.actor:IsLoaded() then Fit(f) end
        end
    elseif kind == "modelscene" then
        for i = 1, n do
            local a = actors[i]
            local u, v, du, dv = PathPoint(time * SPEED + i / n)
            a:SetPosition((u - 0.5) * GROUND_W, (0.5 - v) * GROUND_H, 0)
            a:SetYaw(FacingYaw(du * GROUND_W, dv * GROUND_H))
        end
    end
end

local function ShowScenario(kind, n)
    if kind == "sprites" then
        for i = 1, n do Sprite(i):Show() end
        for j = 1, floor(n / 2) do Shot(j):Show() end
    elseif kind == "modelframes" then
        for i = 1, n do
            local f = ModelFrame(i)
            f:Show()
            f.fitted = false
            LoadActor(f.actor, Pick(List.benchDisplays, i))
        end
    elseif kind == "modelscene" then
        Scene():Show()
        for i = 1, n do LoadActor(Actor(i), Pick(List.benchDisplays, i)) end
    end
end

local function HideScenario(kind, n)
    if kind == "sprites" then
        for i = 1, n do sprites[i]:Hide() end
        for j = 1, floor(n / 2) do shots[j]:Hide() end
    elseif kind == "modelframes" or kind == "modelscene" then
        -- Clear models only while they're visible: clearing a hidden model frame and showing it again crashed this
        -- client (see Creatures.lua). If the window is already closed, leave them; the next load replaces them.
        local visible = board:IsVisible()
        for i = 1, n do
            local a = ActorOf(kind, i)
            if visible then Dev.Call(a, "ClearModel") end
            Dev.Call(a, "Hide")
            if kind == "modelframes" then modelFrames[i]:Hide() end
        end
        if kind == "modelscene" then scene:Hide() end
    end
end

local function CountLoaded(kind, n)
    local loaded = 0
    for i = 1, n do
        if Dev.Call(ActorOf(kind, i), "IsLoaded") then loaded = loaded + 1 end
    end
    return loaded
end

local function Animate(kind, n)
    if kind ~= "modelframes" and kind ~= "modelscene" then return end
    for i = 1, n do Dev.Call(ActorOf(kind, i), "SetAnimation", 4, 0, 1, 0) end
end

-- The client's own per-addon timing, when it has one (Retail 11.x added C_AddOnProfiler; Forever is unconfirmed).
local function ProfilerMs()
    local P = C_AddOnProfiler
    local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
    if not (P and type(P.GetAddOnMetric) == "function" and metric) then return nil end
    local ok, ms = pcall(P.GetAddOnMetric, ADDON, metric)
    return ok and type(ms) == "number" and ms or nil
end

local function SetText(text) results:SetText(text) end

local function LastRunText()
    local runs = Dev.DB().benchRuns
    local last = runs[#runs]
    if not last then
        return "No bench runs yet.\n\nPress Run bench (or type /td bench), then keep this window open and stand still "
            .. "somewhere quiet for about a minute. Afterwards, press Save (reload) so the results reach disk."
    end
    return Core.FormatRun(last) .. "\n\nKept in memory. Press Save (reload) at the bottom right to write it to disk."
end

local function Progress()
    if not run or run.phase == "done" or not run.list[run.index] then
        progress:SetText("")
        return
    end
    local sc = run.list[run.index]
    progress:SetText(string.format("%d/%d  %s%s  (%s)", run.index, #run.list, Core.LABELS[sc.kind],
        sc.n > 0 and (" x" .. sc.n) or "", run.phase == "warm" and "settling" or "measuring"))
end

local function Begin(sc)
    local before = Dev.HeapKB()
    ShowScenario(sc.kind, sc.n)
    active = sc
    setupKB = Dev.HeapKB() - before
end

local function Finish() -- annotates the summary Step() just appended, then clears the board
    local r = run.results[#run.results]
    r.setupKB = floor(setupKB + 0.5) -- heap growth while building this scenario (noisy: shared with every addon)
    if active.kind == "modelframes" or active.kind == "modelscene" then
        r.loaded = CountLoaded(active.kind, active.n)
    end
    r.profilerMs = ProfilerMs()
    HideScenario(active.kind, active.n)
    active = nil
end

local function Save()
    local w, h
    if type(GetPhysicalScreenSize) == "function" then w, h = GetPhysicalScreenSize() end
    local version, build = GetBuildInfo()
    local displays = {}
    for i, d in ipairs(List.benchDisplays) do displays[i] = d end
    local record = {
        date = date("%Y-%m-%d %H:%M"), version = version, build = build,
        zone = type(GetRealZoneText) == "function" and GetRealZoneText() or nil,
        screen = w and (w .. "x" .. h) or nil, uiScale = UIParent:GetEffectiveScale(),
        addonKB = Dev.AddonKB(), displays = displays, results = run.results,
    }
    local runs = Dev.DB().benchRuns
    runs[#runs + 1] = record
    Core.Trim(runs, 8)
end

local function Stop(reason)
    if not run then return end
    if active then HideScenario(active.kind, active.n) end
    run, active = nil, nil
    runButton:Enable()
    stopButton:Disable()
    Progress()
    SetText("Bench stopped (" .. reason .. "); nothing saved.\n\n" .. LastRunText())
end

function Tab.Start()
    if run then return end
    run = Core.NewRun(Core.SCENARIOS)
    active, setupKB = nil, 0
    runButton:Disable()
    stopButton:Enable()
    SetText("Running. Keep this window open and stand still; it takes about a minute.")
end

function Tab.Running() return run ~= nil end

function Tab.OnUpdate(elapsed)
    if not run then return end
    local t0 = debugprofilestop()
    if active then Move(active.kind, active.n, run.time) end
    local event = Core.Step(run, elapsed, debugprofilestop() - t0)
    if not event then return end
    if event == "begin" then
        Begin(run.list[run.index])
    elseif event == "measure" then
        Animate(active.kind, active.n)
    elseif event == "next" then
        Finish()
        Begin(run.list[run.index])
    elseif event == "done" then
        Finish()
        Save()
        run = nil
        runButton:Enable()
        stopButton:Disable()
        SetText(LastRunText())
    end
    Progress()
end

function Tab.Build(panel)
    board = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    board:SetPoint("TOPLEFT")
    board:SetSize(BW, BH)
    board:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    board:SetBackdropColor(0.08, 0.1, 0.07, 1)
    board:SetClipsChildren(true)
    results = Dev.Text(board, "GameFontHighlightSmall")
    results:SetPoint("TOPLEFT", 10, -10)
    results:SetPoint("BOTTOMRIGHT", -10, 10)
    results:SetJustifyV("TOP")
    runButton = Dev.Button(panel, "Run bench", 110, Tab.Start)
    runButton:SetPoint("BOTTOMLEFT", 0, 4)
    stopButton = Dev.Button(panel, "Stop", 70, function() Stop("stopped by you") end)
    stopButton:SetPoint("LEFT", runButton, "RIGHT", 6, 0)
    stopButton:Disable()
    progress = Dev.Text(panel, "GameFontNormalSmall")
    progress:SetPoint("LEFT", stopButton, "RIGHT", 12, 0)
end

function Tab.OnOpen()
    if not run then SetText(LastRunText()) end
end

function Tab.OnClose() Stop("the window or tab closed") end

function Tab.Command() Tab.Start() end

Dev.RegisterTab("Bench", Tab)
