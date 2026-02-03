local _, DF = ...

DF.Widgets = DF.Widgets or {}

function DF.Widgets:CreateButton(parent, text, width, height)
    width = width or 80
    height = height or DF.Layout.buttonHeight

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(unpack(DF.Colors.buttonNormal))
    btn:SetBackdropBorderColor(unpack(DF.Colors.panelBorder))

    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetFontObject(DF.Theme:UIFont())
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetText(text or "")
    btn.label:SetTextColor(0.83, 0.83, 0.83, 1)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(DF.Colors.buttonHover))
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isPressed then
            self:SetBackdropColor(unpack(DF.Colors.buttonNormal))
        end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self.isPressed = true
        self:SetBackdropColor(unpack(DF.Colors.buttonPress))
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.isPressed = false
        if self:IsMouseOver() then
            self:SetBackdropColor(unpack(DF.Colors.buttonHover))
        else
            self:SetBackdropColor(unpack(DF.Colors.buttonNormal))
        end
    end)

    function btn:SetLabel(newText)
        self.label:SetText(newText)
    end

    function btn:SetEnabled(enabled)
        if enabled then
            self:Enable()
            self.label:SetTextColor(0.83, 0.83, 0.83, 1)
        else
            self:Disable()
            self.label:SetTextColor(0.4, 0.4, 0.4, 1)
        end
    end

    return btn
end
