-- Dev/DevCore.lua - the pure part of the dev tools: the bench's scenario list and timing sequence, the lane its movers
-- follow, frame-time statistics, report lines and paging. No WoW calls: tests/run.lua and tools/dev-report.lua load
-- this same file under plain Lua 5.1.
local _, ns = ...
ns = ns or {}
local DevCore = {}
ns.DevCore = DevCore

-- What the bench draws, in order. warm = seconds to settle (models stream in), secs = seconds measured.
-- sprites:     n creeps (a frame holding an icon and a health bar) plus n/2 projectile textures
-- modelframes: n creeps, each a small 3D scene of its own, moved like a sprite
-- modelscene:  n creeps as actors in one board-sized 3D scene
DevCore.SCENARIOS = {
    { kind = "baseline", n = 0, warm = 1, secs = 3 },
    { kind = "sprites", n = 50, warm = 1, secs = 4 },
    { kind = "sprites", n = 200, warm = 1, secs = 4 },
    { kind = "sprites", n = 500, warm = 1, secs = 4 },
    { kind = "modelframes", n = 5, warm = 2, secs = 4 },
    { kind = "modelframes", n = 20, warm = 2, secs = 4 },
    { kind = "modelframes", n = 50, warm = 2, secs = 4 },
    { kind = "modelscene", n = 5, warm = 2, secs = 4 },
    { kind = "modelscene", n = 20, warm = 2, secs = 4 },
    { kind = "modelscene", n = 50, warm = 2, secs = 4 },
}

DevCore.LABELS = {
    baseline = "Baseline (empty board)",
    sprites = "2D sprites",
    modelframes = "3D, a scene each",
    modelscene = "3D, one shared scene",
}

