local _, DF = ...

DF.MacroStore = {}

local Store = DF.MacroStore

function Store:Init()
    -- Nothing to initialize; macros are stored by the WoW client
end

function Store:GetAll()
    local macros = {}
    local numAccount, numCharacter = GetNumMacros()

    -- Account macros: indices 1..numAccount
    for i = 1, numAccount do
        local name, iconTexture, body = GetMacroInfo(i)
        if name then
            macros[#macros + 1] = {
                index = i,
                name = name,
                icon = iconTexture,
                body = body or "",
                isCharacter = false,
            }
        end
    end

    -- Character macros: indices MAX_ACCOUNT_MACROS+1 .. MAX_ACCOUNT_MACROS+numCharacter
    local charStart = MAX_ACCOUNT_MACROS + 1
    for i = charStart, charStart + numCharacter - 1 do
        local name, iconTexture, body = GetMacroInfo(i)
        if name then
            macros[#macros + 1] = {
                index = i,
                name = name,
                icon = iconTexture,
                body = body or "",
                isCharacter = true,
            }
        end
    end

    return macros
end

function Store:Get(index)
    if not index then return nil end
    local name, iconTexture, body = GetMacroInfo(index)
    if not name then return nil end
    return {
        index = index,
        name = name,
        icon = iconTexture,
        body = body or "",
        isCharacter = (index > MAX_ACCOUNT_MACROS),
    }
end

function Store:GetBody(index)
    return GetMacroBody(index)
end

function Store:Save(index, body)
    if not index then return end
    EditMacro(index, nil, nil, body)
end

function Store:SaveFull(index, name, iconId, body)
    if not index then return end
    EditMacro(index, name, iconId, body)
end

function Store:Create(name, icon, body, isCharacter)
    local perCharacter = isCharacter and 1 or nil
    return CreateMacro(name or "New Macro", icon or "INV_Misc_QuestionMark", body or "", perCharacter)
end

function Store:Delete(index)
    if not index then return end
    DeleteMacro(index)
end

function Store:GetCounts()
    local numAccount, numCharacter = GetNumMacros()
    return numAccount, numCharacter
end

function Store:GetMaxCounts()
    return MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS
end
