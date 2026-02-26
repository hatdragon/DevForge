local _, DF = ...

DF.APIBrowserDetail = {}

local Detail = DF.APIBrowserDetail

-- Helper: safely get a Documentation field as a string
local function DocString(doc)
    if not doc then return nil end
    if type(doc) == "table" then return table.concat(doc, " ") end
    return tostring(doc)
end

-- Helper: format a single field/argument/return line with all available metadata
local function FormatField(field)
    local typeStr = field.Type or "any"
    local parts = {}

    -- Name : Type
    parts[#parts + 1] = "  " .. DF.Colors.text .. field.Name .. "|r"
        .. " : " .. DF.Colors.tableRef .. typeStr .. "|r"

    -- InnerType for table types (e.g. table<number>)
    if field.InnerType then
        parts[#parts + 1] = DF.Colors.dim .. "<" .. DF.Colors.tableRef .. field.InnerType .. "|r" .. DF.Colors.dim .. ">|r"
    end

    -- Mixin — the Lua mixin class this argument expects
    if field.Mixin then
        parts[#parts + 1] = DF.Colors.dim .. " mixin:" .. DF.Colors.func .. field.Mixin .. "|r"
    end

    -- Nilable
    if field.Nilable then
        parts[#parts + 1] = DF.Colors.dim .. " [nilable]|r"
    end

    -- Default value
    if field.Default ~= nil then
        parts[#parts + 1] = DF.Colors.dim .. " default:" .. DF.Colors.number .. tostring(field.Default) .. "|r"
    end

    -- EnumValue (for enum fields)
    if field.EnumValue ~= nil then
        parts[#parts + 1] = " = " .. DF.Colors.number .. tostring(field.EnumValue) .. "|r"
    end

    -- StrideIndex — position within repeating argument groups
    if field.StrideIndex then
        parts[#parts + 1] = DF.Colors.dim .. " stride:" .. tostring(field.StrideIndex) .. "|r"
    end

    -- Documentation
    local doc = DocString(field.Documentation)
    if doc then
        parts[#parts + 1] = " - " .. DF.Colors.comment .. doc .. "|r"
    end

    return table.concat(parts)
end

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
        -- Function header
        lines[#lines + 1] = DF.Colors.func .. (system or "") .. "." .. (doc.Name or "?") .. "|r"

        -- Security and flags
        if doc.SecretArguments then
            local secLabel, secColor
            if doc.SecretArguments == "AllowedWhenUntainted" then
                secLabel = "Callable from addon code (untainted execution only)"
                secColor = DF.Colors.dim
            elseif doc.SecretArguments == "NotAllowed" then
                secLabel = "Protected — cannot be called from addon code"
                secColor = DF.Colors.error
            else
                secLabel = doc.SecretArguments
                secColor = DF.Colors.dim
            end
            lines[#lines + 1] = DF.Colors.text .. "Security: |r" .. secColor .. secLabel .. "|r"
        end
        if doc.MayReturnNothing then
            lines[#lines + 1] = DF.Colors.text .. "Returns: |r" .. DF.Colors.dim .. "may return nothing (check for nil)|r"
        end
        lines[#lines + 1] = ""

        -- Build signature string
        local params = {}
        if doc.Arguments then
            for _, arg in ipairs(doc.Arguments) do
                local p = arg.Name
                if arg.Nilable then p = p .. " [optional]" end
                params[#params + 1] = p
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

        if doc.MayReturnNothing then
            sig = sig .. DF.Colors.dim .. "  -- may return nothing|r"
        end

        lines[#lines + 1] = DF.Colors.text .. sig .. "|r"
        lines[#lines + 1] = ""

        -- Documentation
        local docText = DocString(doc.Documentation)
        if docText then
            lines[#lines + 1] = DF.Colors.comment .. "-- " .. docText .. "|r"
            lines[#lines + 1] = ""
        end

        -- Parameters
        if doc.Arguments and #doc.Arguments > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Parameters:|r"
            for _, arg in ipairs(doc.Arguments) do
                lines[#lines + 1] = FormatField(arg)
            end
            lines[#lines + 1] = ""
        end

        -- Returns
        if doc.Returns and #doc.Returns > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Returns:|r"
            for _, ret in ipairs(doc.Returns) do
                lines[#lines + 1] = FormatField(ret)
            end
        end
    end

    function detail:FormatEvent(lines, system, doc)
        lines[#lines + 1] = DF.Colors.keyword .. (doc.Name or "?") .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Event in " .. (system or "?") .. "|r"
        lines[#lines + 1] = ""

        -- LiteralName — the actual event string for RegisterEvent
        if doc.LiteralName then
            lines[#lines + 1] = DF.Colors.text .. "RegisterEvent:|r  "
                .. DF.Colors.string .. "\"" .. doc.LiteralName .. "\"|r"
            lines[#lines + 1] = ""
        end

        -- Synchronous flag
        if doc.SynchronousEvent then
            lines[#lines + 1] = DF.Colors.text .. "Timing: |r" .. DF.Colors.dim .. "Fires synchronously (before frame rendering)|r"
            lines[#lines + 1] = ""
        end

        -- Documentation
        local docText = DocString(doc.Documentation)
        if docText then
            lines[#lines + 1] = DF.Colors.comment .. "-- " .. docText .. "|r"
            lines[#lines + 1] = ""
        end

        -- Payload
        if doc.Payload and #doc.Payload > 0 then
            lines[#lines + 1] = DF.Colors.keyword .. "Payload:|r"
            for _, arg in ipairs(doc.Payload) do
                lines[#lines + 1] = FormatField(arg)
            end
        end
    end

    function detail:FormatTable(lines, system, doc)
        local typeLabel = doc.Type or "Table"
        lines[#lines + 1] = DF.Colors.tableRef .. (doc.Name or "?") .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. typeLabel .. " in " .. (system or "?") .. "|r"
        lines[#lines + 1] = ""

        -- Documentation
        local docText = DocString(doc.Documentation)
        if docText then
            lines[#lines + 1] = DF.Colors.comment .. "-- " .. docText .. "|r"
            lines[#lines + 1] = ""
        end

        -- Enumeration range info
        if doc.Type == "Enumeration" then
            local rangeParts = {}
            if doc.NumValues then
                rangeParts[#rangeParts + 1] = DF.Colors.number .. doc.NumValues .. "|r" .. DF.Colors.text .. " values|r"
            end
            if doc.MinValue then
                rangeParts[#rangeParts + 1] = DF.Colors.text .. "min " .. DF.Colors.number .. doc.MinValue .. "|r"
            end
            if doc.MaxValue then
                rangeParts[#rangeParts + 1] = DF.Colors.text .. "max " .. DF.Colors.number .. doc.MaxValue .. "|r"
            end
            if #rangeParts > 0 then
                lines[#lines + 1] = table.concat(rangeParts, DF.Colors.dim .. " | |r")
                lines[#lines + 1] = ""
            end
        end

        if doc.Type == "Enumeration" and doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Values:|r"
            for _, field in ipairs(doc.Fields) do
                local valStr = ""
                if field.EnumValue ~= nil then
                    valStr = " = " .. DF.Colors.number .. tostring(field.EnumValue) .. "|r"
                end
                local docStr = DocString(field.Documentation)
                if docStr then
                    valStr = valStr .. " - " .. DF.Colors.comment .. docStr .. "|r"
                end
                lines[#lines + 1] = "  " .. DF.Colors.text .. field.Name .. "|r" .. valStr
            end
        elseif doc.Type == "Structure" and doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Fields:|r"
            for _, field in ipairs(doc.Fields) do
                lines[#lines + 1] = FormatField(field)
            end
        elseif doc.Fields then
            lines[#lines + 1] = DF.Colors.keyword .. "Fields:|r"
            for _, field in ipairs(doc.Fields) do
                lines[#lines + 1] = FormatField(field)
            end
        end
    end

    function detail:FormatNamespace(lines, system)
        lines[#lines + 1] = DF.Colors.func .. system .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Namespace|r"
        lines[#lines + 1] = ""

        local sys = DF.APIBrowserData:GetSystem(system)
        if sys then
            -- Environment
            if sys.Environment then
                lines[#lines + 1] = DF.Colors.text .. "Environment: " .. DF.Colors.dim .. sys.Environment .. "|r"
            end

            local funcCount = sys.Functions and #sys.Functions or 0
            local eventCount = sys.Events and #sys.Events or 0
            local tableCount = sys.Tables and #sys.Tables or 0

            lines[#lines + 1] = DF.Colors.text .. "Functions: " .. DF.Colors.number .. funcCount .. "|r"
            lines[#lines + 1] = DF.Colors.text .. "Events: " .. DF.Colors.number .. eventCount .. "|r"
            lines[#lines + 1] = DF.Colors.text .. "Tables: " .. DF.Colors.number .. tableCount .. "|r"

            -- Documentation
            local docText = DocString(sys.Documentation)
            if docText then
                lines[#lines + 1] = ""
                lines[#lines + 1] = DF.Colors.comment .. "-- " .. docText .. "|r"
            end
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
