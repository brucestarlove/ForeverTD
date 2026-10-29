-- DevCore tests: the bench's pure parts (lane, statistics, scenario sequence, paging), plus the asset list's shape.
local stub = require("wowstub")

local function load(T)
    local env = stub.env()
    local ns = {}
    stub.load(T.base .. "/ForeverTD/Dev/DevCore.lua", "ForeverTD", ns, env)
    stub.load(T.base .. "/ForeverTD/Dev/AssetList.lua", "ForeverTD", ns, env)
    return ns.DevCore, ns.AssetList
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

local tests = {}

tests["the lane starts and ends on its waypoints and wraps"] = function(T)
    local Core = load(T)
    local P = Core.PATH
    local u, v = Core.PathPoint(0)
    T.ok(near(u, P[1]) and near(v, P[2]), "t=0 is the first waypoint")
    u, v = Core.PathPoint(0.999999999)
    T.ok(math.abs(u - P[#P - 1]) < 1e-6 and math.abs(v - P[#P]) < 1e-6, "t~1 is the last waypoint")
    local u1, v1 = Core.PathPoint(0.3)
    local u2, v2 = Core.PathPoint(1.3)
    T.ok(near(u1, u2) and near(v1, v2), "wraps")
end

tests["the lane is continuous and stays inside the board"] = function(T)
    local Core = load(T)
    local pu, pv = Core.PathPoint(0)
    for i = 1, 999 do -- t = 1 wraps back to the start (a creep leaving and a new one spawning), so stop short
        local u, v = Core.PathPoint(i / 1000)
        T.ok(u >= 0 and u <= 1 and v >= 0 and v <= 1, "inside at " .. i)
        T.ok(math.abs(u - pu) + math.abs(v - pv) < 0.01, "no jump at " .. i)
        pu, pv = u, v
    end
end

tests["creatures face the way they move on screen"] = function(T)
    local Core = load(T)
    local function same(a, b) return near(math.cos(a), math.cos(b)) and near(math.sin(a), math.sin(b)) end
    T.ok(same(Core.FacingYaw(1, 0), 0), "moving right: yaw 0 (world +x is screen right)")
    T.ok(same(Core.FacingYaw(-1, 0), math.pi), "moving left: yaw pi")
    T.ok(same(Core.FacingYaw(0, 1), -math.pi / 2), "moving down: toward the camera")
end

tests["model sizes: real boxes measure, the placeholder cube and bad numbers don't"] = function(T)
    local Core = load(T)
    local w, d, h = Core.Extent(-1.5, -0.4, 0, 1.5, 0.4, 1.2)
    T.ok(near(w, 3) and near(d, 0.8) and near(h, 1.2), "a wolf-shaped box")
    local none, why = Core.Extent(-0.14, -0.14, 0, 0.14, 0.14, 0.28)
    T.eq(none, nil, "placeholder refused"); T.eq(why, "missing", "and named")
    T.eq(Core.Extent(0, 0, 0, 0 / 0, 1, 1), nil, "NaN")
    T.eq(Core.Extent(0, 0, 0, 1, 1, 0), nil, "flat")
    T.eq(Core.Extent(nil, 0, 0, 1, 1, 1), nil, "missing numbers")
    T.ok(near(Core.FitScale(3, 0.8, 1.2, 2.4), 0.8), "a long model shrinks to fit")
    T.eq(Core.FitScale(0.5, 0.5, 1, 2.4), 1, "a small one is never enlarged")
end

tests["statistics: average, 95th percentile, worst, fps"] = function(T)
    local Core = load(T)
    local st = Core.NewStats()
    for i = 1, 100 do Core.AddSample(st, i / 100, 10) end -- lua 0.01..1.00 ms, frames 10 ms
    local s = Core.Summarize(st)
    T.eq(s.frames, 100, "frames")
    T.eq(s.luaAvg, 0.505, "average")
    T.eq(s.luaP95, 0.95, "p95")
    T.eq(s.luaMax, 1, "worst")
    T.eq(s.frameAvg, 10, "frame average")
    T.eq(s.fps, 100, "fps")
    T.eq(Core.Summarize(Core.NewStats()).fps, 0, "empty stats don't divide by zero")
end

tests["a run steps through warm-up and measurement for every scenario"] = function(T)
    local Core = load(T)
    local list = {
        { kind = "baseline", n = 0, warm = 0.1, secs = 0.2 },
        { kind = "sprites", n = 2, warm = 0.1, secs = 0.2 },
    }
    local run = Core.NewRun(list)
    local events = {}
    for _ = 1, 100 do
        local e = Core.Step(run, 0.05, 0.25)
        if e then events[#events + 1] = e .. run.index end
        if e == "done" then break end
    end
    T.eq(table.concat(events, ","), "begin1,measure1,next2,measure2,done2", "event order")
    T.eq(#run.results, 2, "one summary per scenario")
    T.eq(run.results[2].kind, "sprites", "kind")
    T.eq(run.results[2].n, 2, "n")
    T.ok(run.results[1].frames >= 3 and run.results[1].frames <= 5, "about 4 frames measured")
    T.eq(run.results[1].luaAvg, 0.25, "lua time recorded")
    T.eq(Core.Step(run, 0.05, 0), nil, "a finished run stays finished")
end

tests["the real scenario list is well formed"] = function(T)
    local Core = load(T)
    local seconds = 0
    for i, sc in ipairs(Core.SCENARIOS) do
        T.ok(Core.LABELS[sc.kind], "label for " .. i)
        T.ok(sc.n >= 0 and sc.warm > 0 and sc.secs > 0, "numbers for " .. i)
        seconds = seconds + sc.warm + sc.secs
    end
    T.eq(Core.SCENARIOS[1].kind, "baseline", "baseline first, so deltas have a reference")
    T.ok(seconds <= 70, "about a minute, got " .. seconds)
end

tests["report lines compare frame time to the baseline"] = function(T)
    local Core = load(T)
    local text = Core.FormatRun({ date = "d", zone = "z", screen = "s", uiScale = 1, results = {
        { kind = "baseline", n = 0, luaAvg = 0, luaP95 = 0, frameAvg = 16, frameP95 = 17, fps = 62.5 },
        { kind = "modelscene", n = 20, luaAvg = 0.5, luaP95 = 0.7, frameAvg = 18.5, frameP95 = 20, fps = 54,
            loaded = 19 },
    } })
    T.ok(text:find("3D, one shared scene x20", 1, true), "label and count")
    T.ok(text:find("(+2.5)", 1, true), "delta against baseline")
    T.ok(text:find("loaded 19/20", 1, true), "models loaded")
end

tests["paging clamps and reports ranges"] = function(T)
    local Core = load(T)
    local page, pages, first, last = Core.Page(25, 10, 9)
    T.eq(page, 3, "clamped high"); T.eq(pages, 3, "pages"); T.eq(first, 21, "first"); T.eq(last, 25, "last")
    page, pages, first, last = Core.Page(0, 10, -4)
    T.eq(page, 1, "clamped low"); T.eq(pages, 1, "one empty page"); T.ok(last < first, "empty range")
end

tests["trim keeps the newest entries; sorted keys mix numbers and strings"] = function(T)
    local Core = load(T)
    local list = Core.Trim({ 1, 2, 3, 4, 5 }, 3)
    T.eq(table.concat(list, ","), "3,4,5", "newest kept")
    T.eq(table.concat(Core.SortedKeys({ b = 1, [10] = 1, a = 1, [2] = 1 }), ","), "2,10,a,b", "numbers first")
end

tests["asset list entries are complete and unique"] = function(T)
    local _, List = load(T)
    local seen = {}
    for i, e in ipairs(List.icons) do
        T.ok(type(e.name) == "string" and type(e.file) == "string", "icon " .. i)
        T.ok(not seen[e.file], "duplicate icon " .. e.file)
        seen[e.file] = true
    end
    local npcs = {}
    for i, e in ipairs(List.creatures) do
        T.ok(type(e.npc) == "number" and type(e.name) == "string" and type(e.zone) == "string", "creature " .. i)
        T.ok(not npcs[e.npc], "duplicate NPC " .. e.npc)
        npcs[e.npc] = true
    end
    T.ok(#List.benchDisplays >= 1 and #List.benchIcons >= 1, "bench assets")
end

return tests
