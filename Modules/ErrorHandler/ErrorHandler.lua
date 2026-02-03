local _, DF = ...

DF.ErrorHandler = {}

local Handler = DF.ErrorHandler

local MAX_ERRORS = 500
local MAX_PERSIST = 200
local FLOOD_LIMIT = 10 -- max errors per second
local FLOOD_WINDOW = 1 -- seconds

local errors = {}
local errorIndex = {} -- dedup key -> error object
local nextId = 1
local sessionId = 0
local onNewError = nil
local floodCount = 0
local floodReset = 0
local paused = false

local function SanitizeMessage(msg)
    msg = tostring(msg or "")
    -- Strip color codes
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Strip path noise (keep just filename:line)
    return msg
end

local function DedupKey(message, stack)
    -- Use first line of message + first line of stack for dedup
    local msgKey = (message or ""):match("^([^\n]+)") or message or ""
    local stackKey = ""
    if stack then
        stackKey = stack:match("^([^\n]+)") or ""
    end
    return msgKey .. "\n" .. stackKey
end

local function TrimErrors()
    while #errors > MAX_ERRORS do
        local removed = table.remove(errors, 1)
        if removed then
            local key = DedupKey(removed.message, removed.stack)
            if errorIndex[key] == removed then
                errorIndex[key] = nil
            end
        end
    end
end

local function ProcessError(message, stack, locals, errType)
    if paused then return end

    -- Flood protection
    local now = GetTime()
    if now - floodReset >= FLOOD_WINDOW then
        floodCount = 0
        floodReset = now
    end
    floodCount = floodCount + 1
    if floodCount > FLOOD_LIMIT then return end

    message = SanitizeMessage(message)
    local key = DedupKey(message, stack)

    -- Dedup: increment counter if we've seen this before
    local existing = errorIndex[key]
    if existing then
        existing.counter = existing.counter + 1
        existing.time = date("%Y/%m/%d %H:%M:%S")
        existing.timestamp = now
        if onNewError then onNewError(existing, true) end
        return
    end

    -- Strip |K sequences from locals
    if locals then
        locals = locals:gsub("|K[^|]*|k", "<filtered>")
    end

    local err = {
        id = nextId,
        message = message,
        stack = stack or "",
        locals = locals or "",
        time = date("%Y/%m/%d %H:%M:%S"),
        timestamp = now,
        counter = 1,
        session = sessionId,
        type = errType or "error",
    }

    nextId = nextId + 1
    errors[#errors + 1] = err
    errorIndex[key] = err
    TrimErrors()

    if onNewError then onNewError(err, false) end
end

-- BugGrabber callback handler
local function OnBugGrabbed(_, bugObj)
    if not bugObj then return end
    ProcessError(
        bugObj.message,
        bugObj.stack,
        bugObj.locals,
        bugObj.type or "error"
    )
end

-- Self-hook error handler (used when BugGrabber is absent)
local function OnLuaError(message)
    local stack = debugstack(3)
    local locals = debuglocals(3)
    ProcessError(message, stack, locals, "error")
end

function Handler:Init()
    if self._initialized then return end
    self._initialized = true

    -- Increment session
    if DevForgeDB then
        DevForgeDB.errorSessionId = (DevForgeDB.errorSessionId or 0) + 1
        sessionId = DevForgeDB.errorSessionId
    end

    -- Restore persisted errors
    if DevForgeDB and DevForgeDB.errors then
        for _, err in ipairs(DevForgeDB.errors) do
            errors[#errors + 1] = err
            local key = DedupKey(err.message, err.stack)
            errorIndex[key] = err
            if err.id >= nextId then
                nextId = err.id + 1
            end
        end
    end

    -- Hook error capture
    if _G.BugGrabber then
        -- BugGrabber is present: use its callback system
        if BugGrabber.RegisterCallback then
            BugGrabber:RegisterCallback("BugGrabber_BugGrabbed", OnBugGrabbed)
        elseif BugGrabber.RegisterAddonActionCallback then
            BugGrabber.RegisterAddonActionCallback(OnBugGrabbed)
        end
    else
        -- Self-hook using Blizzard 12.x API
        if _G.AddLuaErrorHandler then
            AddLuaErrorHandler(OnLuaError)
        elseif _G.seterrorhandler then
            -- Fallback: wrap existing error handler
            local oldHandler = geterrorhandler()
            seterrorhandler(function(msg)
                OnLuaError(msg)
                if oldHandler then
                    return oldHandler(msg)
                end
            end)
        end
    end

    -- Register for LUA_WARNING events
    local warningFrame = CreateFrame("Frame")
    warningFrame:RegisterEvent("LUA_WARNING")
    warningFrame:SetScript("OnEvent", function(_, _, warnType, warnMessage)
        ProcessError(warnMessage, nil, nil, "warning")
    end)
end

function Handler:GetErrors()
    return errors
end

function Handler:GetCount()
    return #errors
end

function Handler:Clear()
    wipe(errors)
    wipe(errorIndex)
    if DevForgeDB then
        DevForgeDB.errors = {}
    end
end

function Handler:GetError(id)
    for _, err in ipairs(errors) do
        if err.id == id then return err end
    end
    return nil
end

function Handler:SetOnNewError(cb)
    onNewError = cb
end

-- Programmatically report an error (e.g. from Console pcall results)
function Handler:Report(message, stack, errType)
    if not self._initialized then self:Init() end
    ProcessError(message, stack, nil, errType or "error")
end

function Handler:GetSessionId()
    return sessionId
end

function Handler:IsPaused()
    return paused
end

function Handler:SetPaused(val)
    paused = val
end

function Handler:Save()
    if not DevForgeDB then return end
    -- Persist last MAX_PERSIST errors
    local save = {}
    local start = math.max(1, #errors - MAX_PERSIST + 1)
    for i = start, #errors do
        save[#save + 1] = errors[i]
    end
    DevForgeDB.errors = save
end

-- Persist on logout
DF.EventBus:On("DF_PLAYER_LOGOUT", function()
    DF.ErrorHandler:Save()
end)
