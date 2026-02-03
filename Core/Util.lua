local _, DF = ...

DF.Util = {}

local Util = DF.Util
local SecretGuard = DF.SecretGuard

-- String trim
function Util:Trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

-- String split
function Util:Split(s, sep)
    local parts = {}
    local pattern = "([^" .. (sep or ",") .. "]+)"
    for part in s:gmatch(pattern) do
        parts[#parts + 1] = Util:Trim(part)
    end
    return parts
end

-- String starts with
function Util:StartsWith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

-- String contains (case-insensitive)
function Util:ContainsCI(s, query)
    return s:lower():find(query:lower(), 1, true) ~= nil
end

-- Deep copy a table
function Util:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[Util:DeepCopy(k)] = Util:DeepCopy(v)
    end
    return setmetatable(copy, getmetatable(orig))
end

-- Safe pcall wrapper that returns formatted error
function Util:SafeCall(fn, ...)
    local results = { pcall(fn, ...) }
    if results[1] then
        return true, unpack(results, 2)
    else
        return false, tostring(results[2])
    end
end

-- Pretty-print a value with type coloring
function Util:PrettyPrint(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    -- Secret check
    local secretFmt = SecretGuard:FormatValue(value)
    if secretFmt then return secretFmt end

    local t = type(value)

    if value == nil then
        return DF.Colors.nilVal .. "nil|r"
    elseif t == "boolean" then
        if value then
            return DF.Colors.boolTrue .. "true|r"
        else
            return DF.Colors.boolFalse .. "false|r"
        end
    elseif t == "number" then
        return DF.Colors.number .. tostring(value) .. "|r"
    elseif t == "string" then
        local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
        return DF.Colors.string .. '"' .. escaped .. '"|r'
    elseif t == "function" then
        return DF.Colors.func .. tostring(value) .. "|r"
    elseif t == "userdata" then
        -- Try to get name for WoW frames
        local name
        local ok, result = pcall(function() return value.GetName and value:GetName() end)
        if ok and result then
            name = result
        end
        if name then
            return DF.Colors.tableRef .. "<userdata: " .. name .. ">|r"
        end
        return DF.Colors.tableRef .. tostring(value) .. "|r"
    elseif t == "table" then
        if depth >= DF.PRETTY_DEPTH then
            return DF.Colors.tableRef .. "{...}|r"
        end

        if seen[value] then
            return DF.Colors.tableRef .. "{<circular>}|r"
        end
        seen[value] = true

        local parts = {}
        local indent = string.rep("  ", depth + 1)
        local closingIndent = string.rep("  ", depth)
        local count = 0
        local maxEntries = 30

        -- Array part
        local arrayLen = #value
        for i = 1, arrayLen do
            if count >= maxEntries then
                parts[#parts + 1] = indent .. DF.Colors.dim .. "... (" .. (Util:TableCount(value) - count) .. " more)|r"
                break
            end
            parts[#parts + 1] = indent .. Util:PrettyPrint(value[i], depth + 1, seen)
            count = count + 1
        end

        -- Hash part
        for k, v in pairs(value) do
            if type(k) ~= "number" or k < 1 or k > arrayLen or k ~= math.floor(k) then
                if count >= maxEntries then
                    parts[#parts + 1] = indent .. DF.Colors.dim .. "... (" .. (Util:TableCount(value) - count) .. " more)|r"
                    break
                end
                local keyStr
                if type(k) == "string" then
                    keyStr = DF.Colors.text .. k .. "|r"
                else
                    keyStr = "[" .. Util:PrettyPrint(k, depth + 1, seen) .. "]"
                end
                parts[#parts + 1] = indent .. keyStr .. " = " .. Util:PrettyPrint(v, depth + 1, seen)
                count = count + 1
            end
        end

        seen[value] = nil

        if #parts == 0 then
            return DF.Colors.tableRef .. "{}|r"
        end

        return DF.Colors.tableRef .. "{|r\n" .. table.concat(parts, ",\n") .. "\n" .. closingIndent .. DF.Colors.tableRef .. "}|r"
    end

    return tostring(value)
end

-- Count all entries in a table
function Util:TableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Clamp a number
function Util:Clamp(val, minVal, maxVal)
    return math.max(minVal, math.min(maxVal, val))
end

-- Escape WoW color codes for display
function Util:EscapeColors(s)
    return s:gsub("|", "||")
end

-- Strip WoW color codes
function Util:StripColors(s)
    return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
end

-- Debounce: returns a function that delays execution
function Util:Debounce(fn, delay)
    local timer = nil
    return function(...)
        local args = { ... }
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(delay, function()
            timer = nil
            fn(unpack(args))
        end)
    end
end

-- Format time for display
function Util:FormatTime(timestamp)
    return date("%H:%M:%S", timestamp)
end

-- Truncate string with ellipsis
function Util:Truncate(s, maxLen)
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 3) .. "..."
end
