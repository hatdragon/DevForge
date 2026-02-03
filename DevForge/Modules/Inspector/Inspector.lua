local _, DF = ...

-- Register the Inspector module with sidebar + editor split
DF.ModuleSystem:Register("Inspector", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local inspector = {}
    local currentFrame = nil

    ---------------------------------------------------------------------------
    -- Sidebar: frame hierarchy tree
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local tree = DF.Widgets:CreateTreeView(sidebarFrame)
    tree.frame:SetAllPoints(sidebarFrame)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + property grid
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local pickBtn = DF.Widgets:CreateButton(toolbar, "Pick Frame", 90)
    pickBtn:SetPoint("LEFT", 2, 0)

    local refreshBtn = DF.Widgets:CreateButton(toolbar, "Refresh", 70)
    refreshBtn:SetPoint("LEFT", pickBtn, "RIGHT", 4, 0)

    local gridBtn = DF.Widgets:CreateButton(toolbar, "Grid", 55)
    gridBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 4, 0)

    local genCodeBtn = DF.Widgets:CreateButton(toolbar, "Gen Code", 75)
    genCodeBtn:SetPoint("LEFT", gridBtn, "RIGHT", 4, 0)

    local texBrowserBtn = DF.Widgets:CreateButton(toolbar, "View in Textures", 110)
    texBrowserBtn:SetPoint("LEFT", genCodeBtn, "RIGHT", 4, 0)
    texBrowserBtn:Hide()

    local fstackBtn = DF.Widgets:CreateButton(toolbar, "Blizz FStack", 85)
    fstackBtn:SetPoint("LEFT", texBrowserBtn, "RIGHT", 8, 0)
    fstackBtn:SetScript("OnClick", function()
        if ChatFrame_ImportAllListsToHash then
            ChatFrame_ImportAllListsToHash()
        end
        if hash_SlashCmdList and hash_SlashCmdList["/FSTACK"] then
            hash_SlashCmdList["/FSTACK"]("")
        end
    end)

    local infoLabel = toolbar:CreateFontString(nil, "OVERLAY")
    infoLabel:SetFontObject(DF.Theme:UIFont())
    infoLabel:SetPoint("RIGHT", -4, 0)
    infoLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    infoLabel:SetText("Select a frame to inspect")

    -- Property grid (main editor area)
    local propGrid = DF.Widgets:CreatePropertyGrid(editorFrame)
    propGrid.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    propGrid.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Logic
    ---------------------------------------------------------------------------
    -- Determine texture info for the "View in Textures" button
    local function GetTextureInfo(obj)
        if not obj then return nil end
        local okT, objType = pcall(function() return obj:GetObjectType() end)
        if not okT or (objType ~= "Texture" and objType ~= "MaskTexture") then return nil end
        -- Prefer atlas
        local okA, atlas = pcall(function() return obj:GetAtlas() end)
        if okA and type(atlas) == "string" and atlas ~= "" then
            return { path = atlas, isAtlas = true }
        end
        -- Fall back to texture path (skip render targets, 0, nil, empty)
        local okP, texPath = pcall(function() return obj:GetTexture() end)
        if okP and texPath ~= nil and texPath ~= "" and texPath ~= 0 then
            if type(texPath) ~= "string" or not texPath:match("^RT") then
                return { path = texPath, isAtlas = false }
            end
        end
        -- Fall back to FileID
        local okFID, fileID = pcall(function() return obj:GetTextureFileID() end)
        if okFID and type(fileID) == "number" and fileID ~= 0 then
            return { path = fileID, isAtlas = false }
        end
        return nil
    end

    local function UpdateTexBrowserBtn(obj)
        local info = GetTextureInfo(obj)
        if info then
            texBrowserBtn:Show()
            texBrowserBtn._texInfo = info
        else
            texBrowserBtn:Hide()
            texBrowserBtn._texInfo = nil
        end
    end

    texBrowserBtn:SetScript("OnClick", function(self)
        if self._texInfo then
            DF.EventBus:Fire("DF_SHOW_IN_TEXTURE_BROWSER", self._texInfo)
        end
    end)

    local function InspectFrame(targetFrame)
        currentFrame = targetFrame
        if not targetFrame then
            tree:SetNodes({})
            propGrid:Clear()
            infoLabel:SetText("Select a frame to inspect")
            UpdateTexBrowserBtn(nil)
            return
        end

        local nodes = DF.InspectorTree:BuildFamilyTree(targetFrame)
        tree:SetNodes(nodes)

        local targetId = DF.InspectorTree:FindNodeId(targetFrame)
        tree:ExpandNode(nodes[1] and nodes[1].id or "")
        tree:SetSelected(targetId)

        local sections = DF.InspectorProps:BuildSections(targetFrame)
        propGrid:SetSections(sections)

        local name = ""
        local ok, n = pcall(function() return targetFrame:GetName() end)
        if ok and n then name = n else name = tostring(targetFrame) end
        infoLabel:SetText("Inspecting: " .. name)
        UpdateTexBrowserBtn(targetFrame)
    end

    -- Tree selection handler
    tree:SetOnSelect(function(node)
        if node and node.data then
            currentFrame = node.data
            local sections = DF.InspectorProps:BuildSections(node.data)
            propGrid:SetSections(sections)

            local name = ""
            local ok, n = pcall(function() return node.data:GetName() end)
            if ok and n then name = n else name = tostring(node.data) end
            infoLabel:SetText("Inspecting: " .. name)
            UpdateTexBrowserBtn(node.data)

            DF.InspectorHighlight:Create()
            DF.InspectorHighlight:Show(node.data)

            if DF.InspectorGrid:IsShown() then
                DF.InspectorGrid:UpdateTarget(node.data)
            end
        end
    end)

    pickBtn:SetScript("OnClick", function()
        inspector:StartPicker()
    end)

    refreshBtn:SetScript("OnClick", function()
        if currentFrame then
            InspectFrame(currentFrame)
        end
    end)

    gridBtn:SetScript("OnClick", function()
        DF.InspectorGrid:Toggle(currentFrame)
        if DF.InspectorGrid:IsShown() then
            gridBtn:SetLabel("Grid On")
        else
            gridBtn:SetLabel("Grid")
        end
    end)

    -- Generate Code button: sends frame constructor code to editor
    genCodeBtn:SetScript("OnClick", function()
        if not currentFrame then return end

        local name = ""
        local ok, n = pcall(function() return currentFrame:GetName() end)
        if ok and n then name = n else name = tostring(currentFrame) end

        local lines = {}
        lines[#lines + 1] = "local f = " .. name

        -- Size
        local okW, w = pcall(function() return currentFrame:GetWidth() end)
        local okH, h = pcall(function() return currentFrame:GetHeight() end)
        if okW and okH and w and h then
            lines[#lines + 1] = string.format("-- Size: %.0fx%.0f", w, h)
        end

        -- Position
        local okP, point, relativeTo, relPoint, x, y = pcall(function()
            return currentFrame:GetPoint(1)
        end)
        if okP and point then
            local relName = ""
            if relativeTo then
                local okR, rn = pcall(function() return relativeTo:GetName() end)
                relName = (okR and rn) or "UIParent"
            else
                relName = "UIParent"
            end
            lines[#lines + 1] = string.format("-- Position: %s, %s, %s, %.0f, %.0f",
                point or "CENTER", relName, relPoint or "CENTER", x or 0, y or 0)
        end

        local code = table.concat(lines, "\n")
        DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
    end)

    -- Navigate to a frame (e.g. clicking Parent row)
    DF.EventBus:On("DF_INSPECTOR_NAVIGATE", function(targetFrame)
        if targetFrame then
            InspectFrame(targetFrame)
        end
    end, inspector)

    -- Picker
    function inspector:StartPicker()
        if DF.MainWindow then
            DF.MainWindow:Hide()
        end

        local function RestoreWindow()
            if DF.MainWindow then
                DF.MainWindow:Show()
            end
        end

        DF.InspectorPicker:Start(
            function(pickedFrame)
                RestoreWindow()
                if pickedFrame then
                    InspectFrame(pickedFrame)
                end
            end,
            function()
                RestoreWindow()
            end
        )
    end

    function inspector:OnActivate()
        if currentFrame then
            DF.InspectorHighlight:Create()
            DF.InspectorHighlight:Show(currentFrame)
        end
    end

    function inspector:OnDeactivate()
        DF.InspectorHighlight:Hide()
        DF.InspectorGrid:Hide()
        gridBtn:SetLabel("Grid")
        if DF.InspectorPicker:IsActive() then
            DF.InspectorPicker:Stop()
            if DF.MainWindow then
                DF.MainWindow:Show()
            end
        end
    end

    inspector.sidebar = sidebarFrame
    inspector.editor = editorFrame
    return inspector
end, "Inspector")
