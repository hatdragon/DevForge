local _, DF = ...

DF.Theme = {}

local Theme = DF.Theme

local BACKDROP_PANEL = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BACKDROP_PANEL_NOBORDER = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true,
    tileSize = 16,
}

local BACKDROP_DIALOG = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

-- Apply dark panel styling to a frame
function Theme:ApplyDarkPanel(frame, useBorder)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    if useBorder ~= false then
        frame:SetBackdrop(BACKDROP_PANEL)
        frame:SetBackdropBorderColor(unpack(DF.Colors.panelBorder))
    else
        frame:SetBackdrop(BACKDROP_PANEL_NOBORDER)
    end
    frame:SetBackdropColor(unpack(DF.Colors.panelBg))
end

-- Apply dialog chrome to the main window
function Theme:ApplyDialogChrome(frame)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop(BACKDROP_DIALOG)
    frame:SetBackdropColor(unpack(DF.Colors.panelBg))
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- Apply title bar styling
function Theme:ApplyTitleBar(frame, bg)
    if not bg.SetBackdrop then
        Mixin(bg, BackdropTemplateMixin)
    end
    bg:SetBackdrop(BACKDROP_PANEL_NOBORDER)
    bg:SetBackdropColor(unpack(DF.Colors.titleBg))
end

-- Font fallback paths: try each until one works
local CODE_FONT_PATHS = {
    "Fonts\\ARIALN.TTF",
    "Interface\\AddOns\\DevForge\\Fonts\\ARIALN.TTF",
    "Fonts\\FRIZQT__.TTF",  -- last resort
}
local UI_FONT_PATHS = {
    "Fonts\\FRIZQT__.TTF",
}

-- Font cache: reuse existing font objects across reloads
local fontCache = {}

local function ApplyFontPath(font, paths, size)
    for _, path in ipairs(paths) do
        pcall(font.SetFont, font, path, size, "")
        -- Verify the font actually loaded by checking GetFont
        local ok, fontFile = pcall(font.GetFont, font)
        if ok and fontFile then
            pcall(font.SetTextColor, font, 0.83, 0.83, 0.83, 1)
            return true
        end
    end
    return false
end

local function GetOrCreateFont(name, paths, size)
    if fontCache[name] then
        return fontCache[name]
    end

    -- Try reusing existing font object (persists across reloads as userdata)
    local existing = _G[name]
    if existing then
        local ok, hasMethod = pcall(function() return existing.SetFont ~= nil end)
        if ok and hasMethod and ApplyFontPath(existing, paths, size) then
            fontCache[name] = existing
            return existing
        end
    end

    -- Create new font object
    if not existing then
        local ok, newFont = pcall(CreateFont, name)
        if ok and newFont and ApplyFontPath(newFont, paths, size) then
            fontCache[name] = newFont
            return newFont
        end
    end

    -- All paths failed: fall back to a built-in font object
    return GameFontHighlightSmall
end

function Theme:GetCodeFont(size)
    size = size or DF.Layout.codeFontSize
    return GetOrCreateFont("DevForgeCodeFont" .. size, CODE_FONT_PATHS, size)
end

function Theme:GetUIFont(size)
    size = size or DF.Layout.uiFontSize
    return GetOrCreateFont("DevForgeUIFont" .. size, UI_FONT_PATHS, size)
end

-- Shared font objects (created on demand)
local codeFontObj, uiFontObj

function Theme:CodeFont()
    if not codeFontObj then
        codeFontObj = self:GetCodeFont()
    end
    return codeFontObj
end

function Theme:UIFont()
    if not uiFontObj then
        uiFontObj = self:GetUIFont()
    end
    return uiFontObj
end

-- Apply input field styling (works on both EditBox and plain Frame for backdrop-only)
function Theme:ApplyInputStyle(frame)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop(BACKDROP_PANEL)
    frame:SetBackdropColor(unpack(DF.Colors.inputBg))
    frame:SetBackdropBorderColor(unpack(DF.Colors.panelBorder))
    -- Font/text methods only exist on EditBox, not plain Frame
    if frame.SetFontObject then
        frame:SetFontObject(Theme:CodeFont())
        frame:SetTextColor(0.83, 0.83, 0.83, 1)
        frame:SetTextInsets(6, 6, 4, 4)
    end
end
