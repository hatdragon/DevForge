local _, DF = ...

DF.UI = DF.UI or {}
DF.UI.ActivityBar = {}

local ActivityBar = DF.UI.ActivityBar

-- Module -> icon mapping, grouped
-- Single atlas entries use desaturation for active/inactive states
-- fileID entries use desaturation + vertex color dimming
local MODULE_ICONS = {
    -- Code: writing & running
    { name = "Console",        atlas = "Crosshair_repairnpc_32",    fileID = 134327, group = "code" },     -- INV_Scroll_02 (scroll/REPL)
    { name = "SnippetEditor",  atlas = "Crosshair_Repair_32",       fileID = 133741, group = "code" },     -- INV_Misc_Book_09 (book/code storage)
    { name = "MacroEditor",    fileID = 136377,                      group = "code" },                      -- Ability_Marksmanship
    -- Inspect: looking at things
    { name = "Inspector",      atlas = "Crosshair_Inspect_32",      fileID = 134442, group = "inspect" },  -- INV_Misc_Spyglass_03 (magnifier)
    { name = "TableViewer",    atlasOn = "common-icon-visual", atlasOff = "common-icon-visual-disabled", fileID = 134332, group = "inspect" }, -- INV_Scroll_07 (data listing)
    { name = "TextureBrowser", atlas = "Crosshair_Transmogrify_32", fileID = 132319, group = "inspect" },  -- Ability_Spy (eye/viewing)
    { name = "SoundBrowser",  atlas = "common-icon-sound-pressed",  fileID = 133706, group = "inspect" },  -- INV_Misc_Bell_01 (bell/sound)
    -- Reference: browsing data
    { name = "APIBrowser",     atlas = "crosshair_speak_32",        fileID = 133739, group = "reference" },-- INV_Misc_Book_07 (blue book/docs)
    { name = "CVarViewer",     atlas = "Adventure-Mission-Silver-Dragon", fileID = 136243, group = "reference" }, -- Trade_Engineering (gear/settings)
    { name = "EventMonitor",   atlas = "Crosshair_mail_32",         fileID = 136048, group = "reference" },-- Spell_Nature_Lightning (live events)
    -- Diagnostics
    { name = "ErrorHandler",   atlas = "crosshair_crosshairs_32",   fileID = 136168, group = "diag" },     -- Spell_Fire_SealOfFire (warning)
    { name = "Performance",    atlas = "crosshair_track_32",        fileID = 134377, group = "diag" },     -- INV_Misc_PocketWatch_02 (stopwatch)
}

