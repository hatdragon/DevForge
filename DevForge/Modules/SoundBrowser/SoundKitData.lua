local _, DF = ...

DF.SoundKitData = {}

local SKD = DF.SoundKitData

---------------------------------------------------------------------------
-- Category definitions: prefix patterns matched against SOUNDKIT key names
-- Order matters — first match wins.
---------------------------------------------------------------------------
local CATEGORY_RULES = {
    { id = "account",      name = "Account Store",        pattern = "^ACCOUNT_STORE_" },
    { id = "achievement",  name = "Achievements",         pattern = "^ACHIEVEMENT" },
    { id = "alarm",        name = "Alarms",               pattern = "^ALARM_" },
    { id = "barbershop",   name = "Barbershop",           pattern = "^BARBERSHOP_" },
    { id = "catalog",      name = "Catalog Shop",         pattern = "^CATALOG_SHOP_" },
    { id = "garrison",     name = "Garrison & Missions",  pattern = "^GARRISON" },
    { id = "gluescreen",   name = "Glue Screen Ambience", pattern = "^AMB_GLUESCREEN_" },
    { id = "gs",           name = "Glue Screens (GS)",    pattern = "^GS_" },
    { id = "housing",      name = "Housing",              pattern = "^HOUSING_" },
    { id = "interface",    name = "Interface",            pattern = "^INTERFACE_" },
    { id = "ig",           name = "Interface (IG)",       pattern = "^IG_" },
    { id = "lfg",          name = "LFG / Group Finder",   pattern = "^LFG_" },
    { id = "loot",         name = "Loot & Items",         pattern = "^LOOT" },
    { id = "map",          name = "Map & Navigation",     pattern = "^MAP" },
    { id = "music",        name = "Music",                pattern = "^MUS_" },
    { id = "pet",          name = "Pets & Mounts",        pattern = "^PET" },
    { id = "pvp",          name = "PvP",                  pattern = "^PVP" },
    { id = "quest",        name = "Quests",               pattern = "^QUEST_" },
    { id = "raid",         name = "Raid & Dungeon",       pattern = "^RAID" },
    { id = "soulbinds",    name = "Soulbinds",            pattern = "^SOULBINDS_" },
    { id = "spell",        name = "Spells & Auras",       pattern = "^SPELL" },
    { id = "tradingpost",  name = "Trading Post",         pattern = "^TRADING_POST_" },
    { id = "ui",           name = "UI General",           pattern = "^UI_" },
    { id = "other",        name = "Other",                pattern = "." },
}

---------------------------------------------------------------------------
-- Build data from the global SOUNDKIT table at runtime
---------------------------------------------------------------------------
local categories = nil
local soundData = nil
local allSoundsCache = nil

local function EnsureBuilt()
    if categories then return end

    categories = {}
    soundData = {}

    -- Initialize buckets
    for _, rule in ipairs(CATEGORY_RULES) do
        soundData[rule.id] = {}
    end

    -- Read the global SOUNDKIT table (Blizzard-provided)
    if not SOUNDKIT then
        -- SOUNDKIT not available; create empty categories
        for _, rule in ipairs(CATEGORY_RULES) do
            categories[#categories + 1] = { id = rule.id, name = rule.name }
        end
        return
    end

    -- Sort keys alphabetically for stable ordering
    local keys = {}
    for name, id in pairs(SOUNDKIT) do
        if type(name) == "string" and type(id) == "number" then
            keys[#keys + 1] = name
        end
    end
    table.sort(keys)

    -- Categorize each entry
    for _, name in ipairs(keys) do
        local id = SOUNDKIT[name]
        local placed = false
        for _, rule in ipairs(CATEGORY_RULES) do
            if name:match(rule.pattern) then
                local bucket = soundData[rule.id]
                bucket[#bucket + 1] = { id = id, name = name }
                placed = true
                break
            end
        end
    end

    -- Build category list with counts, skip empty ones (except "other")
    for _, rule in ipairs(CATEGORY_RULES) do
        local bucket = soundData[rule.id]
        if #bucket > 0 then
            categories[#categories + 1] = { id = rule.id, name = rule.name }
        end
    end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function SKD:GetCategories()
    EnsureBuilt()
    return categories
end

function SKD:GetSounds(categoryId)
    EnsureBuilt()
    return soundData[categoryId] or {}
end

function SKD:GetAllSounds()
    EnsureBuilt()
    if allSoundsCache then return allSoundsCache end
    allSoundsCache = {}
    for _, cat in ipairs(categories) do
        local sounds = soundData[cat.id]
        if sounds then
            for _, entry in ipairs(sounds) do
                allSoundsCache[#allSoundsCache + 1] = {
                    id = entry.id,
                    name = entry.name,
                    categoryId = cat.id,
                }
            end
        end
    end
    return allSoundsCache
end
