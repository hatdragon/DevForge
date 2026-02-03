local _, DF = ...

DF.InspectorProps = {}

local Props = DF.InspectorProps

local SG = DF.SecretGuard

-- Common events to check
local COMMON_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN", "PLAYER_LOGOUT",
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_HEALTH", "UNIT_POWER_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "CHAT_MSG_SAY", "CHAT_MSG_PARTY", "CHAT_MSG_GUILD",
    "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "ACTIONBAR_UPDATE_STATE", "SPELL_UPDATE_USABLE",
    "UPDATE_MOUSEOVER_UNIT", "CURSOR_CHANGED",
}

-- Common script handlers to check
local COMMON_SCRIPTS = {
    "OnShow", "OnHide", "OnUpdate", "OnEvent",
    "OnClick", "OnEnter", "OnLeave",
    "OnMouseDown", "OnMouseUp", "OnMouseWheel",
    "OnDragStart", "OnDragStop",
    "OnSizeChanged", "OnKeyDown", "OnKeyUp",
    "OnChar", "OnTextChanged", "OnValueChanged",
    "OnEditFocusGained", "OnEditFocusLost",
}

-- Safe property getter
local function SafeGet(obj, method, ...)
    local val, ok, err = SG:SafeGet(obj, method, ...)
    if err == "secret" then
        return DF.Colors.secret .. "[secret]|r", true
    end
    if not ok then
        return DF.Colors.dim .. "[error]|r", true
    end
    return val, false
end

local function FormatVal(val)
    if val == nil then return DF.Colors.nilVal .. "nil|r" end
    if type(val) == "boolean" then
        return val and (DF.Colors.boolTrue .. "true|r") or (DF.Colors.boolFalse .. "false|r")
    end
    if type(val) == "number" then
        return DF.Colors.number .. string.format("%.2f", val) .. "|r"
    end
    if type(val) == "string" then
        return DF.Colors.string .. '"' .. val .. '"|r'
    end
    return DF.Colors.text .. tostring(val) .. "|r"
end

