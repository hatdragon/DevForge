local _, DF = ...

DF.Colors = {
    -- Syntax highlighting
    keyword     = "|cFFCC78FA",   -- purple
    string      = "|cFFCE9178",   -- orange
    number      = "|cFFB5CEA8",   -- green
    func        = "|cFF569CD6",   -- blue
    comment     = "|cFF6A9955",   -- dim green
    error       = "|cFFFF4444",   -- red
    tableRef    = "|cFF4EC9B0",   -- teal
    nilVal      = "|cFF808080",   -- gray
    boolTrue    = "|cFF569CD6",   -- blue
    boolFalse   = "|cFFCE9178",   -- orange
    secret      = "|cFFFF4444",   -- red
    text        = "|cFFD4D4D4",   -- light gray (default text)
    dim         = "|cFF808080",   -- dim gray

    -- UI colors (r, g, b, a tables)
    panelBg       = { 0.12, 0.12, 0.14, 0.95 },
    panelBorder   = { 0.3, 0.3, 0.3, 0.8 },
    titleBg       = { 0.15, 0.15, 0.17, 1 },
    tabActive     = { 0.25, 0.25, 0.28, 1 },
    tabInactive   = { 0.15, 0.15, 0.17, 1 },
    tabHover      = { 0.20, 0.20, 0.23, 1 },
    highlight     = { 0.3, 0.5, 0.8, 0.3 },
    buttonNormal  = { 0.18, 0.18, 0.20, 1 },
    buttonHover   = { 0.25, 0.25, 0.28, 1 },
    buttonPress   = { 0.12, 0.12, 0.14, 1 },
    inputBg       = { 0.08, 0.08, 0.10, 1 },
    scrollbar     = { 0.3, 0.3, 0.3, 0.6 },
    splitter      = { 0.3, 0.3, 0.3, 1 },
    inspectBlue   = { 0.2, 0.5, 1.0, 0.35 },
    inspectBorder = { 0.3, 0.6, 1.0, 0.8 },
    rowAlt        = { 0.14, 0.14, 0.16, 1 },
    rowSelected   = { 0.2, 0.35, 0.55, 0.6 },
    -- IDE layout colors
    activityBg     = { 0.10, 0.10, 0.12, 1 },
    activityActive = { 0.3, 0.5, 0.8, 1 },
    activityIcon   = { 0.55, 0.55, 0.55, 1 },
    activityIconActive = { 0.85, 0.85, 0.85, 1 },
    sidebarBg      = { 0.13, 0.13, 0.15, 1 },
    sidebarHeaderBg = { 0.16, 0.16, 0.18, 1 },
    bottomBg       = { 0.12, 0.12, 0.14, 1 },
    bottomTabActiveBg = { 0.20, 0.20, 0.23, 1 },
    bottomTabInactiveBg = { 0.13, 0.13, 0.15, 1 },
    badgeBg        = { 0.8, 0.2, 0.2, 1 },
    badgeText      = { 1, 1, 1, 1 },
}

DF.Fonts = {
    code    = "Interface\\AddOns\\DevForge\\Fonts\\ARIALN.TTF",
    codeAlt = "Fonts\\ARIALN.TTF",
    ui      = "Fonts\\FRIZQT__.TTF",
}

DF.Layout = {
    windowMinW    = 700,
    windowMinH    = 450,
    windowDefaultW = 900,
    windowDefaultH = 600,
    titleHeight   = 28,
    tabHeight      = 26,
    tabWidth       = 90,
    splitterWidth  = 4,
    scrollbarWidth = 12,
    rowHeight      = 18,
    buttonHeight   = 22,
    buttonPadding  = 6,
    padding        = 6,
    codeFontSize   = 12,
    uiFontSize     = 11,
    treeIndent      = 16,
    propertyLabelW  = 120,
    dropdownMaxWidth = 200,
    dropdownMinWidth = 120,
    -- IDE layout
    activityBarWidth = 48,
    activityIconSize = 36,
    activityBtnHeight = 42,
    activityGroupGap = 6,
    sidebarDefaultW = 220,
    sidebarMinW     = 140,
    sidebarMaxW     = 320,
    sidebarHeaderH  = 22,
    bottomDefaultH  = 150,
    bottomMinH      = 80,
    bottomMaxH      = 300,
    bottomTabHeight = 20,
    bottomCollapseH = 20,
}

DF.ADDON_NAME    = "DevForge"
DF.ADDON_VERSION = "1.0.0"
DF.MAX_HISTORY   = 200
DF.PRETTY_DEPTH  = 3
DF.DEBOUNCE_MS   = 200
