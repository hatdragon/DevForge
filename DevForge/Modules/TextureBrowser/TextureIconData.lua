local _, DF = ...

DF.TextureIconData = {}

local TID = DF.TextureIconData

local ICON_CATEGORIES = {
    { id = "class",       name = "Class Icons",       prefix = "Interface\\Icons\\ClassIcon_" },
    { id = "abilities",   name = "Abilities",         prefix = "Interface\\Icons\\Ability_" },
    { id = "spells",      name = "Spells",            prefix = "Interface\\Icons\\Spell_" },
    { id = "inventory",   name = "Inventory",         prefix = "Interface\\Icons\\INV_" },
    { id = "trade",       name = "Professions",       prefix = "Interface\\Icons\\Trade_" },
    { id = "achieve",     name = "Achievements",      prefix = "Interface\\Icons\\Achievement_" },
    { id = "racial",      name = "Racial",            prefix = "Interface\\Icons\\Racial_" },
    { id = "ui",          name = "UI Elements",       prefix = "Interface\\" },
    { id = "cursor",      name = "Cursors",           prefix = "Interface\\Cursor\\" },
    { id = "minimap",     name = "Minimap",           prefix = "Interface\\Minimap\\" },
    { id = "targets",     name = "Raid Targets",      prefix = "Interface\\TargetingFrame\\" },
}

local FILEID_RANGES = {
    { id = "classic",       name = "Classic Icons",         start = 132000,  stop = 136000 },
    { id = "bc_wrath",      name = "BC / Wrath Icons",      start = 236000,  stop = 240000 },
    { id = "cata_mop",      name = "Cata / MoP Icons",      start = 460000,  stop = 464000 },
    { id = "wod",           name = "WoD Icons",             start = 1000000, stop = 1004000 },
    { id = "legion",        name = "Legion Icons",          start = 1380000, stop = 1384000 },
    { id = "bfa",           name = "BfA Icons",             start = 2000000, stop = 2004000 },
    { id = "shadowlands",   name = "Shadowlands Icons",     start = 3500000, stop = 3504000 },
    { id = "dragonflight",  name = "Dragonflight Icons",    start = 4500000, stop = 4504000 },
    { id = "warwithin",     name = "War Within Icons",      start = 5500000, stop = 5504000 },
}

-- Named icon suffixes per category
local ICON_DATA = {}

ICON_DATA["class"] = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Shaman", "Mage", "Warlock", "Monk", "Druid",
    "DemonHunter", "DeathKnight", "Evoker",
}

ICON_DATA["abilities"] = {
    "Warrior_Charge", "Warrior_BattleShout", "Warrior_Cleave",
    "Warrior_DecisiveStrike", "Warrior_DefensiveStance",
    "Warrior_EndlessRage", "Warrior_Revenge", "Warrior_ShieldBash",
    "Warrior_ShieldWall", "Warrior_Sunder",
    "Rogue_Sprint", "Rogue_Ambush", "Rogue_Backstab",
    "Rogue_Eviscerate", "Rogue_KidneyShot", "Rogue_SliceDice",
    "Rogue_FeignDeath", "Rogue_Stealth", "Rogue_SinisterStrike",
    "Druid_CatForm", "Druid_BearForm", "Druid_TravelForm",
    "Druid_AquaticForm", "Druid_FlightForm", "Druid_TreeofLife",
    "Druid_Maul", "Druid_Prowl", "Druid_Swipe",
    "Hunter_BeastCall", "Hunter_AspectOfTheMonkey", "Hunter_AspectOfTheHawk",
    "Hunter_MarksmanShip", "Hunter_SurvivalInstincts", "Hunter_SteadyShot",
    "Hunter_FeignDeath", "Hunter_RunningShot", "Hunter_RapidFire",
    "Mage_ArcaneExplosion", "Mage_Fireball", "Mage_FrostBolt",
    "Mage_IceLance", "Mage_Blizzard", "Mage_Polymorph",
    "Paladin_DivineStorm", "Paladin_HolyShock", "Paladin_JudgementBlue",
    "Paladin_ShieldoftheTemplar",
    "Priest_Shadowfiend", "Priest_VampiricEmbrace",
    "Warlock_SeedofCorruption", "Warlock_CurseofAgony",
    "DemonHunter_Blur", "DemonHunter_ChaosStrike",
    "Evoker_FireBreath", "Evoker_LivingFlame",
    "Monk_TigerPalm", "Monk_RisingSunKick",
    "DeathKnight_DeathStrike", "DeathKnight_ArmyoftheDead",
}

