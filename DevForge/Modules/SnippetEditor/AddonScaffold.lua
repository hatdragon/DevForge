local _, DF = ...

DF.AddonScaffold = {}

local Scaffold = DF.AddonScaffold

local dialog = nil

---------------------------------------------------------------------------
-- Local UI helpers (same patterns as FrameBuilder)
---------------------------------------------------------------------------

local function CreateCheckbox(parent, labelText, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(14, 14)

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 1)

    local border = cb:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", -2, 2)
    check:SetColorTexture(0.3, 0.5, 0.8, 1)
    cb:SetCheckedTexture(check)

    local label = cb:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(DF.Theme:UIFont())
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.83, 0.83, 0.83, 1)

    cb:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)

    return cb
end

local function CreateTextInput(parent, labelText, defaultText, width, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(DF.Theme:UIFont())
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.65, 0.65, 0.65, 1)
    label:SetWidth(80)
    label:SetJustifyH("RIGHT")

    local input = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    input:SetPoint("LEFT", label, "RIGHT", 4, 0)
    input:SetSize(width or 180, 20)
    input:SetAutoFocus(false)
    input:SetFontObject(DF.Theme:UIFont())
    input:SetTextColor(0.83, 0.83, 0.83, 1)
    input:SetMaxLetters(200)
    input:SetText(defaultText or "")
    DF.Theme:ApplyInputStyle(input)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnTextChanged", function(self, userInput)
        if userInput and onChange then onChange(self:GetText()) end
    end)

    local wrapper = { frame = row, input = input }
    function wrapper:GetText() return input:GetText() or "" end
    function wrapper:SetText(t) input:SetText(t or "") end
    return wrapper
end

-- File selector button with dropdown
local function CreateFileSelector(parent, files, default, onChange)
    local btn = DF.Widgets:CreateButton(parent, default or files[1], 130)
    local current = default or files[1]
    local menu = DF.Widgets:CreateDropDown()

    btn:SetScript("OnClick", function(self)
        local menuItems = {}
        for _, file in ipairs(files) do
            menuItems[#menuItems + 1] = {
                text = file,
                func = function()
                    current = file
                    btn:SetLabel(file)
                    if onChange then onChange(file) end
                end,
            }
        end
        menu:Show(self, menuItems)
    end)

    local selector = { button = btn }
    function selector:GetValue() return current end
    return selector
end

---------------------------------------------------------------------------
-- Code generation
---------------------------------------------------------------------------

local function GenerateTOC(state)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local name = state.addonName ~= "" and state.addonName or "MyAddon"
    add("## Interface: 120000, 120001")
    add("## Title: " .. name)
    add("## Notes: " .. (state.description ~= "" and state.description or name))
    add("## Author: " .. (state.author ~= "" and state.author or "Unknown"))
    add("## Version: " .. (state.version ~= "" and state.version or "1.0.0"))
    if state.savedVars then
        add("## SavedVariables: " .. name .. "DB")
    end
    add("")
    add("Init.lua")
    if state.optionsPanel then
        add("Options.lua")
    end

    return table.concat(lines, "\n")
end

local function GenerateInit(state)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local name = state.addonName ~= "" and state.addonName or "MyAddon"
    local dbName = name .. "DB"

    add("local ADDON_NAME, ns = ...")
    add("ns." .. name .. " = {}")
    add("")
    add("local f = CreateFrame(\"Frame\")")
    add('f:RegisterEvent("ADDON_LOADED")')

    if state.eventFrame then
        add('f:RegisterEvent("PLAYER_ENTERING_WORLD")')
    end

    add("")
    add("f:SetScript(\"OnEvent\", function(self, event, ...)")
    add("    if event == \"ADDON_LOADED\" then")
    add("        local addon = ...")
    add("        if addon ~= ADDON_NAME then return end")
    add('        self:UnregisterEvent("ADDON_LOADED")')

    if state.savedVars then
        add("")
        add("        -- Initialize saved variables")
        add("        if not " .. dbName .. " then")
        add("            " .. dbName .. " = {}")
        add("        end")
    end

    add("")
    add('        print("|cFF569CD6" .. ADDON_NAME .. "|r loaded")')

    if state.slashCommand then
        add("")
        add("        -- Register slash command")
        add('        SLASH_' .. name:upper() .. '1 = "/' .. name:lower() .. '"')
        add('        SlashCmdList["' .. name:upper() .. '"] = function(msg)')
        add("            local cmd = msg:match(\"%S+\") or \"\"")
        add('            if cmd:lower() == "help" then')
        add('                print(ADDON_NAME .. ": /' .. name:lower() .. ' help")')
        add("            else")
        add('                print(ADDON_NAME .. ": use /' .. name:lower() .. ' help")')
        add("            end")
        add("        end")
    end

    add("    end")

    if state.eventFrame then
        add("")
        add('    if event == "PLAYER_ENTERING_WORLD" then')
        add("        local isLogin, isReload = ...")
        add("        if isLogin or isReload then")
        add("            -- First login or reload")
        add("        end")
        add("    end")
    end

    add("end)")

    return table.concat(lines, "\n")
