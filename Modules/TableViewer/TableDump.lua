local _, DF = ...

DF.TableDump = {}

local TableDump = DF.TableDump
local SecretGuard = DF.SecretGuard

local MAX_DEPTH = 8
local MAX_CHILDREN = 200
local MAX_STRING_LEN = 80

-- Known globals to skip when scanning (frames, noise, etc.)
local SKIP_GLOBALS = {
    -- WoW frame globals
    UIParent = true, WorldFrame = true, GameTooltip = true,
    -- DevForge internals
    DevForge = true,
    -- Common noise
    _G = true, Enum = true,
}

-- Suffix patterns that indicate UI mixins/templates, not data tables
local MIXIN_SUFFIXES = {
    "Mixin$", "Template$", "Util$", "Behavior$", "Handler$",
    "Controller$", "Provider$", "Manager$", "Base$", "Proto$",
    "Frame$", "Button$", "Dialog$", "Tooltip$",
}

-- Check if a global key looks like a frame (has WoW widget methods)
local function LooksLikeFrame(key, value)
    if type(value) ~= "table" then return false end
    local ok, objType = pcall(function() return value.GetObjectType and value:GetObjectType() end)
    return ok and type(objType) == "string"
end

-- Check if a table looks like a UI mixin (has common mixin/handler methods)
local function LooksLikeMixin(value)
    if type(value) ~= "table" then return false end
    local hitCount = 0
    local ok = pcall(function()
        if type(value.OnLoad) == "function" then hitCount = hitCount + 1 end
        if type(value.OnEvent) == "function" then hitCount = hitCount + 1 end
        if type(value.OnShow) == "function" then hitCount = hitCount + 1 end
        if type(value.OnHide) == "function" then hitCount = hitCount + 1 end
        if type(value.Init) == "function" then hitCount = hitCount + 1 end
        if type(value.OnUpdate) == "function" then hitCount = hitCount + 1 end
    end)
    return ok and hitCount >= 2
end

-- Safely count entries in a table, capped at limit to avoid stalling
local function SafeCount(t, limit)
    limit = limit or 10000
    local count = 0
    local ok = pcall(function()
        for _ in pairs(t) do
            count = count + 1
            if count > limit then break end
        end
    end)
    if not ok then return 0 end
    return count
end

-- Check if a string is a valid Lua identifier
local function IsIdentifier(s)
    return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
end

---------------------------------------------------------------------------
-- Expression resolver
---------------------------------------------------------------------------
function TableDump:Resolve(expr)
    if not expr or expr == "" then
        return nil, false, "Empty expression"
    end

    local fn, err = loadstring("return " .. expr)
    if not fn then
        return nil, false, "Syntax error: " .. tostring(err)
    end

    -- Sandbox: only access _G
    setfenv(fn, _G)

    local ok, result = pcall(fn)
    if not ok then
        return nil, false, "Runtime error: " .. tostring(result)
    end

    return result, true, nil
end

---------------------------------------------------------------------------
-- Value formatting (color-coded display string)
---------------------------------------------------------------------------
function TableDump:FormatValue(v)
    -- Secret check first
    local secretFmt = SecretGuard:FormatValue(v)
    if secretFmt then return secretFmt end

    local t = type(v)

    if v == nil then
        return DF.Colors.nilVal .. "nil|r"
    elseif t == "boolean" then
        if v then
            return DF.Colors.boolTrue .. "true|r"
        else
            return DF.Colors.boolFalse .. "false|r"
        end
    elseif t == "number" then
        return DF.Colors.number .. tostring(v) .. "|r"
    elseif t == "string" then
        local display = v
        if #display > MAX_STRING_LEN then
            display = display:sub(1, MAX_STRING_LEN) .. "..."
        end
        display = display:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("|", "||")
        return DF.Colors.string .. '"' .. display .. '"|r'
    elseif t == "function" then
        return DF.Colors.func .. "function|r"
    elseif t == "table" then
        local count = 0
        local ok, _ = pcall(function()
            for _ in pairs(v) do
                count = count + 1
                if count > 9999 then break end
            end
        end)
        if not ok then count = "?" end
        return DF.Colors.tableRef .. "{" .. tostring(count) .. " entries}|r"
    elseif t == "userdata" then
        local name
        local ok, result = pcall(function() return v.GetName and v:GetName() end)
        if ok and result and result ~= "" then
            name = tostring(result)
        end
        if name then
            return DF.Colors.tableRef .. "<userdata: " .. name .. ">|r"
        end
        return DF.Colors.tableRef .. tostring(v) .. "|r"
    end

    return DF.Colors.text .. tostring(v) .. "|r"
end

---------------------------------------------------------------------------
-- Key formatting
---------------------------------------------------------------------------
function TableDump:FormatKey(k)
    if type(k) == "number" then
        return "[" .. tostring(k) .. "]"
    elseif type(k) == "string" then
        if IsIdentifier(k) then
            return k
        else
            local escaped = k:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("|", "||")
            return '["' .. escaped .. '"]'
        end
    else
        return "[" .. tostring(k) .. "]"
    end
