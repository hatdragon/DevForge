local _, DF = ...

DF.FrameBuilder = {}

local Builder = DF.FrameBuilder

local FRAME_TYPES = { "Frame", "Button", "StatusBar", "ScrollFrame", "EditBox" }
local ANCHOR_POINTS = { "CENTER", "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

---------------------------------------------------------------------------
-- Element types: child controls that can be added to the frame being
-- built. x/y are stored as "pixels down/right from the frame's TOPLEFT"
-- (positive y = down) and negated when actually anchoring, since that's
-- the intuitive direction for a form designer even though WoW's own
-- TOPLEFT anchor offsets go the other way.
---------------------------------------------------------------------------
local ELEMENT_TYPES = { "Button", "CheckBox", "EditBox", "Label", "Slider" }

---------------------------------------------------------------------------
-- Code -> model parsing helpers, built on the vendored FAIAP Lua tokenizer
-- (Libs/FAIAP/FAIAP.lua, DF.Indent.nextToken/keywords -- already used for
-- live syntax highlighting) rather than raw line regex, so string/comment
-- boundaries are handled correctly (escaped quotes, a stray "end" inside a
-- string, etc.). This isn't a full Lua parser -- GenerateCode/EmitCode only
-- ever emit a narrow, fixed set of statement shapes, so a small walker
-- recognizing those specific shapes in the token stream is enough.
---------------------------------------------------------------------------
local TT = DF.Indent.tokens

-- Tokenize into a flat array of {type, text, isKeyword, startPos, endPos},
-- dropping whitespace/linebreaks/comments (never load-bearing for any of
-- the shapes below -- see ParseCode's flag detection for why that matters).
local function Tokenize(text)
    local out = {}
    local pos = 1
    local len = #text
    while pos <= len do
        local tokenType, nextPos = DF.Indent.nextToken(text, pos)
        if not tokenType then break end
        if tokenType ~= TT.TOKEN_WHITESPACE and tokenType ~= TT.TOKEN_LINEBREAK
            and tokenType ~= TT.TOKEN_COMMENT_SHORT and tokenType ~= TT.TOKEN_COMMENT_LONG then
            local raw = text:sub(pos, nextPos - 1)
            out[#out + 1] = {
                type = tokenType,
                text = raw,
                isKeyword = (tokenType == TT.TOKEN_IDENTIFIER) and DF.Indent.keywords[raw] ~= nil,
                startPos = pos,
                endPos = nextPos - 1,
            }
        end
        pos = nextPos
    end
    return out
end

-- Reverses %q-style escaping on a raw string token's text (delimiters
-- included). Handles the common escapes; a literal embedded newline in a
-- %q string is the one case that won't round-trip perfectly, which is
-- fine for the short one-line label/text values these fields hold.
local function UnescapeLuaString(raw)
    if not raw or #raw < 2 then return raw or "" end
    local inner = raw:sub(2, -2)
    local out, i, n = {}, 1, #inner
    while i <= n do
        local c = inner:sub(i, i)
        if c == "\\" and i < n then
            local nc = inner:sub(i + 1, i + 1)
            if nc == "n" then out[#out+1] = "\n"; i = i + 2
            elseif nc == "t" then out[#out+1] = "\t"; i = i + 2
            elseif nc == "r" then out[#out+1] = "\r"; i = i + 2
            elseif nc:match("%d") then
                local digits = inner:match("^(%d%d?%d?)", i + 1)
                out[#out+1] = string.char(tonumber(digits) % 256)
                i = i + 1 + #digits
            else
                out[#out+1] = nc; i = i + 2
            end
        else
            out[#out+1] = c; i = i + 1
        end
    end
    return table.concat(out)
end

local function IsPunct(tok, tType)
    return tok ~= nil and tok.type == tType
end

-- spec is an array where each entry is either a literal string (token text
-- must match exactly), {type = TOKEN_TYPE} (token type only), or
-- {str = "value"} (a STRING token whose unescaped value matches).
local function MatchAt(tokens, i, spec)
    for k, want in ipairs(spec) do
        local tok = tokens[i + k - 1]
        if not tok then return false end
        if type(want) == "string" then
            if tok.text ~= want then return false end
        elseif want.str ~= nil then
            if tok.type ~= TT.TOKEN_STRING or UnescapeLuaString(tok.text) ~= want.str then return false end
        elseif want.type ~= nil then
            if tok.type ~= want.type then return false end
        end
    end
    return true
end

-- Scans tokens[fromIndex..] for the first position matching spec.
local function FindSeq(tokens, spec, fromIndex)
    for i = (fromIndex or 1), #tokens - #spec + 1 do
        if MatchAt(tokens, i, spec) then return i end
    end
    return nil
end

-- Reads an optionally-negative number starting at tokens[i] (our own
-- codegen's negative offsets tokenize as a separate TOKEN_MINUS followed
-- by a TOKEN_NUMBER). Returns (value, nextIndex) or (nil, i).
local function ReadNumber(tokens, i)
    local negate, idx = false, i
    if IsPunct(tokens[idx], TT.TOKEN_MINUS) then
        negate = true
        idx = idx + 1
    end
    local tok = tokens[idx]
    if not tok or tok.type ~= TT.TOKEN_NUMBER then return nil, i end
    local val = tonumber(tok.text)
    if negate then val = -val end
    return val, idx + 1
end

-- Block-depth keywords for locating a script handler's matching `end`.
-- `then`/`do`/`elseif`/`else` are deliberately NOT counted -- counting
-- only the statement-opening keyword (if/for/while/function/repeat) is
-- what avoids double-counting "for ... do ... end" and "if ... elseif
-- ... end" chains, which is the actual bug a naive keyword scan hits.
local BLOCK_OPENERS = { ["function"] = true, ["if"] = true, ["for"] = true, ["while"] = true, ["repeat"] = true }
local BLOCK_CLOSERS = { ["end"] = true, ["until"] = true }

-- tokens[funcIdx] must be the "function" keyword token; returns the index
-- of its matching "end" token, or nil if unbalanced.
local function FindMatchingEnd(tokens, funcIdx)
    local depth = 1
    for i = funcIdx + 1, #tokens do
        local tok = tokens[i]
        if tok.type == TT.TOKEN_IDENTIFIER and tok.isKeyword then
            if BLOCK_OPENERS[tok.text] then
                depth = depth + 1
            elseif BLOCK_CLOSERS[tok.text] then
                depth = depth - 1
                if depth == 0 then return i end
            end
        end
    end
    return nil
end

local ELEMENT_SPECS = {
    Button = {
        defaults = { width = 100, height = 24, text = "Button" },
        fields = {
            { key = "text", label = "Text:", kind = "text" },
            { key = "width", label = "Width:", kind = "number" },
            { key = "height", label = "Height:", kind = "number" },
        },
        CreateLive = function(parent)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            btn:SetBackdropColor(0.18, 0.18, 0.20, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.label:SetPoint("CENTER")
            return btn
        end,
        UpdateLive = function(widget, el)
            widget:SetSize(el.width or 100, el.height or 24)
            widget:SetPoint("TOPLEFT", el.x or 0, -(el.y or 0))
            widget.label:SetText(el.text or "")
        end,
        EmitCode = function(el, varName, add)
            add(string.format('local %s = CreateFrame("Button", nil, f, "BackdropTemplate")', varName))
            add(string.format('%s:SetSize(%d, %d)', varName, el.width or 100, el.height or 24))
            add(string.format('%s:SetPoint("TOPLEFT", %d, %d)', varName, el.x or 0, -(el.y or 0)))
            add(string.format('local %sLabel = %s:CreateFontString(nil, "OVERLAY", "GameFontNormal")', varName, varName))
            add(string.format('%sLabel:SetPoint("CENTER")', varName))
            add(string.format('%sLabel:SetText(%q)', varName, el.text or ""))
        end,
        -- Reads back what EmitCode above writes. Returns the highest token
        -- index it matched (used to track where recognized content ends,
        -- for trailing-custom-code preservation), or nil if nothing matched.
        ParseFields = function(tokens, blockStart, blockEnd, varName, el)
            local lastIdx = nil
            local sizeIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetSize", { type = TT.TOKEN_LEFTPAREN } }, blockStart)
            if sizeIdx and sizeIdx <= blockEnd then
                local w, nextI = ReadNumber(tokens, sizeIdx + 4)
                if w and IsPunct(tokens[nextI], TT.TOKEN_COMMA) then
                    local h, afterH = ReadNumber(tokens, nextI + 1)
                    if h then
                        el.width, el.height = w, h
                        lastIdx = afterH
                    end
                end
            end
            local textIdx = FindSeq(tokens, { varName .. "Label", { type = TT.TOKEN_COLON }, "SetText", { type = TT.TOKEN_LEFTPAREN }, { type = TT.TOKEN_STRING } }, blockStart)
            if textIdx and textIdx <= blockEnd then
                el.text = UnescapeLuaString(tokens[textIdx + 4].text)
                lastIdx = math.max(lastIdx or 0, textIdx + 5)
            end
            return lastIdx
        end,
    },
    CheckBox = {
        defaults = { text = "Checkbox" },
        fields = {
            { key = "text", label = "Label:", kind = "text" },
        },
        CreateLive = function(parent)
            return CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        end,
        UpdateLive = function(widget, el)
            widget:SetPoint("TOPLEFT", el.x or 0, -(el.y or 0))
            if widget.text then widget.text:SetText(el.text or "") end
        end,
        EmitCode = function(el, varName, add)
            add(string.format('local %s = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")', varName))
            add(string.format('%s:SetPoint("TOPLEFT", %d, %d)', varName, el.x or 0, -(el.y or 0)))
            add(string.format('if %s.text then %s.text:SetText(%q) end', varName, varName, el.text or ""))
        end,
        ParseFields = function(tokens, blockStart, blockEnd, varName, el)
            local textIdx = FindSeq(tokens, {
                varName, { type = TT.TOKEN_PERIOD }, "text", { type = TT.TOKEN_COLON },
                "SetText", { type = TT.TOKEN_LEFTPAREN }, { type = TT.TOKEN_STRING },
            }, blockStart)
            if textIdx and textIdx <= blockEnd then
                el.text = UnescapeLuaString(tokens[textIdx + 6].text)
                return textIdx + 7
            end
            return nil
        end,
    },
    EditBox = {
        defaults = { width = 150, placeholder = "" },
        fields = {
            { key = "placeholder", label = "Default Text:", kind = "text" },
            { key = "width", label = "Width:", kind = "number" },
        },
        CreateLive = function(parent)
            local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
            eb:SetHeight(20)
            eb:SetAutoFocus(false)
            eb:SetFontObject("ChatFontNormal")
            eb:SetTextInsets(4, 4, 2, 2)
            eb:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            eb:SetBackdropColor(0.08, 0.08, 0.10, 1)
            eb:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            return eb
        end,
        UpdateLive = function(widget, el)
            widget:SetWidth(el.width or 150)
            widget:SetPoint("TOPLEFT", el.x or 0, -(el.y or 0))
            widget:SetText(el.placeholder or "")
        end,
        EmitCode = function(el, varName, add)
            add(string.format('local %s = CreateFrame("EditBox", nil, f, "BackdropTemplate")', varName))
            add(string.format('%s:SetSize(%d, 20)', varName, el.width or 150))
            add(string.format('%s:SetPoint("TOPLEFT", %d, %d)', varName, el.x or 0, -(el.y or 0)))
            add(string.format('%s:SetAutoFocus(false)', varName))
            add(string.format('%s:SetFontObject("ChatFontNormal")', varName))
            if el.placeholder and el.placeholder ~= "" then
                add(string.format('%s:SetText(%q)', varName, el.placeholder))
            end
        end,
        ParseFields = function(tokens, blockStart, blockEnd, varName, el)
            local lastIdx = nil
            local sizeIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetSize", { type = TT.TOKEN_LEFTPAREN } }, blockStart)
            if sizeIdx and sizeIdx <= blockEnd then
                local w, nextI = ReadNumber(tokens, sizeIdx + 4)
                if w then el.width = w; lastIdx = nextI end
            end
            el.placeholder = ""
            local textIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetText", { type = TT.TOKEN_LEFTPAREN }, { type = TT.TOKEN_STRING } }, blockStart)
            if textIdx and textIdx <= blockEnd then
                el.placeholder = UnescapeLuaString(tokens[textIdx + 4].text)
                lastIdx = math.max(lastIdx or 0, textIdx + 5)
            end
            return lastIdx
        end,
    },
    Label = {
        defaults = { text = "Label" },
        fields = {
            { key = "text", label = "Text:", kind = "text" },
        },
        CreateLive = function(parent)
            return parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end,
        UpdateLive = function(widget, el)
            widget:SetPoint("TOPLEFT", el.x or 0, -(el.y or 0))
            widget:SetText(el.text or "")
        end,
        EmitCode = function(el, varName, add)
            add(string.format('local %s = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")', varName))
            add(string.format('%s:SetPoint("TOPLEFT", %d, %d)', varName, el.x or 0, -(el.y or 0)))
            add(string.format('%s:SetText(%q)', varName, el.text or ""))
        end,
        ParseFields = function(tokens, blockStart, blockEnd, varName, el)
            local textIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetText", { type = TT.TOKEN_LEFTPAREN }, { type = TT.TOKEN_STRING } }, blockStart)
            if textIdx and textIdx <= blockEnd then
                el.text = UnescapeLuaString(tokens[textIdx + 4].text)
                return textIdx + 5
            end
            return nil
        end,
    },
    Slider = {
        defaults = { width = 150, min = 0, max = 100 },
        fields = {
            { key = "min", label = "Min:", kind = "number" },
            { key = "max", label = "Max:", kind = "number" },
            { key = "width", label = "Width:", kind = "number" },
        },
        CreateLive = function(parent)
            local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
            slider:SetHeight(20)
            return slider
        end,
        UpdateLive = function(widget, el)
            widget:SetWidth(el.width or 150)
            widget:SetPoint("TOPLEFT", el.x or 0, -(el.y or 0))
            widget:SetMinMaxValues(el.min or 0, el.max or 100)
            widget:SetValue(el.min or 0)
            if widget.Low then widget.Low:SetText(tostring(el.min or 0)) end
            if widget.High then widget.High:SetText(tostring(el.max or 100)) end
        end,
        EmitCode = function(el, varName, add)
            add(string.format('local %s = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")', varName))
            add(string.format('%s:SetSize(%d, 20)', varName, el.width or 150))
            add(string.format('%s:SetPoint("TOPLEFT", %d, %d)', varName, el.x or 0, -(el.y or 0)))
            add(string.format('%s:SetMinMaxValues(%d, %d)', varName, el.min or 0, el.max or 100))
            add(string.format('%s:SetValue(%d)', varName, el.min or 0))
        end,
        ParseFields = function(tokens, blockStart, blockEnd, varName, el)
            local lastIdx = nil
            local sizeIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetSize", { type = TT.TOKEN_LEFTPAREN } }, blockStart)
            if sizeIdx and sizeIdx <= blockEnd then
                local w, nextI = ReadNumber(tokens, sizeIdx + 4)
                if w then el.width = w; lastIdx = nextI end
            end
            local mmIdx = FindSeq(tokens, { varName, { type = TT.TOKEN_COLON }, "SetMinMaxValues", { type = TT.TOKEN_LEFTPAREN } }, blockStart)
            if mmIdx and mmIdx <= blockEnd then
                local mn, nextI = ReadNumber(tokens, mmIdx + 4)
                if mn and IsPunct(tokens[nextI], TT.TOKEN_COMMA) then
                    local mx, afterMx = ReadNumber(tokens, nextI + 1)
                    if mx then
                        el.min, el.max = mn, mx
                        lastIdx = math.max(lastIdx or 0, afterMx)
                    end
                end
            end
            return lastIdx
        end,
    },
}

---------------------------------------------------------------------------
-- Local UI helpers
---------------------------------------------------------------------------

-- Selector button: displays current value, shows dropdown on click
local function CreateSelector(parent, items, default, width, onChange)
    local btn = DF.Widgets:CreateButton(parent, default or items[1], width or 130)
    local current = default or items[1]

    local menu = DF.Widgets:CreateDropDown()

    btn:SetScript("OnClick", function(self)
        local menuItems = {}
        for _, item in ipairs(items) do
            menuItems[#menuItems + 1] = {
                text = item,
                func = function()
                    current = item
                    btn:SetLabel(item)
                    if onChange then onChange(item) end
                end,
            }
        end
        menu:Show(self, menuItems)
    end)

    local selector = { button = btn }
    function selector:GetValue() return current end
    function selector:SetValue(val)
        current = val
        btn:SetLabel(val)
    end
    return selector
end

-- Checkbox: CheckButton with a colored square check texture and label
local function CreateCheckbox(parent, labelText, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(14, 14)

    -- Box background
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 1)

    -- Border
    local border = cb:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Check mark (colored square)
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", -2, 2)
    check:SetColorTexture(0.3, 0.5, 0.8, 1)
    cb:SetCheckedTexture(check)

    -- Label
    local label = cb:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(DF.Theme:UIFont())
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.83, 0.83, 0.83, 1)

    cb:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)

    return cb
end

-- Text input: single-line EditBox with label
local function CreateTextInput(parent, labelText, defaultText, width, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(DF.Theme:UIFont())
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.65, 0.65, 0.65, 1)
    label:SetWidth(70)
    label:SetJustifyH("RIGHT")

    local input = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    input:SetPoint("LEFT", label, "RIGHT", 4, 0)
    input:SetSize(width or 120, 20)
    input:SetAutoFocus(false)
    input:SetFontObject(DF.Theme:UIFont())
    input:SetTextColor(0.83, 0.83, 0.83, 1)
    input:SetMaxLetters(200)
    input:SetText(defaultText or "")
    DF.Theme:ApplyInputStyle(input)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnTextChanged", function(self, userInput)
        if userInput and onChange then onChange(self:GetText()) end
    end)

    row:SetWidth(70 + 4 + (width or 120))

    local wrapper = { frame = row, input = input }
    function wrapper:GetText() return input:GetText() or "" end
    function wrapper:SetText(t) input:SetText(t or "") end
    return wrapper
end

-- Number input: like text input but for numbers
local function CreateNumberInput(parent, labelText, defaultVal, width, onChange)
    local ti = CreateTextInput(parent, labelText, tostring(defaultVal or 0), width, function(text)
        if onChange then onChange(tonumber(text) or 0) end
    end)
    ti.input:SetNumeric(false) -- allow negative and decimal entry
    function ti:GetNumber() return tonumber(ti.input:GetText()) or 0 end
    return ti
end

---------------------------------------------------------------------------
-- Code generation
---------------------------------------------------------------------------

local function GenerateCode(state)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Determine template string
    local inherits = {}
    if state.backdrop then
        inherits[#inherits + 1] = "BackdropTemplate"
    end
    local inheritStr = #inherits > 0 and (', "' .. table.concat(inherits, ", ") .. '"') or ""

    local globalName = (state.globalName and state.globalName ~= "") and ('"' .. state.globalName .. '"') or "nil"
    local parentRef = (state.parent and state.parent ~= "") and state.parent or "UIParent"

    add(string.format('local f = CreateFrame("%s", %s, %s%s)', state.frameType, globalName, parentRef, inheritStr))
    add(string.format("f:SetSize(%d, %d)", state.width or 200, state.height or 150))
    add(string.format('f:SetPoint("%s", %d, %d)', state.anchor or "CENTER", state.offsetX or 0, state.offsetY or 0))

    if state.backdrop then
        add("")
        add("f:SetBackdrop({")
        add('    bgFile = "Interface\\\\ChatFrame\\\\ChatFrameBackground",')
        add('    edgeFile = "Interface\\\\Tooltips\\\\UI-Tooltip-Border",')
        add("    tile = true, tileSize = 16, edgeSize = 16,")
        add("    insets = { left = 4, right = 4, top = 4, bottom = 4 },")
        add("})")
        add("f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)")
        add("f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)")
    end

    if state.movable then
        add("")
        add("f:SetMovable(true)")
        add("f:EnableMouse(true)")
        add('f:RegisterForDrag("LeftButton")')
        add("f:SetScript(\"OnDragStart\", f.StartMoving)")
        add("f:SetScript(\"OnDragStop\", f.StopMovingOrSizing)")
    end

    if state.resizable then
        add("")
        add("f:SetResizable(true)")
        add("f:SetResizeBounds(100, 80, 600, 400)")
    end

    if state.clamped then
        add("f:SetClampedToScreen(true)")
    end

    if state.titleBar then
        add("")
        add("-- Title bar")
        add('local titleBar = CreateFrame("Frame", nil, f)')
        add("titleBar:SetHeight(24)")
        add('titleBar:SetPoint("TOPLEFT", 0, 0)')
        add('titleBar:SetPoint("TOPRIGHT", 0, 0)')
        add("local titleBg = titleBar:CreateTexture(nil, \"BACKGROUND\")")
        add("titleBg:SetAllPoints()")
        add("titleBg:SetColorTexture(0.15, 0.15, 0.17, 1)")
        add('local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")')
        add('titleText:SetPoint("LEFT", 8, 0)')
        add('titleText:SetText("' .. (state.globalName or "My Frame") .. '")')
    end

    if state.closeBtn then
        add("")
        add("-- Close button")
        add('local closeBtn = CreateFrame("Button", nil, f)')
        add("closeBtn:SetSize(20, 20)")
        add('closeBtn:SetPoint("TOPRIGHT", -4, -4)')
        add('closeBtn:SetNormalTexture("Interface\\\\Buttons\\\\UI-Panel-MinimizeButton-Up")')
        add('closeBtn:SetHighlightTexture("Interface\\\\Buttons\\\\UI-Panel-MinimizeButton-Highlight")')
        add("closeBtn:SetScript(\"OnClick\", function() f:Hide() end)")
    end

    -- Scripts. A hand-written body captured by ParseCode (state.scriptBodies)
    -- takes precedence over the canned placeholder, so editing handler logic
    -- by hand survives every future visual-side regeneration.
    local scripts = {}
    if state.scriptOnShow then scripts[#scripts + 1] = { key = "scriptOnShow", name = "OnShow", params = "self", placeholder = "    -- OnShow handler" } end
    if state.scriptOnHide then scripts[#scripts + 1] = { key = "scriptOnHide", name = "OnHide", params = "self", placeholder = "    -- OnHide handler" } end
    if state.scriptOnEvent then scripts[#scripts + 1] = { key = "scriptOnEvent", name = "OnEvent", params = "self, event, ...", placeholder = "    -- handle events" } end
    if state.scriptOnUpdate then scripts[#scripts + 1] = { key = "scriptOnUpdate", name = "OnUpdate", params = "self, elapsed", placeholder = "    -- runs every frame" } end

    if #scripts > 0 then
        add("")
        for _, script in ipairs(scripts) do
            add(string.format('f:SetScript("%s", function(%s)', script.name, script.params))
            local body = state.scriptBodies and state.scriptBodies[script.key]
            add(body or script.placeholder)
            add("end)")
        end
    end

    if state.elements and #state.elements > 0 then
        add("")
        add("-- Elements")
        for _, el in ipairs(state.elements) do
            local spec = ELEMENT_SPECS[el.type]
            if spec then
                local varName = el.type:lower() .. el.seq
                spec.EmitCode(el, varName, add)
                add("")
            end
        end
    end

    if state.trailingCustomCode and state.trailingCustomCode ~= "" then
        add("")
        add(state.trailingCustomCode)
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Default builder state
---------------------------------------------------------------------------

local function DefaultState()
    return {
        frameType = "Frame",
        globalName = "",
        parent = "UIParent",
        width = 300,
        height = 200,
        anchor = "CENTER",
        offsetX = 0,
        offsetY = 0,
        backdrop = false,
        movable = false,
        resizable = false,
        clamped = false,
        closeBtn = false,
        titleBar = false,
        scriptOnShow = false,
        scriptOnHide = false,
        scriptOnEvent = false,
        scriptOnUpdate = false,
        scriptBodies = {},      -- [scriptKey] = hand-written body text, captured verbatim by ParseCode

        elements = {},          -- ordered array of element records: { id, type, seq, x, y, ... }
        selectedElementId = nil,
        nextElementId = 1,      -- monotonic, never reused

        trailingCustomCode = "", -- anything hand-typed after the last recognized construct
    }
end

---------------------------------------------------------------------------
-- Code -> model: reads a hand-edited (or freshly generated) code string
-- back into a state table, using the token-stream helpers defined above
-- ELEMENT_SPECS. Returns nil if the code doesn't even contain a
-- recognizable frame header (caller leaves the existing state untouched
-- in that case rather than guessing).
---------------------------------------------------------------------------

local FLAG_MARKERS = {
    backdrop  = { "f", { type = TT.TOKEN_COLON }, "SetBackdrop", { type = TT.TOKEN_LEFTPAREN }, { type = TT.TOKEN_LEFTWING } },
    movable   = { "f", { type = TT.TOKEN_COLON }, "SetMovable", { type = TT.TOKEN_LEFTPAREN }, "true", { type = TT.TOKEN_RIGHTPAREN } },
    resizable = { "f", { type = TT.TOKEN_COLON }, "SetResizable", { type = TT.TOKEN_LEFTPAREN }, "true", { type = TT.TOKEN_RIGHTPAREN } },
    clamped   = { "f", { type = TT.TOKEN_COLON }, "SetClampedToScreen", { type = TT.TOKEN_LEFTPAREN }, "true", { type = TT.TOKEN_RIGHTPAREN } },
    -- Detected structurally (the actual titleBar/closeBtn frame creation),
    -- not by the "-- Title bar"/"-- Close button" comments -- comments
    -- aren't tokenized into the significant-token array at all, and relying
    -- on them would break the moment someone edits one but not the other.
    titleBar  = { "local", "titleBar", { type = TT.TOKEN_ASSIGNMENT }, "CreateFrame", { type = TT.TOKEN_LEFTPAREN } },
    closeBtn  = { "local", "closeBtn", { type = TT.TOKEN_ASSIGNMENT }, "CreateFrame", { type = TT.TOKEN_LEFTPAREN } },
}

local SCRIPT_MARKERS = {
    scriptOnShow   = "OnShow",
    scriptOnHide   = "OnHide",
    scriptOnEvent  = "OnEvent",
    scriptOnUpdate = "OnUpdate",
}

local ELEMENT_WOWTYPE_MAP = {
    Button = "Button",
    CheckButton = "CheckBox",
    EditBox = "EditBox",
    Slider = "Slider",
}

-- Parses the `local f = CreateFrame(...)` / `f:SetSize(...)` /
-- `f:SetPoint(...)` triple. Returns (success, lastMatchedIdx).
local function ParseRootHeader(tokens, newState)
    local i = FindSeq(tokens, { "local", "f", { type = TT.TOKEN_ASSIGNMENT }, "CreateFrame", { type = TT.TOKEN_LEFTPAREN } })
    if not i then return false end
    local idx = i + 5

    local t = tokens[idx]
    if not t or t.type ~= TT.TOKEN_STRING then return false end
    newState.frameType = UnescapeLuaString(t.text)
    idx = idx + 1
    if not IsPunct(tokens[idx], TT.TOKEN_COMMA) then return false end
    idx = idx + 1

    t = tokens[idx]
    if t and t.type == TT.TOKEN_STRING then
        newState.globalName = UnescapeLuaString(t.text)
        idx = idx + 1
    elseif t and t.text == "nil" then
        newState.globalName = ""
        idx = idx + 1
    else
        return false
    end
    if not IsPunct(tokens[idx], TT.TOKEN_COMMA) then return false end
    idx = idx + 1

    t = tokens[idx]
    if not t or t.type ~= TT.TOKEN_IDENTIFIER then return false end
    local parentParts = { t.text }
    idx = idx + 1
    while IsPunct(tokens[idx], TT.TOKEN_PERIOD) and tokens[idx + 1] and tokens[idx + 1].type == TT.TOKEN_IDENTIFIER do
        parentParts[#parentParts + 1] = tokens[idx + 1].text
        idx = idx + 2
    end
    newState.parent = table.concat(parentParts, ".")

    while IsPunct(tokens[idx], TT.TOKEN_COMMA) and tokens[idx + 1] and tokens[idx + 1].type == TT.TOKEN_STRING do
        idx = idx + 2
    end
    if not IsPunct(tokens[idx], TT.TOKEN_RIGHTPAREN) then return false end
    local lastIdx = idx
    idx = idx + 1

    local sizeIdx = FindSeq(tokens, { "f", { type = TT.TOKEN_COLON }, "SetSize", { type = TT.TOKEN_LEFTPAREN } }, idx)
    if sizeIdx then
        local w, nextI = ReadNumber(tokens, sizeIdx + 4)
        if w and IsPunct(tokens[nextI], TT.TOKEN_COMMA) then
            local h, afterH = ReadNumber(tokens, nextI + 1)
            if h then
                newState.width, newState.height = w, h
                lastIdx = afterH
            end
        end
    end

    local pointIdx = FindSeq(tokens, { "f", { type = TT.TOKEN_COLON }, "SetPoint", { type = TT.TOKEN_LEFTPAREN } }, idx)
    if pointIdx then
        local aTok = tokens[pointIdx + 4]
        if aTok and aTok.type == TT.TOKEN_STRING then
            local nIdx = pointIdx + 5
            if IsPunct(tokens[nIdx], TT.TOKEN_COMMA) then
                local x, afterX = ReadNumber(tokens, nIdx + 1)
                if x and IsPunct(tokens[afterX], TT.TOKEN_COMMA) then
                    local y, afterY = ReadNumber(tokens, afterX + 1)
                    if y then
                        newState.anchor = UnescapeLuaString(aTok.text)
                        newState.offsetX, newState.offsetY = x, y
                        lastIdx = afterY
                    end
                end
            end
        end
    end

    return true, lastIdx
end

-- Reserved internal variable names our own codegen uses for the root frame
-- and its optional title bar / close button -- never element names, but
-- "closeBtn" happens to use CreateFrame("Button", ...) too, so it must be
-- excluded explicitly or it'd be mistaken for an added Button element.
local RESERVED_VAR_NAMES = { f = true, titleBar = true, closeBtn = true }

-- Scans the whole token array for `local VAR = CreateFrame("WowType", ...)`
-- / `local VAR = f:CreateFontString(...)` element-start statements, in
-- source order.
local function FindElementStarts(tokens)
    local starts = {}
    for i = 1, #tokens do
        if MatchAt(tokens, i, { "local", { type = TT.TOKEN_IDENTIFIER }, { type = TT.TOKEN_ASSIGNMENT }, "CreateFrame", { type = TT.TOKEN_LEFTPAREN } }) and not RESERVED_VAR_NAMES[tokens[i + 1].text] then
            local wowTypeTok = tokens[i + 5]
            if wowTypeTok and wowTypeTok.type == TT.TOKEN_STRING then
                local elType = ELEMENT_WOWTYPE_MAP[UnescapeLuaString(wowTypeTok.text)]
                if elType then
                    starts[#starts + 1] = { elType = elType, varName = tokens[i + 1].text, startIdx = i }
                end
            end
        elseif MatchAt(tokens, i, { "local", { type = TT.TOKEN_IDENTIFIER }, { type = TT.TOKEN_ASSIGNMENT }, "f", { type = TT.TOKEN_COLON }, "CreateFontString" }) then
            starts[#starts + 1] = { elType = "Label", varName = tokens[i + 1].text, startIdx = i }
        end
    end
    return starts
end

-- Shared x/y extraction (every EmitCode anchors "TOPLEFT" the same way).
-- Returns (x, y, lastMatchedIdx).
local function ExtractElementXY(tokens, blockStart, blockEnd, varName)
    local idx = FindSeq(tokens, {
        varName, { type = TT.TOKEN_COLON }, "SetPoint", { type = TT.TOKEN_LEFTPAREN },
        { str = "TOPLEFT" }, { type = TT.TOKEN_COMMA },
    }, blockStart)
    if not idx or idx > blockEnd then return 0, 0, nil end
    local x, afterX = ReadNumber(tokens, idx + 6)
    if not x or not IsPunct(tokens[afterX], TT.TOKEN_COMMA) then return 0, 0, nil end
    local y, afterY = ReadNumber(tokens, afterX + 1)
    if not y then return 0, 0, nil end
    return x, -y, afterY
end

local function ParseCode(codeText, previousState)
    local tokens = Tokenize(codeText)
    local newState = DefaultState()
    if previousState and previousState.nextElementId then
        newState.nextElementId = previousState.nextElementId
    end

    local ok, headerLastIdx = ParseRootHeader(tokens, newState)
    if not ok then return nil end
    local maxRecognizedIdx = headerLastIdx or 1

    for flagKey, spec in pairs(FLAG_MARKERS) do
        newState[flagKey] = FindSeq(tokens, spec) ~= nil
    end

    -- Script handler bodies: capture verbatim source text between each
    -- handler's parameter list and its matching `end` (a lightweight block-
    -- depth count over real keyword tokens, see FindMatchingEnd), so
    -- hand-written logic survives every future visual-side regeneration.
    newState.scriptBodies = {}
    for flagKey, scriptName in pairs(SCRIPT_MARKERS) do
        local callIdx = FindSeq(tokens, {
            "f", { type = TT.TOKEN_COLON }, "SetScript", { type = TT.TOKEN_LEFTPAREN },
            { str = scriptName }, { type = TT.TOKEN_COMMA }, "function", { type = TT.TOKEN_LEFTPAREN },
        })
        if callIdx then
            newState[flagKey] = true
            local funcIdx = callIdx + 6
            local parenDepth, paramCloseIdx = 0, nil
            for pIdx = funcIdx + 1, #tokens do
                local tok = tokens[pIdx]
                if tok.type == TT.TOKEN_LEFTPAREN then
                    parenDepth = parenDepth + 1
                elseif tok.type == TT.TOKEN_RIGHTPAREN then
                    if parenDepth == 0 then paramCloseIdx = pIdx; break end
                    parenDepth = parenDepth - 1
                end
            end
            if paramCloseIdx then
                local endIdx = FindMatchingEnd(tokens, funcIdx)
                if endIdx then
                    local bodyStart = tokens[paramCloseIdx].endPos + 1
                    local bodyEnd = tokens[endIdx].startPos - 1
                    if bodyEnd >= bodyStart then
                        local body = codeText:sub(bodyStart, bodyEnd):gsub("^[ \t]*\n", ""):gsub("\n[ \t]*$", "")
                        newState.scriptBodies[flagKey] = body
                    end
                    if endIdx > maxRecognizedIdx then maxRecognizedIdx = endIdx end
                end
            end
        else
            newState[flagKey] = false
        end
    end

    local starts = FindElementStarts(tokens)
    local elements, elementSeqCounters = {}, {}
    for idx, entry in ipairs(starts) do
        local blockEnd = (starts[idx + 1] and starts[idx + 1].startIdx - 1) or #tokens
        local seq = tonumber(entry.varName:match("(%d+)$")) or ((elementSeqCounters[entry.elType] or 0) + 1)
        elementSeqCounters[entry.elType] = math.max(elementSeqCounters[entry.elType] or 0, seq)

        local spec = ELEMENT_SPECS[entry.elType]
        local el = { type = entry.elType, seq = seq }
        for k, v in pairs(spec.defaults) do el[k] = v end

        local x, y, xyIdx = ExtractElementXY(tokens, entry.startIdx, blockEnd, entry.varName)
        el.x, el.y = x, y
        if xyIdx and xyIdx > maxRecognizedIdx then maxRecognizedIdx = xyIdx end

        if spec.ParseFields then
            local fIdx = spec.ParseFields(tokens, entry.startIdx, blockEnd, entry.varName, el)
            if fIdx and fIdx > maxRecognizedIdx then maxRecognizedIdx = fIdx end
        end

        elements[#elements + 1] = el
    end

    -- Keep stable internal ids for elements matched by (type, seq) so
    -- selection / live-widget identity survives a reparse instead of
    -- tearing down and recreating everything on every keystroke.
    local prevByKey = {}
    if previousState and previousState.elements then
        for _, pel in ipairs(previousState.elements) do
            prevByKey[pel.type .. "#" .. pel.seq] = pel
        end
    end
    local nextId = newState.nextElementId or 1
    for _, el in ipairs(elements) do
        local prev = prevByKey[el.type .. "#" .. el.seq]
        if prev then
            el.id = prev.id
        else
            el.id = nextId
            nextId = nextId + 1
        end
    end
    newState.elements = elements
    newState.nextElementId = nextId
    newState.selectedElementId = nil

    -- Anything after the last recognized construct is preserved verbatim
    -- instead of silently dropped. Unrecognized content *interspersed*
    -- between recognized constructs is the one real remaining gap.
    if maxRecognizedIdx < #tokens then
        local tailStart = (tokens[maxRecognizedIdx] and tokens[maxRecognizedIdx].endPos + 1) or 1
        newState.trailingCustomCode = codeText:sub(tailStart):match("^%s*(.-)%s*$") or ""
    else
        newState.trailingCustomCode = ""
    end

    return newState
end

---------------------------------------------------------------------------
-- Embedded builder: a persistent panel hosted inside the Snippet Editor
-- (Code | Preview split + right property pane), driven by a snippet's
-- builderState. Replaces the old floating popup entirely.
---------------------------------------------------------------------------

function Builder:CreateEmbedded(parent)
    -- Clean up stale named frames from a previous /reload (widget-type
    -- immutability means the preview is always recreated fresh below).
    local staleDialog = _G["DevForgeFrameBuilder"]
    if staleDialog then
        staleDialog:Hide(); staleDialog:EnableMouse(false)
    end
    local stalePreview = _G["DevForgeFrameBuilderPreview"]
    if stalePreview then
        stalePreview:Hide(); stalePreview:EnableMouse(false)
    end

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local state = DefaultState()
    local onChangeCallback = nil
    local elementSeqCounters = {}
    local liveWidgets = {}
    local regenerateTimer = nil

    -- Forward declarations: these all call each other and are wired up to
    -- UI created further below, so they're declared here as bare locals
    -- and assigned function bodies later, sharing these upvalues regardless
    -- of definition order.
    local RefreshElementsList, RefreshPropertyPanel, UpdateSelectionOutline, RecalcRightPaneHeight
    local AddElement, DeleteSelectedElement, FindSelectedElement, SelectElement
    local ScheduleRegenerate, ApplyPreview

    ---------------------------------------------------------------------------
    -- Layout: right property pane (fixed width) + center Code | Preview split
    ---------------------------------------------------------------------------
    local rightPane = CreateFrame("Frame", nil, frame)
    rightPane:SetPoint("TOPRIGHT", 0, 0)
    rightPane:SetPoint("BOTTOMRIGHT", 0, 0)
    rightPane:SetWidth(300)

    local centerArea = CreateFrame("Frame", nil, frame)
    centerArea:SetPoint("TOPLEFT", 0, 0)
    centerArea:SetPoint("BOTTOMLEFT", 0, 0)
    centerArea:SetPoint("TOPRIGHT", rightPane, "TOPLEFT", -8, 0)
    centerArea:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMLEFT", -8, 0)

    local split = DF.Widgets:CreateSplitPane(centerArea, {
        direction = "horizontal", initialSize = 420, minSize = 200, maxSize = 3000,
    })
    split.frame:SetAllPoints(centerArea)

    -- Status line for when a hand-edit can't be synced back to the visual
    -- model (missing/garbled frame header); hidden otherwise.
    local codeStatus = split.left:CreateFontString(nil, "OVERLAY")
    codeStatus:SetFontObject(DF.Theme:UIFont())
    codeStatus:SetPoint("BOTTOMLEFT", split.left, "BOTTOMLEFT", 4, 2)
    codeStatus:SetPoint("BOTTOMRIGHT", split.left, "BOTTOMRIGHT", -4, 2)
    codeStatus:SetHeight(14)
    codeStatus:SetJustifyH("LEFT")
    codeStatus:SetTextColor(0.9, 0.5, 0.3, 1)
    codeStatus:Hide()

    local codePreview = DF.Widgets:CreateCodeEditBox(split.left, { multiLine = true, readOnly = false, autocomplete = true })
    codePreview.frame:SetPoint("TOPLEFT", split.left, "TOPLEFT", 0, 0)
    codePreview.frame:SetPoint("BOTTOMRIGHT", split.left, "BOTTOMRIGHT", 0, 16)

    local previewContainer = split.right

    ---------------------------------------------------------------------------
    -- Live preview: an actual frame configured from state, embedded as a
    -- normal child of previewContainer (a fixed design canvas, not a
    -- floating overlay -- Anchor/Offset still drive the generated code,
    -- they just no longer control on-canvas placement here).
    ---------------------------------------------------------------------------
    local previewFrame, previewTitleBar, previewTitleText, previewCloseBtn, currentPreviewType

    -- WoW has no API to change an existing frame's widget type (Frame vs
    -- Button vs StatusBar vs EditBox vs ScrollFrame is fixed at CreateFrame
    -- time), so a Frame Type change retires the old preview object and
    -- creates a new one of the right type.
    local function RecreatePreviewFrame(frameType)
        if previewFrame then
            previewFrame:Hide()
            previewFrame:SetScript("OnDragStart", nil)
            previewFrame:SetScript("OnDragStop", nil)
            previewFrame:SetParent(nil)
        end

        -- Old element widgets were parented to the retired preview frame;
        -- drop them so ApplyPreview recreates them fresh under the new one.
        for id, widget in pairs(liveWidgets) do
            if widget.Hide then widget:Hide() end
            if widget.SetParent then pcall(widget.SetParent, widget, nil) end
            liveWidgets[id] = nil
        end

        previewFrame = CreateFrame(frameType, "DevForgeFrameBuilderPreview", previewContainer, "BackdropTemplate")
        currentPreviewType = frameType

        previewTitleBar = CreateFrame("Frame", nil, previewFrame)
        previewTitleBar:SetHeight(24)
        previewTitleBar:SetPoint("TOPLEFT", 0, 0)
        previewTitleBar:SetPoint("TOPRIGHT", 0, 0)
        local titleBg = previewTitleBar:CreateTexture(nil, "BACKGROUND")
        titleBg:SetAllPoints()
        titleBg:SetColorTexture(0.15, 0.15, 0.17, 1)
        previewTitleText = previewTitleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        previewTitleText:SetPoint("LEFT", 8, 0)
        previewTitleBar:Hide()

        previewCloseBtn = CreateFrame("Button", nil, previewFrame)
        previewCloseBtn:SetSize(20, 20)
        previewCloseBtn:SetPoint("TOPRIGHT", -4, -4)
        previewCloseBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        previewCloseBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        previewCloseBtn:SetScript("OnClick", function() previewFrame:Hide() end)
        previewCloseBtn:Hide()
    end

    -- Apply the current state to the live preview frame (mirrors
    -- GenerateCode, but calling real WoW API instead of emitting text)
    ApplyPreview = function(previewState)
        if previewState.frameType ~= currentPreviewType then
            RecreatePreviewFrame(previewState.frameType)
        end

        previewFrame:ClearAllPoints()
        previewFrame:SetPoint("CENTER", previewContainer, "CENTER", 0, 0)
        previewFrame:SetSize(math.max(1, previewState.width or 200), math.max(1, previewState.height or 150))

        if previewState.backdrop then
            previewFrame:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            previewFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            previewFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        else
            previewFrame:SetBackdrop(nil)
        end

        previewFrame:SetMovable(previewState.movable and true or false)
        if previewState.movable then
            previewFrame:EnableMouse(true)
            previewFrame:RegisterForDrag("LeftButton")
            previewFrame:SetScript("OnDragStart", previewFrame.StartMoving)
            previewFrame:SetScript("OnDragStop", previewFrame.StopMovingOrSizing)
        else
            previewFrame:RegisterForDrag()
            previewFrame:SetScript("OnDragStart", nil)
            previewFrame:SetScript("OnDragStop", nil)
        end

        previewFrame:SetResizable(previewState.resizable and true or false)

        if previewState.titleBar then
            previewTitleText:SetText(previewState.globalName ~= "" and previewState.globalName or "My Frame")
            previewTitleBar:Show()
        else
            previewTitleBar:Hide()
        end
        previewCloseBtn:SetShown(previewState.closeBtn and true or false)

        previewFrame:Show()

        -- Reconcile child elements against the live widget map: create any
        -- missing, update all, and drop any whose element was deleted.
        local seen = {}
        for _, el in ipairs(previewState.elements or {}) do
            local spec = ELEMENT_SPECS[el.type]
            if spec then
                seen[el.id] = true
                local widget = liveWidgets[el.id]
                if not widget then
                    widget = spec.CreateLive(previewFrame)
                    if widget.SetScript then
                        widget:SetScript("OnMouseDown", function()
                            if SelectElement then SelectElement(el.id) end
                        end)
                    end
                    liveWidgets[el.id] = widget
                end
                spec.UpdateLive(widget, el)
                if widget.Show then widget:Show() end
            end
        end
        for id, widget in pairs(liveWidgets) do
            if not seen[id] then
                if widget.Hide then widget:Hide() end
                if widget.SetParent then pcall(widget.SetParent, widget, nil) end
                liveWidgets[id] = nil
            end
        end

        if UpdateSelectionOutline then UpdateSelectionOutline() end
    end

    ScheduleRegenerate = function()
        if regenerateTimer then regenerateTimer:Cancel() end
        regenerateTimer = C_Timer.NewTimer(0.15, function()
            regenerateTimer = nil
            local code = GenerateCode(state)
            codePreview:SetText(code)
            ApplyPreview(state)
            if onChangeCallback then onChangeCallback(state, code) end
        end)
    end

    local function OnFieldChanged()
        ScheduleRegenerate()
    end

    ---------------------------------------------------------------------------
    -- Right pane: root-frame settings on top, then the element
    -- toolbox/list/property panel below, inside a scroll pane.
    ---------------------------------------------------------------------------
    local scrollPane = DF.Widgets:CreateScrollPane(rightPane, true)
    scrollPane.frame:SetAllPoints(rightPane)
    local content = scrollPane.content

    local yOff = 6

    -- Frame Type selector
    local ftLabel = content:CreateFontString(nil, "OVERLAY")
    ftLabel:SetFontObject(DF.Theme:UIFont())
    ftLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    ftLabel:SetText("Frame Type:")
    ftLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    ftLabel:SetWidth(70)
    ftLabel:SetJustifyH("RIGHT")

    local ftSelector = CreateSelector(content, FRAME_TYPES, "Frame", 130, function(val)
        state.frameType = val
        OnFieldChanged()
    end)
    ftSelector.button:SetPoint("LEFT", ftLabel, "RIGHT", 4, 0)
    yOff = yOff + 26

    -- Name (the frame's global name, not the snippet's display name)
    local nameInput = CreateTextInput(content, "Name:", "", 150, function(val)
        state.globalName = val
        OnFieldChanged()
    end)
    nameInput.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    yOff = yOff + 24

    -- Parent
    local parentInput = CreateTextInput(content, "Parent:", "UIParent", 150, function(val)
        state.parent = val
        OnFieldChanged()
    end)
    parentInput.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    yOff = yOff + 24

    -- Width / Height on same row
    local sizeRow = CreateFrame("Frame", nil, content)
    sizeRow:SetHeight(22)
    sizeRow:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)

    local widthInput = CreateNumberInput(sizeRow, "Width:", 300, 55, function(val)
        state.width = val
        OnFieldChanged()
    end)
    widthInput.frame:SetPoint("LEFT", 0, 0)

    local heightInput = CreateNumberInput(sizeRow, "Height:", 200, 55, function(val)
        state.height = val
        OnFieldChanged()
    end)
    heightInput.frame:SetPoint("LEFT", widthInput.frame, "RIGHT", 8, 0)
    yOff = yOff + 24

    -- Anchor selector
    local anchorLabel = content:CreateFontString(nil, "OVERLAY")
    anchorLabel:SetFontObject(DF.Theme:UIFont())
    anchorLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    anchorLabel:SetText("Anchor:")
    anchorLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    anchorLabel:SetWidth(70)
    anchorLabel:SetJustifyH("RIGHT")

    local anchorSelector = CreateSelector(content, ANCHOR_POINTS, "CENTER", 110, function(val)
        state.anchor = val
        OnFieldChanged()
    end)
    anchorSelector.button:SetPoint("LEFT", anchorLabel, "RIGHT", 4, 0)
    yOff = yOff + 26

    -- Offset X / Y
    local offRow = CreateFrame("Frame", nil, content)
    offRow:SetHeight(22)
    offRow:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)

    local offXInput = CreateNumberInput(offRow, "Off X:", 0, 55, function(val)
        state.offsetX = val
        OnFieldChanged()
    end)
    offXInput.frame:SetPoint("LEFT", 0, 0)

    local offYInput = CreateNumberInput(offRow, "Off Y:", 0, 55, function(val)
        state.offsetY = val
        OnFieldChanged()
    end)
    offYInput.frame:SetPoint("LEFT", offXInput.frame, "RIGHT", 8, 0)
    yOff = yOff + 28

    -- Feature checkboxes (two columns)
    local featLabel = content:CreateFontString(nil, "OVERLAY")
    featLabel:SetFontObject(DF.Theme:UIFont())
    featLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    featLabel:SetText("Features:")
    featLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    yOff = yOff + 16

    local features = {
        { key = "backdrop",  label = "Backdrop" },
        { key = "movable",   label = "Movable" },
        { key = "resizable", label = "Resizable" },
        { key = "clamped",   label = "Clamped" },
        { key = "closeBtn",  label = "Close button" },
        { key = "titleBar",  label = "Title bar" },
    }
    local featureCheckboxes = {}
    for i, feat in ipairs(features) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local cb = CreateCheckbox(content, feat.label, function(checked)
            state[feat.key] = checked
            OnFieldChanged()
        end)
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + col * 145, -(yOff + row * 18))
        featureCheckboxes[feat.key] = cb
    end
    yOff = yOff + math.ceil(#features / 2) * 18 + 6

    -- Script checkboxes
    local scriptLabel = content:CreateFontString(nil, "OVERLAY")
    scriptLabel:SetFontObject(DF.Theme:UIFont())
    scriptLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -yOff)
    scriptLabel:SetText("Scripts:")
    scriptLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    yOff = yOff + 16

    local scripts = {
        { key = "scriptOnShow",   label = "OnShow" },
        { key = "scriptOnHide",   label = "OnHide" },
        { key = "scriptOnEvent",  label = "OnEvent" },
        { key = "scriptOnUpdate", label = "OnUpdate" },
    }
    local scriptCheckboxes = {}
    for i, scr in ipairs(scripts) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local cb = CreateCheckbox(content, scr.label, function(checked)
            state[scr.key] = checked
            OnFieldChanged()
        end)
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + col * 145, -(yOff + row * 18))
        scriptCheckboxes[scr.key] = cb
    end
    yOff = yOff + math.ceil(#scripts / 2) * 18 + 12

    local rootFieldsBottomY = yOff

    -- Toolbox
    local addElementMenu = DF.Widgets:CreateDropDown()
    local addElementBtn = DF.Widgets:CreateButton(content, "+ Add Element", 150)
    addElementBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -rootFieldsBottomY)
    addElementBtn:SetScript("OnClick", function(self)
        local menuItems = {}
        for _, t in ipairs(ELEMENT_TYPES) do
            menuItems[#menuItems + 1] = {
                text = t,
                func = function() AddElement(t) end,
            }
        end
        addElementMenu:Show(self, menuItems)
    end)

    local elementsListLabel = content:CreateFontString(nil, "OVERLAY")
    elementsListLabel:SetFontObject(DF.Theme:UIFont())
    elementsListLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(rootFieldsBottomY + 30))
    elementsListLabel:SetText("Elements:")
    elementsListLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local elementsListY = rootFieldsBottomY + 46
    local elementsListArea = CreateFrame("Frame", nil, content)
    elementsListArea:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -elementsListY)
    elementsListArea:SetWidth(260)
    elementsListArea:SetHeight(24)

    local propertyPanelLabel = content:CreateFontString(nil, "OVERLAY")
    propertyPanelLabel:SetFontObject(DF.Theme:UIFont())
    propertyPanelLabel:SetText("Properties:")
    propertyPanelLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local propertyPanelArea = CreateFrame("Frame", nil, content)
    propertyPanelArea:SetWidth(260)
    propertyPanelArea:SetHeight(24)

    -- Selection outline: one reusable thin border wrapping whichever live
    -- widget is currently selected on the preview canvas.
    local selectionOutline = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
    selectionOutline:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    selectionOutline:SetBackdropBorderColor(0.3, 0.8, 1.0, 1)
    selectionOutline:EnableMouse(false)
    selectionOutline:Hide()

    -- The elements list and property panel both change height dynamically
    -- (element count / selected element's field count); everything below
    -- the elements list is repositioned by absolute offset from `content`
    -- rather than relative-chained anchors, and the scroll pane's content
    -- height is recomputed to match.
    RecalcRightPaneHeight = function()
        local listH = elementsListArea:GetHeight() or 24
        local propLabelY = elementsListY + listH + 10
        propertyPanelLabel:ClearAllPoints()
        propertyPanelLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -propLabelY)
        local propAreaY = propLabelY + 16
        propertyPanelArea:ClearAllPoints()
        propertyPanelArea:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -propAreaY)
        local propH = propertyPanelArea:GetHeight() or 24
        scrollPane:SetContentHeight(propAreaY + propH + 20)
    end

    FindSelectedElement = function()
        for _, el in ipairs(state.elements) do
            if el.id == state.selectedElementId then return el end
        end
        return nil
    end

    SelectElement = function(id)
        state.selectedElementId = id
        RefreshElementsList()
        RefreshPropertyPanel()
        UpdateSelectionOutline()
    end

    AddElement = function(elType)
        local spec = ELEMENT_SPECS[elType]
        if not spec then return end
        elementSeqCounters[elType] = (elementSeqCounters[elType] or 0) + 1
        local el = DF.Util:DeepCopy(spec.defaults)
        el.id = state.nextElementId
        el.type = elType
        el.seq = elementSeqCounters[elType]
        -- Stagger new elements a little so they don't stack exactly on top
        -- of each other or of previously-added ones.
        local stagger = ((state.nextElementId - 1) % 8) * 16
        el.x = stagger
        el.y = stagger
        state.nextElementId = state.nextElementId + 1
        state.elements[#state.elements + 1] = el
        state.selectedElementId = el.id
        RefreshElementsList()
        RefreshPropertyPanel()
        ScheduleRegenerate()
    end

    DeleteSelectedElement = function()
        local el = FindSelectedElement()
        if not el then return end
        for i, e in ipairs(state.elements) do
            if e.id == el.id then
                table.remove(state.elements, i)
                break
            end
        end
        state.selectedElementId = nil
        RefreshElementsList()
        RefreshPropertyPanel()
        ScheduleRegenerate()
    end

    -- Elements list: rebuilt from scratch on every refresh -- element
    -- counts here are expected to be small.
    local elementsListRows = {}
    RefreshElementsList = function()
        for _, row in ipairs(elementsListRows) do row:Hide() end

        for i, el in ipairs(state.elements) do
            local row = elementsListRows[i]
            if not row then
                row = DF.Widgets:CreateButton(elementsListArea, "", 150)
                elementsListRows[i] = row
            end
            row:SetLabel(string.format("%s%d", el.type, el.seq or i))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            local selected = (el.id == state.selectedElementId)
            if row.label then
                if selected then
                    row.label:SetTextColor(0.5, 0.85, 1, 1)
                else
                    row.label:SetTextColor(0.83, 0.83, 0.83, 1)
                end
            end
            row:SetScript("OnClick", function() SelectElement(el.id) end)
            row:Show()
        end

        elementsListArea:SetHeight(math.max(24, #state.elements * 20 + 4))
        RecalcRightPaneHeight()
    end

    -- Property panel: rebuilt whenever the selection (or its type) changes
    local propertyPanelWidgets = {}
    RefreshPropertyPanel = function()
        for _, w in ipairs(propertyPanelWidgets) do
            if w.frame then w.frame:Hide(); w.frame:SetParent(nil)
            else w:Hide(); w:SetParent(nil) end
        end
        wipe(propertyPanelWidgets)

        local el = FindSelectedElement()
        local spec = el and ELEMENT_SPECS[el.type]
        if not el or not spec then
            propertyPanelArea:SetHeight(4)
            RecalcRightPaneHeight()
            return
        end

        -- Each row is anchored by both TOPLEFT and TOPRIGHT (relative to
        -- propertyPanelArea's own explicit width) so the row frame gets a
        -- real, explicit width instead of relying on a single anchor point.
        local function AnchorRow(rowFrame, py)
            rowFrame:SetPoint("TOPLEFT", propertyPanelArea, "TOPLEFT", 0, -py)
            rowFrame:SetPoint("TOPRIGHT", propertyPanelArea, "TOPRIGHT", 0, -py)
        end

        local py = 0
        local xInput = CreateNumberInput(propertyPanelArea, "X:", el.x or 0, 55, function(val)
            el.x = val
            ScheduleRegenerate()
        end)
        AnchorRow(xInput.frame, py)
        propertyPanelWidgets[#propertyPanelWidgets + 1] = xInput
        py = py + 24

        local yInput = CreateNumberInput(propertyPanelArea, "Y:", el.y or 0, 55, function(val)
            el.y = val
            ScheduleRegenerate()
        end)
        AnchorRow(yInput.frame, py)
        propertyPanelWidgets[#propertyPanelWidgets + 1] = yInput
        py = py + 24

        for _, field in ipairs(spec.fields) do
            local w
            if field.kind == "number" then
                w = CreateNumberInput(propertyPanelArea, field.label, el[field.key] or 0, 55, function(val)
                    el[field.key] = val
                    ScheduleRegenerate()
                end)
            else
                w = CreateTextInput(propertyPanelArea, field.label, tostring(el[field.key] or ""), 110, function(val)
                    el[field.key] = val
                    ScheduleRegenerate()
                end)
            end
            AnchorRow(w.frame, py)
            propertyPanelWidgets[#propertyPanelWidgets + 1] = w
            py = py + 24
        end

        local deleteBtn = DF.Widgets:CreateButton(propertyPanelArea, "Delete Element", 120)
        deleteBtn:SetPoint("TOPLEFT", propertyPanelArea, "TOPLEFT", 0, -(py + 8))
        deleteBtn:SetScript("OnClick", function() DeleteSelectedElement() end)
        propertyPanelWidgets[#propertyPanelWidgets + 1] = deleteBtn
        py = py + 8 + 24

        propertyPanelArea:SetHeight(math.max(24, py))
        RecalcRightPaneHeight()
    end

    UpdateSelectionOutline = function()
        local el = FindSelectedElement()
        local widget = el and liveWidgets[el.id]
        if not el or not widget or not widget.GetLeft then
            selectionOutline:Hide()
            return
        end
        local ok, left, bottom, width, height = pcall(function()
            return widget:GetLeft(), widget:GetBottom(), widget:GetWidth(), widget:GetHeight()
        end)
        if not ok or not left or not bottom then
            selectionOutline:Hide()
            return
        end
        selectionOutline:ClearAllPoints()
        selectionOutline:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - 2, bottom - 2)
        selectionOutline:SetSize((width or 0) + 4, (height or 0) + 4)
        selectionOutline:Show()
    end

    ---------------------------------------------------------------------------
    -- Public API
    ---------------------------------------------------------------------------
    local function RefreshRootFieldValues()
        ftSelector:SetValue(state.frameType)
        nameInput:SetText(state.globalName or "")
        parentInput:SetText(state.parent or "UIParent")
        widthInput:SetText(tostring(state.width or 300))
        heightInput:SetText(tostring(state.height or 200))
        anchorSelector:SetValue(state.anchor or "CENTER")
        offXInput:SetText(tostring(state.offsetX or 0))
        offYInput:SetText(tostring(state.offsetY or 0))
        for key, cb in pairs(featureCheckboxes) do cb:SetChecked(state[key] and true or false) end
        for key, cb in pairs(scriptCheckboxes) do cb:SetChecked(state[key] and true or false) end
    end

    -- Code -> model sync: debounced the same way visual-side edits are,
    -- and only on real typing (SetText from the visual side fires with
    -- userInput = false, so this never fights ScheduleRegenerate). On a
    -- successful parse the user's own text is left exactly as typed --
    -- only the property panel/preview/preview canvas are refreshed to
    -- match, and the change is reported upstream like any other edit.
    local codeParseTimer = nil
    codePreview:SetOnTextChanged(function(text, userInput)
        if not userInput then return end
        if codeParseTimer then codeParseTimer:Cancel() end
        codeParseTimer = C_Timer.NewTimer(0.5, function()
            codeParseTimer = nil
            local parsed = ParseCode(text, state)
            if parsed then
                state = parsed
                codeStatus:Hide()
                RefreshRootFieldValues()
                RefreshElementsList()
                RefreshPropertyPanel()
                ApplyPreview(state)
                if onChangeCallback then onChangeCallback(state, text) end
            else
                codeStatus:SetText("Couldn't sync from code -- check the CreateFrame/SetSize/SetPoint lines at the top")
                codeStatus:Show()
            end
        end)
    end)

    local builder = { frame = frame }

    -- Load a snippet's builderState (or nil/partial state, falling back to
    -- defaults for anything missing) and start reporting changes via
    -- onChange(state, code), debounced the same way field edits are.
    function builder:LoadState(loadedState, onChange)
        if regenerateTimer then regenerateTimer:Cancel(); regenerateTimer = nil end
        if codeParseTimer then codeParseTimer:Cancel(); codeParseTimer = nil end
        codeStatus:Hide()
        onChangeCallback = onChange

        state = DefaultState()
        if loadedState then
            for k, v in pairs(loadedState) do
                state[k] = v
            end
        end
        if type(state.elements) ~= "table" then state.elements = {} end
        state.selectedElementId = nil

        -- Rebuild seq counters from the loaded elements so freshly-added
        -- elements keep numbering forward instead of colliding with
        -- existing variable names.
        wipe(elementSeqCounters)
        local maxId = 0
        for _, el in ipairs(state.elements) do
            elementSeqCounters[el.type] = math.max(elementSeqCounters[el.type] or 0, el.seq or 0)
            if (el.id or 0) > maxId then maxId = el.id end
        end
        state.nextElementId = math.max(state.nextElementId or 1, maxId + 1)

        RefreshRootFieldValues()
        RefreshElementsList()
        RefreshPropertyPanel()
        codePreview:SetText(GenerateCode(state))
        ApplyPreview(state)
    end

    function builder:GetState()
        return state
    end

    function builder:GetCode()
        return codePreview:GetText()
    end

    return builder
end
