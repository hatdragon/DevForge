local _, DF = ...

DF.UI = DF.UI or {}
DF.UI.TabBar = {}

local TabBar = DF.UI.TabBar

function TabBar:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(DF.Layout.tabHeight)

    local bar = {
        frame = frame,
        tabs = {},
        activeTab = nil,
    }

    function bar:Build()
        -- Clear existing tabs
        for _, tab in ipairs(self.tabs) do
            tab:Hide()
        end
        wipe(self.tabs)

        local names = DF.ModuleSystem:GetModuleNames()
        local xOffset = 4

        for i, name in ipairs(names) do
            local label = DF.ModuleSystem:GetTabLabel(name)
            local tab = self:CreateTab(name, label, xOffset)
            tab:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", xOffset, 0)
            self.tabs[i] = tab
            xOffset = xOffset + DF.Layout.tabWidth + 2
        end

        self:UpdateHighlight()
    end

    function bar:CreateTab(moduleName, label, xPos)
        local tab = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
        tab:SetSize(DF.Layout.tabWidth, DF.Layout.tabHeight)
        tab:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        })
        tab:SetBackdropColor(unpack(DF.Colors.tabInactive))

        local text = tab:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetPoint("CENTER", 0, 0)
        text:SetText(label)
        text:SetTextColor(0.65, 0.65, 0.65, 1)
        tab.text = text

        tab.moduleName = moduleName

        tab:SetScript("OnClick", function()
            DF.ModuleSystem:Activate(moduleName)
        end)

        tab:SetScript("OnEnter", function(self)
            if self.moduleName ~= bar.activeTab then
                self:SetBackdropColor(unpack(DF.Colors.tabHover))
            end
        end)

        tab:SetScript("OnLeave", function(self)
            if self.moduleName ~= bar.activeTab then
                self:SetBackdropColor(unpack(DF.Colors.tabInactive))
            end
        end)

        return tab
    end

    function bar:UpdateHighlight()
        for _, tab in ipairs(self.tabs) do
            if tab.moduleName == self.activeTab then
                tab:SetBackdropColor(unpack(DF.Colors.tabActive))
                tab.text:SetTextColor(0.9, 0.9, 0.9, 1)
            else
                tab:SetBackdropColor(unpack(DF.Colors.tabInactive))
                tab.text:SetTextColor(0.65, 0.65, 0.65, 1)
            end
        end
    end

    -- Listen for module activation
    DF.EventBus:On("DF_MODULE_ACTIVATED", function(name)
        bar.activeTab = name
        bar:UpdateHighlight()
    end, bar)

    return bar
end