end

---------------------------------------------------------------------------
-- Sort keys: numbers ascending, then strings alphabetical
---------------------------------------------------------------------------
local function SortedKeys(t)
    local numKeys = {}
    local strKeys = {}
    local otherKeys = {}

    local ok, err = pcall(function()
        for k in pairs(t) do
            local kt = type(k)
            if kt == "number" then
                numKeys[#numKeys + 1] = k
            elseif kt == "string" then
                strKeys[#strKeys + 1] = k
            else
                otherKeys[#otherKeys + 1] = k
            end
        end
    end)

    if not ok then return {} end

    table.sort(numKeys)
    table.sort(strKeys)

    local result = {}
    for _, k in ipairs(numKeys) do result[#result + 1] = k end
    for _, k in ipairs(strKeys) do result[#result + 1] = k end
    for _, k in ipairs(otherKeys) do result[#result + 1] = k end
    return result
end

---------------------------------------------------------------------------
-- Build tree nodes from any value
---------------------------------------------------------------------------
function TableDump:BuildNodes(value, path, depth, seen)
    path = path or ""
    depth = depth or 0
    seen = seen or {}

    -- Secret check
    if SecretGuard:IsSecret(value) then
        return {{ id = path .. ".__secret", text = DF.Colors.secret .. "[secret]|r" }}
    end

    local t = type(value)

    if t ~= "table" then
        return {{ id = path .. ".__value", text = self:FormatValue(value) }}
    end

    -- Circular reference detection
    if seen[value] then
        return {{ id = path .. ".__circular", text = DF.Colors.dim .. "[circular reference]|r" }}
    end

    -- Depth limit
    if depth >= MAX_DEPTH then
        return {{ id = path .. ".__maxdepth", text = DF.Colors.dim .. "[max depth reached]|r" }}
    end

    seen[value] = true

    local keys = SortedKeys(value)
    local nodes = {}
    local shown = 0

    for _, k in ipairs(keys) do
        if shown >= MAX_CHILDREN then
            local remaining = #keys - shown
            nodes[#nodes + 1] = {
                id = path .. ".__truncated",
                text = DF.Colors.dim .. "... (" .. remaining .. " more — click to load)|r",
                data = {
                    truncated = true,
                    sourceTable = value,
                    keys = keys,
                    offset = shown,
                    path = path,
                    depth = depth,
                    parentNodes = nodes,
                },
            }
            break
        end

        local ok, v = pcall(function() return value[k] end)
        if not ok then
            v = nil
        end

        -- Secret check on the value
        if SecretGuard:IsSecret(v) then
            nodes[#nodes + 1] = {
                id = path .. "." .. tostring(k),
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. DF.Colors.secret .. "[secret]|r",
            }
        elseif type(v) == "table" and not seen[v] then
            local childPath = path .. "." .. tostring(k)
            local children = self:BuildNodes(v, childPath, depth + 1, seen)
            nodes[#nodes + 1] = {
                id = childPath,
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. self:FormatValue(v),
                children = children,
                data = { key = k, value = v },
            }
        else
            local displayVal
            if type(v) == "table" and seen[v] then
                displayVal = DF.Colors.dim .. "[circular reference]|r"
            else
                displayVal = self:FormatValue(v)
            end
            nodes[#nodes + 1] = {
                id = path .. "." .. tostring(k),
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. displayVal,
                data = { key = k, value = v },
            }
        end

        shown = shown + 1
    end

    if #nodes == 0 then
        nodes[#nodes + 1] = {
            id = path .. ".__empty",
            text = DF.Colors.dim .. "(empty table)|r",
        }
    end

    seen[value] = nil
    return nodes
end

---------------------------------------------------------------------------
-- Load more truncated children
---------------------------------------------------------------------------
function TableDump:LoadMore(node)
    local d = node.data
    if not d or not d.truncated then return false end

    local parentNodes = d.parentNodes
    local keys = d.keys
    local offset = d.offset
    local value = d.sourceTable
    local path = d.path
    local depth = d.depth

    -- Remove the truncated placeholder (always the last entry)
    parentNodes[#parentNodes] = nil

    local shown = 0
    local seen = {}

    for i = offset + 1, #keys do
        if shown >= MAX_CHILDREN then
            local remaining = #keys - (offset + shown)
            parentNodes[#parentNodes + 1] = {
                id = path .. ".__truncated",
                text = DF.Colors.dim .. "... (" .. remaining .. " more — click to load)|r",
                data = {
                    truncated = true,
                    sourceTable = value,
                    keys = keys,
                    offset = offset + shown,
                    path = path,
                    depth = depth,
                    parentNodes = parentNodes,
                },
            }
            break
        end

        local k = keys[i]
        local ok, v = pcall(function() return value[k] end)
        if not ok then v = nil end

        if SecretGuard:IsSecret(v) then
            parentNodes[#parentNodes + 1] = {
                id = path .. "." .. tostring(k),
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. DF.Colors.secret .. "[secret]|r",
            }
        elseif type(v) == "table" then
            local childPath = path .. "." .. tostring(k)
            local children = self:BuildNodes(v, childPath, (depth or 0) + 1)
            parentNodes[#parentNodes + 1] = {
                id = childPath,
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. self:FormatValue(v),
                children = children,
                data = { key = k, value = v },
            }
        else
            parentNodes[#parentNodes + 1] = {
                id = path .. "." .. tostring(k),
                text = DF.Colors.text .. self:FormatKey(k) .. "|r = " .. self:FormatValue(v),
                data = { key = k, value = v },
            }
        end

        shown = shown + 1
    end

    return true
end

---------------------------------------------------------------------------
-- Serialize tree nodes to plain text (for copy)
---------------------------------------------------------------------------
function TableDump:SerializeNodes(nodes, indent, lines)
    indent = indent or 0
    lines = lines or {}
    local prefix = string.rep("  ", indent)
    for _, node in ipairs(nodes) do
        local text = DF.Util:StripColors(node.text or "")
        lines[#lines + 1] = prefix .. text
        if node.children then
            self:SerializeNodes(node.children, indent + 1, lines)
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- Scan known tables from _G for the sidebar
---------------------------------------------------------------------------
function TableDump:ScanKnownTables()
    local cNodes = {}
    local enumNodes = {}
    local globalNodes = {}
    local addonNodes = {}

    local MIN_ENTRIES = 1  -- skip empty tables

    -- C_ Namespaces (skip empty ones)
    pcall(function()
        for key, val in pairs(_G) do
            if type(key) == "string" and key:match("^C_") and type(val) == "table" then
                local count = SafeCount(val, 500)
                if count >= MIN_ENTRIES then
                    cNodes[#cNodes + 1] = {
                        id = "known." .. key,
                        text = key .. DF.Colors.dim .. " (" .. count .. ")|r",
                        data = { expr = key },
                    }
                end
            end
        end
    end)
    table.sort(cNodes, function(a, b) return a.data.expr < b.data.expr end)

    -- Enums (skip empty sub-tables)
    pcall(function()
        if type(Enum) == "table" then
            for key, val in pairs(Enum) do
                if type(val) == "table" then
                    local count = SafeCount(val, 500)
                    if count >= MIN_ENTRIES then
                        enumNodes[#enumNodes + 1] = {
                            id = "known.Enum." .. key,
                            text = key .. DF.Colors.dim .. " (" .. count .. ")|r",
                            data = { expr = "Enum." .. key },
                        }
                    end
                end
            end
        end
    end)
    table.sort(enumNodes, function(a, b) return a.data.expr < b.data.expr end)

    -- Other notable globals: strict filtering
    pcall(function()
        for key, val in pairs(_G) do
            if type(key) == "string" and type(val) == "table"
                and not key:match("^C_")
                and key ~= "Enum"
                and not SKIP_GLOBALS[key]
                and key:match("^[A-Z]")
                and #key > 2
            then
                -- Skip frames
                if not LooksLikeFrame(key, val)
                -- Skip UI mixins / templates
                and not LooksLikeMixin(val)
                then
                    -- Skip mixin-named tables
                    local isMixinName = false
                    for _, suffix in ipairs(MIXIN_SUFFIXES) do
                        if key:match(suffix) then
                            isMixinName = true
                            break
                        end
                    end

                    if not isMixinName then
                        local count = SafeCount(val, 500)
                        if count >= MIN_ENTRIES then
                            globalNodes[#globalNodes + 1] = {
                                id = "known." .. key,
                                text = key .. DF.Colors.dim .. " (" .. count .. ")|r",
                                data = { expr = key },
                            }
                        end
                    end
                end
            end
        end
    end)
    table.sort(globalNodes, function(a, b) return a.data.expr < b.data.expr end)

    -- Addon SavedVariables
    local svNames = { "DevForgeDB" }
    local commonSVs = {
        "WeakAurasSaved", "ElvDB", "Details", "Plater",
        "BigWigsStatsDB", "GTFO", "OmniCC_DB",
    }
    for _, name in ipairs(commonSVs) do
        if type(_G[name]) == "table" then
            svNames[#svNames + 1] = name
        end
    end
    table.sort(svNames)

    for _, name in ipairs(svNames) do
        if type(_G[name]) == "table" then
            local count = SafeCount(_G[name], 500)
            addonNodes[#addonNodes + 1] = {
                id = "known.sv." .. name,
                text = name .. DF.Colors.dim .. " (" .. count .. ")|r",
                data = { expr = name },
            }
        end
    end

    return {
        {
            id = "c_ns",
            text = "C_ Namespaces (" .. #cNodes .. ")",
            children = cNodes,
        },
        {
            id = "enums",
            text = "Enums (" .. #enumNodes .. ")",
            children = enumNodes,
        },
        {
            id = "globals",
            text = "Globals (" .. #globalNodes .. ")",
            children = globalNodes,
        },
        {
            id = "addons",
            text = "Addon Data (" .. #addonNodes .. ")",
            children = addonNodes,
        },
    }
end
