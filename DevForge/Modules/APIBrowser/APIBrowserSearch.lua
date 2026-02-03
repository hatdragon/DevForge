local _, DF = ...

DF.APIBrowserSearch = {}

local Search = DF.APIBrowserSearch

-- Search all API entries for a substring match
function Search:Find(query)
    if not query or query == "" then
        return nil -- nil means "show all"
    end

    local results = {}
    local entries = DF.APIBrowserData:GetAllEntries()
    local queryLower = query:lower()

    for _, entry in ipairs(entries) do
        local match = false

        -- Match against full name
        if entry.fullName:lower():find(queryLower, 1, true) then
            match = true
        end

        -- Match against name only
        if not match and entry.name:lower():find(queryLower, 1, true) then
            match = true
        end

        -- Match against documentation text
        if not match and entry.doc and type(entry.doc.Documentation) == "string" then
            if entry.doc.Documentation:lower():find(queryLower, 1, true) then
                match = true
            end
        end

        if match then
            results[#results + 1] = entry
        end
    end

    return results
end

-- Build tree nodes from search results (grouped by system)
function Search:BuildSearchTree(results)
    if not results then return nil end -- nil = use full tree

    local bySystem = {}
    local systemOrder = {}

    for _, entry in ipairs(results) do
        if not bySystem[entry.system] then
            bySystem[entry.system] = {}
            systemOrder[#systemOrder + 1] = entry.system
        end
        bySystem[entry.system][#bySystem[entry.system] + 1] = entry
    end

    table.sort(systemOrder)

    local nodes = {}
    for _, sysName in ipairs(systemOrder) do
        local children = {}
        for _, entry in ipairs(bySystem[sysName]) do
            local color = DF.Colors.func
            if entry.type == "event" then color = DF.Colors.keyword
            elseif entry.type == "table" then color = DF.Colors.tableRef end

            children[#children + 1] = {
                id = entry.fullName,
                text = color .. entry.name .. "|r",
                data = { type = entry.type, system = sysName, doc = entry.doc },
            }
        end

        nodes[#nodes + 1] = {
            id = "search_" .. sysName,
            text = sysName .. " (" .. #children .. ")",
            children = children,
            data = { type = "namespace", system = sysName },
        }
    end

    return nodes
end
