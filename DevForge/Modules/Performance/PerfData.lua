local _, DF = ...

DF.PerfData = {}

local PerfData = DF.PerfData

local snapshots = {}          -- { name -> snapshot }
local virtualSnapshots = {}   -- { key -> snapshot } for debug/run-project entries
local sortedList = {}         -- sorted array of snapshots
local ticker = nil
local onUpdate = nil
local pollingInterval = 2

local function NewSnapshot(name)
    return {
        name = name,
        memory = 0,
        memoryDelta = 0,
        memoryPeak = 0,
        cpu = nil,
        cpuDelta = 0,
        cpuPerSec = 0,
        enabled = false,
        loaded = false,
    }
end

local function DoUpdate()
    local profilingOn = GetCVarBool("scriptProfile")

    UpdateAddOnMemoryUsage()
    if profilingOn then
        UpdateAddOnCPUUsage()
    end

    local numAddons = C_AddOns.GetNumAddOns()
    for i = 1, numAddons do
        local name, _, _, enabled, loadable, reason, security = C_AddOns.GetAddOnInfo(i)
        if name then
            local mem = GetAddOnMemoryUsage(i) or 0
            local snap = snapshots[name]
            if not snap then
                snap = NewSnapshot(name)
                snapshots[name] = snap
            end

            local prevMem = snap.memory
            snap.memory = mem
            snap.memoryDelta = mem - prevMem
            if mem > snap.memoryPeak then
                snap.memoryPeak = mem
            end

            snap.enabled = enabled or false
            snap.loaded = C_AddOns.IsAddOnLoaded(i)

            if profilingOn then
                local cpu = GetAddOnCPUUsage(i) or 0
                local prevCpu = snap.cpu or 0
                snap.cpuDelta = cpu - prevCpu
                snap.cpuPerSec = (pollingInterval > 0) and (snap.cpuDelta / pollingInterval) or 0
                snap.cpu = cpu
            else
                snap.cpu = nil
                snap.cpuDelta = 0
                snap.cpuPerSec = 0
            end
        end
    end

    -- Poll virtual entries (debug/run-project)
    for _, snap in pairs(virtualSnapshots) do
        if snap.pollFn then
            local ok, data = pcall(snap.pollFn)
            if ok and data and data.cpu then
                local prevCpu = snap.cpu or 0
                snap.cpu = data.cpu
                snap.cpuDelta = data.cpu - prevCpu
                snap.cpuPerSec = (pollingInterval > 0) and (snap.cpuDelta / pollingInterval) or 0
            end
        end
    end

    -- Rebuild sorted list (real + virtual)
    wipe(sortedList)
    for _, snap in pairs(snapshots) do
        if snap.loaded then
            sortedList[#sortedList + 1] = snap
        end
    end
    for _, snap in pairs(virtualSnapshots) do
        sortedList[#sortedList + 1] = snap
    end

    if onUpdate then onUpdate() end
end

function PerfData:Init()
    pollingInterval = (DevForgeDB and DevForgeDB.perfPollingInterval) or 2
    DoUpdate()
end

function PerfData:StartPolling()
    if ticker then return end
    ticker = C_Timer.NewTicker(pollingInterval, DoUpdate)
end

function PerfData:StopPolling()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function PerfData:GetSnapshots()
    return sortedList
end

function PerfData:GetTotalMemory()
    local total = 0
    for _, snap in pairs(snapshots) do
        total = total + (snap.memory or 0)
    end
    return total
end

function PerfData:GetTotalCPU()
    local total = 0
    for _, snap in pairs(snapshots) do
        total = total + (snap.cpu or 0)
    end
    return total
end

function PerfData:IsProfilingEnabled()
    return GetCVarBool("scriptProfile")
end

function PerfData:SetPollingInterval(sec)
    pollingInterval = sec
    if DevForgeDB then
        DevForgeDB.perfPollingInterval = sec
    end
    if ticker then
        self:StopPolling()
        self:StartPolling()
    end
end

function PerfData:GetPollingInterval()
    return pollingInterval
end

function PerfData:ForceUpdate()
    DoUpdate()
end

function PerfData:Reset()
    for _, snap in pairs(snapshots) do
        snap.memoryDelta = 0
        snap.memoryPeak = snap.memory
        if snap.cpu then
            snap.cpuDelta = 0
            snap.cpuPerSec = 0
        end
    end
    if onUpdate then onUpdate() end
end

function PerfData:SetOnUpdate(cb)
    onUpdate = cb
end

-- Virtual entries for debug / Run Project tracking
function PerfData:RegisterVirtual(key, name, pollFn)
    local snap = NewSnapshot(name)
    snap.loaded = true
    snap.virtual = true
    snap.pollFn = pollFn
    virtualSnapshots[key] = snap
    return snap
end

function PerfData:UnregisterVirtual(key)
    virtualSnapshots[key] = nil
end
