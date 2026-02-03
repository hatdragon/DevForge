local _, DF = ...

DF.APIBrowserList = {}

local BrowserList = DF.APIBrowserList

function BrowserList:Create(parent)
    local container = CreateFrame("Frame", nil, parent)

    -- Search box at top
    local searchBox = DF.Widgets:CreateSearchBox(container, "Search APIs...", 24)
    searchBox.frame:SetPoint("TOPLEFT", 0, 0)
    searchBox.frame:SetPoint("TOPRIGHT", 0, 0)

    -- Tree view below search
    local tree = DF.Widgets:CreateTreeView(container)
    tree.frame:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", 0, -2)
    tree.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    local list = {
        frame = container,
        searchBox = searchBox,
        tree = tree,
        allNodes = nil,
        onSelect = nil,
    }

    -- Search handler
    searchBox:SetOnSearch(function(query)
        if not query or query == "" then
            -- Show full tree
            if list.allNodes then
                tree:SetNodes(list.allNodes)
            end
            return
        end

        local results = DF.APIBrowserSearch:Find(query)
        if results then
            local searchNodes = DF.APIBrowserSearch:BuildSearchTree(results)
            if searchNodes then
                tree:SetNodes(searchNodes)
                -- Auto-expand all search results
                tree:ExpandAll()
            end
        end
    end)

    -- Tree selection handler
    tree:SetOnSelect(function(node)
        if list.onSelect and node then
            list.onSelect(node)
        end
    end)

    function list:SetNodes(nodes)
        self.allNodes = nodes
        self.tree:SetNodes(nodes)
    end

    function list:SetOnSelect(callback)
        self.onSelect = callback
    end

    function list:ExpandNamespace(nsName)
        self.tree:ExpandNode(nsName)
    end

    function list:SetSelected(id)
        self.tree:SetSelected(id)
    end

    return list
end
