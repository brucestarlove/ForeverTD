-- Menu.lua - the menu over the game window, in four tabs:
--   Campaign  the four campaigns down the left; the chosen one's chapters (its levels) in the middle; the chosen
--             level on the right: its map, its briefing, what's new, stars and Play / Heroic
--   Armory    a tab per campaign: five research tiers for each of its towers (specializations at tiers 3 and 5)
--   Supplies  small, capped bonuses for every level
--   Options   sound, auto waves, story, effects, window size, saving
-- Presentation only: it reads ns.Game and Meta, and spends Warmarks through Game.Buy.
local _, ns = ...
local Content, Levels, Meta, Board, Ui = ns.Content, ns.Levels, ns.Meta, ns.Board, ns.Ui
local Text, Button, Inline, Hex = Ui.Text, Ui.Button, Ui.Inline, Ui.Hex
local Menu = {}
ns.Menu = Menu

local ICON = "Interface\\Icons\\"
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- the raid-marker star
local WARMARK = ICON .. "INV_Misc_Coin_03"                        -- a draft icon for Warmarks
local GREY, GREEN, ORANGE, WHITE_TEXT, GOLD = "|cff888888", "|cff40ff40", "|cffff8040", "|cffffffff", "|cffffd200"
local LENGTH = { short = "Short", standard = "Standard", siege = "Siege" }
local WHY = { warmarks = "Not enough Warmarks.", max = "That's complete already.",
    locked = "That tower hasn't joined you yet." }
local PAGES = { "campaign", "armory", "supplies", "options" }
local TAB_LABEL = { campaign = "Campaign", armory = "Armory", supplies = "Supplies", options = "Options" }
local TIP = {
    campaign = "Win a level to open the next; towers and heroes join as you go. Stars open the later campaigns "
        .. "(Normal and Heroic stars both count), and 3 stars on Normal open Heroic.",
    armory = "Research is permanent and applies to the next level you start; each campaign's later levels expect "
        .. "some. Pick a specialization in a level: select a rank-3 tower.",
    supplies = "Supplies apply to every level you start from now on, in every campaign.",
    options = "Options are saved with your progress.",
}

local function Game() return ns.Game end

local function Background(frame, alpha)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, alpha)
    return t
end

local function Highlight(frame)
    local t = frame:CreateTexture(nil, "HIGHLIGHT")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 0.08)
    return t
end

-- The menu covers everything under the title bar, above the board and its overlays.
local menu = CreateFrame("Frame", nil, Ui.window)
menu:SetPoint("TOPLEFT", 4, -28)
menu:SetPoint("BOTTOMRIGHT", -4, 4)
menu:SetFrameLevel(Ui.boardFrame:GetFrameLevel() + 30)
menu:EnableMouse(true) -- clicks stop here instead of reaching the board
local backdrop = menu:CreateTexture(nil, "BACKGROUND")
backdrop:SetAllPoints()
backdrop:SetColorTexture(0.05, 0.05, 0.06, 0.98)
menu:Hide()
Ui.menu = menu

-- Tabs, a gold rule under them, and the wallet on the right.
local tabs, pages, current = {}, {}, "campaign"
for i, key in ipairs(PAGES) do
    local b = CreateFrame("Button", nil, menu)
    b:SetSize(104, 26)
    b:SetPoint("TOPLEFT", 10 + (i - 1) * 108, -6)
    b.bg = Background(b, 0.04)
    b.hl = Highlight(b)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.text = Text(b, "GameFontNormal", "CENTER")
    b.text:SetAllPoints()
    b.text:SetText(TAB_LABEL[key])
    b:SetScript("OnClick", function() Menu.Page(key) end)
    tabs[key] = b
    local page = CreateFrame("Frame", nil, menu)
    page:SetPoint("TOPLEFT", 0, -38)
    page:SetPoint("BOTTOMRIGHT", 0, 40)
    page:Hide()
    pages[key] = page
