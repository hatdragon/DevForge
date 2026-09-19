local _, DF = ...

DF.Widgets = DF.Widgets or {}

-- Lua syntax colors for the vendored FAIAP indent/highlight library
-- (Libs/FAIAP/FAIAP.lua), reusing the same palette as the rest of the addon.
local FAIAP_COLORS = {
    [DF.Indent.tokens.TOKEN_KEYWORD] = DF.Colors.keyword,
    [DF.Indent.tokens.TOKEN_STRING] = DF.Colors.string,
    [DF.Indent.tokens.TOKEN_NUMBER] = DF.Colors.number,
    [DF.Indent.tokens.TOKEN_COMMENT_SHORT] = DF.Colors.comment,
    [DF.Indent.tokens.TOKEN_COMMENT_LONG] = DF.Colors.comment,
    [0] = "|r",
}

-- When FAIAP syntax highlighting is enabled, the EditBox's actual stored
-- text has |cAARRGGBB/|r color codes injected into it, so raw
-- GetCursorPosition()/SetCursorPosition() operate in that *encoded* text's
-- byte offsets -- not the decoded/clean text GetText() returns. Converts a
-- byte offset in the decoded text to the matching offset in the encoded
-- text via FAIAP's own position-aware color stripper (binary search, since
-- stripping only ever removes characters so the mapping is monotonic).
-- Falls back to the identity mapping when highlighting isn't active.
local function EncodedOffsetFromDecoded(editbox, decodedOffset)
    if not (DF.Indent.coloredGetText and DF.Indent.stripWowColorsWithPos) then
        return decodedOffset
    end
    local ok, rawText = pcall(DF.Indent.coloredGetText, editbox)
    if not ok or not rawText or #rawText == 0 then return decodedOffset end
    local lo, hi = 0, #rawText
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local okStrip, _, decPos = pcall(DF.Indent.stripWowColorsWithPos, rawText, mid)
        if not okStrip then return decodedOffset end
        if (decPos - 1) < decodedOffset then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

local TT = DF.Indent.tokens

