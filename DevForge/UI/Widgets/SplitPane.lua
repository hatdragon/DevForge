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

--[[
    AttachSplitterDrag: wires drag-to-resize behavior onto a splitter button.
    Tracks cursor movement along one axis and reports a size delta; the
    caller owns clamping and applying it (and can bail out of persisting
    until the drag ends).

    opts.axis: "x" or "y"
    opts.invert: flip delta sign (e.g. dragging down growing a panel below)
    opts.onDragStart(): called when the drag begins
    opts.onDrag(delta): called every frame during the drag with the pixel
        delta since drag start
    opts.onDragStop(): called once when the drag ends
]]
function DF.Widgets:AttachSplitterDrag(splitter, opts)
    local axis = opts.axis or "x"
    local isX = (axis == "x")
    local dragging = false
    local dragStart

    splitter:EnableMouse(true)
    splitter:RegisterForDrag("LeftButton")

    splitter:SetScript("OnDragStart", function()
        dragging = true
        local cx, cy = GetCursorPosition()
        local scale = splitter:GetEffectiveScale()
        dragStart = isX and (cx / scale) or (cy / scale)
        if opts.onDragStart then opts.onDragStart() end
    end)

    splitter:SetScript("OnDragStop", function()
        dragging = false
        if opts.onDragStop then opts.onDragStop() end
    end)

    splitter:SetScript("OnUpdate", function()
        if not dragging then return end
        local cx, cy = GetCursorPosition()
        local scale = splitter:GetEffectiveScale()
        local current = isX and (cx / scale) or (cy / scale)
        local delta = current - dragStart
        if opts.invert then delta = -delta end
        if opts.onDrag then opts.onDrag(delta) end
    end)
end

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
    local dragStartSize

    DF.Widgets:AttachSplitterDrag(splitter, {
        axis = isHorizontal and "x" or "y",
        invert = not isHorizontal, -- vertical: dragging down grows the top panel
        onDragStart = function()
            dragStartSize = currentSize
        end,
        onDrag = function(delta)
            currentSize = DF.Util:Clamp(dragStartSize + delta, minSize, maxSize)
            UpdateLayout()
        end,
    })

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