function ActivityBar:Create(parent)
    local L = DF.Layout

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(L.activityBarWidth)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    frame:SetBackdropColor(unpack(DF.Colors.activityBg))

    local bar = {
        frame = frame,
        buttons = {},   -- name -> button data
        ordered = {},   -- ordered list of button data
        active = nil,
    }

    -- Build buttons
    local yOffset = -4
    local lastGroup = nil

    for _, def in ipairs(MODULE_ICONS) do
        -- Add divider line between groups
        if lastGroup and def.group ~= lastGroup then
            yOffset = yOffset - L.activityGroupGap
            local divider = frame:CreateTexture(nil, "ARTWORK")
            divider:SetHeight(1)
            divider:SetPoint("LEFT", 8, 0)
            divider:SetPoint("RIGHT", -8, 0)
            divider:SetPoint("TOP", 0, yOffset)
            divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            yOffset = yOffset - L.activityGroupGap
        end
        lastGroup = def.group

        local btn = CreateFrame("Button", nil, frame)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetSize(L.activityBarWidth, L.activityBtnHeight)
        btn:SetPoint("TOPLEFT", 0, yOffset)

        -- Active indicator (left accent bar)
        local accent = btn:CreateTexture(nil, "OVERLAY")
        accent:SetSize(2, L.activityBtnHeight)
        accent:SetPoint("LEFT", 0, 0)
        accent:SetColorTexture(unpack(DF.Colors.activityActive))
        accent:Hide()

        -- Icon (uses inactive atlas/texture by default, swapped to active on selection)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(L.activityIconSize, L.activityIconSize)
        icon:SetPoint("CENTER", 1, 0) -- offset 1px right to account for accent bar
        local iconSet = false
        if not def.fileID or def.atlas then
            -- Try atlas first (preferred on Retail)
            if def.atlas then
                local atlasOk = pcall(function() icon:SetAtlas(def.atlas) end)
                if atlasOk and icon:GetAtlas() then
                    iconSet = true
                end
            elseif def.atlasOff then
                local atlasOk = pcall(function() icon:SetAtlas(def.atlasOff) end)
                if atlasOk and icon:GetAtlas() then
                    iconSet = true
                end
            end
        end
        if not iconSet and def.fileID then
            icon:SetTexture(def.fileID)
            iconSet = true
        end
        if iconSet then
            icon:SetDesaturated(true)
            icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            icon:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        end

        -- Hover highlight
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.25, 0.25, 0.28, 0.6)

        -- Badge (error/event count)
        local badge = CreateFrame("Frame", nil, btn)
        badge:SetSize(16, 12)
        badge:SetPoint("TOPRIGHT", -2, -2)
        badge:SetFrameLevel(btn:GetFrameLevel() + 2)
        badge:Hide()

        local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
        badgeBg:SetAllPoints()
        badgeBg:SetColorTexture(unpack(DF.Colors.badgeBg))

        local badgeText = badge:CreateFontString(nil, "OVERLAY")
        badgeText:SetFont(DF.Fonts.ui, 9, "OUTLINE")
        badgeText:SetPoint("CENTER", 0, 0)
        badgeText:SetTextColor(unpack(DF.Colors.badgeText))

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local label = DF.ModuleSystem:GetTabLabel(def.name)
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Click
        btn:SetScript("OnClick", function()
            DF.ModuleSystem:Activate(def.name)
        end)

        -- Track whether atlas was actually used (may fail on Classic)
        local usedAtlas = iconSet and not def.fileID or (iconSet and icon:GetAtlas() and icon:GetAtlas() ~= "")
        local entry = {
            name = def.name,
            btn = btn,
            accent = accent,
            icon = icon,
            usedAtlas = usedAtlas,
            fileID = def.fileID,
            atlas = def.atlas,
            atlasOff = def.atlasOff,
            atlasOn = def.atlasOn,
            badge = badge,
            badgeText = badgeText,
        }

        bar.buttons[def.name] = entry
        bar.ordered[#bar.ordered + 1] = entry

        yOffset = yOffset - L.activityBtnHeight
    end

    function bar:SetActive(moduleName)
        bar.active = moduleName
        for _, entry in ipairs(bar.ordered) do
            if entry.name == moduleName then
                entry.accent:Show()
                if entry.usedAtlas and entry.atlasOn then
                    pcall(function() entry.icon:SetAtlas(entry.atlasOn) end)
                else
                    entry.icon:SetDesaturated(false)
                    entry.icon:SetVertexColor(1, 1, 1)
                end
            else
                entry.accent:Hide()
                if entry.usedAtlas and entry.atlasOff then
                    pcall(function() entry.icon:SetAtlas(entry.atlasOff) end)
                else
                    entry.icon:SetDesaturated(true)
                    entry.icon:SetVertexColor(0.6, 0.6, 0.6)
                end
            end
        end
    end

    function bar:SetBadge(moduleName, count)
        local entry = bar.buttons[moduleName]
        if not entry then return end
        if count and count > 0 then
            entry.badgeText:SetText(count > 99 and "99+" or tostring(count))
            entry.badge:Show()
        else
            entry.badge:Hide()
        end
    end

    -- Listen for module activation
    DF.EventBus:On("DF_MODULE_ACTIVATED", function(name)
        bar:SetActive(name)
    end, bar)

    return bar
end
