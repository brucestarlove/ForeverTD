-- tools/package.lua - the players' copy. From the repository folder:   lua tools/package.lua [version]
-- builds dist/ForeverTD/ from the files the TOC lists, as the BigWigs packager does for a release (.pkgmeta,
-- .github/workflows/release.yml): the TOC's #@debug@ blocks (the repository's version and the dev tools) left out,
-- its #@non-debug@ blocks uncommented, and @project-version@ set to the version given (or the repository's own).
-- Media\probe.* aren't listed, so they stay out too. Then it zips dist/ForeverTD as dist/ForeverTD-<version>.zip
-- (.NET's ZipFile, through PowerShell), for a clean-install test before a release. Releases themselves are built by
-- the packager when a tag is pushed. The repository's own TOC keeps the dev tools for testing.
local M = {}

local root = ((arg and arg[0] or ""):match("^(.-)[\\/]?tools[\\/]package%.lua$") or ".")
if root == "" then root = "." end
local windows = package.config:sub(1, 1) == "\\"

-- The release TOC and the files it lists, from the repository TOC's text: { toc = text, files = { "Content.lua",
-- "Campaigns\\Horde.lua", ... } } (paths as the TOC writes them). The TOC's markers work as the BigWigs packager's
-- do: lines from #@debug@ to #@end-debug@ go, and lines between #@non-debug@ and #@end-non-debug@ lose their
-- leading "# ". Without a version, the release keeps the repository's (its "## Version:" line).
function M.Plan(tocText, version)
    local text = tocText:gsub("\r\n", "\n")
    version = version or ("\n" .. text):match("\n## Version: ([^\n]+)")
    local lines, files, block = {}, {}, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local marker = line:match("^#@([%w%-]+)@")
        if marker == "debug" or marker == "non-debug" then
            block, line = marker, nil
        elseif marker == "end-debug" or marker == "end-non-debug" then
            block, line = nil, nil
        elseif block == "debug" then
            line = nil
        else
            if block == "non-debug" then line = line:gsub("^#[ \t]+", "") end
            line = line:gsub("@project%-version@", function() return version or "" end)
            if line ~= "" and not line:find("^#") then files[#files + 1] = line end
        end
        if line then lines[#lines + 1] = line end
    end
    while lines[#lines] == "" do lines[#lines] = nil end
    return { toc = table.concat(lines, "\n") .. "\n", files = files }
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function Write(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end

local function MakeDir(dir)
    if windows then
        os.execute('if not exist "' .. dir:gsub("/", "\\") .. '" mkdir "' .. dir:gsub("/", "\\") .. '"')
    else
        os.execute('mkdir -p "' .. dir .. '"')
    end
end

-- Copies the release into `out`/ForeverTD (made as needed), with the repository's LICENSE beside the TOC as the
-- packager ships it. Fails, before writing the TOC, if a listed file is missing. Returns the plan.
function M.Build(base, version, out)
    local plan = M.Plan(Read(base .. "/ForeverTD/ForeverTD.toc"), version)
    local dest = out .. "/ForeverTD"
    MakeDir(dest)
    for _, file in ipairs(plan.files) do
        local rel = file:gsub("\\", "/")
        local src = base .. "/ForeverTD/" .. rel
        local f = io.open(src, "rb")
        if not f then error("the TOC lists " .. file .. " but there's no " .. src) end
        f:close()
        local dir = rel:match("^(.*)/[^/]*$")
        if dir then MakeDir(dest .. "/" .. dir) end
        Write(dest .. "/" .. rel, Read(src))
    end
    local license = io.open(base .. "/LICENSE", "rb")
    if license then
        license:close()
        Write(dest .. "/LICENSE", Read(base .. "/LICENSE"))
    end
    Write(dest .. "/ForeverTD.toc", plan.toc)
    return plan
end

local args = { ... }
if args[1] == "--lib" then return M end

local version = args[1]
local plan = M.Build(root, version, root .. "/dist")
local toc = plan.toc:match("## Version: ([^\n]+)")
local zip = root .. "/dist/ForeverTD-" .. toc .. ".zip"
print(string.format("dist/ForeverTD: %d files and the TOC (version %s), without the dev tools", #plan.files, toc))
-- Every entry named with forward slashes, as zip tools and addon sites expect (Windows PowerShell's own zipping
-- writes backslashes).
local ZIP = [[
param($src, $dest)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$src = (Resolve-Path $src).Path
$dest = Join-Path (Resolve-Path (Split-Path $dest)).Path (Split-Path $dest -Leaf)
if (Test-Path $dest) { Remove-Item $dest }
$zip = [System.IO.Compression.ZipFile]::Open($dest, 'Create')
try {
    Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
        $name = 'ForeverTD/' + $_.FullName.Substring($src.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $name, 'Optimal')
    }
} finally { $zip.Dispose() }
]]
if windows then
    local script = root .. "/dist/zip.ps1"
    Write(script, ZIP)
    local ok = os.execute('powershell -NoProfile -ExecutionPolicy Bypass -File "' .. script .. '" "' .. root
        .. '/dist/ForeverTD" "' .. zip .. '"')
    os.remove(script)
    print((ok == 0 or ok == true) and ("zipped: " .. zip) or "zipping failed")
else
    print("zip dist/ForeverTD yourself (this script zips with PowerShell on Windows)")
end
