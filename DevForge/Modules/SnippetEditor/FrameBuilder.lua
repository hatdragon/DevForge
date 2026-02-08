local _, DF = ...

DF.FrameBuilder = {}

local Builder = DF.FrameBuilder

local FRAME_TYPES = { "Frame", "Button", "StatusBar", "ScrollFrame", "EditBox" }
local ANCHOR_POINTS = { "CENTER", "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local dialog = nil

---------------------------------------------------------------------------
-- Local UI helpers
---------------------------------------------------------------------------

-- Selector button: displays current value, shows dropdown on click
local function CreateSelector(parent, items, default, width, onChange)
    local btn = DF.Widgets:CreateButton(parent, default or items[1], width or 130)
    local current = default or items[1]

    local menu = DF.Widgets:CreateDropDown()

    btn:SetScript("OnClick", function(self)
        local menuItems = {}
        for _, item in ipairs(items) do
            menuItems[#menuItems + 1] = {
                text = item,
                func = function()
                    current = item
                    btn:SetLabel(item)
                    if onChange then onChange(item) end
                end,
            }
        end
        menu:Show(self, menuItems)
    end)

    local selector = { button = btn }
    function selector:GetValue() return current end
    function selector:SetValue(val)
        current = val
        btn:SetLabel(val)
    end
    return selector
end

-- Checkbox: CheckButton with a colored square check texture and label
local function CreateCheckbox(parent, labelText, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(14, 14)

    -- Box background
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 1)

    -- Border
    local border = cb:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Check mark (colored square)
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", -2, 2)
    check:SetColorTexture(0.3, 0.5, 0.8, 1)
    cb:SetCheckedTexture(check)

    -- Label
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

-- Text input: single-line EditBox with label
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
    input:SetSize(width or 120, 20)
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

-- Number input: like text input but for numbers
local function CreateNumberInput(parent, labelText, defaultVal, width, onChange)
    local ti = CreateTextInput(parent, labelText, tostring(defaultVal or 0), width, function(text)
        if onChange then onChange(tonumber(text) or 0) end
    end)
    ti.input:SetNumeric(false) -- allow negative and decimal entry
    function ti:GetNumber() return tonumber(ti.input:GetText()) or 0 end
    return ti
end

---------------------------------------------------------------------------
-- Code generation
---------------------------------------------------------------------------

local function GenerateCode(state)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Determine template string
    local inherits = {}
    if state.frameType == "Button" then
        -- no special template needed unless backdrop
    end
    if state.backdrop then
        inherits[#inherits + 1] = "BackdropTemplate"
    end
    local inheritStr = #inherits > 0 and (', "' .. table.concat(inherits, ", ") .. '"') or ""

    local globalName = (state.globalName and state.globalName ~= "") and ('"' .. state.globalName .. '"') or "nil"
    local parentRef = (state.parent and state.parent ~= "") and state.parent or "UIParent"

    add(string.format('local f = CreateFrame("%s", %s, %s%s)', state.frameType, globalName, parentRef, inheritStr))
    add(string.format("f:SetSize(%d, %d)", state.width or 200, state.height or 150))
    add(string.format('f:SetPoint("%s", %d, %d)', state.anchor or "CENTER", state.offsetX or 0, state.offsetY or 0))

    if state.backdrop then
        add("")
        add("f:SetBackdrop({")
        add('    bgFile = "Interface\\\\ChatFrame\\\\ChatFrameBackground",')
        add('    edgeFile = "Interface\\\\Tooltips\\\\UI-Tooltip-Border",')
        add("    tile = true, tileSize = 16, edgeSize = 16,")
        add("    insets = { left = 4, right = 4, top = 4, bottom = 4 },")
        add("})")
        add("f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)")
        add("f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)")
    end

    if state.movable then
        add("")
        add("f:SetMovable(true)")
        add("f:EnableMouse(true)")
        add('f:RegisterForDrag("LeftButton")')
        add("f:SetScript(\"OnDragStart\", f.StartMoving)")
        add("f:SetScript(\"OnDragStop\", f.StopMovingOrSizing)")
    end

    if state.resizable then
        add("")
        add("f:SetResizable(true)")
        add("f:SetResizeBounds(100, 80, 600, 400)")
    end

    if state.clamped then
        add("f:SetClampedToScreen(true)")
    end

    if state.titleBar then
        add("")
        add("-- Title bar")
        add('local titleBar = CreateFrame("Frame", nil, f)')
        add("titleBar:SetHeight(24)")
        add('titleBar:SetPoint("TOPLEFT", 0, 0)')
        add('titleBar:SetPoint("TOPRIGHT", 0, 0)')
        add("local titleBg = titleBar:CreateTexture(nil, \"BACKGROUND\")")
        add("titleBg:SetAllPoints()")
        add("titleBg:SetColorTexture(0.15, 0.15, 0.17, 1)")
        add('local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")')
        add('titleText:SetPoint("LEFT", 8, 0)')
        add('titleText:SetText("' .. (state.globalName or "My Frame") .. '")')
    end

    if state.closeBtn then
        add("")
        add("-- Close button")
        add('local closeBtn = CreateFrame("Button", nil, f)')
        add("closeBtn:SetSize(20, 20)")
        add('closeBtn:SetPoint("TOPRIGHT", -4, -4)')
        add('closeBtn:SetNormalTexture("Interface\\\\Buttons\\\\UI-Panel-MinimizeButton-Up")')
        add('closeBtn:SetHighlightTexture("Interface\\\\Buttons\\\\UI-Panel-MinimizeButton-Highlight")')
        add("closeBtn:SetScript(\"OnClick\", function() f:Hide() end)")
    end

    -- Scripts
    local scripts = {}
    if state.scriptOnShow then scripts[#scripts + 1] = "OnShow" end
    if state.scriptOnHide then scripts[#scripts + 1] = "OnHide" end
    if state.scriptOnEvent then scripts[#scripts + 1] = "OnEvent" end
    if state.scriptOnUpdate then scripts[#scripts + 1] = "OnUpdate" end

    if #scripts > 0 then
        add("")
        for _, script in ipairs(scripts) do
            if script == "OnEvent" then
                add('f:SetScript("OnEvent", function(self, event, ...)')
                add("    -- handle events")
                add("end)")
            elseif script == "OnUpdate" then
                add('f:SetScript("OnUpdate", function(self, elapsed)')
                add("    -- runs every frame")
                add("end)")
            else
                add(string.format('f:SetScript("%s", function(self)', script))
                add(string.format("    -- %s handler", script))
                add("end)")
            end
        end
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Dialog creation (singleton)
---------------------------------------------------------------------------

local function GetDialog()
    if dialog then return dialog end

    -- Clean up stale named frame from previous /reload
    local stale = _G["DevForgeFrameBuilder"]
    if stale then
        stale:Hide(); stale:EnableMouse(false)
        for _, c in pairs({stale:GetChildren()}) do c:Hide(); c:EnableMouse(false) end
    end

    local frame = CreateFrame("Frame", "DevForgeFrameBuilder", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetSize(480, 540)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    DF.Theme:ApplyDialogChrome(frame)
    if not tContains(UISpecialFrames, "DevForgeFrameBuilder") then
        tinsert(UISpecialFrames, "DevForgeFrameBuilder")
    end

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
    titleText:SetText("Frame Builder")
    titleText:SetTextColor(0.6, 0.75, 1, 1)

    -- Scrollable form content
    local formArea = CreateFrame("Frame", nil, frame)
    formArea:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -6)
    formArea:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -6)
    formArea:SetHeight(260)

    -- State table
    local state = {
        frameType = "Frame",
        globalName = "",
        parent = "UIParent",
        width = 300,
        height = 200,
        anchor = "CENTER",
        offsetX = 0,
        offsetY = 0,
        backdrop = false,
        movable = false,
        resizable = false,
        clamped = false,
        closeBtn = false,
        titleBar = false,
        scriptOnShow = false,
        scriptOnHide = false,
        scriptOnEvent = false,
        scriptOnUpdate = false,
    }

    local insertCallback = nil
    local codePreview = nil
    local regenerateTimer = nil

    local function ScheduleRegenerate()
        if regenerateTimer then regenerateTimer:Cancel() end
        regenerateTimer = C_Timer.NewTimer(0.15, function()
            regenerateTimer = nil
            if codePreview then
                codePreview:SetText(GenerateCode(state))
            end
        end)
    end

    local function OnFieldChanged()
        ScheduleRegenerate()
    end

    -- Layout rows
    local yOff = 0

    -- Frame Type selector
    local ftLabel = formArea:CreateFontString(nil, "OVERLAY")
    ftLabel:SetFontObject(DF.Theme:UIFont())
    ftLabel:SetPoint("TOPLEFT", 0, -yOff)
    ftLabel:SetText("Frame Type:")
    ftLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    ftLabel:SetWidth(80)
    ftLabel:SetJustifyH("RIGHT")

    local ftSelector = CreateSelector(formArea, FRAME_TYPES, "Frame", 130, function(val)
        state.frameType = val
        OnFieldChanged()
    end)
    ftSelector.button:SetPoint("LEFT", ftLabel, "RIGHT", 4, 0)
    yOff = yOff + 26

    -- Global Name
    local nameInput = CreateTextInput(formArea, "Name:", "", 160, function(val)
        state.globalName = val
        OnFieldChanged()
    end)
    nameInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    nameInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 24

    -- Parent
    local parentInput = CreateTextInput(formArea, "Parent:", "UIParent", 160, function(val)
        state.parent = val
        OnFieldChanged()
    end)
    parentInput.frame:SetPoint("TOPLEFT", 0, -yOff)
    parentInput.frame:SetPoint("TOPRIGHT", 0, -yOff)
    yOff = yOff + 24

    -- Width / Height on same row
    local sizeRow = CreateFrame("Frame", nil, formArea)
    sizeRow:SetHeight(22)
    sizeRow:SetPoint("TOPLEFT", 0, -yOff)
    sizeRow:SetPoint("TOPRIGHT", 0, -yOff)

    local widthInput = CreateNumberInput(sizeRow, "Width:", 300, 60, function(val)
        state.width = val
        OnFieldChanged()
    end)
    widthInput.frame:SetPoint("LEFT", 0, 0)

    local heightInput = CreateNumberInput(sizeRow, "Height:", 200, 60, function(val)
        state.height = val
        OnFieldChanged()
    end)
    heightInput.frame:SetPoint("LEFT", widthInput.frame, "RIGHT", 20, 0)
    yOff = yOff + 24

    -- Anchor selector
    local anchorLabel = formArea:CreateFontString(nil, "OVERLAY")
    anchorLabel:SetFontObject(DF.Theme:UIFont())
    anchorLabel:SetPoint("TOPLEFT", 0, -yOff)
    anchorLabel:SetText("Anchor:")
    anchorLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    anchorLabel:SetWidth(80)
    anchorLabel:SetJustifyH("RIGHT")

    local anchorSelector = CreateSelector(formArea, ANCHOR_POINTS, "CENTER", 110, function(val)
        state.anchor = val
        OnFieldChanged()
    end)
    anchorSelector.button:SetPoint("LEFT", anchorLabel, "RIGHT", 4, 0)
    yOff = yOff + 26

    -- Offset X / Y
    local offRow = CreateFrame("Frame", nil, formArea)
    offRow:SetHeight(22)
    offRow:SetPoint("TOPLEFT", 0, -yOff)
    offRow:SetPoint("TOPRIGHT", 0, -yOff)

    local offXInput = CreateNumberInput(offRow, "Offset X:", 0, 60, function(val)
        state.offsetX = val
        OnFieldChanged()
    end)
    offXInput.frame:SetPoint("LEFT", 0, 0)

    local offYInput = CreateNumberInput(offRow, "Offset Y:", 0, 60, function(val)
        state.offsetY = val
        OnFieldChanged()
    end)
    offYInput.frame:SetPoint("LEFT", offXInput.frame, "RIGHT", 20, 0)
    yOff = yOff + 28

    -- Feature checkboxes (two columns)
    local featLabel = formArea:CreateFontString(nil, "OVERLAY")
    featLabel:SetFontObject(DF.Theme:UIFont())
    featLabel:SetPoint("TOPLEFT", 4, -yOff)
    featLabel:SetText("Features:")
    featLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    yOff = yOff + 16

    local features = {
        { key = "backdrop",  label = "Backdrop" },
        { key = "movable",   label = "Movable" },
        { key = "resizable", label = "Resizable" },
        { key = "clamped",   label = "Clamped" },
        { key = "closeBtn",  label = "Close button" },
        { key = "titleBar",  label = "Title bar" },
    }

    for i, feat in ipairs(features) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local cb = CreateCheckbox(formArea, feat.label, function(checked)
            state[feat.key] = checked
            OnFieldChanged()
        end)
        cb:SetPoint("TOPLEFT", 8 + col * 200, -(yOff + row * 18))
    end
    yOff = yOff + math.ceil(#features / 2) * 18 + 6

    -- Script checkboxes
    local scriptLabel = formArea:CreateFontString(nil, "OVERLAY")
    scriptLabel:SetFontObject(DF.Theme:UIFont())
    scriptLabel:SetPoint("TOPLEFT", 4, -yOff)
    scriptLabel:SetText("Scripts:")
    scriptLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    yOff = yOff + 16

    local scripts = {
        { key = "scriptOnShow",   label = "OnShow" },
        { key = "scriptOnHide",   label = "OnHide" },
        { key = "scriptOnEvent",  label = "OnEvent" },
        { key = "scriptOnUpdate", label = "OnUpdate" },
    }

    for i, scr in ipairs(scripts) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local cb = CreateCheckbox(formArea, scr.label, function(checked)
            state[scr.key] = checked
            OnFieldChanged()
        end)
        cb:SetPoint("TOPLEFT", 8 + col * 200, -(yOff + row * 18))
    end
    yOff = yOff + math.ceil(#scripts / 2) * 18

    formArea:SetHeight(yOff)

    -- Code preview (read-only CodeEditBox)
    codePreview = DF.Widgets:CreateCodeEditBox(frame, { multiLine = true, readOnly = true })
    codePreview.frame:SetPoint("TOPLEFT", formArea, "BOTTOMLEFT", 0, -4)
    codePreview.frame:SetPoint("BOTTOMRIGHT", -12, 40)

    -- Initial code generation
    codePreview:SetText(GenerateCode(state))

    -- Bottom buttons
    local cancelBtn = DF.Widgets:CreateButton(frame, "Cancel", 60)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)

    local copyBtn = DF.Widgets:CreateButton(frame, "Copy", 55)
    copyBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -4, 0)
    copyBtn:SetScript("OnClick", function()
        local code = codePreview:GetText()
        if code and code ~= "" then
            DF.Widgets:ShowCopyDialog(code)
        end
    end)

    local insertBtn = DF.Widgets:CreateButton(frame, "Insert as Snippet", 120)
    insertBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)
    insertBtn:SetScript("OnClick", function()
        local code = codePreview:GetText()
        if code and code ~= "" and insertCallback then
            insertCallback(code, state.globalName ~= "" and state.globalName or "Frame Builder")
            frame:Hide()
        end
    end)

    dialog = {
        frame = frame,
        state = state,
        codePreview = codePreview,
        insertCallback = nil,
        setInsertCallback = function(self, cb) insertCallback = cb end,
        regenerate = function() codePreview:SetText(GenerateCode(state)) end,
    }

    return dialog
end

function Builder:Show(insertCallback)
    local d = GetDialog()
    d:setInsertCallback(insertCallback)
    d:regenerate()
    d.frame:Show()
end
