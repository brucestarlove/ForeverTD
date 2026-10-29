-- Dev/Probe.lua - environment probe (/td probe): records facts about this client that the Forever Custom Games Dev Kit
-- lists as open questions (its PLATFORM-PRIMER §13) or that the game's code will lean on: build and project ID,
-- screen and UI scale, which APIs and widget methods exist, WoW's bit library sign, whether OnUpdate runs on a
-- hidden frame, and the addon memory and CPU counters. Also shows three bundled test images, to settle which file
-- formats load.
-- Results: ForeverTDDB.dev.probe.
local ADDON, ns = ...
local Dev, Core = ns.Dev, ns.DevCore

local Tab = {}
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FORMATS = { { "PNG", "probe.png" }, { "TGA", "probe.tga" }, { "JPG", "probe.jpg" } }

local GLOBALS = {
    "C_AddOnProfiler", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "C_AddOns", "GetMacroIcons",
    "GetMacroItemIcons", "GetLooseMacroIcons", "C_Map", "C_Spell", "GetSpellTexture", "issecretvalue",
    "GetPhysicalScreenSize", "C_Timer", "CreateColor", "C_CreatureInfo",
}

-- Widget methods the game's code would use, checked on throwaway widgets (built once, kept hidden).
local METHODS = {
    texture = { "GetTextureFileID", "SetTexCoord", "SetRotation", "SetBlendMode", "SetSnapToPixelGrid" },
    modelScene = { "CreateActor", "SetCameraPosition", "SetCameraOrientationByAxisVectors", "SetCameraFieldOfView" },
    actor = { "SetModelByCreatureDisplayID", "SetModelByFileID", "IsLoaded", "SetYaw", "SetAnimation", "ClearModel",
        "SetPosition", "GetActiveBoundingBox" },
    playerModel = { "SetCreature", "SetDisplayInfo", "GetModelFileID", "ClearModel", "SetFacing", "RefreshCamera" },
}

local panel, out
local holder, widgets
local probing = false

