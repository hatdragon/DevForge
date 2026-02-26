local _, DF = ...

DF.SoundRuntime = {}

local SR = DF.SoundRuntime

local results = {}
local resultCount = 0
local listening = false
local seenIds = {}

---------------------------------------------------------------------------
-- Hooks: intercept PlaySound / PlaySoundFile calls to capture IDs
---------------------------------------------------------------------------
local origPlaySound
local origPlaySoundFile

local function OnSoundPlayed(soundId, sourceType, displayName)
    if not listening then return end
    if not soundId then return end
    local key = sourceType .. ":" .. tostring(soundId)
    if seenIds[key] then
        seenIds[key].time = GetTime()
        return
    end
    local name
    if displayName then
        name = displayName
    elseif sourceType == "kit" then
        name = "SoundKit:" .. soundId
    elseif sourceType == "music" then
        name = tostring(soundId):match("([^/\\]+)$") or tostring(soundId)
    else
        name = "FileID:" .. tostring(soundId)
    end
    local entry = {
        id = soundId,
        name = name,
        sourceType = sourceType,
        time = GetTime(),
    }
    seenIds[key] = entry
    resultCount = resultCount + 1
    results[resultCount] = entry
end

-- Hook PlaySound to capture SoundKit IDs
if PlaySound then
    hooksecurefunc("PlaySound", function(soundKitID, channel, forceNoDuplicates)
        if soundKitID then
            OnSoundPlayed(soundKitID, "kit")
        end
    end)
end

-- Hook PlaySoundFile to capture file-based sound IDs
if PlaySoundFile then
    hooksecurefunc("PlaySoundFile", function(soundFileOrID, channel)
        if soundFileOrID then
            OnSoundPlayed(soundFileOrID, "file")
        end
    end)
end

-- Hook PlayMusic to capture music paths
if PlayMusic then
    hooksecurefunc("PlayMusic", function(musicPath)
        if musicPath then
            OnSoundPlayed(musicPath, "music")
        end
    end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function SR:StartListening()
    listening = true
end

function SR:StopListening()
    listening = false
end

function SR:IsListening()
    return listening
end

function SR:GetResults()
    return results
end

function SR:GetCount()
    return resultCount
end

function SR:Clear()
    results = {}
    resultCount = 0
    seenIds = {}
end
