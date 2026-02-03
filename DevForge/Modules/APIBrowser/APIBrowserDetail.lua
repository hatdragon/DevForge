local _, DF = ...

DF.APIBrowserDetail = {}

local Detail = DF.APIBrowserDetail

function Detail:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)

    -- Content EditBox (read-only, for selectable text)
    local editbox = CreateFrame("EditBox", nil, pane:GetContent())
    editbox:SetPoint("TOPLEFT", 8, -8)
    editbox:SetPoint("RIGHT", -8, 0)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(DF.Theme:CodeFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:EnableKeyboard(false)
    editbox:SetScript("OnChar", function() end)
    editbox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local detail = {
        frame = pane.frame,
        pane = pane,
        editbox = editbox,
    }

    function detail:ShowEntry(data)
        if not data then
            self:ShowEmpty()
            return
        end

        local lines = {}
        local doc = data.doc

        if data.type == "function" then
            self:FormatFunction(lines, data.system, doc)
        elseif data.type == "event" then
            self:FormatEvent(lines, data.system, doc)
        elseif data.type == "table" then
            self:FormatTable(lines, data.system, doc)
        elseif data.type == "namespace" then
            self:FormatNamespace(lines, data.system)
        end

        local text = table.concat(lines, "\n")
        editbox:SetText(text)

        C_Timer.After(0, function()
            local h = editbox:GetHeight() + 20
            pane:SetContentHeight(h)
            pane:ScrollToTop()
        end)
    end

    function detail:FormatFunction(lines, system, doc)
        -- Function signature
        lines[#lines + 1] = DF.Colors.func .. (system or "") .. "." .. (doc.Name or "?") .. "|r"
        lines[#lines + 1] = ""

        -- Build signature string
        local params = {}
        if doc.Arguments then
            for _, arg in ipairs(doc.Arguments) do
                local nilable = arg.Nilable and " [optional]" or ""
                params[#params + 1] = arg.Name .. nilable
            end
        end

        local returns = {}
        if doc.Returns then
            for _, ret in ipairs(doc.Returns) do
                returns[#returns + 1] = ret.Name
            end
        end

        local sig = ""
        if #returns > 0 then
            sig = table.concat(returns, ", ") .. " = "
        end
        sig = sig .. (system or "") .. "." .. (doc.Name or "?") .. "(" .. table.concat(params, ", ") .. ")"
        lines[#lines + 1] = DF.Colors.text .. sig .. "|r"
        lines[#lines + 1] = ""

        -- Documentation
        if doc.Documentation then
            lines[#lines + 1] = DF.Colors.comment .. "-- " .. doc.Documentation .. "|r"
            lines[#lines + 1] = ""
        end

        -- Parameters
        if doc.Arguments and #doc.Arguments > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Parameters:|r"
            for _, arg in ipairs(doc.Arguments) do
                local typeStr = arg.Type or "any"
                local nilable = arg.Nilable and (DF.Colors.dim .. " [nilable]|r") or ""
                local argLine = "  " .. DF.Colors.text .. arg.Name .. "|r"
                    .. " : " .. DF.Colors.tableRef .. typeStr .. "|r"
                    .. nilable
                if arg.Documentation then
                    argLine = argLine .. " - " .. DF.Colors.comment .. arg.Documentation .. "|r"
                end
                lines[#lines + 1] = argLine
            end
            lines[#lines + 1] = ""
        end

        -- Returns
        if doc.Returns and #doc.Returns > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Returns:|r"
            for _, ret in ipairs(doc.Returns) do
                local typeStr = ret.Type or "any"
                local nilable = ret.Nilable and (DF.Colors.dim .. " [nilable]|r") or ""
                local retLine = "  " .. DF.Colors.text .. ret.Name .. "|r"
                    .. " : " .. DF.Colors.tableRef .. typeStr .. "|r"
                    .. nilable
                if ret.Documentation then
                    retLine = retLine .. " - " .. DF.Colors.comment .. ret.Documentation .. "|r"
                end
                lines[#lines + 1] = retLine
            end
        end
    end

    function detail:FormatEvent(lines, system, doc)
        lines[#lines + 1] = DF.Colors.keyword .. (doc.Name or "?") .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Event in " .. (system or "?") .. "|r"
        lines[#lines + 1] = ""

        if doc.Documentation then
            lines[#lines + 1] = DF.Colors.comment .. "-- " .. doc.Documentation .. "|r"
            lines[#lines + 1] = ""
        end

        if doc.Payload and #doc.Payload > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Payload:|r"
            for _, arg in ipairs(doc.Payload) do
                local typeStr = arg.Type or "any"
                local nilable = arg.Nilable and (DF.Colors.dim .. " [nilable]|r") or ""
                lines[#lines + 1] = "  " .. DF.Colors.text .. arg.Name .. "|r"
                    .. " : " .. DF.Colors.tableRef .. typeStr .. "|r"
                    .. nilable
            end
        end
    end

    function detail:FormatTable(lines, system, doc)
        lines[#lines + 1] = DF.Colors.tableRef .. (doc.Name or "?") .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Table/Enum in " .. (system or "?") .. "|r"
        lines[#lines + 1] = ""

        if doc.Type == "Enumeration" and doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Values:|r"
            for _, field in ipairs(doc.Fields) do
                local valStr = ""
                if field.EnumValue then
                    valStr = " = " .. DF.Colors.number .. tostring(field.EnumValue) .. "|r"
                end
                lines[#lines + 1] = "  " .. DF.Colors.text .. field.Name .. "|r" .. valStr
            end
        elseif doc.Type == "Structure" and doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Fields:|r"
            for _, field in ipairs(doc.Fields) do
                local typeStr = field.Type or "any"
                local nilable = field.Nilable and (DF.Colors.dim .. " [nilable]|r") or ""
                lines[#lines + 1] = "  " .. DF.Colors.text .. field.Name .. "|r"
                    .. " : " .. DF.Colors.tableRef .. typeStr .. "|r"
                    .. nilable
            end
        elseif doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Fields:|r"
            for _, field in ipairs(doc.Fields) do
                lines[#lines + 1] = "  " .. DF.Colors.text .. (field.Name or "?") .. "|r"
            end
        end
    end

    function detail:FormatNamespace(lines, system)
        lines[#lines + 1] = DF.Colors.func .. system .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Namespace|r"
        lines[#lines + 1] = ""

        local sys = DF.APIBrowserData:GetSystem(system)
        if sys then
            local funcCount = sys.Functions and #sys.Functions or 0
            local eventCount = sys.Events and #sys.Events or 0
            local tableCount = sys.Tables and #sys.Tables or 0

            lines[#lines + 1] = DF.Colors.text .. "Functions: " .. DF.Colors.number .. funcCount .. "|r"
            lines[#lines + 1] = DF.Colors.text .. "Events: " .. DF.Colors.number .. eventCount .. "|r"
            lines[#lines + 1] = DF.Colors.text .. "Tables: " .. DF.Colors.number .. tableCount .. "|r"
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = DF.Colors.dim .. "Click an item in the tree to see its details.|r"
    end

    function detail:ShowEmpty()
        editbox:SetText(DF.Colors.dim .. "Select an API entry to view details.|r")
        pane:SetContentHeight(40)
    end

    -- Handle resize
    pane.frame:SetScript("OnSizeChanged", function()
        local w = pane.scrollFrame:GetWidth()
        if w <= 0 then return end
        pane:GetContent():SetWidth(w)
        editbox:SetWidth(math.max(50, w - 16))
        C_Timer.After(0, function()
            local h = editbox:GetHeight()
            if h and h > 0 then
                pane:SetContentHeight(h + 20)
            end
            pane:UpdateThumb()
        end)
    end)

    return detail
end
