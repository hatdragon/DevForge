local _, DF = ...

DF.SnippetTemplates = {}

-- Ordered category list
DF.SnippetTemplates.categories = {
    "Addon Setup",
    "Event Handling",
    "Slash Commands",
    "UI Frames",
    "Data & Storage",
    "Hooks & Overrides",
    "Utilities",
}

-- Template entries: { id, category, name, desc, code, placeholders }
-- Placeholder syntax: $TOKEN in code, replaced via simple string substitution
DF.SnippetTemplates.templates = {
    ---------------------------------------------------------------------------
    -- Addon Setup
    ---------------------------------------------------------------------------
    {
        id = "setup_basic_shell",
        category = "Addon Setup",
        name = "Basic Addon Shell",
        desc = "Minimal addon skeleton with ADDON_LOADED, private namespace, and loaded message",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[local ADDON_NAME, ns = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Addon is loaded, initialize here
    print(ADDON_NAME .. " loaded")
end)]],
    },
    {
        id = "setup_full_lifecycle",
        category = "Addon Setup",
        name = "Full Lifecycle Addon",
        desc = "Complete addon init chain: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD, PLAYER_LOGOUT",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
            { token = "DB_NAME", label = "SavedVariable Name", default = "MyAddonDB" },
        },
        code = [[local ADDON_NAME, ns = ...
ns.loaded = false

local f = CreateFrame("Frame")

local function OnAddonLoaded()
    -- Fires once when your TOC is loaded. SavedVariables are available now.
    if not $DB_NAME then $DB_NAME = {} end
    ns.db = $DB_NAME
    ns.loaded = true
end

local function OnPlayerLogin()
    -- Fires once after all addons are loaded and the player exists.
    -- Safe to access player data, inspect talents, etc.
end

local function OnPlayerEnteringWorld(isLogin, isReload)
    -- Fires on every loading screen (login, reload, zone transitions).
    if isLogin or isReload then
        print(ADDON_NAME .. " ready")
    end
end

local function OnPlayerLogout()
    -- Last chance to write to SavedVariables before they're serialized.
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        OnPlayerLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld(...)
    elseif event == "PLAYER_LOGOUT" then
        OnPlayerLogout()
    end
end)]],
    },
    {
        id = "setup_namespace_module",
        category = "Addon Setup",
        name = "Namespace with Modules",
        desc = "Shared private table pattern for multi-file addons with module sub-tables",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[-- In every file: local ADDON_NAME, ns = ...
-- All files share the same 'ns' table automatically.
local ADDON_NAME, ns = ...

-- Create module sub-tables (each file can populate its own)
ns.Core = ns.Core or {}
ns.UI = ns.UI or {}
ns.Data = ns.Data or {}
ns.Util = ns.Util or {}

-- Example: Core module sets up init
function ns.Core:Init()
    print(ADDON_NAME .. " core initialized")
end

-- Example: other files just reference ns
-- ns.UI:CreateMainFrame()
-- ns.Data:LoadSettings()

-- Wire it up
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.Core:Init()
end)]],
    },
    {
        id = "setup_compartment",
        category = "Addon Setup",
        name = "Addon Compartment Button",
        desc = "Register a minimap addon compartment entry (click and tooltip handlers)",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[-- Requires these TOC fields:
-- ## IconTexture: Interface\Icons\INV_Misc_QuestionMark
-- ## AddonCompartmentFunc: MyAddon_OnCompartmentClick
-- ## AddonCompartmentFuncOnEnter: MyAddon_OnCompartmentEnter
-- ## AddonCompartmentFuncOnLeave: MyAddon_OnCompartmentLeave

function $ADDON_NAME_OnCompartmentClick(addonName, button)
    if button == "LeftButton" then
        -- Toggle your main frame
        print("$ADDON_NAME: left click")
    elseif button == "RightButton" then
        -- Open settings or context menu
        print("$ADDON_NAME: right click")
    end
end

function $ADDON_NAME_OnCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:AddLine("$ADDON_NAME", 1, 1, 1)
    GameTooltip:AddLine("Left-click to toggle", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function $ADDON_NAME_OnCompartmentLeave()
    GameTooltip:Hide()
end]],
    },
    {
        id = "setup_addon_channel",
        category = "Addon Setup",
        name = "Addon Communication",
        desc = "Send and receive hidden addon messages between players via RegisterAddonMessagePrefix",
        placeholders = {
            { token = "PREFIX", label = "Message Prefix", default = "MyAddonComm" },
        },
        code = [[local PREFIX = "$PREFIX"
local success = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
if not success then
    print("Failed to register prefix: " .. PREFIX)
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= PREFIX then return end

    -- Ignore messages from yourself
    local me = UnitName("player")
    if sender == me or sender:match("^" .. me .. "%-") then return end

    print(format("[%s] %s: %s (%s)", prefix, sender, message, channel))
end)

-- Send to party/raid:
-- C_ChatInfo.SendAddonMessage(PREFIX, "hello", "PARTY")
-- C_ChatInfo.SendAddonMessage(PREFIX, "hello", "RAID")
-- C_ChatInfo.SendAddonMessage(PREFIX, "hello", "GUILD")
-- Send to a specific player:
-- C_ChatInfo.SendAddonMessage(PREFIX, "hello", "WHISPER", "PlayerName")]],
    },
    {
        id = "setup_settings_category",
        category = "Addon Setup",
        name = "Settings Panel Registration",
        desc = "Register an addon settings category with checkboxes, sliders, and dropdowns",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
            { token = "DB_NAME", label = "SavedVariable Name", default = "MyAddonDB" },
        },
        code = [==[-- Register after SavedVariables are loaded (inside ADDON_LOADED handler)
local category = Settings.RegisterVerticalLayoutCategory("$ADDON_NAME")

-- Checkbox setting
Settings.CreateCheckbox(
    category,
    "Enable $ADDON_NAME",
    nil,
    function() return $DB_NAME.enabled ~= false end,
    function(value) $DB_NAME.enabled = value end,
    "Enable or disable $ADDON_NAME functionality"
)

-- Slider setting
Settings.CreateSlider(
    category,
    "Scale",
    nil,
    function() return $DB_NAME.scale or 1.0 end,
    function(value) $DB_NAME.scale = value end,
    0.5, 2.0, 0.1,
    "Adjust the UI scale"
)

-- Register the category so it shows in the options panel
Settings.RegisterAddOnCategory(category)

-- Open your settings: Settings.OpenToCategory(category:GetID())]==],
    },

    ---------------------------------------------------------------------------
    -- Event Handling
    ---------------------------------------------------------------------------
    {
        id = "event_basic",
        category = "Event Handling",
        name = "Basic Event Handler",
        desc = "Register for a single event with a handler function",
        placeholders = {
            { token = "EVENT_NAME", label = "Event Name", default = "PLAYER_ENTERING_WORLD" },
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[local f = CreateFrame("Frame")
f:RegisterEvent("$EVENT_NAME")
f:SetScript("OnEvent", function(self, event, ...)
    print("$ADDON_NAME: " .. event .. " fired")
end)]],
    },
    {
        id = "event_multi",
        category = "Event Handling",
        name = "Multi-Event Dispatch",
        desc = "Register multiple events with a dispatch table",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[local $ADDON_NAME = {}
local f = CreateFrame("Frame")

local handlers = {}

function handlers:PLAYER_ENTERING_WORLD(isLogin, isReload)
    if isLogin or isReload then
        print("$ADDON_NAME loaded")
    end
end

function handlers:PLAYER_LOGOUT()
    -- cleanup
end

f:SetScript("OnEvent", function(self, event, ...)
    if handlers[event] then
        handlers[event](handlers, ...)
    end
end)

for event in pairs(handlers) do
    f:RegisterEvent(event)
end]],
    },

    ---------------------------------------------------------------------------
    -- Slash Commands
    ---------------------------------------------------------------------------
    {
        id = "slash_basic",
        category = "Slash Commands",
        name = "Slash Command",
        desc = "Register a simple slash command with argument parsing",
        placeholders = {
            { token = "COMMAND", label = "Command (no slash)", default = "myaddon" },
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
        },
        code = [[SLASH_$ADDON_NAME1 = "/$COMMAND"
SlashCmdList["$ADDON_NAME"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        args[#args + 1] = word
    end
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "help" then
        print("$ADDON_NAME: /|cFF569CD6$COMMAND|r help - show this message")
    else
        print("$ADDON_NAME: use /|cFF569CD6$COMMAND|r help")
    end
end]],
    },
    {
        id = "slash_toggle",
        category = "Slash Commands",
        name = "Slash Toggle",
        desc = "Slash command that toggles a frame's visibility",
        placeholders = {
            { token = "COMMAND", label = "Command (no slash)", default = "myaddon" },
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
            { token = "FRAME_NAME", label = "Frame Variable", default = "MyAddonFrame" },
        },
        code = [[SLASH_$ADDON_NAME1 = "/$COMMAND"
SlashCmdList["$ADDON_NAME"] = function()
    if $FRAME_NAME and $FRAME_NAME:IsShown() then
        $FRAME_NAME:Hide()
    else
        if $FRAME_NAME then
            $FRAME_NAME:Show()
        end
    end
end]],
    },

    ---------------------------------------------------------------------------
    -- UI Frames
    ---------------------------------------------------------------------------
    {
        id = "frame_nineslice",
        category = "UI Frames",
        name = "Frame (NineSlice)",
        desc = "Frame using the NineSlice layout system with themed edge/corner pieces",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyNineSliceFrame" },
            { token = "WIDTH", label = "Width", default = "350" },
            { token = "HEIGHT", label = "Height", default = "250" },
        },
        code = [==[local f = CreateFrame("Frame", "$FRAME_NAME", UIParent, "NineSlicePanelTemplate")
f:SetSize($WIDTH, $HEIGHT)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)

-- Apply a built-in layout (see NineSliceLayouts table for options)
-- Common layouts: "BFAMissionHorde", "BFAMissionAlliance", "UniqueCornersLayout",
-- "InsetFrameTemplate", "SimplePanelTemplate", "PortraitFrameTemplate"
NineSliceUtil.ApplyUniqueCornersLayout(f, "BFAMissionHorde")

-- Background fill
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", 6, -6)
bg:SetPoint("BOTTOMRIGHT", -6, 6)
bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)

-- You can also apply a custom layout from a table:
--[[
local myLayout = {
    TopLeftCorner     = { atlas = "UI-Frame-Metal-CornerTopLeft" },
    TopRightCorner    = { atlas = "UI-Frame-Metal-CornerTopRight" },
    BottomLeftCorner  = { atlas = "UI-Frame-Metal-CornerBottomLeft" },
    BottomRightCorner = { atlas = "UI-Frame-Metal-CornerBottomRight" },
    TopEdge           = { atlas = "_UI-Frame-Metal-EdgeTop" },
    BottomEdge        = { atlas = "_UI-Frame-Metal-EdgeBottom" },
    LeftEdge          = { atlas = "!UI-Frame-Metal-EdgeLeft" },
    RightEdge         = { atlas = "!UI-Frame-Metal-EdgeRight" },
}
NineSliceUtil.ApplyLayout(f, myLayout)
]]]==],
    },
    {
        id = "frame_backdrop",
        category = "UI Frames",
        name = "Frame (Backdrop)",
        desc = "Basic Frame with a dark backdrop, border, movable and clamped",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyFrame" },
            { token = "WIDTH", label = "Width", default = "300" },
            { token = "HEIGHT", label = "Height", default = "200" },
        },
        code = [[local f = CreateFrame("Frame", "$FRAME_NAME", UIParent, "BackdropTemplate")
f:SetSize($WIDTH, $HEIGHT)
f:SetPoint("CENTER")
f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)]],
    },
    {
        id = "frame_draggable",
        category = "UI Frames",
        name = "Draggable Frame (Save Position)",
        desc = "Movable frame that saves and restores its position across sessions",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyDraggableFrame" },
            { token = "DB_NAME", label = "SavedVariable Name", default = "MyAddonDB" },
            { token = "WIDTH", label = "Width", default = "250" },
            { token = "HEIGHT", label = "Height", default = "160" },
        },
        code = [[local f = CreateFrame("Frame", "$FRAME_NAME", UIParent, "BackdropTemplate")
f:SetSize($WIDTH, $HEIGHT)
f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")

-- Save position when dragging stops
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Store the anchor so it persists across /reload
    if $DB_NAME then
        local point, _, relPoint, x, y = self:GetPoint()
        $DB_NAME.framePos = { point = point, relPoint = relPoint, x = x, y = y }
    end
end)

-- Restore saved position (call after SavedVariables load)
local function RestorePosition()
    local pos = $DB_NAME and $DB_NAME.framePos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("CENTER")
    end
end

RestorePosition()]],
    },
    {
        id = "frame_resizable_backdrop",
        category = "UI Frames",
        name = "Resizable Window (Backdrop)",
        desc = "Minimal resizable window with backdrop, drag-to-move title area, and corner resize grip",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyResizableFrame" },
            { token = "WIDTH", label = "Width", default = "300" },
            { token = "HEIGHT", label = "Height", default = "220" },
        },
        code = [[local f = CreateFrame("Frame", "$FRAME_NAME", UIParent, "BackdropTemplate")
f:SetSize($WIDTH, $HEIGHT)
f:SetPoint("CENTER")
f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
f:SetMovable(true)
f:SetResizable(true)
f:SetResizeBounds(180, 120, 600, 500)
f:EnableMouse(true)
f:SetClampedToScreen(true)

-- Drag-to-move via the top 24px
local titleHit = CreateFrame("Frame", nil, f)
titleHit:SetHeight(24)
titleHit:SetPoint("TOPLEFT", 4, -4)
titleHit:SetPoint("TOPRIGHT", -4, -4)
titleHit:EnableMouse(true)
titleHit:RegisterForDrag("LeftButton")
titleHit:SetScript("OnDragStart", function() f:StartMoving() end)
titleHit:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

-- Resize grip (bottom-right corner)
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
end)]],
    },
    {
        id = "frame_resizable_window",
        category = "UI Frames",
        name = "Resizable Window (Decorated)",
        desc = "Full window with title bar, close button, resize grip, and content area",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyWindow" },
            { token = "TITLE", label = "Window Title", default = "My Window" },
            { token = "WIDTH", label = "Width", default = "400" },
            { token = "HEIGHT", label = "Height", default = "300" },
        },
        code = [==[local f = CreateFrame("Frame", "$FRAME_NAME", UIParent, "BackdropTemplate")
f:SetSize($WIDTH, $HEIGHT)
f:SetPoint("CENTER")
f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
f:SetMovable(true)
f:SetResizable(true)
f:SetResizeBounds(250, 180, 800, 600)
f:EnableMouse(true)
f:SetClampedToScreen(true)
tinsert(UISpecialFrames, "$FRAME_NAME") -- close on Escape

-- Title bar
local titleBar = CreateFrame("Frame", nil, f)
titleBar:SetHeight(28)
titleBar:SetPoint("TOPLEFT", 8, -8)
titleBar:SetPoint("TOPRIGHT", -8, -8)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0.15, 0.15, 0.17, 1)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", 8, 0)
titleText:SetText("$TITLE")
titleText:SetTextColor(0.6, 0.75, 1.0, 1)

-- Close button
local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(18, 18)
closeBtn:SetPoint("RIGHT", -2, 0)
local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeTex:SetPoint("CENTER")
closeTex:SetText("x")
closeTex:SetTextColor(0.6, 0.6, 0.6, 1)
closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3, 1) end)
closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.6, 0.6, 0.6, 1) end)
closeBtn:SetScript("OnClick", function() f:Hide() end)

