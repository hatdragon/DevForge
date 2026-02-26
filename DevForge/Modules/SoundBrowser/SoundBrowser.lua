local _, DF = ...

-- Register the Sound Browser module with sidebar + editor split
DF.ModuleSystem:Register("SoundBrowser", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local browser = {}

    ---------------------------------------------------------------------------
    -- State
    ---------------------------------------------------------------------------
    local activeTab = "kits"
    local currentResults = {}
    local lastSelectedNode = nil
    local listItems = {}
    local MAX_LIST_ITEMS = 500
    local ROW_HEIGHT = 28
    local unloadTimer = nil
    local contextMenu = nil
    local ShowContextMenu
    local ShowSounds
    local SwitchTab

    -- Sound playback state: only one sound at a time
    local activeHandle = nil
    local activeItemIndex = nil

    local function StopActiveSound()
        if pollTicker then pollTicker:Cancel(); pollTicker = nil end
        if activeHandle then
            if activeHandle == "music" then
                pcall(StopMusic)
            else
                pcall(StopSound, activeHandle, 0)
            end
            activeHandle = nil
        end
        if activeItemIndex and listItems[activeItemIndex] then
            listItems[activeItemIndex].playIcon:SetAtlas("common-dropdown-icon-play")
            listItems[activeItemIndex].playIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
        end
        activeItemIndex = nil
    end

    -- Poll C_Sound.IsPlaying to auto-reset play button when sound ends
    local pollTicker = nil
    local function StartPlayPoll()
        if pollTicker then return end
        pollTicker = C_Timer.NewTicker(0.3, function()
            if not activeHandle then
                if pollTicker then pollTicker:Cancel(); pollTicker = nil end
                return
            end
            if activeHandle == "music" then return end
            local stillPlaying = C_Sound and C_Sound.IsPlaying and C_Sound.IsPlaying(activeHandle)
            if not stillPlaying then
                if activeItemIndex and listItems[activeItemIndex] then
                    listItems[activeItemIndex].playIcon:SetAtlas("common-dropdown-icon-play")
                    listItems[activeItemIndex].playIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
                end
                activeHandle = nil
                activeItemIndex = nil
                pollTicker:Cancel()
                pollTicker = nil
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Sidebar: tab buttons + tree view
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local TAB_DEFS = {
        { id = "kits",   label = "Kits"   },
        { id = "fileid", label = "FileID"  },
        { id = "live",   label = "Live"   },
        { id = "favs",   label = "Favs"   },
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
    -- Editor: toolbar + info + scrollable list
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local stopAllBtn = DF.Widgets:CreateButton(toolbar, "Stop All", 60)
    stopAllBtn:SetPoint("RIGHT", -4, 0)
    stopAllBtn:SetScript("OnClick", function() StopActiveSound() end)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 46)
    copyBtn:SetPoint("RIGHT", stopAllBtn, "LEFT", -2, 0)

    -- Back button (hidden until cross-module navigation)
    local backBtn = DF.Widgets:CreateButton(toolbar, "< Back", 55)
    backBtn:SetPoint("LEFT", 2, 0)
    backBtn:Hide()
    backBtn._sourceModule = nil

    local searchInput = CreateFrame("EditBox", nil, toolbar, "BackdropTemplate")
    searchInput:SetPoint("LEFT", 2, 0)
    searchInput:SetPoint("RIGHT", copyBtn, "LEFT", -8, 0)
    searchInput:SetHeight(20)
    searchInput:SetAutoFocus(false)
    searchInput:SetFontObject(DF.Theme:CodeFont())
    searchInput:SetTextColor(0.83, 0.83, 0.83, 1)
    searchInput:SetMaxLetters(200)
    DF.Theme:ApplyInputStyle(searchInput)

    local searchPlaceholder = searchInput:CreateFontString(nil, "OVERLAY")
    searchPlaceholder:SetFontObject(DF.Theme:UIFont())
    searchPlaceholder:SetPoint("LEFT", 6, 0)
    searchPlaceholder:SetText("Search sounds by name or ID...")
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    local function ShowBackButton(sourceModule)
        if sourceModule then
            backBtn._sourceModule = sourceModule
            local label = DF.ModuleSystem:GetTabLabel(sourceModule) or sourceModule
            backBtn:SetLabel("< " .. label)
            backBtn:Show()
            searchInput:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
        else
            backBtn:Hide()
            backBtn._sourceModule = nil
            searchInput:SetPoint("LEFT", toolbar, "LEFT", 2, 0)
        end
    end

    backBtn:SetScript("OnClick", function()
        local target = backBtn._sourceModule
        ShowBackButton(nil)
        if target then
            DF.ModuleSystem:Activate(target)
        end
    end)

    searchInput:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text and text ~= "" then
            searchPlaceholder:Hide()
        else
            searchPlaceholder:Show()
        end
    end)

    -- Info label
    local infoLabel = editorFrame:CreateFontString(nil, "OVERLAY")
    infoLabel:SetFontObject(DF.Theme:UIFont())
    infoLabel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 4, -2)
    infoLabel:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -4, -2)
    infoLabel:SetHeight(16)
    infoLabel:SetJustifyH("LEFT")
    infoLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    infoLabel:SetText("")

    local listPane = DF.Widgets:CreateScrollPane(editorFrame, true)
    listPane.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -20)
    listPane.frame:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- List item pool
    ---------------------------------------------------------------------------
    local function GetListItem(index)
        if listItems[index] then
            listItems[index].frame:Show()
            return listItems[index]
        end

        local item = {}
        item.frame = CreateFrame("Button", nil, listPane:GetContent())
        item.frame:SetHeight(ROW_HEIGHT)
        item.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Alternating row background
        local bg = item.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.12, (index % 2 == 0) and 0.6 or 0.3)
        item.bg = bg

        -- Play/Stop button
        local playBtn = CreateFrame("Button", nil, item.frame)
        playBtn:RegisterForClicks("LeftButtonUp")
        playBtn:SetSize(20, 20)
        playBtn:SetPoint("LEFT", 6, 0)
        local playIcon = playBtn:CreateTexture(nil, "OVERLAY")
        playIcon:SetAllPoints()
        playIcon:SetAtlas("common-dropdown-icon-play")
        playIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
        item.playBtn = playBtn
        item.playIcon = playIcon

        playBtn:SetScript("OnEnter", function() playIcon:SetVertexColor(1, 1, 1, 1) end)
        playBtn:SetScript("OnLeave", function()
            if activeItemIndex == index then
                playIcon:SetVertexColor(0.3, 1, 0.3, 1)
            else
                playIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
            end
        end)

        playBtn:SetScript("OnClick", function()
            if activeItemIndex == index then
                StopActiveSound()
                return
            end
            StopActiveSound()
            if not item.soundId then return end
            local willPlay, handle
            if item.sourceType == "music" then
                PlayMusic(tostring(item.soundId))
                willPlay, handle = true, "music"
            elseif item.sourceType == "file" then
                willPlay, handle = PlaySoundFile(item.soundId, "Master")
            else
                willPlay, handle = PlaySound(item.soundId, "Master")
            end
            if willPlay and handle then
                activeHandle = handle
                activeItemIndex = index
                playIcon:SetAtlas("common-dropdown-icon-stop")
                playIcon:SetVertexColor(0.3, 1, 0.3, 1)
                StartPlayPoll()
                -- Add to recent
                DF.SoundIndex:AddRecent({
                    id = item.soundId,
                    name = item.displayName or tostring(item.soundId),
                    sourceType = item.sourceType or "kit",
                })
            end
        end)

        -- Sound name/ID label
        local nameLabel = item.frame:CreateFontString(nil, "OVERLAY")
        nameLabel:SetFontObject(DF.Theme:CodeFont())
        nameLabel:SetPoint("LEFT", playBtn, "RIGHT", 8, 0)
        nameLabel:SetPoint("RIGHT", item.frame, "RIGHT", -30, 0)
        nameLabel:SetJustifyH("LEFT")
        nameLabel:SetWordWrap(false)
        nameLabel:SetTextColor(0.83, 0.83, 0.83, 1)
        item.nameLabel = nameLabel

        -- Highlight
        local hl = item.frame:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.2)

        -- Favorite star
        local star = CreateFrame("Button", nil, item.frame)
        star:RegisterForClicks("LeftButtonUp")
        star:SetSize(14, 14)
        star:SetPoint("RIGHT", item.frame, "RIGHT", -8, 0)
        star:SetFrameLevel(item.frame:GetFrameLevel() + 2)
        local starTex = star:CreateTexture(nil, "OVERLAY")
        starTex:SetAllPoints()
        starTex:SetAtlas("auctionhouse-icon-favorite")
        starTex:SetDesaturated(true)
        starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
        star.tex = starTex
        item.star = star
        item.starTex = starTex

        star:SetScript("OnEnter", function(self) self.tex:SetVertexColor(1, 0.85, 0, 1) end)
        star:SetScript("OnLeave", function(self)
            if item.soundId and DF.SoundIndex:IsFavorite(item.soundId, item.sourceType) then
                self.tex:SetDesaturated(false)
                self.tex:SetVertexColor(1, 0.85, 0, 1)
            else
                self.tex:SetDesaturated(true)
                self.tex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
            end
        end)
        star:SetScript("OnClick", function()
            if not item.soundId then return end
            if DF.SoundIndex:IsFavorite(item.soundId, item.sourceType) then
                DF.SoundIndex:RemoveFavorite(item.soundId, item.sourceType)
                starTex:SetDesaturated(true)
                starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
            else
                DF.SoundIndex:AddFavorite({
                    id = item.soundId,
                    name = item.displayName or tostring(item.soundId),
                    sourceType = item.sourceType or "kit",
                })
                starTex:SetDesaturated(false)
                starTex:SetVertexColor(1, 0.85, 0, 1)
            end
        end)

        -- Row click
        item.frame:SetScript("OnClick", function(self, button)
            if not item.soundId then return end
            if button == "RightButton" then
                ShowContextMenu(item)
            else
                searchInput:SetText(tostring(item.soundId))
                searchInput:SetFocus()
                searchInput:HighlightText()
            end
        end)

        item.frame:SetScript("OnEnter", function(self)
            if not item.soundId then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            if item.sourceType == "file" then
                GameTooltip:SetText("FileID: " .. tostring(item.soundId), 1, 1, 1)
            else
                GameTooltip:SetText("SoundKit: " .. tostring(item.soundId), 1, 1, 1)
            end
            if item.displayName then
                GameTooltip:AddLine(item.displayName, 0.6, 0.8, 1)
            end
            GameTooltip:AddLine("Left-click to select  |  Right-click for options", 0.5, 0.8, 1)
            GameTooltip:AddLine("Play button to preview", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        item.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        listItems[index] = item
        return item
    end

    local function HideAllListItems()
        for _, item in ipairs(listItems) do item.frame:Hide() end
    end

    local function UpdateStarState(item)
        if item.soundId and DF.SoundIndex:IsFavorite(item.soundId, item.sourceType) then
            item.starTex:SetDesaturated(false)
            item.starTex:SetVertexColor(1, 0.85, 0, 1)
        else
            item.starTex:SetDesaturated(true)
            item.starTex:SetVertexColor(0.6, 0.6, 0.6, 0.7)
        end
    end

    ---------------------------------------------------------------------------
    -- Show sounds in the list
    ---------------------------------------------------------------------------
    ShowSounds = function(results)
        HideAllListItems()
        StopActiveSound()
        currentResults = results
        local totalCount = #results
        local displayCount = math.min(totalCount, MAX_LIST_ITEMS)
        local contentW = listPane:GetContent():GetWidth()
        if contentW < 1 then contentW = listPane.scrollFrame:GetWidth() end

        for i = 1, displayCount do
            local result = results[i]
            local item = GetListItem(i)
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", listPane:GetContent(), "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
            item.frame:SetPoint("RIGHT", listPane:GetContent(), "RIGHT", 0, 0)

            item.soundId = result.id
            item.displayName = result.name
            item.sourceType = result.sourceType or "kit"

            -- Format display text
            local label
            if item.sourceType == "file" then
                label = "FileID:" .. tostring(result.id)
                if result.name and result.name ~= ("FileID:" .. tostring(result.id)) then
                    label = result.name .. "  |  " .. label
                end
            else
                label = tostring(result.id) .. "  —  " .. (result.name or "?")
            end
            item.nameLabel:SetText(label)

            -- Reset play icon
            item.playIcon:SetAtlas("common-dropdown-icon-play")
            item.playIcon:SetVertexColor(0.7, 0.7, 0.7, 1)

            -- Update alternating background
            item.bg:SetColorTexture(0.1, 0.1, 0.12, (i % 2 == 0) and 0.6 or 0.3)

            UpdateStarState(item)
        end

        listPane:SetContentHeight(displayCount * ROW_HEIGHT + 4)
        listPane:ScrollToTop()

        if totalCount > displayCount then
            infoLabel:SetText(displayCount .. " of " .. totalCount .. " sounds (search to narrow)")
        else
            infoLabel:SetText(totalCount .. " sounds")
        end
    end

    ---------------------------------------------------------------------------
    -- Context menu
    ---------------------------------------------------------------------------
    ShowContextMenu = function(item)
        if not contextMenu then contextMenu = DF.Widgets:CreateDropDown() end
        local items = {}

        items[#items + 1] = {
            text = "Copy ID",
            func = function() DF.Widgets:ShowCopyDialog(tostring(item.soundId)) end,
        }

        if item.sourceType == "music" then
            local code = 'PlayMusic("' .. tostring(item.soundId) .. '")'
            items[#items + 1] = {
                text = "Copy PlayMusic Code",
                func = function() DF.Widgets:ShowCopyDialog(code) end,
            }
            items[#items + 1] = {
                text = "Insert PlayMusic Code",
                func = function()
                    DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
                end,
            }
        elseif item.sourceType == "file" then
            local code = "PlaySoundFile(" .. tostring(item.soundId) .. ', "Master")'
            items[#items + 1] = {
                text = "Copy PlaySoundFile Code",
                func = function() DF.Widgets:ShowCopyDialog(code) end,
            }
            items[#items + 1] = {
                text = "Insert PlaySoundFile Code",
                func = function()
                    DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
                end,
            }
        else
            local code = "PlaySound(" .. tostring(item.soundId) .. ', "Master")'
            items[#items + 1] = {
                text = "Copy PlaySound Code",
                func = function() DF.Widgets:ShowCopyDialog(code) end,
            }
            items[#items + 1] = {
                text = "Insert PlaySound Code",
                func = function()
                    DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
                end,
            }
        end

        items[#items + 1] = { isSeparator = true }

        if DF.SoundIndex:IsFavorite(item.soundId, item.sourceType) then
            items[#items + 1] = {
                text = "Remove from Favorites",
                func = function()
                    DF.SoundIndex:RemoveFavorite(item.soundId, item.sourceType)
                    UpdateStarState(item)
                end,
            }
        else
            items[#items + 1] = {
                text = "Add to Favorites",
                func = function()
                    DF.SoundIndex:AddFavorite({
                        id = item.soundId,
                        name = item.displayName or tostring(item.soundId),
                        sourceType = item.sourceType or "kit",
                    })
                    UpdateStarState(item)
                end,
            }
        end

        contextMenu:Show(nil, items)
    end

    ---------------------------------------------------------------------------
    -- Tree builders
    ---------------------------------------------------------------------------
    local function BuildKitsTree()
        local categories = DF.SoundKitData:GetCategories()
        local nodes = {}
        for _, cat in ipairs(categories) do
            local sounds = DF.SoundKitData:GetSounds(cat.id)
            nodes[#nodes + 1] = {
                id = "kitcat_" .. cat.id,
                text = cat.name .. " (" .. #sounds .. ")",
                data = { categoryType = "soundkit", categoryId = cat.id },
            }
        end
        return nodes
    end

    -- FileID range explorer state
    local fileidStart = 1
    local FILEID_PAGE_SIZE = DF.SoundFileData:GetDefaultRangeSize()

    local function BuildFileIdTree()
        return {
            { id = "fileid_browse", text = "Browse from " .. fileidStart, data = { categoryType = "fileid_browse" } },
            { id = "fileid_prev",   text = "< Previous " .. FILEID_PAGE_SIZE, data = { categoryType = "fileid_prev" } },
            { id = "fileid_next",   text = "Next " .. FILEID_PAGE_SIZE .. " >", data = { categoryType = "fileid_next" } },
        }
    end

    local fileidScanTicker = nil

    local function CancelFileIdScan()
        if fileidScanTicker then fileidScanTicker:Cancel(); fileidScanTicker = nil end
    end

    local function LoadFileIdPage()
        CancelFileIdScan()
        HideAllListItems()
        currentResults = {}
        local rangeEnd = fileidStart + FILEID_PAGE_SIZE - 1
        infoLabel:SetText("Scanning FileID " .. fileidStart .. " - " .. rangeEnd .. " ...")
        if activeTab == "fileid" then tree:SetNodes(BuildFileIdTree()) end

        local results = {}
        local current = fileidStart
        local BATCH = 50

        fileidScanTicker = C_Timer.NewTicker(0, function(ticker)
            if current > rangeEnd then
                ticker:Cancel()
                fileidScanTicker = nil
                ShowSounds(results)
                infoLabel:SetText("FileID " .. fileidStart .. " - " .. rangeEnd .. "  |  " .. #results .. " playable")
                return
            end

            local batchEnd = math.min(current + BATCH - 1, rangeEnd)
            for fileId = current, batchEnd do
                local willPlay, handle = PlaySoundFile(fileId, "Master")
                if willPlay and handle then
                    pcall(StopSound, handle, 0)
                    results[#results + 1] = {
                        id = fileId,
                        name = "FileID:" .. fileId,
                        sourceType = "file",
                    }
                end
            end
            current = batchEnd + 1
            infoLabel:SetText("Scanning FileID " .. fileidStart .. " - " .. rangeEnd .. "  |  " .. (current - fileidStart) .. "/" .. FILEID_PAGE_SIZE .. " checked, " .. #results .. " found")
        end)
    end

    local function BuildLiveTree()
        local nodes = {}
        local isListening = DF.SoundRuntime:IsListening()
        nodes[1] = {
            id = "live_toggle",
            text = isListening and "Stop Listening" or "Start Listening",
            data = { categoryType = "live_toggle" },
        }
        local runtimeResults = DF.SoundRuntime:GetResults()
        if #runtimeResults > 0 then
            nodes[#nodes + 1] = {
                id = "live_all",
                text = "All Captured (" .. #runtimeResults .. ")",
                data = { categoryType = "live_all" },
            }
            -- Group by source type
            local kitCount, fileCount, musicCount = 0, 0, 0
            for _, item in ipairs(runtimeResults) do
                if item.sourceType == "music" then
                    musicCount = musicCount + 1
                elseif item.sourceType == "file" then
                    fileCount = fileCount + 1
                else
                    kitCount = kitCount + 1
                end
            end
            if kitCount > 0 then
                nodes[#nodes + 1] = {
                    id = "live_kits",
                    text = "SoundKit (" .. kitCount .. ")",
                    data = { categoryType = "live_kits" },
                }
            end
            if fileCount > 0 then
                nodes[#nodes + 1] = {
                    id = "live_files",
                    text = "SoundFile (" .. fileCount .. ")",
                    data = { categoryType = "live_files" },
                }
            end
            if musicCount > 0 then
                nodes[#nodes + 1] = {
                    id = "live_music",
                    text = "Music (" .. musicCount .. ")",
                    data = { categoryType = "live_music" },
                }
            end
            nodes[#nodes + 1] = {
                id = "live_clear",
                text = "Clear Results",
                data = { categoryType = "live_clear" },
            }
        end
        return nodes
    end

    local function BuildFavsTree()
        local favs = DF.SoundIndex:GetFavorites()
        local recent = DF.SoundIndex:GetRecent()
        return {
            { id = "favorites_root", text = "Favorites (" .. #favs .. ")", data = { categoryType = "favorites" } },
            { id = "recent_root",    text = "Recent (" .. #recent .. ")",  data = { categoryType = "recent" } },
        }
    end

    ---------------------------------------------------------------------------
    -- Tab switching
    ---------------------------------------------------------------------------
    SwitchTab = function(tabId)
        CancelFileIdScan()
        activeTab = tabId
        UpdateTabHighlights()
        local nodes
        if tabId == "kits" then nodes = BuildKitsTree()
        elseif tabId == "fileid" then nodes = BuildFileIdTree()
        elseif tabId == "live" then nodes = BuildLiveTree()
        elseif tabId == "favs" then nodes = BuildFavsTree()
        end
        tree:SetNodes(nodes or {})
        HideAllListItems()
        StopActiveSound()
        currentResults = {}
        infoLabel:SetText("")
    end

    for _, tb in ipairs(tabButtons) do
        tb.btn:SetScript("OnClick", function() SwitchTab(tb.id) end)
    end

    ---------------------------------------------------------------------------
    -- Tree selection handler
    ---------------------------------------------------------------------------
    tree:SetOnSelect(function(node)
        if not node or not node.data then return end
        lastSelectedNode = node
        local d = node.data

        -- SoundKit category
        if d.categoryType == "soundkit" and d.categoryId then
            local sounds = DF.SoundKitData:GetSounds(d.categoryId)
            local results = {}
            for _, entry in ipairs(sounds) do
                results[#results + 1] = {
                    id = entry.id,
                    name = entry.name,
                    sourceType = "kit",
                }
            end
            ShowSounds(results)
            return
        end

        -- FileID range explorer
        if d.categoryType == "fileid_browse" then
            local text = searchInput:GetText()
            local asNum = tonumber(text)
            if asNum and asNum > 0 then
                fileidStart = math.floor(asNum)
            end
            LoadFileIdPage()
            return
        end
        if d.categoryType == "fileid_prev" then
            fileidStart = math.max(1, fileidStart - FILEID_PAGE_SIZE)
            LoadFileIdPage()
            return
        end
        if d.categoryType == "fileid_next" then
            fileidStart = fileidStart + FILEID_PAGE_SIZE
            LoadFileIdPage()
            return
        end

        -- Live toggle
        if d.categoryType == "live_toggle" then
            if DF.SoundRuntime:IsListening() then
                DF.SoundRuntime:StopListening()
                infoLabel:SetText("Listener stopped — " .. DF.SoundRuntime:GetCount() .. " sounds captured")
            else
                DF.SoundRuntime:StartListening()
                infoLabel:SetText("Listening for sounds... play sounds in-game to capture them")
            end
            C_Timer.After(0, function()
                if activeTab == "live" then tree:SetNodes(BuildLiveTree()) end
            end)
            return
        end

        -- Live: all results
        if d.categoryType == "live_all" then
            local runtimeResults = DF.SoundRuntime:GetResults()
            local results = {}
            for _, item in ipairs(runtimeResults) do
                results[#results + 1] = {
                    id = item.id,
                    name = item.name,
                    sourceType = item.sourceType,
                }
            end
            ShowSounds(results)
            return
        end

        -- Live: filtered by type
        if d.categoryType == "live_kits" or d.categoryType == "live_files" or d.categoryType == "live_music" then
            local filterType = (d.categoryType == "live_kits" and "kit") or (d.categoryType == "live_music" and "music") or "file"
            local runtimeResults = DF.SoundRuntime:GetResults()
            local results = {}
            for _, item in ipairs(runtimeResults) do
                if item.sourceType == filterType then
                    results[#results + 1] = {
                        id = item.id,
                        name = item.name,
                        sourceType = item.sourceType,
                    }
                end
            end
            ShowSounds(results)
            return
        end

        -- Live: clear
        if d.categoryType == "live_clear" then
            DF.SoundRuntime:Clear()
            infoLabel:SetText("Captured sounds cleared")
            HideAllListItems()
            currentResults = {}
            C_Timer.After(0, function()
                if activeTab == "live" then tree:SetNodes(BuildLiveTree()) end
            end)
            return
        end

        -- Favorites
        if d.categoryType == "favorites" then
            local favs = DF.SoundIndex:GetFavorites()
            local results = {}
            for _, fav in ipairs(favs) do
                results[#results + 1] = {
                    id = fav.id,
                    name = fav.name,
                    sourceType = fav.sourceType or "kit",
                }
            end
            ShowSounds(results)
            return
        end

        -- Recent
        if d.categoryType == "recent" then
            local recent = DF.SoundIndex:GetRecent()
            local results = {}
            for _, rec in ipairs(recent) do
                results[#results + 1] = {
                    id = rec.id,
                    name = rec.name,
                    sourceType = rec.sourceType or "kit",
                }
            end
            ShowSounds(results)
            return
        end
    end)

    ---------------------------------------------------------------------------
    -- Search input
    ---------------------------------------------------------------------------
    searchInput:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            local asNum = tonumber(text)
            if asNum then
                if activeTab == "fileid" then
                    -- On FileID tab, jump to that range
                    fileidStart = math.max(1, math.floor(asNum))
                    LoadFileIdPage()
                else
                    -- Try as both SoundKit and FileID
                    ShowSounds({
                        { id = asNum, name = "SoundKit:" .. asNum, sourceType = "kit" },
                        { id = asNum, name = "FileID:" .. asNum, sourceType = "file" },
                    })
                    infoLabel:SetText("Showing ID " .. asNum .. " as SoundKit and FileID")
                end
            else
                local results = DF.SoundIndex:Search(text)
                ShowSounds(results)
                infoLabel:SetText(#results .. " search results for \"" .. text .. "\"")
            end
        end
        self:ClearFocus()
    end)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    copyBtn:SetScript("OnClick", function()
        local text = searchInput:GetText()
        if text and text ~= "" then DF.Widgets:ShowCopyDialog(text) end
    end)

    listPane.frame:SetScript("OnSizeChanged", function()
        listPane:GetContent():SetWidth(listPane.scrollFrame:GetWidth())
        if #currentResults > 0 then ShowSounds(currentResults) end
    end)

    SwitchTab("kits")

    ---------------------------------------------------------------------------
    -- Cross-module navigation: show a specific sound
    ---------------------------------------------------------------------------
    function browser:ShowSound(soundId, sourceType, sourceModule)
        if not soundId then return end
        ShowBackButton(sourceModule)
        searchInput:SetText(tostring(soundId))
        local name = (sourceType == "file") and ("FileID:" .. soundId) or ("SoundKit:" .. soundId)
        ShowSounds({ { id = soundId, name = name, sourceType = sourceType or "kit" } })
        infoLabel:SetText(name)
    end

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function browser:OnActivate()
        if unloadTimer then unloadTimer:Cancel(); unloadTimer = nil end
    end

    function browser:OnDeactivate()
        ShowBackButton(nil)
        CancelFileIdScan()
        StopActiveSound()
        unloadTimer = C_Timer.After(30, function()
            unloadTimer = nil
            HideAllListItems()
            currentResults = {}
            infoLabel:SetText("")
        end)
    end

    browser.sidebar = sidebarFrame
    browser.editor = editorFrame
    return browser
end, "Sounds")

-- Cross-module event: navigate to SoundBrowser with a specific sound.
-- Registered at file-load time so it works even before the module is first opened.
DF.EventBus:On("DF_SHOW_IN_SOUND_BROWSER", function(data)
    if not data or not data.id then return end
    local sourceModule = DF.ModuleSystem:GetActive()
    DF.ModuleSystem:Activate("SoundBrowser")
    local instance = DF.ModuleSystem:GetInstance("SoundBrowser")
    if instance and instance.ShowSound then
        instance:ShowSound(data.id, data.sourceType, sourceModule)
    end
end)
