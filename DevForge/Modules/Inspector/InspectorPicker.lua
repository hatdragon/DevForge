local _, DF = ...

DF.InspectorPicker = {}

local Picker = DF.InspectorPicker

local pickerFrame = nil
local onPick = nil
local onCancel = nil

-- Cache once whether this client has the secret-value API (WoW 12.0+)
-- instead of re-checking per call -- BuildFrameStack below runs every
-- 0.1s over every frame in the UI, so per-call overhead matters here.
-- issecretvalue() is documented as safe to call on any value including
-- secret ones, so it's called directly (no pcall needed).
local HAS_SECRET_API = type(issecretvalue) == "function"

local function SafeBool(ok, value)
    if not ok then return false end
    if HAS_SECRET_API and issecretvalue(value) then return false end
    return value and true or false
end

-- Frame stack state
local frameStack = {}   -- all frames under cursor, sorted top-to-bottom
local stackIndex = 1    -- which frame in the stack is selected
local showFiltered = false  -- toggle to show noise frames
local scanMode = false  -- false = live single-frame mode, true = frozen full-scan snapshot
local liveTarget = nil  -- frame currently highlighted in live mode

local STRATA_ORDER = {
    WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3,
    HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

-- Live-mode polling interval. Cheap now that it drives GetLiveTarget
-- (native GetMouseFoci) instead of the full EnumerateFrames walk, so this
-- can run closer to every frame without cost concerns.
local UPDATE_INTERVAL = 0.05

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

-- Collect all visible frames under the cursor. Expensive (walks every
-- frame object in the client) -- only run on an explicit user action
-- (Space, in the picker below), never continuously.
local function BuildFrameStack()
    local stack = {}

    if not EnumerateFrames then return stack end

    local f = EnumerateFrames()
    while f do
        if f ~= pickerFrame then
            -- Some protected frames (secure unit frames, etc.) return a
            -- "secret" value here, which can't be boolean-tested directly
            -- from tainted addon code -- SafeBool treats that as unknown/
            -- false rather than erroring.
            local okVis, vis = pcall(f.IsVisible, f)
            if SafeBool(okVis, vis) then
                local okOver, over = pcall(f.IsMouseOver, f)
                if SafeBool(okOver, over) then
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

-- Fast, continuous "what's on top" resolution using the native mouse-focus
-- API instead of walking every frame. Only ever returns the single topmost
-- real frame under the cursor (not the full occlusion stack -- that's what
-- BuildFrameStack/Space is for), skipping the picker's own capture overlay
-- (which requires SetPropagateMouseMotion(true) on that overlay to be
-- visible to GetMouseFoci at all) and applying the same noise filter.
local function GetLiveTarget()
    if not GetMouseFoci then return nil end
    local foci = GetMouseFoci()

    local isOwnFrame = function(f)
        return f == pickerFrame or f == pickerFrame.stackPanel
    end

    local fallback = nil
    for _, f in ipairs(foci) do
        if not isOwnFrame(f) then
            if not fallback then fallback = f end
            if showFiltered then
                return f
            end
            local okN, fname = pcall(f.GetName, f)
            if not IsFilteredFrame(f, okN and fname or nil) then
                return f
            end
        end
    end
    return fallback
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
    return SafeBool(ok, enabled)
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

-- Single-line display for live mode (just the topmost real frame)
local function UpdateLiveDisplay(target)
    if not pickerFrame then return end

    local lines = {}
    if not target then
        lines[#lines + 1] = "|cFF808080(no frame)|r"
    else
        local name = GetFrameDisplayName(target)
        local ftype = GetFrameType(target)
        local mouseEnabled = IsMouseEnabled(target)
        local color = mouseEnabled and "|cFFFFCC00" or "|cFF6688AA"
        lines[#lines + 1] = color .. name .. "  |cFF888888(" .. ftype .. ")|r"
    end

    lines[#lines + 1] = ""
    local filterLabel = showFiltered
        and "|cFF88AA88Tab: Hide noise frames|r"
        or "|cFF888888Tab: Show noise frames (UIParent, WorldFrame, etc.)|r"
    lines[#lines + 1] = "|cFF888888Live top frame  |  Space: Full stack scan  |  Click to select  |  Esc/Right-click to cancel|r"
    lines[#lines + 1] = filterLabel

    pickerFrame.stackText:SetText(table.concat(lines, "\n"))

    local textH = pickerFrame.stackText:GetStringHeight()
    local textW = pickerFrame.stackText:GetStringWidth()
    if (not textH or textH < 20) then textH = 60 end
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
    -- Let native mouse-focus resolution (GetMouseFoci, used by GetLiveTarget)
    -- see past this full-screen capture overlay to the real frame beneath,
    -- while still receiving our own OnMouseDown/OnMouseWheel normally --
    -- motion propagation is independent of click/wheel event delivery.
    pickerFrame:SetPropagateMouseMotion(true)
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

    -- OnUpdate: live mode continuously (but cheaply, via GetLiveTarget)
    -- resolves the top frame under the cursor, throttled and skipped when
    -- the cursor hasn't moved. Frozen entirely once a full scan (Space) is
    -- active -- that's a snapshot until the user re-scans or cancels.
    local elapsed = 0
    local lastCursorX, lastCursorY = nil, nil
    pickerFrame:SetScript("OnUpdate", function(_, dt)
        if scanMode then return end

        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0

        local cx, cy = GetCursorPosition()
        if cx == lastCursorX and cy == lastCursorY then return end
        lastCursorX, lastCursorY = cx, cy

        liveTarget = GetLiveTarget()
        if liveTarget then
            DF.InspectorHighlight:Show(liveTarget)
        else
            DF.InspectorHighlight:Hide()
        end

        pickerFrame.titleText:SetText("Live Frame")
        UpdateLiveDisplay(liveTarget)
    end)

    -- Mouse wheel cycles through the stack, only meaningful once a full
    -- scan snapshot exists -- nothing to cycle through in live mode.
    pickerFrame:EnableMouseWheel(true)
    pickerFrame:SetScript("OnMouseWheel", function(_, delta)
        if not scanMode then return end
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

    -- Left click = pick selected (scan mode) or live target, Right click = cancel
    pickerFrame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local picked
            if scanMode then
                local selected = frameStack[stackIndex]
                picked = selected and selected.frame
            else
                picked = liveTarget
            end
            if picked then
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

    -- Keyboard: Escape cancel, Up/Down to cycle (scan mode only), Tab to
    -- toggle noise filter, Space to run a full stack scan at the cursor
    pickerFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            local cb = onCancel
            Picker:Stop()
            if cb then cb() end
        elseif key == "SPACE" then
            scanMode = true
            stackIndex = 1
            frameStack = BuildFrameStack()
            if stackIndex > #frameStack then stackIndex = #frameStack end
            local selected = frameStack[stackIndex]
            if selected then DF.InspectorHighlight:Show(selected.frame) end
            pickerFrame.titleText:SetText("Frame Stack (" .. #frameStack .. " frames)")
            UpdateStackDisplay()
        elseif key == "UP" then
            if scanMode and stackIndex > 1 then
                stackIndex = stackIndex - 1
                local selected = frameStack[stackIndex]
                if selected then DF.InspectorHighlight:Show(selected.frame) end
                UpdateStackDisplay()
            end
        elseif key == "DOWN" then
            if scanMode and stackIndex < #frameStack then
                stackIndex = stackIndex + 1
                local selected = frameStack[stackIndex]
                if selected then DF.InspectorHighlight:Show(selected.frame) end
                UpdateStackDisplay()
            end
        elseif key == "TAB" then
            showFiltered = not showFiltered
            if scanMode then
                stackIndex = 1
                frameStack = BuildFrameStack()
                local selected = frameStack[stackIndex]
                if selected then DF.InspectorHighlight:Show(selected.frame) end
                UpdateStackDisplay()
            else
                liveTarget = GetLiveTarget()
                if liveTarget then
                    DF.InspectorHighlight:Show(liveTarget)
                else
                    DF.InspectorHighlight:Hide()
                end
                UpdateLiveDisplay(liveTarget)
            end
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
    scanMode = false
    liveTarget = nil
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
    scanMode = false
    liveTarget = nil
    onPick = nil
    onCancel = nil
end

function Picker:IsActive()
    return pickerFrame and pickerFrame:IsShown()
end