ICON_DATA["spells"] = {
    "Fire_FlameBlast", "Fire_Fireball02", "Fire_FlameBolt",
    "Fire_Incinerate", "Fire_BurningSpeed", "Fire_SelfDestruct",
    "Fire_MasterofElements", "Fire_SoulBurn", "Fire_FelFlameRing",
    "Nature_Lightning", "Nature_LightningShield", "Nature_ChainLightning",
    "Nature_Rejuvenation", "Nature_HealingTouch", "Nature_Regenerate",
    "Nature_ResistNature", "Nature_AbolishMagic", "Nature_NaturesBlessing",
    "Nature_StoneClawTotem", "Nature_Thorns", "Nature_WispSplode",
    "Holy_HolyBolt", "Holy_HolyNova", "Holy_Renew",
    "Holy_GreaterHeal", "Holy_FlashHeal", "Holy_SealOfSacrifice",
    "Holy_InnerFire", "Holy_LayOnHands", "Holy_WordFortitude",
    "Shadow_ShadowBolt", "Shadow_CurseOfTongues", "Shadow_DeathCoil",
    "Shadow_Vampirism", "Shadow_ShadowWordPain", "Shadow_Plague",
    "Shadow_DarkSummoning", "Shadow_AnimateDead", "Shadow_SealOfBlackness",
    "Arcane_Blink", "Arcane_ArcaneBlast", "Arcane_MassDispel",
    "Arcane_PortalStormwind", "Arcane_PortalOrgrimmar", "Arcane_TeleportDalaran",
    "Frost_FrostBolt02", "Frost_IceStorm", "Frost_FrostNova",
    "Frost_Glacier", "Frost_ArcticWinds", "Frost_FrostArmor02",
    "ChargePositive", "ChargeNegative", "DeathKnight_PillarOfFrost",
}

ICON_DATA["inventory"] = {
    "Sword_04", "Sword_27", "Sword_39",
    "Shield_06", "Shield_09", "Shield_11",
    "Helmet_01", "Helmet_24", "Helmet_44",
    "Chest_Plate01", "Chest_Chain_12", "Chest_Cloth_17",
    "Potion_54", "Potion_76", "Potion_93",
    "Misc_Gem_Diamond_02", "Misc_Gem_Ruby_01", "Misc_Gem_Emerald_02",
    "Misc_Herb_02", "Misc_Herb_Frostlotus", "Misc_Herb_AnchorWeed",
    "Misc_Food_01", "Misc_Food_15", "Misc_Food_Meat_Raw_01",
    "Misc_Bag_07", "Misc_Bag_10", "Misc_Bag_17",
    "Inscription_Tradeskill01", "Misc_Gem_01",
    "Fishingpole_02", "Fishingpole_03",
    "Weapon_Bow_07", "Weapon_Crossbow_05",
    "Weapon_Rifle_01", "Weapon_Glave_01",
    "Staff_09", "Staff_30",
    "Mace_01", "Mace_11",
    "Axe_03", "Axe_10",
    "Polearm_04", "Wand_01",
    "Misc_Key_02", "Misc_Key_04",
    "Ore_Copper_01", "Ore_Iron_01",
    "Ore_Mithril_02", "Ore_TrueIron",
    "Enchant_Disenchant", "Enchant_EssentialEternity",
    "Letter_01", "Letter_15",
    "Scroll_02", "Scroll_07",
    "Jewelcrafting_GemCutOnly", "Jewelcrafting_DragonsEye02",
    "Boots_Cloth_01", "Boots_Plate_01",
    "Belt_01", "Gauntlets_04",
    "Shoulder_01", "Bracer_07",
}

ICON_DATA["trade"] = {
    "BlackSmithing", "Mining", "Tailoring",
    "Leather", "LeatherWorking", "Engineering",
    "Engraving", "Alchemy", "Herbalism",
    "Fishing", "Cooking", "FirstAid",
    "Enchanting", "Archaeology",
}

ICON_DATA["achieve"] = {
    "General", "BG_AB_scorebar",
    "Boss_Illidan", "Boss_CThun",
    "Boss_KelThuzad", "Boss_Ragnaros",
    "Boss_Sapphiron", "Boss_NeuroticNed",
    "Dungeon_ClassicDungeonMaster", "Dungeon_OutlandDungeonMaster",
    "Dungeon_NorthrendDungeonMaster", "Dungeon_GloryoftheHero",
    "PVP_A_01", "PVP_A_02", "PVP_A_03",
    "PVP_H_01", "PVP_H_02", "PVP_H_03",
    "Arena_2v2_1", "Arena_3v3_1", "Arena_5v5_1",
    "Reputation_01", "Reputation_02", "Reputation_03",
    "Zone_Elwynn", "Zone_Durotar",
}

ICON_DATA["racial"] = {
    "Dwarf_FindTreasure", "Gnome_PackHobbyist",
    "Human_Diplomacy", "NightElf_Shadowmeld",
    "Orc_BerserkerStrength", "Tauren_WarStomp",
    "Troll_Berserk", "Undead_Cannibalize",
    "Draenei_GiftoftheNaaru", "BloodElf_ArcaneTorrent",
    "Worgen_DarkFlight", "Goblin_RocketJump",
    "Pandaren_Bouncy", "VoidElf_SpatialRift",
    "LightforgedDraenei_LightsJudgment",
    "HighmountainTauren_BullRush",
    "Nightborne_ArcanePulse", "MagharOrc_AncestralCall",
    "DarkIronDwarf_Fireblood", "ZandalariTroll_Regeneratin",
    "KulTiran_HayMaker", "Vulpera_BagofTricks",
    "Mechagnome_CombatAnalysis", "DracthyrSoar",
}

