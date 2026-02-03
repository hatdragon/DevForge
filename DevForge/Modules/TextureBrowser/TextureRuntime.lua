local _, DF = ...

DF.TextureRuntime = {}

local TR = DF.TextureRuntime

local results = {}
local resultCount = 0
local scanning = false
local scanTicker = nil
local seenPaths = {}

function TR:Scan(onProgress, onComplete)
    if scanning then return end
    scanning = true
    results = {}
    resultCount = 0
    seenPaths = {}

    -- Count total frames first for progress
    local totalFrames = 0
    local countFrame = EnumerateFrames()
    while countFrame do
        totalFrames = totalFrames + 1
        countFrame = EnumerateFrames(countFrame)
    end

    local currentFrame = EnumerateFrames()
    local processed = 0
    local BATCH_SIZE = 200

    scanTicker = C_Timer.NewTicker(0, function(ticker)
        if not scanning then
            ticker:Cancel()
            scanTicker = nil
            return
        end

        local batchEnd = processed + BATCH_SIZE

        while currentFrame and processed < batchEnd do
            processed = processed + 1

            local ok, frameName = pcall(function() return currentFrame:GetName() end)
            if not ok then frameName = nil end

            -- Scan all regions of this frame
            local regionOk, numRegions = pcall(function() return currentFrame:GetNumRegions() end)
            if regionOk and numRegions and numRegions > 0 then
                local regions = { pcall(currentFrame.GetRegions, currentFrame) }
                if regions[1] then
                    for i = 2, #regions do
                        local region = regions[i]
                        if region and type(region) == "table" then
                            -- Check if it's a texture region
                            local isTexture = false
                            local texOk, objType = pcall(function() return region:GetObjectType() end)
                            if texOk and objType == "Texture" then
                                isTexture = true
                            end

                            if isTexture then
                                -- Try GetAtlas first
                                local atlasOk, atlasInfo = pcall(function() return region:GetAtlas() end)
                                if atlasOk and atlasInfo and atlasInfo ~= "" then
                                    if not seenPaths[atlasInfo] then
                                        seenPaths[atlasInfo] = true
                                        resultCount = resultCount + 1
                                        results[resultCount] = {
                                            path = atlasInfo,
                                            name = atlasInfo,
                                            isAtlas = true,
                                            source = frameName or ("Frame#" .. processed),
                                        }
                                    end
                                end

                                -- Try GetTexture for file path/ID
                                local texPathOk, texPath = pcall(function() return region:GetTexture() end)
                                if texPathOk and texPath and texPath ~= "" then
                                    local pathKey = tostring(texPath)
                                    if not seenPaths[pathKey] then
                                        seenPaths[pathKey] = true
                                        local displayName
                                        if type(texPath) == "number" then
                                            displayName = "FileID:" .. texPath
                                        else
                                            displayName = tostring(texPath):match("([^\\]+)$") or tostring(texPath)
                                        end
                                        resultCount = resultCount + 1
                                        results[resultCount] = {
                                            path = texPath,
                                            name = displayName,
                                            isAtlas = false,
                                            source = frameName or ("Frame#" .. processed),
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end

            currentFrame = EnumerateFrames(currentFrame)
        end

        if onProgress then
            onProgress(processed, totalFrames)
        end

        if not currentFrame then
            scanning = false
            ticker:Cancel()
            scanTicker = nil
            if onComplete then
                onComplete(results, resultCount)
            end
        end
    end)
end

function TR:Cancel()
    scanning = false
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

function TR:IsScanning()
    return scanning
end

function TR:GetResults()
    return results
end

function TR:GetCount()
    return resultCount
end

function TR:Clear()
    results = {}
    resultCount = 0
    seenPaths = {}
end