-- Content area (anchored below title bar, above bottom edge)
local content = CreateFrame("Frame", nil, f)
content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
content:SetPoint("BOTTOMRIGHT", -10, 10)

-- Resize grip
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -4, 4)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
end)

-- Use 'content' as the parent for your window contents]==],
    },
    {
        id = "frame_button",
        category = "UI Frames",
        name = "Button",
        desc = "Clickable Button with normal/highlight/pushed textures and a label",
        placeholders = {
            { token = "BUTTON_NAME", label = "Global Name", default = "MyButton" },
        },
        code = [[local btn = CreateFrame("Button", "$BUTTON_NAME", UIParent, "BackdropTemplate")
btn:SetSize(120, 28)
btn:SetPoint("CENTER")
btn:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
btn:SetBackdropColor(0.18, 0.18, 0.20, 1)
btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("CENTER")
label:SetText("Click Me")

btn:SetScript("OnClick", function(self, button)
    print("$BUTTON_NAME clicked with " .. button)
end)
btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.25, 0.25, 0.28, 1)
end)
btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.18, 0.18, 0.20, 1)
end)]],
    },
    {
        id = "frame_check_button",
        category = "UI Frames",
        name = "CheckButton",
        desc = "Toggle checkbox with a label and OnClick handler",
        placeholders = {
            { token = "CB_NAME", label = "Global Name", default = "MyCheckButton" },
            { token = "LABEL", label = "Label Text", default = "Enable Feature" },
        },
        code = [[local cb = CreateFrame("CheckButton", "$CB_NAME", UIParent, "UICheckButtonTemplate")
cb:SetPoint("CENTER")

-- The template provides a .text FontString
if cb.text then
    cb.text:SetText("$LABEL")
    cb.text:SetFontObject("GameFontNormal")
end

cb:SetScript("OnClick", function(self)
    local checked = self:GetChecked()
    print("$CB_NAME is now " .. (checked and "checked" or "unchecked"))
end)]],
    },
    {
        id = "frame_editbox",
        category = "UI Frames",
        name = "EditBox",
        desc = "Text input field with enter/escape handling",
        placeholders = {
            { token = "EB_NAME", label = "Global Name", default = "MyEditBox" },
            { token = "WIDTH", label = "Width", default = "200" },
        },
        code = [[local eb = CreateFrame("EditBox", "$EB_NAME", UIParent, "BackdropTemplate")
eb:SetSize($WIDTH, 28)
eb:SetPoint("CENTER")
eb:SetFontObject("ChatFontNormal")
eb:SetTextColor(1, 1, 1, 1)
eb:SetAutoFocus(false)
eb:SetMaxLetters(256)
eb:SetTextInsets(8, 8, 4, 4)
eb:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
eb:SetBackdropColor(0.08, 0.08, 0.10, 1)
eb:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

eb:SetScript("OnEnterPressed", function(self)
    print("Entered: " .. self:GetText())
    self:ClearFocus()
end)
eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)]],
    },
    {
        id = "frame_scrollframe",
        category = "UI Frames",
        name = "ScrollFrame",
        desc = "Scrollable container with a child frame and mouse wheel support",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyScrollFrame" },
            { token = "WIDTH", label = "Width", default = "250" },
            { token = "HEIGHT", label = "Height", default = "200" },
        },
        code = [[local sf = CreateFrame("ScrollFrame", "$FRAME_NAME", UIParent)
sf:SetSize($WIDTH, $HEIGHT)
sf:SetPoint("CENTER")

-- Scrollable child (taller than the viewport)
local child = CreateFrame("Frame", nil, sf)
child:SetSize($WIDTH, 600)
sf:SetScrollChild(child)

-- Example content
for i = 1, 20 do
    local text = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 8, -(i - 1) * 24)
    text:SetText("Row " .. i)
end

-- Mouse wheel scrolling
sf:EnableMouseWheel(true)
sf:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local maxScroll = child:GetHeight() - self:GetHeight()
    local newScroll = math.max(0, math.min(current - delta * 30, maxScroll))
    self:SetVerticalScroll(newScroll)
end)]],
    },
    {
        id = "frame_slider",
        category = "UI Frames",
        name = "Slider",
        desc = "Horizontal slider with min/max labels and value display",
        placeholders = {
            { token = "SLIDER_NAME", label = "Global Name", default = "MySlider" },
            { token = "MIN_VAL", label = "Min Value", default = "0" },
            { token = "MAX_VAL", label = "Max Value", default = "100" },
        },
        code = [[local slider = CreateFrame("Slider", "$SLIDER_NAME", UIParent, "OptionsSliderTemplate")
slider:SetSize(200, 20)
slider:SetPoint("CENTER")
slider:SetMinMaxValues($MIN_VAL, $MAX_VAL)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)
slider:SetValue($MIN_VAL)

-- Labels (provided by template)
if slider.Low then slider.Low:SetText("$MIN_VAL") end
if slider.High then slider.High:SetText("$MAX_VAL") end
if slider.Text then slider.Text:SetText("$SLIDER_NAME") end

slider:SetScript("OnValueChanged", function(self, value)
    print("$SLIDER_NAME value: " .. math.floor(value))
end)]],
    },
    {
        id = "frame_statusbar",
        category = "UI Frames",
        name = "StatusBar",
        desc = "Progress/health bar with color and value text overlay",
        placeholders = {
            { token = "BAR_NAME", label = "Global Name", default = "MyStatusBar" },
            { token = "WIDTH", label = "Width", default = "200" },
        },
        code = [[local bar = CreateFrame("StatusBar", "$BAR_NAME", UIParent)
bar:SetSize($WIDTH, 20)
bar:SetPoint("CENTER")
bar:SetMinMaxValues(0, 100)
bar:SetValue(75)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)

-- Background
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

-- Border
local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
border:SetPoint("TOPLEFT", -2, 2)
border:SetPoint("BOTTOMRIGHT", 2, -2)
border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- Value text
local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER")
text:SetText("75%")

bar:SetScript("OnValueChanged", function(self, value)
    text:SetText(math.floor(value) .. "%")
end)]],
    },
    {
        id = "frame_cooldown",
        category = "UI Frames",
        name = "Cooldown",
        desc = "Cooldown sweep overlay on an icon, like ability cooldowns",
        placeholders = {
            { token = "ICON_ID", label = "Icon FileID or Path", default = "136243" },
            { token = "DURATION", label = "Duration (sec)", default = "10" },
        },
        code = [[-- Parent button to hold the icon
local btn = CreateFrame("Button", nil, UIParent)
btn:SetSize(48, 48)
btn:SetPoint("CENTER")

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture($ICON_ID)

-- Cooldown overlay
local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
cd:SetAllPoints()

-- Start a cooldown sweep: (start, duration)
cd:SetCooldown(GetTime(), $DURATION)

-- Click to restart the cooldown
btn:SetScript("OnClick", function()
    cd:SetCooldown(GetTime(), $DURATION)
    print("Cooldown restarted for $DURATION seconds")
end)]],
    },
    {
        id = "frame_gametooltip",
        category = "UI Frames",
        name = "GameTooltip (Custom)",
        desc = "Custom tooltip frame with multi-line text, usable anywhere",
        code = [[local tip = CreateFrame("GameTooltip", "MyCustomTooltip", UIParent, "GameTooltipTemplate")

-- Show the tooltip on a target frame (or just at CENTER for demo)
local anchor = UIParent
tip:SetOwner(anchor, "ANCHOR_CURSOR")
tip:AddLine("Custom Tooltip Title", 0.4, 0.7, 1.0)
tip:AddLine("This is a description line.", 1, 1, 1, true)
tip:AddDoubleLine("Left side", "Right side", 0.8, 0.8, 0.8, 0.6, 0.8, 0.2)
tip:AddLine(" ")
tip:AddLine("Hint: you can anchor this to any frame", 0.5, 0.5, 0.5, true)
tip:Show()

-- To hide later: tip:Hide()]],
    },
    {
        id = "frame_colorselect",
        category = "UI Frames",
        name = "ColorSelect",
        desc = "Color picker wheel with brightness slider and preview swatch",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyColorPicker" },
        },
        code = [[local picker = CreateFrame("ColorSelect", "$FRAME_NAME", UIParent)
picker:SetSize(180, 180)
picker:SetPoint("CENTER")

-- The color wheel texture (required)
local wheel = picker:CreateTexture(nil, "ARTWORK")
wheel:SetSize(128, 128)
wheel:SetPoint("TOPLEFT", 8, -8)
picker:SetColorWheelTexture(wheel)

-- Thumb on the wheel
local wheelThumb = picker:CreateTexture(nil, "OVERLAY")
wheelThumb:SetSize(10, 10)
wheelThumb:SetColorTexture(1, 1, 1, 1)
picker:SetColorWheelThumbTexture(wheelThumb)

-- Brightness slider
local slider = picker:CreateTexture(nil, "ARTWORK")
slider:SetSize(16, 128)
slider:SetPoint("LEFT", wheel, "RIGHT", 12, 0)
picker:SetColorValueTexture(slider)

-- Slider thumb
local sliderThumb = picker:CreateTexture(nil, "OVERLAY")
sliderThumb:SetSize(20, 8)
sliderThumb:SetColorTexture(1, 1, 1, 1)
picker:SetColorValueThumbTexture(sliderThumb)

-- Preview swatch
local swatch = picker:CreateTexture(nil, "OVERLAY")
swatch:SetSize(30, 30)
swatch:SetPoint("BOTTOM", 0, 4)

picker:SetScript("OnColorSelect", function(self, r, g, b)
    swatch:SetColorTexture(r, g, b, 1)
    print(format("Color: %.2f, %.2f, %.2f", r, g, b))
end)

picker:SetColorRGB(0.3, 0.6, 1.0)]],
    },
    {
        id = "frame_simplehtml",
        category = "UI Frames",
        name = "SimpleHTML",
        desc = "Rich text display supporting basic HTML tags (h1, p, br, a)",
        placeholders = {
            { token = "WIDTH", label = "Width", default = "300" },
            { token = "HEIGHT", label = "Height", default = "200" },
        },
        code = [==[local html = CreateFrame("SimpleHTML", nil, UIParent)
html:SetSize($WIDTH, $HEIGHT)
html:SetPoint("CENTER")

-- Set fonts for each HTML element
html:SetFont("h1", "Fonts\\FRIZQT__.TTF", 16, "")
html:SetFont("h2", "Fonts\\FRIZQT__.TTF", 13, "")
html:SetFont("p",  "Fonts\\FRIZQT__.TTF", 11, "")

html:SetTextColor("h1", 0.4, 0.7, 1.0, 1)
html:SetTextColor("h2", 0.8, 0.8, 0.5, 1)
html:SetTextColor("p",  0.83, 0.83, 0.83, 1)

local content = [[
<html><body>
<h1>SimpleHTML Example</h1>
<p>This frame renders basic HTML markup.</p>
<br/>
<h2>Supported Tags</h2>
<p>h1, h2, h3, p, br, a (hyperlinks), img</p>
<p>Useful for formatted help text or changelogs.</p>
</body></html>
]]
html:SetText(content)]==],
    },
    {
        id = "frame_messageframe",
        category = "UI Frames",
        name = "MessageFrame",
        desc = "Scrolling combat-text style frame with fading messages",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyMessageFrame" },
            { token = "WIDTH", label = "Width", default = "300" },
            { token = "HEIGHT", label = "Height", default = "150" },
        },
        code = [[local mf = CreateFrame("MessageFrame", "$FRAME_NAME", UIParent)
mf:SetSize($WIDTH, $HEIGHT)
mf:SetPoint("CENTER")
mf:SetFontObject("GameFontNormal")
mf:SetJustifyH("CENTER")
mf:SetFading(true)
mf:SetFadeDuration(1.5)
mf:SetTimeVisible(3)
mf:SetInsertMode("TOP")

-- Background so you can see the area
local bg = mf:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.4)

-- Add some messages
mf:AddMessage("Welcome!", 0.4, 0.7, 1.0)
mf:AddMessage("Messages fade out after 3 seconds", 0.8, 0.8, 0.8)
mf:AddMessage("New messages appear at the top", 0.6, 0.8, 0.2)]],
    },
    {
        id = "frame_scrolling_message",
        category = "UI Frames",
        name = "ScrollingMessageFrame",
        desc = "Chat-log style frame with scrollback, mouse wheel, and history",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyLogFrame" },
            { token = "WIDTH", label = "Width", default = "350" },
            { token = "HEIGHT", label = "Height", default = "180" },
        },
        code = [[local smf = CreateFrame("ScrollingMessageFrame", "$FRAME_NAME", UIParent, "BackdropTemplate")
smf:SetSize($WIDTH, $HEIGHT)
smf:SetPoint("CENTER")
smf:SetFontObject("GameFontNormal")
smf:SetJustifyH("LEFT")
smf:SetFading(false)
smf:SetMaxLines(200)
smf:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
smf:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
smf:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- Mouse wheel scrolling
smf:EnableMouseWheel(true)
smf:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
        self:ScrollUp()
    else
        self:ScrollDown()
    end
end)

-- Add some log lines
for i = 1, 25 do
    smf:AddMessage(format("[%s] Log entry %d", date("%H:%M:%S"), i), 0.83, 0.83, 0.83)
end]],
    },
    {
        id = "frame_model_scene",
        category = "UI Frames",
        name = "ModelScene",
        desc = "3D model viewer with camera controls (creatures, items, players)",
        placeholders = {
            { token = "FRAME_NAME", label = "Global Name", default = "MyModelScene" },
            { token = "DISPLAY_ID", label = "CreatureDisplayID", default = "31156" },
        },
        code = [[local scene = CreateFrame("ModelScene", "$FRAME_NAME", UIParent)
scene:SetSize(200, 250)
scene:SetPoint("CENTER")

-- Background
local bg = scene:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.05, 0.05, 0.07, 0.9)

-- Add an actor to display a creature model
local actor = scene:CreateActor()
actor:SetUseCenterForOrigin(true, true, true)

-- SetModelByCreatureDisplayID expects a number
actor:SetModelByCreatureDisplayID($DISPLAY_ID)
actor:SetPosition(0, 0, 0)

-- Allow mouse rotation
scene:SetScript("OnMouseWheel", function(self, delta)
    local actor = self:GetActorAtIndex(1)
    if actor then
        local yaw = actor:GetYaw() or 0
        actor:SetYaw(yaw + delta * 0.3)
    end
end)]],
    },
    {
        id = "frame_secure_button",
        category = "UI Frames",
        name = "SecureActionButton",
        desc = "Protected button for casting spells or running macros in combat",
        placeholders = {
            { token = "BUTTON_NAME", label = "Global Name", default = "MySecureButton" },
            { token = "ACTION_TYPE", label = "Action Type", default = "macro" },
            { token = "ACTION_BODY", label = "Action Body", default = "/say Hello!" },
        },
        code = [[local btn = CreateFrame("Button", "$BUTTON_NAME", UIParent, "SecureActionButtonTemplate")
btn:SetSize(40, 40)
btn:SetPoint("CENTER")
btn:SetAttribute("type", "$ACTION_TYPE")
btn:SetAttribute("$ACTION_TYPE", "$ACTION_BODY")

-- Visual
local tex = btn:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetColorTexture(0.2, 0.4, 0.6, 0.8)

local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("CENTER")
label:SetText("Go")

btn:RegisterForClicks("AnyUp", "AnyDown")]],
    },

    ---------------------------------------------------------------------------
    -- Data & Storage
    ---------------------------------------------------------------------------
    {
        id = "savedvars_init",
        category = "Data & Storage",
        name = "SavedVariables Init",
        desc = "Initialize saved variables with defaults on ADDON_LOADED",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
            { token = "DB_NAME", label = "SavedVariable Name", default = "MyAddonDB" },
        },
        code = [[local DEFAULTS = {
    enabled = true,
    scale = 1.0,
    position = { point = "CENTER", x = 0, y = 0 },
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon ~= "$ADDON_NAME" then return end
    self:UnregisterEvent("ADDON_LOADED")

    if not $DB_NAME then
        $DB_NAME = {}
    end

    -- Apply defaults for missing keys
    for k, v in pairs(DEFAULTS) do
        if $DB_NAME[k] == nil then
            if type(v) == "table" then
                $DB_NAME[k] = CopyTable(v)
            else
                $DB_NAME[k] = v
            end
        end
    end

    print("$ADDON_NAME: settings loaded")
end)]],
    },
    {
        id = "settings_panel",
        category = "Data & Storage",
        name = "Settings Panel",
        desc = "Create a basic Settings category panel using the Settings API",
        placeholders = {
            { token = "ADDON_NAME", label = "Addon Name", default = "MyAddon" },
            { token = "DB_NAME", label = "SavedVariable Name", default = "MyAddonDB" },
        },
        code = [[local category = Settings.RegisterVerticalLayoutCategory("$ADDON_NAME")

Settings.RegisterAddOnCategory(category)

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon ~= "$ADDON_NAME" then return end
    self:UnregisterEvent("ADDON_LOADED")

    if not $DB_NAME then $DB_NAME = {} end
    if $DB_NAME.enabled == nil then $DB_NAME.enabled = true end

    local initializer = Settings.CreateCheckbox(
        category,
        "Enabled",
        nil,
        function() return $DB_NAME.enabled end,
        function(value) $DB_NAME.enabled = value end,
        "$ADDON_NAME: Enable or disable the addon"
    )
end)]],
    },

    ---------------------------------------------------------------------------
    -- Hooks & Overrides
    ---------------------------------------------------------------------------
    {
        id = "hook_secure",
        category = "Hooks & Overrides",
        name = "Secure Hook",
        desc = "Post-hook a global function without tainting it",
        placeholders = {
            { token = "FUNC_NAME", label = "Function Name", default = "TargetFrame_Update" },
        },
        code = [[hooksecurefunc("$FUNC_NAME", function(...)
    -- This runs after the original function
    -- Arguments are the same as the original call
    local args = { ... }
    print("$FUNC_NAME called with", #args, "args")
end)]],
    },
    {
        id = "hook_script",
        category = "Hooks & Overrides",
        name = "HookScript",
        desc = "Hook a widget script handler (runs after the original)",
        placeholders = {
            { token = "FRAME_REF", label = "Frame Reference", default = "PlayerFrame" },
            { token = "SCRIPT_NAME", label = "Script Name", default = "OnEnter" },
        },
        code = [[-- HookScript runs your function AFTER the original handler
$FRAME_REF:HookScript("$SCRIPT_NAME", function(self, ...)
    print("$SCRIPT_NAME fired on " .. (self:GetName() or "anonymous frame"))
end)]],
    },

    ---------------------------------------------------------------------------
    -- Utilities
    ---------------------------------------------------------------------------
    {
        id = "util_timer",
        category = "Utilities",
        name = "Repeating Timer",
        desc = "Set up a repeating timer using C_Timer",
        placeholders = {
            { token = "INTERVAL", label = "Interval (seconds)", default = "5" },
        },
        code = [[local function OnTick()
    -- Your repeating logic here
    print("Timer tick at " .. date("%H:%M:%S"))
end

local ticker = C_Timer.NewTicker($INTERVAL, OnTick)

-- To stop later: ticker:Cancel()]],
    },
    {
        id = "util_debug_print",
        category = "Utilities",
        name = "Debug Print Table",
        desc = "Recursively print a table's contents for debugging",
        code = [[local function PrintTable(tbl, indent, seen)
    indent = indent or 0
    seen = seen or {}
    if seen[tbl] then
        print(string.rep("  ", indent) .. "(circular reference)")
        return
    end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        local prefix = string.rep("  ", indent)
        if type(v) == "table" then
            print(prefix .. tostring(k) .. ":")
            PrintTable(v, indent + 1, seen)
        else
            print(prefix .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Usage: PrintTable(someTable)]],
    },
}

-- Build a lookup table: id -> template
DF.SnippetTemplates.byId = {}
for _, tmpl in ipairs(DF.SnippetTemplates.templates) do
    DF.SnippetTemplates.byId[tmpl.id] = tmpl
end
