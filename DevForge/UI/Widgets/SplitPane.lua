local _, DF = ...

DF.Widgets = DF.Widgets or {}

--[[
    SplitPane: Resizable horizontal or vertical split container.

    Usage:
        local split = DF.Widgets:CreateSplitPane(parent, {
            direction = "horizontal",  -- or "vertical"
            initialSize = 200,         -- initial left/top panel size
            minSize = 100,
            maxSize = 400,
        })
        -- split.left / split.right  (for horizontal)
        -- split.top / split.bottom  (for vertical)
]]

local SPLITTER_W = DF.Layout.splitterWidth

function DF.Widgets:CreateSplitPane(parent, opts)
    opts = opts or {}
    local direction = opts.direction or "horizontal"
    local initialSize = opts.initialSize or 200
    local minSize = opts.minSize or 80
    local maxSize = opts.maxSize or 600
    local isHorizontal = (direction == "horizontal")

    local frame = CreateFrame("Frame", nil, parent)

    -- First panel (left or top)
    local panel1 = CreateFrame("Frame", nil, frame)
    -- Second panel (right or bottom)
    local panel2 = CreateFrame("Frame", nil, frame)
    -- Splitter
    local splitter = CreateFrame("Button", nil, frame)

    local currentSize = initialSize

    local function UpdateLayout()
        panel1:ClearAllPoints()
        panel2:ClearAllPoints()
        splitter:ClearAllPoints()

        if isHorizontal then
            panel1:SetPoint("TOPLEFT", 0, 0)
            panel1:SetPoint("BOTTOMLEFT", 0, 0)
            panel1:SetWidth(currentSize)

            splitter:SetPoint("TOPLEFT", currentSize, 0)
            splitter:SetPoint("BOTTOMLEFT", currentSize, 0)
            splitter:SetWidth(SPLITTER_W)

            panel2:SetPoint("TOPLEFT", currentSize + SPLITTER_W, 0)
            panel2:SetPoint("BOTTOMRIGHT", 0, 0)
        else
            panel1:SetPoint("TOPLEFT", 0, 0)
            panel1:SetPoint("TOPRIGHT", 0, 0)
            panel1:SetHeight(currentSize)

            splitter:SetPoint("TOPLEFT", 0, -currentSize)
            splitter:SetPoint("TOPRIGHT", 0, -currentSize)
            splitter:SetHeight(SPLITTER_W)

            panel2:SetPoint("TOPLEFT", 0, -(currentSize + SPLITTER_W))
            panel2:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    -- Splitter visuals
    local splitterTex = splitter:CreateTexture(nil, "BACKGROUND")
    splitterTex:SetAllPoints()
    splitterTex:SetColorTexture(unpack(DF.Colors.splitter))

    -- Splitter hover
    local splitterHl = splitter:CreateTexture(nil, "HIGHLIGHT")
    splitterHl:SetAllPoints()
    splitterHl:SetColorTexture(0.4, 0.6, 0.9, 0.3)

    -- Drag behavior
    local isDragging = false
    local dragStart, dragStartSize

    splitter:EnableMouse(true)
    splitter:RegisterForDrag("LeftButton")

    splitter:SetScript("OnDragStart", function()
        isDragging = true
        local cursorX, cursorY = GetCursorPosition()
        local scale = splitter:GetEffectiveScale()
        if isHorizontal then
            dragStart = cursorX / scale
        else
            dragStart = cursorY / scale
        end
        dragStartSize = currentSize
    end)

    splitter:SetScript("OnDragStop", function()
        isDragging = false
    end)

    splitter:SetScript("OnUpdate", function()
        if not isDragging then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = splitter:GetEffectiveScale()

        if isHorizontal then
            local current = cursorX / scale
            local delta = current - dragStart
            currentSize = DF.Util:Clamp(dragStartSize + delta, minSize, maxSize)
        else
            local current = cursorY / scale
            local delta = dragStart - current
            currentSize = DF.Util:Clamp(dragStartSize + delta, minSize, maxSize)
        end

        UpdateLayout()
    end)

    UpdateLayout()

    local split = {
        frame = frame,
        splitter = splitter,
    }

    if isHorizontal then
        split.left = panel1
        split.right = panel2
    else
        split.top = panel1
        split.bottom = panel2
    end

    function split:SetSize1(size)
        currentSize = DF.Util:Clamp(size, minSize, maxSize)
        UpdateLayout()
    end

    function split:GetSize1()
        return currentSize
    end

    return split
end
