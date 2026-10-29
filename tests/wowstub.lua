-- wowstub.lua - just enough of the WoW environment to load addon files under plain Lua 5.1.
-- Not an emulator: frames are recorders, timers run when you call stub.runTimers(), the clock moves when you say.
-- Add stubs as your Shell needs them; keep Engine.lua free of WoW calls so it needs none.
local stub = {}
local hasBit, bitlib = pcall(require, "bit") -- LuaBitOp; WoW provides a global `bit`

-- Globals WoW does not give addons. Loading a file through stub.load() hides these, so a stray io/os/require in game
-- code fails here instead of in the client. [General] WoW's exact sandbox differs in details; this is the safe subset.
local HIDDEN = { io = true, os = true, require = true, dofile = true, loadfile = true, package = true, module = true }

stub.now = 0          -- what GetTime() returns
stub.serverNow = 1760000000
stub.timers = {}
stub.frames = {}
stub.printed = {}

local function noop() end

-- A frame (or texture, font string...) that accepts any method. Scripts, events, shown state and size are recorded so
-- tests can drive them: stub.fire(event, ...) and frame:Run("OnUpdate", elapsed).
local Frame = {}
-- Unknown CamelCase keys are WoW widget methods the stub doesn't model: they answer as no-ops. Anything else is an
-- addon's own field, and, as in the client, a missing field is nil.
Frame.__index = function(self, key)
    local method = rawget(Frame, key)
    if method then return method end
    if type(key) == "string" and key:find("^%u") then return noop end
    return nil
end
function Frame.new(kind, name)
    local f = setmetatable({ kind = kind, name = name, scripts = {}, events = {}, shown = true,
        w = 100, h = 100, left = 0, scale = 1 }, Frame)
    stub.frames[#stub.frames + 1] = f
    return f
end
function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:HookScript(script, fn)
    local old = self.scripts[script]
    self.scripts[script] = function(...) if old then old(...) end; return fn(...) end
end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:IsEventRegistered(event) return self.events[event] == true end
-- Show/Hide fire OnShow/OnHide on a change, as the client does (ESC and combat close windows through Hide).
function Frame:Show()
    if self.shown then return end
    self.shown = true
    self:Run("OnShow")
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    self:Run("OnHide")
end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:SetEnabled(on) self.enabled = on and true or false end
function Frame:EnableKeyboard(on) self.keyboard = on and true or false end -- recorded: the game takes no keys
function Frame:IsKeyboardEnabled() return self.keyboard == true end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:GetLeft() return self.left end
function Frame:GetTop() return self.top end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:GetEffectiveScale() return self.scale end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:CreateTexture(name) return Frame.new("Texture", name) end
function Frame:CreateFontString(name) return Frame.new("FontString", name) end
function Frame:CreateAnimationGroup(name) return Frame.new("AnimationGroup", name) end
function Frame:CreateMaskTexture(name) return Frame.new("MaskTexture", name) end
function Frame:CreateLine(name) return Frame.new("Line", name) end
function Frame:CreateActor(name) return Frame.new("Actor", name) end -- ModelScene actors
function Frame:Run(script, ...) local fn = self.scripts[script]; if fn then return fn(self, ...) end end
stub.Frame = Frame

-- Sends an event to every frame registered for it, as the client would.
function stub.fire(event, ...)
    for _, f in ipairs(stub.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Runs due C_Timer callbacks (advance stub.now first). Callbacks may schedule more.
function stub.runTimers()
    local due = {}
    for i = #stub.timers, 1, -1 do
        if stub.timers[i].at <= stub.now then due[#due + 1] = table.remove(stub.timers, i) end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
    return #due
end

-- The environment game files see.
function stub.env()
    local env = {}
    for k, v in pairs(_G) do
        if not HIDDEN[k] then env[k] = v end
    end
    env._G = env
    env.UIParent = Frame.new("Frame", "UIParent")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.CreateFrame = function(kind, name) local f = Frame.new(kind, name); if name then env[name] = f end; return f end
    env.GameTooltip = Frame.new("GameTooltip", "GameTooltip")
    env.GetFramerate = function() return 60 end
    env.GetRealZoneText = function() return "Elwynn Forest" end
    env.GetPhysicalScreenSize = function() return 2560, 1440 end
    env.ReloadUI = function() stub.reloads = (stub.reloads or 0) + 1 end
    env.GetTime = function() return stub.now end
    env.GetServerTime = function() return stub.serverNow end
    env.time = function() return stub.serverNow end
    env.date = function() return "00:00:00" end
    env.debugprofilestop = function() return stub.now * 1000 end
    env.GetCursorPosition = function() return stub.cursorX or 0, stub.cursorY or 0 end
    env.InCombatLockdown = function() return stub.inCombat == true end
    env.UnitAffectingCombat = function() return stub.inCombat == true end
    env.issecretvalue = function() return false end
    env.UnitName = function() return "Tester", nil end
    env.GetBuildInfo = function() return "1.60.1", "70170", "Oct 1 2026", 16001 end
    env.C_Timer = {
        After = function(delay, fn) stub.timers[#stub.timers + 1] = { at = stub.now + delay, fn = fn } end,
        NewTicker = function(delay, fn) -- returns a handle with :Cancel()
            local handle = { cancelled = false }
            local function again()
                if handle.cancelled then return end
                fn(handle)
                stub.timers[#stub.timers + 1] = { at = stub.now + delay, fn = again }
            end
            stub.timers[#stub.timers + 1] = { at = stub.now + delay, fn = again }
            function handle:Cancel() self.cancelled = true end
            return handle
        end,
    }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return 0 end,
        SendAddonMessage = function(prefix, msg, channel, target)
            stub.sent = stub.sent or {}
            stub.sent[#stub.sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
            return 0
        end,
        InChatMessagingLockdown = function() return false end,
    }
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        stub.printed[#stub.printed + 1] = table.concat(parts, " ")
    end
    -- WoW's Lua helpers that plain Lua lacks.
    env.strsplit = function(sep, text, limit)
        local out, start, n = {}, 1, 0
        while true do
            n = n + 1
            local s, e = string.find(text, sep, start, true)
            if not s or (limit and n >= limit) then out[#out + 1] = string.sub(text, start); break end
            out[#out + 1] = string.sub(text, start, s - 1)
            start = e + 1
        end
        return unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.strtrim = function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
    env.tinsert, env.tremove = table.insert, table.remove
    env.format, env.strlower, env.strupper = string.format, string.lower, string.upper
    env.floor, env.ceil, env.abs, env.max, env.min = math.floor, math.ceil, math.abs, math.max, math.min
    -- [General] LuaBitOp (bundled with Lua for Windows) returns signed results; do not depend on the sign either way.
    env.bit = hasBit and bitlib or nil
    return env
end

-- Loads a game file the way the client does: `...` is (addonName, ns), globals come from `env`.
function stub.load(path, addonName, ns, env)
    local chunk, err = loadfile(path)
    if not chunk then error(err, 2) end
    setfenv(chunk, env)
    return chunk(addonName, ns)
end

return stub
