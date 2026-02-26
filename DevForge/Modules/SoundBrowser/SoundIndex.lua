local _, DF = ...

DF.SoundIndex = {}

local Index = DF.SoundIndex
local MAX_SEARCH_RESULTS = 200
local MAX_RECENT = 50

---------------------------------------------------------------------------
-- Search: unified across all data sources
---------------------------------------------------------------------------
function Index:Search(query)
    if not query or query == "" then return {} end
    local queryLower = query:lower()
    local results = {}
    local count = 0
    local seen = {}

    -- Search SoundKit entries
    local allSounds = DF.SoundKitData:GetAllSounds()
    for _, entry in ipairs(allSounds) do
        if count >= MAX_SEARCH_RESULTS then break end
        if entry.name:lower():find(queryLower, 1, true) or
           tostring(entry.id):find(queryLower, 1, true) then
            local key = "kit:" .. entry.id
            if not seen[key] then
                seen[key] = true
                count = count + 1
                results[count] = {
                    id = entry.id,
                    name = entry.name,
                    category = "SoundKit",
                    sourceType = "kit",
                }
            end
        end
    end

    -- Search runtime results
    if count < MAX_SEARCH_RESULTS then
        local runtimeResults = DF.SoundRuntime:GetResults()
        for _, item in ipairs(runtimeResults) do
            if count >= MAX_SEARCH_RESULTS then break end
            if item.name:lower():find(queryLower, 1, true) or
               tostring(item.id):find(queryLower, 1, true) then
                local key = item.sourceType .. ":" .. tostring(item.id)
                if not seen[key] then
                    seen[key] = true
                    count = count + 1
                    results[count] = {
                        id = item.id,
                        name = item.name,
                        category = "Runtime",
                        sourceType = item.sourceType,
                    }
                end
            end
        end
    end

    -- Search favorites
    if count < MAX_SEARCH_RESULTS then
        local favs = self:GetFavorites()
        for _, fav in ipairs(favs) do
            if count >= MAX_SEARCH_RESULTS then break end
            if fav.name:lower():find(queryLower, 1, true) or
               tostring(fav.id):find(queryLower, 1, true) then
                local key = (fav.sourceType or "kit") .. ":" .. tostring(fav.id)
                if not seen[key] then
                    seen[key] = true
                    count = count + 1
                    results[count] = {
                        id = fav.id,
                        name = fav.name,
                        category = "Favorite",
                        sourceType = fav.sourceType or "kit",
                    }
                end
            end
        end
    end

    return results
end

---------------------------------------------------------------------------
-- Favorites (persisted in DevForgeDB.soundFavorites)
---------------------------------------------------------------------------
function Index:GetFavorites()
    if not DevForgeDB then return {} end
    return DevForgeDB.soundFavorites or {}
end

function Index:AddFavorite(entry)
    if not DevForgeDB then return end
    if not DevForgeDB.soundFavorites then
        DevForgeDB.soundFavorites = {}
    end
    local idStr = tostring(entry.id)
    for _, fav in ipairs(DevForgeDB.soundFavorites) do
        if tostring(fav.id) == idStr and (fav.sourceType or "kit") == (entry.sourceType or "kit") then
            return
        end
    end
    DevForgeDB.soundFavorites[#DevForgeDB.soundFavorites + 1] = {
        id = entry.id,
        name = entry.name,
        sourceType = entry.sourceType or "kit",
    }
end

function Index:RemoveFavorite(id, sourceType)
    if not DevForgeDB or not DevForgeDB.soundFavorites then return end
    local idStr = tostring(id)
    sourceType = sourceType or "kit"
    for i, fav in ipairs(DevForgeDB.soundFavorites) do
        if tostring(fav.id) == idStr and (fav.sourceType or "kit") == sourceType then
            table.remove(DevForgeDB.soundFavorites, i)
            return
        end
    end
end

function Index:IsFavorite(id, sourceType)
    if not DevForgeDB or not DevForgeDB.soundFavorites then return false end
    local idStr = tostring(id)
    sourceType = sourceType or "kit"
    for _, fav in ipairs(DevForgeDB.soundFavorites) do
        if tostring(fav.id) == idStr and (fav.sourceType or "kit") == sourceType then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Recent history (persisted in DevForgeDB.soundRecent, newest first)
---------------------------------------------------------------------------
function Index:GetRecent()
    if not DevForgeDB then return {} end
    return DevForgeDB.soundRecent or {}
end

function Index:AddRecent(entry)
    if not DevForgeDB then return end
    if not DevForgeDB.soundRecent then
        DevForgeDB.soundRecent = {}
    end
    local idStr = tostring(entry.id)
    local st = entry.sourceType or "kit"
    for i, rec in ipairs(DevForgeDB.soundRecent) do
        if tostring(rec.id) == idStr and (rec.sourceType or "kit") == st then
            table.remove(DevForgeDB.soundRecent, i)
            break
        end
    end
    table.insert(DevForgeDB.soundRecent, 1, {
        id = entry.id,
        name = entry.name,
        sourceType = st,
    })
    while #DevForgeDB.soundRecent > MAX_RECENT do
        DevForgeDB.soundRecent[#DevForgeDB.soundRecent] = nil
    end
end
