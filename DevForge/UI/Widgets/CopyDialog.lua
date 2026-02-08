local _, DF = ...

DF.Widgets = DF.Widgets or {}

-- Shared copy-to-clipboard dialog. Shows a popup with pre-selected text
-- so the user only needs to press Ctrl+C.
local dialog = nil

local function GetDialog()
    if dialog then return dialog end

    -- Clean up stale named frame from previous /reload
    local stale = _G["DevForgeCopyDialog"]
    if stale then
        stale:Hide(); stale:EnableMouse(false)
        for _, c in pairs({stale:GetChildren()}) do c:Hide(); c:EnableMouse(false) end
    end

    local frame = CreateFrame("Frame", "DevForgeCopyDialog", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(999)
    frame:SetSize(460, 260)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    DF.Theme:ApplyDialogChrome(frame)

    -- Title bar for dragging
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(22)
    titleBar:SetPoint("TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", -8, -8)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then frame:StartMoving() end
    end)
    titleBar:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFontObject(DF.Theme:UIFont())
    titleText:SetPoint("LEFT", 4, 0)
    titleText:SetText("Copy Text")
    titleText:SetTextColor(0.6, 0.75, 1, 1)

    local hint = titleBar:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(DF.Theme:UIFont())
    hint:SetPoint("RIGHT", -4, 0)
    hint:SetText("Ctrl+C to copy, Esc to close")
    hint:SetTextColor(0.45, 0.45, 0.45, 1)

    -- ScrollFrame + EditBox for the text
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 36)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", scrollFrame, -2, 2)
    bg:SetPoint("BOTTOMRIGHT", scrollFrame, 20, -2)
    bg:SetColorTexture(0.08, 0.08, 0.1, 1)

    local editbox = CreateFrame("EditBox", nil, scrollFrame)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(DF.Theme:CodeFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:SetWidth(scrollFrame:GetWidth() or 400)
    editbox:SetScript("OnChar", function() end) -- read-only
    editbox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    scrollFrame:SetScrollChild(editbox)

    -- Close button
    local closeBtn = DF.Widgets:CreateButton(frame, "Close", 60)
    closeBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Update editbox width on resize
    scrollFrame:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w > 0 then
            editbox:SetWidth(w)
        end
    end)

    frame:SetScript("OnShow", function()
        -- Highlight all text and focus so Ctrl+C works immediately
        C_Timer.After(0, function()
            editbox:SetFocus()
            editbox:HighlightText()
        end)
    end)

    frame:SetScript("OnHide", function()
        editbox:SetText("")
        editbox:ClearFocus()
    end)

    dialog = {
        frame = frame,
        editbox = editbox,
        scrollFrame = scrollFrame,
    }

    return dialog
end

function DF.Widgets:ShowCopyDialog(text)
    local d = GetDialog()
    d.editbox:SetText(text or "")
    d.frame:Show()
end