-- Build property sections for a frame
function Props:BuildSections(frame)
    if not frame then return {} end

    local sections = {}

    -- Identity
    local identity = { title = "Identity", props = {} }
    local name, nameErr = SafeGet(frame, "GetName")
    identity.props[#identity.props + 1] = { key = "Name", value = nameErr and name or FormatVal(name) }

    local objType, typeErr = SafeGet(frame, "GetObjectType")
    identity.props[#identity.props + 1] = { key = "Type", value = typeErr and objType or FormatVal(objType) }

    local parent, parentOk, parentErrMsg = SafeGet(frame, "GetParent")
    if parentErrMsg then
        identity.props[#identity.props + 1] = { key = "Parent", value = parent or FormatVal(nil) }
    elseif parent then
        local pnOk, pn = pcall(function() return parent:GetName() end)
        local parentName = (pnOk and pn) or tostring(parent)
        local parentRef = parent
        identity.props[#identity.props + 1] = {
            key = "Parent",
            value = FormatVal(parentName) .. "  [Go]",
            onClick = function()
                DF.EventBus:Fire("DF_INSPECTOR_NAVIGATE", parentRef)
            end,
        }
    else
        identity.props[#identity.props + 1] = { key = "Parent", value = FormatVal(nil) }
    end

    sections[#sections + 1] = identity

    -- Texture properties (for Texture regions)
    local isTexture = objType == "Texture" or objType == "MaskTexture"
    if isTexture then
        local texSection = { title = "Texture", props = {} }

        -- Gather values
        local atlas, atlasErr = SafeGet(frame, "GetAtlas")
        local hasAtlas = not atlasErr and type(atlas) == "string" and atlas ~= ""

        local texPath, texErr = SafeGet(frame, "GetTexture")
        local texFileID, texFileIDErr = SafeGet(frame, "GetTextureFileID")
        local isRenderTarget = not texErr and type(texPath) == "string" and texPath:match("^RT")
        local hasTexPath = not texErr and texPath ~= nil and texPath ~= "" and texPath ~= 0 and not isRenderTarget
        local hasFileID = not texFileIDErr and type(texFileID) == "number" and texFileID ~= 0

        -- Atlas row (always shown)
        if hasAtlas then
            texSection.props[#texSection.props + 1] = {
                key = "Atlas",
                value = DF.Colors.string .. '"' .. atlas .. '"|r  [View]',
                onClick = function()
                    DF.EventBus:Fire("DF_SHOW_IN_TEXTURE_BROWSER", { path = atlas, isAtlas = true })
                end,
            }
        else
            texSection.props[#texSection.props + 1] = {
                key = "Atlas",
                value = atlasErr and atlas or FormatVal(nil),
            }
        end

        -- Texture row (always shown)
        if hasTexPath then
            local display
            if type(texPath) == "number" then
                display = DF.Colors.number .. texPath .. "|r"
            else
                display = DF.Colors.string .. '"' .. tostring(texPath) .. '"|r'
            end
            texSection.props[#texSection.props + 1] = {
                key = "Texture",
                value = display .. "  [View]",
                onClick = function()
                    DF.EventBus:Fire("DF_SHOW_IN_TEXTURE_BROWSER", { path = texPath, isAtlas = false })
                end,
            }
        elseif isRenderTarget then
            texSection.props[#texSection.props + 1] = {
                key = "Texture",
                value = DF.Colors.dim .. texPath .. " (render target)|r",
            }
        else
            texSection.props[#texSection.props + 1] = {
                key = "Texture",
                value = texErr and texPath or FormatVal(nil),
            }
        end

        -- FileID row (shown when it provides extra info)
        if hasFileID then
            texSection.props[#texSection.props + 1] = {
                key = "FileID",
                value = DF.Colors.number .. texFileID .. "|r  [View]",
                onClick = function()
                    DF.EventBus:Fire("DF_SHOW_IN_TEXTURE_BROWSER", { path = texFileID, isAtlas = false })
                end,
            }
        end

        -- Detect PortraitFrame pattern:
        -- texture -> PortraitContainer -> frame with SetPortraitToAsset
        if not hasAtlas and not hasTexPath and not hasFileID and not isRenderTarget then
            local parentOk, parentFrame = pcall(function() return frame:GetParent() end)
            if parentOk and parentFrame then
                local gpOk, grandparent = pcall(function() return parentFrame:GetParent() end)
                if gpOk and grandparent then
                    local hasPortraitAPI = pcall(function() return grandparent.SetPortraitToAsset end)
                        and type(grandparent.SetPortraitToAsset) == "function"
                    if hasPortraitAPI then
                        local gpName = ""
                        local nameOk, gn = pcall(function() return grandparent:GetName() end)
                        gpName = (nameOk and gn) or tostring(grandparent)
                        texSection.props[#texSection.props + 1] = {
                            key = "PortraitFrame",
                            value = DF.Colors.dim .. gpName .. "|r",
                        }
                        texSection.props[#texSection.props + 1] = {
                            key = "Set via",
                            value = DF.Colors.func .. "frame:SetPortraitToAsset(tex)|r "
                                .. DF.Colors.dim .. "or|r "
                                .. DF.Colors.func .. ":SetPortraitAtlasRaw(atlas)|r",
                        }

                        -- Scan grandparent regions for a sibling portrait texture
                        -- that actually has a file set (e.g. MacroFramePortrait with
                        -- file="Interface\MacroFrame\MacroFrame-Icon" defined in XML)
                        local regOk, regions = pcall(function() return { grandparent:GetRegions() } end)
                        if regOk and regions then
                            for _, region in ipairs(regions) do
                                if region ~= frame then
                                    local rTypeOk, rType = pcall(function() return region:GetObjectType() end)
                                    if rTypeOk and rType == "Texture" then
                                        local rTexOk, rTex = pcall(function() return region:GetTexture() end)
                                        local rAtlasOk, rAtlas = pcall(function() return region:GetAtlas() end)
                                        local rHasTex = rTexOk and rTex ~= nil and rTex ~= "" and rTex ~= 0
                                        local rHasAtlas = rAtlasOk and type(rAtlas) == "string" and rAtlas ~= ""
                                        if rHasTex or rHasAtlas then
                                            local rName = ""
                                            local rnOk, rn = pcall(function() return region:GetDebugName() end)
                                            if not rnOk or not rn or rn == "" then
                                                rnOk, rn = pcall(function() return region:GetName() end)
                                            end
                                            rName = (rnOk and rn) or tostring(region)
                                            -- Only surface textures that look portrait-related
                                            if rName:lower():find("portrait") then
                                                local display
                                                if rHasAtlas then
                                                    display = DF.Colors.string .. '"' .. rAtlas .. '"|r  [View]'
                                                elseif type(rTex) == "number" then
                                                    display = DF.Colors.number .. rTex .. "|r  [View]"
                                                else
                                                    display = DF.Colors.string .. '"' .. tostring(rTex) .. '"|r  [View]'
                                                end
                                                local clickPath = rHasAtlas and rAtlas or rTex
                                                local clickIsAtlas = rHasAtlas
                                                texSection.props[#texSection.props + 1] = {
                                                    key = "Active (" .. rName .. ")",
                                                    value = display,
                                                    onClick = function()
                                                        DF.EventBus:Fire("DF_SHOW_IN_TEXTURE_BROWSER", {
                                                            path = clickPath, isAtlas = clickIsAtlas,
                                                        })
                                                    end,
                                                }
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Draw layer
        local layerOk, layer, sublayer = pcall(function() return frame:GetDrawLayer() end)
        if layerOk and layer then
            local layerStr = FormatVal(layer)
            if sublayer and sublayer ~= 0 then
                layerStr = layerStr .. " (" .. FormatVal(sublayer) .. ")"
            end
            texSection.props[#texSection.props + 1] = { key = "DrawLayer", value = layerStr }
        end

        -- TexCoord
        local coordOk, l, r, t, b = pcall(function() return frame:GetTexCoord() end)
        if coordOk and l then
            texSection.props[#texSection.props + 1] = {
                key = "TexCoord",
                value = string.format("%s, %s, %s, %s",
                    FormatVal(l), FormatVal(r), FormatVal(t), FormatVal(b)),
            }
        end

        -- Blend mode
        local blend, blendErr = SafeGet(frame, "GetBlendMode")
        if not blendErr and blend then
            texSection.props[#texSection.props + 1] = { key = "BlendMode", value = FormatVal(blend) }
        end

        -- Vertex color
        local vcOk, vcR, vcG, vcB, vcA = pcall(function() return frame:GetVertexColor() end)
        if vcOk and vcR then
            texSection.props[#texSection.props + 1] = {
                key = "VertexColor",
                value = string.format("%s, %s, %s, %s",
                    FormatVal(vcR), FormatVal(vcG), FormatVal(vcB), FormatVal(vcA)),
            }
        end

        sections[#sections + 1] = texSection
    end

    -- Geometry
    local geometry = { title = "Geometry", props = {} }

    local w, wErr = SafeGet(frame, "GetWidth")
    geometry.props[#geometry.props + 1] = { key = "Width", value = wErr and w or FormatVal(w) }

    local h, hErr = SafeGet(frame, "GetHeight")
    geometry.props[#geometry.props + 1] = { key = "Height", value = hErr and h or FormatVal(h) }

    local left, leftErr = SafeGet(frame, "GetLeft")
    geometry.props[#geometry.props + 1] = { key = "Left", value = leftErr and left or FormatVal(left) }

    local top, topErr = SafeGet(frame, "GetTop")
    geometry.props[#geometry.props + 1] = { key = "Top", value = topErr and top or FormatVal(top) }

    local right, rightErr = SafeGet(frame, "GetRight")
    geometry.props[#geometry.props + 1] = { key = "Right", value = rightErr and right or FormatVal(right) }

    local bottom, bottomErr = SafeGet(frame, "GetBottom")
    geometry.props[#geometry.props + 1] = { key = "Bottom", value = bottomErr and bottom or FormatVal(bottom) }

    local scale, scaleErr = SafeGet(frame, "GetScale")
    geometry.props[#geometry.props + 1] = { key = "Scale", value = scaleErr and scale or FormatVal(scale) }

    local effScale, esErr = SafeGet(frame, "GetEffectiveScale")
    geometry.props[#geometry.props + 1] = { key = "Eff. Scale", value = esErr and effScale or FormatVal(effScale) }

    sections[#sections + 1] = geometry

    -- Strata / Visibility (only for Frame-derived objects)
    local hasStrata = pcall(function() return frame.GetFrameStrata end) and frame.GetFrameStrata
    if hasStrata then
        local vis = { title = "Strata / Visibility", props = {} }

        local strata, strataErr = SafeGet(frame, "GetFrameStrata")
        vis.props[#vis.props + 1] = { key = "Strata", value = strataErr and strata or FormatVal(strata) }

        local level, levelErr = SafeGet(frame, "GetFrameLevel")
        vis.props[#vis.props + 1] = { key = "Level", value = levelErr and level or FormatVal(level) }

        local alpha, alphaErr = SafeGet(frame, "GetAlpha")
        vis.props[#vis.props + 1] = { key = "Alpha", value = alphaErr and alpha or FormatVal(alpha) }

        local effAlpha, eaErr = SafeGet(frame, "GetEffectiveAlpha")
        vis.props[#vis.props + 1] = { key = "Eff. Alpha", value = eaErr and effAlpha or FormatVal(effAlpha) }

        local shown, shownErr = SafeGet(frame, "IsShown")
        vis.props[#vis.props + 1] = { key = "IsShown", value = shownErr and shown or FormatVal(shown) }

        local visible, visErr = SafeGet(frame, "IsVisible")
        vis.props[#vis.props + 1] = { key = "IsVisible", value = visErr and visible or FormatVal(visible) }

        local mouse, mouseErr = SafeGet(frame, "IsMouseEnabled")
        vis.props[#vis.props + 1] = { key = "Mouse Enabled", value = mouseErr and mouse or FormatVal(mouse) }

        local kb, kbErr = SafeGet(frame, "IsKeyboardEnabled")
        vis.props[#vis.props + 1] = { key = "Keyboard", value = kbErr and kb or FormatVal(kb) }

        sections[#sections + 1] = vis
    end

    -- Anchors
    local hasPoints = pcall(function() return frame.GetNumPoints end) and frame.GetNumPoints
    if hasPoints then
        local anchors = { title = "Anchors", props = {} }
        local numPts, ptsErr = SafeGet(frame, "GetNumPoints")
        if not ptsErr and numPts and numPts > 0 then
            for i = 1, numPts do
                local ok, point, relTo, relPoint, xOff, yOff = pcall(function()
                    return frame:GetPoint(i)
                end)
                if ok then
                    local relName = "?"
                    if relTo then
                        local nameOk2, nameResult2 = pcall(function() return relTo:GetName() end)
                        relName = (nameOk2 and nameResult2) or tostring(relTo)
                    end
                    local anchorStr = string.format("%s -> %s.%s (%s, %s)",
                        tostring(point), relName, tostring(relPoint),
                        FormatVal(xOff), FormatVal(yOff))
                    anchors.props[#anchors.props + 1] = { key = "Point " .. i, value = anchorStr }
                end
            end
        else
            anchors.props[#anchors.props + 1] = { key = "Points", value = ptsErr and numPts or FormatVal(0) }
        end
        sections[#sections + 1] = anchors
    end

    -- Events (check common events)
    local hasEventReg = pcall(function() return frame.IsEventRegistered end) and frame.IsEventRegistered
    if hasEventReg then
        local events = { title = "Registered Events", props = {} }
        local found = false
        for _, event in ipairs(COMMON_EVENTS) do
            local ok, registered = pcall(function() return frame:IsEventRegistered(event) end)
            if ok and registered then
                events.props[#events.props + 1] = { key = event, value = DF.Colors.boolTrue .. "true|r" }
                found = true
            end
        end
        if not found then
            events.props[#events.props + 1] = { key = "(none detected)", value = DF.Colors.dim .. "checked " .. #COMMON_EVENTS .. " common events|r" }
        end
        sections[#sections + 1] = events
    end

    -- Scripts
    local hasScript = pcall(function() return frame.HasScript end) and frame.HasScript
    if hasScript then
        local scripts = { title = "Scripts", props = {} }
        local found = false
        for _, handler in ipairs(COMMON_SCRIPTS) do
            local ok, has = pcall(function() return frame:HasScript(handler) end)
            if ok and has then
                local scriptOk, scriptFn = pcall(function() return frame:GetScript(handler) end)
                if scriptOk and scriptFn then
                    scripts.props[#scripts.props + 1] = { key = handler, value = DF.Colors.func .. tostring(scriptFn) .. "|r" }
                    found = true
                elseif scriptOk then
                    scripts.props[#scripts.props + 1] = { key = handler, value = DF.Colors.dim .. "(no handler)|r" }
                end
            end
        end
        if not found then
            scripts.props[#scripts.props + 1] = { key = "(none)", value = DF.Colors.dim .. "no script handlers attached|r" }
        end
        sections[#sections + 1] = scripts
    end

    return sections
end
