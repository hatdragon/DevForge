local _, DF = ...

DF.InspectorGrid = {}

local Grid = DF.InspectorGrid

local gridFrame = nil
local guideLines = {}
local enabled = false
local gridSize = 8    -- pixels between grid lines
local gridAlpha = 0.15

function Grid:Create()
    if gridFrame then return end

    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetFrameStrata("TOOLTIP")
    gridFrame:SetFrameLevel(198)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:EnableMouse(false)
    gridFrame:Hide()
end

-- Draw the grid overlay
function Grid:DrawGrid()
    if not gridFrame then self:Create() end

    -- Clear old lines
    for _, line in ipairs(guideLines) do
        line:Hide()
    end
    wipe(guideLines)

    local w = GetScreenWidth()
    local h = GetScreenHeight()
    local scale = UIParent:GetEffectiveScale()
    local safeGridSize = math.max(4, gridSize) -- prevent infinite loop
    local MAX_LINES = 4000

    -- Vertical lines
    local x = 0
    while x <= w and #guideLines < MAX_LINES do
        local line = gridFrame:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.4, 0.6, 1.0, gridAlpha)
        line:SetSize(1 / scale, h)
        line:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x, 0)
        guideLines[#guideLines + 1] = line
        x = x + safeGridSize
    end

    -- Horizontal lines
    local y = 0
    while y <= h and #guideLines < MAX_LINES do
        local line = gridFrame:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.4, 0.6, 1.0, gridAlpha)
        line:SetSize(w, 1 / scale)
        line:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", 0, y)
        guideLines[#guideLines + 1] = line
        y = y + safeGridSize
    end

    -- Center crosshair (brighter)
    local cx = w / 2
    local cy = h / 2

    local vCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    vCenter:SetColorTexture(1.0, 0.5, 0.3, 0.4)
    vCenter:SetSize(1, h)
    vCenter:SetPoint("BOTTOM", gridFrame, "BOTTOMLEFT", cx, 0)
    guideLines[#guideLines + 1] = vCenter

    local hCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    hCenter:SetColorTexture(1.0, 0.5, 0.3, 0.4)
    hCenter:SetSize(w, 1)
    hCenter:SetPoint("LEFT", gridFrame, "BOTTOMLEFT", 0, cy)
    guideLines[#guideLines + 1] = hCenter
end

-- Show anchor guide lines for a specific frame
function Grid:ShowFrameGuides(targetFrame)
    if not gridFrame then self:Create() end
    if not targetFrame then return end

    local ok, left, right, top, bottom = pcall(function()
        return targetFrame:GetLeft(), targetFrame:GetRight(),
               targetFrame:GetTop(), targetFrame:GetBottom()
    end)
    if not ok or not left then return end

    local h = GetScreenHeight()
    local w = GetScreenWidth()

    -- Left edge
    local lLine = gridFrame:CreateTexture(nil, "ARTWORK")
    lLine:SetColorTexture(0.3, 1.0, 0.3, 0.5)
    lLine:SetSize(1, h)
    lLine:SetPoint("BOTTOM", gridFrame, "BOTTOMLEFT", left, 0)
    guideLines[#guideLines + 1] = lLine

    -- Right edge
    local rLine = gridFrame:CreateTexture(nil, "ARTWORK")
    rLine:SetColorTexture(0.3, 1.0, 0.3, 0.5)
    rLine:SetSize(1, h)
    rLine:SetPoint("BOTTOM", gridFrame, "BOTTOMLEFT", right, 0)
    guideLines[#guideLines + 1] = rLine

    -- Top edge
    local tLine = gridFrame:CreateTexture(nil, "ARTWORK")
    tLine:SetColorTexture(0.3, 1.0, 0.3, 0.5)
    tLine:SetSize(w, 1)
    tLine:SetPoint("LEFT", gridFrame, "BOTTOMLEFT", 0, top)
    guideLines[#guideLines + 1] = tLine

    -- Bottom edge
    local bLine = gridFrame:CreateTexture(nil, "ARTWORK")
    bLine:SetColorTexture(0.3, 1.0, 0.3, 0.5)
    bLine:SetSize(w, 1)
    bLine:SetPoint("LEFT", gridFrame, "BOTTOMLEFT", 0, bottom)
    guideLines[#guideLines + 1] = bLine

    -- Dimension labels
    local dimW = right - left
    local dimH = top - bottom

    local wLabel = gridFrame:CreateFontString(nil, "OVERLAY")
    wLabel:SetFontObject(DF.Theme:UIFont())
    wLabel:SetPoint("BOTTOM", gridFrame, "BOTTOMLEFT", (left + right) / 2, bottom - 14)
    wLabel:SetText(string.format("%.1f", dimW))
    wLabel:SetTextColor(0.3, 1.0, 0.3, 1)
    guideLines[#guideLines + 1] = wLabel

    local hLabel = gridFrame:CreateFontString(nil, "OVERLAY")
    hLabel:SetFontObject(DF.Theme:UIFont())
    hLabel:SetPoint("LEFT", gridFrame, "BOTTOMLEFT", right + 4, (top + bottom) / 2)
    hLabel:SetText(string.format("%.1f", dimH))
    hLabel:SetTextColor(0.3, 1.0, 0.3, 1)
    guideLines[#guideLines + 1] = hLabel

    -- Position label (from BOTTOMLEFT of screen)
    local posLabel = gridFrame:CreateFontString(nil, "OVERLAY")
    posLabel:SetFontObject(DF.Theme:UIFont())
    posLabel:SetPoint("TOPLEFT", gridFrame, "BOTTOMLEFT", left, bottom - 2)
    posLabel:SetText(string.format("(%.1f, %.1f)", left, bottom))
    posLabel:SetTextColor(0.7, 0.7, 1.0, 1)
    guideLines[#guideLines + 1] = posLabel
end

function Grid:Show(targetFrame)
    if not gridFrame then self:Create() end
    self:DrawGrid()
    if targetFrame then
        self:ShowFrameGuides(targetFrame)
    end
    gridFrame:Show()
    enabled = true
end

function Grid:Hide()
    if gridFrame then
        gridFrame:Hide()
    end
    for _, line in ipairs(guideLines) do
        if line.Hide then line:Hide() end
    end
    enabled = false
end

function Grid:Toggle(targetFrame)
    if enabled then
        self:Hide()
    else
        self:Show(targetFrame)
    end
end

function Grid:IsShown()
    return enabled
end

function Grid:SetGridSize(size)
    gridSize = size
    if enabled then
        self:Hide()
        self:Show()
    end
end

function Grid:SetAlpha(alpha)
    gridAlpha = alpha
end

-- Refresh guides for a new target frame (keeps grid, updates frame guides)
function Grid:UpdateTarget(targetFrame)
    if not enabled then return end
    -- Clear and redraw
    self:Show(targetFrame)
end
