local _, DF = ...

DF.UI = DF.UI or {}
DF.UI.Sidebar = {}

local Sidebar = DF.UI.Sidebar

function Sidebar:Create(parent)
    local L = DF.Layout

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    frame:SetBackdropColor(unpack(DF.Colors.sidebarBg))

    local sidebar = {
        frame = frame,
        collapsed = false,
        currentContent = nil,
        width = L.sidebarDefaultW,
    }

    -- Header bar
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(L.sidebarHeaderH)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    header:SetBackdropColor(unpack(DF.Colors.sidebarHeaderBg))
    sidebar.header = header

    -- Title label
    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(DF.Theme:UIFont())
    title:SetPoint("LEFT", 6, 0)
    title:SetTextColor(0.7, 0.7, 0.7, 1)
    title:SetText("Sidebar")
    sidebar.title = title

    -- Collapse toggle button
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:RegisterForClicks("LeftButtonUp")
    collapseBtn:SetSize(16, 16)
    collapseBtn:SetPoint("RIGHT", -4, 0)

    local collapseTex = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseTex:SetSize(12, 12)
    collapseTex:SetPoint("CENTER", 0, 0)
    collapseTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    collapseTex:SetVertexColor(0.6, 0.6, 0.6, 1)
    sidebar.collapseTex = collapseTex

    collapseBtn:SetScript("OnEnter", function()
        collapseTex:SetVertexColor(0.9, 0.9, 0.9, 1)
    end)
    collapseBtn:SetScript("OnLeave", function()
        collapseTex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    collapseBtn:SetScript("OnClick", function()
        sidebar:Toggle()
    end)

    -- Content area (modules mount their sidebar frame here)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    sidebar.content = content

    -- Placeholder text for modules with no sidebar
    local placeholder = content:CreateFontString(nil, "OVERLAY")
    placeholder:SetFontObject(DF.Theme:UIFont())
    placeholder:SetPoint("CENTER", 0, 0)
    placeholder:SetText("")
    placeholder:SetTextColor(0.4, 0.4, 0.4, 1)
    sidebar.placeholder = placeholder

    -- Restore state from saved variables
    function sidebar:RestoreState()
        if DevForgeDB then
            self.width = DevForgeDB.sidebarWidth or L.sidebarDefaultW
            self.collapsed = DevForgeDB.sidebarCollapsed or false
        end
    end

    -- Save state
    function sidebar:SaveState()
        if DevForgeDB then
            DevForgeDB.sidebarWidth = self.width
            DevForgeDB.sidebarCollapsed = self.collapsed
        end
    end

    -- Set the content frame (mount a module's sidebar frame)
    function sidebar:SetContent(moduleFrame)
        -- Hide previous content
        if self.currentContent then
            self.currentContent:Hide()
            self.currentContent:ClearAllPoints()
        end

        self.currentContent = moduleFrame

        if moduleFrame then
            moduleFrame:SetParent(content)
            moduleFrame:ClearAllPoints()
            moduleFrame:SetAllPoints(content)
            moduleFrame:Show()
            placeholder:Hide()
        else
            placeholder:Show()
        end
    end

    -- Set header title
    function sidebar:SetTitle(text)
        title:SetText(text or "Sidebar")
    end

    -- Toggle collapse/expand
    function sidebar:Toggle()
        if self.collapsed then
            self:Expand()
        else
            self:Collapse()
        end
    end

    function sidebar:Collapse()
        self.collapsed = true
        content:Hide()
        title:Hide()
        frame:SetWidth(L.sidebarHeaderH) -- narrow strip, just wide enough for toggle
        collapseTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        self:SaveState()
        DF.EventBus:Fire("DF_SIDEBAR_TOGGLED", false)
    end

    function sidebar:Expand()
        self.collapsed = false
        content:Show()
        title:Show()
        frame:SetWidth(self.width)
        collapseTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        self:SaveState()
        DF.EventBus:Fire("DF_SIDEBAR_TOGGLED", true)
    end

    function sidebar:IsCollapsed()
        return self.collapsed
    end

    function sidebar:GetWidth()
        return self.width
    end

    function sidebar:SetWidth(w)
        self.width = DF.Util:Clamp(w, L.sidebarMinW, L.sidebarMaxW)
        frame:SetWidth(self.width)
        self:SaveState()
    end

    return sidebar
end
