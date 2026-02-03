local _, DF = ...

DF.EventMonitorLog = {}

local Log = DF.EventMonitorLog

local MAX_ENTRIES = 2000
local entries = {}
local paused = false
local filters = {}       -- event name -> true (whitelist). empty = capture all
local blacklist = {}     -- event name -> true (never capture)
local entryId = 0
local onNewEntry = nil   -- callback(entry)

-- High-frequency events blacklisted by default (same approach as Blizzard_EventTrace)
local DEFAULT_BLACKLIST = {
    "CURSOR_CHANGED", "MODIFIER_STATE_CHANGED",
    "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
    "PLAYER_STARTED_TURNING", "PLAYER_STOPPED_TURNING",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "UPDATE_MOUSEOVER_UNIT",
}

function Log:Init()
    for _, event in ipairs(DEFAULT_BLACKLIST) do
        blacklist[event] = true
    end
    self:LoadBlacklist()
end

function Log:SetOnNewEntry(callback)
    onNewEntry = callback
end

-- Add an event to the log. Returns true if the event was actually captured.
function Log:Push(event, timestamp, ...)
    if paused then return false end

    -- Blacklist check
    if blacklist[event] then return false end

    -- Whitelist check (empty = capture all)
    if next(filters) and not filters[event] then return false end

    entryId = entryId + 1

    local args = {}
    local numArgs = math.min(select("#", ...), 64)  -- cap for safety
    for i = 1, numArgs do
        local val = select(i, ...)
        -- Secret value check
        if DF.SecretGuard:IsSecret(val) then
            args[i] = { display = DF.Colors.secret .. "[secret]|r", raw = nil }
        else
            args[i] = { display = DF.Util:PrettyPrint(val, 0), raw = val }
        end
    end

    local entry = {
        id = entryId,
        event = event,
        time = timestamp or GetTime(),
        args = args,
        numArgs = numArgs,
    }

    entries[#entries + 1] = entry

    -- Trim
    while #entries > MAX_ENTRIES do
        table.remove(entries, 1)
    end

    if onNewEntry then
        onNewEntry(entry)
    end

    return true
end

function Log:GetEntries()
    return entries
end

function Log:GetCount()
    return #entries
end

function Log:Clear()
    wipe(entries)
    entryId = 0
end

function Log:SetPaused(state)
    paused = state
end

function Log:IsPaused()
    return paused
end

-- Filter management
function Log:SetFilter(event, enabled)
    if enabled then
        filters[event] = true
    else
        filters[event] = nil
    end
end

function Log:ClearFilters()
    wipe(filters)
end

function Log:GetFilters()
    return filters
end

function Log:SetBlacklisted(event, state)
    if state then
        blacklist[event] = true
    else
        blacklist[event] = nil
    end
end

function Log:IsBlacklisted(event)
    return blacklist[event] or false
end

-- Bulk blacklist access for filter panel
function Log:GetBlacklistTable()
    local copy = {}
    for event, val in pairs(blacklist) do
        copy[event] = val
    end
    return copy
end

function Log:SetBlacklistFromTable(tbl)
    wipe(blacklist)
    if tbl then
        for event, val in pairs(tbl) do
            if val then
                blacklist[event] = true
            end
        end
    end
end

-- Persistence
function Log:SaveBlacklist()
    if not DevForgeDB then return end
    local save = {}
    for event, val in pairs(blacklist) do
        save[event] = val or nil
    end
    DevForgeDB.eventBlacklist = save
end

function Log:LoadBlacklist()
    if not DevForgeDB or not DevForgeDB.eventBlacklist then return end
    local saved = DevForgeDB.eventBlacklist
    if next(saved) then
        wipe(blacklist)
        for event, val in pairs(saved) do
            if val then
                blacklist[event] = true
            end
        end
    end
end

-- Format an entry for display
function Log:FormatEntry(entry)
    local timeStr = DF.Colors.dim .. string.format("%.3f", entry.time) .. "|r"
    local eventStr = DF.Colors.keyword .. entry.event .. "|r"

    local argParts = {}
    for i = 1, entry.numArgs do
        if entry.args[i] then
            argParts[#argParts + 1] = entry.args[i].display
        end
    end

    local argStr = ""
    if #argParts > 0 then
        argStr = " " .. DF.Colors.dim .. ">>|r " .. table.concat(argParts, ", ")
    end

    return timeStr .. "  " .. eventStr .. argStr
end

-- Save blacklist on logout
DF.EventBus:On("DF_PLAYER_LOGOUT", function()
    DF.EventMonitorLog:SaveBlacklist()
end)
