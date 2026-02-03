local _, DF = ...

DF.SecretGuard = {}

local SecretGuard = DF.SecretGuard

-- issecretvalue() and canaccessvalue() are WoW 12.0+ (Midnight) API.
-- On older clients these globals don't exist; we degrade gracefully.

-- Check if a value is secret (12.x API)
function SecretGuard:IsSecret(value)
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        return ok and result == true
    end
    return false
end

-- Check if we can access a value (12.x API)
function SecretGuard:CanAccess(value)
    if type(canaccessvalue) == "function" then
        local ok, result = pcall(canaccessvalue, value)
        return ok and result ~= false
    end
    -- Pre-12.x: assume accessible
    return true
end

-- Safely get a property from a frame, returning value and success
-- Returns: value, success (bool), errorReason (string or nil)
function SecretGuard:SafeGet(obj, method, ...)
    if not obj then
        return nil, false, "nil object"
    end

    local fn = obj[method]
    if not fn then
        return nil, false, "no method: " .. tostring(method)
    end

    if not self:CanAccess(fn) then
        return nil, false, "access denied"
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, false, tostring(result)
    end

    if self:IsSecret(result) then
        return nil, true, "secret"
    end

    return result, true, nil
end

-- Safely call a function, handling secrets
function SecretGuard:SafeCall(fn, ...)
    if not fn then
        return nil, false, "nil function"
    end

    if not self:CanAccess(fn) then
        return nil, false, "access denied"
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        return nil, false, tostring(result)
    end

    if self:IsSecret(result) then
        return nil, true, "secret"
    end

    return result, true, nil
end

-- Format a value for display, showing [secret] for restricted values
function SecretGuard:FormatValue(value)
    if self:IsSecret(value) then
        return DF.Colors.secret .. "[secret]|r"
    end
    return nil -- Caller should format normally
end
