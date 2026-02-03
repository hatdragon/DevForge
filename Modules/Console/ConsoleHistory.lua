local _, DF = ...

DF.ConsoleHistory = {}

local History = DF.ConsoleHistory

local history = {}
local position = 0
local tempInput = ""

function History:Init()
    -- Load from saved variables
    if DevForgeDB and DevForgeDB.consoleHistory then
        history = DevForgeDB.consoleHistory
    end
    position = #history + 1
    tempInput = ""
end

function History:Add(text)
    if not text or text == "" then return end

    -- Don't add duplicates of the last entry
    if #history > 0 and history[#history] == text then
        position = #history + 1
        return
    end

    history[#history + 1] = text

    -- Trim to max
    while #history > DF.MAX_HISTORY do
        table.remove(history, 1)
    end

    position = #history + 1
    tempInput = ""

    -- Persist
    if DevForgeDB then
        DevForgeDB.consoleHistory = history
    end
end

-- Navigate up in history, returns the text or nil
function History:Up(currentText)
    if #history == 0 then return nil end

    -- Save current text if at the bottom
    if position > #history then
        tempInput = currentText or ""
    end

    position = math.max(1, position - 1)

    return history[position]
end

-- Navigate down in history, returns the text or nil
function History:Down(currentText)
    if #history == 0 then return tempInput end

    position = math.min(#history + 1, position + 1)

    if position > #history then
        return tempInput
    end

    return history[position]
end

-- Reset position to bottom (after executing)
function History:ResetPosition()
    position = #history + 1
    tempInput = ""
end

-- Get all history entries
function History:GetAll()
    return history
end

-- Get count
function History:Count()
    return #history
end

-- Clear history
function History:Clear()
    wipe(history)
    position = 1
    tempInput = ""
    if DevForgeDB then
        DevForgeDB.consoleHistory = history
    end
end
