-- Dev/Dev.lua - the dev window (/td dev): a performance bench, asset browsers and an environment probe, as tabs.
-- Dev tools only. The game never calls into Dev/, a tab builds nothing until it is first opened, and the window's
-- OnUpdate stops while it is closed, so unused dev tools cost no CPU. Findings go to ForeverTDDB.dev, which reaches
-- disk at /reload or logout, where tools/dev-report.lua reads it for the agent.
local ADDON, ns = ...
local Dev = { tabs = {}, order = {} }
ns.Dev = Dev

local W, H = 700, 500
Dev.CONTENT_W, Dev.CONTENT_H = 680, 420

-- Calls obj:method(...) if this client has that method, inside pcall. Dev tools probe APIs that may differ on
-- Forever; a missing or failing one must leave the rest working. Returns the first two results, or nil.
function Dev.Call(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if ok then return a, b end
    return nil
end

-- Lua heap in KB. All addons share one Lua state, so this counts everyone: compare differences, not totals.
function Dev.HeapKB()
    local ok, kb = pcall(collectgarbage, "count")
    return ok and kb or 0
end

-- This addon's own memory in KB, when the client offers it. It walks every addon, so call it rarely.
function Dev.AddonKB()
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if type(UpdateAddOnMemoryUsage) ~= "function" or type(get) ~= "function" then return nil end
    if not pcall(UpdateAddOnMemoryUsage) then return nil end
    local ok, kb = pcall(get, ADDON)
    return ok and type(kb) == "number" and math.floor(kb + 0.5) or nil
end

-- ForeverTDDB.dev: benchRuns (newest last), probe, starred[kind][key] = label (Bruce's picks), and
-- checked[kind][key] = what the client resolved (a file ID, true, or false for "didn't load").
function Dev.DB()
    ForeverTDDB = ForeverTDDB or {}
    local dev = ForeverTDDB.dev or {}
    ForeverTDDB.dev = dev
    dev.benchRuns = dev.benchRuns or {}
    dev.starred = dev.starred or {}
    dev.checked = dev.checked or {}
    for _, kind in ipairs({ "icons", "creatures", "maps" }) do
        dev.starred[kind] = dev.starred[kind] or {}
        dev.checked[kind] = dev.checked[kind] or {}
    end
    return dev
end

function Dev.IsStarred(kind, key) return Dev.DB().starred[kind][key] ~= nil end

function Dev.ToggleStar(kind, key, label)
    local starred = Dev.DB().starred[kind]
    if starred[key] ~= nil then starred[key] = nil else starred[key] = label or true end
    return starred[key] ~= nil
end

function Dev.Record(kind, key, value) Dev.DB().checked[kind][key] = value end

-- Small widget helpers shared by the tabs.
function Dev.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function Dev.Text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function Dev.Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end

function Dev.HideTooltip() GameTooltip:Hide() end

-- Points a ModelScene's camera at (0, 0, targetZ) from `dist` away, tilted down by `pitch` radians, looking along +y.
-- The axis vectors are the ones a polished Forever game passes on this client.
-- Seen in Bruce's client (2026-10-17): with this camera, screen right is world +x, screen down is toward the camera
-- (world -y), and an actor at yaw 0 faces +x, so yaw = atan2(-dv, du) faces screen motion (du right, dv down).
-- Every call is guarded: a scene that refuses one still renders.
function Dev.AimCamera(scene, dist, pitch, targetZ, fovDegrees)
    local fy, fz = math.cos(pitch), -math.sin(pitch)
    Dev.Call(scene, "SetCameraPosition", 0, -dist * fy, (targetZ or 0) - dist * fz)
    Dev.Call(scene, "SetCameraOrientationByAxisVectors", 0, fy, fz, -1, 0, 0, 0, -fz, fy)
    Dev.Call(scene, "SetCameraFieldOfView", math.rad(fovDegrees or 40))
    Dev.Call(scene, "SetCameraNearClip", 0.1)
    Dev.Call(scene, "SetCameraFarClip", 200)
    Dev.Call(scene, "SetLightVisible", true)
    Dev.Call(scene, "SetLightAmbientColor", 0.8, 0.8, 0.8)
    Dev.Call(scene, "SetLightDiffuseColor", 0.8, 0.75, 0.7)
    Dev.Call(scene, "SetLightDirection", -0.4, 1, -1)
end

-- The window: named (ESC closes it), movable, clamped, above the game window.
local frame = CreateFrame("Frame", "ForeverTDDevFrame", UIParent, "BackdropTemplate")
frame:SetSize(W, H)
frame:SetPoint("CENTER", 0, 40)
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
frame:Hide()
tinsert(UISpecialFrames, "ForeverTDDevFrame")
Dev.frame = frame

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local title = Dev.Text(frame, "GameFontNormal", "RIGHT")
title:SetPoint("TOPRIGHT", -34, -14)
title:SetText("ForeverTD dev")

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", 10, -40)
content:SetSize(Dev.CONTENT_W, Dev.CONTENT_H)

local status = Dev.Text(frame, "GameFontDisableSmall")
status:SetPoint("BOTTOMLEFT", 12, 12)

-- SavedVariables reach disk only at /reload or logout, and a client crash loses everything since (it did, twice, on
-- 2026-10-17). After each test, Save writes the results to disk by reloading the UI.
local save = Dev.Button(frame, "Save (reload)", 110, function() ReloadUI() end)
save:SetPoint("BOTTOMRIGHT", -10, 8)
save:SetScript("OnEnter", function(self)
    Dev.Tooltip(self, "Save to disk", { "Reloads the UI, which writes the dev results (and the game) to disk "
        .. "so a crash can't lose them. Same as /reload or /td save." })
end)
save:SetScript("OnLeave", function() Dev.HideTooltip() end)

-- A tab is a table with Build(panel) and optional OnOpen(), OnClose(), OnUpdate(elapsed) and Command(rest).
function Dev.RegisterTab(name, tab)
    tab.name = name
    Dev.tabs[name] = tab
    Dev.order[#Dev.order + 1] = name
    local b = Dev.Button(frame, name, 88, function() Dev.Show(name) end)
    b:SetPoint("TOPLEFT", 10 + (#Dev.order - 1) * 92, -10)
    tab.button = b
end

function Dev.Show(name)
    local tab = Dev.tabs[name]
    if not tab then return false end
    if InCombatLockdown() then
        print("ForeverTD: the dev window stays shut during combat.")
        return false
    end
    local old = Dev.current
    if old and old ~= tab then
        old.panel:Hide()
        old.button:UnlockHighlight()
        if frame:IsShown() and old.OnClose then old.OnClose() end
    end
    if not tab.panel then -- built on first use
        tab.panel = CreateFrame("Frame", nil, content)
        tab.panel:SetAllPoints(content)
        tab.Build(tab.panel)
    end
    Dev.current = tab
    tab.panel:Show()
    tab.button:LockHighlight()
    if frame:IsShown() then
        if old ~= tab and tab.OnOpen then tab.OnOpen() end
    else
        frame:Show() -- OnShow opens the current tab
    end
    return true
end

function Dev.Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        Dev.Show(Dev.current and Dev.current.name or "Bench")
    end
end

frame:SetScript("OnShow", function()
    if Dev.current and Dev.current.OnOpen then Dev.current.OnOpen() end
end)

frame:SetScript("OnHide", function() -- ESC, the close button, combat, or /td dev
    Dev.HideTooltip()
    if Dev.current and Dev.current.OnClose then Dev.current.OnClose() end
end)

local statusClock, tabMs = 0, 0
frame:SetScript("OnUpdate", function(_, elapsed)
    local tab = Dev.current
    if tab and tab.OnUpdate then
        local t0 = debugprofilestop()
        tab.OnUpdate(elapsed)
        tabMs = tabMs * 0.9 + (debugprofilestop() - t0) * 0.1
    end
    statusClock = statusClock + elapsed
    if statusClock >= 0.5 then
        statusClock = 0
        status:SetText(string.format("%.0f fps   this tab: %.2f ms Lua per frame   UI Lua heap %.1f MB (all addons)",
            GetFramerate(), tabMs, Dev.HeapKB() / 1024))
    end
end)

-- Combat: get out of the way (keyboard and protected frames are locked down in combat). A running bench aborts.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if frame:IsShown() then
        frame:Hide()
        print("ForeverTD: dev window closed for combat.")
    end
end)

-- /td words this file answers, and the tab each opens.
local TAB_FOR = { bench = "Bench", icons = "Icons", creatures = "Creatures", maps = "Maps", probe = "Probe" }

function Dev.Handles(word) return word == "dev" or TAB_FOR[word] ~= nil end

function Dev.Command(msg)
    local word, rest = msg:match("^(%S*)%s*(.-)$")
    if word == "dev" then
        Dev.Toggle()
        return
    end
    local name = TAB_FOR[word]
    if name and Dev.Show(name) then
        local tab = Dev.tabs[name]
        if tab.Command then tab.Command(rest or "") end
    end
end
