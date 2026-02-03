local _, DF = ...

DF.TextureIndex = {}

local Index = DF.TextureIndex
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

    -- Search atlas names
    local allAtlases = DF.TextureAtlasData:GetAllAtlases()
    for _, name in ipairs(allAtlases) do
        if count >= MAX_SEARCH_RESULTS then break end
        if name:lower():find(queryLower, 1, true) then
            count = count + 1
            results[count] = {
                path = name,
                name = name,
                category = "Atlas",
                isAtlas = true,
            }
        end
    end

    -- Search icon paths
    if count < MAX_SEARCH_RESULTS then
        local allIcons = DF.TextureIconData:GetAllIcons()
        for _, icon in ipairs(allIcons) do
            if count >= MAX_SEARCH_RESULTS then break end
            if icon.path:lower():find(queryLower, 1, true) or
               icon.name:lower():find(queryLower, 1, true) then
                count = count + 1
                results[count] = {
                    path = icon.path,
                    name = icon.name,
                    category = "Icon",
                    isAtlas = false,
                }
            end
        end
    end

    -- Search runtime results
    if count < MAX_SEARCH_RESULTS then
        local runtimeResults = DF.TextureRuntime:GetResults()
        for _, item in ipairs(runtimeResults) do
            if count >= MAX_SEARCH_RESULTS then break end
            if tostring(item.path):lower():find(queryLower, 1, true) or
               item.name:lower():find(queryLower, 1, true) then
                -- Avoid duplicates from atlas/icon results
                local isDup = false
                for _, r in ipairs(results) do
                    if tostring(r.path) == tostring(item.path) then
                        isDup = true
                        break
                    end
                end
                if not isDup then
                    count = count + 1
                    results[count] = {
                        path = item.path,
                        name = item.name,
                        category = "Runtime",
                        isAtlas = item.isAtlas,
                        source = item.source,
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
            if tostring(fav.path):lower():find(queryLower, 1, true) or
               fav.name:lower():find(queryLower, 1, true) then
                local isDup = false
                for _, r in ipairs(results) do
                    if tostring(r.path) == tostring(fav.path) then
                        isDup = true
                        break
                    end
                end
                if not isDup then
                    count = count + 1
                    results[count] = {
                        path = fav.path,
                        name = fav.name,
                        category = "Favorite",
                        isAtlas = fav.isAtlas,
                    }
                end
            end
        end
    end

    return results
end

---------------------------------------------------------------------------
-- Favorites (persisted in DevForgeDB.textureFavorites)
---------------------------------------------------------------------------
function Index:GetFavorites()
    if not DevForgeDB then return {} end
    return DevForgeDB.textureFavorites or {}
end

function Index:AddFavorite(entry)
    if not DevForgeDB then return end
    if not DevForgeDB.textureFavorites then
        DevForgeDB.textureFavorites = {}
    end
    -- Don't add duplicates
    local pathStr = tostring(entry.path)
    for _, fav in ipairs(DevForgeDB.textureFavorites) do
        if tostring(fav.path) == pathStr then return end
    end
    DevForgeDB.textureFavorites[#DevForgeDB.textureFavorites + 1] = {
        path = entry.path,
        name = entry.name,
        isAtlas = entry.isAtlas or false,
    }
end

function Index:RemoveFavorite(path)
    if not DevForgeDB or not DevForgeDB.textureFavorites then return end
    local pathStr = tostring(path)
    for i, fav in ipairs(DevForgeDB.textureFavorites) do
        if tostring(fav.path) == pathStr then
            table.remove(DevForgeDB.textureFavorites, i)
            return
        end
    end
end

function Index:IsFavorite(path)
    if not DevForgeDB or not DevForgeDB.textureFavorites then return false end
    local pathStr = tostring(path)
    for _, fav in ipairs(DevForgeDB.textureFavorites) do
        if tostring(fav.path) == pathStr then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Recent history (persisted in DevForgeDB.textureRecent, newest first)
---------------------------------------------------------------------------
function Index:GetRecent()
    if not DevForgeDB then return {} end
    return DevForgeDB.textureRecent or {}
end

function Index:AddRecent(entry)
    if not DevForgeDB then return end
    if not DevForgeDB.textureRecent then
        DevForgeDB.textureRecent = {}
    end
    -- Remove existing entry if present (will re-add at front)
    local pathStr = tostring(entry.path)
    for i, rec in ipairs(DevForgeDB.textureRecent) do
        if tostring(rec.path) == pathStr then
            table.remove(DevForgeDB.textureRecent, i)
            break
        end
    end
    -- Insert at front
    table.insert(DevForgeDB.textureRecent, 1, {
        path = entry.path,
        name = entry.name,
        isAtlas = entry.isAtlas or false,
    })
    -- Trim to max
    while #DevForgeDB.textureRecent > MAX_RECENT do
        DevForgeDB.textureRecent[#DevForgeDB.textureRecent] = nil
    end
end

---------------------------------------------------------------------------
-- Backward-compatible API (used by old tree builder path)
---------------------------------------------------------------------------
function Index:GetCategories()
    return DF.TextureIconData:GetCategories()
end

function Index:GetCommonAtlases()
    return DF.TextureAtlasData:GetAllAtlases()
end

function Index:GetFullPaths(categoryId)
    local icons = DF.TextureIconData:GetIcons(categoryId)
    local prefix = DF.TextureIconData:GetPrefix(categoryId)
    local paths = {}
    for _, suffix in ipairs(icons) do
        paths[#paths + 1] = prefix .. suffix
    end
    return paths, prefix
end
