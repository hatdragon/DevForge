local _, DF = ...

DF.ModuleSystem = {}
DF.Modules = {}

local ModuleSystem = DF.ModuleSystem
local modules = {}       -- { name = { factory, tabLabel, icon, instance, activated, sidebarFrame, editorFrame } }
local moduleOrder = {}   -- ordered list of module names
local activeModule = nil

-- Register a module with a factory function (lazy creation)
-- New signature supports icon and two-part factory:
--   factory(sidebarParent, editorParent) -> { sidebar = frame, editor = frame }
--   OR legacy: factory() -> { frame = frame }
function ModuleSystem:Register(name, factory, tabLabel)
    if modules[name] then return end
    modules[name] = {
        factory = factory,
        tabLabel = tabLabel or name,
        instance = nil,
        activated = false,
        sidebarFrame = nil,
        editorFrame = nil,
    }
    moduleOrder[#moduleOrder + 1] = name
end

-- Get ordered list of module names
function ModuleSystem:GetModuleNames()
    return moduleOrder
end

-- Get the tab label for a module
function ModuleSystem:GetTabLabel(name)
    local mod = modules[name]
    return mod and mod.tabLabel or name
end

-- Activate a module (creates it on first access)
function ModuleSystem:Activate(name)
    local mod = modules[name]
    if not mod then return end

    -- Deactivate current module
    if activeModule and activeModule ~= name then
        local prev = modules[activeModule]
        if prev and prev.instance and prev.instance.OnDeactivate then
            pcall(prev.instance.OnDeactivate, prev.instance)
        end
        -- Hide previous module's frames
        if prev and prev.sidebarFrame then
            prev.sidebarFrame:Hide()
        end
        if prev and prev.editorFrame then
            prev.editorFrame:Hide()
        end
        -- Legacy: hide frame if it exists
        if prev and prev.instance and prev.instance.frame and not prev.editorFrame then
            prev.instance.frame:Hide()
        end
    end

    -- Lazy-create the module instance
    if not mod.instance then
        local sidebarParent = self:GetSidebarParent()
        local editorParent = self:GetEditorParent()

        local ok, result = pcall(mod.factory, sidebarParent, editorParent)
        if ok then
            mod.instance = result
            DF.Modules[name] = result

            -- Determine frame layout: two-part or legacy
            if result.sidebar and result.editor then
                -- Two-part module
                mod.sidebarFrame = result.sidebar
                mod.editorFrame = result.editor
            elseif result.frame then
                -- Legacy single-frame module
                mod.editorFrame = result.frame
                mod.sidebarFrame = nil
            end
        else
            print("|cFFFF4444DevForge: Failed to create module '" .. name .. "': " .. tostring(result) .. "|r")
            return
        end
    end

    -- Mount sidebar content
    if DF.sidebar then
        if mod.sidebarFrame then
            mod.sidebarFrame:Show()
            DF.sidebar:SetContent(mod.sidebarFrame)
        else
            DF.sidebar:SetContent(nil)
        end
        DF.sidebar:SetTitle(mod.tabLabel)
    end

    -- Show editor frame
    if mod.editorFrame then
        mod.editorFrame:Show()
    end

    -- Activate callback
    if not mod.activated then
        mod.activated = true
        if mod.instance.OnFirstActivate then
            pcall(mod.instance.OnFirstActivate, mod.instance)
        end
    end

    if mod.instance.OnActivate then
        pcall(mod.instance.OnActivate, mod.instance)
    end

    activeModule = name

    -- Update activity bar + layout
    DF.EventBus:Fire("DF_MODULE_ACTIVATED", name)

    -- Save last active module
    if DevForgeDB then
        DevForgeDB.lastModule = name
    end
end

-- Get the currently active module name
function ModuleSystem:GetActive()
    return activeModule
end

-- Get a module instance (may be nil if not yet activated)
function ModuleSystem:GetInstance(name)
    local mod = modules[name]
    return mod and mod.instance
end

-- Deactivate the current module (called when window hides)
function ModuleSystem:DeactivateCurrent()
    if activeModule then
        local mod = modules[activeModule]
        if mod and mod.instance then
            if mod.instance.OnDeactivate then
                pcall(mod.instance.OnDeactivate, mod.instance)
            end
            if mod.sidebarFrame then
                mod.sidebarFrame:Hide()
            end
            if mod.editorFrame then
                mod.editorFrame:Hide()
            end
            -- Legacy
            if mod.instance.frame and not mod.editorFrame then
                mod.instance.frame:Hide()
            end
        end
    end
end

-- Reactivate the current module (called when window shows)
function ModuleSystem:ReactivateCurrent()
    if activeModule then
        local mod = modules[activeModule]
        if mod and mod.instance then
            if mod.sidebarFrame and DF.sidebar and not DF.sidebar.collapsed then
                mod.sidebarFrame:Show()
                DF.sidebar:SetContent(mod.sidebarFrame)
            end
            if mod.editorFrame then
                mod.editorFrame:Show()
            end
            -- Legacy
            if mod.instance.frame and not mod.editorFrame then
                mod.instance.frame:Show()
            end
            if mod.instance.OnActivate then
                pcall(mod.instance.OnActivate, mod.instance)
            end
        end
    end
end

-- Get the editor content parent frame for modules
function ModuleSystem:GetEditorParent()
    return DF.MainWindow and DF.MainWindow.editorContent
end

-- Get the sidebar content parent frame for modules
function ModuleSystem:GetSidebarParent()
    if DF.sidebar then
        return DF.sidebar.content
    end
    return nil
end

-- Legacy compatibility: GetContentParent returns editorContent
function ModuleSystem:GetContentParent()
    return self:GetEditorParent()
end
