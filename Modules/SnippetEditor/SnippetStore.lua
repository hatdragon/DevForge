local _, DF = ...

DF.SnippetStore = {}

local Store = DF.SnippetStore
local counter = 0

function Store:Init()
    if not DevForgeDB then return end
    if not DevForgeDB.snippets then
        DevForgeDB.snippets = {}
    end
end

-- Generate a unique ID
local function NewId()
    counter = counter + 1
    return "s_" .. GetTime() .. "_" .. counter
end

-- Get all snippets sorted by most-recently-modified
function Store:GetAll()
    self:Init()
    local snippets = DevForgeDB.snippets
    -- Sort by modified descending
    table.sort(snippets, function(a, b)
        return (a.modified or 0) > (b.modified or 0)
    end)
    return snippets
end

-- Get a snippet by ID
function Store:Get(id)
    self:Init()
    for _, snippet in ipairs(DevForgeDB.snippets) do
        if snippet.id == id then
            return snippet
        end
    end
    return nil
end

-- Create a new snippet with empty code
function Store:Create(name, parentId, isProject)
    self:Init()
    local snippet = {
        id = NewId(),
        name = name or "Untitled",
        code = "",
        modified = GetTime(),
        parentId = parentId,
        isProject = isProject or nil,
    }
    DevForgeDB.snippets[#DevForgeDB.snippets + 1] = snippet
    return snippet
end

-- Create a project node (folder grouping, no code)
function Store:CreateProject(name)
    return self:Create(name, nil, true)
end

-- Get top-level snippets (no parentId), sorted by modified desc
function Store:GetTopLevel()
    self:Init()
    local results = {}
    for _, snippet in ipairs(DevForgeDB.snippets) do
        if not snippet.parentId then
            results[#results + 1] = snippet
        end
    end
    table.sort(results, function(a, b)
        return (a.modified or 0) > (b.modified or 0)
    end)
    return results
end

-- Get children of a project, sorted by name
function Store:GetChildren(parentId)
    self:Init()
    local results = {}
    for _, snippet in ipairs(DevForgeDB.snippets) do
        if snippet.parentId == parentId then
            results[#results + 1] = snippet
        end
    end
    table.sort(results, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return results
end

-- Update a snippet's fields
function Store:Save(id, name, code)
    local snippet = self:Get(id)
    if not snippet then return nil end

    if name ~= nil then
        snippet.name = name
    end
    if code ~= nil then
        snippet.code = code
    end
    snippet.modified = GetTime()
    return snippet
end

-- Delete a snippet (cascade: if project, also delete all children)
function Store:Delete(id)
    self:Init()
    local snippet = self:Get(id)
    if not snippet then return false end

    -- If this is a project, delete children first
    if snippet.isProject then
        local i = 1
        while i <= #DevForgeDB.snippets do
            if DevForgeDB.snippets[i].parentId == id then
                table.remove(DevForgeDB.snippets, i)
            else
                i = i + 1
            end
        end
    end

    -- Delete the snippet itself
    for i, s in ipairs(DevForgeDB.snippets) do
        if s.id == id then
            table.remove(DevForgeDB.snippets, i)
            return true
        end
    end
    return false
end

-- Duplicate a snippet
function Store:Duplicate(id)
    local original = self:Get(id)
    if not original then return nil end

    local snippet = {
        id = NewId(),
        name = original.name .. " (copy)",
        code = original.code,
        modified = GetTime(),
        parentId = original.parentId,
    }
    DevForgeDB.snippets[#DevForgeDB.snippets + 1] = snippet
    return snippet
end