-- The lane: a serpentine through the unit square (u right, v down), like a tower-defense path.
local PATH = { 0.04, 0.15, 0.96, 0.15, 0.96, 0.50, 0.04, 0.50, 0.04, 0.85, 0.96, 0.85 }
local cumulative, total = { 0 }, 0
for i = 3, #PATH, 2 do
    local dx, dy = PATH[i] - PATH[i - 2], PATH[i + 1] - PATH[i - 1]
    total = total + math.sqrt(dx * dx + dy * dy)
    cumulative[#cumulative + 1] = total
end
DevCore.PATH = PATH

-- Position on the lane at fraction t (wrapping), plus the current segment's direction. Returns numbers, never a
-- table: it runs for every mover on every frame, and per-frame garbage becomes GC hitches.
function DevCore.PathPoint(t)
    local d = (t % 1) * total
    for s = 1, #cumulative - 1 do
        if d <= cumulative[s + 1] then
            local i = 2 * s - 1
            local x0, y0, x1, y1 = PATH[i], PATH[i + 1], PATH[i + 2], PATH[i + 3]
            local f = (d - cumulative[s]) / (cumulative[s + 1] - cumulative[s])
            return x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, x1 - x0, y1 - y0
        end
    end
    return PATH[#PATH - 1], PATH[#PATH], 0, 0
end

-- The yaw that turns a 3D model to face a screen direction (du right, dv down) under Dev.AimCamera's camera.
-- Seen in Bruce's client (2026-10-17): screen right is world +x, screen down is world -y, and yaw 0 faces +x. The
-- first bench had the x sign backwards, and its creatures walked backwards along the lane's horizontal runs.
function DevCore.FacingYaw(du, dv) return math.atan2(-dv, du) end

-- A model's size from its bounding box corners: width (x), depth (y), height (z), or nil when the numbers are unusable.
-- The client reports its missing-model placeholder as loaded with a 0.28-unit cube (as another Forever game
-- found); that returns nil, "missing".
function DevCore.Extent(minX, minY, minZ, maxX, maxY, maxZ)
    local values = { minX, minY, minZ, maxX, maxY, maxZ }
    for i = 1, 6 do
        local v = values[i]
        if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then return nil end
    end
    local w, d, h = maxX - minX, maxY - minY, maxZ - minZ
    if w <= 0 or d <= 0 or h <= 0 then return nil end
    if math.abs(w - 0.28) < 0.002 and math.abs(d - 0.28) < 0.002 and math.abs(h - 0.28) < 0.002 then
        return nil, "missing"
    end
    return w, d, h
end

-- Scale that fits a model's largest side into `room` model units, never enlarging past maxScale (default 1, so small
-- creatures stay small).
function DevCore.FitScale(w, d, h, room, maxScale)
    return math.min(maxScale or 1, room / math.max(w, d, h))
end

-- Frame statistics. Arrays are reused between scenarios (n resets), so measuring doesn't allocate per frame.
function DevCore.NewStats() return { n = 0, lua = {}, frame = {} } end

function DevCore.AddSample(stats, luaMs, frameMs)
    local n = stats.n + 1
    stats.n = n
    stats.lua[n], stats.frame[n] = luaMs, frameMs
end

local function Round(x) return math.floor(x * 1000 + 0.5) / 1000 end

local function Spread(values, n) -- average, 95th percentile, worst
    if n == 0 then return 0, 0, 0 end
    local sorted, sum = {}, 0
    for i = 1, n do sorted[i] = values[i]; sum = sum + values[i] end
    table.sort(sorted)
    return sum / n, sorted[math.max(1, math.ceil(n * 0.95))], sorted[n]
end

function DevCore.Summarize(stats)
    local luaAvg, luaP95, luaMax = Spread(stats.lua, stats.n)
    local frameAvg, frameP95, frameMax = Spread(stats.frame, stats.n)
    return {
        frames = stats.n,
        luaAvg = Round(luaAvg), luaP95 = Round(luaP95), luaMax = Round(luaMax),
        frameAvg = Round(frameAvg), frameP95 = Round(frameP95), frameMax = Round(frameMax),
        fps = frameAvg > 0 and Round(1000 / frameAvg) or 0,
    }
end

-- A bench run walks the scenarios: warm up, then measure, then the next. Step() is called once per frame with that
-- frame's elapsed seconds and the Lua milliseconds the movers took, and returns at most one event:
--   "begin"   set up run.list[run.index] (the first scenario)
--   "measure" warm-up is over; samples count from now
--   "next"    the previous scenario finished (its summary is the last of run.results); set up run.list[run.index]
--   "done"    the last scenario finished; run.results is complete
-- run.time is an animation clock for the movers.
function DevCore.NewRun(scenarios)
    return { list = scenarios, index = 0, phase = "idle", t = 0, time = 0, stats = DevCore.NewStats(), results = {} }
end

function DevCore.Step(run, elapsed, luaMs)
    if run.phase == "done" then return nil end
    run.time = run.time + elapsed
    if run.phase == "idle" then
        run.index, run.phase, run.t = 1, "warm", 0
        return "begin"
    end
    local scenario = run.list[run.index]
    run.t = run.t + elapsed
    if run.phase == "warm" then
        if run.t >= scenario.warm then
            run.phase, run.t, run.stats.n = "measure", 0, 0
            return "measure"
        end
    else
        DevCore.AddSample(run.stats, luaMs, elapsed * 1000)
        if run.t >= scenario.secs then
            local result = DevCore.Summarize(run.stats)
            result.kind, result.n = scenario.kind, scenario.n
            run.results[#run.results + 1] = result
            if run.index >= #run.list then
                run.phase = "done"
                return "done"
            end
            run.index, run.phase, run.t = run.index + 1, "warm", 0
            return "next"
        end
    end
    return nil
end

-- One line per scenario, with the frame time compared to the empty board's.
function DevCore.FormatResult(r, baseFrameMs)
    local parts = { (DevCore.LABELS[r.kind] or tostring(r.kind)) .. ((r.n or 0) > 0 and (" x" .. r.n) or "") }
    parts[#parts + 1] = string.format("Lua %.2f ms (p95 %.2f)", r.luaAvg or 0, r.luaP95 or 0)
    local delta = ""
    if baseFrameMs and r.kind ~= "baseline" then delta = string.format(" (%+.1f)", (r.frameAvg or 0) - baseFrameMs) end
    parts[#parts + 1] = string.format("frame %.1f ms%s, p95 %.1f", r.frameAvg or 0, delta, r.frameP95 or 0)
    parts[#parts + 1] = string.format("%.0f fps", r.fps or 0)
    if r.loaded then parts[#parts + 1] = string.format("loaded %d/%d", r.loaded, r.n) end
    return table.concat(parts, "  |  ")
end

function DevCore.FormatRun(record)
    local lines = { string.format("Bench %s  %s  %s  UI scale %.2f", record.date or "?", record.zone or "",
        record.screen or "", record.uiScale or 0) }
    local base
    for _, r in ipairs(record.results or {}) do
        if r.kind == "baseline" then base = r.frameAvg end
    end
    for _, r in ipairs(record.results or {}) do lines[#lines + 1] = DevCore.FormatResult(r, base) end
    return table.concat(lines, "\n")
end

-- Paging: clamps the page and returns page, pages, first index, last index (last < first when empty).
function DevCore.Page(count, perPage, page)
    local pages = math.max(1, math.ceil(count / perPage))
    page = math.min(math.max(math.floor(tonumber(page) or 1), 1), pages)
    local first = (page - 1) * perPage + 1
    return page, pages, first, math.min(count, first + perPage - 1)
end

-- Keeps the newest `max` entries of a list (SavedVariables shouldn't grow forever).
function DevCore.Trim(list, max)
    while #list > max do table.remove(list, 1) end
    return list
end

-- Sorted keys of a set, numbers and strings mixed (pairs() order is not a contract).
function DevCore.SortedKeys(set)
    local keys = {}
    for k in pairs(set) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

return DevCore
