local _, DF = ...

DF.WADecode = {}

local WADecode = DF.WADecode

local LibDeflate, LibSerialize

---------------------------------------------------------------------------
-- Library resolution (lazy, once per session)
---------------------------------------------------------------------------

local function EnsureLibs()
    if LibDeflate and LibSerialize then return true end

    local ok, stub = pcall(function() return LibStub end)
    if not ok or not stub then
        return false, "LibStub not loaded"
    end

    LibDeflate = stub("LibDeflate", true)
    if not LibDeflate then
        return false, "LibDeflate not found (is it listed in the TOC?)"
    end

    LibSerialize = stub("LibSerialize", true)
    if not LibSerialize then
        return false, "LibSerialize not found (is it listed in the TOC?)"
    end

    return true
end

---------------------------------------------------------------------------
-- Decode pipeline
---------------------------------------------------------------------------

function WADecode:Decode(importString)
    if not importString or importString == "" then
        return false, nil, "Empty import string"
    end

    -- Trim whitespace
    importString = importString:match("^%s*(.-)%s*$")

    -- Validate prefix and extract encoded payload
    -- Formats: "!WA:2!<data>" (versioned) or "!<data>" (legacy)
    local encoded
    if importString:sub(1, 6) == "!WA:2!" then
        encoded = importString:sub(7)
    elseif importString:sub(1, 1) == "!" then
        encoded = importString:sub(2)
    else
        return false, nil, "Invalid format: WeakAuras export strings must start with '!'"
    end

    -- Ensure libraries are available
    local libOk, libErr = EnsureLibs()
    if not libOk then
        return false, nil, libErr
    end

    -- Step 1: Base-N decode (DecodeForPrint)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then
        return false, nil, "Failed to decode base encoding (invalid characters?)"
    end

    -- Step 2: Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false, nil, "Failed to decompress data (corrupt or truncated?)"
    end

    -- Step 3: Deserialize
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then
        return false, nil, "Failed to deserialize data: " .. tostring(data)
    end

    return true, data, nil
end

---------------------------------------------------------------------------
-- Analyze: normalize WA data into a clean descriptor
---------------------------------------------------------------------------

