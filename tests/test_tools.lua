-- tools/dev-report.lua: reads a SavedVariables file in a sandbox and prints what the dev tools saved.
local stub = require("wowstub")

local function load(T)
    local M = assert(loadfile(T.base .. "/tools/dev-report.lua"))("--lib")
    local ns = {}
    stub.load(T.base .. "/ForeverTD/Dev/DevCore.lua", "ForeverTD", ns, stub.env())
    return M, ns.DevCore
end

local tests = {}

tests["reads a SavedVariables file and reports runs, probe, stars and failed checks"] = function(T)
    local M, Core = load(T)
    local db = assert(M.LoadSaved(T.base .. "/tests/fixtures/ForeverTD.lua"))
    local text = table.concat(M.Lines(db, Core), "\n")
    T.ok(text:find("2D sprites x500", 1, true), "bench line")
    T.ok(text:find("== Probe", 1, true) and text:find("toc: 16001", 1, true), "probe facts")
    T.ok(text:find("* npc:448  Hogger (boss)  (resolved: 123456)", 1, true), "starred creature")
    T.ok(text:find("1 loaded, 1 failed: Interface\\Icons\\Nope", 1, true), "failed icon listed")
end

tests["reports the player's progress: levels by campaign, abandoned runs, the level in progress"] = function(T)
    local M = load(T)
    local db = assert(M.LoadSaved(T.base .. "/tests/fixtures/ForeverTD-progress.lua"))
    local sim = assert(loadfile(T.base .. "/tools/sim.lua"))("--lib")
    local text = table.concat(M.Progress(db, sim.Load(T.base)), "\n")
    T.ok(text:find("runs started 5, paid 3, abandoned 1 (+1 in progress)", 1, true), "runs: " .. text)
    T.ok(text:find("The Horde: 1 Valley of Trials 1* (1/1); 2 Razor Hill 3*, Heroic 2 (2/3)", 1, true),
        "the Horde's levels in order, with Heroic stars")
    T.ok(text:find("The Alliance: 1 Northshire Valley 2* (1/1)", 1, true), "each campaign on its own line")
    T.ok(text:find("research: earthshaker 1, headhunter 2; supplies: gold 1", 1, true), "research and supplies")
    T.ok(text:find("in progress: run5 Sen'jin Village, normal: wave 4, lives 18/20, gold 120, towers: headhunter r3, "
        .. "witchdoctor r1", 1, true), "the level in progress")
    T.ok(text:find("auto waves on, scale 1.4", 1, true), "settings")
end

tests["a SavedVariables file can't reach the machine"] = function(T)
    local M = load(T)
    local db, err = M.LoadSaved(T.base .. "/tests/fixtures/escape-attempt.lua")
    T.eq(db, nil, "refused")
    T.ok(tostring(err):find("os", 1, true), "because os doesn't exist in the sandbox: " .. tostring(err))
end

tests["the players' copy: the TOC's files without the dev tools, the version set, every file copied"] = function(T)
    local P = assert(loadfile(T.base .. "/tools/package.lua"))("--lib")
    local f = assert(io.open(T.base .. "/ForeverTD/ForeverTD.toc", "rb"))
    local toc = f:read("*a")
    f:close()
    local plan = P.Plan(toc, "1.2.3")
    T.ok(not plan.toc:find("Dev"), "no dev tools in the TOC")
    T.ok(("\n" .. plan.toc):find("\n## Version: 1.2.3\n", 1, true), "the version set, uncommented")
    local _, versions = plan.toc:gsub("## Version:", "")
    T.eq(versions, 1, "one version line: the repository's left with its #@debug@ block")
    T.ok(not plan.toc:find("#@", 1, true) and not plan.toc:find("@project-version@", 1, true), "no markers left")
    T.ok(plan.toc:find("## SavedVariables: ForeverTDDB\n", 1, true), "the rest of the header as it was")
    T.ok(plan.toc:find("## AddonCompartmentFunc: ", 1, true), "the minimap's addon menu entry")
    T.eq(plan.files[1] .. " ... " .. plan.files[#plan.files], "Content.lua ... Shell.lua", "the game's files in order")
    for _, file in ipairs(plan.files) do T.ok(not file:find("^Dev"), file .. ": not a dev file") end
    local repoVersion = toc:match("\n## Version: ([^\r\n]+)")
    T.ok(repoVersion, "the repository's TOC has a version (in its #@debug@ block)")
    T.ok(("\n" .. P.Plan(toc).toc):find("\n## Version: " .. repoVersion .. "\n", 1, true),
        "no version given: the repository's")
    local out = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/ForeverTD-package-test"
    P.Build(T.base, "1.2.3", out)
    for _, file in ipairs(plan.files) do
        local h = io.open(out .. "/ForeverTD/" .. file:gsub("\\", "/"), "rb")
        T.ok(h ~= nil, file .. " copied")
        if h then h:close() end
    end
    f = assert(io.open(out .. "/ForeverTD/ForeverTD.toc", "rb"))
    T.eq(f:read("*a"), plan.toc, "and the players' TOC beside them")
    f:close()
    f = io.open(out .. "/ForeverTD/LICENSE", "rb")
    T.ok(f and f:read("*a"):find("MIT License", 1, true), "the license beside them, as the release zip has it")
    if f then f:close() end
end

return tests
