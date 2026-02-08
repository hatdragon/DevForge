local _, DF = ...

DF.EventMonitorLog = {}

local Log = DF.EventMonitorLog

local MAX_ENTRIES = 2000
local DRAIN_PER_FRAME = 25  -- max queued events to process per frame
local entries = {}
local paused = false
local filters = {}       -- event name -> true (whitelist). empty = capture all
local blacklist = {}     -- event name -> true (never capture)
local entryId = 0
local onNewEntry = nil   -- callback(entry)

-- Frame-batching: queue raw event data, process expensive serialization across frames
local pendingQueue = {}  -- { { event, timestamp, numArgs, arg1, arg2, ... }, ... }
local drainFrame = nil   -- OnUpdate frame for processing queue

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
    if DF.EventIndex then
        DF.EventIndex:LoadDiscovered()
    end
end

function Log:SetOnNewEntry(callback)
    onNewEntry = callback
end

-- Process a single queued event into a full entry (expensive: PrettyPrint, SecretGuard)
local function ProcessQueuedEvent(queued)
    local event = queued.event
    local numArgs = queued.numArgs

    local args = {}
    for i = 1, numArgs do
        local val = queued[i]
        if DF.SecretGuard:IsSecret(val) then
            args[i] = { display = DF.Colors.secret .. "[secret]|r", raw = nil }
        else
            args[i] = { display = DF.Util:PrettyPrint(val, 0), raw = val }
        end
    end

    local entry = {
        id = queued.id,
        event = event,
        time = queued.time,
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
end

-- OnUpdate handler: drain pending queue in batches
local function DrainQueue()
    if #pendingQueue == 0 then
        if drainFrame then drainFrame:Hide() end
        return
    end

    local count = math.min(#pendingQueue, DRAIN_PER_FRAME)
    for i = 1, count do
        ProcessQueuedEvent(pendingQueue[i])
    end

    -- Shift remaining items (remove processed from front)
    if count == #pendingQueue then
        wipe(pendingQueue)
        if drainFrame then drainFrame:Hide() end
    else
        local remaining = #pendingQueue - count
        for i = 1, remaining do
            pendingQueue[i] = pendingQueue[i + count]
        end
        for i = remaining + 1, remaining + count do
            pendingQueue[i] = nil
        end
    end
end

local function EnsureDrainFrame()
    if not drainFrame then
        drainFrame = CreateFrame("Frame")
        drainFrame:SetScript("OnUpdate", DrainQueue)
    end
    drainFrame:Show()
end

-- Add an event to the log. Returns true if the event was queued for capture.
function Log:Push(event, timestamp, ...)
    -- Auto-discover unknown events (before filtering, so blacklisted ones get discovered too)
    if DF.EventIndex and not DF.EventIndex:IsKnown(event) then
        DF.EventIndex:RegisterDiscovered(event)
    end

    if paused then return false end

    -- Blacklist check
    if blacklist[event] then return false end

    -- Whitelist check (empty = capture all)
    if next(filters) and not filters[event] then return false end

    -- Lightweight capture: assign ID and timestamp now, defer expensive serialization
    entryId = entryId + 1

    local numArgs = math.min(select("#", ...), 64)
    local queued = {
        id = entryId,
        event = event,
        time = timestamp or GetTime(),
        numArgs = numArgs,
    }
    -- Store raw arg values by index (cheap table insert)
    for i = 1, numArgs do
        queued[i] = select(i, ...)
    end

    pendingQueue[#pendingQueue + 1] = queued
    EnsureDrainFrame()

    return true
end

function Log:GetEntries()
    return entries
end

function Log:GetCount()
    return #entries + #pendingQueue
end

function Log:Clear()
    wipe(entries)
    wipe(pendingQueue)
    if drainFrame then drainFrame:Hide() end
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

-- Save blacklist + discovered events on logout
DF.EventBus:On("DF_PLAYER_LOGOUT", function()
    DF.EventMonitorLog:SaveBlacklist()
    if DF.EventIndex then
        DF.EventIndex:SaveDiscovered()
    end
end)
