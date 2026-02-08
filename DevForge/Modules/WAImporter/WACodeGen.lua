local _, DF = ...

DF.WACodeGen = {}

local WACodeGen = DF.WACodeGen

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function SanitizeName(name)
    if not name or name == "" then return "MyAura" end
    return name:gsub("[^%w_]", ""):gsub("^%d", "_")
end

local function VarName(auraId, index)
    local base = SanitizeName(auraId)
    if base == "" then base = "aura" .. index end
    return base
end

local function Indent(lines, prefix)
    prefix = prefix or "    "
    local out = {}
    for i = 1, #lines do
        out[i] = prefix .. lines[i]
    end
    return out
end

-- Check if an aura has event-driven triggers that handle visibility
local function HasEventTriggers(aura)
    for _, trig in ipairs(aura.triggers or {}) do
        if trig.type == "aura2" or trig.type == "status" or trig.type == "event" then
            return true
        end
    end
    return false
end

-- Parse a WA custom trigger events string ("EVENT1 EVENT2:unit") into structured list
local function ParseCustomEvents(eventsStr)
    if not eventsStr or eventsStr == "" then return {} end
    local events = {}
    for token in eventsStr:gmatch("%S+") do
        -- Strip trailing commas/semicolons (WA often comma-separates events)
        token = token:gsub("[,;]+$", "")
        if token ~= "" then
            local evt, unit = token:match("^(.+):(.+)$")
            if evt then
                events[#events + 1] = { event = evt, unit = unit }
            else
                events[#events + 1] = { event = token }
            end
        end
    end
    return events
end

-- Strip leading comment lines and whitespace from WA custom code,
-- returning (leadingComments, strippedCode)
local function StripLeadingComments(code)
    local lines = {}
    local leading = {}
    local pastComments = false
    for line in code:gmatch("[^\r\n]+") do
        if not pastComments then
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed == "" or trimmed:match("^%-%-") then
                leading[#leading + 1] = line
            else
                pastComments = true
                lines[#lines + 1] = line
            end
        else
            lines[#lines + 1] = line
        end
    end
    return leading, table.concat(lines, "\n")
end

-- Has custom triggers that should be polled via OnUpdate (excludes stateupdate/event-driven)
local function HasPollableCustomTriggers(aura)
    for _, trig in ipairs(aura.triggers or {}) do
        if trig.type == "custom" and trig.custom and trig.custom_type ~= "stateupdate" and trig.custom_type ~= "event" then
            return true
        end
    end
    return false
end

local function Quoted(s)
    if not s then return '""' end
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
end

-- Recursive table-to-Lua-literal helper.
-- Short arrays (<=8 elements) emit inline; longer/nested tables use multi-line.
local function EmitTableLiteral(value, indent)
    indent = indent or "    "
    local vt = type(value)
    if vt == "string" then
        return Quoted(value)
    elseif vt == "number" or vt == "boolean" then
        return tostring(value)
    elseif vt ~= "table" then
        return "nil"
    end
    -- Check if it's a short, flat array (all values are primitives, <=8 elements)
    local n = #value
    local isShortArray = n > 0 and n <= 8
    if isShortArray then
        for i = 1, n do
            local et = type(value[i])
            if et ~= "string" and et ~= "number" and et ~= "boolean" then
                isShortArray = false
                break
            end
        end
        -- Also check there are no non-integer keys
        if isShortArray then
            local count = 0
            for _ in pairs(value) do count = count + 1 end
            if count ~= n then isShortArray = false end
        end
    end
    if isShortArray then
        local parts = {}
        for i = 1, n do
            parts[i] = EmitTableLiteral(value[i], indent)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    -- Multi-line format
    local inner = indent .. "    "
    local parts = {}
    -- Array part first
    for i = 1, n do
        parts[#parts + 1] = inner .. EmitTableLiteral(value[i], inner) .. ","
    end
    -- Hash part
    for k, v in pairs(value) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. EmitTableLiteral(k, inner) .. "]"
            end
            parts[#parts + 1] = inner .. keyStr .. " = " .. EmitTableLiteral(v, inner) .. ","
        end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end

local function AuraNeedsEnv(aura)
    for _, code in ipairs({ aura.initCode, aura.onShowCode, aura.onHideCode, aura.customText }) do
        if code and code:find("aura_env") then return true end
    end
    for _, trig in ipairs(aura.triggers or {}) do
        if trig.custom and trig.custom:find("aura_env") then return true end
        if trig.customName and trig.customName:find("aura_env") then return true end
    end
    return false
end

-- Emit aura_env local inside each aura's do-block.
-- frameName is the local variable name of the frame (used for aura_env.region).
local function EmitAuraEnv(lines, aura, frameName)
    lines[#lines + 1] = "    local aura_env = {}"
    lines[#lines + 1] = "    aura_env.id = " .. Quoted(aura.id or "Unnamed")
    if aura.config then
        lines[#lines + 1] = "    aura_env.config = {"
        -- Sort keys for deterministic output
        local keys = {}
        for k in pairs(aura.config) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = aura.config[k]
            lines[#lines + 1] = "        " .. k .. " = " .. EmitTableLiteral(v, "        ") .. ","
        end
        lines[#lines + 1] = "    }"
    else
        lines[#lines + 1] = "    aura_env.config = {}"
    end
    lines[#lines + 1] = "    -- Overlay saved config from DB"
    lines[#lines + 1] = "    if db.config then"
    lines[#lines + 1] = "        for k, v in pairs(db.config) do aura_env.config[k] = v end"
    lines[#lines + 1] = "    end"
    if frameName then
        lines[#lines + 1] = "    aura_env.region = " .. frameName
    end
    lines[#lines + 1] = "    aura_env.state = {}"
    lines[#lines + 1] = "    aura_env.states = {}"
    lines[#lines + 1] = ""
end

-- Emit per-aura WA setup: register this aura's region in the global WA regions table.
-- Global WA stubs are set up once in GenerateInit; this just adds aura-specific bindings.
local function EmitWAStubs(lines, aura)
    -- Collect all custom code strings to scan
    local codeStrings = {}
    local function collect(s) if s then codeStrings[#codeStrings + 1] = s end end
    collect(aura.initCode)
    collect(aura.onShowCode)
    collect(aura.onHideCode)
    collect(aura.customText)
    for _, trig in ipairs(aura.triggers or {}) do
        collect(trig.custom)
        collect(trig.customName)
    end
    if #codeStrings == 0 then return end

    local allCode = table.concat(codeStrings, "\n")
    local needsWA = allCode:find("WeakAuras")
    if not needsWA then return end

    lines[#lines + 1] = "    -- Register this aura in WA regions table (global stubs set up at top of Init)"
    lines[#lines + 1] = "    if WeakAuras and WeakAuras.regions then"
    lines[#lines + 1] = "        WeakAuras.regions[" .. Quoted(aura.id or "Unnamed") .. "] = { region = aura_env.region }"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = ""
end

-- Emit WA custom code as live code (init) or comments (show/hide callbacks)
local function EmitCustomCode(lines, code, banner, asLive)
    if not code then return end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    -- ============ WA " .. banner .. " ============"
    if asLive then
        for line in code:gmatch("[^\r\n]+") do
            lines[#lines + 1] = "    " .. line
        end
    else
        lines[#lines + 1] = "    -- (commented out — callback needs manual wiring)"
        for line in code:gmatch("[^\r\n]+") do
            lines[#lines + 1] = "    -- " .. line
        end
    end
    lines[#lines + 1] = "    -- ============ end WA " .. banner .. " ============"
end

-- Wire onShow/onHide code as frame callbacks instead of commenting them out.
local function EmitFrameCallbacks(lines, aura, frameName)
    if aura.onShowCode then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    -- ============ WA onShow callback ============"
        lines[#lines + 1] = "    " .. frameName .. ':SetScript("OnShow", function(self)'
        for line in aura.onShowCode:gmatch("[^\r\n]+") do
            lines[#lines + 1] = "        " .. line
        end
        lines[#lines + 1] = "    end)"
    end
    if aura.onHideCode then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    -- ============ WA onHide callback ============"
        lines[#lines + 1] = "    " .. frameName .. ':SetScript("OnHide", function(self)'
        for line in aura.onHideCode:gmatch("[^\r\n]+") do
            lines[#lines + 1] = "        " .. line
        end
        lines[#lines + 1] = "    end)"
    end
end

-- Fire stateupdate triggers once after setup to establish initial state.
local function EmitInitialStateUpdateEval(lines, aura, frameName)
    for i, trig in ipairs(aura.triggers or {}) do
        if trig.type == "custom" and trig.custom_type == "stateupdate" then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "    -- Initial stateupdate evaluation (trigger " .. i .. ")"
            lines[#lines + 1] = "    do"
            lines[#lines + 1] = "        local changed = stateUpdate_" .. i .. " and stateUpdate_" .. i .. "(allstates_" .. i .. ', "STATUS")'
            lines[#lines + 1] = "        if changed then"
            lines[#lines + 1] = "            local anyShow = (next(allstates_" .. i .. ") == nil)  -- empty allstates = trigger active"
            lines[#lines + 1] = "            for _, st in pairs(allstates_" .. i .. ") do"
            lines[#lines + 1] = "                if st.show then anyShow = true; break end"
            lines[#lines + 1] = "            end"
            lines[#lines + 1] = "            triggerStates[" .. i .. "] = anyShow"
            lines[#lines + 1] = "            EvalTriggers()"
            lines[#lines + 1] = "        end"
            lines[#lines + 1] = "    end"
        end
    end
end

-- Emit per-frame unified trigger state tracking.
-- Creates a triggerStates table and EvalTriggers() function that combines
-- all trigger states according to the aura's disjunctive mode (AND/OR).
local function EmitTriggerStateTracking(lines, aura, frameName)
    if not aura.triggers or #aura.triggers == 0 then return end

    local N = #aura.triggers
    local useAny = (aura.disjunctive == "any")

    lines[#lines + 1] = ""
    lines[#lines + 1] = "    -- Unified trigger state tracking (disjunctive=" .. tostring(aura.disjunctive) .. ")"
    lines[#lines + 1] = "    local triggerStates = {}"
    for i, trig in ipairs(aura.triggers) do
        if trig.type == "custom" or trig.type == "aura2" or trig.type == "status" or trig.type == "event" then
            lines[#lines + 1] = "    triggerStates[" .. i .. "] = false"
        else
            -- Unknown trigger type: default to active so it doesn't block visibility
            lines[#lines + 1] = "    triggerStates[" .. i .. "] = true  -- " .. tostring(trig.type) .. ": default active"
        end
    end
    lines[#lines + 1] = ""
    if useAny then
        lines[#lines + 1] = "    local function EvalTriggers()"
        lines[#lines + 1] = "        for i = 1, " .. N .. " do"
        lines[#lines + 1] = "            if triggerStates[i] then " .. frameName .. ":Show(); return end"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        " .. frameName .. ":Hide()"
        lines[#lines + 1] = "    end"
    else
        lines[#lines + 1] = "    local function EvalTriggers()"
        lines[#lines + 1] = "        for i = 1, " .. N .. " do"
        lines[#lines + 1] = "            if not triggerStates[i] then " .. frameName .. ":Hide(); return end"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        " .. frameName .. ":Show()"
        lines[#lines + 1] = "    end"
    end
end

-- Check if any aura in the analysis references WeakAuras APIs
local function AnalysisNeedsWA(analysis)
    for _, aura in ipairs(analysis.auras or {}) do
        local codeStrings = {}
        local function collect(s) if s then codeStrings[#codeStrings + 1] = s end end
        collect(aura.initCode)
        collect(aura.onShowCode)
        collect(aura.onHideCode)
        collect(aura.customText)
        for _, trig in ipairs(aura.triggers or {}) do
            collect(trig.custom)
            collect(trig.customName)
        end
        if #codeStrings > 0 then
            local allCode = table.concat(codeStrings, "\n")
            if allCode:find("WeakAuras") then return true end
        end
    end
    return false
end

-- WA bundled texture substitutions
local WA_TEXTURE_SUBS = {
    Circle_Smooth2 = "Interface\\COMMON\\Indicator-Gray",
    Circle_Smooth  = "Interface\\COMMON\\Indicator-Gray",
    Square_White   = "Interface\\BUTTONS\\WHITE8X8",
}

-- Determine SetAtlas vs SetTexture for a WA texture source.
-- Atlas names are simple strings (no path separators), file paths contain / or \,
-- numeric values are fileIDs. Substitutes known WA bundled textures.
local function TextureCall(texValue)
    if not texValue then
        return "SetTexture", '"Interface\\\\Icons\\\\INV_Misc_QuestionMark"', nil
    end
    if type(texValue) == "number" then
        return "SetTexture", tostring(texValue), nil
    end
    local s = tostring(texValue)
    -- Check for WA bundled textures
    local waBase = s:match("WeakAuras[/\\]Media[/\\]Textures[/\\](.+)")
    if waBase then
        -- Strip file extension if present
        local name = waBase:gsub("%.[^%.]+$", "")
        local sub = WA_TEXTURE_SUBS[name]
        if sub then
            return "SetTexture", Quoted(sub), "-- WA texture: " .. s .. " -> substituted"
        else
            return "SetTexture", '"Interface\\\\Icons\\\\INV_Misc_QuestionMark"',
                "-- TODO: WA bundled texture not available: " .. s
        end
    end
    if s:find("[/\\]") or s:lower():find("^interface") then
        return "SetTexture", Quoted(s), nil
    end
    return "SetAtlas", Quoted(s), nil
end

---------------------------------------------------------------------------
-- TOC generation
---------------------------------------------------------------------------

local function GenerateTOC(projectName)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add("## Interface: 120000, 120001")
    add("## Title: " .. projectName)
    add("## Notes: Generated from WeakAuras import")
    add("## Author: DevForge WAImporter")
    add("## Version: 1.0.0")
    add("## SavedVariables: " .. projectName .. "DB")
    add("")
    add("Init.lua")
    add("Options.lua")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Trigger code generation
---------------------------------------------------------------------------

local function GenAura2Trigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local unit = trig.unit or "player"
    local showOnMissing = (trig.matchesShowOn == "showOnMissing")

    add(frameName .. ':RegisterUnitEvent("UNIT_AURA", "' .. unit .. '")')

    -- Build the aura check function
    add("local function CheckAura_" .. index .. "()")
    add("    local found = false")

    if trig.auraspellids and #trig.auraspellids > 0 then
        -- Spell ID based lookup
        for _, spellId in ipairs(trig.auraspellids) do
            add('    local aura = C_UnitAuras.GetPlayerAuraBySpellID(' .. tostring(spellId) .. ')')
            add("    if aura then found = true end")
        end
    elseif trig.auranames and #trig.auranames > 0 then
        -- Name based lookup
        for _, name in ipairs(trig.auranames) do
            add('    if AuraUtil.FindAuraByName(' .. Quoted(name) .. ', "' .. unit .. '") then')
            add("        found = true")
            add("    end")
        end
    else
        add("    -- TODO: No specific aura names/IDs found in WA data")
        add("    found = true")
    end

    if showOnMissing then
        add("    return not found  -- showOnMissing: show when aura is absent")
    else
        add("    return found")
    end
    add("end")

    return lines
end

local function GenCooldownTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local spellName = trig.spellName or "UNKNOWN_SPELL"

    add(frameName .. ':RegisterEvent("SPELL_UPDATE_COOLDOWN")')
    add("local function CheckCooldown_" .. index .. "()")
    add("    local info = C_Spell.GetSpellCooldown(" .. Quoted(spellName) .. ")")
    add("    if info and info.duration > 0 then")
    add("        return true, info.startTime, info.duration")
    add("    end")
    add("    return false")
    add("end")

    return lines
end

local function GenHealthTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local unit = trig.unit or "player"

    add(frameName .. ':RegisterUnitEvent("UNIT_HEALTH", "' .. unit .. '")')
    add("local function CheckHealth_" .. index .. "()")
    add('    local hp = UnitHealth("' .. unit .. '")')
    add('    local max = UnitHealthMax("' .. unit .. '")')
    add("    return hp, max")
    add("end")

    return lines
end

local function GenPowerTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local unit = trig.unit or "player"

    add(frameName .. ':RegisterUnitEvent("UNIT_POWER_UPDATE", "' .. unit .. '")')
    add("local function CheckPower_" .. index .. "()")
    add('    local power = UnitPower("' .. unit .. '")')
    add('    local max = UnitPowerMax("' .. unit .. '")')
    add("    return power, max")
    add("end")

    return lines
end

local function GenStateUpdateTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Register events from the trigger's events field (pcall for custom WA events)
    local events = ParseCustomEvents(trig.events)
    for _, ev in ipairs(events) do
        if ev.unit then
            add('pcall(' .. frameName .. '.RegisterUnitEvent, ' .. frameName .. ', "' .. ev.event .. '", "' .. ev.unit .. '")')
        else
            add('pcall(' .. frameName .. '.RegisterEvent, ' .. frameName .. ', "' .. ev.event .. '")')
        end
    end

    -- State table for this trigger
    add("local allstates_" .. index .. " = {}")
    add("")

    -- The stateupdate function: signature is function(allstates, event, ...)
    add("-- WA stateupdate trigger " .. index)
    if trig.custom then
        local code = trig.custom:match("^%s*(.-)%s*$")
        local leadingLines, stripped = StripLeadingComments(code)
        if stripped:match("^function%s*%(") then
            for _, cline in ipairs(leadingLines) do
                add(cline)
            end
            add("local stateUpdate_" .. index .. " = " .. stripped)
        else
            add("local function stateUpdate_" .. index .. "(allstates, event, ...)")
            for line in code:gmatch("[^\r\n]+") do
                add("    " .. line)
            end
            add("end")
        end
    else
        add("-- (no custom code found for stateupdate trigger)")
    end

    return lines
end

local function GenCustomTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Register events if present (event-driven custom triggers; pcall for custom WA events)
    if trig.events and trig.events ~= "" and frameName then
        local events = ParseCustomEvents(trig.events)
        for _, ev in ipairs(events) do
            if ev.unit then
                add('pcall(' .. frameName .. '.RegisterUnitEvent, ' .. frameName .. ', "' .. ev.event .. '", "' .. ev.unit .. '")')
            else
                add('pcall(' .. frameName .. '.RegisterEvent, ' .. frameName .. ', "' .. ev.event .. '")')
            end
        end
    end

    add("-- WA custom trigger " .. index)
    if trig.custom then
        local code = trig.custom:match("^%s*(.-)%s*$")
        local leadingLines, stripped = StripLeadingComments(code)
        if stripped:match("^function%s*%(") then
            for _, cline in ipairs(leadingLines) do
                add(cline)
            end
            add("local customTrigger_" .. index .. " = " .. stripped)
        else
            add("local function customTrigger_" .. index .. "()")
            for line in code:gmatch("[^\r\n]+") do
                add("    " .. line)
            end
            add("end")
        end
    else
        add("-- (no custom code found)")
    end

    return lines
end

local function GenEventTrigger(trig, frameName, index)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local event = trig.event or "UNKNOWN_EVENT"

    add(frameName .. ':RegisterEvent("' .. event .. '")')
    add("-- Event handler skeleton for " .. event)
    add("-- TODO: Implement event logic for trigger " .. index)

    return lines
end

local function GenTriggerCode(trig, frameName, index)
    if not trig then return { "-- No trigger data" } end

    if trig.type == "aura2" then
        return GenAura2Trigger(trig, frameName, index)
    elseif trig.type == "status" then
        if trig.event == "Cooldown Progress (Spell)" or
           trig.event == "Cooldown Ready (Spell)" then
            return GenCooldownTrigger(trig, frameName, index)
        elseif trig.event == "Health" then
            return GenHealthTrigger(trig, frameName, index)
        elseif trig.event == "Power" or trig.event == "Alternate Power" then
            return GenPowerTrigger(trig, frameName, index)
        else
            -- Generic status event
            local lines = {}
            lines[#lines + 1] = "-- Status trigger: " .. tostring(trig.event)
            lines[#lines + 1] = "-- TODO: Implement status handler for trigger " .. index
            return lines
        end
    elseif trig.type == "custom" then
        if trig.custom_type == "stateupdate" then
            return GenStateUpdateTrigger(trig, frameName, index)
        end
        return GenCustomTrigger(trig, frameName, index)
    elseif trig.type == "event" then
        return GenEventTrigger(trig, frameName, index)
    end

    return { "-- Unknown trigger type: " .. tostring(trig.type) }
end

---------------------------------------------------------------------------
-- OnEvent handler generation
---------------------------------------------------------------------------

local function GenOnEventHandler(aura, frameName, varPrefix)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    if not aura.triggers or #aura.triggers == 0 then
        add("-- TODO: No triggers defined; add event handling here")
        return lines
    end

    local hasTriggers = false
    for i, trig in ipairs(aura.triggers) do
        if trig.type == "aura2" or trig.type == "status" or trig.type == "event" then
            hasTriggers = true
            break
        end
        if trig.type == "custom" and (trig.custom_type == "stateupdate" or trig.custom_type == "event") then
            hasTriggers = true
            break
        end
    end

    if not hasTriggers then return lines end

    add(frameName .. ':SetScript("OnEvent", function(self, event, ...)')

    -- Standard triggers (aura2 / status / event)
    for i, trig in ipairs(aura.triggers) do
        if trig.type == "aura2" then
            add('    if event == "UNIT_AURA" then')
            add("        local show = CheckAura_" .. i .. "()")
            if aura.regionType == "aurabar" then
                add("        self.active = show")
            end
            add("        triggerStates[" .. i .. "] = show")
            add("        EvalTriggers()")
            add("    end")
        elseif trig.type == "status" then
            if trig.event == "Cooldown Progress (Spell)" or
               trig.event == "Cooldown Ready (Spell)" then
                add('    if event == "SPELL_UPDATE_COOLDOWN" then')
                add("        local onCD, start, dur = CheckCooldown_" .. i .. "()")
                if aura.regionType == "icon" then
                    add("        if onCD and self.cooldown then self.cooldown:SetCooldown(start, dur) end")
                end
                add("        triggerStates[" .. i .. "] = onCD and true or false")
                add("        EvalTriggers()")
                add("    end")
            elseif trig.event == "Health" then
                add('    if event == "UNIT_HEALTH" then')
                add("        local hp, max = CheckHealth_" .. i .. "()")
                if aura.regionType == "aurabar" then
                    add("        if max > 0 then self:SetValue(hp / max * 100) end")
                end
                add("    end")
            elseif trig.event == "Power" or trig.event == "Alternate Power" then
                add('    if event == "UNIT_POWER_UPDATE" then')
                add("        local power, max = CheckPower_" .. i .. "()")
                if aura.regionType == "aurabar" then
                    add("        if max > 0 then self:SetValue(power / max * 100) end")
                end
                add("    end")
            end
        elseif trig.type == "event" then
            local evt = trig.event or "UNKNOWN_EVENT"
            add('    if event == "' .. evt .. '" then')
            add("        -- TODO: Handle " .. evt)
            add("    end")
        end
    end

    -- Stateupdate triggers: called on any event, manage allstates table
    for i, trig in ipairs(aura.triggers) do
        if trig.type == "custom" and trig.custom_type == "stateupdate" then
            add("")
            add("    -- Stateupdate trigger " .. i)
            add("    do")
            add("        local changed = stateUpdate_" .. i .. " and stateUpdate_" .. i .. "(allstates_" .. i .. ", event, ...)")
            add("        if changed then")
            add("            local anyShow = (next(allstates_" .. i .. ") == nil)  -- empty allstates = trigger active")
            add("            for _, st in pairs(allstates_" .. i .. ") do")
            add("                if st.show then anyShow = true; break end")
            add("            end")
            add("            triggerStates[" .. i .. "] = anyShow")
            add("            EvalTriggers()")
            add("        end")
            add("    end")
        end
    end

    -- Event-driven custom triggers: called on their registered events
    for i, trig in ipairs(aura.triggers) do
        if trig.type == "custom" and trig.custom_type == "event" then
            add("")
            add("    -- Event-driven custom trigger " .. i)
            add("    do")
            add("        local result = customTrigger_" .. i .. " and customTrigger_" .. i .. "(event, ...)")
            add("        triggerStates[" .. i .. "] = result and true or false")
            add("        EvalTriggers()")
            add("    end")
        end
    end

    add("end)")

    -- Register frame for WA ScanEvents custom event dispatch
    add("")
    add("if WeakAuras and WeakAuras._scanEventFrames then")
    add("    WeakAuras._scanEventFrames[#WeakAuras._scanEventFrames + 1] = " .. frameName)
    add("end")

    return lines
end

---------------------------------------------------------------------------
-- Custom trigger OnUpdate generation
---------------------------------------------------------------------------

-- Emit an OnUpdate that polls custom trigger functions for show/hide.
-- If displayFnName is provided, also calls it each tick to update a FontString.
-- Automatically handles cursor following when aura.anchorFrameType == "MOUSE".
local function EmitCustomTriggerOnUpdate(lines, aura, frameName, displayFnName, additionalLines)
    local customIdxs = {}
    for i, trig in ipairs(aura.triggers or {}) do
        -- Only poll non-stateupdate, non-event-driven custom triggers via OnUpdate
        if trig.type == "custom" and trig.custom
           and trig.custom_type ~= "stateupdate"
           and trig.custom_type ~= "event" then
            customIdxs[#customIdxs + 1] = i
        end
    end

    local hasCustomTriggers = #customIdxs > 0
    local hasDynText = displayFnName ~= nil
    local mouseFollow = (aura.anchorFrameType == "MOUSE")

    if not hasCustomTriggers and not hasDynText and not mouseFollow then return end

    lines[#lines + 1] = ""

    -- Simple cursor-only OnUpdate (no throttle needed)
    if mouseFollow and not hasCustomTriggers and not hasDynText then
        local xOff = aura.xOffset or 0
        local yOff = aura.yOffset or 0
        lines[#lines + 1] = "    -- OnUpdate: follow cursor (anchorFrameType = MOUSE)"
        lines[#lines + 1] = "    " .. frameName .. ':SetScript("OnUpdate", function(self)'
        lines[#lines + 1] = "        local cx, cy = GetCursorPosition()"
        lines[#lines + 1] = "        local scale = self:GetEffectiveScale()"
        lines[#lines + 1] = "        self:ClearAllPoints()"
        lines[#lines + 1] = '        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale + ' .. xOff .. ", cy / scale + " .. yOff .. ")"
        lines[#lines + 1] = "    end)"
        return
    end

    -- Combined OnUpdate: cursor following (every frame) + throttled trigger/text polling
    local label = mouseFollow and "follow cursor + " or ""
    lines[#lines + 1] = "    -- OnUpdate: " .. label .. "poll custom triggers / dynamic text (~15fps)"
    lines[#lines + 1] = "    local elapsed = 0"
    lines[#lines + 1] = "    " .. frameName .. ':SetScript("OnUpdate", function(self, dt)'

    if mouseFollow then
        local xOff = aura.xOffset or 0
        local yOff = aura.yOffset or 0
        lines[#lines + 1] = "        -- Cursor following (every frame)"
        lines[#lines + 1] = "        local cx, cy = GetCursorPosition()"
        lines[#lines + 1] = "        local scale = self:GetEffectiveScale()"
        lines[#lines + 1] = "        self:ClearAllPoints()"
        lines[#lines + 1] = '        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale + ' .. xOff .. ", cy / scale + " .. yOff .. ")"
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "        elapsed = elapsed + dt"
    lines[#lines + 1] = "        if elapsed < 0.066 then return end"
    lines[#lines + 1] = "        elapsed = 0"

    if hasCustomTriggers then
        lines[#lines + 1] = ""
        -- Store individual trigger results so conditions can reference them
        for _, idx in ipairs(customIdxs) do
            lines[#lines + 1] = "        local trigResult_" .. idx .. " = customTrigger_" .. idx .. " and customTrigger_" .. idx .. "()"
        end

        -- Update unified trigger states from polled results
        lines[#lines + 1] = ""
        for _, idx in ipairs(customIdxs) do
            lines[#lines + 1] = "        triggerStates[" .. idx .. "] = trigResult_" .. idx .. " and true or false"
        end
        lines[#lines + 1] = "        EvalTriggers()"
        lines[#lines + 1] = "        if not self:IsShown() then return end"
    end

    if hasDynText then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "        -- Dynamic text update"
        lines[#lines + 1] = "        text:SetText(" .. displayFnName .. "() or \"\")"
    end

    -- Inject additional code (conditions, etc.)
    if additionalLines then
        for _, line in ipairs(additionalLines) do
            lines[#lines + 1] = line
        end
    end

    lines[#lines + 1] = "    end)"
end

---------------------------------------------------------------------------
-- Condition code generation (for text auras)
---------------------------------------------------------------------------

-- Build lines that evaluate WA conditions inside an OnUpdate.
-- Expects trigResult_N locals to be in scope from trigger evaluation.
-- Supports properties: color, fontSize.  Skips yOffsetRelative (needs reposition wiring).
local function BuildConditionLines(aura)
    if not aura.conditions then return nil end

    -- Determine which properties any condition touches, so we know what to revert
    local condLines = {}
    local function add(s) condLines[#condLines + 1] = s end

    add("")
    add("        -- WA conditions")

    for _, cond in ipairs(aura.conditions) do
        if cond.variable == "show" and cond.value == 1 and cond.trigger then
            local checkVar = "trigResult_" .. cond.trigger
            add("        if " .. checkVar .. " then")

            local touchesColor, touchesFontSize = false, false
            for _, change in ipairs(cond.changes) do
                if change.property == "color" and type(change.value) == "table" then
                    touchesColor = true
                    local r = change.value[1] or 1
                    local g = change.value[2] or 1
                    local b = change.value[3] or 1
                    local a = change.value[4] or 1
                    add("            text:SetTextColor(" .. r .. ", " .. g .. ", " .. b .. ", " .. a .. ")")
                elseif change.property == "fontSize" and change.value then
                    touchesFontSize = true
                    add("            text:SetFont(fontPath, " .. change.value .. ", fontFlags)")
                end
            end

            add("        else")

            -- Revert only the properties this condition touches
            if touchesColor then
                local r = aura.color and aura.color[1] or 1
                local g = aura.color and aura.color[2] or 1
                local b = aura.color and aura.color[3] or 1
                local a = aura.color and aura.color[4] or 1
                add("            text:SetTextColor(" .. r .. ", " .. g .. ", " .. b .. ", " .. a .. ")")
            end
            if touchesFontSize then
                add("            text:SetFont(fontPath, " .. (aura.fontSize or 12) .. ", fontFlags)")
            end

            add("        end")
        end
    end

    return #condLines > 1 and condLines or nil  -- > 1 because first line is the header comment
end

---------------------------------------------------------------------------
-- Per-aura frame code by regionType
---------------------------------------------------------------------------

local function GenIconAura(aura, index, parentFrame)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local var = VarName(aura.id, index)
    local frameName = var .. "Frame"
    local w = aura.width or 40
    local h = aura.height or 40

    add("-- Icon: " .. aura.id)
    add("do")
    add("    local " .. frameName .. " = CreateFrame(\"Frame\", nil, " .. parentFrame .. ")")
    add("    " .. frameName .. ":SetSize(" .. w .. ", " .. h .. ")")
    add("    " .. frameName .. ':SetPoint("' .. (aura.selfPoint or "CENTER") .. '", ' .. parentFrame .. ', "' .. (aura.anchorPoint or "CENTER") .. '", ' .. (aura.xOffset or 0) .. ", " .. (aura.yOffset or 0) .. ")")
    add("")
    if AuraNeedsEnv(aura) then
        EmitAuraEnv(lines, aura, frameName)
        EmitWAStubs(lines, aura)
    end
    add("    local icon = " .. frameName .. ':CreateTexture(nil, "ARTWORK")')
    add("    icon:SetAllPoints()")
    local iconMethod, iconArg, iconComment = TextureCall(aura.displayIcon or aura.texture)
    if iconComment then add("    " .. iconComment) end
    add("    icon:" .. iconMethod .. "(" .. iconArg .. ")")
    if aura.color and type(aura.color) == "table" then
        local r = aura.color[1] or 1
        local g = aura.color[2] or 1
        local b = aura.color[3] or 1
        local a = aura.color[4] or 1
        add("    icon:SetVertexColor(" .. r .. ", " .. g .. ", " .. b .. ", " .. a .. ")")
    end
    if aura.desaturate then
        add("    icon:SetDesaturated(true)")
    end
    if aura.alpha then
        add("    " .. frameName .. ":SetAlpha(" .. aura.alpha .. ")")
    end
    add("    " .. frameName .. ".icon = icon")
    add("")
    add("    local cooldown = CreateFrame(\"Cooldown\", nil, " .. frameName .. ", \"CooldownFrameTemplate\")")
    add("    cooldown:SetAllPoints()")
    add("    " .. frameName .. ".cooldown = cooldown")
    add("")

    -- Trigger setup
    for i, trig in ipairs(aura.triggers or {}) do
        local trigLines = GenTriggerCode(trig, frameName, i)
        for _, tl in ipairs(trigLines) do
            add("    " .. tl)
        end
        add("")
    end

    -- Unified trigger state tracking
    EmitTriggerStateTracking(lines, aura, frameName)

    -- OnEvent handler
    local handlerLines = GenOnEventHandler(aura, frameName, var)
    for _, hl in ipairs(handlerLines) do
        add("    " .. hl)
    end

    -- WA custom code
    EmitCustomCode(lines, aura.initCode, "init custom code", true)
    EmitFrameCallbacks(lines, aura, frameName)

    -- OnUpdate for custom trigger polling / cursor following
    if HasPollableCustomTriggers(aura) or aura.anchorFrameType == "MOUSE" then
        EmitCustomTriggerOnUpdate(lines, aura, frameName, nil)
    end

    -- Initial stateupdate evaluation
    EmitInitialStateUpdateEval(lines, aura, frameName)

    if not aura.triggers or #aura.triggers == 0 then
        add("")
        add("    -- TODO: No triggers defined; frame created but no event handling")
    end

    add("")
    if aura.triggers and #aura.triggers > 0 then
        add("    EvalTriggers()  -- Set initial visibility from trigger defaults")
    else
        add("    " .. frameName .. ":Show()  -- No triggers, always visible")
    end
    add("end")

    return lines
end

local function GenAuraBarAura(aura, index, parentFrame)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local var = VarName(aura.id, index)
    local frameName = var .. "Frame"
    local w = aura.width or 200
    local h = aura.height or 20

    add("-- AuraBar: " .. aura.id)
    add("do")
    add("    local " .. frameName .. ' = CreateFrame("StatusBar", nil, ' .. parentFrame .. ")")
    add("    " .. frameName .. ":SetSize(" .. w .. ", " .. h .. ")")
    add("    " .. frameName .. ':SetPoint("' .. (aura.selfPoint or "CENTER") .. '", ' .. parentFrame .. ', "' .. (aura.anchorPoint or "CENTER") .. '", ' .. (aura.xOffset or 0) .. ", " .. (aura.yOffset or 0) .. ")")
    add("    " .. frameName .. ':SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")')
    add("    " .. frameName .. ":SetStatusBarColor(0.3, 0.5, 0.8, 1)")
    add("    " .. frameName .. ":SetMinMaxValues(0, 100)")
    add("    " .. frameName .. ":SetValue(0)")
    add("")
    add("    local bg = " .. frameName .. ':CreateTexture(nil, "BACKGROUND")')
    add("    bg:SetAllPoints()")
    add("    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)")
    add("")
    add("    local text = " .. frameName .. ':CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")')
    add('    text:SetPoint("CENTER")')
    add('    text:SetText("")')
    add("    " .. frameName .. ".text = text")
    add("")
    add("    " .. frameName .. ".active = false")
    add("    " .. frameName .. ".expirationTime = 0")
    add("    " .. frameName .. ".duration = 0")
    add("")
    if AuraNeedsEnv(aura) then
        EmitAuraEnv(lines, aura, frameName)
        EmitWAStubs(lines, aura)
    end

    -- Trigger setup
    for i, trig in ipairs(aura.triggers or {}) do
        local trigLines = GenTriggerCode(trig, frameName, i)
        for _, tl in ipairs(trigLines) do
            add("    " .. tl)
        end
        add("")
    end

    -- Unified trigger state tracking
    EmitTriggerStateTracking(lines, aura, frameName)

    if HasPollableCustomTriggers(aura) then
        -- Custom trigger polling via OnUpdate (handles show/hide via EvalTriggers)
        EmitCustomTriggerOnUpdate(lines, aura, frameName, nil)
    else
        -- OnUpdate for smooth countdown (event-driven bars)
        add("    " .. frameName .. ':SetScript("OnUpdate", function(self, elapsed)')
        add("        if not self.active then return end")
        add("        local remaining = self.expirationTime - GetTime()")
        add("        if remaining <= 0 then")
        add("            self:Hide()")
        add("            self.active = false")
        add("            return")
        add("        end")
        add("        if self.duration > 0 then")
        add("            self:SetValue(remaining / self.duration * 100)")
        add("        end")
        add('        self.text:SetText(string.format("%.1f", remaining))')
        add("    end)")
    end
    add("")

    -- OnEvent handler
    local handlerLines = GenOnEventHandler(aura, frameName, var)
    for _, hl in ipairs(handlerLines) do
        add("    " .. hl)
    end

    -- WA custom code
    EmitCustomCode(lines, aura.initCode, "init custom code", true)
    EmitFrameCallbacks(lines, aura, frameName)

    -- Initial stateupdate evaluation
    EmitInitialStateUpdateEval(lines, aura, frameName)

    if not aura.triggers or #aura.triggers == 0 then
        add("")
        add("    -- TODO: No triggers defined; frame created but no event handling")
    end

    add("")
    if aura.triggers and #aura.triggers > 0 then
        add("    EvalTriggers()  -- Set initial visibility from trigger defaults")
    else
        add("    " .. frameName .. ":Show()  -- No triggers, always visible")
    end
    add("end")

    return lines
end

local function GenTextAura(aura, index, parentFrame)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local var = VarName(aura.id, index)
    local frameName = var .. "Frame"
    local w = aura.width or 200
    local h = aura.height or 20

    -- Determine dynamic text source:
    -- 1) aura.customText resolves %c tokens in displayText
    -- 2) trigger.customName resolves %n tokens in displayText
    -- Either can serve as the dynamic text function.
    local dynamicTextCode, dynamicTextLabel
    if aura.customText and aura.customText ~= "" then
        dynamicTextCode = aura.customText
        dynamicTextLabel = "customText"
    else
        -- Check active trigger's customName (resolves %n dynamically)
        local idx = aura.activeTriggerMode
        if not idx or idx < 1 then idx = 1 end
        local activeTrig = aura.triggers and aura.triggers[idx]
        if activeTrig and activeTrig.customName and activeTrig.customName ~= "" then
            dynamicTextCode = activeTrig.customName
            dynamicTextLabel = "customName (trigger " .. idx .. ")"
        end
    end
    local hasDynamicText = dynamicTextCode ~= nil

    add("-- Text: " .. aura.id)
    add("do")
    add("    local " .. frameName .. " = CreateFrame(\"Frame\", nil, " .. parentFrame .. ")")
    add("    " .. frameName .. ":SetSize(" .. w .. ", " .. h .. ")")
    add("    " .. frameName .. ':SetPoint("' .. (aura.selfPoint or "CENTER") .. '", ' .. parentFrame .. ', "' .. (aura.anchorPoint or "CENTER") .. '", ' .. (aura.xOffset or 0) .. ", " .. (aura.yOffset or 0) .. ")")
    add("")
    if AuraNeedsEnv(aura) then
        EmitAuraEnv(lines, aura, frameName)
        EmitWAStubs(lines, aura)
    end
    add("    local text = " .. frameName .. ':CreateFontString(nil, "OVERLAY", "GameFontNormal")')
    add('    text:SetPoint("CENTER")')

    -- Font setup
    local baseFontSize = aura.fontSize or 12
    local outlineFlags = aura.outline or ""
    add('    local fontPath = "Fonts\\\\FRIZQT__.TTF"')
    if aura.font then
        add("    -- WA font: " .. aura.font .. " (using system font)")
    end
    add("    local fontFlags = " .. Quoted(outlineFlags))
    add("    text:SetFont(fontPath, " .. baseFontSize .. ", fontFlags)")
    if aura.color and type(aura.color) == "table" then
        local r = aura.color[1] or 1
        local g = aura.color[2] or 1
        local b = aura.color[3] or 1
        local a = aura.color[4] or 1
        add("    text:SetTextColor(" .. r .. ", " .. g .. ", " .. b .. ", " .. a .. ")")
    end
    if aura.justify then
        add("    text:SetJustifyH(" .. Quoted(aura.justify) .. ")")
    end

    if hasDynamicText then
        add('    text:SetText("")  -- updated dynamically by displayFn')
    else
        -- Resolve basic WA format tokens: %n = aura name, others stripped
        local staticText = aura.displayText or aura.id
        staticText = staticText:gsub("%%n", aura.id)
        staticText = staticText:gsub("%%[cptsCSi]", "")
        add('    text:SetText(' .. Quoted(staticText) .. ')')
    end
    add("    " .. frameName .. ".text = text")
    add("")

    -- Emit dynamic text as a callable function
    local displayFnName
    if hasDynamicText then
        displayFnName = "displayFn"
        add("    -- WA " .. dynamicTextLabel .. " (returns display string)")
        local code = dynamicTextCode:match("^%s*(.-)%s*$")
        if code:match("^function%s*%(") then
            add("    local " .. displayFnName .. " = " .. code)
        else
            add("    local function " .. displayFnName .. "()")
            for line in code:gmatch("[^\r\n]+") do
                add("        " .. line)
            end
            add("    end")
        end
        add("")
    end

    -- Trigger setup
    for i, trig in ipairs(aura.triggers or {}) do
        local trigLines = GenTriggerCode(trig, frameName, i)
        for _, tl in ipairs(trigLines) do
            add("    " .. tl)
        end
        add("")
    end

    -- Unified trigger state tracking
    EmitTriggerStateTracking(lines, aura, frameName)

    -- OnEvent handler (for event-driven triggers)
    local handlerLines = GenOnEventHandler(aura, frameName, var)
    for _, hl in ipairs(handlerLines) do
        add("    " .. hl)
    end

    -- WA custom code
    EmitCustomCode(lines, aura.initCode, "init custom code", true)
    EmitFrameCallbacks(lines, aura, frameName)

    -- OnUpdate: custom trigger polling + dynamic text refresh + conditions + cursor following
    if HasPollableCustomTriggers(aura) or hasDynamicText or aura.anchorFrameType == "MOUSE" then
        local condLines = BuildConditionLines(aura)
        EmitCustomTriggerOnUpdate(lines, aura, frameName, displayFnName, condLines)
    end

    -- Initial stateupdate evaluation
    EmitInitialStateUpdateEval(lines, aura, frameName)

    if not aura.triggers or #aura.triggers == 0 then
        if not hasDynamicText then
            add("")
            add("    -- TODO: No triggers defined; frame created but no event handling")
        end
    end

    add("")
    if aura.triggers and #aura.triggers > 0 then
        add("    EvalTriggers()  -- Set initial visibility from trigger defaults")
    else
        add("    " .. frameName .. ":Show()  -- No triggers, always visible")
    end
    add("end")

    return lines
end

local function GenTextureAura(aura, index, parentFrame)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local var = VarName(aura.id, index)
    local frameName = var .. "Frame"
    local w = aura.width or 40
    local h = aura.height or 40

    add("-- Texture: " .. aura.id)
    add("do")
    add("    local " .. frameName .. " = CreateFrame(\"Frame\", nil, " .. parentFrame .. ")")
    add("    " .. frameName .. ":SetSize(" .. w .. ", " .. h .. ")")
    add("    " .. frameName .. ':SetPoint("' .. (aura.selfPoint or "CENTER") .. '", ' .. parentFrame .. ', "' .. (aura.anchorPoint or "CENTER") .. '", ' .. (aura.xOffset or 0) .. ", " .. (aura.yOffset or 0) .. ")")
    add("")
    if AuraNeedsEnv(aura) then
        EmitAuraEnv(lines, aura, frameName)
        EmitWAStubs(lines, aura)
    end
    add("    local tex = " .. frameName .. ':CreateTexture(nil, "ARTWORK")')
    add("    tex:SetAllPoints()")
    local texMethod, texArg, texComment = TextureCall(aura.texture or aura.displayIcon)
    if texComment then add("    " .. texComment) end
    add("    tex:" .. texMethod .. "(" .. texArg .. ")")
    if aura.color and type(aura.color) == "table" then
        local r = aura.color[1] or 1
        local g = aura.color[2] or 1
        local b = aura.color[3] or 1
        local a = aura.color[4] or 1
        add("    tex:SetVertexColor(" .. r .. ", " .. g .. ", " .. b .. ", " .. a .. ")")
    end
    if aura.desaturate then
        add("    tex:SetDesaturated(true)")
    end
    if aura.rotation then
        add("    tex:SetRotation(" .. aura.rotation .. ")")
    end
    if aura.alpha then
        add("    " .. frameName .. ":SetAlpha(" .. aura.alpha .. ")")
    end
    add("    " .. frameName .. ".texture = { texture = tex }  -- WA region compat: region.texture.texture")
    add("")

    -- Trigger setup
    for i, trig in ipairs(aura.triggers or {}) do
        local trigLines = GenTriggerCode(trig, frameName, i)
        for _, tl in ipairs(trigLines) do
            add("    " .. tl)
        end
        add("")
    end

    -- Unified trigger state tracking
    EmitTriggerStateTracking(lines, aura, frameName)

    -- OnEvent handler
    local handlerLines = GenOnEventHandler(aura, frameName, var)
    for _, hl in ipairs(handlerLines) do
        add("    " .. hl)
    end

    -- WA custom code
    EmitCustomCode(lines, aura.initCode, "init custom code", true)
    EmitFrameCallbacks(lines, aura, frameName)

    -- OnUpdate for custom trigger polling / cursor following
    if HasPollableCustomTriggers(aura) or aura.anchorFrameType == "MOUSE" then
        EmitCustomTriggerOnUpdate(lines, aura, frameName, nil)
    end

    -- Initial stateupdate evaluation
    EmitInitialStateUpdateEval(lines, aura, frameName)

    if not aura.triggers or #aura.triggers == 0 then
        add("")
        add("    -- TODO: No triggers defined; frame created but no event handling")
    end

    add("")
    if aura.triggers and #aura.triggers > 0 then
        add("    EvalTriggers()  -- Set initial visibility from trigger defaults")
    else
        add("    " .. frameName .. ":Show()  -- No triggers, always visible")
    end
    add("end")

    return lines
end

local function GenUnknownAura(aura, index, parentFrame)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add("-- Unknown regionType: " .. tostring(aura.regionType) .. " for: " .. aura.id)
    add("-- Original WA data summary:")
    add("--   regionType = " .. tostring(aura.regionType))
    add("--   size = " .. tostring(aura.width) .. "x" .. tostring(aura.height))
    add("--   triggers = " .. tostring(aura.triggers and #aura.triggers or 0))
    add("-- TODO: Implement native frame for this regionType")

    return lines
end

local function GenAuraCode(aura, index, parentFrame)
    local regionType = aura.regionType or "unknown"

    if regionType == "icon" then
        return GenIconAura(aura, index, parentFrame)
    elseif regionType == "aurabar" then
        return GenAuraBarAura(aura, index, parentFrame)
    elseif regionType == "text" then
        return GenTextAura(aura, index, parentFrame)
    elseif regionType == "texture" then
        return GenTextureAura(aura, index, parentFrame)
    else
        return GenUnknownAura(aura, index, parentFrame)
    end
end

---------------------------------------------------------------------------
-- Load guard generation
---------------------------------------------------------------------------

local function GenLoadGuard(analysis)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Use the first aura's load conditions as the guard
    local aura = analysis.auras and analysis.auras[1]
    if not aura then return lines end

    local hasClass = aura.loadClass and #aura.loadClass > 0
    local hasSpec = aura.loadSpec and #aura.loadSpec > 0

    if not hasClass and not hasSpec then return lines end

    add("    -- Load guard: class/spec check from WA load conditions")

    if hasClass then
        local checks = {}
        for _, cls in ipairs(aura.loadClass) do
            checks[#checks + 1] = 'playerClass == "' .. cls .. '"'
        end
        add('    local _, playerClass = UnitClass("player")')
        if #checks == 1 then
            add("    if not (" .. checks[1] .. ") then return end")
        else
            add("    if not (" .. table.concat(checks, " or ") .. ") then return end")
        end
    end

    if hasSpec then
        local checks = {}
        for _, spec in ipairs(aura.loadSpec) do
            checks[#checks + 1] = "playerSpec == " .. tostring(spec)
        end
        add("    local playerSpec = GetSpecialization()")
        if #checks == 1 then
            add("    if not (" .. checks[1] .. ") then return end")
        else
            add("    if not (" .. table.concat(checks, " or ") .. ") then return end")
        end
    end

    add("")

    return lines
end

---------------------------------------------------------------------------
-- Config defaults collection
---------------------------------------------------------------------------

-- Gather default config values from authorOptions (priority) and raw config (fallback).
local function CollectConfigDefaults(analysis)
    local defaults = {}   -- ordered list of { key, value }
    local seen = {}
    -- authorOptions take priority
    for _, aura in ipairs(analysis.auras or {}) do
        for _, opt in ipairs(aura.authorOptions or {}) do
            if opt.key and not seen[opt.key] and opt.default ~= nil then
                seen[opt.key] = true
                defaults[#defaults + 1] = { key = opt.key, value = opt.default }
            end
        end
    end
    -- Raw config values as fallback
    for _, aura in ipairs(analysis.auras or {}) do
        if aura.config then
            local keys = {}
            for k in pairs(aura.config) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                if not seen[k] then
                    seen[k] = true
                    defaults[#defaults + 1] = { key = k, value = aura.config[k] }
                end
            end
        end
    end
    return #defaults > 0 and defaults or nil
end

-- Gather authorOptions from all auras into a single ordered list (deduped by key).
local function CollectAuthorOptions(analysis)
    local opts = {}
    local seen = {}
    for _, aura in ipairs(analysis.auras or {}) do
        for _, opt in ipairs(aura.authorOptions or {}) do
            if opt.type == "description" then
                -- Always include description entries (they have no key)
                opts[#opts + 1] = opt
            elseif opt.key and not seen[opt.key] then
                seen[opt.key] = true
                opts[#opts + 1] = opt
            end
        end
    end
    return #opts > 0 and opts or nil
end

---------------------------------------------------------------------------
-- Init.lua generation
---------------------------------------------------------------------------

local function GenerateInit(analysis, projectName)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local dbName = projectName .. "DB"

    add("local ADDON_NAME, ns = ...")
    add("")
    add("local f = CreateFrame(\"Frame\")")
    add('f:RegisterEvent("PLAYER_ENTERING_WORLD")')
    add('f:SetScript("OnEvent", function(self)')
    add('    self:UnregisterEvent("PLAYER_ENTERING_WORLD")')

    -- Load guard
    local guardLines = GenLoadGuard(analysis)
    for _, gl in ipairs(guardLines) do
        add(gl)
    end

    add("    ns.Init()")
    add("end)")
    add("")
    add("function ns.Init()")

    -- SavedVariables initialization (per-key defaults preserve saved values)
    add("    if not " .. dbName .. " then " .. dbName .. " = {} end")
    add("    local db = " .. dbName)
    add("    if db.enabled == nil then db.enabled = true end")
    add("    if db.xOff == nil then db.xOff = 0 end")
    add("    if db.yOff == nil then db.yOff = 0 end")

    -- Config defaults from authorOptions / raw config
    local configDefaults = CollectConfigDefaults(analysis)
    if configDefaults then
        add("    if not db.config then db.config = {} end")
        add("    -- Per-key defaults from authorOptions / aura config")
        for _, def in ipairs(configDefaults) do
            add("    if db.config." .. def.key .. " == nil then db.config." .. def.key .. " = " .. EmitTableLiteral(def.value, "    ") .. " end")
        end
    end

    add("")
    add("    -- Config refresh stub (config changes take effect on /reload)")
    add("    function ns.RefreshConfig() end")
    add("")
    add("    -- Check enabled flag")
    add("    if not db.enabled then return end")
    add("")

    -- Global WeakAuras API stubs (set up once, before any aura code runs)
    if AnalysisNeedsWA(analysis) then
        -- Emit aura data registry so GetData can return subRegions, config, etc.
        add("    -- Aura data registry (for WeakAuras.GetData compatibility)")
        add("    local _auraData = {")
        for _, aura in ipairs(analysis.auras) do
            add("        [" .. Quoted(aura.id) .. "] = {")
            add("            id = " .. Quoted(aura.id) .. ",")
            add("            regionType = " .. Quoted(aura.regionType or "unknown") .. ",")
            if aura.subRegions then
                add("            subRegions = " .. EmitTableLiteral(aura.subRegions, "            ") .. ",")
            end
            if aura.config then
                add("            config = " .. EmitTableLiteral(aura.config, "            ") .. ",")
            end
            add("        },")
        end
        add("    }")
        add("")

        add("    -- WeakAuras API compatibility (stubs when WeakAuras addon is not installed)")
        add("    if not WeakAuras then")
        add("        WeakAuras = setmetatable({")
        add('            IsOptionsOpen = function() return false end,')
        add('            GetData = function(id) return _auraData[id] or {} end,')
        add('            GetRegion = function(id)')
        add('                local r = WeakAuras.regions and WeakAuras.regions[id]')
        add('                return r and r.region')
        add('            end,')
        add('            ScanEvents = function(event, ...)')
        add('                for _, frame in ipairs(WeakAuras._scanEventFrames) do')
        add('                    local handler = frame:GetScript("OnEvent")')
        add('                    if handler then handler(frame, event, ...) end')
        add('                end')
        add('            end,')
        add('            WatchGCD = function() end,')
        add('            WatchSpellCooldown = function() end,')
        add('            WatchItemCooldown = function() end,')
        add('            WatchRuneDuration = function() end,')
        add('            StopMotion = function() end,')
        add('            prettyPrint = function(...) print(...) end,')
        add('            IsRetail = function() return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE end,')
        add('            IsClassicEra = function() return false end,')
        add('            IsCataClassic = function() return false end,')
        add('            me = UnitGUID("player"),')
        add('            myGUID = UnitGUID("player"),')
        add("            regions = {},")
        add("            currentStates = {},")
        add("            _scanEventFrames = {},")
        add("        }, {")
        add("            __index = function(t, k)")
        add("                -- Auto-stub unknown methods as no-ops to prevent errors")
        add("                local v = rawget(t, k)")
        add("                if v == nil then")
        add("                    v = function() end")
        add("                    rawset(t, k, v)")
        add("                end")
        add("                return v")
        add("            end,")
        add("        })")
        add("    end")
        add("")
    end

    if analysis.isGroup then
        -- Container frame for groups
        add("    -- Container frame for group: " .. (analysis.groupId or "WAGroup"))
        add("    local container = CreateFrame(\"Frame\", nil, UIParent)")
        add('    container:SetPoint("CENTER", UIParent, "CENTER", db.xOff, db.yOff)')
        add("    container:SetSize(1, 1)  -- Children position themselves via offsets")
        add("    ns.container = container")
        add("")

        for i, aura in ipairs(analysis.auras) do
            local auraLines = GenAuraCode(aura, i, "container")
            for _, al in ipairs(auraLines) do
                add("    " .. al)
            end
            if i < #analysis.auras then add("") end
        end
    else
        -- Single aura — wrap in a container for Options.lua repositioning
        add("    local container = CreateFrame(\"Frame\", nil, UIParent)")
        add('    container:SetPoint("CENTER", UIParent, "CENTER", db.xOff, db.yOff)')
        add("    container:SetSize(1, 1)")
        add("    ns.container = container")
        add("")
        for i, aura in ipairs(analysis.auras) do
            local auraLines = GenAuraCode(aura, i, "container")
            for _, al in ipairs(auraLines) do
                add("    " .. al)
            end
        end
    end

    add("end")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- AuthorOption emitters (one per option type)
---------------------------------------------------------------------------

local function EmitRangeOption(add, projectName, opt)
    local settingId = projectName .. "_cfg_" .. opt.key
    add("")
    add("    -- Slider: " .. (opt.name or opt.key))
    add('    do')
    add('        local s = Settings.RegisterAddOnSetting(category, "' .. settingId .. '", "' .. opt.key .. '", db.config, type(0), ' .. Quoted(opt.name or opt.key) .. ', ' .. tostring(opt.default or 0) .. ')')
    add("        local opts = Settings.CreateSliderOptions(" .. (opt.min or 0) .. ", " .. (opt.max or 100) .. ", " .. (opt.step or 1) .. ")")
    add('        Settings.CreateSlider(category, s, opts, ' .. Quoted(opt.name or opt.key) .. ')')
    add('        Settings.SetOnValueChangedCallback("' .. settingId .. '", function() ns.RefreshConfig() end)')
    add("    end")
end

local function EmitToggleOption(add, projectName, opt)
    local settingId = projectName .. "_cfg_" .. opt.key
    add("")
    add("    -- Toggle: " .. (opt.name or opt.key))
    add('    do')
    add('        local s = Settings.RegisterAddOnSetting(category, "' .. settingId .. '", "' .. opt.key .. '", db.config, type(true), ' .. Quoted(opt.name or opt.key) .. ', ' .. tostring(opt.default and true or false) .. ')')
    add('        Settings.CreateCheckbox(category, s, ' .. Quoted(opt.name or opt.key) .. ')')
    add('        Settings.SetOnValueChangedCallback("' .. settingId .. '", function() ns.RefreshConfig() end)')
    add("    end")
end

local function EmitSelectOption(add, projectName, opt)
    local settingId = projectName .. "_cfg_" .. opt.key
    add("")
    add("    -- Dropdown: " .. (opt.name or opt.key))
    add("    do")
    add('        local s = Settings.RegisterAddOnSetting(category, "' .. settingId .. '", "' .. opt.key .. '", db.config, type(0), ' .. Quoted(opt.name or opt.key) .. ', ' .. tostring(opt.default or 1) .. ')')
    add("        local function GetOptions()")
    add("            local container = Settings.CreateControlTextContainer()")
    if opt.values then
        for i, v in ipairs(opt.values) do
            add("            container:Add(" .. i .. ", " .. Quoted(v) .. ")")
        end
    end
    add("            return container:GetData()")
    add("        end")
    add('        Settings.CreateDropdown(category, s, GetOptions, ' .. Quoted(opt.name or opt.key) .. ')')
    add('        Settings.SetOnValueChangedCallback("' .. settingId .. '", function() ns.RefreshConfig() end)')
    add("    end")
end

-- EmitColorOption is a no-op; colors are handled in bulk by EmitColorEditor
local function EmitColorOption() end

-- Emit a standalone color editor frame containing all color options
local function EmitColorEditor(add, projectName, colorOpts)
    if not colorOpts or #colorOpts == 0 then return end

    add("")
    add("    -- ========== Color Editor Panel ==========")
    add("    do")
    add('        local editor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")')
    add("        editor:SetSize(260, " .. (40 + #colorOpts * 26) .. ")")
    add('        editor:SetPoint("CENTER")')
    add('        editor:SetFrameStrata("DIALOG")')
    add("        editor:SetBackdrop({ bgFile = \"Interface\\\\Tooltips\\\\UI-Tooltip-Background\", edgeFile = \"Interface\\\\Tooltips\\\\UI-Tooltip-Border\", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })")
    add("        editor:SetBackdropColor(0.1, 0.1, 0.1, 0.95)")
    add("        editor:SetMovable(true)")
    add("        editor:EnableMouse(true)")
    add('        editor:RegisterForDrag("LeftButton")')
    add("        editor:SetScript(\"OnDragStart\", editor.StartMoving)")
    add("        editor:SetScript(\"OnDragStop\", editor.StopMovingOrSizing)")
    add("        editor:Hide()")
    add("        ns.colorEditor = editor")
    add("")
    add('        local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")')
    add('        title:SetPoint("TOP", 0, -8)')
    add('        title:SetText("Color Settings")')
    add("")
    add('        local closeBtn = CreateFrame("Button", nil, editor, "UIPanelCloseButton")')
    add('        closeBtn:SetPoint("TOPRIGHT", -2, -2)')
    add("")

    for i, opt in ipairs(colorOpts) do
        local def = opt.default or { 1, 1, 1, 1 }
        local defStr = (def[1] or 1) .. ", " .. (def[2] or 1) .. ", " .. (def[3] or 1) .. ", " .. (def[4] or 1)
        local yOff = -28 - (i - 1) * 26
        add("        -- " .. (opt.name or opt.key))
        add("        do")
        add("            local colorKey = " .. Quoted(opt.key))
        add("            local colorDef = { " .. defStr .. " }")
        add('            local row = CreateFrame("Frame", nil, editor)')
        add("            row:SetSize(240, 24)")
        add('            row:SetPoint("TOPLEFT", 10, ' .. yOff .. ')')
        add('            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")')
        add('            label:SetPoint("LEFT")')
        add("            label:SetText(" .. Quoted(opt.name or opt.key) .. ")")
        add('            local swatch = CreateFrame("Button", nil, row)')
        add("            swatch:SetSize(20, 20)")
        add('            swatch:SetPoint("RIGHT")')
        add('            local tex = swatch:CreateTexture(nil, "OVERLAY")')
        add("            tex:SetAllPoints()")
        add("            local function UpdateSwatch()")
        add("                local c = db.config[colorKey] or colorDef")
        add("                tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)")
        add("            end")
        add('            swatch:SetScript("OnClick", function()')
        add("                local c = db.config[colorKey] or colorDef")
        add("                ColorPickerFrame:SetupColorPickerAndShow({")
        add("                    r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, opacity = c[4] or 1,")
        add("                    hasOpacity = true,")
        add("                    swatchFunc = function()")
        add("                        local r, g, b = ColorPickerFrame:GetColorRGB()")
        add("                        local a = ColorPickerFrame:GetColorAlpha()")
        add("                        db.config[colorKey] = { r, g, b, a }")
        add("                        UpdateSwatch()")
        add("                    end,")
        add("                    cancelFunc = function(prev)")
        add("                        db.config[colorKey] = { prev.r, prev.g, prev.b, prev.opacity }")
        add("                        UpdateSwatch()")
        add("                    end,")
        add("                })")
        add("            end)")
        add("            UpdateSwatch()")
        add("        end")
    end
    add("    end")

    -- Add a toggle in the Settings panel to open/close the editor
    local settingId = projectName .. "_editColors"
    add("")
    add("    -- Toggle to open/close the color editor")
    add('    do')
    add('        local s = Settings.RegisterAddOnSetting(category, "' .. settingId .. '", "editColors", db, type(true), "Edit Colors...", false)')
    add('        Settings.CreateCheckbox(category, s, "Open a floating panel to edit color options. Changes take effect after /reload.")')
    add('        Settings.SetOnValueChangedCallback("' .. settingId .. '", function(_, _, value)')
    add("            if ns.colorEditor then ns.colorEditor:SetShown(value) end")
    add("        end)")
    add("    end")
end

local function EmitDescriptionOption(add, opt)
    local text = (opt.text or ""):match("^%s*(.-)%s*$") or ""
    if text == "" or text == "*" then return end  -- skip empty/decorative descriptions
    add("")
    add("    -- Section: " .. text:gsub("\n", " "))
    add("    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(" .. Quoted(text) .. "))")
end

---------------------------------------------------------------------------
-- Options.lua generation
---------------------------------------------------------------------------

local function GenerateOptions(analysis, projectName)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local dbName = projectName .. "DB"

    add("local ADDON_NAME, ns = ...")
    add("")
    add('local DB_NAME = "' .. dbName .. '"')
    add("")
    add("local function GetDB()")
    add("    return _G[DB_NAME]")
    add("end")
    add("")
    add("-- Wait for DB to be ready, then register")
    add('local f = CreateFrame("Frame")')
    add('f:RegisterEvent("ADDON_LOADED")')
    add('f:SetScript("OnEvent", function(self, event, addon)')
    add("    if addon ~= ADDON_NAME then return end")
    add('    self:UnregisterEvent("ADDON_LOADED")')
    add("")
    add("    if not _G[DB_NAME] then _G[DB_NAME] = {} end")
    add("    local db = GetDB()")
    add("    if not db.config then db.config = {} end")
    add('    local category, layout = Settings.RegisterVerticalLayoutCategory("' .. projectName .. '")')
    add("")
    add("    -- Enabled toggle")
    add('    local enabledSetting = Settings.RegisterAddOnSetting(category, "' .. projectName .. '_enabled", "enabled", db, type(true), "Show Auras", true)')
    add('    Settings.CreateCheckbox(category, enabledSetting, "Show or hide the aura display")')
    add('    Settings.SetOnValueChangedCallback("' .. projectName .. '_enabled", function(_, setting, value)')
    add("        if ns.container then")
    add("            ns.container:SetShown(value)")
    add("        end")
    add("    end)")
    add("")
    add("    -- X Offset slider")
    add('    local xOffSetting = Settings.RegisterAddOnSetting(category, "' .. projectName .. '_xOff", "xOff", db, type(0), "X Offset", 0)')
    add("    local xOptions = Settings.CreateSliderOptions(-800, 800, 1)")
    add('    Settings.CreateSlider(category, xOffSetting, xOptions, "Horizontal offset from screen center")')
    add('    Settings.SetOnValueChangedCallback("' .. projectName .. '_xOff", function(_, setting, value)')
    add("        if ns.container then")
    add("            ns.container:ClearAllPoints()")
    add('            ns.container:SetPoint("CENTER", UIParent, "CENTER", db.xOff, db.yOff)')
    add("        end")
    add("    end)")
    add("")
    add("    -- Y Offset slider")
    add('    local yOffSetting = Settings.RegisterAddOnSetting(category, "' .. projectName .. '_yOff", "yOff", db, type(0), "Y Offset", 0)')
    add("    local yOptions = Settings.CreateSliderOptions(-500, 500, 1)")
    add('    Settings.CreateSlider(category, yOffSetting, yOptions, "Vertical offset from screen center")')
    add('    Settings.SetOnValueChangedCallback("' .. projectName .. '_yOff", function(_, setting, value)')
    add("        if ns.container then")
    add("            ns.container:ClearAllPoints()")
    add('            ns.container:SetPoint("CENTER", UIParent, "CENTER", db.xOff, db.yOff)')
    add("        end")
    add("    end)")
    add("")
    -- Emit authorOptions-based controls
    local authorOpts = CollectAuthorOptions(analysis)
    local colorOpts = {}
    if authorOpts then
        add("    -- ========== Aura Configuration ==========")
        add("    -- NOTE: Config changes (except Enabled/X/Y Offset) take effect after /reload")
        for _, opt in ipairs(authorOpts) do
            if opt.type == "range" then
                EmitRangeOption(add, projectName, opt)
            elseif opt.type == "toggle" then
                EmitToggleOption(add, projectName, opt)
            elseif opt.type == "select" then
                EmitSelectOption(add, projectName, opt)
            elseif opt.type == "color" then
                colorOpts[#colorOpts + 1] = opt
            elseif opt.type == "description" then
                EmitDescriptionOption(add, opt)
            elseif opt.type == "input" then
                add("")
                add("    -- TODO: text input option (" .. Quoted(opt.name or opt.key) .. ") -- string binding not supported by Settings API")
            end
        end
        add("")
    end

    -- Emit standalone color editor panel (if any color options exist)
    EmitColorEditor(add, projectName, colorOpts)
    add("")

    add("    Settings.RegisterAddOnCategory(category)")
    add("end)")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function WACodeGen:Generate(analysis, projectName)
    if not analysis or not analysis.auras then
        return nil, "Invalid analysis data"
    end

    projectName = projectName or "WAImport"

    return {
        { name = projectName .. ".toc", code = GenerateTOC(projectName) },
        { name = "Init.lua", code = GenerateInit(analysis, projectName) },
        { name = "Options.lua", code = GenerateOptions(analysis, projectName) },
    }
end

function WACodeGen:GenerateAllFilesText(analysis, projectName)
    local files = self:Generate(analysis, projectName)
    if not files then return "" end

    local parts = {}
    for _, file in ipairs(files) do
        parts[#parts + 1] = "======== FILE: " .. file.name .. " ========"
        parts[#parts + 1] = file.code
        parts[#parts + 1] = ""
    end
    return table.concat(parts, "\n")
end
