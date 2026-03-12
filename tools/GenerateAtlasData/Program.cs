using System.Text;
using System.Text.RegularExpressions;

// ============================================================================
// GenerateAtlasData - Fetches UiTextureAtlasMember data from wago.tools
// and generates TextureAtlasData.lua for DevForge's TextureBrowser module.
//
// Usage:
//   dotnet run [-- <output-path>]
//
// If no output path is given, writes to stdout.
// ============================================================================

var outputPath = args.Length > 0 ? args[0] : null;

const string CsvUrl = "https://wago.tools/db2/UiTextureAtlasMember/csv";

// ---------------------------------------------------------------------------
// Category rules: first match wins.  Checked case-insensitively.
// Each rule has an id (Lua table key), display name, and list of patterns.
// A pattern starting with "^" is a prefix match; otherwise it's a substring.
// ---------------------------------------------------------------------------
var categoryRules = new (string Id, string Name, string[] Patterns)[]
{
    // Expansion-specific (check before generic keywords to avoid mis-buckets)
    ("expansion_midnight", "Midnight", new[] { "^midnight-", "-midnight-", "-midnight", "^_ui-frame-midnight", "midnightexpansion", "midnightcampaign" }),
    ("expansion_tww",      "The War Within", new[] { "^thewarwithin-", "^warwithin-", "^warband", "^warbands-", "^accountupgradebanner-" }),
    ("expansion_df",       "Dragonflight", new[] { "^dragonflight-", "^dragonriding-", "^majorfactions-" }),
    ("expansion_sl",       "Shadowlands", new[] {
        "^animachannel-", "^animadiversion-", "^covenantchoice-", "^covenant-", "^covenantmission-",
        "^covenantsanctum-", "^covenantrenown", "^soulbind", "^jailerstower-", "^torghast-",
        "^shadowlands-", "^maw-", "^oribos-", "^necrolord", "^nightfae", "^venthyr", "^kyrian",
        "^zerethmortispath", "^eyeofthejailer-", "^eyeofthejailer_", "^runecarving-" }),
    ("expansion_bfa",      "BfA Content", new[] {
        "^darkshore_warfront", "^islands-", "^warfront-", "^warfronts-", "^warfronts_",
        "^azeriteessence-", "^azerite-",
        "^heartofazeroth", "^nazjatar-", "^bfa-", "^ui-hud-unitframe-player-corruption",
        "^visions-", "^nzoth-", "^mechagon-" }),
    ("expansion_art",      "Artifacts & Azerite", new[] { "^artifacts", "^artifactsfx-" }),

    // Feature systems
    ("adventures",    "Adventures",           new[] { "^adventuremap", "^adventures-" }),
    ("alliedraces",   "Allied Races",         new[] { "^alliedrace-", "^racetrait-" }),
    ("achievements",  "Achievements",         new[] { "^achievementcompare-", "^achievement-", "^ui-achievement-" }),
    ("actionbar",     "Action Bar",           new[] { "^actionbar_", "^ui-hud-actionbar-" }),
    ("auctionhouse",  "Auction House",        new[] { "^auctionhouse-" }),
    ("bags",          "Bags & Bank",          new[] { "^bag-", "^bags-", "^bank-", "^banker" }),
    ("calendar",      "Calendar",             new[] { "^calendar-", "^calendar_" }),
    ("castbar",       "Cast Bar",             new[] { "^ui-castingbar-" }),
    ("chat",          "Chat",                 new[] { "^chatframe-", "^chat-", "^chatbubble-", "^ui-chaticon-" }),
    ("class",         "Class & Spec",         new[] {
        "^classicon-", "^classhall-", "^classhall_", "^class_",
        "^deathknight-", "^demonhunter-", "^druid-", "^evoker-", "^hunter-", "^mage-",
        "^monk-", "^paladin-", "^priest-", "^rogue-", "^shaman-", "^warlock-", "^warrior-",
        "^ui-hud-unitframe-player-class",
        "^specialization-", "^specdial-", "^specdial_",
        "^spec-", "^raceicon", "^relic-" }),
    ("collections",   "Collections",          new[] {
        "^collections-", "^mountjournalicons-", "^mountjournal-", "^mountjournal_",
        "^petjournal-", "^petjournalexpbar-", "^petjournalheader-",
        "^transmog-", "^transmog_", "^wardrobeicon-", "^ui-wardrobe-",
        "^heirloom-", "^toybox-", "^itemset-" }),
    ("common",        "Common Icons",         new[] { "^commoniconmask", "^common-icon-", "^common-",
                                                       "^category-", "^category_" }),
    ("crafting",      "Crafting & Professions", new[] {
        "^professions-", "^professions_", "^profession-", "^craftingorders-",
        "^tradeskill-", "^ui-professions-", "^proglan-", "^proglan_" }),
    ("cursor",        "Cursors & Crosshairs", new[] { "^crosshair_", "^cursor_", "^ui-cursor-" }),
    ("delves",        "Delves",               new[] { "^delve-", "^delves-", "^delves_" }),
    ("dungeons",      "Dungeons & Raids",     new[] {
        "^dungeon-", "^dungeons-", "^raidframe-", "^raid-", "^ui-ej-",
        "^encounterjournal-", "^encounterjournal_", "^mythicplus-", "^mythic-",
        "^activities-", "^activities_" }),
    ("editmode",      "Edit Mode",            new[] { "^editmode-" }),
    ("gamepad",       "Gamepad",              new[] { "^gamepad-", "^gamepad_" }),
    ("garrison",      "Garrison & Missions",  new[] { "^garr-", "^garr_", "^garrison", "^garrission", "^garrmission", "^garrisoncurrencyicon-",
                                                       "^garrbuilding-", "^garrbuilding_", "^garrlanding-", "^garrlanding_",
                                                       "^orderhallcommandbar-", "^orderhall-", "^orderhalltalents-",
                                                       "^legionmission-", "^legionmission_",
                                                       "^shipmission", "^ships-", "^ships_" }),
    ("glues",         "Character Select",     new[] { "^charactercreate-", "^charactercreate_", "^characterselect-",
                                                       "^characterservices-", "^glues-", "^charselect-", "^glue-",
                                                       "^splash-", "^streamcinematic-", "^vas-" }),
    ("gm",            "GM & System",          new[] { "^gm-", "^gm_", "^gmchat-", "^ui-hud-chat-chatframe-icon-gm",
                                                       "^customerservice-", "^ui-hud-chat-bug", "^gmquest-", "^reportingui-",
                                                       "^evergreen-", "^evergreen_" }),
    ("groupfinder",   "Group Finder",         new[] { "^groupfinder-", "^premade-", "^lfgicon-", "^lfg-", "^ui-lfg-" }),
    ("housing",       "Housing",              new[] { "^house-", "^housefinder", "^housing-", "^housing_",
                                                       "^decor-", "^furblan-", "^furblan_" }),
    ("hud",           "HUD & Unit Frames",    new[] { "^hud-", "^ui-hud-", "^unitframe-", "^uf-" }),
    ("loot",          "Loot & Rewards",       new[] { "^loot-", "^loottoast-", "^grouploot-", "^bonusobjective",
                                                       "^ui-loot-", "^alliedrace-rewardframe-",
                                                       "^itemupgrade", "^ui-itemupgrade-",
                                                       "^greatvault-", "^greatvault_",
                                                       "^perks-", "^perks_",
                                                       "^tokens-", "^tokens_" }),
    ("map",           "Map & Navigation",     new[] { "^worldmap-", "^minimap-", "^flightmap-", "^flightmaster-",
                                                       "^taxinode-", "^poi-", "^navigation-",
                                                       "^worldquest-", "^ui-worldmap-",
                                                       "^worldstate-", "^worldstate_" }),
    ("nameplates",    "Nameplates",           new[] { "^nameplate-", "^ui-hud-nameplate-" }),
    ("ping",          "Ping System",          new[] { "^ping-", "^ping_" }),
    ("plunderstorm",  "Plunderstorm",         new[] { "^plunderstorm-" }),
    ("pvp",           "PvP",                  new[] { "^pvp-", "^pvpqueue-", "^pvprating-", "^warmode-",
                                                       "^conquestbar-", "^honor-", "^prestige-", "^ui-hud-unitframe-player-pvp",
                                                       "^scoreboard-", "^hearthsteel-" }),
    ("quest",         "Quest",                new[] { "^quest-", "^questlog-", "^questtracker-", "^quest_",
                                                       "^ui-quest", "^campaignquest-", "^questcomplete-",
                                                       "^wrapper", "^questbg-", "^questbg_",
                                                       "^campaign-" }),
    ("spellbook",     "Spellbook",            new[] { "^spellbook-", "^spellbook_", "^ui-spellbook-" }),
    ("store",         "Store & Shop",         new[] { "^shop-", "^catalogshop-", "^subsupgrade-",
                                                       "^recruitafriend-", "^recruitafriend_" }),
    ("talents",       "Talents",              new[] { "^talents-", "^talenttree-", "^talentree-", "^talent-",
                                                       "^classtrial-", "^specialization-",
                                                       "^hero-talent", "^herotrait-" }),
    ("tooltip",       "Tooltip & Frames",     new[] { "^tooltip-", "^tooltipicon-" }),
    ("tutorial",      "Tutorial",             new[] { "^newplayertutorial-", "^tutorial-", "^helptip-" }),
    ("frames",        "UI Chrome & Frames",   new[] { "^ui-frame-", "^ui-silver-", "^ui-button", "^nineslice-",
                                                       "-nineslice-edge", "^ui-", "^uitools-",
                                                       "^minimal-", "^minimal_" }),
    ("voicechat",     "Voice Chat",           new[] { "^voicechat-", "^voice-" }),
};