end
local rule = menu:CreateTexture(nil, "ARTWORK")
rule:SetColorTexture(1, 0.82, 0, 0.25)
rule:SetHeight(1)
rule:SetPoint("TOPLEFT", 8, -34)
rule:SetPoint("TOPRIGHT", -8, -34)
local wallet = Text(menu, "GameFontHighlight", "RIGHT")
wallet:SetPoint("TOPRIGHT", -14, -12)

-- Footer: a line of help or news, and the way back.
local note = Text(menu, "GameFontHighlightSmall")
note:SetPoint("BOTTOMLEFT", 14, 12)
note:SetWidth(390)
local said, saidUntil = nil, 0

function Menu.Say(text)
    said, saidUntil = text, GetTime() + 6
    note:SetText(text)
end

local pendingStart -- { level, difficulty } waiting for "abandon the current run?"
local backButton = Button(menu, "Back to the game", 140, function()
    pendingStart = nil
    Ui.ShowMenu(false)
end)
backButton:SetPoint("BOTTOMRIGHT", -10, 10)
local abandonButton = Button(menu, "Abandon it", 100, function()
    local p = pendingStart
    pendingStart = nil
    if p then Game().Start(p.level, p.difficulty) end
end)
abandonButton:SetPoint("RIGHT", backButton, "LEFT", -6, 0)
local saveButton = Button(menu, "Save (reload)", 110, function() Game().Save() end)
saveButton:SetPoint("RIGHT", abandonButton, "LEFT", -6, 0)

local function Choose(levelId, difficulty)
    local G = Game()
    if G.state and not G.state.over then -- ask first; "Abandon it" starts the new one
        pendingStart = { level = levelId, difficulty = difficulty }
        Menu.Refresh()
        return
    end
    pendingStart = nil
    G.Start(levelId, difficulty)
end

local function Buy(what, key)
    local cost, why = Game().Buy(what, key)
    if cost then
        Menu.Say(GREEN .. "Done, for " .. cost .. " Warmarks. It applies to the next level you start.|r")
    else
        Menu.Say(ORANGE .. (WHY[why] or "You can't buy that.") .. "|r")
    end
    Menu.Refresh()
end

local function StarRow(parent, x, y, size)
    local row = {}
    for i = 1, 3 do
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetTexture(STAR)
        t:SetSize(size or 14, size or 14)
        t:SetPoint("TOPLEFT", x + (i - 1) * ((size or 14) + 1), y)
        row[i] = t
    end
    return row
end

local function SetStars(row, n)
    for i, t in ipairs(row) do
        local on = i <= (n or 0)
        t:SetDesaturated(not on)
        t:SetAlpha(on and 1 or 0.25)
    end
end

-- Why a level is locked, in words.
local function LockText(profile, level)
    local why = Meta.LockReason(profile, level)
    if not why then return "" end
    if why.campaignStars then
        return string.format("Opens at %d stars (you have %d).", why.campaignStars, Meta.TotalStars(profile))
    end
    if why.level then return "Win " .. why.level.name .. " to open it." end
    if why.stars then return string.format("Needs %d stars (you have %d).", why.stars, Meta.TotalStars(profile)) end
    return "Locked."
end

------------------------------------------------------------------------------------------------------------------------
-- Campaign
local campaign = pages.campaign
local banners, chapters = {}, {}
local selectedCamp, selectedLevel -- campaign index, level id

