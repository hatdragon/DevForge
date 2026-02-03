local _, DF = ...

DF.Widgets = DF.Widgets or {}

--[[
    DropDown: Simple context menu without UIDropDownMenu dependency.

    Usage:
        local menu = DF.Widgets:CreateDropDown()
        menu:Show(anchorFrame, {
            { text = "Option 1", func = function() ... end },
            { text = "Option 2", func = function() ... end, disabled = true },
            { isSeparator = true },
            { text = "Cancel" },
        })
]]

local ROW_HEIGHT = 20
local MENU_PADDING = 4
local MAX_WIDTH = DF.Layout.dropdownMaxWidth or 200
local MIN_WIDTH = DF.Layout.dropdownMinWidth or 120

local activeMenu = nil

function DF.Widgets:CreateDropDown()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    DF.Theme:ApplyDarkPanel(frame, true)
    frame:Hide()

    local rows = {}
    local menu = {
        frame = frame,
        rows = rows,
    }

    -- Close on outside click
    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN")
    blocker:Hide()
    blocker:SetScript("OnClick", function()
        menu:Hide()
    end)

    function menu:GetRow(index)
        if rows[index] then
            rows[index]:Show()
            return rows[index]
        end

        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(ROW_HEIGHT)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(unpack(DF.Colors.highlight))
        row.hl = hl

        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", 8, 0)
        text:SetPoint("RIGHT", -8, 0)
        row.text = text

        -- Separator line
        local sep = row:CreateTexture(nil, "OVERLAY")
        sep:SetHeight(1)
        sep:SetPoint("LEFT", 4, 0)
        sep:SetPoint("RIGHT", -4, 0)
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        sep:Hide()
        row.sep = sep

        rows[index] = row
        return row
    end

    function menu:HideAllRows()
        for _, row in ipairs(rows) do
            row:Hide()
        end
    end

    function menu:Show(anchor, items, xOff, yOff)
        if activeMenu and activeMenu ~= self then
            activeMenu:Hide()
        end
        activeMenu = self

        self:HideAllRows()

        -- Calculate width
        local maxTextW = MIN_WIDTH
        for _, item in ipairs(items) do
            if not item.isSeparator and item.text then
                local testStr = frame:CreateFontString(nil, "OVERLAY")
                testStr:SetFontObject(DF.Theme:UIFont())
                testStr:SetText(item.text)
                local w = testStr:GetStringWidth() + 24
                if w > maxTextW then maxTextW = w end
                testStr:Hide()
            end
        end
        maxTextW = math.min(maxTextW, MAX_WIDTH)

        local totalH = MENU_PADDING * 2
        for i, item in ipairs(items) do
            local row = self:GetRow(i)
            row:SetWidth(maxTextW)

            if item.isSeparator then
                row:SetHeight(8)
                row.text:SetText("")
                row.sep:Show()
                row.hl:Hide()
                row:SetScript("OnClick", nil)
                totalH = totalH + 8
            else
                row:SetHeight(ROW_HEIGHT)
                row.sep:Hide()
                row.hl:Show()
                row.text:SetText(item.text or "")

                if item.disabled then
                    row.text:SetTextColor(0.4, 0.4, 0.4, 1)
                    row:SetScript("OnClick", nil)
                else
                    row.text:SetTextColor(0.83, 0.83, 0.83, 1)
                    row:SetScript("OnClick", function()
                        menu:Hide()
                        if item.func then
                            item.func()
                        end
                    end)
                end
                totalH = totalH + ROW_HEIGHT
            end
        end

        -- Position rows
        local yPos = -MENU_PADDING
        for i, item in ipairs(items) do
            local row = self:GetRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", MENU_PADDING, yPos)
            yPos = yPos - (item.isSeparator and 8 or ROW_HEIGHT)
        end

        frame:SetSize(maxTextW + MENU_PADDING * 2, totalH)
        frame:ClearAllPoints()
        if anchor then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOff or 0, yOff or 0)
        else
            local cursorX, cursorY = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
        end

        blocker:Show()
        blocker:SetFrameLevel(frame:GetFrameLevel() - 1)
        frame:Show()
    end

    function menu:Hide()
        frame:Hide()
        blocker:Hide()
        activeMenu = nil
    end

    return menu
end
