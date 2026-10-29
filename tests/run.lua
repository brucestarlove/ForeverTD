-- run.lua - zero-dependency test runner for Lua 5.1.  Usage (from the repository folder):  lua tests/run.lua
-- Each test file returns a table of { ["name"] = function(T) ... end }. Exit code 0 = all passed.
local base = (arg and arg[0] or ""):match("^(.-)[\\/]?tests[\\/]run%.lua$") or "."
if base == "" then base = "." end
package.path = base .. "/tests/?.lua;" .. package.path

local T = {}
function T.eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "eq", tostring(expected), tostring(actual)), 2)
    end
end
function T.ok(value, label)
    if not value then error((label or "ok") .. ": expected a true value", 2) end
end
function T.raises(fn, label)
    if pcall(fn) then error((label or "raises") .. ": expected an error", 2) end
end
-- Deterministic serialization (sorted keys) for comparing plain-data tables.
function T.dump(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. T.dump(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
T.base = base

local files = { "test_engine", "test_meta", "test_sim", "test_shell", "test_devcore", "test_dev", "test_tools" }
local passed, failed = 0, 0
for _, name in ipairs(files) do
    local suite = dofile(base .. "/tests/" .. name .. ".lua")
    local names = {}
    for testName in pairs(suite) do names[#names + 1] = testName end
    table.sort(names)
    for _, testName in ipairs(names) do
        local ok, err = pcall(suite[testName], T)
        if ok then
            passed = passed + 1
            print("  ok   " .. name .. " :: " .. testName)
        else
            failed = failed + 1
            print("  FAIL " .. name .. " :: " .. testName .. "\n       " .. tostring(err))
        end
    end
end
print(string.format("%d passed, %d failed (%s)", passed, failed, _VERSION))
os.exit(failed == 0 and 0 or 1)