-- Given a token stream (DF.Util:TokenizeLua) and a 0-based cursor offset,
-- finds the innermost function call enclosing the cursor: walks backward
-- from the last token before the cursor, tracking paren depth (a `)` seen
-- going backward means "skip one extra matching `(`"; hitting a `(` at
-- depth 0 is *our* call's open paren) while counting commas seen at depth
-- 0 along the way -- that count is the 0-based parameter index. Then reads
-- the identifier/dot/colon chain immediately before that `(` as the
-- function name. Returns (fullNameChain, paramIndex) or nil if the cursor
-- isn't inside a recognizable call.
local function FindSignatureContext(tokens, cursorOffset)
    local idx = 0
    for i = 1, #tokens do
        if tokens[i].endPos <= cursorOffset then
            idx = i
        else
            break
        end
    end
    if idx == 0 then return nil end

    local depth, paramIndex, openIdx = 0, 0, nil
    for i = idx, 1, -1 do
        local tok = tokens[i]
        if tok.type == TT.TOKEN_RIGHTPAREN then
            depth = depth + 1
        elseif tok.type == TT.TOKEN_LEFTPAREN then
            if depth == 0 then
                openIdx = i
                break
            end
            depth = depth - 1
        elseif tok.type == TT.TOKEN_COMMA and depth == 0 then
            paramIndex = paramIndex + 1
        end
    end
    if not openIdx then return nil end

    local j = openIdx - 1
    if not (tokens[j] and tokens[j].type == TT.TOKEN_IDENTIFIER) then
        return nil
    end
    local nameParts = { tokens[j].text }
    j = j - 1
    while tokens[j] and (tokens[j].type == TT.TOKEN_PERIOD or tokens[j].type == TT.TOKEN_COLON) do
        local sep = tokens[j].text
        local identTok = tokens[j - 1]
        if not (identTok and identTok.type == TT.TOKEN_IDENTIFIER) then break end
        table.insert(nameParts, 1, sep)
        table.insert(nameParts, 1, identTok.text)
        j = j - 2
    end

    return table.concat(nameParts), paramIndex
end

function DF.Widgets:CreateCodeEditBox(parent, opts)
    opts = opts or {}
    local multiLine = opts.multiLine ~= false
    local readOnly = opts.readOnly or false
    local highlightEnabled = multiLine and opts.syntaxHighlight ~= false

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(container, true)
    container:SetBackdropColor(unpack(DF.Colors.inputBg))

    -- The actual EditBox
    local editbox
    if multiLine then
        local scrollFrame = CreateFrame("ScrollFrame", nil, container)
        scrollFrame:SetPoint("TOPLEFT", 4, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)

        editbox = CreateFrame("EditBox", nil, scrollFrame)
        editbox:SetMultiLine(true)
        editbox:SetAutoFocus(false)
        editbox:SetFontObject(DF.Theme:CodeFont())
        editbox:SetTextColor(0.83, 0.83, 0.83, 1)
        editbox:SetWidth(math.max(50, scrollFrame:GetWidth() or 400))
        editbox:SetHeight(math.max(100, scrollFrame:GetHeight() or 100))
        editbox:SetTextInsets(4, 4, 2, 2)

        scrollFrame:SetScrollChild(editbox)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = math.max(0, editbox:GetHeight() - self:GetHeight())
            local newScroll = DF.Util:Clamp(current - delta * 30, 0, maxScroll)
            self:SetVerticalScroll(newScroll)
        end)

        -- Keep editbox sized to fill visible area (so clicks anywhere land on it)
        scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
            if w and w > 10 then
                editbox:SetWidth(w)
            end
            if h and h > 0 then
                local textH = editbox:GetHeight()
                if textH < h then
                    editbox:SetHeight(h)
                end
            end
        end)

        -- Clicking empty space in the scroll area focuses the editbox
        scrollFrame:SetScript("OnMouseDown", function()
            editbox:SetFocus()
        end)

        container.scrollFrame = scrollFrame
    else
        editbox = CreateFrame("EditBox", nil, container)
        editbox:SetPoint("TOPLEFT", 6, -4)
        editbox:SetPoint("BOTTOMRIGHT", -6, 4)
        editbox:SetAutoFocus(false)
        editbox:SetFontObject(DF.Theme:CodeFont())
        editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    end

    if readOnly then
        editbox:SetScript("OnChar", function() end)
        editbox:EnableKeyboard(false)
        editbox:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)
    end

    -- Tab key inserts spaces (FAIAP takes over Tab for context-aware indent
    -- when syntax highlighting is enabled, so skip this to avoid double-indent)
    if multiLine and not readOnly and not highlightEnabled then
        editbox:SetScript("OnTabPressed", function(self)
            self:Insert("    ")
        end)
    end

    -- Escape clears focus
    editbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Widget API
    local widget = {
        frame = container,
        editbox = editbox,
        multiLine = multiLine,
        -- Undo/redo state (populated below for editable multiLine boxes)
        undoStack = {},
        redoStack = {},
        _skipSnapshot = false,
        _lastSavedText = "",
        _lastSavedCursor = 0,
        _typing = false,
        _undoTimer = nil,
    }

    function widget:GetText()
        return self.editbox:GetText() or ""
    end

    function widget:SetText(text)
        self._skipSnapshot = true
        self.editbox:SetText(text or "")
        self._skipSnapshot = false
        -- Reset undo state when text is set programmatically (loading a snippet, etc.)
        self._lastSavedText = text or ""
        self._lastSavedCursor = 0
        self._typing = false
    end

    function widget:SetFocus()
        self.editbox:SetFocus()
    end

    function widget:ClearFocus()
        self.editbox:ClearFocus()
    end

    function widget:SetOnTextChanged(callback)
        self._onTextChangedCallback = callback
    end

    function widget:SetOnEnterPressed(callback)
        self.editbox:SetScript("OnEnterPressed", callback)
    end

    -- Fires callback on Ctrl+S while this box has focus
    function widget:SetOnSaveShortcut(callback)
        DF.Util:HookSaveShortcut(self.editbox, callback)
    end

    function widget:Enable()
        self.editbox:EnableKeyboard(true)
        self.editbox:EnableMouse(true)
    end

    function widget:Disable()
        self.editbox:EnableKeyboard(false)
        self.editbox:EnableMouse(false)
    end

    function widget:SetCursorToEnd()
        self.editbox:SetCursorPosition(#self:GetText())
    end

    function widget:ScrollToBottom()
        if self.frame.scrollFrame then
            local maxScroll = math.max(0, self.editbox:GetHeight() - self.frame.scrollFrame:GetHeight())
            self.frame.scrollFrame:SetVerticalScroll(maxScroll)
        end
    end

    function widget:HighlightText(start, finish)
        self.editbox:HighlightText(start or 0, finish or -1)
    end

    function widget:Insert(text)
        self.editbox:Insert(text)
    end

    -- Moves the cursor to a byte offset in the DECODED text (optionally
    -- highlighting the next `highlightLen` characters, e.g. a search
    -- match). WoW's EditBox already auto-scrolls its parent ScrollFrame to
    -- keep the cursor visible when it moves off-screen, so no manual
    -- scroll math is needed -- the only wrinkle is translating the offset
    -- through EncodedOffsetFromDecoded when syntax highlighting is active.
    function widget:JumpToOffset(decodedOffset, highlightLen)
        local encodedOffset = EncodedOffsetFromDecoded(self.editbox, decodedOffset)
        self.editbox:SetCursorPosition(encodedOffset)
        if highlightLen and highlightLen > 0 then
            local encodedEnd = EncodedOffsetFromDecoded(self.editbox, decodedOffset + highlightLen)
            self.editbox:HighlightText(encodedOffset, encodedEnd)
        end
    end

    -- Returns (fullDecodedText, cursorOffset), both derived from a single
    -- fresh read of the *actual current* EditBox content. Deliberately
    -- does not use self:GetText() here: FAIAP caches its decoded text and
    -- only invalidates that cache on its own ~0.2s idle recolor pass --
    -- an independent timer that can fire after (not before) a caller's own
    -- debounce, so self:GetText() can return text missing the most recent
    -- keystrokes mid-typing. Position-sensitive callers (autocomplete,
    -- find/replace, jump-to-line) need both values from the *same* snapshot
    -- or splicing text back together duplicates/misplaces characters.
    function widget:GetTextAndCursor()
        if DF.Indent.coloredGetText and DF.Indent.stripWowColorsWithPos then
            local ok, rawText = pcall(DF.Indent.coloredGetText, self.editbox)
            if ok and rawText then
                local rawPos = self.editbox:GetCursorPosition()
                local okStrip, decodedFull, decPos = pcall(DF.Indent.stripWowColorsWithPos, rawText, rawPos)
                if okStrip then
                    return decodedFull, decPos - 1
                end
            end
        end
        local text = self:GetText()
        return text, self.editbox:GetCursorPosition()
    end

    -- The (decoded) text up to the cursor -- used to detect "what's being
    -- typed" for autocomplete triggers.
    function widget:GetTextBeforeCursor()
        local text, pos = self:GetTextAndCursor()
        return text:sub(1, pos)
    end

    -- ── Undo / Redo (multiLine, editable only) ──────────────────────────
    if multiLine and not readOnly then
        local UNDO_MAX = 50
        local DEBOUNCE = 0.4

        function widget:PushUndo(text, cursorPos)
            text = text or self:GetText()
            cursorPos = cursorPos or self.editbox:GetCursorPosition()
            local stack = self.undoStack
            -- Skip duplicate consecutive states
            if #stack > 0 and stack[#stack].text == text then
                return
            end
            stack[#stack + 1] = { text = text, cursor = cursorPos }
            -- Cap size
            if #stack > UNDO_MAX then
                table.remove(stack, 1)
            end
            -- Any new edit clears the redo stack
            self.redoStack = {}
        end

        function widget:Undo()
            local stack = self.undoStack
            if #stack == 0 then return end
            -- Save current state to redo stack
            local cur = self:GetText()
            local curCursor = self.editbox:GetCursorPosition()
            self.redoStack[#self.redoStack + 1] = { text = cur, cursor = curCursor }
            -- Pop undo stack
            local prev = table.remove(stack)
            self._skipSnapshot = true
            self.editbox:SetText(prev.text)
            self.editbox:SetCursorPosition(prev.cursor)
            self._skipSnapshot = false
            self._lastSavedText = prev.text
            self._lastSavedCursor = prev.cursor
            self._typing = false
        end

        function widget:Redo()
            local rstack = self.redoStack
            if #rstack == 0 then return end
            -- Save current state to undo stack
            local cur = self:GetText()
            local curCursor = self.editbox:GetCursorPosition()
            self.undoStack[#self.undoStack + 1] = { text = cur, cursor = curCursor }
            -- Pop redo stack
            local next = table.remove(rstack)
            self._skipSnapshot = true
            self.editbox:SetText(next.text)
            self.editbox:SetCursorPosition(next.cursor)
            self._skipSnapshot = false
            self._lastSavedText = next.text
            self._lastSavedCursor = next.cursor
            self._typing = false
        end

        function widget:ResetUndo()
            self.undoStack = {}
            self.redoStack = {}
            self._lastSavedText = self:GetText()
            self._lastSavedCursor = 0
            self._typing = false
        end

        -- Debounce timer frame (invisible, just for OnUpdate timing)
        local timerFrame = CreateFrame("Frame")
        timerFrame:Hide()
        timerFrame.elapsed = 0
        timerFrame:SetScript("OnUpdate", function(tf, dt)
            tf.elapsed = tf.elapsed + dt
            if tf.elapsed >= DEBOUNCE then
                tf:Hide()
                -- Timer fired: push the pre-edit snapshot
                if widget._typing then
                    widget:PushUndo(widget._lastSavedText, widget._lastSavedCursor)
                    widget._lastSavedText = widget:GetText()
                    widget._lastSavedCursor = widget.editbox:GetCursorPosition()
                    widget._typing = false
                end
            end
        end)
        widget._undoTimer = timerFrame

        -- Hook OnTextChanged for debounced snapshots + user callback
        local origTextChanged = editbox:GetScript("OnTextChanged")
        editbox:SetScript("OnTextChanged", function(eb, userInput)
            if origTextChanged then origTextChanged(eb, userInput) end
            -- Fire user-supplied callback
            local cb = widget._onTextChangedCallback
            if cb then cb(eb:GetText(), userInput) end
            if widget._skipSnapshot then return end
            if not userInput then return end
            -- First keystroke after idle: capture pre-edit state
            if not widget._typing then
                widget._typing = true
            end
            -- Reset debounce timer
            timerFrame.elapsed = 0
            timerFrame:Show()
        end)

        -- Hook OnKeyDown for Ctrl+Z / Ctrl+Shift+Z
        editbox:HookScript("OnKeyDown", function(eb, key)
            if key == "Z" and IsControlKeyDown() then
                if IsShiftKeyDown() then
                    -- Flush any pending typing snapshot before redo
                    if widget._typing then
                        widget:PushUndo(widget._lastSavedText, widget._lastSavedCursor)
                        widget._lastSavedText = widget:GetText()
                        widget._lastSavedCursor = widget.editbox:GetCursorPosition()
                        widget._typing = false
                        timerFrame:Hide()
                    end
                    widget:Redo()
                else
                    -- Flush any pending typing snapshot before undo
                    if widget._typing then
                        widget:PushUndo(widget._lastSavedText, widget._lastSavedCursor)
                        widget._lastSavedText = widget:GetText()
                        widget._lastSavedCursor = widget.editbox:GetCursorPosition()
                        widget._typing = false
                        timerFrame:Hide()
                    end
                    widget:Undo()
                end
            end
        end)

        -- Seed initial state
        widget._lastSavedText = editbox:GetText() or ""
        widget._lastSavedCursor = 0
    else
        -- Non-undo path: still wire up the user callback
        local origTextChanged = editbox:GetScript("OnTextChanged")
        editbox:SetScript("OnTextChanged", function(eb, userInput)
            if origTextChanged then origTextChanged(eb, userInput) end
            local cb = widget._onTextChangedCallback
            if cb then cb(eb:GetText(), userInput) end
        end)
    end

    ---------------------------------------------------------------------------
    -- Autocomplete against the WoW API surface (DF.APIBrowserData). Opt-in,
    -- editable multiline boxes only. Scoped to API members, not local
    -- variables or other snippets' functions -- that needs a real per-file
    -- symbol table, out of scope here.
    ---------------------------------------------------------------------------
    if opts.autocomplete and multiLine and not readOnly then
        local AC_MAX = 30
        local ROW_H = 18
        local suggestBox, suggestRows = nil, {}
        local suggestItems, matchedChain, selectedIndex = {}, "", 1
        local acTimer = nil
        local focusLostTimer = nil

        -- Parameter auto-fill state: set after accepting a function
        -- completion that has real argument names. `fillOpenOffset` is the
        -- fixed decoded offset right after the call's "(" -- deliberately
        -- the *only* position stored, since a per-parameter start/end would
        -- go stale the moment an earlier parameter's replacement text has a
        -- different length. Each Tab re-scans forward from that one fixed
        -- point instead.
        local fillOpenOffset, fillCount, fillIndex = nil, 0, 0

        local sigBox, sigText = nil, nil

        local function HideSuggestions()
            if suggestBox then suggestBox:Hide() end
            suggestItems = {}
        end

        local function HideSignatureHelp()
            if sigBox then sigBox:Hide() end
        end

        local function ExitFillMode()
            fillOpenOffset, fillCount, fillIndex = nil, 0, 0
        end

        local function EnsureSuggestBox()
            if suggestBox then return suggestBox end
            suggestBox = CreateFrame("Frame", nil, container, "BackdropTemplate")
            suggestBox:SetFrameStrata("TOOLTIP")
            DF.Theme:ApplyDarkPanel(suggestBox, true)
            -- Docked to a fixed corner of the editor rather than the literal
            -- caret -- WoW's EditBox exposes no caret-to-screen-pixel API,
            -- so exact "popup at the cursor" positioning isn't achievable.
            suggestBox:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -4)
            suggestBox:SetWidth(280)
            suggestBox:Hide()
            return suggestBox
        end

        local function EnsureSigBox()
            if sigBox then return sigBox end
            sigBox = CreateFrame("Frame", nil, container, "BackdropTemplate")
            sigBox:SetFrameStrata("TOOLTIP")
            DF.Theme:ApplyDarkPanel(sigBox, true)
            -- Bottom-right corner (completions dock top-right) so the two
            -- never overlap if both happen to apply at once.
            sigBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)
            sigBox:SetHeight(22)
            sigText = sigBox:CreateFontString(nil, "OVERLAY")
            sigText:SetFontObject(DF.Theme:UIFont())
            sigText:SetPoint("LEFT", 6, 0)
            sigText:SetPoint("RIGHT", -6, 0)
            sigText:SetJustifyH("LEFT")
            sigText:SetWordWrap(false)
            sigBox:Hide()
            return sigBox
        end

        -- Shows entry's signature with the paramIndex-th argument (0-based)
        -- highlighted. Mirrors APIBrowserDetail:FormatFunction's field
        -- usage (Name/Nilable) so the two stay consistent. No-ops (hides)
        -- when the entry has no Arguments data -- true for every function
        -- sourced from the _G-scan fallback.
        local function ShowSignatureHelp(entry, paramIndex)
            local args = entry.doc and entry.doc.Arguments
            if not args or #args == 0 then
                HideSignatureHelp()
                return
            end
            local box = EnsureSigBox()
            local parts = {}
            for i, arg in ipairs(args) do
                local label = arg.Name or "?"
                if arg.Nilable then label = label .. " [optional]" end
                if (i - 1) == paramIndex then
                    label = "|cffffd200" .. label .. "|r"
                else
                    label = "|cff999999" .. label .. "|r"
                end
                parts[#parts + 1] = label
            end
            sigText:SetText(entry.fullName .. "(" .. table.concat(parts, ", ") .. ")")
            local textW = sigText:GetStringWidth() or 200
            box:SetWidth(math.min(500, math.max(120, textW + 20)))
            box:Show()
        end

        local function CheckSignatureHelp()
            if not DF.APIBrowserData then
                HideSignatureHelp()
                return
            end
            local text, cursorPos = widget:GetTextAndCursor()
            local tokens = DF.Util:TokenizeLua(text)
            local funcName, paramIndex = FindSignatureContext(tokens, cursorPos)
            local entry = funcName and DF.APIBrowserData:GetEntryByFullName(funcName)
            if not entry then
                HideSignatureHelp()
                return
            end
            ShowSignatureHelp(entry, paramIndex)
        end

        -- Re-scans forward from the fixed fillOpenOffset (see above) to
        -- find the *current* start/end of the `index`-th (1-based)
        -- comma-separated argument and highlights it. Token-based (not raw
        -- character scanning) so a comma/paren typed inside an earlier
        -- parameter's string value doesn't confuse the split. Returns false
        -- if that parameter no longer exists (call was edited/removed).
        local function HighlightParamRange(index)
            if not fillOpenOffset then return false end
            -- Fresh read (see GetTextAndCursor) -- FAIAP's cached GetText()
            -- can be stale if the user just typed over the previous
            -- parameter and hit Tab again before FAIAP's own idle recolor
            -- refreshed the cache, which would compute wrong ranges here.
            local text = widget:GetTextAndCursor()
            local tokens = DF.Util:TokenizeLua(text)
            local openTokIdx = nil
            for i, tok in ipairs(tokens) do
                if tok.type == TT.TOKEN_LEFTPAREN and tok.endPos == fillOpenOffset then
                    openTokIdx = i
                    break
                end
            end
            if not openTokIdx then return false end

            local depth, curIndex, segStart = 0, 1, fillOpenOffset
            for i = openTokIdx + 1, #tokens do
                local tok = tokens[i]
                if tok.type == TT.TOKEN_LEFTPAREN then
                    depth = depth + 1
                elseif tok.type == TT.TOKEN_RIGHTPAREN and depth == 0 then
                    if curIndex == index then
                        widget:JumpToOffset(segStart, math.max(0, (tok.startPos - 1) - segStart))
                        return true
                    end
                    return false
                elseif tok.type == TT.TOKEN_RIGHTPAREN then
                    depth = depth - 1
                elseif tok.type == TT.TOKEN_COMMA and depth == 0 then
                    if curIndex == index then
                        widget:JumpToOffset(segStart, math.max(0, (tok.startPos - 1) - segStart))
                        return true
                    end
                    curIndex = curIndex + 1
                    segStart = tok.endPos
                end
            end
            return false
        end

        local function AcceptSuggestion(idx)
            local item = suggestItems[idx]
            if not item then return end
            -- Both halves must come from the same snapshot (see
            -- GetTextAndCursor) -- splicing text/cursor read at different
            -- moments is what caused characters to duplicate.
            local fullText, cursorPos = widget:GetTextAndCursor()
            local textBefore = fullText:sub(1, cursorPos)
            local textAfter = fullText:sub(cursorPos + 1)
            local prefix = textBefore:sub(1, #textBefore - #matchedChain)

            -- Functions with known argument names get them inserted for
            -- real (not just empty parens), with the first one immediately
            -- highlighted for tab-through auto-fill; WoW's EditBox already
            -- replaces a highlighted range when you type over it, so no
            -- custom replace logic is needed for the actual editing.
            local isFunction = item.type == "function"
            local argNames = {}
            if isFunction and item.doc and item.doc.Arguments then
                for _, arg in ipairs(item.doc.Arguments) do
                    argNames[#argNames + 1] = arg.Name or "arg"
                end
            end

            local insertion = item.fullName
            if isFunction then
                insertion = insertion .. "(" .. table.concat(argNames, ", ") .. ")"
            end

            local newTextBefore = prefix .. insertion
            widget:SetText(newTextBefore .. textAfter)
            HideSuggestions()
            -- Clicking a suggestion (rather than pressing Enter/Tab) blurs
            -- the EditBox first (see the OnEditFocusLost handling above) --
            -- without restoring focus here, keystrokes right after a click-
            -- accept would fall through to the game's own keybinds instead
            -- of continuing to type, with no visible cursor to show why.
            widget:SetFocus()
            -- That same blur armed a deferred cleanup (OnEditFocusLost)
            -- that would otherwise fire a moment from now and wipe out the
            -- fill-mode/signature-help state this function is about to set
            -- up -- cancel it, since we're handling cleanup ourselves here.
            if focusLostTimer then
                focusLostTimer:Cancel()
                focusLostTimer = nil
            end

            ExitFillMode()
            if isFunction and #argNames > 0 then
                fillOpenOffset = #prefix + #item.fullName + 1
                fillCount = #argNames
                fillIndex = 1
                HighlightParamRange(1)
            else
                widget:JumpToOffset(isFunction and (#newTextBefore - 1) or #newTextBefore)
            end

            -- SetText marks this as a non-user-input change (it is,
            -- mechanically), but accepting a suggestion is a real,
            -- user-initiated edit -- notify listeners (e.g. Frame Builder's
            -- code-sync, which only reacts to userInput=true) as such.
            if widget._onTextChangedCallback then
                widget._onTextChangedCallback(widget:GetText(), true)
            end

            CheckSignatureHelp()
        end

        local function RefreshSuggestBox()
            local box = EnsureSuggestBox()
            for _, row in ipairs(suggestRows) do row:Hide() end
            for i, item in ipairs(suggestItems) do
                local row = suggestRows[i]
                if not row then
                    row = CreateFrame("Button", nil, box)
                    row:RegisterForClicks("LeftButtonUp")
                    row:SetHeight(ROW_H)
                    local hl = row:CreateTexture(nil, "BACKGROUND")
                    hl:SetAllPoints()
                    hl:SetColorTexture(unpack(DF.Colors.highlight))
                    row.hl = hl
                    local text = row:CreateFontString(nil, "OVERLAY")
                    text:SetFontObject(DF.Theme:UIFont())
                    text:SetPoint("LEFT", 4, 0)
                    text:SetPoint("RIGHT", -4, 0)
                    text:SetJustifyH("LEFT")
                    text:SetWordWrap(false)
                    row.text = text
                    suggestRows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(i - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -(i - 1) * ROW_H)
                local label = item.fullName
                if item.type == "function" then
                    local argNames = {}
                    if item.doc and item.doc.Arguments then
                        for _, arg in ipairs(item.doc.Arguments) do
                            argNames[#argNames + 1] = arg.Name or "arg"
                        end
                    end
                    label = label .. "(" .. table.concat(argNames, ", ") .. ")"
                end
                row.text:SetText(label)
                row.text:SetTextColor(0.83, 0.83, 0.83, 1)
                row.hl:SetShown(i == selectedIndex)
                row:SetScript("OnClick", function() AcceptSuggestion(i) end)
                -- Re-set every refresh (not just at row creation), same
                -- reason OnClick is: rows are pooled and reused for
                -- different list positions, so a handler set only once at
                -- creation would close over a stale `i`. Hovering moves the
                -- highlight/selection so it's obvious which item Enter/
                -- click will accept.
                row:SetScript("OnEnter", function()
                    if selectedIndex ~= i then
                        selectedIndex = i
                        RefreshSuggestBox()
                    end
                end)
                row:Show()
            end
            box:SetHeight(math.max(1, #suggestItems) * ROW_H + 4)
            box:Show()
        end

        local function CheckAutocomplete()
            local textBefore = widget:GetTextBeforeCursor()
            local chain = textBefore:match("[%w_%.:]+$") or ""
            if #chain < 2 or not DF.APIBrowserData then
                HideSuggestions()
                return
            end
            if not DF.APIBrowserData:IsLoaded() then
                DF.APIBrowserData:Load()
            end
            local lowerChain = chain:lower()
            local starts, contains = {}, {}
            for _, entry in ipairs(DF.APIBrowserData:GetAllEntries()) do
                local lowerFull = entry.fullName:lower()
                if lowerFull:sub(1, #lowerChain) == lowerChain then
                    starts[#starts + 1] = entry
                elseif lowerFull:find(lowerChain, 1, true) then
                    contains[#contains + 1] = entry
                end
                if #starts >= AC_MAX then break end
            end
            local results = {}
            for _, e in ipairs(starts) do
                if #results >= AC_MAX then break end
                results[#results + 1] = e
            end
            for _, e in ipairs(contains) do
                if #results >= AC_MAX then break end
                results[#results + 1] = e
            end
            if #results == 0 then
                HideSuggestions()
                return
            end
            suggestItems = results
            matchedChain = chain
            selectedIndex = 1
            RefreshSuggestBox()
        end

        editbox:HookScript("OnTextChanged", function(eb, userInput)
            if not userInput then return end
            HideSuggestions()
            HideSignatureHelp()
            if acTimer then acTimer:Cancel() end
            acTimer = C_Timer.NewTimer(0.2, function()
                acTimer = nil
                CheckAutocomplete()
                CheckSignatureHelp()
            end)
        end)

        -- Consumes Up/Down/Enter/Tab/Escape while suggestions are showing,
        -- or Tab/Escape while in parameter fill mode -- normal typing
        -- (including Enter-for-newline and Tab-indent when neither is
        -- active) is completely unaffected.
        editbox:HookScript("OnKeyDown", function(eb, key)
            if suggestBox and suggestBox:IsShown() and #suggestItems > 0 then
                if key == "UP" then
                    selectedIndex = math.max(1, selectedIndex - 1)
                    RefreshSuggestBox()
                    eb:SetPropagateKeyboardInput(false)
                elseif key == "DOWN" then
                    selectedIndex = math.min(#suggestItems, selectedIndex + 1)
                    RefreshSuggestBox()
                    eb:SetPropagateKeyboardInput(false)
                elseif key == "ENTER" or key == "TAB" then
                    AcceptSuggestion(selectedIndex)
                    eb:SetPropagateKeyboardInput(false)
                elseif key == "ESCAPE" then
                    HideSuggestions()
                    eb:SetPropagateKeyboardInput(false)
                end
                return
            end

            if fillOpenOffset then
                if key == "TAB" then
                    fillIndex = fillIndex + 1
                    if fillIndex > fillCount or not HighlightParamRange(fillIndex) then
                        ExitFillMode()
                    end
                    eb:SetPropagateKeyboardInput(false)
                elseif key == "ESCAPE" then
                    ExitFillMode()
                    eb:SetPropagateKeyboardInput(false)
                end
            end
        end)

        -- Clicking a suggestion row blurs the EditBox first (standard WoW
        -- behavior: any click outside the currently-focused EditBox clears
        -- its focus) -- if this ran synchronously it would clear
        -- suggestItems before the row's own OnClick (which fires on mouse-
        -- up, a moment later) gets to read it, so AcceptSuggestion always
        -- found nothing. Deferring by one tick lets that click finish first;
        -- AcceptSuggestion's own HideSuggestions() call makes this a no-op
        -- in the normal "accepted a suggestion" case either way.
        editbox:HookScript("OnEditFocusLost", function()
            focusLostTimer = C_Timer.NewTimer(0.15, function()
                focusLostTimer = nil
                HideSuggestions()
                HideSignatureHelp()
                ExitFillMode()
            end)
        end)
    end

    -- Enable syntax highlighting last, so it chains after our own
    -- OnTextChanged/OnTabPressed hooks rather than being overwritten by them.
    -- Explicit tabWidth forces space-based indent (a non-nil/non-false
    -- tabWidth picks FAIAP's fillWithSpaces over fillWithTabs) -- our code
    -- font doesn't have a glyph for literal tab characters, so they render
    -- as boxes.
    if highlightEnabled then
        DF.Indent.enable(editbox, FAIAP_COLORS, 4)
    end

    return widget
end
