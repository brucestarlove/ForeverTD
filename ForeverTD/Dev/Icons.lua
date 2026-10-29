-- Dev/Icons.lua - icon browser (/td icons [curated|all|starred] [page]). Curated: the tower, creep and interface
-- candidates in AssetList, each checked against the client (the file ID it resolved, or false). All: every icon the
-- client's macro icon picker lists. Starred: Bruce's picks. Click an icon to star it; hover for its name and file ID.
local _, ns = ...
local Dev, Core, List = ns.Dev, ns.DevCore, ns.AssetList

local Tab = {}
local COLS, ROWS, SIZE, GAP = 14, 7, 40, 7
local PER_PAGE = COLS * ROWS
local TOP = 34
local MODES = { curated = "Curated", all = "All icons", starred = "Starred" }

local panel, pageText, footer
local cells = {}
local mode, page = "curated", 1
local allIcons, starredKeys

-- Old clients list icon names, current ones file IDs; SetTexture takes either once names get their folder.
local function IconFile(v)
    if type(v) == "string" and not v:find("\\", 1, true) then return "Interface\\Icons\\" .. v end
    return v
end

local SOURCES = { "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }

local function AllIcons()
    if allIcons then return allIcons end
    allIcons = {}
    local seen = {}
    for _, name in ipairs(SOURCES) do
        local fill = _G[name]
        if type(fill) == "function" then
            local list = {}
            if pcall(fill, list) then
                for _, v in ipairs(list) do
                    if not seen[v] then seen[v] = true; allIcons[#allIcons + 1] = v end
                end
            end
        end
    end
    return allIcons
end

local function Count()
    if mode == "curated" then return #List.icons end
    if mode == "all" then return #AllIcons() end
    return #starredKeys
end

-- key (what a star is saved under), file (what SetTexture gets), label, note
local function ItemAt(i)
    if mode == "curated" then
        local e = List.icons[i]
        if e then return e.file, e.file, e.name, e.file end
    elseif mode == "all" then
        local v = AllIcons()[i]
        if v then return v, IconFile(v), "icon " .. tostring(v), nil end
    else
        local k = starredKeys[i]
        if k ~= nil then
            local label = Dev.DB().starred.icons[k]
            return k, IconFile(k), type(label) == "string" and label or tostring(k), nil
        end
    end
end

local function Render()
    local count = Count()
    local pages, first
    page, pages, first = Core.Page(count, PER_PAGE, page)
    for i = 1, PER_PAGE do
        local c = cells[i]
        local key, file, label, note = ItemAt(first + i - 1)
        c.key, c.label, c.note = key, label, note
        if key == nil then
            c:Hide()
        else
            c.icon:SetTexture(file)
            c.star:SetShown(Dev.IsStarred("icons", key))
            c.fileID = Dev.Call(c.icon, "GetTextureFileID")
            local missing = false
            if mode == "curated" and type(c.icon.GetTextureFileID) == "function" then
                -- A path the client can't resolve has no file ID. The picture is the final word: a blank or
                -- green square means the same thing.
                missing = not c.fileID or c.fileID == 0
                Dev.Record("icons", key, not missing and c.fileID or false)
            end
            c.miss:SetText(missing and "|cffff3333?|r" or "")
            c:Show()
        end
    end
    pageText:SetText(string.format("%s   page %d / %d   (%d)", MODES[mode], page, pages, count))
    if mode == "all" and count == 0 then
        footer:SetText("This client lists no macro icons (GetMacroIcons and friends are missing or empty).")
    else
        footer:SetText("Click to star; hover for details. A red ? means the client gave no file ID for that path "
            .. "(the picture is the final word).")
    end
end

local function SetMode(newMode)
    if not MODES[newMode] then return end
    if newMode ~= mode then page = 1 end
    mode = newMode
    if mode == "starred" then starredKeys = Core.SortedKeys(Dev.DB().starred.icons) end
end

local function Cell(i)
    local c = CreateFrame("Button", nil, panel)
    c:SetSize(SIZE, SIZE)
    c:SetPoint("TOPLEFT", ((i - 1) % COLS) * (SIZE + GAP), -TOP - math.floor((i - 1) / COLS) * (SIZE + GAP))
    c.star = c:CreateTexture(nil, "BACKGROUND")
    c.star:SetPoint("TOPLEFT", -3, 3)
    c.star:SetPoint("BOTTOMRIGHT", 3, -3)
    c.star:SetColorTexture(1, 0.82, 0, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.miss = Dev.Text(c, "GameFontNormalLarge", "CENTER")
    c.miss:SetPoint("CENTER")
    c:SetScript("OnClick", function(self)
        if self.key == nil then return end
        self.star:SetShown(Dev.ToggleStar("icons", self.key, self.label))
    end)
    c:SetScript("OnEnter", function(self)
        Dev.Tooltip(self, self.label or "icon", {
            self.note or "",
            "file ID: " .. tostring(self.fileID or "?"),
            Dev.IsStarred("icons", self.key) and "Starred. Click to unstar." or "Click to star.",
        })
    end)
    c:SetScript("OnLeave", Dev.HideTooltip)
    return c
end

function Tab.Build(p)
    panel = p
    local x = 0
    for _, m in ipairs({ "curated", "all", "starred" }) do
        local b = Dev.Button(panel, MODES[m], 80, function() SetMode(m); Render() end)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + 84
    end
    local prev = Dev.Button(panel, "<", 30, function() page = page - 1; Render() end)
    prev:SetPoint("TOPLEFT", x + 8, 0)
    local nextB = Dev.Button(panel, ">", 30, function() page = page + 1; Render() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    local jump = Dev.Button(panel, ">>", 34, function() page = page + 10; Render() end)
    jump:SetPoint("LEFT", nextB, "RIGHT", 4, 0)
    pageText = Dev.Text(panel, "GameFontNormalSmall")
    pageText:SetPoint("LEFT", jump, "RIGHT", 10, 0)
    for i = 1, PER_PAGE do cells[i] = Cell(i) end
    footer = Dev.Text(panel, "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 0, 4)
end

function Tab.OnOpen()
    SetMode(mode) -- refreshes the starred list
    Render()
end

function Tab.OnClose() Dev.HideTooltip() end

function Tab.Command(rest)
    local word, number = rest:match("^(%a*)%s*(%d*)$")
    if word and word ~= "" then SetMode(word) end
    if number and number ~= "" then page = tonumber(number) end
    Render()
end

Dev.RegisterTab("Icons", Tab)
