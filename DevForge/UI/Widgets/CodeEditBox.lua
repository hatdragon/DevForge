local _, DF = ...

DF.Widgets = DF.Widgets or {}

function DF.Widgets:CreateCodeEditBox(parent, opts)
    opts = opts or {}
    local multiLine = opts.multiLine ~= false
    local readOnly = opts.readOnly or false

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

    -- Tab key inserts spaces
    if multiLine and not readOnly then
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

    return widget
end
