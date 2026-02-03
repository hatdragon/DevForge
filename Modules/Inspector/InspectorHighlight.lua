local _, DF = ...

DF.InspectorHighlight = {}

local Highlight = DF.InspectorHighlight

local highlightFrame = nil
local labelFrame = nil

function Highlight:Create()
    if highlightFrame then return end

    -- Blue overlay rectangle
    highlightFrame = CreateFrame("Frame", nil, UIParent)
    highlightFrame:SetFrameStrata("TOOLTIP")
    highlightFrame:SetFrameLevel(200)

    local bg = highlightFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(DF.Colors.inspectBlue))
    highlightFrame.bg = bg

    local border = highlightFrame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(unpack(DF.Colors.inspectBorder))
    highlightFrame.border = border

    -- Inner overlay (slightly smaller, creates border effect)
    local inner = highlightFrame:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(unpack(DF.Colors.inspectBlue))
    highlightFrame.inner = inner

    highlightFrame:Hide()

    -- Name label
    labelFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    labelFrame:SetFrameStrata("TOOLTIP")
    labelFrame:SetFrameLevel(201)
    labelFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    labelFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    labelFrame:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8)

    local labelText = labelFrame:CreateFontString(nil, "OVERLAY")
    labelText:SetFontObject(DF.Theme:UIFont())
    labelText:SetPoint("CENTER", 0, 0)
    labelText:SetTextColor(0.7, 0.85, 1, 1)
    labelFrame.text = labelText

    labelFrame:Hide()
end

function Highlight:Show(targetFrame)
    if not highlightFrame then self:Create() end
    if not targetFrame then
        self:Hide()
        return
    end

    -- Re-apply font in case it wasn't ready at Create time
    local font = DF.Theme:UIFont()
    if font and labelFrame.text then
        labelFrame.text:SetFontObject(font)
    end

    local ok, left, bottom, width, height = pcall(function()
        return targetFrame:GetLeft(), targetFrame:GetBottom(), targetFrame:GetWidth(), targetFrame:GetHeight()
    end)

    if not ok or not left or not bottom then
        self:Hide()
        return
    end
    width = width or 0
    height = height or 0

    highlightFrame:ClearAllPoints()
    highlightFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    highlightFrame:SetSize(width, height)
    highlightFrame:Show()

    -- Label: use GetDebugName for full path (like /fstack)
    local name = ""
    local nameOk, nameResult = pcall(function() return targetFrame:GetDebugName() end)
    if nameOk and nameResult and nameResult ~= "" then
        name = nameResult
    else
        local nameOk2, nameResult2 = pcall(function() return targetFrame:GetName() end)
        if nameOk2 and nameResult2 and nameResult2 ~= "" then
            name = nameResult2
        else
            name = tostring(targetFrame)
        end
    end

    local typeOk, typeResult = pcall(function() return targetFrame:GetObjectType() end)
    local objType = (typeOk and typeResult) or "?"

    local labelStr = name .. "  (" .. objType .. ")"
    labelFrame.text:SetText(labelStr)

    -- Size from string width, with minimum and fallback
    local textW = labelFrame.text:GetStringWidth()
    if not textW or textW < 10 then
        textW = #labelStr * 6
    end
    labelFrame:SetSize(math.max(80, textW + 20), 22)
    labelFrame:ClearAllPoints()

    -- Position above the highlight, but keep on screen
    local hlTop = (bottom or 0) + (height or 0)
    local screenH = UIParent:GetHeight()
    if hlTop + 24 > screenH then
        labelFrame:SetPoint("TOPLEFT", highlightFrame, "BOTTOMLEFT", 0, -2)
    else
        labelFrame:SetPoint("BOTTOMLEFT", highlightFrame, "TOPLEFT", 0, 2)
    end
    labelFrame:Show()
end

function Highlight:Hide()
    if highlightFrame then highlightFrame:Hide() end
    if labelFrame then labelFrame:Hide() end
end

function Highlight:IsShown()
    return highlightFrame and highlightFrame:IsShown()
end
