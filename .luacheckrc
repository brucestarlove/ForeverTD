-- luacheck config (run from this folder:  luacheck ForeverTD tests tools).
-- Catches typos and accidental globals before the client does. Add each WoW API you start using to read_globals;
-- the list is deliberately short so an unknown name stands out.
std = "lua51"
max_line_length = 120
codes = true

-- Globals this addon is allowed to create.
globals = {
    "ForeverTDDB",              -- SavedVariables (TOC)
    "SLASH_FOREVERTD1", "SLASH_FOREVERTD2",
    "SlashCmdList",             -- written to, so listed here rather than read_globals
    "ForeverTD_OnAddonCompartmentClick", "ForeverTD_OnAddonCompartmentEnter", "ForeverTD_OnAddonCompartmentLeave",
}

-- WoW API the addon may read.
read_globals = {
    "CreateFrame", "UIParent", "UISpecialFrames", "GetTime", "GetServerTime", "GetCursorPosition",
    "InCombatLockdown", "UnitAffectingCombat", "C_Timer", "C_ChatInfo", "issecretvalue", "tinsert", "tremove",
    "wipe", "strsplit", "strjoin", "strtrim", "bit", "GetBuildInfo", "UnitName", "PlaySound", "SOUNDKIT",
    "Enum", "IsShiftKeyDown", "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "debugprofilestop", "date", "time",
    "GetFileIDFromPath", "UnitFactionGroup", "geterrorhandler",
    -- dev tools
    "GameTooltip", "GetFramerate", "GetPhysicalScreenSize", "GetRealZoneText", "C_Map", "C_AddOns",
    "C_AddOnProfiler", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "ReloadUI",
}

files["tests/"] = {
    std = "lua51",
    globals = {},
    read_globals = {},
    ignore = { "212" }, -- unused arguments (test signatures)
}

files["tests/fixtures/"] = { globals = { "ForeverTDDB" }, ignore = { "631" } } -- SavedVariables-shaped data

files["tools/"] = { std = "lua51", globals = {}, read_globals = { "arg" } } -- command-line scripts, not addon code