// ---------------------------------------------------------------------------
// Fetch CSV
// ---------------------------------------------------------------------------
Console.Error.WriteLine("Fetching CSV from wago.tools...");
using var http = new HttpClient();
http.DefaultRequestHeaders.Add("User-Agent", "DevForge-GenerateAtlasData/1.0");
var csv = await http.GetStringAsync(CsvUrl);
Console.Error.WriteLine($"Downloaded {csv.Length:N0} bytes.");

// ---------------------------------------------------------------------------
// Parse CSV - find CommittedName column index
// ---------------------------------------------------------------------------
var lines = csv.Split('\n');
if (lines.Length < 2)
{
    Console.Error.WriteLine("ERROR: CSV has no data rows.");
    return;
}

var header = ParseCsvLine(lines[0]);
int nameCol = Array.IndexOf(header, "CommittedName");
if (nameCol < 0)
{
    Console.Error.WriteLine("ERROR: 'CommittedName' column not found in CSV header.");
    Console.Error.WriteLine($"  Columns: {string.Join(", ", header)}");
    return;
}

// ---------------------------------------------------------------------------
// Extract atlas names (skip blank/numeric-only)
// ---------------------------------------------------------------------------
var allNames = new HashSet<string>(StringComparer.Ordinal);
for (int i = 1; i < lines.Length; i++)
{
    var line = lines[i].TrimEnd('\r');
    if (string.IsNullOrWhiteSpace(line)) continue;

    var cols = ParseCsvLine(line);
    if (cols.Length <= nameCol) continue;

    var name = cols[nameCol].Trim();
    if (string.IsNullOrEmpty(name)) continue;
    if (Regex.IsMatch(name, @"^\d+$")) continue; // skip numeric-only

    allNames.Add(name);
}

