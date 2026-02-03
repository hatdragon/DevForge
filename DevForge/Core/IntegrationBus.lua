local _, DF = ...

DF.IntegrationBus = {}

local Bus = DF.IntegrationBus

function Bus:Init()
    if self._initialized then return end
    self._initialized = true

    -- INSERT_TO_EDITOR: Insert code text into the active editor
    DF.EventBus:On("DF_INSERT_TO_EDITOR", function(payload)
        if not payload or not payload.text then return end
        local text = payload.text

        -- Find an active editor to insert into
        local active = DF.ModuleSystem:GetActive()
        local instance = active and DF.ModuleSystem:GetInstance(active)

        -- If SnippetEditor is active and has an InsertText method, use it
        if active == "SnippetEditor" and instance and instance.InsertText then
            instance:InsertText(text)
            return
        end

        -- If Console is active, put in input
        if active == "Console" and instance and instance.input then
            instance.input:SetText(text)
            instance.input:Focus()
            return
        end

        -- Otherwise, navigate to SnippetEditor and create/insert
        DF.ModuleSystem:Activate("SnippetEditor")
        C_Timer.After(0.1, function()
            local editor = DF.ModuleSystem:GetInstance("SnippetEditor")
            if editor and editor.InsertText then
                editor:InsertText(text)
            elseif editor and editor.CreateAndInsert then
                editor:CreateAndInsert(text)
            end
        end)
    end)

    -- EXECUTE_CODE: Run code, pipe output to bottom panel
    DF.EventBus:On("DF_EXECUTE_CODE", function(payload)
        if not payload or not payload.code then return end

        local source = payload.source or "unknown"
        local code = payload.code

        -- Execute through ConsoleExec
        if not DF.ConsoleExec then return end

        local result = DF.ConsoleExec:Execute(code)
        local lines = DF.ConsoleExec:FormatResults(result)

        -- Output source header
        DF.EventBus:Fire("DF_OUTPUT_LINE", {
            text = "> " .. code,
            color = DF.Colors.func,
        })

        -- Output results
        if #lines > 0 then
            for _, line in ipairs(lines) do
                DF.EventBus:Fire("DF_OUTPUT_LINE", { text = line })
            end
        end

        -- Blank separator
        DF.EventBus:Fire("DF_OUTPUT_LINE", { text = "" })
    end)

    -- OUTPUT_LINE: Append line to BottomPanel's shared output
    DF.EventBus:On("DF_OUTPUT_LINE", function(payload)
        if not payload then return end
        local bottomPanel = DF.bottomPanel
        if not bottomPanel then return end

        local text = payload.text or ""
        local color = payload.color
        bottomPanel:AddOutput(text, color)
    end)

    -- NAVIGATE_TO: Switch module with optional context
    DF.EventBus:On("DF_NAVIGATE_TO", function(payload)
        if not payload or not payload.module then return end
        DF.ModuleSystem:Activate(payload.module)

        -- Pass context to the module if it supports it
        if payload.context then
            C_Timer.After(0.1, function()
                local instance = DF.ModuleSystem:GetInstance(payload.module)
                if instance and instance.OnNavigateContext then
                    instance:OnNavigateContext(payload.context)
                end
            end)
        end
    end)
end

-- Auto-init when EventBus fires ADDON_LOADED
DF.EventBus:On("DF_ADDON_LOADED", function()
    Bus:Init()
end)
