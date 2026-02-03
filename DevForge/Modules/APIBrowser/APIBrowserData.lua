local _, DF = ...

DF.APIBrowserData = {}

local Data = DF.APIBrowserData

local systems = nil
local systemIndex = {}   -- name -> system
local allFunctions = {}  -- flat list of { name, fullName, system, type, doc }
local loaded = false
local loadError = nil

-- Safely load a Blizzard addon by name
local function SafeLoadAddOn(name)
    pcall(function()
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn(name)
        elseif LoadAddOn then
            LoadAddOn(name)
        end
    end)
end

-- Try to extract systems from the APIDocumentation object
local function ExtractSystems()
    if not APIDocumentation then return nil end

    -- Method 1: GetAllSystems() (older WoW)
    if type(APIDocumentation.GetAllSystems) == "function" then
        local ok, result = pcall(APIDocumentation.GetAllSystems, APIDocumentation)
        if ok and type(result) == "table" and #result > 0 then return result end
    end

    -- Method 2: direct .systems table
    if type(APIDocumentation.systems) == "table" and #APIDocumentation.systems > 0 then
        return APIDocumentation.systems
    end

    -- Method 3: call OnLoad() to initialize, then check .systems
    if type(APIDocumentation.OnLoad) == "function" then
        pcall(APIDocumentation.OnLoad, APIDocumentation)
        if type(APIDocumentation.systems) == "table" and #APIDocumentation.systems > 0 then
            return APIDocumentation.systems
        end
    end

    -- Method 4: scan all keys for system-shaped tables
    local found = {}
    pcall(function()
        for k, v in pairs(APIDocumentation) do
            if type(v) == "table" and (v.Functions or v.Events or v.Tables or v.Namespace) then
                found[#found + 1] = v
            end
        end
    end)
    if #found > 0 then return found end

    return nil
end

-- Load Blizzard API documentation at runtime
function Data:Load()
    if loaded then return true, nil end

    -- Load documentation addons (framework + generated data are sometimes separate)
    SafeLoadAddOn("Blizzard_APIDocumentation")
    SafeLoadAddOn("Blizzard_APIDocumentationGenerated")

    if not APIDocumentation then
        loadError = "APIDocumentation global not found after loading addon."
        return false, loadError
    end

    -- Try to get systems from APIDocumentation
    local sysResult = ExtractSystems()

    -- Fallback: scan _G for C_* namespaces and build synthetic system entries
    if not sysResult or #sysResult == 0 then
        sysResult = self:BuildFromGlobals()
    end

    if not sysResult or #sysResult == 0 then
        loadError = "No API data found. APIDocumentation loaded but contained no systems."
        return false, loadError
    end

    systems = sysResult

    -- Try loading Blizzard_ObjectAPI for additional widget method data
    self:LoadObjectAPI()

    self:BuildIndex()
    loaded = true
    return true, nil
end

-- Fallback: build system entries by scanning _G for C_* namespaces and Enum.*
function Data:BuildFromGlobals()
    local result = {}
    local seen = {}

    -- Scan for C_* namespaces
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and k:sub(1, 2) == "C_" and not seen[k] then
            seen[k] = true
            local funcs = {}
            pcall(function()
                for fname, fval in pairs(v) do
                    if type(fval) == "function" then
                        funcs[#funcs + 1] = { Name = fname }
                    end
                end
            end)
            table.sort(funcs, function(a, b) return a.Name < b.Name end)
            result[#result + 1] = {
                Namespace = k,
                Name = k,
                Functions = funcs,
                Events = {},
                Tables = {},
            }
        end
    end

    -- Scan Enum.* for enumerations
    if type(Enum) == "table" then
        local enumFuncs = {}
        pcall(function()
            for ename, etbl in pairs(Enum) do
                if type(etbl) == "table" then
                    local fields = {}
                    for fname, fval in pairs(etbl) do
                        fields[#fields + 1] = { Name = fname, EnumValue = fval }
                    end
                    table.sort(fields, function(a, b)
                        local na, nb = tonumber(a.EnumValue), tonumber(b.EnumValue)
                        if na and nb then return na < nb end
                        return a.Name < b.Name
                    end)
                    enumFuncs[#enumFuncs + 1] = {
                        Name = ename,
                        Type = "Enumeration",
                        Fields = fields,
                    }
                end
            end
        end)
        if #enumFuncs > 0 then
            table.sort(enumFuncs, function(a, b) return a.Name < b.Name end)
            result[#result + 1] = {
                Namespace = "Enum",
                Name = "Enum",
                Functions = {},
                Events = {},
                Tables = enumFuncs,
            }
        end
    end

    table.sort(result, function(a, b) return a.Namespace < b.Namespace end)
    return result
end

-- Load Blizzard_ObjectAPI if available (supplements APIDocumentation with widget methods)
local objectAPISystems = nil

function Data:LoadObjectAPI()
    SafeLoadAddOn("Blizzard_ObjectAPI")

    -- Re-query systems to pick up any new entries ObjectAPI added
    local sysResult = ExtractSystems()

    if sysResult then
        -- Merge any new systems that weren't in the original set
        local existing = {}
        for _, sys in ipairs(systems) do
            existing[sys.Namespace or sys.Name or ""] = true
        end
        for _, sys in ipairs(sysResult) do
            local name = sys.Namespace or sys.Name or ""
            if not existing[name] then
                systems[#systems + 1] = sys
                existing[name] = true
            end
        end
        objectAPISystems = sysResult
    end
end

function Data:HasObjectAPI()
    return objectAPISystems ~= nil
end

-- Build searchable index from systems
function Data:BuildIndex()
    wipe(systemIndex)
    wipe(allFunctions)

    if not systems then return end

    for _, system in ipairs(systems) do
        local sysName = system.Namespace or system.Name or "Unknown"
        systemIndex[sysName] = system

        -- Index functions
        if system.Functions then
            for _, func in ipairs(system.Functions) do
                allFunctions[#allFunctions + 1] = {
                    name = func.Name,
                    fullName = sysName .. "." .. func.Name,
                    system = sysName,
                    type = "function",
                    doc = func,
                }
            end
        end

        -- Index events
        if system.Events then
            for _, event in ipairs(system.Events) do
                allFunctions[#allFunctions + 1] = {
                    name = event.Name,
                    fullName = sysName .. ":" .. event.Name,
                    system = sysName,
                    type = "event",
                    doc = event,
                }
            end
        end

        -- Index tables (enums)
        if system.Tables then
            for _, tbl in ipairs(system.Tables) do
                allFunctions[#allFunctions + 1] = {
                    name = tbl.Name,
                    fullName = sysName .. "." .. tbl.Name,
                    system = sysName,
                    type = "table",
                    doc = tbl,
                }
            end
        end
    end

    -- Sort by name
    table.sort(allFunctions, function(a, b)
        return a.fullName < b.fullName
    end)
end

-- Get all systems (sorted by namespace)
function Data:GetSystems()
    if not systems then return {} end
    local sorted = {}
    for _, sys in ipairs(systems) do
        sorted[#sorted + 1] = sys
    end
    table.sort(sorted, function(a, b)
        return (a.Namespace or a.Name or "") < (b.Namespace or b.Name or "")
    end)
    return sorted
end

-- Get a system by name
function Data:GetSystem(name)
    return systemIndex[name]
end

-- Get all indexed entries (for search)
function Data:GetAllEntries()
    return allFunctions
end

-- Check if loaded
function Data:IsLoaded()
    return loaded
end

-- Get load error
function Data:GetError()
    return loadError
end

-- Build tree nodes for the namespace tree
function Data:BuildTreeNodes()
    local nodes = {}
    local sorted = self:GetSystems()

    for _, system in ipairs(sorted) do
        local sysName = system.Namespace or system.Name or "Unknown"
        local children = {}

        if system.Functions then
            for _, func in ipairs(system.Functions) do
                children[#children + 1] = {
                    id = sysName .. "." .. func.Name,
                    text = DF.Colors.func .. func.Name .. "|r",
                    data = { type = "function", system = sysName, doc = func },
                }
            end
        end

        if system.Events then
            for _, event in ipairs(system.Events) do
                children[#children + 1] = {
                    id = sysName .. ":" .. event.Name,
                    text = DF.Colors.keyword .. event.Name .. "|r",
                    data = { type = "event", system = sysName, doc = event },
                }
            end
        end

        if system.Tables then
            for _, tbl in ipairs(system.Tables) do
                children[#children + 1] = {
                    id = sysName .. "." .. tbl.Name,
                    text = DF.Colors.tableRef .. tbl.Name .. "|r",
                    data = { type = "table", system = sysName, doc = tbl },
                }
            end
        end

        nodes[#nodes + 1] = {
            id = sysName,
            text = sysName,
            children = #children > 0 and children or nil,
            data = { type = "namespace", system = sysName },
        }
    end

    return nodes
end