Console.Error.WriteLine($"Parsed {allNames.Count:N0} unique atlas names.");

// ---------------------------------------------------------------------------
// Categorize
// ---------------------------------------------------------------------------
var buckets = new Dictionary<string, List<string>>();
foreach (var rule in categoryRules)
    buckets[rule.Id] = new List<string>();
buckets["misc"] = new List<string>();

foreach (var name in allNames)
{
    var lower = name.ToLowerInvariant();
    bool matched = false;

    foreach (var rule in categoryRules)
    {
        foreach (var pattern in rule.Patterns)
        {
            bool isMatch;
            if (pattern.StartsWith('^'))
            {
                isMatch = lower.StartsWith(pattern[1..], StringComparison.Ordinal);
            }
            else
            {
                isMatch = lower.Contains(pattern, StringComparison.Ordinal);
            }

            if (isMatch)
            {
                buckets[rule.Id].Add(name);
                matched = true;
                break;
            }
        }
        if (matched) break;
    }

    if (!matched)
        buckets["misc"].Add(name);
}

// Sort each bucket alphabetically (case-insensitive, matching WoW behavior)
foreach (var kvp in buckets)
    kvp.Value.Sort(StringComparer.OrdinalIgnoreCase);

// Build ordered category list: alphabetically by name, Miscellaneous last
var orderedCategories = categoryRules
    .Where(r => buckets[r.Id].Count > 0)
    .Select(r => (r.Id, r.Name, Count: buckets[r.Id].Count))
    .OrderBy(c => c.Name, StringComparer.OrdinalIgnoreCase)
    .ToList();

// Always add Miscellaneous at the end if it has entries
if (buckets["misc"].Count > 0)
    orderedCategories.Add(("misc", "Miscellaneous", buckets["misc"].Count));

int totalCount = orderedCategories.Sum(c => c.Count);

