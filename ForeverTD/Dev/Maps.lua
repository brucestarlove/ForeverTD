-- Dev/Maps.lua - zone map browser (/td maps). Lists every continent and zone the client's map data has, found by
-- climbing from the player's map to the world map (the way the client's own map menus can be walked),
-- and draws a zone's painted map art from its tiles.
-- The idea under test: real zone art as level backgrounds. Star the zones you'd like levels in.
local _, ns = ...
local Dev, Core = ns.Dev, ns.DevCore

local Tab = {}
local ROWS, ROW_H, LIST_W = 18, 20, 200
local TOP = 34
local VIEW_W, VIEW_H = Dev.CONTENT_W - LIST_W - 10, Dev.CONTENT_H - TOP
local MAX_TILES = 64
local FALLBACK_WORLDS = { 947 } -- Retail's Azeroth map, if the climb finds nothing (e.g. inside an instance)

local panel, pageText, art, caption, starButton
local rows, tiles = {}, {}
local zones, discoverError
local page, shown = 1, nil

local function MapType(name, fallback)
    return Enum and Enum.UIMapType and Enum.UIMapType[name] or fallback
end

local function Discover()
    local list = {}
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return list, "C_Map is missing" end
    local COSMIC, WORLD = MapType("Cosmic", 0), MapType("World", 1)
    local CONTINENT, ZONE = MapType("Continent", 2), MapType("Zone", 3)
    local world
    local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _ = 1, 12 do
        local info = id and C_Map.GetMapInfo(id)
        if not info or info.mapType == COSMIC then break end
        if info.mapType == WORLD then world = info.mapID; break end
        id = info.parentMapID
    end
    if not world then
        for _, guess in ipairs(FALLBACK_WORLDS) do
            local info = C_Map.GetMapInfo(guess)
            if info and info.mapType == WORLD then world = guess; break end
        end
    end
    if not world then return list, "no world map found from here" end
    for _, cont in ipairs(C_Map.GetMapChildrenInfo(world) or {}) do
        if cont.mapType == CONTINENT then
            list[#list + 1] = { mapID = cont.mapID, name = cont.name, continent = cont.name, isContinent = true }
            local zoneList = {}
            for _, z in ipairs(C_Map.GetMapChildrenInfo(cont.mapID) or {}) do
                if z.mapType == ZONE then
                    zoneList[#zoneList + 1] = { mapID = z.mapID, name = z.name, continent = cont.name }
                end
            end
            table.sort(zoneList, function(a, b) return a.name < b.name end)
            for _, z in ipairs(zoneList) do list[#list + 1] = z end
        end
    end
    return list
end

local function Tile(i)
    local t = tiles[i]
    if t then return t end
    t = art:CreateTexture(nil, "ARTWORK")
    tiles[i] = t
    return t
end

local function PaintStar()
    if shown and Dev.IsStarred("maps", shown.mapID) then
        starButton:SetText("Unstar")
    else
        starButton:SetText("Star map")
    end
end

-- Lays the zone's first art layer out as its grid of tiles, scaled to fit the viewer.
local function ShowMap(entry)
    shown = entry
    for _, t in ipairs(tiles) do t:Hide() end
    local okL, layers = pcall(C_Map.GetMapArtLayers, entry.mapID)
    local okT, files = pcall(C_Map.GetMapArtLayerTextures, entry.mapID, 1)
    local layer = okL and type(layers) == "table" and layers[1]
    if not (layer and okT and type(files) == "table" and #files > 0) then
        caption:SetText(entry.name .. ": no map art on this client")
        Dev.Record("maps", entry.mapID, false)
        PaintStar()
        return
    end
    local scale = math.min(VIEW_W / layer.layerWidth, VIEW_H / layer.layerHeight)
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local tw, th = layer.tileWidth * scale, layer.tileHeight * scale
    art:SetSize(layer.layerWidth * scale, layer.layerHeight * scale)
    for i = 1, math.min(#files, MAX_TILES) do
        local t = Tile(i)
        t:SetTexture(files[i])
        t:SetSize(tw, th)
        t:SetPoint("TOPLEFT", art, "TOPLEFT", ((i - 1) % cols) * tw, -math.floor((i - 1) / cols) * th)
        t:Show()
    end
    caption:SetText(string.format("%s (%s)   map %d   %dx%d art in %d tiles", entry.name, entry.continent or "?",
        entry.mapID, layer.layerWidth, layer.layerHeight, #files))
    Dev.Record("maps", entry.mapID, { name = entry.name, width = layer.layerWidth, height = layer.layerHeight,
        tiles = #files })
    PaintStar()
end

local function Render()
    local count = #zones
    local pages, first
    page, pages, first = Core.Page(count, ROWS, page)
    for i = 1, ROWS do
        local row, entry = rows[i], zones[first + i - 1]
        row.entry = entry
        if entry then
            local color = entry.isContinent and "|cff88bbff" or ""
            if Dev.IsStarred("maps", entry.mapID) then color = "|cffffd200" end
            row.text:SetText(color .. entry.name .. (entry.isContinent and " (continent)" or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    if discoverError then
        pageText:SetText("No maps: " .. discoverError)
    else
        pageText:SetText(string.format("page %d / %d   (%d maps)", page, pages, count))
    end
end

local function Row(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -TOP - (i - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.text = Dev.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self) if self.entry then ShowMap(self.entry) end end)
    return row
end

function Tab.Build(p)
    panel = p
    local prev = Dev.Button(panel, "<", 30, function() page = page - 1; Render() end)
    prev:SetPoint("TOPLEFT", 0, 0)
    local nextB = Dev.Button(panel, ">", 30, function() page = page + 1; Render() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    pageText = Dev.Text(panel, "GameFontNormalSmall")
    pageText:SetPoint("LEFT", nextB, "RIGHT", 10, 0)
    starButton = Dev.Button(panel, "Star map", 90, function()
        if not shown then return end
        Dev.ToggleStar("maps", shown.mapID, shown.name)
        PaintStar()
        Render()
    end)
    starButton:SetPoint("TOPRIGHT", 0, 0)
    for i = 1, ROWS do rows[i] = Row(i) end
    local viewer = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    viewer:SetPoint("TOPLEFT", LIST_W + 10, -TOP)
    viewer:SetSize(VIEW_W, VIEW_H)
    viewer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    viewer:SetBackdropColor(0, 0, 0, 0.6)
    art = CreateFrame("Frame", nil, viewer)
    art:SetPoint("TOPLEFT")
    art:SetSize(VIEW_W, VIEW_H)
    art:SetClipsChildren(true)
    caption = Dev.Text(viewer, "GameFontNormalSmall")
    caption:SetPoint("BOTTOMLEFT", 6, 6)
    caption:SetText("Pick a zone on the left.")
end

function Tab.OnOpen()
    if not zones then zones, discoverError = Discover() end
    Render()
end

Dev.RegisterTab("Maps", Tab)
