std = "lua51"
max_line_length = false
exclude_files = { "ForeverTactics/Data/*.lua", "Data/*.lua" }

-- Globals we create.
globals = {
  "ForeverTacticsDB",
  "SLASH_FOREVERTACTICS1",
  "SLASH_FOREVERTACTICS2",
  "SlashCmdList",
  "UISpecialFrames",
}

-- WoW API we read.
read_globals = {
  "C_EncounterJournal", "C_Map", "C_Secrets",
  "ChatFontNormal", "CreateFrame", "DEFAULT_CHAT_FRAME", "EJ_GetEncounterInfoByIndex",
  "EJ_GetInstanceByIndex", "EJ_GetInstanceForMap", "EJ_GetNumTiers", "EJ_SelectInstance",
  "EJ_SelectTier", "GetBuildInfo", "GetInstanceInfo", "InCombatLockdown", "TargetFrame",
  "UIParent", "UnitAffectingCombat", "UnitClassification", "UnitExists", "UnitGUID",
  "UnitIsPlayer", "UnitLevel", "UnitName", "date", "issecretvalue", "strsplit", "strtrim",
  "unpack", "wipe", "GameTooltip", "IsShiftKeyDown", "tinsert",
  "IsControlKeyDown", "IsAltKeyDown", "TooltipDataProcessor", "Enum", "C_Item", "GetItemIcon",
}