// ---------------------------------------------------------------------------
// Generate Lua
// ---------------------------------------------------------------------------
var sb = new StringBuilder();
sb.AppendLine("local _, DF = ...");
sb.AppendLine();
sb.AppendLine("DF.TextureAtlasData = {}");
sb.AppendLine();
sb.AppendLine("local TAD = DF.TextureAtlasData");
sb.AppendLine();
sb.AppendLine("-- Auto-generated from wago.tools UiTextureAtlasMember DB2 table");
sb.AppendLine($"-- Generated: {DateTime.UtcNow:yyyy-MM-dd}");
sb.AppendLine($"-- Total atlas entries: {totalCount}");
sb.AppendLine();

// CATEGORIES table
sb.AppendLine("local CATEGORIES = {");
foreach (var cat in orderedCategories)
{
    sb.AppendLine($"    {{ id = \"{cat.Id}\", name = \"{cat.Name}\", count = {cat.Count} }},");
}
sb.AppendLine("}");
sb.AppendLine();

// ATLAS_DATA tables
sb.AppendLine("local ATLAS_DATA = {}");
sb.AppendLine();

foreach (var cat in orderedCategories)
{
    var names = buckets[cat.Id];
    sb.AppendLine($"ATLAS_DATA[\"{cat.Id}\"] = {{");

    // Write 3 names per line, matching the existing format
    for (int i = 0; i < names.Count; i += 3)
    {
        sb.Append("    ");
        int end = Math.Min(i + 3, names.Count);
        for (int j = i; j < end; j++)
        {
            sb.Append($"\"{names[j]}\"");
            if (j < names.Count - 1)
                sb.Append(", ");
        }
        sb.AppendLine();
    }

    sb.AppendLine("}");
    sb.AppendLine();
}

// API functions
sb.AppendLine();
sb.AppendLine("-- Cached flat array of all atlas names");
sb.AppendLine("local allAtlasesCache = nil");
sb.AppendLine();
sb.AppendLine("function TAD:GetCategories()");
sb.AppendLine("    return CATEGORIES");
sb.AppendLine("end");
sb.AppendLine();
sb.AppendLine("function TAD:GetAtlases(categoryId)");
sb.AppendLine("    return ATLAS_DATA[categoryId] or {}");
sb.AppendLine("end");
sb.AppendLine();
sb.AppendLine("function TAD:GetAllAtlases()");
sb.AppendLine("    if allAtlasesCache then return allAtlasesCache end");
sb.AppendLine("    allAtlasesCache = {}");
sb.AppendLine("    for _, cat in ipairs(CATEGORIES) do");
sb.AppendLine("        local atlases = ATLAS_DATA[cat.id]");
sb.AppendLine("        if atlases then");
sb.AppendLine("            for _, name in ipairs(atlases) do");
sb.AppendLine("                allAtlasesCache[#allAtlasesCache + 1] = name");
sb.AppendLine("            end");
sb.AppendLine("        end");
sb.AppendLine("    end");
sb.AppendLine("    return allAtlasesCache");
sb.AppendLine("end");

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------
var output = sb.ToString();

if (outputPath != null)
{
    // Resolve relative paths
    var fullPath = Path.GetFullPath(outputPath);
    var dir = Path.GetDirectoryName(fullPath);
    if (dir != null && !Directory.Exists(dir))
        Directory.CreateDirectory(dir);

    File.WriteAllText(fullPath, output, new UTF8Encoding(false));
    Console.Error.WriteLine($"Wrote {fullPath}");
    Console.Error.WriteLine($"  Categories: {orderedCategories.Count}");
    Console.Error.WriteLine($"  Total entries: {totalCount}");

    // Print category summary
    foreach (var cat in orderedCategories)
        Console.Error.WriteLine($"    {cat.Name}: {cat.Count}");
}
else
{
    Console.Write(output);
}

// ---------------------------------------------------------------------------
// CSV parser (handles quoted fields)
// ---------------------------------------------------------------------------
static string[] ParseCsvLine(string line)
{
    var fields = new List<string>();
    int i = 0;
    while (i < line.Length)
    {
        if (line[i] == '"')
        {
            // Quoted field
            i++;
            var sb = new StringBuilder();
            while (i < line.Length)
            {
                if (line[i] == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"')
                    {
                        sb.Append('"');
                        i += 2;
                    }
                    else
                    {
                        i++; // skip closing quote
                        break;
                    }
                }
                else
                {
                    sb.Append(line[i]);
                    i++;
                }
            }
            fields.Add(sb.ToString());
            if (i < line.Length && line[i] == ',') i++; // skip comma
        }
        else
        {
            // Unquoted field
            int start = i;
            while (i < line.Length && line[i] != ',') i++;
            fields.Add(line[start..i]);
            if (i < line.Length) i++; // skip comma
        }
    }
    return fields.ToArray();
}
