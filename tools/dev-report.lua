-- tools/dev-report.lua - prints what a tester's game saved, for an agent that can't see the client: the progress
-- (every level's stars and plays, abandoned runs, the level in progress, research, settings), then what the dev
-- tools saved (bench, probe, which icons, creatures and maps loaded).
-- Usage (after a /reload or logout in the client), from the repository folder:
--   lua tools/dev-report.lua                       the newest ForeverTD.lua among the client's accounts
--   lua tools/dev-report.lua 5                     the account whose folder ends in #5 (a second test account, say)
--   lua tools/dev-report.lua <account folder>      e.g. 12345678#1
--   lua tools/dev-report.lua <path to ForeverTD.lua>
-- The accounts are the client's WTF\Account folders; FOREVERTD_WTF names another WTF folder than the default.
-- Finding them uses PowerShell, so the lookups are Windows-only (a path works anywhere).
-- A SavedVariables file is plain Lua assignments. It runs here in an empty sandbox, so it can't reach anything.
local WTF = os.getenv("FOREVERTD_WTF") or "C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\WTF"
local function SavedFile(account) return WTF .. "\\Account\\" .. account .. "\\SavedVariables\\ForeverTD.lua" end

-- The account folders that have a ForeverTD.lua, the newest save first.
local function Accounts()
    local accounts = {}
    local pipe = io.popen('powershell -NoProfile -Command "Get-ChildItem -Path \'' .. WTF
        .. '\\Account\\*\\SavedVariables\\ForeverTD.lua\' | Sort-Object LastWriteTime -Descending'
        .. ' | ForEach-Object { $_.Directory.Parent.Name }"')
    if pipe then
        for line in pipe:lines() do
            if line ~= "" then accounts[#accounts + 1] = line end
        end
        pipe:close()
    end
    return accounts
end

-- The file a command-line argument names (see Usage), or nil.
local function SavedPath(given)
    if given and (given:find("[\\/]") or given:find("%.lua$")) then return given end
    if given and not given:match("^#?%d+$") then return SavedFile(given) end
    local n = given and given:match("%d+")
    for _, account in ipairs(Accounts()) do
        if not n or account:match("#" .. n .. "$") then return SavedFile(account) end
    end
end

local M = {}

local root = ((arg and arg[0] or ""):match("^(.-)[\\/]?tools[\\/]dev%-report%.lua$") or ".")
if root == "" then root = "." end

local function LoadCore()
    local chunk = assert(loadfile(root .. "/ForeverTD/Dev/DevCore.lua"))
    local ns = {}
    chunk("ForeverTD", ns)
    return ns.DevCore
end

-- Returns the ForeverTDDB table from a SavedVariables file, or nil and a reason.
function M.LoadSaved(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    local env = {}
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    if not ok then return nil, runErr end
    if type(env.ForeverTDDB) ~= "table" then return nil, "no ForeverTDDB in " .. path end
    return env.ForeverTDDB
end

local function Section(lines, title) lines[#lines + 1] = ""; lines[#lines + 1] = "== " .. title end

-- The game's own files, through the simulator's loader: level names and campaign order for the progress report.
local function LoadGame()
    return assert(loadfile(root .. "/tools/sim.lua"))("--lib").Load(root)
end

local function OnOff(v) return v and "on" or "off" end

-- The player's progress as a list of lines: what was played and how it went, and the level in progress. Runs
-- started but never paid were abandoned (a restart, or another level started) or are still in progress.
function M.Progress(db, ns)
    ns = ns or LoadGame()
    local lines = {}
    local p = db.profile
    Section(lines, string.format("Progress (save schema %s)", tostring(db.schema)))
    if type(p) ~= "table" then
        lines[#lines + 1] = "   (no profile)"
        return lines
    end
    local s, claimed = p.stats or {}, #(p.claimed or {})
    local run = type(db.run) == "table" and db.run or nil
    local open = run and 1 or 0
    lines[#lines + 1] = string.format("   runs started %d, paid %d, abandoned %d%s; won %d, lost %d; kills %d; "
        .. "Warmarks %d", p.runs or 0, claimed, math.max(0, (p.runs or 0) - claimed - open),
        run and " (+1 in progress)" or "", s.won or 0, s.lost or 0, s.kills or 0, p.warmarks or 0)
    local research = {}
    for kind, tier in pairs(p.armory or {}) do research[#research + 1] = kind .. " " .. tier end
    table.sort(research)
    local sup = p.supplies or {}
    lines[#lines + 1] = string.format("   research: %s; supplies: gold %d, lives %d%s",
        #research > 0 and table.concat(research, ", ") or "none", sup.gold or 0, sup.lives or 0,
        p.sandbox and "; SANDBOX ON" or "")
    local set = db.settings or {}
    lines[#lines + 1] = string.format("   settings: speed %s, auto waves %s, scale %s, effects %s, story %s",
        tostring(set.speed), OnOff(set.autoWaves), tostring(set.scale), OnOff(set.effects),
        OnOff(set.story))
    for _, camp in ipairs(ns.Levels.campaigns) do
        local parts = {}
        for _, level in ipairs(camp.levels) do
            local r = p.levels and p.levels[level.id]
            if r then
                parts[#parts + 1] = string.format("%d %s %d*%s (%d/%d)", level.number, level.name, r.stars or 0,
                    (r.heroicStars or 0) > 0 and (", Heroic " .. r.heroicStars) or "", r.wins or 0, r.plays or 0)
            end
        end
        if #parts > 0 then
            lines[#lines + 1] = "   " .. camp.name .. ": " .. table.concat(parts, "; ")
        end
    end
    if run then
        local level = ns.Levels.byId[run.level]
        local snap = type(run.snapshot) == "table" and run.snapshot or nil
        local towers = {}
        for _, t in ipairs(snap and snap.towers or {}) do towers[#towers + 1] = t.kind .. " r" .. t.rank end
        lines[#lines + 1] = string.format("   in progress: %s %s, %s%s", tostring(run.runId), level and level.name
            or tostring(run.level), tostring(run.difficulty), snap and string.format(": wave %d, lives %d/%d, gold "
            .. "%d, towers: %s", snap.wave or 0, snap.lives or 0, snap.maxLives or 0, snap.gold or 0,
            #towers > 0 and table.concat(towers, ", ") or "none") or "")
    end
    return lines
end

-- The report as a list of lines.
function M.Lines(db, Core)
    Core = Core or LoadCore()
    local dev = db.dev or {}
    local lines = {}
    local runs = dev.benchRuns or {}
    Section(lines, string.format("Bench runs (%d saved, newest last)", #runs))
    for i = math.max(1, #runs - 2), #runs do
        local r = runs[i]
        lines[#lines + 1] = Core.FormatRun(r)
        lines[#lines + 1] = string.format("   build %s %s, addon memory %s KB, displays %s", tostring(r.version),
            tostring(r.build), tostring(r.addonKB), table.concat(r.displays or {}, "/"))
        for _, res in ipairs(r.results or {}) do
            if res.profilerMs then
                lines[#lines + 1] = string.format("   profiler: %s x%d %.3f ms", res.kind, res.n, res.profilerMs)
            end
        end
    end
    Section(lines, "Probe")
    if dev.probe then
        for _, k in ipairs(Core.SortedKeys(dev.probe)) do
            local v = dev.probe[k]
            if type(v) == "table" then
                for _, k2 in ipairs(Core.SortedKeys(v)) do
                    lines[#lines + 1] = "   " .. k .. "." .. k2 .. ": " .. tostring(v[k2])
                end
            else
                lines[#lines + 1] = "   " .. k .. ": " .. tostring(v)
            end
        end
    else
        lines[#lines + 1] = "   (not run)"
    end
    for _, kind in ipairs({ "icons", "creatures", "maps" }) do
        local starred = (dev.starred or {})[kind] or {}
        local checked = (dev.checked or {})[kind] or {}
        local keys = Core.SortedKeys(starred)
        Section(lines, string.format("%s: %d starred", kind, #keys))
        for _, k in ipairs(keys) do
            lines[#lines + 1] = string.format("   * %s  %s  (resolved: %s)", tostring(k), tostring(starred[k]),
                tostring(checked[k]))
        end
        local failed, ok = {}, 0
        for _, k in ipairs(Core.SortedKeys(checked)) do
            if checked[k] == false then failed[#failed + 1] = tostring(k) else ok = ok + 1 end
        end
        lines[#lines + 1] = string.format("   checked: %d loaded, %d failed%s", ok, #failed,
            #failed > 0 and (": " .. table.concat(failed, ", ")) or "")
    end
    return lines
end

if ... == "--lib" then return M end

local path = SavedPath((...))
if not path then
    io.stderr:write("dev-report: no ForeverTD.lua found in " .. WTF .. "\\Account (give a path)\n")
    os.exit(1)
end
local db, err = M.LoadSaved(path)
if not db then
    io.stderr:write("dev-report: " .. tostring(err) .. "\n")
    os.exit(1)
end
print("ForeverTD report: " .. path)
for _, line in ipairs(M.Progress(db)) do print(line) end
for _, line in ipairs(M.Lines(db)) do print(line) end
