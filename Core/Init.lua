local ADDON_NAME, DF = ...

-- Global addon table
DevForge = DF
DF.name = ADDON_NAME

-- Frame for event handling
DF.frame = CreateFrame("Frame")
DF.frame:RegisterEvent("ADDON_LOADED")
DF.frame:RegisterEvent("PLAYER_LOGOUT")

DF.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            DF.frame:UnregisterEvent("ADDON_LOADED")
            if DF.Schema then
                DF.Schema:Init()
            end
            -- Install error handler hooks immediately so no errors are missed
            if DF.ErrorHandler then
                DF.ErrorHandler:Init()
            end
            if DF.EventBus then
                DF.EventBus:Fire("DF_ADDON_LOADED")
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        if DF.EventBus then
            DF.EventBus:Fire("DF_PLAYER_LOGOUT")
        end
    end
end)

-- Addon Compartment support
if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    AddonCompartmentFrame:RegisterAddon({
        text = "DevForge",
        icon = 134064, -- Interface\\Icons\\INV_Gizmo_02
        notCheckable = true,
        func = function()
            DF:Toggle()
        end,
        funcOnEnter = function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
            GameTooltip:SetText("DevForge", 1, 1, 1)
            GameTooltip:AddLine("In-game Lua IDE", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to toggle window", 0.5, 0.8, 1)
            GameTooltip:Show()
        end,
        funcOnLeave = function()
            GameTooltip:Hide()
        end,
    })
end

-- Slash commands
SLASH_DEVFORGE1 = "/devforge"
SLASH_DEVFORGE2 = "/df"

SlashCmdList["DEVFORGE"] = function(msg)
    msg = strtrim(msg or "")
    local cmd = msg:lower()

    if cmd == "" then
        DF:Toggle()
    elseif cmd == "console" then
        DF:Show("Console")
    elseif cmd == "inspect" then
        DF:Show("Inspector")
        if DF.Modules and DF.Modules.Inspector and DF.Modules.Inspector.StartPicker then
            C_Timer.After(0.1, function()
                DF.Modules.Inspector:StartPicker()
            end)
        end
    elseif cmd == "api" then
        DF:Show("APIBrowser")
    elseif cmd == "pick" then
        DF:Show("Inspector")
        if DF.Modules and DF.Modules.Inspector and DF.Modules.Inspector.StartPicker then
            C_Timer.After(0.1, function()
                DF.Modules.Inspector:StartPicker()
            end)
        end
    elseif cmd == "editor" then
        DF:Show("SnippetEditor")
    elseif cmd == "events" then
        DF:Show("EventMonitor")
    elseif cmd == "textures" then
        DF:Show("TextureBrowser")
    elseif cmd == "errors" then
        DF:Show("ErrorHandler")
    elseif cmd == "perf" then
        DF:Show("Performance")
    elseif cmd == "macros" then
        DF:Show("MacroEditor")
    elseif cmd == "grid" then
        DF:Show("Inspector")
        C_Timer.After(0.1, function()
            if DF.InspectorGrid then
                DF.InspectorGrid:Toggle()
            end
        end)
    elseif cmd == "reset" then
        DF:ResetWindow()
    elseif DF.Util:StartsWith(cmd, "dump ") then
        -- /df dump <expression> - deep inspect and print to console
        local expr = msg:sub(6)
        DF:Show("Console")
        C_Timer.After(0.1, function()
            if DF.ConsoleExec then
                local result = DF.ConsoleExec:Execute(expr)
                local lines = DF.ConsoleExec:FormatResults(result)
                local output = DF.bottomPanel and DF.bottomPanel:GetSharedOutput()
                if output then
                    output:AddLine(DF.Colors.func .. "dump> |r" .. DF.Colors.text .. expr .. "|r")
                    if #lines > 0 then
                        output:AddLines(lines)
                    end
                    output:AddLine("")
                end
            end
        end)
    else
        -- Execute as Lua code in the console
        DF:Show("Console")
        C_Timer.After(0.1, function()
            if DF.Modules and DF.Modules.Console and DF.Modules.Console.ExecuteCode then
                DF.Modules.Console:ExecuteCode(msg)
            end
        end)
    end
end

-- Hook /dl -> DevForge Errors tab
SLASH_DEVFORGE_DL1 = "/dl"
SlashCmdList["DEVFORGE_DL"] = function()
    DF:Show("ErrorHandler")
end

-- Hook /apii -> DevForge API Browser tab
SLASH_DEVFORGE_APII1 = "/apii"
SlashCmdList["DEVFORGE_APII"] = function()
    DF:Show("APIBrowser")
end

-- Hook /lua -> DevForge Console tab
SLASH_DEVFORGE_LUA1 = "/lua"
SlashCmdList["DEVFORGE_LUA"] = function(msg)
    msg = strtrim(msg or "")
    if msg ~= "" then
        DF:Show("Console")
        C_Timer.After(0.1, function()
            if DF.Modules and DF.Modules.Console and DF.Modules.Console.ExecuteCode then
                DF.Modules.Console:ExecuteCode(msg)
            end
        end)
    else
        DF:Show("Console")
    end
end

function DF:Toggle()
    if DF.MainWindow then
        if DF.MainWindow:IsShown() then
            DF.MainWindow:Hide()
        else
            DF.MainWindow:Show()
        end
    else
        DF:CreateMainWindow()
        if DF.MainWindow then
            DF.MainWindow:Show()
        end
    end
end

function DF:Show(moduleName)
    if not DF.MainWindow then
        DF._pendingModule = moduleName
        DF:CreateMainWindow()
    end
    if DF.MainWindow then
        DF.MainWindow:Show()
        if moduleName and DF.ModuleSystem and not DF._pendingModule then
            -- Window already existed, activate directly
            DF.ModuleSystem:Activate(moduleName)
        end
    end
end

function DF:CreateMainWindow()
    if DF.MainWindow then return end
    if DF.UI and DF.UI.MainWindow then
        DF.UI.MainWindow:Create()
    end
end

function DF:ResetWindow()
    if DevForgeDB then
        DevForgeDB.windowX = nil
        DevForgeDB.windowY = nil
        DevForgeDB.windowW = nil
        DevForgeDB.windowH = nil
        DevForgeDB.sidebarWidth = DF.Layout.sidebarDefaultW
        DevForgeDB.sidebarCollapsed = false
        DevForgeDB.bottomHeight = DF.Layout.bottomDefaultH
        DevForgeDB.bottomCollapsed = false
        DevForgeDB.bottomActiveTab = "output"
    end
    if DF.MainWindow then
        DF.MainWindow:ClearAllPoints()
        DF.MainWindow:SetSize(DF.Layout.windowDefaultW, DF.Layout.windowDefaultH)
        DF.MainWindow:SetPoint("CENTER")
    end
    if DF.sidebar then
        DF.sidebar:SetWidth(DF.Layout.sidebarDefaultW)
        DF.sidebar:RestoreState()
    end
    if DF.bottomPanel then
        DF.bottomPanel:RestoreState()
    end
    print("|cFF569CD6DevForge|r: Window and layout reset.")
end
