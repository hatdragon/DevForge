local _, DF = ...

-- Register the Texture Browser module with sidebar + editor split
DF.ModuleSystem:Register("TextureBrowser", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local browser = {}

    ---------------------------------------------------------------------------
    -- State
    ---------------------------------------------------------------------------
    local activeTab = "atlas"
    local currentResults = {}
    local lastSelectedNode = nil
    local previewSize = 64
    local previewItems = {}
    local MAX_GRID_ITEMS = 500
    local unloadTimer = nil
    local contextMenu = nil
    local ShowContextMenu
    local validFrame = CreateFrame("Frame", nil, UIParent)
    validFrame:SetSize(1, 1)
    validFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    local testValidTex = validFrame:CreateTexture(nil, "BACKGROUND")
    testValidTex:SetAllPoints()
    local ShowTextures
    local SwitchTab

    ---------------------------------------------------------------------------
    -- Full-size preview popup (same as before, unchanged)
    ---------------------------------------------------------------------------
    local previewPopup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    previewPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    previewPopup:SetClampedToScreen(true)
    previewPopup:SetMovable(true)
    previewPopup:EnableMouse(true)
    previewPopup:Hide()
    DF.Theme:ApplyDarkPanel(previewPopup, true)

    previewPopup:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self:StartMoving() end
    end)
    previewPopup:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    previewPopup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local previewBlocker = CreateFrame("Button", nil, UIParent)
    previewBlocker:RegisterForClicks("LeftButtonUp")
    previewBlocker:SetAllPoints(UIParent)
    previewBlocker:SetFrameStrata("FULLSCREEN")
    previewBlocker:Hide()
    previewBlocker:SetScript("OnClick", function() previewPopup:Hide() end)

    local previewCloseBtn = CreateFrame("Button", nil, previewPopup, "UIPanelCloseButton")
    previewCloseBtn:SetPoint("TOPRIGHT", -2, -2)

    local previewPath = previewPopup:CreateFontString(nil, "OVERLAY")
    previewPath:SetFontObject(DF.Theme:CodeFont())
    previewPath:SetPoint("TOPLEFT", 8, -8)
    previewPath:SetPoint("TOPRIGHT", -28, -8)
    previewPath:SetJustifyH("LEFT")
    previewPath:SetWordWrap(false)
    previewPath:SetTextColor(0.6, 0.75, 1, 1)

    local previewSizeLabel = previewPopup:CreateFontString(nil, "OVERLAY")
    previewSizeLabel:SetFontObject(DF.Theme:UIFont())
    previewSizeLabel:SetPoint("TOPLEFT", previewPath, "BOTTOMLEFT", 0, -2)
    previewSizeLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local previewChecker = previewPopup:CreateTexture(nil, "BORDER")
    previewChecker:SetPoint("TOP", previewSizeLabel, "BOTTOM", 0, -6)
    previewChecker:SetColorTexture(0.15, 0.15, 0.15, 1)

    local previewTex = previewPopup:CreateTexture(nil, "ARTWORK")
    previewTex:SetPoint("TOP", previewSizeLabel, "BOTTOM", 0, -6)

    local PREVIEW_MAX = 512
    local PREVIEW_PAD = 16

    local function ShowPreviewPopup(itemData)
        if not itemData or not itemData.path then return end
        previewTex:SetTexture(nil)
        previewTex:SetTexCoord(0, 1, 0, 1)

        local texW, texH = 256, 256
        if itemData.isAtlas then
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tostring(itemData.path))
            if info and info.width and info.height and info.width > 0 and info.height > 0 then
                texW = info.width
                texH = info.height
            end
            pcall(function() previewTex:SetAtlas(tostring(itemData.path)) end)
        else
            pcall(function()
                previewTex:SetTexture(itemData.path)
                previewTex:SetTexCoord(0, 1, 0, 1)
            end)
        end

        local scale = 1
        if texW > PREVIEW_MAX or texH > PREVIEW_MAX then
            scale = math.min(PREVIEW_MAX / texW, PREVIEW_MAX / texH)
        elseif texW < 128 and texH < 128 then
            scale = math.min(2, math.min(128 / texW, 128 / texH))
        end
        local dispW = math.floor(texW * scale)
        local dispH = math.floor(texH * scale)

        previewTex:SetSize(dispW, dispH)
        previewChecker:SetSize(dispW, dispH)

        local frameW = math.max(240, dispW + PREVIEW_PAD * 2)
        local frameH = dispH + 60 + PREVIEW_PAD
        previewPopup:SetSize(frameW, frameH)
        previewPopup:ClearAllPoints()
        previewPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        previewPath:SetText(tostring(itemData.path))
        previewSizeLabel:SetText(texW .. "x" .. texH .. (scale ~= 1 and ("  (shown at " .. math.floor(scale * 100) .. "%)") or ""))

        previewBlocker:Show()
        previewBlocker:SetFrameLevel(previewPopup:GetFrameLevel() - 1)
        previewPopup:Show()
    end

    previewPopup:SetScript("OnHide", function()
        previewBlocker:Hide()
        previewTex:SetTexture(nil)
    end)

    ---------------------------------------------------------------------------
    -- Sidebar: tab buttons + tree view
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local TAB_DEFS = {
        { id = "atlas", label = "Atlas" },
        { id = "live",  label = "Live"  },
        { id = "favs",  label = "Favs"  },
    }

    local tabBtnHeight = 20
    local tabBtnRow = CreateFrame("Frame", nil, sidebarFrame)
    tabBtnRow:SetHeight(tabBtnHeight)
    tabBtnRow:SetPoint("TOPLEFT", sidebarFrame, "TOPLEFT", 0, 0)
    tabBtnRow:SetPoint("TOPRIGHT", sidebarFrame, "TOPRIGHT", 0, 0)

    local tabButtons = {}

    local function UpdateTabHighlights()
        for _, tb in ipairs(tabButtons) do
            if tb.id == activeTab then
                tb.btn:SetBackdropColor(unpack(DF.Colors.tabActive))
            else
                tb.btn:SetBackdropColor(unpack(DF.Colors.tabInactive))
            end
        end
    end

    for i, def in ipairs(TAB_DEFS) do
        local btn = CreateFrame("Button", nil, tabBtnRow, "BackdropTemplate")
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetHeight(tabBtnHeight)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetPoint("CENTER", 0, 0)
        label:SetText(def.label)
        label:SetTextColor(0.83, 0.83, 0.83, 1)

        btn:SetScript("OnEnter", function(self)
            if def.id ~= activeTab then
                self:SetBackdropColor(unpack(DF.Colors.tabHover))
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if def.id ~= activeTab then
                self:SetBackdropColor(unpack(DF.Colors.tabInactive))
            end
        end)

        tabButtons[i] = { id = def.id, btn = btn, label = label }
    end

    tabBtnRow:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        local count = #tabButtons
        local bw = math.floor(w / count)
        for i, tb in ipairs(tabButtons) do
            tb.btn:ClearAllPoints()
            tb.btn:SetSize(bw, tabBtnHeight)
            tb.btn:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * bw, 0)
        end
    end)

    local tree = DF.Widgets:CreateTreeView(sidebarFrame)
    tree.frame:SetPoint("TOPLEFT", tabBtnRow, "BOTTOMLEFT", 0, -2)
    tree.frame:SetPoint("BOTTOMRIGHT", sidebarFrame, "BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + info + preview grid
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local sizeLabel = toolbar:CreateFontString(nil, "OVERLAY")
    sizeLabel:SetFontObject(DF.Theme:UIFont())
    sizeLabel:SetPoint("RIGHT", -4, 0)
    sizeLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    sizeLabel:SetText("Preview: 64px")

    local smallBtn = DF.Widgets:CreateButton(toolbar, "32", 36)
    smallBtn:SetPoint("RIGHT", sizeLabel, "LEFT", -6, 0)

    local medBtn = DF.Widgets:CreateButton(toolbar, "64", 36)
    medBtn:SetPoint("RIGHT", smallBtn, "LEFT", -2, 0)

    local largeBtn = DF.Widgets:CreateButton(toolbar, "128", 40)
    largeBtn:SetPoint("RIGHT", medBtn, "LEFT", -2, 0)

    local unloadBtn = DF.Widgets:CreateButton(toolbar, "Unload", 56)
    unloadBtn:SetPoint("RIGHT", largeBtn, "LEFT", -6, 0)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 46)
    copyBtn:SetPoint("RIGHT", unloadBtn, "LEFT", -2, 0)

    -- Back button (hidden until cross-module navigation)
    local backBtn = DF.Widgets:CreateButton(toolbar, "< Back", 55)
    backBtn:SetPoint("LEFT", 2, 0)
    backBtn:Hide()
    backBtn._sourceModule = nil

    local pathInput = CreateFrame("EditBox", nil, toolbar, "BackdropTemplate")
    pathInput:SetPoint("LEFT", 2, 0)
    pathInput:SetPoint("RIGHT", copyBtn, "LEFT", -8, 0)
    pathInput:SetHeight(20)
    pathInput:SetAutoFocus(false)
    pathInput:SetFontObject(DF.Theme:CodeFont())
    pathInput:SetTextColor(0.83, 0.83, 0.83, 1)
    pathInput:SetMaxLetters(500)
    DF.Theme:ApplyInputStyle(pathInput)

    local pathPlaceholder = pathInput:CreateFontString(nil, "OVERLAY")
    pathPlaceholder:SetFontObject(DF.Theme:UIFont())
    pathPlaceholder:SetPoint("LEFT", 6, 0)
    pathPlaceholder:SetText("Search textures or enter path...")
    pathPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    local function ShowBackButton(sourceModule)
        if sourceModule then
            backBtn._sourceModule = sourceModule
            local label = DF.ModuleSystem:GetTabLabel(sourceModule) or sourceModule
            backBtn:SetLabel("< " .. label)
            backBtn:Show()
            pathInput:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
        else
            backBtn:Hide()
            backBtn._sourceModule = nil
            pathInput:SetPoint("LEFT", toolbar, "LEFT", 2, 0)
        end
    end

    backBtn:SetScript("OnClick", function()
        local target = backBtn._sourceModule
        ShowBackButton(nil)
        if target then
            DF.ModuleSystem:Activate(target)
        end
    end)

    pathInput:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text and text ~= "" then
            pathPlaceholder:Hide()
        else
            pathPlaceholder:Show()
        end
    end)

    -- Info label + hide-invalid checkbox
    local infoLabel = editorFrame:CreateFontString(nil, "OVERLAY")
    infoLabel:SetFontObject(DF.Theme:UIFont())
    infoLabel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 4, -2)
    infoLabel:SetHeight(16)
    infoLabel:SetJustifyH("LEFT")
    infoLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    infoLabel:SetText("")

    local hideInvalid = true
    local hideInvalidBtn = CreateFrame("CheckButton", nil, editorFrame, "UICheckButtonTemplate")
    hideInvalidBtn:SetSize(20, 20)
    hideInvalidBtn:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -4, 0)
    hideInvalidBtn:SetChecked(true)
    local hideInvalidLabel = editorFrame:CreateFontString(nil, "OVERLAY")
    hideInvalidLabel:SetFontObject(DF.Theme:UIFont())
    hideInvalidLabel:SetPoint("RIGHT", hideInvalidBtn, "LEFT", -2, 0)
    hideInvalidLabel:SetText("Hide invalid")
    hideInvalidLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local hideInvalidInfo = CreateFrame("Button", nil, editorFrame)
    hideInvalidInfo:SetSize(16, 16)
    hideInvalidInfo:SetPoint("RIGHT", hideInvalidLabel, "LEFT", -1, 0)
    local hideInvalidInfoIcon = hideInvalidInfo:CreateTexture(nil, "OVERLAY")
    hideInvalidInfoIcon:SetSize(16, 16)
    hideInvalidInfoIcon:SetPoint("CENTER", 0, 0)
    hideInvalidInfoIcon:SetTexture(616343)
    hideInvalidInfoIcon:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    hideInvalidInfo:SetScript("OnEnter", function(self)
        hideInvalidInfoIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Hide Invalid Textures", 1, 1, 1)
        GameTooltip:AddLine("Atlas names and icon paths are sourced from known WoW data across multiple expansions. Some may not exist in your client version.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Invalid entries are shown as a red square with \"?\" when this is unchecked.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    hideInvalidInfo:SetScript("OnLeave", function()
        hideInvalidInfoIcon:SetVertexColor(0.4, 0.4, 0.4, 0.8)
        GameTooltip:Hide()
    end)
    hideInvalidBtn:SetScript("OnClick", function(self)
        hideInvalid = self:GetChecked()
        local savedNode = lastSelectedNode
        SwitchTab(activeTab)
        if savedNode then
            tree:SetSelected(savedNode.id)
            if tree.onSelect then
                tree.onSelect(savedNode)
            end
        end
    end)
    infoLabel:SetPoint("RIGHT", hideInvalidInfo, "LEFT", -4, 0)

    local previewPane = DF.Widgets:CreateScrollPane(editorFrame, true)
    previewPane.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -20)
    previewPane.frame:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Preview grid (same logic as before)
    ---------------------------------------------------------------------------
    local function GetPreviewItem(index)
        if previewItems[index] then
            previewItems[index].frame:Show()
            return previewItems[index]
        end

        local item = {}
        item.frame = CreateFrame("Button", nil, previewPane:GetContent())
        item.frame:SetSize(previewSize + 8, previewSize + 24)
        item.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local bg = item.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.12, 0.8)
        item.bg = bg

        local checker = item.frame:CreateTexture(nil, "BORDER")
        checker:SetPoint("TOP", 0, -2)
        checker:SetSize(previewSize, previewSize)
        checker:SetColorTexture(0.2, 0.2, 0.2, 1)
        item.checker = checker

        local tex = item.frame:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOP", 0, -2)
        tex:SetSize(previewSize, previewSize)
        item.tex = tex

        local invalidOverlay = item.frame:CreateTexture(nil, "ARTWORK", nil, 1)
        invalidOverlay:SetPoint("TOP", 0, -2)
        invalidOverlay:SetSize(previewSize, previewSize)
        invalidOverlay:SetColorTexture(0.4, 0.1, 0.1, 0.5)
        invalidOverlay:Hide()
        item.invalidOverlay = invalidOverlay

        local invalidLabel = item.frame:CreateFontString(nil, "OVERLAY")
        invalidLabel:SetFontObject(DF.Theme:UIFont())
        invalidLabel:SetPoint("CENTER", item.tex, "CENTER", 0, 0)
        invalidLabel:SetText("?")
        invalidLabel:SetTextColor(1, 0.3, 0.3, 1)
        invalidLabel:Hide()
        item.invalidLabel = invalidLabel

        local name = item.frame:CreateFontString(nil, "OVERLAY")
        name:SetFontObject(DF.Theme:UIFont())
        name:SetPoint("BOTTOM", 0, 2)
        name:SetWidth(previewSize + 4)
        name:SetWordWrap(false)
        name:SetTextColor(0.7, 0.7, 0.7, 1)
        item.name = name

        local hl = item.frame:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.2)
        item.hl = hl

        -- Favorite star
        local star = CreateFrame("Button", nil, item.frame)
        star:RegisterForClicks("LeftButtonUp")
        star:SetSize(14, 14)
        star:SetPoint("TOPRIGHT", item.frame, "TOPRIGHT", -1, -1)
        star:SetFrameLevel(item.frame:GetFrameLevel() + 2)
        local starTex = star:CreateTexture(nil, "OVERLAY")
        starTex:SetAllPoints()
        starTex:SetAtlas("auctionhouse-icon-favorite")
        starTex:SetDesaturated(true)
        starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
        star.tex = starTex
        star:SetScript("OnEnter", function(self) self.tex:SetVertexColor(1, 0.85, 0, 1) end)
        star:SetScript("OnLeave", function(self)
            if item.path and DF.TextureIndex:IsFavorite(item.path) then
                self.tex:SetDesaturated(false)
                self.tex:SetVertexColor(1, 0.85, 0, 1)
            else
                self.tex:SetDesaturated(true)
                self.tex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
            end
        end)
        star:SetScript("OnClick", function()
            if not item.path then return end
            if DF.TextureIndex:IsFavorite(item.path) then
                DF.TextureIndex:RemoveFavorite(item.path)
                starTex:SetDesaturated(true)
                starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
            else
                DF.TextureIndex:AddFavorite({
                    path = item.path,
                    name = item.displayName or item.path,
                    isAtlas = item.isAtlas or false,
                })
                starTex:SetDesaturated(false)
                starTex:SetVertexColor(1, 0.85, 0, 1)
            end
        end)
        item.star = star
        item.starTex = starTex

        item.frame:SetScript("OnClick", function(self, button)
            if not item.path then return end
            if button == "RightButton" then
                ShowContextMenu(item)
            else
                pathInput:SetText(tostring(item.path))
                pathInput:SetFocus()
                pathInput:HighlightText()
                DF.TextureIndex:AddRecent({
                    path = item.path,
                    name = item.displayName or tostring(item.path),
                    isAtlas = item.isAtlas or false,
                })
            end
        end)

        item.frame:SetScript("OnEnter", function(self)
            if not item.path then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(tostring(item.path), 1, 1, 1, 1, true)
            if item.isAtlas then
                local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tostring(item.path))
                if info then
                    GameTooltip:AddLine("Atlas: " .. (info.filename or "?"), 0.6, 0.8, 1)
                    GameTooltip:AddLine(string.format("Size: %dx%d", info.width or 0, info.height or 0), 0.6, 0.8, 1)
                end
            end
            if item.source then
                GameTooltip:AddLine("Source: " .. item.source, 0.5, 0.7, 0.5)
            end
            GameTooltip:AddLine("Left-click to select", 0.5, 0.8, 1)
            GameTooltip:AddLine("Right-click for options", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        item.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        previewItems[index] = item
        return item
    end

    local function HideAllPreviews()
        for _, item in ipairs(previewItems) do item.frame:Hide() end
    end

    local function UpdateStarState(item)
        if item.path and DF.TextureIndex:IsFavorite(item.path) then
            item.starTex:SetDesaturated(false)
            item.starTex:SetVertexColor(1, 0.85, 0, 1)
        else
            item.starTex:SetDesaturated(true)
            item.starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
        end
    end

    ShowTextures = function(results)
        HideAllPreviews()
        currentResults = results
        local totalCount = #results
        local displayCount = math.min(totalCount, MAX_GRID_ITEMS)
        local contentW = previewPane:GetContent():GetWidth()
        if contentW < 1 then contentW = previewPane.scrollFrame:GetWidth() end
        local itemW = previewSize + 12
        local cols = math.max(1, math.floor(contentW / itemW))
        local row, col = 0, 0

        for i = 1, displayCount do
            local result = results[i]
            local item = GetPreviewItem(i)
            item.tex:SetSize(previewSize, previewSize)
            item.checker:SetSize(previewSize, previewSize)
            item.invalidOverlay:SetSize(previewSize, previewSize)
            item.frame:SetSize(previewSize + 8, previewSize + 24)
            item.name:SetWidth(previewSize + 4)
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", previewPane:GetContent(), "TOPLEFT",
                col * itemW + 4, -(row * (previewSize + 28) + 4))
            item.invalidOverlay:Hide()
            item.invalidLabel:Hide()
            item.path = result.path
            item.displayName = result.name
            item.isAtlas = result.isAtlas
            item.source = result.source
            item.tex:SetTexture(nil)
            item.tex:SetTexCoord(0, 1, 0, 1)

            if result.isAtlas then
                local ok = pcall(function() item.tex:SetAtlas(result.path) end)
                if not ok then
                    item.tex:SetColorTexture(0.15, 0.15, 0.17, 1)
                    item.invalidOverlay:Show()
                    item.invalidLabel:Show()
                else
                    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(result.path)
                    if not info then
                        item.invalidOverlay:Show()
                        item.invalidLabel:Show()
                    end
                end
            else
                local ok = pcall(function()
                    item.tex:SetTexture(result.path)
                    item.tex:SetTexCoord(0, 1, 0, 1)
                end)
                if not ok then
                    item.tex:SetColorTexture(0.15, 0.15, 0.17, 1)
                    item.invalidOverlay:Show()
                    item.invalidLabel:Show()
                end
            end

            item.name:SetText(result.name or "?")
            UpdateStarState(item)
            col = col + 1
            if col >= cols then col = 0; row = row + 1 end
        end

        local totalRows = math.ceil(displayCount / math.max(1, cols))
        previewPane:SetContentHeight(totalRows * (previewSize + 28) + 8)
        previewPane:ScrollToTop()

        if totalCount > displayCount then
            infoLabel:SetText(displayCount .. " of " .. totalCount .. " textures (search to narrow)")
        else
            infoLabel:SetText(totalCount .. " textures")
        end
    end

    ---------------------------------------------------------------------------
    -- Context menu (with INSERT_TO_EDITOR integration)
    ---------------------------------------------------------------------------
    ShowContextMenu = function(item)
        if not contextMenu then contextMenu = DF.Widgets:CreateDropDown() end
        local items = {}

        items[#items + 1] = {
            text = "Copy Path",
            func = function() DF.Widgets:ShowCopyDialog(tostring(item.path)) end,
        }

        if not item.isAtlas then
            local code
            if type(item.path) == "number" then
                code = "texture:SetTexture(" .. item.path .. ")"
            else
                code = "texture:SetTexture(\"" .. tostring(item.path) .. "\")"
            end
            items[#items + 1] = {
                text = "Copy SetTexture Code",
                func = function() DF.Widgets:ShowCopyDialog(code) end,
            }
            items[#items + 1] = {
                text = "Insert SetTexture Code",
                func = function()
                    DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
                end,
            }
        end

        if item.isAtlas then
            local code = "texture:SetAtlas(\"" .. tostring(item.path) .. "\")"
            items[#items + 1] = {
                text = "Copy SetAtlas Code",
                func = function() DF.Widgets:ShowCopyDialog(code) end,
            }
            items[#items + 1] = {
                text = "Insert SetAtlas Code",
                func = function()
                    DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
                end,
            }
        end

        items[#items + 1] = { isSeparator = true }
        items[#items + 1] = {
            text = "Preview Full Size",
            func = function()
                ShowPreviewPopup({ path = item.path, name = item.displayName, isAtlas = item.isAtlas })
            end,
        }
        items[#items + 1] = { isSeparator = true }

        if DF.TextureIndex:IsFavorite(item.path) then
            items[#items + 1] = {
                text = "Remove from Favorites",
                func = function()
                    DF.TextureIndex:RemoveFavorite(item.path)
                    UpdateStarState(item)
                end,
            }
        else
            items[#items + 1] = {
                text = "Add to Favorites",
                func = function()
                    DF.TextureIndex:AddFavorite({
                        path = item.path, name = item.displayName or tostring(item.path), isAtlas = item.isAtlas or false,
                    })
                    UpdateStarState(item)
                end,
            }
        end

        contextMenu:Show(nil, items)
    end

    ---------------------------------------------------------------------------
    -- Unload
    ---------------------------------------------------------------------------
    local atlasValidCache = {}
    local function UnloadTextures()
        for _, item in ipairs(previewItems) do
            pcall(function() item.tex:SetTexture(nil) end)
            item.frame:Hide()
        end
        currentResults = {}
        wipe(atlasValidCache)
        infoLabel:SetText("Textures unloaded - select a category to browse")
    end

    ---------------------------------------------------------------------------
    -- Tree builders
    ---------------------------------------------------------------------------
    local function IsAtlasValid(name)
        local cached = atlasValidCache[name]
        if cached ~= nil then return cached end
        local ok = pcall(function() testValidTex:SetAtlas(name) end)
        testValidTex:SetTexture(nil)
        if not ok then atlasValidCache[name] = false; return false end
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        local valid = info ~= nil
        atlasValidCache[name] = valid
        return valid
    end

    local function BuildAtlasTree()
        local categories = DF.TextureAtlasData:GetCategories()
        local nodes = {}
        for _, cat in ipairs(categories) do
            local count
            if hideInvalid then
                count = 0
                for _, atlasName in ipairs(DF.TextureAtlasData:GetAtlases(cat.id)) do
                    if IsAtlasValid(atlasName) then count = count + 1 end
                end
            else
                count = #DF.TextureAtlasData:GetAtlases(cat.id)
            end
            nodes[#nodes + 1] = {
                id = "atlascat_" .. cat.id,
                text = cat.name .. " (" .. count .. ")",
                data = { categoryType = "atlas", categoryId = cat.id },
            }
        end
        return nodes
    end

    local function BuildLiveTree()
        local nodes = {}
        nodes[1] = {
            id = "live_scan",
            text = DF.TextureRuntime:IsScanning() and "Scanning..." or "Scan Loaded Frames",
            data = { categoryType = "live_scan" },
        }
        local runtimeResults = DF.TextureRuntime:GetResults()
        if #runtimeResults > 0 then
            local bySource = {}
            local sourceOrder = {}
            for _, item in ipairs(runtimeResults) do
                local src = item.source or "Unknown"
                if not bySource[src] then
                    bySource[src] = 0
                    sourceOrder[#sourceOrder + 1] = src
                end
                bySource[src] = bySource[src] + 1
            end
            for _, src in ipairs(sourceOrder) do
                nodes[#nodes + 1] = {
                    id = "rtsrc_" .. src,
                    text = src .. " (" .. bySource[src] .. ")",
                    data = { categoryType = "live_source", sourceName = src },
                }
            end
        end
        return nodes
    end

    local function BuildFavsTree()
        local favs = DF.TextureIndex:GetFavorites()
        local recent = DF.TextureIndex:GetRecent()
        return {
            { id = "favorites_root", text = "Favorites (" .. #favs .. ")", data = { categoryType = "favorites" } },
            { id = "recent_root",    text = "Recent (" .. #recent .. ")",  data = { categoryType = "recent" } },
        }
    end

    ---------------------------------------------------------------------------
    -- Tab switching
    ---------------------------------------------------------------------------
    SwitchTab = function(tabId)
        activeTab = tabId
        UpdateTabHighlights()
        local nodes
        if tabId == "atlas" then nodes = BuildAtlasTree()
        elseif tabId == "live" then nodes = BuildLiveTree()
        elseif tabId == "favs" then nodes = BuildFavsTree()
        end
        tree:SetNodes(nodes or {})
        HideAllPreviews()
        currentResults = {}
        infoLabel:SetText("")
    end

    for _, tb in ipairs(tabButtons) do
        tb.btn:SetScript("OnClick", function() SwitchTab(tb.id) end)
    end

    ---------------------------------------------------------------------------
    -- Tree selection handler (same logic as original)
    ---------------------------------------------------------------------------
    tree:SetOnSelect(function(node)
        if not node or not node.data then return end
        lastSelectedNode = node
        local d = node.data

        if d.path then
            ShowTextures({ d })
            pathInput:SetText(tostring(d.path))
            DF.TextureIndex:AddRecent({ path = d.path, name = d.name or tostring(d.path), isAtlas = d.isAtlas or false })
            return
        end

        if d.categoryType == "atlas" and d.categoryId then
            local atlases = DF.TextureAtlasData:GetAtlases(d.categoryId)
            local results = {}
            for _, name in ipairs(atlases) do
                if not hideInvalid or IsAtlasValid(name) then
                    results[#results + 1] = { path = name, name = name, isAtlas = true }
                end
            end
            ShowTextures(results)
            return
        end

        if d.categoryType == "live_scan" then
            if DF.TextureRuntime:IsScanning() then
                DF.TextureRuntime:Cancel()
                infoLabel:SetText("Scan cancelled")
                C_Timer.After(0, function()
                    if activeTab == "live" then tree:SetNodes(BuildLiveTree()) end
                end)
            else
                infoLabel:SetText("Scanning frames...")
                DF.TextureRuntime:Scan(
                    function(current, total)
                        infoLabel:SetText("Scanning... " .. current .. "/" .. total .. " frames")
                    end,
                    function(runtimeResults, count)
                        infoLabel:SetText("Scan complete: " .. count .. " unique textures found")
                        if activeTab == "live" then tree:SetNodes(BuildLiveTree()) end
                        local gridResults = {}
                        for _, item in ipairs(runtimeResults) do
                            gridResults[#gridResults + 1] = { path = item.path, name = item.name, isAtlas = item.isAtlas, source = item.source }
                        end
                        ShowTextures(gridResults)
                    end
                )
                C_Timer.After(0, function()
                    if activeTab == "live" then tree:SetNodes(BuildLiveTree()) end
                end)
            end
            return
        end

        if d.categoryType == "live_source" and d.sourceName then
            local runtimeResults = DF.TextureRuntime:GetResults()
            local results = {}
            for _, item in ipairs(runtimeResults) do
                if item.source == d.sourceName then
                    results[#results + 1] = { path = item.path, name = item.name, isAtlas = item.isAtlas, source = item.source }
                end
            end
            ShowTextures(results)
            return
        end

        if d.categoryType == "favorites" then
            local favs = DF.TextureIndex:GetFavorites()
            local results = {}
            for _, fav in ipairs(favs) do
                results[#results + 1] = { path = fav.path, name = fav.name, isAtlas = fav.isAtlas }
            end
            ShowTextures(results)
            return
        end

        if d.categoryType == "recent" then
            local recent = DF.TextureIndex:GetRecent()
            local results = {}
            for _, rec in ipairs(recent) do
                results[#results + 1] = { path = rec.path, name = rec.name, isAtlas = rec.isAtlas }
            end
            ShowTextures(results)
            return
        end
    end)

    ---------------------------------------------------------------------------
    -- Path input
    ---------------------------------------------------------------------------
    pathInput:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            if text:find("\\") or text:find("/") or tonumber(text) then
                local path = tonumber(text) or text
                local name = type(path) == "number" and ("FileID:" .. path) or (text:match("([^\\]+)$") or text)
                ShowTextures({ { path = path, name = name, isAtlas = false } })
            else
                local results = DF.TextureIndex:Search(text)
                ShowTextures(results)
                infoLabel:SetText(#results .. " search results for \"" .. text .. "\"")
            end
        end
        self:ClearFocus()
    end)
    pathInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    copyBtn:SetScript("OnClick", function()
        local text = pathInput:GetText()
        if text and text ~= "" then DF.Widgets:ShowCopyDialog(text) end
    end)

    unloadBtn:SetScript("OnClick", function() UnloadTextures() end)

    local function SetPreviewSize(size)
        previewSize = size
        sizeLabel:SetText("Preview: " .. size .. "px")
        if #currentResults > 0 then ShowTextures(currentResults) end
    end

    smallBtn:SetScript("OnClick", function() SetPreviewSize(32) end)
    medBtn:SetScript("OnClick", function() SetPreviewSize(64) end)
    largeBtn:SetScript("OnClick", function() SetPreviewSize(128) end)

    previewPane.frame:SetScript("OnSizeChanged", function()
        previewPane:GetContent():SetWidth(previewPane.scrollFrame:GetWidth())
        if #currentResults > 0 then ShowTextures(currentResults) end
    end)

    SwitchTab("atlas")

    ---------------------------------------------------------------------------
    -- Cross-module navigation: show a specific texture
    ---------------------------------------------------------------------------
    function browser:ShowTexture(path, isAtlas, sourceModule)
        if not path then return end
        ShowBackButton(sourceModule)
        pathInput:SetText(tostring(path))
        if isAtlas then
            local name = tostring(path)
            ShowTextures({ { path = tostring(path), name = name, isAtlas = true } })
            infoLabel:SetText("Atlas: " .. name)
        else
            local displayName
            if type(path) == "number" then
                displayName = "FileID:" .. path
            else
                displayName = tostring(path):match("([^\\]+)$") or tostring(path)
            end
            ShowTextures({ { path = path, name = displayName, isAtlas = false } })
            infoLabel:SetText("Texture: " .. displayName)
        end
    end

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function browser:OnActivate()
        if unloadTimer then unloadTimer:Cancel(); unloadTimer = nil end
    end

    function browser:OnDeactivate()
        ShowBackButton(nil)
        unloadTimer = C_Timer.After(30, function()
            unloadTimer = nil
            UnloadTextures()
        end)
    end

    browser.sidebar = sidebarFrame
    browser.editor = editorFrame
    return browser
end, "Textures")

-- Cross-module event: navigate to TextureBrowser with a specific texture.
-- Registered at file-load time so it works even before the module is first opened.
DF.EventBus:On("DF_SHOW_IN_TEXTURE_BROWSER", function(data)
    if not data or not data.path then return end
    -- Remember where we came from so the back button can return
    local sourceModule = DF.ModuleSystem:GetActive()
    -- Activate creates the module instance if it doesn't exist yet
    DF.ModuleSystem:Activate("TextureBrowser")
    local instance = DF.ModuleSystem:GetInstance("TextureBrowser")
    if instance and instance.ShowTexture then
        instance:ShowTexture(data.path, data.isAtlas, sourceModule)
    end
end)
