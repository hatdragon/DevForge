local _, DF = ...

-- Register the Macro Editor module with sidebar + editor split
DF.ModuleSystem:Register("MacroEditor", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local editor = {}
    local currentIndex = nil

    ---------------------------------------------------------------------------
    -- Sidebar: macro list
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local macroList = DF.MacroList:Create(sidebarFrame)
    macroList.frame:SetAllPoints(sidebarFrame)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + name/icon + code editor + output
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local newBtn = DF.Widgets:CreateButton(toolbar, "+ New", 60)
    newBtn:SetPoint("LEFT", 2, 0)

    local delBtn = DF.Widgets:CreateButton(toolbar, "Delete", 60)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)

    local saveBtn = DF.Widgets:CreateButton(toolbar, "Save", 55)
    saveBtn:SetPoint("RIGHT", -2, 0)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 55)
    copyBtn:SetPoint("RIGHT", saveBtn, "LEFT", -4, 0)

    local runLuaBtn = DF.Widgets:CreateButton(toolbar, "Run as Lua", 80)
    runLuaBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)

    local validateBtn = DF.Widgets:CreateButton(toolbar, "Validate", 65)
    validateBtn:SetPoint("RIGHT", runLuaBtn, "LEFT", -4, 0)

    -- Empty state
    local emptyState = editorFrame:CreateFontString(nil, "OVERLAY")
    emptyState:SetFontObject(DF.Theme:UIFont())
    emptyState:SetPoint("CENTER", 0, 0)
    emptyState:SetText("Select a macro to edit, or click + New.")
    emptyState:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Editor content (hidden when no macro selected)
    local editorContent = CreateFrame("Frame", nil, editorFrame)
    editorContent:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    editorContent:SetPoint("BOTTOMRIGHT", 0, 0)
    editorContent:Hide()

    -- Name + icon row
    local nameRow = CreateFrame("Frame", nil, editorContent)
    nameRow:SetHeight(24)
    nameRow:SetPoint("TOPLEFT", 0, 0)
    nameRow:SetPoint("TOPRIGHT", 0, 0)

    local macroIcon = nameRow:CreateTexture(nil, "ARTWORK")
    macroIcon:SetSize(20, 20)
    macroIcon:SetPoint("LEFT", 4, 0)
    macroIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local nameLabel = nameRow:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFontObject(DF.Theme:UIFont())
    nameLabel:SetPoint("LEFT", macroIcon, "RIGHT", 4, 0)
    nameLabel:SetText("Name:")
    nameLabel:SetTextColor(0.65, 0.65, 0.65, 1)

    local nameInput = CreateFrame("EditBox", nil, nameRow, "BackdropTemplate")
    nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
    nameInput:SetPoint("RIGHT", -4, 0)
    nameInput:SetHeight(20)
    nameInput:SetAutoFocus(false)
    nameInput:SetFontObject(DF.Theme:UIFont())
    nameInput:SetTextColor(0.83, 0.83, 0.83, 1)
    nameInput:SetMaxLetters(100)
    DF.Theme:ApplyInputStyle(nameInput)

    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Vertical split: code editor top, output bottom
    local editorSplit = DF.Widgets:CreateSplitPane(editorContent, {
        direction = "vertical",
        initialSize = 300,
        minSize = 80,
        maxSize = 800,
    })
    editorSplit.frame:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -2)
    editorSplit.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    local codeEditor = DF.Widgets:CreateCodeEditBox(editorSplit.top, {
        multiLine = true,
        readOnly = false,
    })
    codeEditor.frame:SetAllPoints(editorSplit.top)

    local outputPane = DF.ConsoleOutput:Create(editorSplit.bottom)
    outputPane.frame:SetAllPoints(editorSplit.bottom)

    ---------------------------------------------------------------------------
    -- Logic (same as before, adapted for split layout)
    ---------------------------------------------------------------------------
    local function SaveCurrent()
        if not currentIndex then return end
        local name = nameInput:GetText()
        local body = codeEditor:GetText()
        DF.MacroStore:SaveFull(currentIndex, name, nil, body)
    end

    local function LoadMacro(index)
        if not index then
            editorContent:Hide()
            emptyState:Show()
            currentIndex = nil
            return
        end

        local macro = DF.MacroStore:Get(index)
        if not macro then
            editorContent:Hide()
            emptyState:Show()
            currentIndex = nil
            return
        end

        emptyState:Hide()
        editorContent:Show()
        currentIndex = index
        nameInput:SetText(macro.name or "")
        codeEditor:SetText(macro.body or "")
        if codeEditor.ResetUndo then codeEditor:ResetUndo() end
        outputPane:Clear()

        if macro.icon then
            macroIcon:SetTexture(macro.icon)
        else
            macroIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        macroList:SetSelected(index)

        if DevForgeDB then
            DevForgeDB.lastMacroIndex = index
        end
    end

    local function SelectNext()
        local all = DF.MacroStore:GetAll()
        if #all == 0 then LoadMacro(nil); return end
        LoadMacro(all[1].index)
    end

    macroList:SetOnSelect(function(index)
        SaveCurrent()
        LoadMacro(index)
    end)

    newBtn:SetScript("OnClick", function()
        SaveCurrent()
        local numAccount = DF.MacroStore:GetCounts()
        local maxAccount = MAX_ACCOUNT_MACROS
        local newIndex
        if numAccount < maxAccount then
            newIndex = DF.MacroStore:Create("New Macro", nil, "", false)
        else
            local _, numChar = DF.MacroStore:GetCounts()
            if numChar < MAX_CHARACTER_MACROS then
                newIndex = DF.MacroStore:Create("New Macro", nil, "", true)
            else
                outputPane:Clear()
                outputPane:AddLine(DF.Colors.error .. "No macro slots available.|r")
                return
            end
        end
        if newIndex then
            macroList:Refresh()
            LoadMacro(newIndex)
            nameInput:SetFocus()
            nameInput:HighlightText()
        end
    end)

    delBtn:SetScript("OnClick", function()
        if not currentIndex then return end
        local idxToDelete = currentIndex
        currentIndex = nil
        DF.MacroStore:Delete(idxToDelete)
        macroList:Refresh()
        SelectNext()
    end)

    saveBtn:SetScript("OnClick", function()
        SaveCurrent()
        macroList:Refresh()
    end)

    copyBtn:SetScript("OnClick", function()
        local text = outputPane:GetText()
        if text and text ~= "" then
            DF.Widgets:ShowCopyDialog(text)
        end
    end)

    ---------------------------------------------------------------------------
    -- Validation (same logic as before)
    ---------------------------------------------------------------------------
    local knownCommandsCache = nil
    local function GetKnownCommands()
        if knownCommandsCache then return knownCommandsCache end
        knownCommandsCache = {}
        for key, val in pairs(_G) do
            if type(key) == "string" and type(val) == "string"
               and key:match("^SLASH_") and val:sub(1, 1) == "/" then
                knownCommandsCache[val:lower()] = true
            end
        end
        return knownCommandsCache
    end

    local KNOWN_CONDITIONS = {
        ["help"] = true, ["harm"] = true, ["exists"] = true, ["dead"] = true,
        ["stealth"] = true, ["mounted"] = true, ["swimming"] = true,
        ["flying"] = true, ["indoors"] = true, ["outdoors"] = true,
        ["combat"] = true, ["channeling"] = true, ["canexitvehicle"] = true,
        ["mod"] = true, ["modifier"] = true,
        ["group"] = true, ["party"] = true, ["raid"] = true,
        ["spec"] = true, ["talent"] = true, ["pvptalent"] = true,
        ["stance"] = true, ["form"] = true,
        ["equipped"] = true, ["worn"] = true,
        ["actionbar"] = true, ["bonusbar"] = true, ["bar"] = true,
        ["button"] = true, ["btn"] = true,
        ["pet"] = true, ["petbattle"] = true,
        ["known"] = true, ["flyable"] = true, ["advflyable"] = true,
        ["unithasvehicleui"] = true,
    }

    local KNOWN_TARGETS = {
        ["target"] = true, ["player"] = true, ["focus"] = true,
        ["pet"] = true, ["mouseover"] = true, ["cursor"] = true,
        ["none"] = true, ["vehicle"] = true,
    }

    local function ValidateConditionalBlock(block, lineNum, issues, warnings)
        for cond in block:gmatch("[^,]+") do
            cond = strtrim(cond)
            if cond == "" then
            elseif cond:sub(1, 1) == "@" then
                local unit = cond:sub(2):lower()
                if unit == "" then
                    issues[#issues + 1] = format("Line %d: empty '@' target in conditional.", lineNum)
                elseif not KNOWN_TARGETS[unit]
                    and not unit:match("^party%d+$") and not unit:match("^raid%d+$")
                    and not unit:match("^arena%d+$") and not unit:match("^boss%d+$")
                    and not unit:match("^nameplate%d+$") then
                    warnings[#warnings + 1] = format("Line %d: '@%s' is not a standard unit token.", lineNum, cond:sub(2))
                end
            elseif cond:match("^target=") or cond:match("^target%s*=") then
                local unit = cond:match("target%s*=%s*(.+)")
                if unit then
                    unit = strtrim(unit):lower()
                    if not KNOWN_TARGETS[unit]
                        and not unit:match("^party%d+$") and not unit:match("^raid%d+$")
                        and not unit:match("^arena%d+$") and not unit:match("^boss%d+$") then
                        warnings[#warnings + 1] = format("Line %d: 'target=%s' is not a standard unit token.", lineNum, unit)
                    end
                end
            else
                local keyword = cond:match("^([%a]+)")
                if keyword then
                    local bare = keyword:lower()
                    local stripped = bare:match("^no(.+)") or bare
                    if not KNOWN_CONDITIONS[stripped] then
                        warnings[#warnings + 1] = format("Line %d: '%s' is not a recognized conditional.", lineNum, keyword)
                    end
                end
            end
        end
    end

    local function ValidateMacro(body)
        local issues = {}
        local warnings = {}
        local lines = {}
        for line in (body .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end

        local len = #body
        if len > 255 then
            issues[#issues + 1] = format("Body is %d chars (max 255). Will be truncated.", len)
        elseif len > 230 then
            warnings[#warnings + 1] = format("Body is %d/255 chars - close to limit.", len)
        end

        for i, line in ipairs(lines) do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed == "" then
            elseif trimmed:sub(1, 1) == "#" then
                if not trimmed:match("^#show") then
                    warnings[#warnings + 1] = format("Line %d: unrecognized directive '%s'.", i, trimmed:match("^#(%S+)") or trimmed)
                end
            elseif trimmed:sub(1, 1) == "/" then
                local cmd = trimmed:match("^(/[%a]+)")
                if not cmd then
                    issues[#issues + 1] = format("Line %d: malformed slash command.", i)
                else
                    if not GetKnownCommands()[cmd:lower()] then
                        local ADDON_HINTS = {
                            ["/way"] = "TomTom", ["/dbm"] = "Deadly Boss Mods",
                            ["/bigwigs"] = "BigWigs", ["/details"] = "Details! Damage Meter",
                            ["/elvui"] = "ElvUI",
                        }
                        local hint = ADDON_HINTS[cmd:lower()]
                        if hint then
                            warnings[#warnings + 1] = format("Line %d: '%s' requires %s (not installed or disabled).", i, cmd, hint)
                        else
                            warnings[#warnings + 1] = format("Line %d: '%s' is not a registered slash command.", i, cmd)
                        end
                    end

                    local rest = trimmed:sub(#cmd + 1)
                    local depth = 0
                    for ci = 1, #rest do
                        local ch = rest:sub(ci, ci)
                        if ch == "[" then depth = depth + 1
                        elseif ch == "]" then
                            depth = depth - 1
                            if depth < 0 then
                                issues[#issues + 1] = format("Line %d: unexpected ']' in conditionals.", i)
                                break
                            end
                        end
                    end
                    if depth > 0 then
                        issues[#issues + 1] = format("Line %d: unclosed '[' in conditionals.", i)
                    end

                    for block in rest:gmatch("%[([^%]]+)%]") do
                        ValidateConditionalBlock(block, i, issues, warnings)
                    end

                    local cmdLower = cmd:lower()
                    if cmdLower == "/run" or cmdLower == "/script" then
                        local luaCode = trimmed:match("^/%S+%s+(.+)")
                        if luaCode then
                            local fn, err = loadstring(luaCode)
                            if not fn then
                                local short = err:match(":(%d+:.+)") or err
                                issues[#issues + 1] = format("Line %d: Lua syntax error: %s", i, short)
                            end
                        end
                    end
                end
            else
                issues[#issues + 1] = format("Line %d: text doesn't start with '/' or '#'.", i)
            end
        end
        return issues, warnings
    end

    validateBtn:SetScript("OnClick", function()
        if not currentIndex then return end
        knownCommandsCache = nil
        SaveCurrent()
        local body = codeEditor:GetText()
        outputPane:Clear()

        if not body or body == "" then
            outputPane:AddLine(DF.Colors.dim .. "(empty macro)|r")
            return
        end

        local issues, warnings = ValidateMacro(body)
        if #issues == 0 and #warnings == 0 then
            outputPane:AddLine(DF.Colors.func .. "Macro looks clean.|r")
            outputPane:AddLine(DF.Colors.dim .. format("(%d/255 characters)", #body) .. "|r")
            return
        end
        if #issues > 0 then
            outputPane:AddLine(DF.Colors.error .. "Errors:|r")
            for _, msg in ipairs(issues) do outputPane:AddLine(DF.Colors.error .. "  " .. msg .. "|r") end
        end
        if #warnings > 0 then
            if #issues > 0 then outputPane:AddLine("") end
            outputPane:AddLine(DF.Colors.keyword .. "Warnings:|r")
            for _, msg in ipairs(warnings) do outputPane:AddLine(DF.Colors.keyword .. "  " .. msg .. "|r") end
        end
        outputPane:AddLine("")
        outputPane:AddLine(DF.Colors.dim .. format("(%d/255 characters)", #body) .. "|r")
    end)

    ---------------------------------------------------------------------------
    -- Protected function / command checks for Run as Lua
    ---------------------------------------------------------------------------
    local PROTECTED_FUNCTIONS = {
        "SetRaidTarget", "CastSpellByName", "CastSpellByID", "UseAction",
        "UseItemByName", "UseInventoryItem", "UseContainerItem",
        "RunMacro", "RunMacroText", "CastShapeshiftForm", "CancelShapeshiftForm",
        "TargetUnit", "AssistUnit", "FollowUnit", "FocusUnit", "ClearTarget", "ClearFocus",
        "AttackTarget", "PetAttack", "PetFollow", "PetStay", "PetPassiveMode",
        "PetDefensiveMode", "PetAssistMode",
        "EquipItemByName", "PickupAction", "PlaceAction",
        "AcceptDuel", "StartDuel", "CancelDuel",
        "JoinBattlefield", "LeaveBattlefield", "ConfirmReadyCheck",
    }

    local function CheckProtectedLua(luaCode)
        local found = {}
        for _, fn in ipairs(PROTECTED_FUNCTIONS) do
            if luaCode:find(fn .. "%s*%(") then found[#found + 1] = fn .. "()" end
        end
        return found
    end

    local PROTECTED_COMMANDS = {
        ["/cast"] = true, ["/use"] = true, ["/castsequence"] = true,
        ["/castrandom"] = true, ["/userandom"] = true,
        ["/startattack"] = true, ["/stopattack"] = true,
        ["/petattack"] = true, ["/petfollow"] = true, ["/petstay"] = true,
        ["/petpassive"] = true, ["/petdefensive"] = true, ["/petassist"] = true,
        ["/petautocaston"] = true, ["/petautocastoff"] = true, ["/petautocasttoggle"] = true,
        ["/cancelaura"] = true, ["/cancelform"] = true, ["/dismount"] = true,
        ["/stopcasting"] = true, ["/cancelqueuedspell"] = true,
        ["/equip"] = true, ["/equipslot"] = true, ["/equipset"] = true,
        ["/click"] = true, ["/target"] = true, ["/tar"] = true,
        ["/focus"] = true, ["/clearfocus"] = true, ["/cleartarget"] = true,
        ["/assist"] = true, ["/follow"] = true, ["/f"] = true,
        ["/stopmacro"] = true, ["/leavevehicle"] = true,
        ["/changeactionbar"] = true, ["/swapactionbar"] = true,
    }

    runLuaBtn:SetScript("OnClick", function()
        if not currentIndex then return end
        SaveCurrent()
        local code = codeEditor:GetText()
        if not code or code == "" then return end
        outputPane:Clear()

        if not DF.ConsoleExec then
            outputPane:AddLine(DF.Colors.error .. "Console execution engine not loaded.|r")
            return
        end

        local protectedFound = {}
        local actions = {}
        for line in code:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed == "" or trimmed:sub(1, 1) == "#" then
            else
                local cmd = trimmed:match("^(/[%a]+)")
                local cmdLower = cmd and cmd:lower() or ""
                if cmd and PROTECTED_COMMANDS[cmdLower] then
                    protectedFound[cmdLower] = true
                elseif cmdLower == "/run" or cmdLower == "/script" then
                    local stripped = trimmed:match("^/%S+%s+(.+)")
                    if stripped then actions[#actions + 1] = { type = "lua", code = stripped } end
                elseif cmd and trimmed:sub(1, 1) == "/" then
                    local args = trimmed:sub(#cmd + 1):match("^%s*(.-)%s*$") or ""
                    actions[#actions + 1] = { type = "slash", cmd = cmdLower, args = args, raw = cmd }
                else
                    actions[#actions + 1] = { type = "lua", code = trimmed }
                end
            end
        end

        for _, action in ipairs(actions) do
            if action.type == "lua" then
                local calls = CheckProtectedLua(action.code)
                for _, fn in ipairs(calls) do protectedFound[fn] = true end
            end
        end

        if next(protectedFound) then
            local cmds = {}
            for cmd in pairs(protectedFound) do cmds[#cmds + 1] = cmd end
            table.sort(cmds)
            outputPane:AddLine(DF.Colors.keyword .. "This macro uses " .. table.concat(cmds, ", ") .. " which require a keybind or button click. Running validation instead.|r")
            outputPane:AddLine("")
            knownCommandsCache = nil
            local issues, warnings = ValidateMacro(code)
            if #issues > 0 then
                outputPane:AddLine(DF.Colors.error .. "Errors:|r")
                for _, msg in ipairs(issues) do outputPane:AddLine(DF.Colors.error .. "  " .. msg .. "|r") end
            end
            if #warnings > 0 then
                if #issues > 0 then outputPane:AddLine("") end
                outputPane:AddLine(DF.Colors.keyword .. "Warnings:|r")
                for _, msg in ipairs(warnings) do outputPane:AddLine(DF.Colors.keyword .. "  " .. msg .. "|r") end
            end
            if #issues == 0 and #warnings == 0 then
                outputPane:AddLine(DF.Colors.func .. "Macro looks clean.|r")
            end
            outputPane:AddLine(DF.Colors.dim .. format("(%d/255 characters)", #code) .. "|r")
            return
        end

        if #actions == 0 then
            outputPane:AddLine(DF.Colors.dim .. "No executable content in this macro.|r")
            return
        end

        local function FindSlashHandler(cmdLower)
            if ChatFrame_ImportAllListsToHash then ChatFrame_ImportAllListsToHash() end
            local cmdUpper = cmdLower:upper()
            if hash_SlashCmdList and hash_SlashCmdList[cmdUpper] then return hash_SlashCmdList[cmdUpper] end
            return nil
        end

        local hasOutput = false
        for _, action in ipairs(actions) do
            if action.type == "lua" then
                local result = DF.ConsoleExec:Execute(action.code)
                local fmtLines = DF.ConsoleExec:FormatResults(result)
                if #fmtLines > 0 then outputPane:AddLines(fmtLines); hasOutput = true end
            elseif action.type == "slash" then
                local handler = FindSlashHandler(action.cmd)
                if handler then
                    local ok, err = pcall(handler, action.args)
                    if not ok then outputPane:AddLine(DF.Colors.error .. action.raw .. ": " .. tostring(err) .. "|r"); hasOutput = true end
                else
                    outputPane:AddLine(DF.Colors.keyword .. action.raw .. ": no handler found, skipping.|r"); hasOutput = true
                end
            end
        end

        if not hasOutput then outputPane:AddLine(DF.Colors.dim .. "(no output)|r") end
    end)

    ---------------------------------------------------------------------------
    -- Listen for macro changes
    ---------------------------------------------------------------------------
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_MACROS")
    eventFrame:SetScript("OnEvent", function()
        if editorFrame:IsVisible() then macroList:Refresh() end
    end)

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function editor:OnFirstActivate()
        DF.MacroStore:Init()
        macroList:Refresh()
        local lastIdx = DevForgeDB and DevForgeDB.lastMacroIndex
        if lastIdx and DF.MacroStore:Get(lastIdx) then
            LoadMacro(lastIdx)
        else
            local all = DF.MacroStore:GetAll()
            if #all > 0 then LoadMacro(all[1].index) else LoadMacro(nil) end
        end
    end

    function editor:OnActivate()
        macroList:Refresh()
    end

    function editor:OnDeactivate()
        SaveCurrent()
        if DevForgeDB and currentIndex then DevForgeDB.lastMacroIndex = currentIndex end
        codeEditor:ClearFocus()
        nameInput:ClearFocus()
    end

    editor.sidebar = sidebarFrame
    editor.editor = editorFrame
    return editor
end, "Macros")
