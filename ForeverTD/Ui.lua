-- Ui.lua - the game window around the board: title bar, HUD, the campaign's tower palette and its hero, the info
-- panel, the boss portrait, the briefing before a level, battle cries during it, and the paused and end-of-level
-- screens (the menu is Menu.lua). Presentation only: it reads ns.Game (Shell.lua) and the engine state, and sends
-- the player's actions back through Game.
local _, ns = ...
local Engine, Content, Levels, Meta, Board = ns.Engine, ns.Content, ns.Levels, ns.Meta, ns.Board
local Ui = {}
ns.Ui = Ui

local W, H = 720, 500
local BOARD_X, BOARD_Y = 10, -56
local SIDE_X, SIDE_W = 596, 114
local ICON = "Interface\\Icons\\"
local COIN, HEART = ICON .. "INV_Misc_Coin_01", ICON .. "Spell_Holy_SealOfSacrifice"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SLOTS = 5 -- towers per campaign

-- Every sentence the player reads, in one place (for a translation later).
local L = {
    gold = "Not enough gold.", road = "That's the road.", blocked = "You can't build there.",
    occupied = "There's a tower there.", locked = "That tower isn't unlocked yet.", max = "Already at the top rank.",
    nowaves = "No more waves.", over = "The level is over.", bounds = "Off the board.",
    hero = "Your hero is already on the field.", nohero = "Place your hero first.",
    cooldown = "Not ready yet.",
    paused = "Paused\n\n|cffffffffClick to resume|r",
    unsaved = "Progress is kept in memory until you log out or press Save.",
    research = "Open that specialization in the Armory first (Menu, Armory).",
    warmarks = "Not enough Warmarks.",
    toBattle = "To battle!",
}

