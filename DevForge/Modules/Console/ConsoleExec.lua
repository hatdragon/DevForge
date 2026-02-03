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

    -- Hook print temporarily (always restore via the function-scoped origPrint)
    local origPrint = print
    local hookPrint = (printCapture ~= false)
    if hookPrint then
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring(select(i, ...))
            end
            prints[#prints + 1] = table.concat(parts, "    ")
        end
    end

    -- Wrapped execution: guarantees print is restored even on unexpected errors
    local function DoExecute()
        local success, results, err

        -- Try as expression first (return ...)
        local exprFn, exprErr = loadstring("return " .. evalCode)
        if exprFn then
            setfenv(exprFn, setmetatable({ DF = DF, DevForge = DF }, { __index = _G, __newindex = _G }))

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
            local stmtFn, stmtErr = loadstring(evalCode)
            if stmtFn then
                setfenv(stmtFn, setmetatable({ DF = DF, DevForge = DF }, { __index = _G, __newindex = _G }))

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

    -- ALWAYS restore print, no matter what happened above
    if hookPrint then
        print = origPrint
    end

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

    local origPrint = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        prints[#prints + 1] = table.concat(parts, "    ")
    end

    local success, results, err

    local fn, loadErr = loadstring(code)
    if fn then
        setfenv(fn, setmetatable({ DF = DF, DevForge = DF }, { __index = _G, __newindex = _G }))

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

    print = origPrint

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
