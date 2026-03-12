local _, DF = ...

DF.ConsoleExec = {}

local Exec = DF.ConsoleExec

-- Route a slash command through WoW's slash command handler
-- Returns: handled (bool), prints (table of captured output strings)
function Exec:TrySlashCommand(code)
    if not code or code:sub(1, 1) ~= "/" then
        return false, {}
    end

    local cmd, args = code:match("^(/[^%s]+)%s*(.*)")
    if not cmd then return false, {} end

    cmd = cmd:upper()

    -- Build hash table if needed (same as WoW does on first use)
    if ChatFrame_ImportAllListsToHash then
        ChatFrame_ImportAllListsToHash()
    end

    local handler
    if hash_SlashCmdList and hash_SlashCmdList[cmd] then
        handler = hash_SlashCmdList[cmd]
    end

    if not handler then
        -- Try chat type commands (/say, /yell, /whisper)
        if hash_ChatTypeInfoList and hash_ChatTypeInfoList[cmd] then
            local chatType = hash_ChatTypeInfoList[cmd]
            if chatType then
                SendChatMessage(args or "", chatType)
                return true, {}
            end
        end
        return false, {}
    end

    -- Hook print() and DEFAULT_CHAT_FRAME:AddMessage() for the duration of the
    -- synchronous handler call. WoW Lua is single-threaded, so no incoming chat
    -- events can fire during pcall — only messages the handler itself produces.
    local prints = {}

    local origPrint = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        prints[#prints + 1] = table.concat(parts, "    ")
    end

    local chatFrame = DEFAULT_CHAT_FRAME
    local origAddMsg = chatFrame and chatFrame.AddMessage
    if chatFrame and origAddMsg then
        chatFrame.AddMessage = function(self, text, ...)
            if text then
                local clean = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                prints[#prints + 1] = clean
            end
        end
    end

    local ok, err = pcall(handler, args or "")

    -- Restore immediately — any subsequent async chat goes to chat frame as normal
    print = origPrint
    if chatFrame and origAddMsg then
        chatFrame.AddMessage = origAddMsg
    end

    if not ok then
        prints[#prints + 1] = tostring(err)
    end

    return true, prints
end

-- Error handler for xpcall: reports the error to DevForge's ErrorHandler
-- for the Errors tab, then returns the message so xpcall captures it for
-- console display. We deliberately do NOT forward to geterrorhandler() here
-- because our seterrorhandler hook would also call ProcessError, creating
-- a duplicate entry with a different stack trace.
local function ConsoleErrorHandler(msg)
    if DF.ErrorHandler then
        pcall(DF.ErrorHandler.Report, DF.ErrorHandler, msg, debugstack(2), "console")
    end
    return msg
end

-- Execute a string of Lua code, returning results
-- Returns: { success = bool, results = { ... }, prints = { ... }, error = string }
function Exec:Execute(code, printCapture)
    if not code or code == "" then
        return { success = true, results = {}, prints = {} }
    end

    -- Handle slash commands first
    if code:sub(1, 1) == "/" then
        local handled, slashPrints = self:TrySlashCommand(code)
        if handled then
            return { success = true, results = {}, prints = slashPrints, slashCommand = true }
        end
        return {
            success = false,
            results = {},
            prints = {},
            error = "Unknown slash command: " .. (code:match("^(/[^%s]+)") or code),
        }
    end

    -- Strip leading '=' for expression evaluation (like /run)
    local evalCode = code
    if evalCode:sub(1, 1) == "=" then
        evalCode = evalCode:sub(2)
    end

    -- Captured print output
    local prints = {}
    local hookPrint = (printCapture ~= false)
    local doneExecuting = false

    -- Build a custom print that captures output into our prints table.
    -- During synchronous execution, output is stored for FormatResults.
    -- After Execute returns (deferred callbacks like C_Timer), output is
    -- sent directly to the bottom panel via DF_OUTPUT_LINE.
    local capturedPrint
    if hookPrint then
        capturedPrint = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring(select(i, ...))
            end
            local line = table.concat(parts, "    ")
            if not doneExecuting then
                prints[#prints + 1] = line
            elseif DF.EventBus then
                DF.EventBus:Fire("DF_OUTPUT_LINE", { text = line })
            end
        end
    end

    local env = setmetatable({ DF = DF, DevForge = DF }, { __index = _G, __newindex = _G })

    -- Stash captured print in a temp global so loadstring'd code can grab it
    -- via a chunk-level local.  Varargs approach (select(1,...)) is unreliable
    -- in WoW 12.x loadstring chunks.
    local preamble = capturedPrint and "local print = rawget(_G,'_DF_CAPTURED_PRINT') or print; " or ""
    if capturedPrint then
        rawset(_G, "_DF_CAPTURED_PRINT", capturedPrint)
    end

    -- Wrapped execution
    local function DoExecute()
        local success, results, err

        -- Try as expression first (return ...)
        local exprFn, exprErr = loadstring(preamble .. "return " .. evalCode, "=(console)")
        if exprFn then
            setfenv(exprFn, env)

            local retValues = { xpcall(exprFn, ConsoleErrorHandler) }
            if retValues[1] then
                success = true
                results = {}
                for i = 2, #retValues do
                    results[i - 1] = retValues[i]
                end
            else
                success = false
                err = tostring(retValues[2])
            end
        else
            -- Try as statement
            local stmtFn, stmtErr = loadstring(preamble .. evalCode, "=(console)")
            if stmtFn then
                setfenv(stmtFn, env)

                local retValues = { xpcall(stmtFn, ConsoleErrorHandler) }
                if retValues[1] then
                    success = true
                    results = {}
                    for i = 2, #retValues do
                        results[i - 1] = retValues[i]
                    end
                else
                    success = false
                    err = tostring(retValues[2])
                end
            else
                success = false
                err = tostring(stmtErr)
            end
        end

        return success, results, err
    end

    local execOk, success, results, err = pcall(DoExecute)

    -- Mark synchronous execution done. Any deferred callbacks (C_Timer, etc.)
    -- that call print will now route directly to DF_OUTPUT_LINE.
    doneExecuting = true
    rawset(_G, "_DF_CAPTURED_PRINT", nil)

    if not execOk then
        -- DoExecute itself errored (shouldn't happen, but safety net)
        return {
            success = false,
            results = {},
            prints = prints,
            error = "Internal execution error: " .. tostring(success),
        }
    end

    return {
        success = success,
        results = results or {},
        prints = prints,
        error = err,
    }
end

-- Execute code as a statement with varargs (for addon file simulation).
-- No slash command handling, no expression-first attempt.
-- Returns: { success = bool, results = { ... }, prints = { ... }, error = string }
function Exec:ExecuteFile(code, ...)
    if not code or code == "" then
        return { success = true, results = {}, prints = {} }
    end

    local prints = {}
    local args = { ... }
    local nArgs = select("#", ...)
    local doneExecuting = false

    local capturedPrint = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        local line = table.concat(parts, "    ")
        if not doneExecuting then
            prints[#prints + 1] = line
        elseif DF.EventBus then
            DF.EventBus:Fire("DF_OUTPUT_LINE", { text = line })
        end
    end

    local success, results, err

    -- Stash captured print in a temp global so the chunk-level local can grab
    -- it.  Varargs are reserved for the file's own arguments (addon name, etc).
    rawset(_G, "_DF_CAPTURED_PRINT", capturedPrint)
    local fn, loadErr = loadstring("local print = rawget(_G,'_DF_CAPTURED_PRINT') or print; " .. code, "=(snippet)")
    if fn then
        local env = setmetatable({ DF = DF, DevForge = DF }, { __index = _G, __newindex = _G })
        setfenv(fn, env)

        local retValues = { xpcall(function() return fn(unpack(args, 1, nArgs)) end, ConsoleErrorHandler) }
        if retValues[1] then
            success = true
            results = {}
            for i = 2, #retValues do
                results[i - 1] = retValues[i]
            end
        else
            success = false
            err = tostring(retValues[2])
        end
    else
        success = false
        err = tostring(loadErr)
    end
    doneExecuting = true
    rawset(_G, "_DF_CAPTURED_PRINT", nil)

    return {
        success = success,
        results = results or {},
        prints = prints,
        error = err,
    }
end

-- Format execution results as colored text lines
function Exec:FormatResults(result)
    if not result then return {} end
    local lines = {}

    -- Print output
    if result.prints then
        for _, line in ipairs(result.prints) do
            lines[#lines + 1] = DF.Colors.text .. line .. "|r"
        end
    end

    -- Return values
    if result.success then
        if result.results and #result.results > 0 then
            for _, val in ipairs(result.results) do
                lines[#lines + 1] = DF.Util:PrettyPrint(val)
            end
        end
    else
        if result.error then
            lines[#lines + 1] = DF.Colors.error .. result.error .. "|r"
        end
    end

    return lines
end