local function Text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Game() return ns.Game end
local PALETTE_STEP = 46 -- one tower button per row in the side column
local function Stars(n) return string.format("|cffffd200%d/3|r", n or 0) end
local function Inline(path, size) return "|T" .. path .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|t" end
local function Hex(c)
    local function B(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", B(c[1]), B(c[2]), B(c[3]))
end

-- The window: a named frame (ESC closes named frames listed in UISpecialFrames), dragged by its title bar, hidden
-- by default. OnUpdate (Shell.lua) only runs while it's shown, so closing it pauses the game.
local window = CreateFrame("Frame", "ForeverTDFrame", UIParent, "BackdropTemplate")
Ui.window = window
window:SetSize(W, H)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH")
window:SetMovable(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
window:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
window:Hide()
tinsert(UISpecialFrames, "ForeverTDFrame")

local titleBar = CreateFrame("Frame", nil, window)
titleBar:SetPoint("TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", -30, -4)
titleBar:SetHeight(22)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
titleBar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
local title = Text(titleBar, "GameFontNormal")
title:SetPoint("LEFT", 6, 0)
local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 0, 0)

-- HUD row
local goldText = Text(window, "GameFontHighlight")
goldText:SetPoint("TOPLEFT", 14, -34)
local livesText = Text(window, "GameFontHighlight")
livesText:SetPoint("TOPLEFT", 100, -34)
local waveText = Text(window, "GameFontHighlight")
waveText:SetPoint("TOPLEFT", 190, -34)

local menuButton = Button(window, "Menu", 64, function() Ui.ShowMenu(true) end)
menuButton:SetPoint("TOPRIGHT", -10, -28)
local pauseButton = Button(window, "Pause", 64, function() Game().SetPaused(not Game().paused) end)
pauseButton:SetPoint("RIGHT", menuButton, "LEFT", -4, 0)
local speedButton = Button(window, "1x", 40, function() Game().ToggleSpeed() end)
local autoButton = Button(window, "Auto: off", 72, function()
    Game().SetOption("autoWaves", not Game().db.settings.autoWaves)
end)
speedButton:SetPoint("RIGHT", pauseButton, "LEFT", -4, 0)
local waveButton = Button(window, "Start wave", 120, function() Game().Act({ kind = "wave" }) end)
autoButton:SetPoint("RIGHT", speedButton, "LEFT", -4, 0)
waveButton:SetPoint("RIGHT", autoButton, "LEFT", -4, 0)

local boardFrame = Board.Create(window)
Board.Place(window, BOARD_X, BOARD_Y)

-- Short messages ("Not enough gold.") across the top of the board, fading after a moment.
local banner = CreateFrame("Frame", nil, window)
banner:SetPoint("TOP", boardFrame, "TOP", 0, -6)
banner:SetSize(500, 24)
banner:SetFrameLevel(boardFrame:GetFrameLevel() + 15)
local message = Text(banner, "GameFontNormalLarge", "CENTER")
message:SetAllPoints()
local messageUntil = 0

-- Battle cries: who speaks and what, in a strip along the bottom of the board, for a few seconds.
local bark = CreateFrame("Frame", nil, window)
bark:SetPoint("BOTTOMLEFT", boardFrame, "BOTTOMLEFT", 8, 8)
bark:SetPoint("BOTTOMRIGHT", boardFrame, "BOTTOMRIGHT", -8, 8)
bark:SetHeight(40)
bark:SetFrameLevel(boardFrame:GetFrameLevel() + 14)
bark.bg = bark:CreateTexture(nil, "BACKGROUND")
bark.bg:SetAllPoints()
bark.bg:SetColorTexture(0, 0, 0, 0.62)
bark.icon = bark:CreateTexture(nil, "ARTWORK")
bark.icon:SetSize(30, 30)
bark.icon:SetPoint("LEFT", 6, 0)
bark.mask = bark:CreateMaskTexture()
bark.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
bark.mask:SetAllPoints(bark.icon)
bark.icon:AddMaskTexture(bark.mask)
bark.text = Text(bark, "GameFontHighlight")
bark.text:SetPoint("LEFT", bark.icon, "RIGHT", 8, 0)
bark.text:SetPoint("RIGHT", -8, 0)
bark:Hide()
local barkUntil = 0

------------------------------------------------------------------------------------------------------------------------
-- Tower palette: the run's towers in their campaign's order. Under the board on the right: the hero.

local palette = {}
for i = 1, SLOTS do
    local b = CreateFrame("Button", nil, window)
    b:SetSize(SIDE_W, PALETTE_STEP - 4)
    b:SetPoint("TOPLEFT", SIDE_X, BOARD_Y - (i - 1) * PALETTE_STEP)
    b.slot = i
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.06)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(34, 34)
    b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = Text(b, "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -2)
    b.name:SetWidth(SIDE_W - 46)
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b.cost = Text(b, "GameFontHighlightSmall")
    b.cost:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 2)
    b:SetScript("OnClick", function(self) if self.kind then Ui.Pick(self.kind) end end)
    b:SetScript("OnEnter", function(self)
        local T = self.kind and Content.towers[self.kind]
        if not T then return end
        local s = Game() and Game().state
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(T.name)
        GameTooltip:AddLine(Content.ROLE_NAME[T.role] .. " tower", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(T.blurb, 1, 1, 1, true)
        if s then GameTooltip:AddLine(Ui.StatsLine(s, self.kind, 1), 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    palette[i] = b
end

-- The hero: a button to bring them to the field (free), then to use their ability.
local heroButton = CreateFrame("Button", nil, window)
heroButton:SetSize(SIDE_W, 44)
heroButton:SetPoint("TOPLEFT", SIDE_X, BOARD_Y - 364)
heroButton.bg = heroButton:CreateTexture(nil, "BACKGROUND")
heroButton.bg:SetAllPoints()
heroButton.bg:SetColorTexture(1, 0.75, 0.15, 0.1)
heroButton.hl = heroButton:CreateTexture(nil, "HIGHLIGHT")
heroButton.hl:SetAllPoints()
heroButton.hl:SetColorTexture(1, 1, 1, 0.08)
heroButton.icon = heroButton:CreateTexture(nil, "ARTWORK")
heroButton.icon:SetSize(36, 36)
heroButton.icon:SetPoint("LEFT", 4, 0)
heroButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
heroButton.shade = heroButton:CreateTexture(nil, "ARTWORK", nil, 2) -- the cooldown, draining from the top
heroButton.shade:SetPoint("BOTTOMLEFT", heroButton.icon, "BOTTOMLEFT")
heroButton.shade:SetPoint("BOTTOMRIGHT", heroButton.icon, "BOTTOMRIGHT")
heroButton.shade:SetColorTexture(0, 0, 0, 0.7)
heroButton.shade:SetHeight(1)
heroButton.name = Text(heroButton, "GameFontNormalSmall")
heroButton.name:SetPoint("TOPLEFT", heroButton.icon, "TOPRIGHT", 6, -1)
heroButton.name:SetWidth(SIDE_W - 48)
if heroButton.name.SetWordWrap then heroButton.name:SetWordWrap(false) end
heroButton.state = Text(heroButton, "GameFontHighlightSmall")
heroButton.state:SetPoint("BOTTOMLEFT", heroButton.icon, "BOTTOMRIGHT", 6, 1)
heroButton.state:SetWidth(SIDE_W - 48)
heroButton:SetScript("OnClick", function() Ui.HeroAction() end)
heroButton:SetScript("OnEnter", function(self)
    local s = Game() and Game().state
    local kind = s and s.loadout.hero
    if not kind then return end
    local T = Content.towers[kind]
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(T.name)
    GameTooltip:AddLine("Hero: free, one per level, can't be sold. This button places them, then uses their "
        .. "ability.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(T.blurb, 1, 1, 1, true)
    GameTooltip:AddLine(Ui.StatsLine(s, kind, 1), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(string.format("%s: %s Every %s.", T.ability.name, T.ability.blurb,
        Ui.Duration(T.ability.cd)), 1, 0.82, 0, true)
    GameTooltip:Show()
end)
heroButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
heroButton:Hide()

local nextTitle = Text(window, "GameFontNormalSmall")
nextTitle:SetPoint("TOPLEFT", SIDE_X, BOARD_Y - SLOTS * PALETTE_STEP - 4)
local nextText = Text(window, "GameFontHighlightSmall")
nextText:SetPoint("TOPLEFT", nextTitle, "BOTTOMLEFT", 0, -4)
nextText:SetWidth(SIDE_W)

-- Boss panel, in the side column under the palette, while a boss lives.
local bossPanel = CreateFrame("Frame", nil, window)
bossPanel:SetPoint("TOPLEFT", SIDE_X, BOARD_Y - SLOTS * PALETTE_STEP - 4)
bossPanel:SetSize(SIDE_W, 126)
bossPanel:Hide()
local bossName = Text(bossPanel, "GameFontNormalSmall", "CENTER")
bossName:SetPoint("TOP", 0, 0)
bossName:SetWidth(SIDE_W)
local bossView = CreateFrame("Frame", nil, bossPanel) -- where the 3D portrait sits
bossView:SetSize(96, 96)
bossView:SetPoint("TOP", 0, -14)
local bossIcon = bossView:CreateTexture(nil, "ARTWORK") -- shown until (unless) the model loads
bossIcon:SetSize(56, 56)
bossIcon:SetPoint("CENTER")
local bossMask = bossView:CreateMaskTexture()
bossMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
bossMask:SetAllPoints(bossIcon)
bossIcon:AddMaskTexture(bossMask)
local bossBarBg = bossPanel:CreateTexture(nil, "ARTWORK")
bossBarBg:SetColorTexture(0, 0, 0, 0.9)
bossBarBg:SetSize(SIDE_W, 8)
bossBarBg:SetPoint("TOP", bossView, "BOTTOM", 0, -2)
local bossBar = bossPanel:CreateTexture(nil, "OVERLAY")
bossBar:SetColorTexture(1, 0.6, 0.2, 1)
bossBar:SetPoint("LEFT", bossBarBg, "LEFT", 1, 0)
bossBar:SetSize(SIDE_W - 2, 6)

-- Info panel along the bottom
local infoTitle = Text(window, "GameFontNormal")
infoTitle:SetPoint("TOPLEFT", BOARD_X + 4, BOARD_Y - 366)
local infoText = Text(window, "GameFontHighlightSmall")
infoText:SetPoint("TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -4)
infoText:SetWidth(330)
local sellButton = Button(window, "Sell", 96, function()
    local id = Board.selected
    Board.selected = nil
    Game().Act({ kind = "sell", id = id })
end)
sellButton:SetPoint("TOPRIGHT", window, "TOPLEFT", BOARD_X + 576, BOARD_Y - 368)
local upgradeButton = Button(window, "Upgrade", 110, function()
    Game().Act({ kind = "upgrade", id = Board.selected })
end)
upgradeButton:SetPoint("RIGHT", sellButton, "LEFT", -4, 0)

-- At rank 3 a tower can take one of its two specializations instead of a plain upgrade (if researched).
local specButtons = {}
for i = 1, 2 do
    local b = Button(window, "Spec", 116, function(self)
        Game().Act({ kind = "upgrade", id = Board.selected, spec = self.spec })
    end)
    b.spec = i
    b:SetScript("OnEnter", function(self)
        local s = Game().state
        local t
        for _, tower in ipairs(s and s.towers or {}) do if tower.id == Board.selected then t = tower end end
        if not t then return end
        local S, open = Engine.Spec(s, t.kind, self.spec)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(S.name)
        GameTooltip:AddLine(S.blurb, 1, 1, 1, true)
        GameTooltip:AddLine(Ui.StatsLine(s, t.kind, 3 + self.spec), 0.8, 0.8, 0.8, true)
        if not open then
            GameTooltip:AddLine("Research Armory tier " .. (self.spec == 1 and 3 or 5) .. " to open it.", 1, 0.5, 0.25,
                true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    specButtons[i] = b
end
specButtons[2]:SetPoint("RIGHT", sellButton, "LEFT", -4, 0)
specButtons[1]:SetPoint("RIGHT", specButtons[2], "LEFT", -4, 0)
local saveNote = Text(window, "GameFontDisableSmall", "RIGHT")
saveNote:SetPoint("BOTTOMRIGHT", -12, 8)

------------------------------------------------------------------------------------------------------------------------
-- Overlays above the board

local function Overlay(parent, alpha)
    local f = CreateFrame("Button", nil, parent)
    f:EnableMouse(true) -- clicks stop here instead of reaching the board
    f:SetFrameLevel(boardFrame:GetFrameLevel() + 20)
    f.dim = f:CreateTexture(nil, "BACKGROUND")
    f.dim:SetAllPoints()
    f.dim:SetColorTexture(0, 0, 0, alpha)
    f:Hide()
    return f
end

local pausedOverlay = Overlay(window, 0.55)
pausedOverlay:SetAllPoints(boardFrame)
pausedOverlay.text = Text(pausedOverlay, "GameFontNormalHuge", "CENTER")
pausedOverlay.text:SetPoint("CENTER")
pausedOverlay.text:SetText(L.paused)
pausedOverlay:SetScript("OnClick", function() Game().SetPaused(false) end)

local endOverlay = Overlay(window, 0.8)
endOverlay:SetAllPoints(boardFrame)
endOverlay.title = Text(endOverlay, "GameFontNormalHuge", "CENTER")
endOverlay.title:SetPoint("TOP", 0, -36)
endOverlay.story = Text(endOverlay, "GameFontHighlight", "CENTER")
endOverlay.story:SetPoint("TOP", endOverlay.title, "BOTTOM", 0, -14)
endOverlay.story:SetWidth(500)
endOverlay.lines = Text(endOverlay, "GameFontHighlight", "CENTER")
endOverlay.lines:SetPoint("TOP", endOverlay.story, "BOTTOM", 0, -16)
endOverlay.lines:SetWidth(520)
local retryButton = Button(endOverlay, "Retry", 90, function()
    local G = Game()
    G.Start(G.lastLevel, G.lastDifficulty)
end)
local nextButton = Button(endOverlay, "Next level", 90, function()
    local G = Game()
    local level = Levels.byId[G.lastLevel]
    local nextLevel = level and Levels.Next(level)
    if nextLevel then G.Start(nextLevel.id, "normal") end
end)
local levelsButton = Button(endOverlay, "Levels", 90, function() Ui.ShowMenu(true, "campaign") end)
local armoryButton = Button(endOverlay, "Armory", 90, function() Ui.ShowMenu(true, "armory") end)
local saveButton = Button(endOverlay, "Save (reload)", 110, function() Game().Save() end)
retryButton:SetPoint("BOTTOMLEFT", endOverlay, "BOTTOMLEFT", 41, 30)
nextButton:SetPoint("LEFT", retryButton, "RIGHT", 6, 0)
levelsButton:SetPoint("LEFT", nextButton, "RIGHT", 6, 0)
armoryButton:SetPoint("LEFT", levelsButton, "RIGHT", 6, 0)
saveButton:SetPoint("LEFT", armoryButton, "RIGHT", 6, 0)

-- The briefing before a level: who speaks (a 3D portrait when the client has the model, else their icon), what
-- they say, and what's new in this level.
local briefing = Overlay(window, 0.86)
briefing:SetAllPoints(boardFrame)
briefing.view = CreateFrame("Frame", nil, briefing) -- where the speaker's 3D portrait sits
briefing.view:SetSize(130, 150)
briefing.view:SetPoint("TOPLEFT", 26, -40)
briefing.icon = briefing.view:CreateTexture(nil, "ARTWORK")
briefing.icon:SetSize(84, 84)
briefing.icon:SetPoint("CENTER")
briefing.mask = briefing.view:CreateMaskTexture()
briefing.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
briefing.mask:SetAllPoints(briefing.icon)
briefing.icon:AddMaskTexture(briefing.mask)
briefing.speaker = Text(briefing, "GameFontNormal", "CENTER")
briefing.speaker:SetPoint("TOP", briefing.view, "BOTTOM", 0, -4)
briefing.speaker:SetWidth(150)
briefing.place = Text(briefing, "GameFontDisableSmall")
briefing.place:SetPoint("TOPLEFT", 178, -34)
briefing.title = Text(briefing, "GameFontNormalHuge")
briefing.title:SetPoint("TOPLEFT", briefing.place, "BOTTOMLEFT", 0, -4)
briefing.text = Text(briefing, "GameFontHighlight")
briefing.text:SetPoint("TOPLEFT", briefing.title, "BOTTOMLEFT", 0, -12)
briefing.text:SetWidth(370)
briefing.news = Text(briefing, "GameFontNormalSmall")
briefing.news:SetPoint("TOPLEFT", briefing.text, "BOTTOMLEFT", 0, -14)
briefing.news:SetWidth(370)
briefing.go = Button(briefing, L.toBattle, 130, function() Ui.CloseBriefing() end)
briefing.go:SetPoint("BOTTOMRIGHT", -24, 22)
briefing:SetScript("OnClick", function() end)

------------------------------------------------------------------------------------------------------------------------
-- 3D portraits (the boss, and whoever speaks in a briefing): at most these two live models. Client rules (CLAUDE.md,
-- from two crashes): clear a model only while its frame is shown, and never hide a frame that holds one. So each
-- model frame belongs to UIParent (closing the window doesn't hide it), is never hidden, fades to alpha 0 when
-- unused, and is cleared before that, while still shown. SetCreature often shows nothing the first time, so it asks
-- again until OnModelLoaded fires; until then the round icon under it shows.
local ASK_AT = { 0.1, 0.5, 1.5 }

local function SafeModel(anchorFrame, strata, facing, onLoaded)
    local m = { anchor = anchorFrame }
    local function Clear(p) -- only ever called while p is on screen
        pcall(p.ClearModel, p)
        p:SetAlpha(0)
        p.npc, p.loaded, p.releaseLater = nil, false, false
        if onLoaded then onLoaded(false) end
    end
    function m.Show(npc)
        local p = m.frame
        if not p then
            p = CreateFrame("PlayerModel", nil, UIParent)
            p:SetFrameStrata(strata)
            p:SetAllPoints(anchorFrame)
            p:SetAlpha(0)
            p:SetScript("OnModelLoaded", function(self)
                if not self.npc then return end -- a late load for a model already let go
                self.loaded = true
                pcall(self.SetFacing, self, facing)
                if onLoaded then onLoaded(true) end
            end)
            p:SetScript("OnShow", function(self) -- back on screen: finish a release that had to wait
                if self.releaseLater and self:IsVisible() then Clear(self) end
            end)
            m.frame = p
        end
        if p.npc == npc and not p.releaseLater then return end
        if p.npc then
            if not p:IsVisible() then return end -- not now: never change a model that isn't on screen
            Clear(p)
        end
        p.npc, p.loaded, p.releaseLater = npc, false, false
        if onLoaded then onLoaded(false) end
        p:SetAlpha(1)
        pcall(p.SetCreature, p, npc)
        for _, delay in ipairs(ASK_AT) do
            C_Timer.After(delay, function()
                if p.npc == npc and not p.loaded and p:IsVisible() then pcall(p.SetCreature, p, npc) end
            end)
        end
    end
    function m.Release()
        local p = m.frame
        if not (p and p.npc) then return end
        if p:IsVisible() then Clear(p) return end
        -- Not on screen (UIParent hidden, e.g. Alt+Z): fade it now, and clear it the moment it's visible again.
        p:SetAlpha(0)
        p.releaseLater = true
    end
    return m
end

local bossModel = SafeModel(bossView, "DIALOG", 0.4, function(loaded) bossIcon:SetShown(not loaded) end)
local speakerModel = SafeModel(briefing.view, "DIALOG", 0.3, function(loaded) briefing.icon:SetShown(not loaded) end)
Ui.models = { boss = bossModel, speaker = speakerModel }

------------------------------------------------------------------------------------------------------------------------

-- Hovering a creep token shows what it is.
local tipCreep, tipHp
local function CreepTooltip(blocked)
    local c = not blocked and not Board.placing and Board.HoverCreep() or nil
    if not c then
        if tipCreep then
            tipCreep = nil
            if GameTooltip:GetOwner() == boardFrame then GameTooltip:Hide() end
        end
        return
    end
    if c.id == tipCreep and c.hp == tipHp then return end
    tipCreep, tipHp = c.id, c.hp
    local C = Content.creeps[c.kind]
    GameTooltip:SetOwner(boardFrame, "ANCHOR_CURSOR")
    GameTooltip:SetText(C.name)
    GameTooltip:AddLine(string.format("Health %d / %d", c.hp, c.maxHp), 1, 1, 1)
    local tags = Content.Tags(c.kind)
    if tags ~= "" then GameTooltip:AddLine(tags, 0.7, 0.7, 0.7) end
    if C.note then GameTooltip:AddLine(C.note, 0.9, 0.82, 0.5, true) end
    GameTooltip:Show()
end

-- Client sounds by SOUNDKIT name, at the sound-effects volume. A name this client lacks is skipped, and the noisy
-- ones are spaced out.
local SOUND_FOR = { placed = "LOOT_WINDOW_COIN_SOUND", sold = "LOOT_WINDOW_COIN_SOUND",
    upgraded = "IG_ABILITY_PAGE_TURN", waveStart = "READY_CHECK", leaked = "RAID_WARNING",
    ability = "RAID_WARNING" }
local SOUND_GAP = { leaked = 3, waveStart = 1 }
local soundAt = {}

function Ui.Sound(name, kind)
    local G = Game()
    if not (G and G.db and G.db.settings.sound) then return end
    local id = SOUNDKIT and SOUNDKIT[name]
    if not id then return end
    if kind and SOUND_GAP[kind] then
        local now = GetTime()
        if now < (soundAt[kind] or -99) + SOUND_GAP[kind] then return end
        soundAt[kind] = now
    end
    pcall(PlaySound, id, "SFX")
end

-- No keys (Bruce, 2026-10-23: keybinds "will likely interfere with people's gameplay if they are multitasking"):
-- the game is played with the mouse, and no frame of it listens to the keyboard, so every key stays the player's.
-- Esc still closes the window, as it does every WoW window (UISpecialFrames, above).

window:HookScript("OnHide", function()
    tipCreep = nil
    bossModel.Release()
    speakerModel.Release()
    Board.placing = nil
    GameTooltip:Hide()
end)

-- Times as a player sees them: real seconds at normal speed (1x plays Engine.PACE game seconds a real second).
local SECOND = Engine.HZ * Engine.PACE
local function Secs(ticks)
    local s = ticks / SECOND
    return string.format(s < 1 and "%.2f" or "%.1f", s)
end
function Ui.Duration(ticks) -- "3 minutes", "45 seconds"
    local s = ticks / SECOND
    if s >= 60 then return string.format("%g minute%s", s / 60, s == 60 and "" or "s") end
    return string.format("%g seconds", s)
end

function Ui.StatsLine(state, kind, rank)
    local S = Engine.Stats(state, kind, rank)
    local parts = { string.format("Damage %d (%s)", S.dmg, S.damage), string.format("range %.1f", S.range / 1000),
        string.format("every %s s", Secs(S.cd)) }
    local function Add(fmt, ...) parts[#parts + 1] = string.format(fmt, ...) end
    if S.multi then Add("%d targets", S.multi) end
    if S.crit then Add("%d%% crits", S.crit.pct) end
    if S.slow then Add("slows %d%% for %s s", S.slow, Secs(S.slowTicks)) end
    if S.stun then Add("stuns %s s", Secs(S.stun)) end
    if S.splash then Add("splash %.1f", S.splash / 1000) end
    if S.pulse then Add("hits everything near it") end
    if S.chain then Add("jumps %d times", S.chain) end
    if S.dot then
        Add("%d more damage over %s s%s", S.dot.dmg * S.dot.seconds, Secs(S.dot.seconds * Engine.HZ),
            S.spread and ", spreads" or "")
    end
    if S.vuln then Add("curse: +%d%% damage taken", S.vuln.pct) end
    if S.bane then Add("corpses explode for %d", S.bane.dmg) end
    if S.holy then Add("+%d%% vs undead and demons", S.holy) end
    if S.airBonus then Add("+%d%% vs flyers", S.airBonus) end
    if S.misfire then Add("%d%% fizzle", S.misfire) end
    if S.bonusVsSlowed then Add("+%d%% vs slowed", S.bonusVsSlowed) end
    if S.haste then Add("towers near it fire %d%% faster", S.haste) end
    if S.might then Add("towers near it hit %d%% harder", S.might) end
    if S.reveal then Add("reveals stealth") end
    if S.regrow then Add("restores a life each wave (%d a level)", S.regrow) end
    Add(S.air and "hits air" or "ground only")
    return table.concat(parts, ", ")
end

function Ui.Message(text)
    message:SetText(text)
    messageUntil = GetTime() + 2.5
end

-- A battle cry along the bottom of the board: { speaker, text }.
function Ui.Bark(line)
    local G = Game()
    if not (line and G and G.db and G.db.settings.story) then return end
    local speaker = ns.Story.Speaker(line[1])
    bark.icon:SetTexture(Board.Icon(speaker))
    bark.text:SetText(string.format("|cffffd200%s:|r %s", line[1], line[2]))
    bark:Show()
    barkUntil = GetTime() + 6
end

function Ui.Pick(kind)
    local s = Game().state
    if not s or s.over then return end
    if not s._allowed[kind] then Ui.Message(L.locked); return end
    if Content.towers[kind].hero and s.heroId then Ui.Message(L.hero); return end
    Board.placing = Board.placing ~= kind and kind or nil
    Board.selected = nil
    Board.SyncTowers()
    Ui.Refresh()
end

-- The hero button: bring the hero to the field, or use the ability once they're there.
function Ui.HeroAction()
    local G = Game()
    local s = G.state
    if not s or s.over or not s.loadout.hero then return end
    if s.heroId then G.Act({ kind = "ability" }) else Ui.Pick(s.loadout.hero) end
end

Board.onClick = function(c, r, button)
    local G = Game()
    local s = G.state
    if not s or s.over then return end
    if button == "RightButton" then
        Board.placing, Board.selected = nil, nil
    else
        local tower = Engine.TowerAt(s, c, r)
        if tower then
            Board.placing = nil
            Board.selected = Board.selected ~= tower.id and tower.id or nil
        elseif Board.placing then
            local e = G.Act({ kind = "place", tower = Board.placing, c = c, r = r })
            local keep = IsShiftKeyDown and IsShiftKeyDown() and not Content.towers[Board.placing].hero
            if e and e[1].kind == "placed" and not keep then Board.placing = nil end
        else
            Board.selected = nil
        end
    end
    Board.SyncTowers()
    Ui.Refresh()
end

local previewState, previewWave -- what the side column's wave preview was written for

local function RefreshPreview(s)
    if previewState == s and previewWave == s.wave then return end
    previewState, previewWave = s, s.wave
    local level = s._level
    if s.wave >= #level.waves then
        nextTitle:SetText("All waves are out")
        nextText:SetText("")
        return
    end
    nextTitle:SetText(string.format("Next: wave %d of %d", s.wave + 1, #level.waves))
    local lines = {}
    local summary = Engine.WaveSummary(level, s.wave + 1)
    for _, item in ipairs(summary) do
        local C = Content.creeps[item.creep]
        local tags = #summary <= 3 and Content.Tags(item.creep) or "" -- a crowded wave shows names only
        tags = tags:match("^[^,]+,[^,]+") or tags                     -- and at most two tags each
        lines[#lines + 1] = string.format("|T%s:16:16|t %d %s%s", Board.Icon(C), item.count, C.name,
            tags ~= "" and ("\n|cff999999      " .. tags .. "|r") or "")
    end
    nextText:SetText(table.concat(lines, "\n"))
end

local function RefreshInfo(s)
    local selected
    for _, t in ipairs(s.towers) do if t.id == Board.selected then selected = t end end
    local T = selected and Content.towers[selected.kind]
    upgradeButton:SetShown(selected ~= nil and not T.hero)
    sellButton:SetShown(selected ~= nil and not T.hero)
    for _, b in ipairs(specButtons) do b:Hide() end
    infoText:SetWidth(330)
    if selected and T.hero then
        infoTitle:SetText(T.name .. ", your hero")
        infoText:SetWidth(560)
        infoText:SetText(Ui.StatsLine(s, selected.kind, 1) .. "\n|cffffd200" .. T.ability.name .. ":|r "
            .. T.ability.blurb)
    elseif selected then
        local S = Engine.Stats(s, selected.kind, selected.rank)
        infoTitle:SetText(S.spec and string.format("%s: %s", T.name, S.name)
            or string.format("%s, rank %d of 3", T.name, selected.rank))
        infoText:SetText(Ui.StatsLine(s, selected.kind, selected.rank))
        local cost = Engine.UpgradeCost(s, selected)
        if selected.rank == 3 and T.specs then -- the choice of specialization replaces the upgrade button
            upgradeButton:Hide()
            infoText:SetWidth(220)
            for i, b in ipairs(specButtons) do
                local SS, open = Engine.Spec(s, selected.kind, i)
                b:SetText(open and string.format("%s %dg", SS.short or SS.name, SS.cost) or (SS.short or SS.name))
                b:SetEnabled(open and s.gold >= SS.cost)
                b:Show()
            end
        end
        upgradeButton:SetText(cost and string.format("Upgrade (%dg)", cost) or "Top rank")
        upgradeButton:SetEnabled(cost ~= nil and s.gold >= cost)
        sellButton:SetText(string.format("Sell +%dg", Engine.SellValue(selected)))
    elseif Board.placing then
        local P = Content.towers[Board.placing]
        if P.hero then
            infoTitle:SetText(P.name .. ": free")
            infoText:SetText(P.blurb)
        else
            infoTitle:SetText(string.format("%s: %dg", P.name, Engine.Stats(s, Board.placing, 1).cost))
            infoText:SetText(P.blurb)
        end
    else
        local level = s._level
        infoTitle:SetText(level.zone .. ": " .. level.name)
        infoText:SetText(level.blurb or "")
    end
end

local function RefreshHero(s)
    local kind = s.loadout.hero
    heroButton:SetShown(kind ~= nil)
    if not kind then return end
    local T = Content.towers[kind]
    heroButton.icon:SetTexture(Board.Icon(T))
    heroButton.name:SetText(T.name)
    local A = T.ability
    if not s.heroId then
        heroButton.state:SetText(Board.placing == kind and "|cff40ff40Pick a cell|r" or "Place (free)")
        heroButton.shade:Hide()
        heroButton.icon:SetDesaturated(false)
        heroButton.bg:SetColorTexture(1, 0.75, 0.15, Board.placing == kind and 0.3 or 0.12)
    elseif s.abilityCd > 0 then
        local left = math.ceil(s.abilityCd / SECOND)
        heroButton.state:SetText(left >= 60 and string.format("%s: %d:%02d", A.name, math.floor(left / 60), left % 60)
            or string.format("%s: %ds", A.name, left))
        heroButton.shade:SetHeight(math.max(1, 36 * s.abilityCd / A.cd))
        heroButton.shade:Show()
        heroButton.icon:SetDesaturated(true)
        heroButton.bg:SetColorTexture(1, 1, 1, 0.05)
    else
        heroButton.state:SetText("|cff40ff40" .. A.name .. ": ready|r")
        heroButton.shade:Hide()
        heroButton.icon:SetDesaturated(false)
        heroButton.bg:SetColorTexture(1, 0.75, 0.15, 0.25)
    end
end

-- Everything the HUD shows. Called after events that change it, never every frame (but the hero's cooldown,
-- once a second).
function Ui.Refresh()
    local G = Game()
    local s = G and G.state
    speedButton:SetText(G and G.speed == 2 and "2x" or "1x")
    autoButton:SetText(G and G.db and G.db.settings.autoWaves and "Auto: on" or "Auto: off")
    saveNote:SetText(G and G.unsaved and L.unsaved or "")
    if not s then
        title:SetText("ForeverTD")
        goldText:SetText(""); livesText:SetText(""); waveText:SetText(""); infoTitle:SetText(""); infoText:SetText("")
        nextTitle:SetText(""); nextText:SetText("")
        upgradeButton:Hide(); sellButton:Hide(); specButtons[1]:Hide(); specButtons[2]:Hide()
        waveButton:SetEnabled(false); pauseButton:SetEnabled(false)
        for _, b in ipairs(palette) do b:Hide() end
        heroButton:Hide()
        return
    end
    local level = s._level
    local camp = Levels.Campaign(level)
    local heroic = s.loadout.difficulty == "heroic"
    title:SetText("ForeverTD   " .. (camp and (Hex(camp.color) .. camp.name .. "|r  ") or "") .. "|cffffffff"
        .. level.name .. (heroic and " (Heroic)" or "") .. "|r")
    goldText:SetText(Inline(COIN) .. " " .. s.gold)
    livesText:SetText(Inline(HEART) .. " " .. s.lives .. "/" .. s.maxLives)
    waveText:SetText(string.format("Wave %d/%d", s.wave, #level.waves))
    local more = s.wave < #level.waves and not s.over
    waveButton:SetEnabled(more and not briefing:IsShown()) -- read the briefing first
    if not more then waveButton:SetText("All waves out")
    elseif G.AutoIn() then waveButton:SetText(string.format("Next wave in %d", G.AutoIn()))
    elseif s.wave == 0 then waveButton:SetText("Start wave 1")
    elseif #s.active > 0 and (level.earlyBonus or 0) > 0 then
        waveButton:SetText(string.format("Next wave (+%dg)", level.earlyBonus))
    else waveButton:SetText("Next wave") end
    pauseButton:SetEnabled(not s.over)
    pauseButton:SetText(G.paused and "Resume" or "Pause")
    for i, b in ipairs(palette) do
        local kind = s.loadout.towers[i]
        b.kind = kind
        if kind then
            local T = Content.towers[kind]
            local cost = Engine.Stats(s, kind, 1).cost
            b.icon:SetTexture(Board.Icon(T))
            b.name:SetText(T.name)
            b.icon:SetDesaturated(s.gold < cost)
            b.cost:SetText(Inline(COIN) .. " " .. cost)
            b.bg:SetColorTexture(1, 0.82, 0, Board.placing == kind and 0.3 or 0.06)
            b:Show()
        else
            b:Hide()
        end
    end
    RefreshHero(s)
    RefreshPreview(s)
    RefreshInfo(s)
end

local REFRESH_ON = { placed = true, upgraded = true, sold = true, waveStart = true, waveCleared = true, over = true,
    rejected = true, ability = true }
local COUNTS_ON = { killed = true, leaked = true, regrow = true } -- gold and lives only

-- Gold, lives, and what that gold can buy now: the light refresh for kills and leaks.
function Ui.RefreshCounts()
    local G = Game()
    local s = G and G.state
    if not s then return end
    goldText:SetText(Inline(COIN) .. " " .. s.gold)
    livesText:SetText(Inline(HEART) .. " " .. s.lives .. "/" .. s.maxLives)
    for i, b in ipairs(palette) do
        local kind = s.loadout.towers[i]
        if kind then b.icon:SetDesaturated(s.gold < Engine.Stats(s, kind, 1).cost) end
    end
    if Board.selected then RefreshInfo(s) end
end

function Ui.OnEvents(events)
    local refresh, counts = false, false
    local G = Game()
    local level = G and G.state and G.state._level
    for _, e in ipairs(events) do
        if REFRESH_ON[e.kind] then refresh = true elseif COUNTS_ON[e.kind] then counts = true end
        if e.kind == "rejected" and L[e.reason] then Ui.Message(L[e.reason]) end
        if e.kind == "sold" then Board.selected = nil end
        if e.kind == "over" then
            Ui.Sound(e.result == "won" and "IG_QUEST_LIST_COMPLETE" or "IG_QUEST_FAILED")
        elseif SOUND_FOR[e.kind] then
            Ui.Sound(SOUND_FOR[e.kind], e.kind)
        end
        if e.kind == "waveStart" and level and level.story.barks then Ui.Bark(level.story.barks[e.wave]) end
        if e.kind == "spawn" and level and level.story.boss and level.story.boss[1] == Content.creeps[e.creep].name then
            Ui.Bark(level.story.boss) -- the boss's own line, as it arrives (not a mid-level boss's)
        end
    end
    if refresh then Ui.Refresh() elseif counts then Ui.RefreshCounts() end
end

local shownAutoIn, shownCd

-- Every frame: the boss panel, the creep tooltip, the auto-wave countdown, the hero's cooldown and the messages.
function Ui.Update(now)
    if messageUntil > 0 and now >= messageUntil then
        message:SetText("")
        messageUntil = 0
    end
    if barkUntil > 0 and now >= barkUntil then
        bark:Hide()
        barkUntil = 0
    end
    local G = Game()
    local s = G and G.state
    if s then
        CreepTooltip(Ui.MenuShown() or endOverlay:IsShown() or briefing:IsShown())
        local autoIn = G.AutoIn()
        local cd = math.ceil(s.abilityCd / SECOND)
        if autoIn ~= shownAutoIn or cd ~= shownCd then
            shownAutoIn, shownCd = autoIn, cd
            Ui.Refresh()
        end
    end
    local boss
    if s and not Ui.MenuShown() and not endOverlay:IsShown() and not briefing:IsShown() then
        for _, c in ipairs(s.creeps) do
            if Content.creeps[c.kind].boss then boss = c; break end
        end
    end
    if boss then
        local C = Content.creeps[boss.kind]
        if bossPanel.id ~= boss.id then
            bossPanel.id = boss.id
            bossPanel:Show()
            nextTitle:Hide(); nextText:Hide()
            bossName:SetText(C.name)
            bossIcon:SetTexture(Board.Icon(C))
        end
        bossBar:SetWidth(math.max(1, (SIDE_W - 2) * boss.hp / boss.maxHp))
        if C.npc then bossModel.Show(C.npc) else bossModel.Release() end
    elseif bossPanel.id then
        bossPanel.id = nil
        bossPanel:Hide()
        nextTitle:Show(); nextText:Show()
        bossModel.Release()
    else
        bossModel.Release() -- (a release that had to wait for the screen)
    end
end

function Ui.ShowPaused(on)
    pausedOverlay:SetShown(on and Game().state ~= nil and not Game().state.over and not briefing:IsShown())
end

-- The briefing: shown before a level you haven't won yet (if the story is on), and from the menu's Story button.
local briefingDone
function Ui.ShowBriefing(level, onDone)
    local story = level.story or {}
    local b = story.briefing
    if not b then
        if onDone then onDone() end
        return false
    end
    local camp = Levels.Campaign(level)
    local speaker = ns.Story.Speaker(b[1])
    briefingDone = onDone
    briefing.icon:SetTexture(Board.Icon(speaker))
    briefing.icon:Show()
    briefing.speaker:SetText(b[1])
    briefing.place:SetText(string.format("%s%s|r  -  %s, level %d of %d", Hex(camp.color), camp.name, level.zone,
        level.number, #camp.levels))
    briefing.title:SetText(level.name)
    briefing.text:SetText(b[2])
    local news = {}
    for _, kind in ipairs(Levels.NewTowers(level)) do
        local T = Content.towers[kind]
        news[#news + 1] = string.format("%s |cff40ff40New tower:|r %s. %s", Inline(Board.Icon(T), 16), T.name, T.blurb)
    end
    if camp.hero and camp.hero.at == level.number then
        local T = Content.towers[camp.hero.kind]
        news[#news + 1] = string.format("%s |cffffd200Your hero joins:|r %s. %s", Inline(Board.Icon(T), 16), T.name,
            T.ability.name .. ": " .. T.ability.blurb)
    end
    briefing.news:SetText(table.concat(news, "\n"))
    pausedOverlay:Hide()
    briefing:Show()
    if speaker.npc then speakerModel.Show(speaker.npc) end
    Ui.Refresh()
    return true
end

function Ui.CloseBriefing()
    speakerModel.Release()
    briefing:Hide()
    local done = briefingDone
    briefingDone = nil
    if done then done() end
    Ui.ShowPaused(Game().paused)
    Ui.Refresh()
end

function Ui.BriefingShown() return briefing:IsShown() end

function Ui.ShowEnd(summary, state)
    local won = state.over == "won"
    local level = state._level
    local camp = Levels.Campaign(level)
    local nextLevel = Levels.Next(level)
    endOverlay.title:SetText(won and "|cff40ff40Victory!|r" or "|cffff4040Defeat|r")
    local story = ""
    if won then
        story = level.story.victory or ""
        if not nextLevel and camp.story.outro then
            story = story .. (story ~= "" and "\n\n" or "") .. string.format("|cffffd200%s:|r %s", camp.story.outro[1],
                camp.story.outro[2])
        end
    end
    endOverlay.story:SetText(story)
    local lines = {}
    if won then
        lines[#lines + 1] = string.format("Stars: %s%s", Stars(summary.stars),
            summary.newBest and "  (new best!)" or "")
    else
        lines[#lines + 1] = string.format("The road fell at wave %d of %d.", state.wave, #level.waves)
    end
    local rw = summary.reward
    if rw then
        local why = {}
        if rw.base > 0 then why[#why + 1] = (won and "win " or "effort ") .. rw.base end
        if rw.firstClear > 0 then why[#why + 1] = "first clear " .. rw.firstClear end
        if rw.starBonus > 0 then why[#why + 1] = "new stars " .. rw.starBonus end
        if (rw.finale or 0) > 0 then why[#why + 1] = "campaign complete " .. rw.finale end
        lines[#lines + 1] = string.format("Warmarks +%d (%s). You have %d.", rw.total, table.concat(why, ", "),
            Game().db.profile.warmarks)
    end
    local opened = summary.opened
    if opened then
        local news = {}
        for _, kind in ipairs(opened.towers) do
            local T = Content.towers[kind]
            news[#news + 1] = Inline(Board.Icon(T), 16) .. " " .. T.name .. (T.hero and " joins you" or " joins")
        end
        for _, c in ipairs(opened.campaigns) do news[#news + 1] = Hex(c.color) .. c.name .. "|r: a new campaign!" end
        if #news > 0 then lines[#lines + 1] = "|cff40ff40New:|r " .. table.concat(news, ",  ") end
    end
    lines[#lines + 1] = "|cffaaaaaa" .. L.unsaved .. "|r"
    endOverlay.lines:SetText(table.concat(lines, "\n\n"))
    nextButton:SetShown(won and nextLevel ~= nil and Meta.LevelUnlocked(Game().db.profile, nextLevel))
    pausedOverlay:Hide()
    bark:Hide()
    endOverlay:Show()
end

-- A run started or was restored.
function Ui.OnRun()
    endOverlay:Hide()
    bark:Hide()
    if briefing:IsShown() then Ui.CloseBriefing() end
    Ui.ShowMenu(false)
    previewState = nil
    Ui.ShowPaused(Game().paused)
    Ui.Refresh()
end

Ui.L = L
Ui.Text, Ui.Button, Ui.Inline, Ui.Hex = Text, Button, Inline, Hex
Ui.boardFrame, Ui.specButtons, Ui.heroButton, Ui.briefing, Ui.bark = boardFrame, specButtons, heroButton, briefing, bark
Ui.waveButton, Ui.speedButton = waveButton, speedButton
Ui.endOverlay, Ui.pausedOverlay, Ui.palette = endOverlay, pausedOverlay, palette

return Ui
