local _, DF = ...

DF.Schema = {}

local Schema = DF.Schema

local DEFAULTS = {
    dbVersion      = 3,
    windowX        = nil,
    windowY        = nil,
    windowW        = nil,
    windowH        = nil,
    lastModule     = "Console",
    consoleFontSize = 12,
    consoleHistory = {},
    apiBrowserNS   = nil,
    apiBrowserFavs = {},
    snippets       = {},
    lastSnippetId  = nil,
    snippetSidebarTab = "snippets",
    eventBlacklist = {},
    errors         = {},
    errorSessionId = 0,
    perfPollingInterval = 2,
    lastMacroIndex = nil,
    textureFavorites = {},
    textureRecent = {},
    -- IDE layout state
    sidebarWidth    = 220,
    sidebarCollapsed = false,
    bottomHeight    = 150,
    bottomCollapsed = false,
    bottomActiveTab = "output",
}

function Schema:Init()
    if not DevForgeDB then
        DevForgeDB = {}
    end

    -- Apply defaults for missing keys
    for key, default in pairs(DEFAULTS) do
        if DevForgeDB[key] == nil then
            if type(default) == "table" then
                DevForgeDB[key] = DF.Util:DeepCopy(default)
            else
                DevForgeDB[key] = default
            end
        end
    end

    -- Version migrations
    self:Migrate(DevForgeDB)
end

function Schema:Migrate(db)
    local version = db.dbVersion or 0

    if version < 1 then
        -- Initial version, ensure all fields exist
        db.dbVersion = 1
    end

    if version < 2 then
        -- IDE layout: add sidebar/bottom panel state
        if db.sidebarWidth == nil then db.sidebarWidth = 220 end
        if db.sidebarCollapsed == nil then db.sidebarCollapsed = false end
        if db.bottomHeight == nil then db.bottomHeight = 150 end
        if db.bottomCollapsed == nil then db.bottomCollapsed = false end
        if db.bottomActiveTab == nil then db.bottomActiveTab = "output" end
        -- Ensure minimum window width for IDE layout
        if db.windowW and db.windowW < 750 then
            db.windowW = 750
        end
        db.dbVersion = 2
    end

    if version < 3 then
        -- Snippet Editor sidebar tab preference
        if db.snippetSidebarTab == nil then db.snippetSidebarTab = "snippets" end
        db.dbVersion = 3
    end
end

function Schema:GetDefault(key)
    return DEFAULTS[key]
end

-- Register for logout to ensure data is saved
DF.EventBus:On("DF_PLAYER_LOGOUT", function()
    -- Trim console history to max
    if DevForgeDB and DevForgeDB.consoleHistory then
        while #DevForgeDB.consoleHistory > DF.MAX_HISTORY do
            table.remove(DevForgeDB.consoleHistory, 1)
        end
    end
end)
