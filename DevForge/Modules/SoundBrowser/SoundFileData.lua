local _, DF = ...

DF.SoundFileData = {}

local SFD = DF.SoundFileData

local RANGE_SIZE = 500

---------------------------------------------------------------------------
-- Generate a range of FileIDs to explore from a given start point.
-- Not all IDs will be playable — users try each one to discover sounds.
---------------------------------------------------------------------------
function SFD:GetRange(startId, count)
    count = count or RANGE_SIZE
    local ids = {}
    for i = startId, startId + count - 1 do
        ids[#ids + 1] = i
    end
    return ids
end

function SFD:GetDefaultRangeSize()
    return RANGE_SIZE
end