local function Missing(obj, names)
    local missing = {}
    for _, name in ipairs(names) do
        if type(obj and obj[name]) ~= "function" then missing[#missing + 1] = name end
    end
    return #missing == 0 and "all present" or ("missing: " .. table.concat(missing, ", "))
end

local function Widgets()
    if widgets then return widgets end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    local scene = CreateFrame("ModelScene", nil, holder)
    widgets = {
        texture = holder:CreateTexture(),
        modelScene = scene,
        actor = Dev.Call(scene, "CreateActor"),
        playerModel = CreateFrame("PlayerModel", nil, holder),
    }
    return widgets
end

local function Facts()
    local f = { date = date("%Y-%m-%d %H:%M") }
    local version, build, buildDate, toc = GetBuildInfo()
    f.version, f.build, f.buildDate, f.toc = version, build, buildDate, toc
    f.projectID, f.projectCamelot = WOW_PROJECT_ID, WOW_PROJECT_CAMELOT
    if type(GetPhysicalScreenSize) == "function" then
        local w, h = GetPhysicalScreenSize()
        f.screen = tostring(w) .. "x" .. tostring(h)
    end
    f.uiScale = UIParent:GetEffectiveScale()
    f.zone = type(GetRealZoneText) == "function" and GetRealZoneText() or nil
    f.api = {}
    for _, name in ipairs(GLOBALS) do f.api[name] = type(_G[name]) end
    f.methods = {}
    for kind, names in pairs(METHODS) do f.methods[kind] = Missing(Widgets()[kind], names) end
    if bit then -- LuaBitOp returns signed results; whether WoW's does is §13's question
        f.bitBnot0 = bit.bnot(0)
        f.bitLshift1by31 = bit.lshift(1, 31)
    end
    f.heapKB = math.floor(Dev.HeapKB())
    f.addonKB = Dev.AddonKB()
    local P = C_AddOnProfiler
    if type(P) == "table" then
        f.profilerFunctions = table.concat(Core.SortedKeys(P), ", ")
        if type(P.IsEnabled) == "function" then
            local ok, on = pcall(P.IsEnabled)
            if ok then f.profilerEnabled = on end
        end
        local metrics = Enum and Enum.AddOnProfilerMetric
        if type(metrics) == "table" then
            f.profilerMetrics = table.concat(Core.SortedKeys(metrics), ", ")
            if metrics.RecentAverageTime and type(P.GetAddOnMetric) == "function" then
                local ok, ms = pcall(P.GetAddOnMetric, ADDON, metrics.RecentAverageTime)
                if ok then f.profilerRecentMs = ms end
            end
        end
    end
    return f
end

-- One line per fact; a table of facts (api, methods) becomes one wrapped line, so the panel holds it all.
local function Format(f)
    local lines = {}
    for _, k in ipairs(Core.SortedKeys(f)) do
        local v = f[k]
        if type(v) == "table" then
            local parts = {}
            for _, k2 in ipairs(Core.SortedKeys(v)) do parts[#parts + 1] = k2 .. "=" .. tostring(v[k2]) end
            lines[#lines + 1] = k .. ": " .. table.concat(parts, ", ")
        else
            lines[#lines + 1] = k .. ": " .. tostring(v)
        end
    end
    return table.concat(lines, "\n")
end

-- Counts OnUpdate calls for one second on a hidden frame and on a shown one, then saves everything. The two
-- counting frames are made once and reused: frames are never freed, so a probe must not leak two per run.
local hiddenFrame, shownFrame
local hiddenCalls, shownCalls = 0, 0
local function CountHidden() hiddenCalls = hiddenCalls + 1 end
local function CountShown() shownCalls = shownCalls + 1 end

function Tab.Run()
    if probing then return end
    probing = true
    local facts = Facts()
    out:SetText("Probing (one second)...")
    if not hiddenFrame then
        hiddenFrame = CreateFrame("Frame", nil, panel)
        hiddenFrame:Hide()
        shownFrame = CreateFrame("Frame", nil, panel)
    end
    hiddenCalls, shownCalls = 0, 0
    hiddenFrame:SetScript("OnUpdate", CountHidden)
    shownFrame:SetScript("OnUpdate", CountShown)
    C_Timer.After(1, function()
        hiddenFrame:SetScript("OnUpdate", nil)
        shownFrame:SetScript("OnUpdate", nil)
        facts.onUpdateCallsHiddenFrame, facts.onUpdateCallsShownFrame = hiddenCalls, shownCalls
        Dev.DB().probe = facts
        probing = false
        out:SetText(Format(facts) .. "\n\nKept in memory. Press Save (reload) to write it to disk.")
    end)
end

function Tab.Build(p)
    panel = p
    local run = Dev.Button(panel, "Run probe", 110, Tab.Run)
    run:SetPoint("TOPLEFT")
    local note = Dev.Text(panel, "GameFontDisableSmall")
    note:SetPoint("LEFT", run, "RIGHT", 10, 0)
    note:SetText("Images: each should show a coloured square. Blank or green = that format doesn't load.")
    for i, spec in ipairs(FORMATS) do
        local t = panel:CreateTexture(nil, "ARTWORK")
        t:SetSize(64, 64)
        t:SetPoint("TOPRIGHT", -(3 - i) * 84 - 10, -40)
        t:SetTexture(MEDIA .. spec[2])
        local label = Dev.Text(panel, "GameFontHighlightSmall", "CENTER")
        label:SetPoint("TOP", t, "BOTTOM", 0, -4)
        label:SetText(spec[1])
    end
    out = Dev.Text(panel, "GameFontHighlightSmall")
    out:SetPoint("TOPLEFT", 0, -34)
    out:SetPoint("BOTTOMRIGHT", -260, 0)
    out:SetJustifyV("TOP")
end

function Tab.OnOpen()
    local saved = Dev.DB().probe
    if not probing then
        out:SetText(saved and (Format(saved) .. "\n\n(Last saved probe. Run it again any time.)")
            or "Press Run probe (or type /td probe). It takes a second.")
    end
end

function Tab.Command() Tab.Run() end

Dev.RegisterTab("Probe", Tab)
