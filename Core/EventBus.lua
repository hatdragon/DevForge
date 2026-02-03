local _, DF = ...

DF.EventBus = {}
DF.ErrorLog = DF.ErrorLog or {}

local EventBus = DF.EventBus
local callbacks = {}

-- Register a callback for an event
function EventBus:On(event, callback, owner)
    if not event or not callback then return end
    if not callbacks[event] then
        callbacks[event] = {}
    end
    callbacks[event][#callbacks[event] + 1] = {
        fn = callback,
        owner = owner,
    }
end

-- Unregister all callbacks for an owner
function EventBus:Off(event, owner)
    if not callbacks[event] then return end
    local filtered = {}
    for _, entry in ipairs(callbacks[event]) do
        if entry.owner ~= owner then
            filtered[#filtered + 1] = entry
        end
    end
    callbacks[event] = filtered
end

-- Unregister a specific callback function
function EventBus:OffFunc(event, fn)
    if not callbacks[event] then return end
    local filtered = {}
    for _, entry in ipairs(callbacks[event]) do
        if entry.fn ~= fn then
            filtered[#filtered + 1] = entry
        end
    end
    callbacks[event] = filtered
end

-- Fire an event, calling all registered callbacks
function EventBus:Fire(event, ...)
    if not callbacks[event] then return end
    -- Copy list so modifications during iteration are safe
    local list = { unpack(callbacks[event]) }
    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.fn, ...)
        if not ok then
            local errMsg = tostring(err)
            -- Log to error buffer
            DF.ErrorLog[#DF.ErrorLog + 1] = {
                source = "EventBus",
                event = event,
                err = errMsg,
                time = GetTime and GetTime() or 0,
            }
            -- Trim error log
            while #DF.ErrorLog > 200 do
                table.remove(DF.ErrorLog, 1)
            end
            -- Print unless this IS an error event (avoid recursion)
            if event ~= "ERROR" then
                pcall(print, "|cFFFF4444DevForge EventBus error [" .. event .. "]:|r " .. errMsg)
            end
        end
    end
end

-- Check if an event has any listeners
function EventBus:HasListeners(event)
    return callbacks[event] and #callbacks[event] > 0
end

-- Clear all callbacks (for testing/reset)
function EventBus:Reset()
    wipe(callbacks)
end
