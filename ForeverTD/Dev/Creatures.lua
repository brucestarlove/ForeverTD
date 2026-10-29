-- Dev/Creatures.lua - 3D creature browser (/td creatures [curated|starred] [page]).
-- Curated: AssetList's Azeroth creatures by NPC ID. Starred: Bruce's picks. Each model's outcome is recorded in
-- ForeverTDDB.dev.checked.creatures (the model file ID, or false when nothing loaded after the retries).
--
-- Lessons from Bruce's client (2026-10-17, build 70450), built into the code below:
--   - SetCreature on a creature the client hasn't seen yet shows nothing the first time and loads when asked again,
--     so a page loads one frame after it is laid out and asks again for anything still missing.
--   - Raw display IDs are gone from this browser: low ones load the missing-model placeholder (a checkered box), and
--     a PlayerModel holding it, cleared while hidden and then shown, crashed the client twice
--     (_classic_beta_/Errors/2026-10-17_17.24.17 and 17.28.28: Lua stack at this file's old line 81, display 4).
--     So models are cleared only while their cell is shown, and a cell is never hidden while it holds one.
--   - Another Forever game found that loading every display at once crashed the client,
--     so this loads one small page at a time.
local _, ns = ...
local Dev, Core, List = ns.Dev, ns.DevCore, ns.AssetList

local Tab = {}
local COLS, ROWS, CW, CH, GAP = 5, 2, 128, 180, 7
local PER_PAGE = COLS * ROWS
local TOP = 34
local ASK_AT = { 0, 1.5, 3 } -- seconds after a page is laid out: load, then ask again for anything not yet loaded
local GIVE_UP = 5            -- seconds: still nothing means "no model"
local MODES = { curated = "Curated", starred = "Starred" }

local panel, pageText
local cells = {}
local mode, page = "curated", 1
local starredKeys = {}
local generation = 0 -- bumps per page, so a late timer can't write into a newer page

local function Count()
    if mode == "curated" then return #List.creatures end
    return #starredKeys
end

-- key ("npc:448"), NPC ID, name, note
local function ItemAt(i)
    if mode == "curated" then
        local e = List.creatures[i]
        if e then return "npc:" .. e.npc, e.npc, e.name, e.zone end
    else
        local key = starredKeys[i]
        local id = key and tonumber(key:match("^npc:(%d+)$"))
        if id then
            local label = Dev.DB().starred.creatures[key]
            return key, id, type(label) == "string" and label or key, nil
        end
    end
end

local function SubText(c)
    if c.loaded then return "|cff88ff88model " .. tostring(c.fileID or "?") .. "|r" end
    if c.failed then return "|cffff5555no model|r" end
    return "loading..."
end

local function Paint(c)
    if c.key and Dev.IsStarred("creatures", c.key) then
        c:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
        c:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
    c.sub:SetText(SubText(c))
end

local function ModelLoaded(model)
    local c = model.cell
    if not c.key then return end
    c.loaded, c.failed = true, false
    c.fileID = Dev.Call(model, "GetModelFileID")
    Dev.Record("creatures", c.key, c.fileID or true)
    Dev.Call(model, "SetFacing", 0.4)
    Paint(c)
end

-- Asks the client for every model on the page that hasn't loaded yet.
local function Ask(gen)
    if gen ~= generation then return end
    for _, c in ipairs(cells) do
        if c.key and not c.loaded then Dev.Call(c.model, "SetCreature", c.id) end
    end
end

local function GiveUp(gen)
    if gen ~= generation then return end
    for _, c in ipairs(cells) do
        if c.key and not c.loaded then
            c.failed = true
            Dev.Record("creatures", c.key, false)
            Paint(c)
        end
    end
end

local function Render()
    generation = generation + 1
    local gen = generation
    local count = Count()
    local pages, first
    page, pages, first = Core.Page(count, PER_PAGE, page)
    for i = 1, PER_PAGE do
        local c = cells[i]
        local key, id, name, note = ItemAt(first + i - 1)
        -- A shown cell may hold a model: clear it now, while it's shown. A hidden cell holds none (see below).
        if c:IsShown() then Dev.Call(c.model, "ClearModel") end
        c.key, c.id, c.title, c.note = key, id, name, note
        c.loaded, c.failed, c.fileID = false, false, nil
        if key then
            c:Show()
            c.label:SetText(name)
            Paint(c)
        else
            c:Hide() -- already cleared above
        end
    end
    pageText:SetText(string.format("%s   page %d / %d", MODES[mode], page, pages))
    for _, delay in ipairs(ASK_AT) do C_Timer.After(delay, function() Ask(gen) end) end
    C_Timer.After(GIVE_UP, function() GiveUp(gen) end)
end

local function SetMode(newMode)
    if not MODES[newMode] then return end
    if newMode ~= mode then page = 1 end
    mode = newMode
    if mode == "starred" then starredKeys = Core.SortedKeys(Dev.DB().starred.creatures) end
end

local function Cell(i)
    local c = CreateFrame("Button", nil, panel, "BackdropTemplate")
    c:SetSize(CW, CH)
    c:SetPoint("TOPLEFT", ((i - 1) % COLS) * (CW + GAP), -TOP - math.floor((i - 1) / COLS) * (CH + GAP))
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    c:SetBackdropColor(0.08, 0.08, 0.1, 1)
    c.model = CreateFrame("PlayerModel", nil, c)
    c.model:SetPoint("TOPLEFT", 4, -4)
    c.model:SetPoint("BOTTOMRIGHT", -4, 32)
    c.model.cell = c
    c.model:SetScript("OnModelLoaded", ModelLoaded)
    c.label = Dev.Text(c, "GameFontHighlightSmall", "CENTER")
    c.label:SetPoint("BOTTOMLEFT", 4, 18)
    c.label:SetPoint("BOTTOMRIGHT", -4, 18)
    c.sub = Dev.Text(c, "GameFontDisableSmall", "CENTER")
    c.sub:SetPoint("BOTTOMLEFT", 4, 6)
    c.sub:SetPoint("BOTTOMRIGHT", -4, 6)
    c:SetScript("OnClick", function(self)
        if not self.key then return end
        Dev.ToggleStar("creatures", self.key, self.title)
        Paint(self)
    end)
    c:SetScript("OnEnter", function(self)
        Dev.Tooltip(self, self.title or "creature", {
            self.note or "",
            "NPC ID " .. tostring(self.id),
            "model file: " .. tostring(self.fileID or "-"),
            Dev.IsStarred("creatures", self.key) and "Starred. Click to unstar." or "Click to star.",
        })
    end)
    c:SetScript("OnLeave", Dev.HideTooltip)
    c:Hide() -- empty until a page fills it
    return c
end

function Tab.Build(p)
    panel = p
    local x = 0
    for _, m in ipairs({ "curated", "starred" }) do
        local b = Dev.Button(panel, MODES[m], 84, function() SetMode(m); Render() end)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + 88
    end
    local prev = Dev.Button(panel, "<", 30, function() page = page - 1; Render() end)
    prev:SetPoint("TOPLEFT", x + 8, 0)
    local nextB = Dev.Button(panel, ">", 30, function() page = page + 1; Render() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    pageText = Dev.Text(panel, "GameFontNormalSmall")
    pageText:SetPoint("LEFT", nextB, "RIGHT", 10, 0)
    for i = 1, PER_PAGE do cells[i] = Cell(i) end
end

-- Hidden model frames can come back blank (as other Forever games found), so every open reloads the page.
function Tab.OnOpen()
    SetMode(mode)
    Render()
end

function Tab.OnClose()
    generation = generation + 1
    Dev.HideTooltip()
end

function Tab.Command(rest)
    local word, number = rest:match("^(%a*)%s*(%d*)$")
    if word and word ~= "" then SetMode(word) end
    local n = tonumber(number)
    if n then page = n end
    Render()
end

Dev.RegisterTab("Creatures", Tab)