end

local function GenerateOptions(state)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local name = state.addonName ~= "" and state.addonName or "MyAddon"
    local dbName = name .. "DB"

    add("local ADDON_NAME, ns = ...")
    add("")
    add('local category = Settings.RegisterVerticalLayoutCategory("' .. name .. '")')
    add("Settings.RegisterAddOnCategory(category)")
    add("")
    add("-- Add settings here after " .. dbName .. " is initialized")
    add("-- Example:")
    add("-- Settings.CreateCheckbox(category, \"Enabled\", nil,")
    add("--     function() return " .. dbName .. ".enabled end,")
    add("--     function(value) " .. dbName .. ".enabled = value end,")
    add('--     "Enable or disable ' .. name .. '"')
    add("-- )")

    return table.concat(lines, "\n")
end

local function GenerateAllFiles(state)
    local name = state.addonName ~= "" and state.addonName or "MyAddon"
    local parts = {}
    parts[#parts + 1] = "======== FILE: " .. name .. ".toc ========"
    parts[#parts + 1] = GenerateTOC(state)
    parts[#parts + 1] = ""
    parts[#parts + 1] = "======== FILE: Init.lua ========"
    parts[#parts + 1] = GenerateInit(state)
    if state.optionsPanel then
        parts[#parts + 1] = ""
        parts[#parts + 1] = "======== FILE: Options.lua ========"
        parts[#parts + 1] = GenerateOptions(state)
    end
    return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Dialog creation (singleton)
---------------------------------------------------------------------------

local function GetDialog()
    if dialog then return dialog end

    local frame = CreateFrame("Frame", "DevForgeAddonScaffold", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetSize(480, 480)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    DF.Theme:ApplyDialogChrome(frame)
    tinsert(UISpecialFrames, "DevForgeAddonScaffold")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", 12, -12)
    titleBar:SetPoint("TOPRIGHT", -12, -12)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then frame:StartMoving() end
    end)
    titleBar:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFontObject(DF.Theme:UIFont())
    titleText:SetPoint("LEFT", 4, 0)
    titleText:SetText("Addon Scaffold")
    titleText:SetTextColor(0.6, 0.75, 1, 1)

    -- Form area
    local formArea = CreateFrame("Frame", nil, frame)
    formArea:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -6)
    formArea:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -6)

    -- State
    local state = {
        addonName = "",
        author = "",
        description = "",
        version = "1.0.0",
        savedVars = false,
        slashCommand = false,
        eventFrame = false,
        optionsPanel = false,
    }

    local projectCallback = nil
    local codePreview = nil
    local currentFile = "TOC"
    local regenerateTimer = nil

    local function GetCurrentFileCode()
        if currentFile == "TOC" then
            return GenerateTOC(state)
        elseif currentFile == "Init.lua" then
            return GenerateInit(state)
        elseif currentFile == "Options.lua" then
            return GenerateOptions(state)
        end
        return ""
    end

    local function ScheduleRegenerate()
        if regenerateTimer then regenerateTimer:Cancel() end
        regenerateTimer = C_Timer.NewTimer(0.15, function()
            regenerateTimer = nil
            if codePreview then
                codePreview:SetText(GetCurrentFileCode())
            end
        end)
    end

    local function OnFieldChanged()
        ScheduleRegenerate()
    end

    -- Layout
    local yOff = 0

    local nameInput = CreateTextInput(formArea, "Addon:", "", 200, function(val)
        state.addonName = val
        OnFieldChanged()
    end)
    nameInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    nameInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 24

    local authorInput = CreateTextInput(formArea, "Author:", "", 200, function(val)
        state.author = val
        OnFieldChanged()
    end)
    authorInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    authorInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 24

    local descInput = CreateTextInput(formArea, "Notes:", "", 200, function(val)
        state.description = val
        OnFieldChanged()
    end)
    descInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    descInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 24

    local versionInput = CreateTextInput(formArea, "Version:", "1.0.0", 100, function(val)
        state.version = val
        OnFieldChanged()
    end)
    versionInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    versionInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 28

    -- Feature checkboxes
    local featLabel = formArea:CreateFontString(nil, "OVERLAY")
    featLabel:SetFontObject(DF.Theme:UIFont())
    featLabel:SetPoint("TOPLEFT", 4, -yOff)
    featLabel:SetText("Features:")
    featLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    yOff = yOff + 16

    local feats = {
        { key = "savedVars",    label = "SavedVariables" },
        { key = "slashCommand", label = "Slash command" },
        { key = "eventFrame",   label = "Event frame" },
        { key = "optionsPanel", label = "Options panel" },
    }

    for i, feat in ipairs(feats) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local cb = CreateCheckbox(formArea, feat.label, function(checked)
            state[feat.key] = checked
            OnFieldChanged()
        end)
        cb:SetPoint("TOPLEFT", 8 + col * 200, -(yOff + row * 18))
    end
    yOff = yOff + math.ceil(#feats / 2) * 18 + 6

    formArea:SetHeight(yOff)

    -- File selector row
    local fileSelectorRow = CreateFrame("Frame", nil, frame)
    fileSelectorRow:SetHeight(24)
    fileSelectorRow:SetPoint("TOPLEFT", formArea, "BOTTOMLEFT", 0, -4)
    fileSelectorRow:SetPoint("TOPRIGHT", formArea, "BOTTOMRIGHT", 0, -4)

    local fileLabel = fileSelectorRow:CreateFontString(nil, "OVERLAY")
    fileLabel:SetFontObject(DF.Theme:UIFont())
    fileLabel:SetPoint("LEFT", 4, 0)
    fileLabel:SetText("Preview:")
    fileLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local fileSelector = CreateFileSelector(fileSelectorRow, { "TOC", "Init.lua", "Options.lua" }, "TOC", function(file)
        currentFile = file
        if codePreview then
            codePreview:SetText(GetCurrentFileCode())
        end
    end)
    fileSelector.button:SetPoint("LEFT", fileLabel, "RIGHT", 4, 0)

    -- Code preview
    codePreview = DF.Widgets:CreateCodeEditBox(frame, { multiLine = true, readOnly = true })
    codePreview.frame:SetPoint("TOPLEFT", fileSelectorRow, "BOTTOMLEFT", 0, -2)
    codePreview.frame:SetPoint("BOTTOMRIGHT", -12, 40)

    -- Initial code
    codePreview:SetText(GetCurrentFileCode())

    -- Bottom buttons
    local cancelBtn = DF.Widgets:CreateButton(frame, "Cancel", 60)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)

    local createProjectBtn = DF.Widgets:CreateButton(frame, "Create Project", 105)
    createProjectBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -4, 0)
    createProjectBtn:SetScript("OnClick", function()
        if not projectCallback then return end
        local name = state.addonName ~= "" and state.addonName or "MyAddon"
        local files = {
            { name = name .. ".toc", code = GenerateTOC(state) },
            { name = "Init.lua", code = GenerateInit(state) },
        }
        if state.optionsPanel then
            files[#files + 1] = { name = "Options.lua", code = GenerateOptions(state) }
        end
        projectCallback(files, name)
        frame:Hide()
    end)

    local copyAllBtn = DF.Widgets:CreateButton(frame, "Copy All Files", 100)
    copyAllBtn:SetPoint("RIGHT", createProjectBtn, "LEFT", -4, 0)
    copyAllBtn:SetScript("OnClick", function()
        local allCode = GenerateAllFiles(state)
        if allCode and allCode ~= "" then
            DF.Widgets:ShowCopyDialog(allCode)
        end
    end)

    dialog = {
        frame = frame,
        state = state,
        codePreview = codePreview,
        setProjectCallback = function(self, cb) projectCallback = cb end,
        regenerate = function()
            if codePreview then
                codePreview:SetText(GetCurrentFileCode())
            end
        end,
    }

    return dialog
end

function Scaffold:Show(callback)
    local d = GetDialog()
    d:setProjectCallback(callback)
    d:regenerate()
    d.frame:Show()
end