ICON_DATA["ui"] = {
    "ChatFrame\\ChatFrameBackground",
    "Tooltips\\UI-Tooltip-Border",
    "Tooltips\\UI-Tooltip-Background",
    "DialogFrame\\UI-DialogBox-Border",
    "DialogFrame\\UI-DialogBox-Background",
    "ChatFrame\\UI-ChatIM-SizeGrabber-Up",
    "ChatFrame\\UI-ChatIM-SizeGrabber-Down",
    "ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
    "Buttons\\UI-Panel-Button-Up",
    "Buttons\\UI-Panel-Button-Down",
    "Buttons\\UI-Panel-Button-Highlight",
    "Buttons\\UI-CheckBox-Up",
    "Buttons\\UI-CheckBox-Check",
    "Buttons\\UI-SliderBar-Background",
    "Buttons\\UI-SliderBar-Border",
    "Buttons\\WHITE8X8",
    "Buttons\\UI-PlusButton-Up",
    "Buttons\\UI-MinusButton-Up",
    "Buttons\\UI-GroupLoot-Dice-Up",
    "Buttons\\UI-GroupLoot-Coin-Up",
    "Buttons\\UI-GroupLoot-DE-Up",
    "Buttons\\UI-SquareButton-Up",
    "PaperDollInfoFrame\\UI-GearManager-Undo",
    "PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque",
    "ContainerFrame\\UI-Bag-1Slot",
    "MONEYFRAME\\UI-GoldIcon",
    "MONEYFRAME\\UI-SilverIcon",
    "MONEYFRAME\\UI-CopperIcon",
}

ICON_DATA["cursor"] = {
    "Attack", "Buy", "Cast", "Crosshairs",
    "Inspect", "InteractCursor", "LootAll",
    "Mail", "Mine", "PickLock", "Quest",
    "QuestRepeatable", "Repair", "Skin",
    "Speak", "Taxi", "UnableCast",
    "UnableInspect", "UnableMine", "UnableSkin",
    "PointLeft", "PointRight", "GatherHerbs",
    "PickUp", "PutDown", "Directions",
}

ICON_DATA["minimap"] = {
    "MiniMap-TrackingBorder",
    "UI-Minimap-Background",
    "UI-Minimap-ZoomButton-Highlight",
    "Tracking\\None", "Tracking\\Auctioneer",
    "Tracking\\BattleMaster", "Tracking\\Banker",
    "Tracking\\FlightMaster", "Tracking\\Innkeeper",
    "Tracking\\Mailbox", "Tracking\\Repair",
    "Tracking\\StableMaster", "Tracking\\Trainer-Class",
    "Tracking\\Trainer-Profession", "Tracking\\Vendor-Food",
    "Tracking\\Vendor-Reagent", "ObjectIcons\\DoorArrow",
    "ObjectIcons\\DungeonArrow",
}

ICON_DATA["targets"] = {
    "UI-RaidTargetingIcon_1", "UI-RaidTargetingIcon_2",
    "UI-RaidTargetingIcon_3", "UI-RaidTargetingIcon_4",
    "UI-RaidTargetingIcon_5", "UI-RaidTargetingIcon_6",
    "UI-RaidTargetingIcon_7", "UI-RaidTargetingIcon_8",
}

-- Cached flat array of all icon full paths
local allIconsCache = nil

function TID:GetCategories()
    return ICON_CATEGORIES
end

function TID:GetIcons(categoryId)
    return ICON_DATA[categoryId] or {}
end

function TID:GetFileIdRanges()
    return FILEID_RANGES
end

function TID:GetFullPath(categoryId, suffix)
    for _, cat in ipairs(ICON_CATEGORIES) do
        if cat.id == categoryId then
            return cat.prefix .. suffix
        end
    end
    return suffix
end

function TID:GetPrefix(categoryId)
    for _, cat in ipairs(ICON_CATEGORIES) do
        if cat.id == categoryId then
            return cat.prefix
        end
    end
    return ""
end

function TID:GetAllIcons()
    if allIconsCache then return allIconsCache end
    allIconsCache = {}
    for _, cat in ipairs(ICON_CATEGORIES) do
        local icons = ICON_DATA[cat.id]
        if icons then
            for _, suffix in ipairs(icons) do
                allIconsCache[#allIconsCache + 1] = {
                    path = cat.prefix .. suffix,
                    name = suffix,
                    categoryId = cat.id,
                }
            end
        end
    end
    return allIconsCache
end
