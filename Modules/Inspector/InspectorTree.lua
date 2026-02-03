local _, DF = ...

DF.InspectorTree = {}

local InspTree = DF.InspectorTree

-- Get a display name for a frame (uses SecretGuard to handle 12.x secret values)
local function GetFrameName(frame)
    -- GetDebugName gives full path for anonymous frames (e.g. "PlayerFrame.HealthBar")
    local debugName, okD = DF.SecretGuard:SafeGet(frame, "GetDebugName")
    if okD and type(debugName) == "string" and debugName ~= "" then return debugName end

    local name, okN = DF.SecretGuard:SafeGet(frame, "GetName")
    if okN and type(name) == "string" and name ~= "" then return name end

    local objType, okT = DF.SecretGuard:SafeGet(frame, "GetObjectType")
    if okT and type(objType) == "string" then
        return "<" .. objType .. ">"
    end

    return tostring(frame)
end

-- Get the object type
local function GetFrameType(frame)
    local objType, ok = DF.SecretGuard:SafeGet(frame, "GetObjectType")
    return (ok and type(objType) == "string") and objType or "?"
end

-- Build a tree node for a frame
local function BuildNode(frame, depth)
    depth = depth or 0
    if depth > 20 then return nil end -- Safety limit

    local name = GetFrameName(frame)
    local objType = GetFrameType(frame)

    local node = {
        id = tostring(frame),
        text = name .. " |cFF808080(" .. objType .. ")|r",
        data = frame,
        children = {},
    }

    -- Get children (frames)
    local ok, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if ok and children then
        for _, child in ipairs(children) do
            local childNode = BuildNode(child, depth + 1)
            if childNode then
                node.children[#node.children + 1] = childNode
            end
        end
    end

    -- Get regions (textures, fontstrings, etc.)
    local regOk, regions = pcall(function()
        return { frame:GetRegions() }
    end)
    if regOk and regions then
        for _, region in ipairs(regions) do
            local regionName = GetFrameName(region)
            local regionType = GetFrameType(region)
            node.children[#node.children + 1] = {
                id = tostring(region),
                text = regionName .. " |cFF808080(" .. regionType .. ")|r",
                data = region,
                children = nil,
            }
        end
    end

    if #node.children == 0 then
        node.children = nil
    end

    return node
end

-- Build tree from a picked frame: walk up to root, then build subtree
function InspTree:BuildFromFrame(pickedFrame)
    if not pickedFrame then return {} end

    -- Walk up to find the root (or a reasonable ancestor)
    local root = pickedFrame
    local depth = 0
    while depth < 50 do
        local ok, parent = pcall(function() return root:GetParent() end)
        if not ok or not parent or parent == UIParent or parent == WorldFrame then
            break
        end
        root = parent
        depth = depth + 1
    end

    -- Build tree from root
    local rootNode = BuildNode(root, 0)
    if rootNode then
        return { rootNode }
    end

    return {}
end

-- Build tree of just the immediate family (parent, siblings, children)
function InspTree:BuildFamilyTree(frame)
    if not frame then return {} end

    -- Get parent (stop at UIParent/WorldFrame — they have too many children to be useful)
    local parentOk, parent = pcall(function() return frame:GetParent() end)
    if not parentOk or not parent or parent == UIParent or parent == WorldFrame then
        local node = BuildNode(frame, 0)
        return node and { node } or {}
    end

    -- Build parent node with its children
    local parentNode = BuildNode(parent, 0)
    return parentNode and { parentNode } or {}
end

-- Find the node ID for a given frame in the tree
function InspTree:FindNodeId(frame)
    return tostring(frame)
end
