local _, DF = ...

-- Register the API Browser module with sidebar + editor split
DF.ModuleSystem:Register("APIBrowser", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local browser = {}

    ---------------------------------------------------------------------------
    -- Sidebar: namespace list with search
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local list = DF.APIBrowserList:Create(sidebarFrame)
    list.frame:SetAllPoints(sidebarFrame)

    ---------------------------------------------------------------------------
    -- Editor: detail view with Insert Call button
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Error/loading state
    local errorFrame = CreateFrame("Frame", nil, editorFrame)
    errorFrame:SetAllPoints(editorFrame)
    errorFrame:Hide()

    local errorText = errorFrame:CreateFontString(nil, "OVERLAY")
    errorText:SetFontObject(DF.Theme:UIFont())
    errorText:SetPoint("CENTER", 0, 0)
    errorText:SetWidth(400)
    errorText:SetTextColor(0.8, 0.4, 0.4, 1)

    -- Content frame (hidden until data loads)
    local contentFrame = CreateFrame("Frame", nil, editorFrame)
    contentFrame:SetAllPoints(editorFrame)
    contentFrame:Hide()

    -- Detail view
    local detail = DF.APIBrowserDetail:Create(contentFrame)
    detail.frame:SetPoint("TOPLEFT", 0, 0)
    detail.frame:SetPoint("BOTTOMRIGHT", 0, 30) -- leave room for Insert Call button

    -- Insert Call button at the bottom
    local insertCallBtn = DF.Widgets:CreateButton(contentFrame, "Insert Call", 100)
    insertCallBtn:SetPoint("BOTTOMLEFT", 4, 4)
    insertCallBtn:Hide()

    local currentData = nil

    -- Selection handler
    list:SetOnSelect(function(node)
        if node and node.data then
            currentData = node.data
            detail:ShowEntry(node.data)

            -- Show Insert Call for functions
            if node.data.type == "function" and node.data.doc then
                insertCallBtn:Show()
            else
                insertCallBtn:Hide()
            end

            if DevForgeDB and node.data.system then
                DevForgeDB.apiBrowserNS = node.data.system
            end
        end
    end)

    -- Insert Call generates a function call skeleton and sends to editor
    insertCallBtn:SetScript("OnClick", function()
        if not currentData or currentData.type ~= "function" or not currentData.doc then return end
        local doc = currentData.doc
        local system = currentData.system or ""

        -- Build arguments with safe placeholder values
        local args = {}
        if doc.Arguments then
            for _, arg in ipairs(doc.Arguments) do
                local argType = arg.Type or "any"
                if argType == "string" or argType == "cstring" then
                    args[#args + 1] = '"' .. (arg.Name or "str") .. '"'
                elseif argType == "number" or argType == "luaIndex" or argType == "uiMapID" then
                    args[#args + 1] = "0"
                elseif argType == "bool" then
                    args[#args + 1] = "true"
                else
                    -- Use nil with a type hint comment so the code is runnable
                    args[#args + 1] = "nil --[[" .. (arg.Name or "arg") .. ": " .. argType .. "]]"
                end
            end
        end

        -- Build return values
        local rets = {}
        if doc.Returns then
            for _, ret in ipairs(doc.Returns) do
                rets[#rets + 1] = ret.Name or "result"
            end
        end

        local lines = {}

        -- Warn if the namespace isn't currently loaded
        if system ~= "" and not _G[system] then
            lines[#lines + 1] = "-- " .. system .. " is not loaded; its Blizzard addon may need to be loaded first"
        end

        local call = system .. "." .. (doc.Name or "Unknown") .. "(" .. table.concat(args, ", ") .. ")"
        if #rets > 0 then
            lines[#lines + 1] = "local " .. table.concat(rets, ", ") .. " = " .. call
        else
            lines[#lines + 1] = call
        end

        DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = table.concat(lines, "\n") })
    end)

    -- Data state
    local dataLoaded = false

    function browser:LoadData()
        if dataLoaded then return end

        local ok, err = DF.APIBrowserData:Load()
        if not ok then
            errorFrame:Show()
            contentFrame:Hide()
            errorText:SetText("Failed to load API documentation:\n\n" .. (err or "Unknown error") .. "\n\nThe rest of DevForge is unaffected.")
            return
        end

        local nodes = DF.APIBrowserData:BuildTreeNodes()
        list:SetNodes(nodes)

        if DevForgeDB and DevForgeDB.apiBrowserNS then
            list:ExpandNamespace(DevForgeDB.apiBrowserNS)
        end

        errorFrame:Hide()
        contentFrame:Show()
        detail:ShowEmpty()
        dataLoaded = true
    end

    function browser:OnFirstActivate()
        self:LoadData()
    end

    function browser:OnActivate()
        -- Nothing special
    end

    function browser:OnDeactivate()
        -- Nothing special
    end

    browser.sidebar = sidebarFrame
    browser.editor = editorFrame
    return browser
end, "API Browser")
