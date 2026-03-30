local _, DF = ...

-- ============================================================================
-- Flavor Detection
-- ============================================================================
DF.IsRetail    = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
DF.IsClassicEra = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
DF.IsClassic   = not DF.IsRetail

-- ============================================================================
-- C_AddOns polyfill (Retail 11.0+ namespace; Classic has legacy globals)
-- ============================================================================
if not C_AddOns then
    C_AddOns = {
        GetNumAddOns    = GetNumAddOns,
        GetAddOnInfo    = GetAddOnInfo,
        IsAddOnLoaded   = IsAddOnLoaded,
        LoadAddOn       = LoadAddOn,
        GetAddOnMetadata = GetAddOnMetadata,
    }
end

-- ============================================================================
-- HelpTip stub (Retail-only tutorial tooltip API; used in MainWindow.lua)
-- ============================================================================
if not HelpTip then
    HelpTip = {
        ButtonStyle = { GotIt = 1 },
        Point       = { BottomEdgeCenter = 1 },
        Alignment   = { Center = 1 },
        Show        = function() end,
        Hide        = function() end,
        IsShowing   = function() return false end,
    }
end
