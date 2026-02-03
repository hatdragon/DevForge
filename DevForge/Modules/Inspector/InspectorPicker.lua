local _, DF = ...

DF.InspectorPicker = {}

local Picker = DF.InspectorPicker

local pickerFrame = nil
local onPick = nil
local onCancel = nil

-- Frame stack state
local frameStack = {}   -- all frames under cursor, sorted top-to-bottom
local stackIndex = 1    -- which frame in the stack is selected
local showFiltered = false  -- toggle to show noise frames

local STRATA_ORDER = {
    WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3,
    HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local UPDATE_INTERVAL = 0.1  -- same as /fstack

-- Frames filtered out by default (common noise)
local FILTERED_EXACT = {
    ["UIParent"] = true,
    ["WorldFrame"] = true,
    ["TimerTracker"] = true,
    ["MotionSicknessFrame"] = true,
    ["ContainerFrameContainer"] = true,
}
local FILTERED_PREFIXES = {
    "UIWidget",
    "GlobalFX",
}
local FILTERED_TYPES = {
    ["ModelScene"] = true,
}

-- Cache screen size (updated on pick start)
local screenW, screenH = 0, 0

local function IsFullscreenFrame(frame)
    -- Filter anonymous frames that cover the entire screen (layout containers)
    if screenW == 0 then return false end
    local okW, w = pcall(frame.GetWidth, frame)
    local okH, h = pcall(frame.GetHeight, frame)
    if okW and okH and w and h then
        -- Within 2px of screen size = fullscreen noise
        return (w >= screenW - 2) and (h >= screenH - 2)
    end
    return false
end

local function IsFilteredFrame(frame, name)
    -- Check object type
    local okT, objType = pcall(frame.GetObjectType, frame)
    if okT and objType and FILTERED_TYPES[objType] then return true end

    -- Named frame checks
    if name and name ~= "" then
        if FILTERED_EXACT[name] then return true end
        for _, prefix in ipairs(FILTERED_PREFIXES) do
            if name:sub(1, #prefix) == prefix then return true end
        end
    end

    -- Fullscreen container check (catches anonymous UIParent children)
    if IsFullscreenFrame(frame) then return true end

    -- Anonymous "Frame" types are almost always internal layout containers
    if (not name or name == "") and okT and objType == "Frame" then
        return true
    end

    return false
end

-- Collect all visible frames under the cursor
local function BuildFrameStack()
    local stack = {}

    if not EnumerateFrames then return stack end

    local f = EnumerateFrames()
    while f do
        if f ~= pickerFrame then
            local okVis, vis = pcall(f.IsVisible, f)
            if okVis and vis then
                local okOver, over = pcall(f.IsMouseOver, f)
                if okOver and over then
                    -- Apply noise filter
                    local dominated = false
                    if not showFiltered then
                        local okN, fname = pcall(f.GetName, f)
                        dominated = IsFilteredFrame(f, okN and fname or nil)
                    end

                    if not dominated then
                        local okS, strata = pcall(f.GetFrameStrata, f)
                        local okL, level = pcall(f.GetFrameLevel, f)
                        stack[#stack + 1] = {
                            frame = f,
                            strata = (okS and STRATA_ORDER[strata]) or 0,
                            level = (okL and level) or 0,
                        }
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end

    -- Sort: highest strata first, then highest level
    table.sort(stack, function(a, b)
        if a.strata ~= b.strata then return a.strata > b.strata end
        return a.level > b.level
    end)

    return stack
end

-- Get display name for a frame (matches /fstack behavior)
local function GetFrameDisplayName(frame)
    -- GetDebugName gives full path for anonymous frames (e.g. "PlayerFrame.HealthBar")
    local okD, debugName = pcall(frame.GetDebugName, frame)
    if okD and debugName and debugName ~= "" then
        return debugName
    end
    local okN, name = pcall(frame.GetName, frame)
    if okN and name and name ~= "" then
        return name
    end
    return tostring(frame)
end

local function GetFrameType(frame)
    local ok, objType = pcall(frame.GetObjectType, frame)
    return (ok and objType) or "?"
end

local function IsMouseEnabled(frame)
    local ok, enabled = pcall(frame.IsMouseEnabled, frame)
    return ok and enabled
end

-- Build the tooltip text showing the frame stack
local function UpdateStackDisplay()
    if not pickerFrame then return end

    local lines = {}
    local maxShow = 15  -- cap visible lines

    if #frameStack == 0 then
        lines[#lines + 1] = "|cFF808080(no frames)|r"
    else
        local startIdx = math.max(1, stackIndex - 7)
        local endIdx = math.min(#frameStack, startIdx + maxShow - 1)

        for i = startIdx, endIdx do
            local entry = frameStack[i]
            local name = GetFrameDisplayName(entry.frame)
            local ftype = GetFrameType(entry.frame)
            local mouseEnabled = IsMouseEnabled(entry.frame)

            -- Color: selected = white, mouse-enabled = yellow, others = gray
            local color
            if i == stackIndex then
                color = "|cFFFFFFFF"
            elseif mouseEnabled then
                color = "|cFFFFCC00"
            else
                color = "|cFF6688AA"
            end

            local prefix = (i == stackIndex) and ">> " or "   "
            lines[#lines + 1] = color .. prefix .. name .. "  |cFF888888(" .. ftype .. ")|r"
        end

        if endIdx < #frameStack then
            lines[#lines + 1] = "|cFF666666   ... " .. (#frameStack - endIdx) .. " more|r"
        end
    end

    lines[#lines + 1] = ""
    local filterLabel = showFiltered
        and "|cFF88AA88Tab: Hide noise frames|r"
        or "|cFF888888Tab: Show noise frames (UIParent, WorldFrame, etc.)|r"
    lines[#lines + 1] = "|cFF888888Scroll to cycle  |  Click to select  |  Esc/Right-click to cancel|r"
    lines[#lines + 1] = filterLabel

    pickerFrame.stackText:SetText(table.concat(lines, "\n"))

    -- Resize panel to fit text
    local textH = pickerFrame.stackText:GetStringHeight()
    local textW = pickerFrame.stackText:GetStringWidth()
    if (not textH or textH < 20) then textH = 200 end
    if (not textW or textW < 100) then textW = 350 end
    pickerFrame.stackPanel:SetSize(math.min(500, textW + 24), textH + 16)
end

function Picker:Create()
    if pickerFrame then return end

    pickerFrame = CreateFrame("Frame", nil, UIParent)
    pickerFrame:SetFrameStrata("TOOLTIP")
    pickerFrame:SetFrameLevel(199)
    pickerFrame:SetAllPoints(UIParent)
    pickerFrame:EnableMouse(true)
    pickerFrame:EnableKeyboard(true)
    pickerFrame:Hide()

    -- Nearly invisible overlay to catch mouse
    local overlay = pickerFrame:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.01)

    -- Stack display panel (anchored to cursor area)
    local stackPanel = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
    stackPanel:SetFrameLevel(202)
    stackPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    stackPanel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    stackPanel:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8)
    stackPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    stackPanel:SetSize(400, 200)
    pickerFrame.stackPanel = stackPanel

    local stackText = stackPanel:CreateFontString(nil, "OVERLAY")
    stackText:SetFontObject(DF.Theme:CodeFont())
    stackText:SetPoint("TOPLEFT", 8, -8)
    stackText:SetPoint("RIGHT", -8, 0)
    stackText:SetJustifyH("LEFT")
    stackText:SetJustifyV("TOP")
    stackText:SetTextColor(0.83, 0.83, 0.83, 1)
    pickerFrame.stackText = stackText

    -- Title
    local titleText = stackPanel:CreateFontString(nil, "OVERLAY")
    titleText:SetFontObject(DF.Theme:UIFont())
    titleText:SetPoint("BOTTOMLEFT", stackPanel, "TOPLEFT", 4, 2)
    titleText:SetTextColor(0.4, 0.7, 1, 0.9)
    pickerFrame.titleText = titleText

    -- OnUpdate: rebuild frame stack periodically
    local elapsed = 0
    pickerFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0

        frameStack = BuildFrameStack()

        -- Clamp index
        if stackIndex > #frameStack then stackIndex = #frameStack end
        if stackIndex < 1 then stackIndex = 1 end

        -- Update highlight
        local selected = frameStack[stackIndex]
        if selected then
            DF.InspectorHighlight:Show(selected.frame)
        end

        -- Update display
        pickerFrame.titleText:SetText("Frame Stack (" .. #frameStack .. " frames)")
        UpdateStackDisplay()
    end)

    -- Mouse wheel to cycle through stack
    pickerFrame:EnableMouseWheel(true)
    pickerFrame:SetScript("OnMouseWheel", function(_, delta)
        if #frameStack == 0 then return end
        stackIndex = stackIndex - delta  -- scroll up = previous (higher strata)
        if stackIndex < 1 then stackIndex = 1 end
        if stackIndex > #frameStack then stackIndex = #frameStack end

        local selected = frameStack[stackIndex]
        if selected then
            DF.InspectorHighlight:Show(selected.frame)
        end
        UpdateStackDisplay()
    end)

    -- Left click = pick selected, Right click = cancel
    pickerFrame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local selected = frameStack[stackIndex]
            if selected then
                local picked = selected.frame
                local cb = onPick
                Picker:Stop()
                if cb then cb(picked) end
            end
        elseif button == "RightButton" then
            local cb = onCancel
            Picker:Stop()
            if cb then cb() end
        end
    end)

    -- Keyboard: Escape cancel, Up/Down to cycle, Tab to toggle filter
    pickerFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            local cb = onCancel
            Picker:Stop()
            if cb then cb() end
        elseif key == "UP" then
            if stackIndex > 1 then
                stackIndex = stackIndex - 1
                local selected = frameStack[stackIndex]
                if selected then DF.InspectorHighlight:Show(selected.frame) end
                UpdateStackDisplay()
            end
        elseif key == "DOWN" then
            if stackIndex < #frameStack then
                stackIndex = stackIndex + 1
                local selected = frameStack[stackIndex]
                if selected then DF.InspectorHighlight:Show(selected.frame) end
                UpdateStackDisplay()
            end
        elseif key == "TAB" then
            showFiltered = not showFiltered
            stackIndex = 1
            frameStack = BuildFrameStack()
            local selected = frameStack[stackIndex]
            if selected then DF.InspectorHighlight:Show(selected.frame) end
            UpdateStackDisplay()
        end
    end)
end

function Picker:Start(pickCallback, cancelCallback)
    if not pickerFrame then self:Create() end
    onPick = pickCallback
    onCancel = cancelCallback
    frameStack = {}
    stackIndex = 1
    showFiltered = false
    -- Cache screen size for fullscreen detection
    screenW = UIParent:GetWidth()
    screenH = UIParent:GetHeight()
    pickerFrame:Show()
    DF.InspectorHighlight:Create()
end

function Picker:Stop()
    if pickerFrame then
        pickerFrame:Hide()
    end
    DF.InspectorHighlight:Hide()
    frameStack = {}
    stackIndex = 1
    onPick = nil
    onCancel = nil
end

function Picker:IsActive()
    return pickerFrame and pickerFrame:IsShown()
end