local function ParseTriggers(triggerList)
    local triggers = {}
    if not triggerList then return triggers end

    for i = 1, #triggerList do
        local entry = triggerList[i]
        local t = entry and entry.trigger
        if t then
            local info = {
                type = t.type or "unknown",
                event = t.event,
                unit = t.unit,
                auranames = t.auranames,
                auraspellids = t.auraspellids,
                debuffType = t.debuffType,
                matchesShowOn = t.matchesShowOn,
                spellName = t.realSpellName or t.spellName,
                custom = t.custom,
                customName = t.customName,
            }
            triggers[#triggers + 1] = info
        end
    end

    return triggers
end

local function ParseLoadConditions(load)
    if not load then return nil, nil end

    local loadClass, loadSpec

    if load.class then
        if load.class.single then
            loadClass = { load.class.single }
        elseif load.class.multi then
            loadClass = {}
            for cls, enabled in pairs(load.class.multi) do
                if enabled then
                    loadClass[#loadClass + 1] = cls
                end
            end
        end
    end

    if load.spec then
        if load.spec.single then
            loadSpec = { load.spec.single }
        elseif load.spec.multi then
            loadSpec = {}
            for spec, enabled in pairs(load.spec.multi) do
                if enabled then
                    loadSpec[#loadSpec + 1] = spec
                end
            end
        end
    end

    return loadClass, loadSpec
end

local function ExtractCustomCode(actions)
    local initCode, onShowCode, onHideCode
    if not actions then return initCode, onShowCode, onHideCode end

    if actions.init and actions.init.do_custom and actions.init.custom then
        initCode = actions.init.custom
    end
    if actions.start and actions.start.do_custom and actions.start.custom then
        onShowCode = actions.start.custom
    end
    if actions.finish and actions.finish.do_custom and actions.finish.custom then
        onHideCode = actions.finish.custom
    end

    return initCode, onShowCode, onHideCode
end

local function ExtractConfig(d)
    -- WA stores user config values in d.config (from custom options)
    if not d.config or type(d.config) ~= "table" then return nil end
    -- Only keep simple key-value pairs (string/number/boolean)
    local config = {}
    local hasAny = false
    for k, v in pairs(d.config) do
        local vt = type(v)
        if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
            config[k] = v
            hasAny = true
        end
    end
    return hasAny and config or nil
end

local function ExtractAuthorOptions(d)
    if not d.authorOptions or type(d.authorOptions) ~= "table" then return nil end
    local opts = {}
    for i = 1, #d.authorOptions do
        local ao = d.authorOptions[i]
        if ao and ao.type then
            local t = ao.type
            if t == "range" or t == "number" then
                opts[#opts + 1] = {
                    type = "range",
                    key = ao.key,
                    name = ao.name or ao.key,
                    default = tonumber(ao.default) or 0,
                    min = tonumber(ao.min) or 0,
                    max = tonumber(ao.max) or 100,
                    step = tonumber(ao.step) or 1,
                }
            elseif t == "toggle" then
                opts[#opts + 1] = {
                    type = "toggle",
                    key = ao.key,
                    name = ao.name or ao.key,
                    default = ao.default and true or false,
                }
            elseif t == "color" then
                local def = ao.default
                if type(def) ~= "table" then def = { 1, 1, 1, 1 } end
                opts[#opts + 1] = {
                    type = "color",
                    key = ao.key,
                    name = ao.name or ao.key,
                    default = { def[1] or def.r or 1, def[2] or def.g or 1, def[3] or def.b or 1, def[4] or def.a or 1 },
                }
            elseif t == "select" then
                local vals = {}
                if ao.values then
                    for j = 1, #ao.values do
                        vals[j] = tostring(ao.values[j])
                    end
                end
                opts[#opts + 1] = {
                    type = "select",
                    key = ao.key,
                    name = ao.name or ao.key,
                    default = tonumber(ao.default) or 1,
                    values = vals,
                }
            elseif t == "input" then
                opts[#opts + 1] = {
                    type = "input",
                    key = ao.key,
                    name = ao.name or ao.key,
                    default = tostring(ao.default or ""),
                }
            elseif t == "description" then
                opts[#opts + 1] = {
                    type = "description",
                    text = ao.text or "",
                    fontSize = ao.fontSize or "medium",
                }
            -- space/header: decorative, skip
            end
        end
    end
    return #opts > 0 and opts or nil
end

local function DetectWATextures(d)
    local found = {}
    local seen = {}
    local function check(s)
        if type(s) ~= "string" then return end
        for path in s:gmatch("[%w_/\\]-WeakAuras[/\\][%w_/\\%.]+") do
            if not seen[path] then
                seen[path] = true
                found[#found + 1] = path
            end
        end
    end
    check(d.texture)
    check(d.displayIcon)
    if d.actions then
        if d.actions.init then check(d.actions.init.custom) end
        if d.actions.start then check(d.actions.start.custom) end
        if d.actions.finish then check(d.actions.finish.custom) end
    end
    for i = 1, (d.triggers and #d.triggers or 0) do
        local entry = d.triggers[i]
        if entry then
            local t = entry.trigger
            if t then check(t.custom); check(t.customName) end
            check(entry.untrigger and entry.untrigger.custom)
        end
    end
    return #found > 0 and found or nil
end

local function ParseConditions(conditions)
    if not conditions or type(conditions) ~= "table" then return nil end
    local results = {}
    for i = 1, #conditions do
        local cond = conditions[i]
        if cond and cond.check and cond.changes then
            local parsed = {
                trigger = cond.check.trigger,
                variable = cond.check.variable,
                value = cond.check.value,
                changes = {},
            }
            for j = 1, #cond.changes do
                local change = cond.changes[j]
                if change and change.property then
                    parsed.changes[#parsed.changes + 1] = {
                        property = change.property,
                        value = change.value,
                    }
                end
            end
            if #parsed.changes > 0 then
                results[#results + 1] = parsed
            end
        end
    end
    return #results > 0 and results or nil
end

local function AnalyzeAura(d)
    local loadClass, loadSpec = ParseLoadConditions(d.load)
    local initCode, onShowCode, onHideCode = ExtractCustomCode(d.actions)

    -- disjunctive and activeTriggerMode live as string keys in the triggers table
    -- disjunctive: "any" (OR), "all" (AND), "custom" (custom logic function)
    -- activeTriggerMode: which trigger provides display values (1-indexed, -10 = auto)
    local disjunctive, activeTriggerMode
    if d.triggers and type(d.triggers) == "table" then
        disjunctive = d.triggers.disjunctive
        activeTriggerMode = d.triggers.activeTriggerMode
    end

    return {
        id = d.id or "Unnamed",
        regionType = d.regionType or "unknown",
        width = d.width,
        height = d.height,
        xOffset = d.xOffset or 0,
        yOffset = d.yOffset or 0,
        anchorPoint = d.anchorPoint or "CENTER",
        selfPoint = d.selfPoint or "CENTER",
        triggers = ParseTriggers(d.triggers),
        disjunctive = disjunctive,
        activeTriggerMode = activeTriggerMode,
        loadClass = loadClass,
        loadSpec = loadSpec,
        initCode = initCode,
        onShowCode = onShowCode,
        onHideCode = onHideCode,
        config = ExtractConfig(d),
        authorOptions = ExtractAuthorOptions(d),
        waTextures = DetectWATextures(d),
        customText = d.customText,
        customTextUpdate = d.customTextUpdate,
        displayText = d.displayText,
        font = d.font,
        fontSize = d.fontSize,
        outline = d.outline,
        color = d.color,
        justify = d.justify,
        conditions = ParseConditions(d.conditions),
        texture = d.texture,
        displayIcon = d.displayIcon,
        rotation = d.rotation,
        alpha = d.alpha,
        desaturate = d.desaturate,
        anchorFrameType = d.anchorFrameType,
    }
end

function WADecode:Analyze(waData)
    if not waData or type(waData) ~= "table" then
        return nil, "Invalid WA data (expected table)"
    end

    local d = waData.d or waData
    local isGroup = (d.regionType == "group" or d.regionType == "dynamicgroup")
    local auras = {}

    if isGroup and waData.c then
        -- Group: extract children
        for i = 1, #waData.c do
            local child = waData.c[i]
            if child and child.d then
                auras[#auras + 1] = AnalyzeAura(child.d)
            elseif child then
                auras[#auras + 1] = AnalyzeAura(child)
            end
        end
    else
        -- Single aura
        auras[#auras + 1] = AnalyzeAura(d)
    end

    return {
        isGroup = isGroup,
        groupId = d.id or "WAImport",
        auras = auras,
    }
end
