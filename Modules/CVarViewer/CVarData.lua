local _, DF = ...

DF.CVarData = {}

local CVarData = DF.CVarData

-- Enum.ConsoleCategory display names
local CATEGORY_NAMES = {
    [0] = "Debug",
    [1] = "Graphics",
    [2] = "Console",
    [3] = "Combat",
    [4] = "Game",
    [5] = "Default",
    [6] = "Net",
    [7] = "Sound",
    [8] = "Gm",
}

-- Build name map from Enum.ConsoleCategory if available
local function BuildCategoryMap()
    if Enum and Enum.ConsoleCategory then
        local map = {}
        for name, val in pairs(Enum.ConsoleCategory) do
            map[val] = name
        end
        return map
    end
    return CATEGORY_NAMES
end

function CVarData:CategoryName(enumVal)
    local map = BuildCategoryMap()
    return map[enumVal] or ("Category " .. tostring(enumVal))
end

function CVarData:InferType(value, default)
    if value == nil and default == nil then
        return "string"
    end
    local v = tostring(value or "")
    local d = tostring(default or "")
    if (v == "0" or v == "1") and (d == "0" or d == "1") then
        return "boolean"
    end
    if tonumber(v) ~= nil then
        return "number"
    end
    return "string"
end

function CVarData:ScanAll()
    local getAllFn = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
    if not getAllFn then
        return nil, "No CVar enumeration API available"
    end

    local ok, commands = pcall(getAllFn)
    if not ok or not commands then
        return nil, "Failed to retrieve console commands"
    end

    -- Filter to CVars only
    local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
    local cvars = {}
    for _, cmd in ipairs(commands) do
        if cvarType and cmd.commandType == cvarType then
            cvars[#cvars + 1] = cmd
        end
    end

    -- Sort alphabetically by name
    table.sort(cvars, function(a, b)
        return (a.command or ""):lower() < (b.command or ""):lower()
    end)

    return cvars
end

-- Cached command lookup by name (built on first scan)
local commandLookup = nil

function CVarData:BuildLookup(cvarList)
    commandLookup = {}
    if cvarList then
        for _, cmd in ipairs(cvarList) do
            if cmd.command then
                commandLookup[cmd.command] = cmd
            end
        end
    end
end

function CVarData:GetInfo(name)
    if not name or name == "" then return nil end

    local info = {
        name = name,
        value = nil,
        default = nil,
        help = "",
        category = nil,
        categoryName = "Unknown",
        isModified = false,
        readOnly = false,
        perChar = false,
        type = "string",
    }

    -- Current value
    local ok, val = pcall(C_CVar.GetCVar, name)
    if ok then
        info.value = val
    end

    -- Default value
    local ok2, def = pcall(C_CVar.GetCVarDefault, name)
    if ok2 then
        info.default = def
    end

    -- Modified check
    if info.value ~= nil and info.default ~= nil then
        info.isModified = (tostring(info.value) ~= tostring(info.default))
    end

    -- Type inference
    info.type = self:InferType(info.value, info.default)

    -- Help / description from cached lookup
    if commandLookup then
        local cmd = commandLookup[name]
        if cmd then
            info.help = cmd.help or ""
            info.category = cmd.category
            if cmd.category ~= nil then
                info.categoryName = self:CategoryName(cmd.category)
            end
        end
    end

    -- Character-specific / read-only check via GetCVarInfo
    -- Returns: value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
    local infoFn = C_CVar and C_CVar.GetCVarInfo or GetCVarInfo
    if infoFn then
        local ok3, _, _, _, isPerChar, _, _, isReadOnly = pcall(infoFn, name)
        if ok3 then
            info.perChar = (isPerChar == true) or false
            info.readOnly = (isReadOnly == true) or false
        end
    end

    return info
end

function CVarData:SetValue(name, value)
    if not name or name == "" then
        return false, "No CVar name specified"
    end

    local ok, err = pcall(C_CVar.SetCVar, name, value)
    if not ok then
        return false, tostring(err)
    end
    return true, nil
end

function CVarData:ResetToDefault(name)
    if not name or name == "" then
        return false, "No CVar name specified"
    end

    local ok, def = pcall(C_CVar.GetCVarDefault, name)
    if not ok or def == nil then
        return false, "Could not retrieve default value"
    end

    return self:SetValue(name, def)
end

function CVarData:BuildSidebarNodes(cvarList, filter, modifiedOnly)
    if not cvarList then return {} end

    local lowerFilter = filter and filter ~= "" and filter:lower() or nil

    -- Group by category
    local groups = {}
    local groupOrder = {}

    for _, cmd in ipairs(cvarList) do
        local name = cmd.command or ""
        local help = cmd.help or ""
        local catVal = cmd.category

        -- Apply filter
        local passFilter = true
        if lowerFilter then
            local matchName = name:lower():find(lowerFilter, 1, true)
            local matchHelp = help:lower():find(lowerFilter, 1, true)
            if not matchName and not matchHelp then
                passFilter = false
            end
        end

        if passFilter then
            -- Check modified status
            local currentVal, defaultVal
            local okV, v = pcall(C_CVar.GetCVar, name)
            if okV then currentVal = v end
            local okD, d = pcall(C_CVar.GetCVarDefault, name)
            if okD then defaultVal = d end
            local isModified = currentVal ~= nil and defaultVal ~= nil and tostring(currentVal) ~= tostring(defaultVal)

            if not modifiedOnly or isModified then
                -- Add to category group
                local catName = self:CategoryName(catVal)
                if not groups[catName] then
                    groups[catName] = {}
                    groupOrder[#groupOrder + 1] = catName
                end

                local nodeText
                if isModified then
                    nodeText = DF.Colors.string .. name .. "|r"
                else
                    nodeText = name
                end

                groups[catName][#groups[catName] + 1] = {
                    id = "cvar." .. name,
                    text = nodeText,
                    data = { name = name, isModified = isModified },
                }
            end
        end
    end

    -- Sort group names
    table.sort(groupOrder)

    -- Build tree nodes
    local nodes = {}
    for _, catName in ipairs(groupOrder) do
        local children = groups[catName]
        nodes[#nodes + 1] = {
            id = "cat." .. catName,
            text = catName .. " (" .. #children .. ")",
            children = children,
        }
    end

    return nodes
end