local BANNER_H = 88
for i, camp in ipairs(Levels.campaigns) do
    local b = CreateFrame("Button", nil, campaign)
    b:SetSize(172, BANNER_H)
    b:SetPoint("TOPLEFT", 10, -6 - (i - 1) * (BANNER_H + 6))
    b.bg = Background(b, 0.05)
    b.hl = Highlight(b)
    b.band = b:CreateTexture(nil, "ARTWORK") -- the campaign's colour along the top
    b.band:SetPoint("TOPLEFT")
    b.band:SetPoint("TOPRIGHT")
    b.band:SetHeight(3)
    b.band:SetColorTexture(camp.color[1], camp.color[2], camp.color[3], 0.9)
    b.sel = b:CreateTexture(nil, "ARTWORK")
    b.sel:SetPoint("TOPLEFT")
    b.sel:SetPoint("BOTTOMLEFT")
    b.sel:SetWidth(3)
    b.sel:SetColorTexture(1, 0.82, 0, 1)
    b.crest = b:CreateTexture(nil, "ARTWORK")
    b.crest:SetSize(38, 38)
    b.crest:SetPoint("TOPLEFT", 8, -10)
    b.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = Text(b, "GameFontNormal")
    b.name:SetPoint("TOPLEFT", 54, -10)
    b.name:SetWidth(112)
    b.title = Text(b, "GameFontHighlightSmall")
    b.title:SetPoint("TOPLEFT", 54, -28)
    b.title:SetWidth(112)
    b.sub = Text(b, "GameFontHighlightSmall")
    b.sub:SetPoint("TOPLEFT", 8, -56)
    b.sub:SetWidth(158)
    b:SetScript("OnClick", function()
        selectedCamp, selectedLevel, pendingStart = i, nil, nil
        Menu.Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(camp.name .. ": " .. camp.title)
        GameTooltip:AddLine(camp.blurb, 1, 1, 1, true)
        local intro = camp.story and camp.story.intro
        if intro then GameTooltip:AddLine(intro[1] .. ": \"" .. intro[2] .. "\"", 0.9, 0.82, 0.5, true) end
        local names = {}
        for _, kind in ipairs(camp.towers) do names[#names + 1] = Content.towers[kind].name end
        GameTooltip:AddLine("Towers: " .. table.concat(names, ", ") .. ". Hero: "
            .. Content.towers[camp.hero.kind].name .. ".", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    banners[i] = b
end

local CHAPTER_H = 44
local function NewChapter(i)
    local r = CreateFrame("Button", nil, campaign)
    r:SetSize(200, CHAPTER_H - 4)
    r:SetPoint("TOPLEFT", 190, -6 - (i - 1) * CHAPTER_H)
    r.bg = Background(r, 0.05)
    r.hl = Highlight(r)
    r.sel = r:CreateTexture(nil, "ARTWORK")
    r.sel:SetPoint("TOPLEFT")
    r.sel:SetPoint("BOTTOMLEFT")
    r.sel:SetWidth(3)
    r.sel:SetColorTexture(1, 0.82, 0, 1)
    r.num = Text(r, "GameFontNormalLarge", "CENTER")
    r.num:SetPoint("LEFT", 4, 0)
    r.num:SetWidth(22)
    r.name = Text(r, "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 30, -5)
    r.name:SetWidth(166)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.stars = StarRow(r, 30, -22, 12)
    r.sub = Text(r, "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", 74, -23)
    r.sub:SetWidth(122)
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
    r:SetScript("OnClick", function(self)
        selectedLevel, pendingStart = self.level and self.level.id, nil
        Menu.Refresh()
    end)
    chapters[i] = r
    return r
end

-- The level on the right.
local DETAIL_X, DETAIL_W, THUMB_W, THUMB_H = 398, 304, 288, 180 -- the map keeps the board's 16:10 shape
local detail = CreateFrame("Frame", nil, campaign)
detail:SetPoint("TOPLEFT", DETAIL_X, -6)
detail:SetSize(DETAIL_W, 384)
detail.thumb = CreateFrame("Frame", nil, detail) -- the level's board, small: map art and road
detail.thumb:SetSize(THUMB_W, THUMB_H)
detail.thumb:SetPoint("TOP", 0, 0)
detail.thumb:SetClipsChildren(true)
local thumbArt = CreateFrame("Frame", nil, detail.thumb) -- drawn on a child, as the board does, so the clip applies
thumbArt:SetAllPoints(detail.thumb)
detail.paint = { layer = thumbArt, anchor = detail.thumb, tiles = {}, cells = {}, shown = 0 }
detail.name = Text(detail, "GameFontNormalLarge")
detail.name:SetPoint("TOPLEFT", 0, -THUMB_H - 6)
detail.name:SetWidth(DETAIL_W)
detail.info = Text(detail, "GameFontDisableSmall")
detail.info:SetPoint("TOPLEFT", 0, -THUMB_H - 26)
detail.info:SetWidth(DETAIL_W)
detail.story = Text(detail, "GameFontHighlightSmall")
detail.story:SetPoint("TOPLEFT", 0, -THUMB_H - 42)
detail.story:SetWidth(DETAIL_W)
if detail.story.SetMaxLines then detail.story:SetMaxLines(6) end
detail.news = Text(detail, "GameFontNormalSmall")
detail.news:SetPoint("TOPLEFT", 0, -THUMB_H - 128)
detail.news:SetWidth(DETAIL_W)
if detail.news.SetMaxLines then detail.news:SetMaxLines(2) end
local label = Text(detail, "GameFontNormalSmall")
label:SetPoint("BOTTOMLEFT", 0, 34)
label:SetText("Normal")
detail.normalStars = StarRow(detail, 44, -(384 - 48))
label = Text(detail, "GameFontNormalSmall")
label:SetPoint("BOTTOMLEFT", 100, 34)
label:SetText("Heroic")
detail.heroicStars = StarRow(detail, 140, -(384 - 48))

local function DifficultyTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Heroic")
    local h = Meta.DIFFICULTY.heroic
    GameTooltip:AddLine(string.format("Creeps have %d%% health and you start with %d%% gold, for %.1fx Warmarks. "
        .. "Opens with 3 stars on Normal.", h.hpPct, h.goldPct, h.rewardPct / 100), 1, 1, 1, true)
    GameTooltip:Show()
end

detail.heroic = Button(detail, "Heroic", 80, function() Choose(selectedLevel, "heroic") end)
detail.heroic:SetPoint("BOTTOMRIGHT", 0, 0)
detail.heroic:SetScript("OnEnter", DifficultyTip)
detail.heroic:SetScript("OnLeave", function() GameTooltip:Hide() end)
detail.normal = Button(detail, "Play", 80, function() Choose(selectedLevel, "normal") end)
detail.normal:SetPoint("RIGHT", detail.heroic, "LEFT", -4, 0)

local function BossName(level)
    local boss = Levels.Boss(level)
    return boss and (", boss: " .. Content.creeps[boss].name) or ""
end

local function RefreshCampaign(profile)
    for i, camp in ipairs(Levels.campaigns) do
        local b = banners[i]
        local open = Meta.CampaignUnlocked(profile, camp)
        local normal, heroic, most = Meta.CampaignStars(profile, camp)
        b.crest:SetTexture(Board.Icon(camp, "crest", "crestAlt"))
        b.crest:SetDesaturated(not open)
        b.name:SetText(open and (Hex(camp.color) .. camp.name .. "|r") or (GREY .. camp.name .. "|r"))
        b.title:SetText(open and camp.title or (GREY .. camp.title .. "|r"))
        b.sub:SetText(open and string.format("%s %d/%d    Heroic %d/%d", Inline(STAR), normal, most, heroic, most)
            or (GREY .. string.format("%s %d / %d to open", Inline(STAR), Meta.TotalStars(profile),
                camp.unlock and camp.unlock.stars or 0) .. "|r"))
        b.sel:SetShown(i == selectedCamp)
        b.bg:SetColorTexture(1, 1, 1, i == selectedCamp and 0.12 or 0.05)
    end
    local camp = Levels.campaigns[selectedCamp]
    local level = selectedLevel and Levels.byId[selectedLevel]
    if not (level and level.campaign == camp.id) then
        level = Meta.NextLevel(profile, camp)
        selectedLevel = level.id
    end
    for i, l in ipairs(camp.levels) do
        local r = chapters[i] or NewChapter(i)
        r.level = l
        local open = Meta.LevelUnlocked(profile, l)
        local rec = profile.levels[l.id]
        r.num:SetText(open and (GOLD .. i .. "|r") or (GREY .. i .. "|r"))
        r.name:SetText(open and l.name or (GREY .. l.name .. "|r"))
        SetStars(r.stars, rec and rec.stars)
        local sub = ""
        if not open then sub = GREY .. "locked|r"
        elseif rec and (rec.heroicStars or 0) > 0 then sub = string.format("|cffff8040Heroic %d/3|r", rec.heroicStars)
        elseif not (rec and rec.wins > 0) then sub = GREEN .. "new|r" end
        r.sub:SetText(sub)
        r.sel:SetShown(l.id == selectedLevel)
        r.bg:SetColorTexture(1, 1, 1, l.id == selectedLevel and 0.12 or 0.05)
        r:Show()
    end
    for i = #camp.levels + 1, #chapters do chapters[i]:Hide() end
    if detail.paintedFor ~= level.id then
        Board.Paint(detail.paint, level, THUMB_W)
        detail.paintedFor = level.id
    end
    local open = Meta.LevelUnlocked(profile, level)
    local rec = profile.levels[level.id]
    detail.name:SetText(open and level.name or (GREY .. level.name .. "|r"))
    detail.info:SetText(string.format("%s  -  %s, %d waves%s", level.zone, LENGTH[level.length] or "",
        #level.waves, BossName(level)))
    local b = level.story and level.story.briefing
    local story = b and string.format("%s%s:|r %s", GOLD, b[1], b[2]) or (level.blurb or level.draft or "")
    detail.story:SetText(open and story or (ORANGE .. LockText(profile, level) .. "|r\n\n" .. (level.blurb or "")))
    local news = {}
    for _, kind in ipairs(Levels.NewTowers(level)) do
        news[#news + 1] = Inline(Board.Icon(Content.towers[kind]), 16) .. " " .. Content.towers[kind].name
    end
    if camp.hero.at == level.number then
        local T = Content.towers[camp.hero.kind]
        news[#news + 1] = Inline(Board.Icon(T), 16) .. " " .. T.name .. " (hero)"
    end
    detail.news:SetText(#news > 0 and (GREEN .. "Joins you here:|r " .. table.concat(news, ",  ")) or "")
    detail.thumb:SetAlpha(open and 1 or 0.35)
    SetStars(detail.normalStars, rec and rec.stars)
    SetStars(detail.heroicStars, rec and rec.heroicStars)
    detail.normal:SetEnabled(open)
    detail.heroic:SetEnabled(Meta.DifficultyUnlocked(profile, level.id, "heroic"))
end

------------------------------------------------------------------------------------------------------------------------
-- Armory: a tab per campaign, a column per tower.
local armory = pages.armory
local campTabs, columns = {}, {}
local armoryCamp = 1
local COL_W = 136

for i, camp in ipairs(Levels.campaigns) do
    local b = CreateFrame("Button", nil, armory)
    b:SetSize(170, 26)
    b:SetPoint("TOPLEFT", 10 + (i - 1) * 174, -4)
    b.bg = Background(b, 0.05)
    b.hl = Highlight(b)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(camp.color[1], camp.color[2], camp.color[3], 1)
    b.crest = b:CreateTexture(nil, "ARTWORK")
    b.crest:SetSize(20, 20)
    b.crest:SetPoint("LEFT", 4, 0)
    b.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = Text(b, "GameFontNormal")
    b.text:SetPoint("LEFT", b.crest, "RIGHT", 6, 0)
    b.text:SetText(camp.name)
    b:SetScript("OnClick", function()
        armoryCamp = i
        Menu.Refresh()
    end)
    campTabs[i] = b
end

for i = 1, 5 do
    local col = CreateFrame("Frame", nil, armory)
    col:SetSize(COL_W - 4, 304)
    col:SetPoint("TOPLEFT", 10 + (i - 1) * (COL_W + 2), -36)
    Background(col, 0.05)
    col.icon = col:CreateTexture(nil, "ARTWORK")
    col.icon:SetSize(36, 36)
    col.icon:SetPoint("TOPLEFT", 6, -6)
    col.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    col.name = Text(col, "GameFontNormal")
    col.name:SetPoint("TOPLEFT", 48, -6)
    col.name:SetWidth(COL_W - 54)
    col.tier = Text(col, "GameFontHighlightSmall")
    col.tier:SetPoint("TOPLEFT", 48, -30)
    col.tier:SetWidth(COL_W - 54)
    col.rows = {}
    for tier = 1, #Meta.ARMORY do
        local row = CreateFrame("Frame", nil, col)
        row:SetSize(COL_W - 14, 40)
        row:SetPoint("TOPLEFT", 6, -48 - (tier - 1) * 42)
        row.mark = Text(row, "GameFontNormalSmall")
        row.mark:SetPoint("TOPLEFT", 0, 0)
        row.text = Text(row, "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", 12, 0)
        row.text:SetWidth(COL_W - 28)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local kind = col.kind
            if not kind then return end
            local title, blurb = Meta.TierText(kind, tier)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Content.towers[kind].name .. ": research " .. tier)
            GameTooltip:AddLine(title, 1, 0.82, 0)
            if blurb ~= "" then GameTooltip:AddLine(blurb, 1, 1, 1, true) end
            GameTooltip:AddLine(Meta.ARMORY[tier].cost .. " Warmarks", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        col.rows[tier] = row
    end
    col.buy = Button(col, "Research", COL_W - 16, function() if col.kind then Buy("armory", col.kind) end end)
    col.buy:SetPoint("BOTTOM", 0, 8)
    columns[i] = col
end
local heroLine = Text(armory, "GameFontHighlightSmall")
heroLine:SetPoint("TOPLEFT", 14, -346)
heroLine:SetWidth(684)

local function RefreshArmory(profile)
    local camp = Levels.campaigns[armoryCamp]
    for i, b in ipairs(campTabs) do
        local c = Levels.campaigns[i]
        local on = i == armoryCamp
        b.crest:SetTexture(Board.Icon(c, "crest", "crestAlt"))
        b.bg:SetColorTexture(1, 1, 1, on and 0.14 or 0.04)
        b.line:SetShown(on)
        if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(1, 0.82, 0) end
    end
    for i, col in ipairs(columns) do
        local kind = camp.towers[i]
        col.kind = kind
        local T = Content.towers[kind]
        local tier = Meta.ArmoryTier(profile, kind)
        local unlocked = Meta.TowerUnlocked(profile, kind)
        col.icon:SetTexture(Board.Icon(T))
        col.icon:SetDesaturated(not unlocked)
        col.name:SetText(T.name)
        local joins = camp.levels[camp.joins[kind]]
        col.tier:SetText(unlocked and string.format("Research %d/%d", tier, #Meta.ARMORY)
            or (GREY .. "Joins at " .. (joins and joins.name or "?") .. "|r"))
        for t, row in ipairs(col.rows) do
            local color = t <= tier and GREEN or (t == tier + 1 and unlocked) and WHITE_TEXT or GREY
            row.mark:SetText(color .. t .. "|r")
            row.text:SetText(color .. (Meta.TierText(kind, t)) .. "|r")
        end
        local price, why = Meta.Price(profile, "armory", kind)
        col.buy:SetText(price and ("Research: " .. price) or (why == "max" and "Complete" or "Research"))
        col.buy:SetEnabled(price ~= nil and profile.warmarks >= price)
    end
    local H = Content.towers[camp.hero.kind]
    local at = camp.levels[camp.hero.at]
    heroLine:SetText(string.format("%sHero:|r %s, who joins at %s. %s %s%s:|r %s", GOLD, H.name, at.name, H.blurb,
        GOLD, H.ability.name, H.ability.blurb))
end

------------------------------------------------------------------------------------------------------------------------
-- Supplies
local supplies = pages.supplies
local supplyRows = {}
for i, s in ipairs(Meta.SUPPLIES) do
    local row = CreateFrame("Frame", nil, supplies)
    row:SetSize(688, 64)
    row:SetPoint("TOPLEFT", 10, -6 - (i - 1) * 70)
    Background(row, 0.05)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(ICON .. s.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = Text(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 64, -12)
    row.name:SetText(s.name)
    row.text = Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 64, -32)
    row.buy = Button(row, "Buy", 130, function() Buy("supply", s.key) end)
    row.buy:SetPoint("RIGHT", -12, 0)
    supplyRows[i] = row
end

local function RefreshSupplies(profile)
    for i, s in ipairs(Meta.SUPPLIES) do
        local row, have = supplyRows[i], profile.supplies[s.key] or 0
        local now = s.key == "gold" and string.format("+%d%% starting gold", have * s.step)
            or string.format("+%d lives", have * s.step)
        row.text:SetText(string.format("%s.  Bought %d of %d: now %s in every level.", s.text, have, #s.costs, now))
        local price, why = Meta.Price(profile, "supply", s.key)
        row.buy:SetText(price and ("Buy: " .. price) or (why == "max" and "Complete" or "Buy"))
        row.buy:SetEnabled(price ~= nil and profile.warmarks >= price)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Options
local options = pages.options
local optionRows = {}
local function OptionRow(i, title, blurb)
    local row = CreateFrame("Frame", nil, options)
    row:SetSize(688, 48)
    row:SetPoint("TOPLEFT", 10, -4 - (i - 1) * 54)
    Background(row, 0.05)
    row.title = Text(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 12, -8)
    row.title:SetText(title)
    row.blurb = Text(row, "GameFontHighlightSmall")
    row.blurb:SetPoint("TOPLEFT", 12, -26)
    row.blurb:SetWidth(470)
    row.blurb:SetText(blurb)
    optionRows[i] = row
    return row
end
local function Toggle(name) Game().SetOption(name, not Game().db.settings[name]) end
local function Switch(i, name, title, blurb)
    local row = OptionRow(i, title, blurb)
    row.button = Button(row, "On", 90, function() Toggle(name) end)
    row.button:SetPoint("RIGHT", -12, 0)
    row.setting = name
    return row
end

local switches = {
    Switch(1, "sound", "Sound", "Coins, war drums and fanfares, from the game's own sounds."),
    Switch(2, "autoWaves", "Auto waves", "The next wave starts a few seconds after the board clears. Good on flights."),
    Switch(3, "story", "Story", "Briefings before levels you haven't won yet, and battle cries during them."),
    Switch(4, "effects", "Full effects", "Glows, sparks, smoke and a shaking board for the big blasts. Off keeps "
        .. "just the essentials (bolts, flashes and numbers)."),
}
local sizeRow = OptionRow(5, "Window size", "Make the whole window smaller or bigger (60% to 160%).")
sizeRow.bigger = Button(sizeRow, "Bigger", 70, function() Game().SetOption("scale", Game().db.settings.scale + 0.1) end)
sizeRow.bigger:SetPoint("RIGHT", -12, 0)
sizeRow.value = Text(sizeRow, "GameFontHighlight", "CENTER")
sizeRow.value:SetWidth(56)
sizeRow.value:SetPoint("RIGHT", sizeRow.bigger, "LEFT", -2, 0)
sizeRow.smaller = Button(sizeRow, "Smaller", 70, function()
    Game().SetOption("scale", Game().db.settings.scale - 0.1)
end)
sizeRow.smaller:SetPoint("RIGHT", sizeRow.value, "LEFT", -2, 0)
local saveRow = OptionRow(6, "Saving", "WoW writes saved data to disk only at a /reload or logout, so a crash loses "
    .. "what came since. Save now reloads the interface; a level in progress waits, paused.")
saveRow.button = Button(saveRow, "Save now", 90, function() Game().Save() end)
saveRow.button:SetPoint("RIGHT", -12, 0)

local function RefreshOptions(settings)
    for _, row in ipairs(switches) do row.button:SetText(settings[row.setting] and "On" or "Off") end
    sizeRow.value:SetText(string.format("%d%%", math.floor(settings.scale * 100 + 0.5)))
end

------------------------------------------------------------------------------------------------------------------------

-- The campaign of the level last played, else the one matching the player's faction, else the first.
local function DefaultCampaign()
    local G = Game()
    local last = G.lastLevel and Levels.byId[G.lastLevel]
    if last then return Levels.Campaign(last).index, last.id end
    local faction
    if UnitFactionGroup then
        local ok, f = pcall(UnitFactionGroup, "player")
        faction = ok and f or nil
    end
    for i, camp in ipairs(Levels.campaigns) do
        if camp.faction == faction and not camp.unlock then return i end
    end
    return 1
end

function Menu.Page(key)
    current = pages[key] and key or "campaign"
    pendingStart = nil
    for k, page in pairs(pages) do page:SetShown(k == current) end
    Menu.Refresh()
end

-- Points the Campaign page at a level, or at the one after it once it's won and the next is open.
function Menu.Select(levelId)
    local level = Levels.byId[levelId]
    if not level then return end
    local profile = Game().db.profile
    local nextLevel = Levels.Next(level)
    if Meta.Cleared(profile, level.id) and nextLevel and Meta.LevelUnlocked(profile, nextLevel) then
        level = nextLevel
    end
    selectedCamp, selectedLevel = Levels.Campaign(level).index, level.id
    armoryCamp = selectedCamp -- the Armory opens on the campaign you're playing
end

function Menu.Refresh()
    local G = Game()
    local profile = G.db.profile
    if not selectedCamp then
        selectedCamp, selectedLevel = DefaultCampaign()
        armoryCamp = selectedCamp
    end
    wallet:SetText(string.format("%s %d Warmarks      %s %d", Inline(WARMARK), profile.warmarks, Inline(STAR),
        Meta.TotalStars(profile)))
    for key, b in pairs(tabs) do
        local on = key == current
        b.bg:SetColorTexture(1, 0.82, 0, on and 0.16 or 0.04)
        b.line:SetShown(on)
        if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(1, 0.82, 0) end
    end
    if current == "campaign" then RefreshCampaign(profile)
    elseif current == "armory" then RefreshArmory(profile)
    elseif current == "supplies" then RefreshSupplies(profile)
    else RefreshOptions(G.db.settings) end
    local inRun = G.state ~= nil and not G.state.over
    backButton:SetShown(inRun)
    abandonButton:SetShown(pendingStart ~= nil)
    saveButton:SetShown(G.unsaved == true)
    if pendingStart then
        note:SetText(ORANGE .. "A level is in progress. Abandon it to start another? It earns nothing.|r")
    elseif said and GetTime() < saidUntil then
        note:SetText(said)
    else
        note:SetText((G.unsaved and (ORANGE .. "Unsaved progress. |r") or "")
            .. (profile.sandbox and (GREEN .. "Sandbox: everything is open (/td sandbox to close). |r") or "")
            .. TIP[current])
    end
end

-- Opens (on a page) or closes the menu. Opening it pauses a level in progress.
function Ui.ShowMenu(on, page)
    if not on then
        menu:Hide()
        return
    end
    pendingStart = nil
    local G = Game()
    if Ui.BriefingShown() then Ui.CloseBriefing() end -- its 3D speaker would draw over the menu
    if G.state and not G.state.over then G.SetPaused(true) end
    if G.lastLevel then Menu.Select(G.lastLevel) end
    menu:Show()
    Menu.Page(page or current)
end

function Ui.RefreshMenu() if menu:IsShown() then Menu.Refresh() end end
function Ui.MenuShown() return menu:IsShown() end

Menu.tabs, Menu.pages, Menu.banners, Menu.chapters, Menu.detail = tabs, pages, banners, chapters, detail
Menu.columns, Menu.campTabs, Menu.supplyRows, Menu.optionRows = columns, campTabs, supplyRows, optionRows
Menu.abandonButton = abandonButton

return Menu
