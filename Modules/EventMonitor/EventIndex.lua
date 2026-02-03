local _, DF = ...

DF.EventIndex = {}

local Index = DF.EventIndex

--[[
    Comprehensive catalog of known WoW events, grouped by category.
    Each entry: { event = "EVENT_NAME", desc = "Short description" }
    Sources: Blizzard_APIDocumentation, FrameXML event registrations, wowpedia.
]]

local CATEGORIES = {
    {
        name = "Addon / Loading",
        events = {
            { event = "ADDON_LOADED",                  desc = "Fires for each addon after its files are loaded. arg1 = addonName." },
            { event = "PLAYER_LOGIN",                  desc = "Fires after the player fully logs in and the UI is ready." },
            { event = "PLAYER_ENTERING_WORLD",         desc = "Fires on login, reload, and every loading screen transition." },
            { event = "PLAYER_LEAVING_WORLD",          desc = "Fires when entering a loading screen." },
            { event = "PLAYER_LOGOUT",                 desc = "Fires when the player logs out or exits the game." },
            { event = "LOADING_SCREEN_DISABLED",       desc = "Fires when a loading screen finishes." },
            { event = "LOADING_SCREEN_ENABLED",        desc = "Fires when a loading screen starts." },
            { event = "VARIABLES_LOADED",              desc = "Fires once after all SavedVariables have been loaded." },
            { event = "SAVED_VARIABLES_TOO_LARGE",     desc = "Fires if a SavedVariables file exceeds size limit." },
            { event = "ADDON_ACTION_BLOCKED",          desc = "Fires when an addon calls a protected function at the wrong time." },
            { event = "ADDON_ACTION_FORBIDDEN",        desc = "Fires when a forbidden (always-protected) API is called by addon code." },
        },
    },
    {
        name = "Combat",
        events = {
            { event = "PLAYER_REGEN_DISABLED",         desc = "Player entered combat (regen locked out)." },
            { event = "PLAYER_REGEN_ENABLED",          desc = "Player left combat (regen restored)." },
            { event = "COMBAT_LOG_EVENT_UNFILTERED",   desc = "Fires for every combat log entry. Use CombatLogGetCurrentEventInfo()." },
            { event = "PLAYER_DEAD",                   desc = "Player has died." },
            { event = "PLAYER_ALIVE",                  desc = "Player is alive (after release or resurrect accept)." },
            { event = "PLAYER_UNGHOST",                desc = "Player returned to body from ghost form." },
            { event = "ENCOUNTER_START",               desc = "Boss encounter started. arg1 = encounterID, arg2 = name, arg3 = difficulty, arg4 = groupSize." },
            { event = "ENCOUNTER_END",                 desc = "Boss encounter ended. arg5 = success (1/0)." },
            { event = "COMBAT_RATING_UPDATE",          desc = "A combat rating (crit, haste, etc.) has changed." },
            { event = "RUNE_POWER_UPDATE",             desc = "Death Knight rune state changed." },
            { event = "PLAYER_ENTER_COMBAT",           desc = "Auto-attack combat started (not the same as regen lock)." },
            { event = "PLAYER_LEAVE_COMBAT",           desc = "Auto-attack combat ended." },
        },
    },
    {
        name = "Unit Health / Power",
        events = {
            { event = "UNIT_HEALTH",                   desc = "Unit's health changed. arg1 = unitId." },
            { event = "UNIT_MAXHEALTH",                desc = "Unit's max health changed." },
            { event = "UNIT_POWER_UPDATE",             desc = "Unit's power (mana/rage/energy/etc.) changed. arg1 = unitId, arg2 = powerType." },
            { event = "UNIT_MAXPOWER",                 desc = "Unit's max power changed." },
            { event = "UNIT_ABSORB_AMOUNT_CHANGED",    desc = "Unit's absorb shield amount changed." },
            { event = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", desc = "Unit's healing absorb amount changed." },
            { event = "UNIT_HEAL_PREDICTION",          desc = "Incoming heal prediction changed for unit." },
            { event = "UNIT_POWER_FREQUENT",           desc = "High-frequency power update (energy/focus tick)." },
            { event = "UNIT_LEVEL",                    desc = "Unit's level changed." },
            { event = "UNIT_DISPLAYPOWER",             desc = "Unit's displayed power type changed (e.g. stance swap)." },
            { event = "UNIT_CONNECTION",               desc = "Unit connected or disconnected." },
        },
    },
    {
        name = "Unit Auras / Buffs",
        events = {
            { event = "UNIT_AURA",                     desc = "Aura (buff/debuff) added, removed, or updated on a unit. Use C_UnitAuras." },
            { event = "LOSS_OF_CONTROL_ADDED",         desc = "A loss of control effect was applied to the player." },
            { event = "LOSS_OF_CONTROL_UPDATE",        desc = "A loss of control effect was modified or removed." },
        },
    },
    {
        name = "Spellcasting",
        events = {
            { event = "UNIT_SPELLCAST_START",          desc = "Unit started casting a spell. arg1 = unitId." },
            { event = "UNIT_SPELLCAST_STOP",           desc = "Unit's spellcast display ended." },
            { event = "UNIT_SPELLCAST_SUCCEEDED",      desc = "Unit's spell successfully cast." },
            { event = "UNIT_SPELLCAST_FAILED",         desc = "Unit's spellcast failed." },
            { event = "UNIT_SPELLCAST_INTERRUPTED",    desc = "Unit's spellcast was interrupted." },
            { event = "UNIT_SPELLCAST_DELAYED",        desc = "Unit's spellcast was pushbacked/delayed." },
            { event = "UNIT_SPELLCAST_CHANNEL_START",  desc = "Unit started channeling a spell." },
            { event = "UNIT_SPELLCAST_CHANNEL_STOP",   desc = "Unit's channel ended." },
            { event = "UNIT_SPELLCAST_CHANNEL_UPDATE", desc = "Unit's channel was hasted/slowed." },
            { event = "UNIT_SPELLCAST_SENT",           desc = "Client sent a cast request to the server." },
            { event = "UNIT_SPELLCAST_EMPOWER_START",  desc = "Empowered spell (Evoker) charge-up started." },
            { event = "UNIT_SPELLCAST_EMPOWER_STOP",   desc = "Empowered spell charge-up ended." },
            { event = "UNIT_SPELLCAST_EMPOWER_UPDATE", desc = "Empowered spell charge stage changed." },
            { event = "CURRENT_SPELL_CAST_CHANGED",    desc = "The player's current casting spell changed." },
            { event = "SPELL_UPDATE_USABLE",           desc = "Usability of spells on action bars may have changed." },
            { event = "SPELL_UPDATE_COOLDOWN",         desc = "A spell cooldown started or ended." },
            { event = "SPELL_UPDATE_CHARGES",          desc = "Spell charge count changed." },
        },
    },
    {
        name = "Targeting",
        events = {
            { event = "PLAYER_TARGET_CHANGED",         desc = "Player changed their target." },
            { event = "PLAYER_FOCUS_CHANGED",          desc = "Player changed their focus target." },
            { event = "PLAYER_SOFT_ENEMY_CHANGED",     desc = "Soft-target enemy changed (action targeting)." },
            { event = "PLAYER_SOFT_FRIEND_CHANGED",    desc = "Soft-target friendly changed (action targeting)." },
            { event = "PLAYER_SOFT_INTERACT_CHANGED",  desc = "Soft-target interact changed." },
            { event = "UPDATE_MOUSEOVER_UNIT",         desc = "Mouseover unit changed (or cleared)." },
            { event = "CURSOR_CHANGED",                desc = "Mouse cursor appearance changed." },
            { event = "NAME_PLATE_UNIT_ADDED",         desc = "A nameplate became visible. arg1 = unitId." },
            { event = "NAME_PLATE_UNIT_REMOVED",       desc = "A nameplate was hidden. arg1 = unitId." },
        },
    },
    {
        name = "Action Bars",
        events = {
            { event = "ACTIONBAR_UPDATE_STATE",        desc = "Action bar button checked/highlight state may have changed." },
            { event = "ACTIONBAR_UPDATE_USABLE",       desc = "Action bar button usability (mana, range) changed." },
            { event = "ACTIONBAR_UPDATE_COOLDOWN",     desc = "An action bar cooldown started or ended." },
            { event = "ACTIONBAR_SLOT_CHANGED",        desc = "An action was placed/removed from a bar slot. arg1 = slot." },
            { event = "ACTIONBAR_PAGE_CHANGED",        desc = "The current action bar page changed." },
            { event = "ACTIONBAR_SHOWGRID",            desc = "Action bar grid shown (dragging a spell)." },
            { event = "ACTIONBAR_HIDEGRID",            desc = "Action bar grid hidden." },
            { event = "UPDATE_BONUS_ACTIONBAR",        desc = "Bonus action bar changed (vehicle, override, possess)." },
            { event = "UPDATE_EXTRA_ACTIONBAR",        desc = "Extra action button (zone ability) changed." },
        },
    },
    {
        name = "Bags / Items",
        events = {
            { event = "BAG_UPDATE",                    desc = "Contents of a bag changed. arg1 = bagIndex." },
            { event = "BAG_UPDATE_DELAYED",            desc = "Fires once after all BAG_UPDATE events in a batch." },
            { event = "BAG_OPEN",                      desc = "A bag was opened. arg1 = bagIndex." },
            { event = "BAG_CLOSED",                    desc = "A bag was closed." },
            { event = "ITEM_LOCK_CHANGED",             desc = "An item's lock state changed (being moved)." },
            { event = "ITEM_LOCKED",                   desc = "An item was locked (pickup started)." },
            { event = "ITEM_UNLOCKED",                 desc = "An item was unlocked (pickup ended)." },
            { event = "ITEM_COUNT_CHANGED",            desc = "Stack count of an item changed." },
            { event = "GET_ITEM_INFO_RECEIVED",        desc = "Item info response received from server. arg1 = itemID, arg2 = success." },
            { event = "PLAYER_EQUIPMENT_CHANGED",      desc = "A gear slot was equipped or unequipped. arg1 = slot, arg2 = hasCurrent." },
            { event = "EQUIPMENT_SETS_CHANGED",        desc = "Equipment Manager set list changed." },
            { event = "INVENTORY_SEARCH_UPDATE",       desc = "Inventory search filter changed." },
        },
    },
    {
        name = "Chat",
        events = {
            { event = "CHAT_MSG_SAY",                  desc = "Message in /say channel." },
            { event = "CHAT_MSG_YELL",                 desc = "Message in /yell channel." },
            { event = "CHAT_MSG_PARTY",                desc = "Message in party chat." },
            { event = "CHAT_MSG_PARTY_LEADER",         desc = "Message from party leader." },
            { event = "CHAT_MSG_RAID",                 desc = "Message in raid chat." },
            { event = "CHAT_MSG_RAID_LEADER",          desc = "Message from raid leader." },
            { event = "CHAT_MSG_RAID_WARNING",         desc = "Raid warning message." },
            { event = "CHAT_MSG_GUILD",                desc = "Message in guild chat." },
            { event = "CHAT_MSG_OFFICER",              desc = "Message in guild officer chat." },
            { event = "CHAT_MSG_WHISPER",              desc = "Incoming whisper. args: message, sender, ..." },
            { event = "CHAT_MSG_WHISPER_INFORM",       desc = "Outgoing whisper sent confirmation." },
            { event = "CHAT_MSG_BN_WHISPER",           desc = "Battle.net whisper received." },
            { event = "CHAT_MSG_CHANNEL",              desc = "Message in a numbered channel (Trade, General, etc.)." },
            { event = "CHAT_MSG_SYSTEM",               desc = "System message (yellow text)." },
            { event = "CHAT_MSG_LOOT",                 desc = "Loot message." },
            { event = "CHAT_MSG_MONEY",                desc = "Money looted message." },
            { event = "CHAT_MSG_ADDON",                desc = "Addon-to-addon message via SendAddonMessage(). arg1 = prefix, arg2 = text, arg3 = channel, arg4 = sender." },
            { event = "CHAT_MSG_ADDON_LOGGED",         desc = "Logged addon message received." },
            { event = "CHAT_MSG_EMOTE",                desc = "Custom emote message." },
            { event = "CHAT_MSG_TEXT_EMOTE",            desc = "Standard emote (e.g. /wave)." },
            { event = "CHAT_MSG_COMBAT_XP_GAIN",       desc = "XP gain combat message." },
        },
    },
    {
        name = "Group / Party / Raid",
        events = {
            { event = "GROUP_ROSTER_UPDATE",           desc = "Group composition changed (join, leave, role, etc.)." },
            { event = "GROUP_FORMED",                  desc = "A group was formed." },
            { event = "GROUP_LEFT",                    desc = "Player left a group." },
            { event = "PARTY_LEADER_CHANGED",          desc = "Party/raid leader changed." },
            { event = "PARTY_LOOT_METHOD_CHANGED",     desc = "Loot method/threshold changed." },
            { event = "PARTY_MEMBER_ENABLE",           desc = "A party member came in range / loaded." },
            { event = "PARTY_MEMBER_DISABLE",          desc = "A party member went out of range / unloaded." },
            { event = "RAID_ROSTER_UPDATE",            desc = "Raid roster changed." },
            { event = "READY_CHECK",                   desc = "A ready check was initiated." },
            { event = "READY_CHECK_CONFIRM",           desc = "A player responded to the ready check." },
            { event = "READY_CHECK_FINISHED",          desc = "The ready check completed." },
            { event = "ROLE_CHANGED_INFORM",           desc = "A player's role (tank/healer/dps) was set." },
        },
    },
    {
        name = "Zone / Map / Travel",
        events = {
            { event = "ZONE_CHANGED",                  desc = "Player moved to a different subzone." },
            { event = "ZONE_CHANGED_INDOORS",          desc = "Player moved between indoor/outdoor in same subzone." },
            { event = "ZONE_CHANGED_NEW_AREA",         desc = "Player moved to a different major zone." },
            { event = "NEW_WMO_CHUNK",                 desc = "Player entered a new world map object (building interior)." },
            { event = "WORLD_MAP_UPDATE",              desc = "World map data needs refreshing." },
            { event = "MINIMAP_UPDATE_ZOOM",           desc = "Minimap zoom level changed (indoor/outdoor)." },
            { event = "PLAYER_STARTED_MOVING",         desc = "Player began moving." },
            { event = "PLAYER_STOPPED_MOVING",         desc = "Player stopped moving." },
            { event = "HEARTHSTONE_BOUND",             desc = "Hearthstone bind point changed." },
        },
    },
    {
        name = "Quest",
        events = {
            { event = "QUEST_ACCEPTED",                desc = "A quest was accepted. arg1 = questID." },
            { event = "QUEST_REMOVED",                 desc = "A quest was removed from the log. arg1 = questID." },
            { event = "QUEST_TURNED_IN",               desc = "A quest was turned in." },
            { event = "QUEST_COMPLETE",                desc = "Quest completion dialog opened (NPC turn-in)." },
            { event = "QUEST_DETAIL",                  desc = "Quest detail/accept dialog opened." },
            { event = "QUEST_PROGRESS",                desc = "Quest progress dialog opened (not yet completable)." },
            { event = "QUEST_FINISHED",                desc = "Quest dialog closed." },
            { event = "QUEST_LOG_UPDATE",              desc = "Quest log contents changed." },
            { event = "QUEST_WATCH_LIST_CHANGED",      desc = "Tracked quest list changed." },
            { event = "QUEST_AUTOCOMPLETE",            desc = "A quest was auto-completed (turn in at quest tracker)." },
            { event = "QUEST_POI_UPDATE",              desc = "Quest points of interest updated on the map." },
            { event = "TASK_PROGRESS_UPDATE",           desc = "World quest / bonus objective progress changed." },
        },
    },
    {
        name = "Merchant / Vendor",
        events = {
            { event = "MERCHANT_SHOW",                 desc = "Merchant window opened." },
            { event = "MERCHANT_CLOSED",               desc = "Merchant window closed." },
            { event = "MERCHANT_UPDATE",               desc = "Merchant inventory changed." },
            { event = "MERCHANT_FILTER_ITEM_UPDATE",   desc = "Merchant filter changed." },
        },
    },
    {
        name = "Auction House",
        events = {
            { event = "AUCTION_HOUSE_SHOW",            desc = "Auction house frame opened." },
            { event = "AUCTION_HOUSE_CLOSED",          desc = "Auction house frame closed." },
            { event = "AUCTION_HOUSE_NEW_RESULTS_RECEIVED", desc = "New search results available." },
            { event = "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", desc = "Browse result set updated." },
            { event = "COMMODITY_SEARCH_RESULTS_UPDATED", desc = "Commodity search results updated." },
            { event = "ITEM_SEARCH_RESULTS_UPDATED",   desc = "Item-level search results updated." },
        },
    },
    {
        name = "Guild",
        events = {
            { event = "GUILD_ROSTER_UPDATE",           desc = "Guild roster data changed." },
            { event = "GUILD_RANKS_UPDATE",            desc = "Guild rank structure changed." },
            { event = "GUILD_MOTD",                    desc = "Guild message of the day received." },
            { event = "GUILD_NEWS_UPDATE",             desc = "Guild news feed updated." },
            { event = "GUILD_XP_UPDATE",               desc = "Guild experience changed." },
            { event = "CLUB_MESSAGE_ADDED",            desc = "New message in a community/guild channel." },
        },
    },
    {
        name = "Talent / Specialization",
        events = {
            { event = "ACTIVE_TALENT_GROUP_CHANGED",   desc = "Player switched specialization." },
            { event = "PLAYER_TALENT_UPDATE",          desc = "Player's talents changed." },
            { event = "TRAIT_CONFIG_UPDATED",          desc = "Talent loadout configuration changed (Dragonflight+)." },
            { event = "TRAIT_CONFIG_CREATED",          desc = "A new talent config/loadout was created." },
            { event = "TRAIT_CONFIG_DELETED",          desc = "A talent config/loadout was deleted." },
            { event = "TRAIT_CONFIG_LIST_UPDATED",     desc = "List of available talent configs changed." },
        },
    },
    {
        name = "Achievement",
        events = {
            { event = "ACHIEVEMENT_EARNED",            desc = "Player earned an achievement. arg1 = achievementID." },
            { event = "CRITERIA_EARNED",               desc = "An achievement criteria was met." },
            { event = "CRITERIA_UPDATE",               desc = "Progress toward an achievement criteria changed." },
            { event = "TRACKED_ACHIEVEMENT_UPDATE",    desc = "Tracked achievement progress changed." },
            { event = "ACHIEVEMENT_SEARCH_UPDATED",    desc = "Achievement search results updated." },
        },
    },
    {
        name = "LFG / Dungeon Finder",
        events = {
            { event = "LFG_LIST_SEARCH_RESULTS_RECEIVED", desc = "Premade group finder results returned." },
            { event = "LFG_LIST_APPLICATION_STATUS_UPDATED", desc = "Group application status changed." },
            { event = "LFG_PROPOSAL_SHOW",             desc = "Dungeon finder proposal popup (accept/decline)." },
            { event = "LFG_PROPOSAL_DONE",             desc = "Dungeon finder proposal finished." },
            { event = "LFG_PROPOSAL_FAILED",           desc = "Dungeon finder proposal failed (someone declined)." },
            { event = "LFG_PROPOSAL_SUCCEEDED",        desc = "Dungeon finder proposal accepted by all." },
            { event = "LFG_ROLE_CHECK_SHOW",           desc = "Role check dialog shown." },
            { event = "LFG_QUEUE_STATUS_UPDATE",       desc = "Queue wait time / status changed." },
            { event = "LFG_UPDATE",                    desc = "General LFG state update." },
        },
    },
    {
        name = "PvP / Battleground",
        events = {
            { event = "PVP_MATCH_ACTIVE",              desc = "PvP match became active." },
            { event = "PVP_MATCH_INACTIVE",            desc = "PvP match became inactive." },
            { event = "PVP_MATCH_COMPLETE",            desc = "PvP match completed." },
            { event = "UPDATE_BATTLEFIELD_STATUS",     desc = "Battleground queue status changed." },
            { event = "UPDATE_BATTLEFIELD_SCORE",      desc = "Battleground scoreboard updated." },
            { event = "HONOR_XP_UPDATE",               desc = "Honor points changed." },
            { event = "PVP_RATED_STATS_UPDATE",        desc = "Rated PvP stats refreshed." },
            { event = "WAR_MODE_STATUS_UPDATE",        desc = "War Mode toggled." },
        },
    },
    {
        name = "Trade / Mail / Economy",
        events = {
            { event = "TRADE_SHOW",                    desc = "Trade window opened." },
            { event = "TRADE_CLOSED",                  desc = "Trade window closed." },
            { event = "TRADE_REQUEST",                 desc = "Incoming trade request." },
            { event = "TRADE_ACCEPT_UPDATE",           desc = "Trade accept state changed." },
            { event = "MAIL_SHOW",                     desc = "Mailbox opened." },
            { event = "MAIL_CLOSED",                   desc = "Mailbox closed." },
            { event = "MAIL_INBOX_UPDATE",             desc = "Mail inbox contents changed." },
            { event = "MAIL_SEND_SUCCESS",             desc = "Mail sent successfully." },
            { event = "PLAYER_MONEY",                  desc = "Player's gold amount changed." },
            { event = "TOKEN_MARKET_PRICE_UPDATED",    desc = "WoW Token price updated." },
        },
    },
    {
        name = "Professions / Crafting",
        events = {
            { event = "TRADE_SKILL_LIST_UPDATE",       desc = "Profession recipe list changed." },
            { event = "TRADE_SKILL_SHOW",              desc = "Profession window opened." },
            { event = "TRADE_SKILL_CLOSE",             desc = "Profession window closed." },
            { event = "UPDATE_TRADESKILL_RECAST",      desc = "Craft queue / recast state changed." },
            { event = "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG", desc = "Crafting order fulfilled notification." },
        },
    },
    {
        name = "Pet / Mount / Collection",
        events = {
            { event = "PET_JOURNAL_LIST_UPDATE",       desc = "Battle pet journal list changed." },
            { event = "PET_BATTLE_OPENING_START",      desc = "Pet battle starting." },
            { event = "PET_BATTLE_OVER",               desc = "Pet battle ended." },
            { event = "COMPANION_UPDATE",              desc = "Companion (non-combat pet) update." },
            { event = "MOUNT_JOURNAL_USABILITY_CHANGED", desc = "Mount usability changed (zone restrictions)." },
            { event = "NEW_MOUNT_ADDED",               desc = "A new mount was added to the collection." },
            { event = "NEW_PET_ADDED",                 desc = "A new pet was added to the collection." },
            { event = "TRANSMOG_COLLECTION_UPDATED",   desc = "Transmog collection changed (new appearance)." },
            { event = "HEIRLOOMS_UPDATED",             desc = "Heirloom collection changed." },
            { event = "TOYS_UPDATED",                  desc = "Toy collection changed." },
        },
    },
    {
        name = "Unit Info / Inspection",
        events = {
            { event = "UNIT_NAME_UPDATE",              desc = "Unit's displayed name changed." },
            { event = "UNIT_PORTRAIT_UPDATE",          desc = "Unit's portrait model changed." },
            { event = "UNIT_MODEL_CHANGED",            desc = "Unit's 3D model changed." },
            { event = "UNIT_FLAGS",                    desc = "Unit's flags changed (PvP, AFK, etc.)." },
            { event = "UNIT_FACTION",                  desc = "Unit's faction/reputation standing changed." },
            { event = "UNIT_CLASSIFICATION_CHANGED",   desc = "Unit classification changed (normal/elite/rare/boss)." },
            { event = "UNIT_PET",                      desc = "Unit's pet changed." },
            { event = "UNIT_ENTERED_VEHICLE",          desc = "Unit entered a vehicle." },
            { event = "UNIT_EXITED_VEHICLE",           desc = "Unit exited a vehicle." },
            { event = "INSPECT_READY",                 desc = "Inspect data for a unit is now available." },
            { event = "UNIT_INVENTORY_CHANGED",        desc = "Unit's visible equipment changed." },
        },
    },
    {
        name = "Tooltip",
        events = {
            { event = "CURSOR_CHANGED",                desc = "Mouse cursor icon changed. (High frequency - often blacklisted.)" },
            { event = "UPDATE_MOUSEOVER_UNIT",         desc = "Mouseover target changed." },
        },
    },
    {
        name = "Frame / UI",
        events = {
            { event = "DISPLAY_SIZE_CHANGED",          desc = "Game window resolution changed." },
            { event = "UI_SCALE_CHANGED",              desc = "UI scale setting changed." },
            { event = "MODIFIER_STATE_CHANGED",        desc = "A modifier key (Shift/Ctrl/Alt) was pressed or released. (High frequency.)" },
            { event = "GLOBAL_MOUSE_DOWN",             desc = "Any mouse button pressed anywhere. (High frequency.)" },
            { event = "GLOBAL_MOUSE_UP",               desc = "Any mouse button released. (High frequency.)" },
            { event = "UPDATE_BINDINGS",               desc = "Key bindings changed." },
            { event = "CVAR_UPDATE",                   desc = "A CVar value changed. arg1 = cvar name." },
            { event = "CINEMATIC_START",               desc = "An in-game cinematic started." },
            { event = "CINEMATIC_STOP",                desc = "An in-game cinematic stopped." },
            { event = "SCREENSHOT_SUCCEEDED",          desc = "A screenshot was saved." },
            { event = "SCREENSHOT_FAILED",             desc = "A screenshot failed." },
        },
    },
    {
        name = "Mythic+ / Challenge Mode",
        events = {
            { event = "CHALLENGE_MODE_START",          desc = "Mythic+ dungeon timer started." },
            { event = "CHALLENGE_MODE_COMPLETED",      desc = "Mythic+ dungeon completed." },
            { event = "CHALLENGE_MODE_RESET",          desc = "Mythic+ dungeon reset." },
            { event = "CHALLENGE_MODE_DEATH_COUNT_UPDATED", desc = "Death count updated during M+ run." },
            { event = "MYTHIC_PLUS_NEW_WEEKLY_RECORD", desc = "New weekly best M+ record set." },
        },
    },
    {
        name = "Delves",
        events = {
            { event = "DELVES_DISPLAY_SEASON_INFO",    desc = "Delve season info display updated." },
        },
    },
    {
        name = "Loot",
        events = {
            { event = "LOOT_READY",                    desc = "Loot window is ready to open." },
            { event = "LOOT_OPENED",                   desc = "Loot window opened." },
            { event = "LOOT_CLOSED",                   desc = "Loot window closed." },
            { event = "LOOT_SLOT_CLEARED",             desc = "A loot slot was taken." },
            { event = "START_LOOT_ROLL",               desc = "A loot roll started. arg1 = rollID." },
            { event = "BONUS_ROLL_RESULT",             desc = "Bonus roll result received." },
            { event = "SHOW_LOOT_TOAST",               desc = "Loot toast popup (item/currency gained)." },
            { event = "ENCOUNTER_LOOT_RECEIVED",       desc = "Loot received from a boss encounter." },
        },
    },
    {
        name = "Currency / Reputation",
        events = {
            { event = "CURRENCY_DISPLAY_UPDATE",       desc = "Currency amounts changed." },
            { event = "UPDATE_FACTION",                desc = "Reputation / faction standing changed." },
            { event = "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", desc = "Renown level changed for a major faction." },
            { event = "MAJOR_FACTION_UNLOCKED",        desc = "A new major faction became available." },
        },
    },
    {
        name = "Garrison / Mission Table",
        events = {
            { event = "GARRISON_MISSION_COMPLETE_RESPONSE", desc = "Garrison/covenant mission completion result." },
            { event = "GARRISON_MISSION_STARTED",      desc = "A garrison mission was started." },
            { event = "GARRISON_MISSION_FINISHED",     desc = "A garrison mission can be collected." },
        },
    },
    {
        name = "Vignette / World Event",
        events = {
            { event = "VIGNETTE_MINIMAP_UPDATED",      desc = "Minimap vignette (rare/event star) updated." },
            { event = "SCENARIO_UPDATE",               desc = "Scenario objectives changed." },
            { event = "SCENARIO_COMPLETED",            desc = "A scenario was completed." },
            { event = "WORLD_QUEST_COMPLETED_BY_SPELL", desc = "A world quest was completed by a spell effect." },
        },
    },
}

-- Flat index for searching
local flatIndex = nil

local function BuildFlatIndex()
    if flatIndex then return end
    flatIndex = {}
    for _, cat in ipairs(CATEGORIES) do
        for _, entry in ipairs(cat.events) do
            flatIndex[#flatIndex + 1] = {
                event = entry.event,
                desc = entry.desc,
                category = cat.name,
            }
        end
    end
    table.sort(flatIndex, function(a, b) return a.event < b.event end)
end

-- Get all categories
function Index:GetCategories()
    return CATEGORIES
end

-- Get flat list of all events
function Index:GetAll()
    BuildFlatIndex()
    return flatIndex
end

-- Get total count
function Index:GetCount()
    BuildFlatIndex()
    return #flatIndex
end

-- Search events by name or description substring
function Index:Search(query)
    BuildFlatIndex()
    if not query or query == "" then return flatIndex end

    local queryLower = query:lower()
    local results = {}
    for _, entry in ipairs(flatIndex) do
        if entry.event:lower():find(queryLower, 1, true) or
           entry.desc:lower():find(queryLower, 1, true) or
           entry.category:lower():find(queryLower, 1, true) then
            results[#results + 1] = entry
        end
    end
    return results
end

-- Lookup a single event
function Index:Lookup(eventName)
    BuildFlatIndex()
    for _, entry in ipairs(flatIndex) do
        if entry.event == eventName then
            return entry
        end
    end
    return nil
end

-- Build tree nodes for the TreeView widget
function Index:BuildTreeNodes(filterQuery)
    local nodes = {}
    for _, cat in ipairs(CATEGORIES) do
        local children = {}
        for _, entry in ipairs(cat.events) do
            local include = true
            if filterQuery and filterQuery ~= "" then
                local q = filterQuery:lower()
                include = entry.event:lower():find(q, 1, true)
                    or entry.desc:lower():find(q, 1, true)
            end
            if include then
                children[#children + 1] = {
                    id = "evt_" .. entry.event,
                    text = DF.Colors.keyword .. entry.event .. "|r",
                    data = entry,
                }
            end
        end
        if #children > 0 then
            nodes[#nodes + 1] = {
                id = "cat_" .. cat.name,
                text = cat.name .. " (" .. #children .. ")",
                children = children,
                data = { category = cat.name },
            }
        end
    end
    return nodes
end
