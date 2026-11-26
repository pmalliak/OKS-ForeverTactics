-- ForeverTactics: /ft diag
-- Collects facts about the Forever client API so the design can be locked:
-- secret values, GUID format, encounter journal data, encounter and combat
-- log events. Every call is guarded, so a missing or changed API shows up as
-- a result instead of a Lua error. Results are saved per run in
-- ForeverTacticsDB.diag and can be copied with /ft diag copy.
local _, ns = ...

local MAX_RUNS = 40
local Show, IsSecret = ns.Show, ns.IsSecret

-- pcall wrapper that returns "ERR: ..." text instead of raising.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return false, "missing"
  end
  local res = { pcall(fn, ...) }
  if not res[1] then
    return false, "ERR: " .. tostring(res[2])
  end
  return true, unpack(res, 2)
end

-- True only when v is a real, non-secret truthy value.
local function truthy(v)
  return (not IsSecret(v)) and v and true or false
end

-- Passive watchers ----------------------------------------------------------

local watch = {
  encounterStart = nil, -- text of the last ENCOUNTER_START
  encounterEnd = nil,
  targetChanges = 0,
  targetChangesSecret = 0,
}
ns.diagWatch = watch

local function argsText(...)
  local out = {}
  for i = 1, select("#", ...) do
    out[#out + 1] = Show((select(i, ...)))
  end
  return table.concat(out, ", ")
end

ns.On("ENCOUNTER_START", function(_, ...)
  watch.encounterStart = date("%H:%M:%S") .. " args: " .. argsText(...)
end)

ns.On("ENCOUNTER_END", function(_, ...)
  watch.encounterEnd = date("%H:%M:%S") .. " args: " .. argsText(...)
end)

ns.On("PLAYER_TARGET_CHANGED", function()
  watch.targetChanges = watch.targetChanges + 1
  if IsSecret(UnitGUID("target")) then
    watch.targetChangesSecret = watch.targetChangesSecret + 1
  end
end)

-- Combat log: not registered. In Forever, registering
-- COMBAT_LOG_EVENT_UNFILTERED from an addon is a blocked action (it raised the
-- "blocked from an action only available to the Blizzard UI" popup in 0.1.0),
-- which itself confirms addons get no combat log.

-- Encounter journal probe ---------------------------------------------------

local function ProbeEJ(add)
  add("EJ.C_EncounterJournal", type(C_EncounterJournal))
  add("EJ.EJ_GetNumTiers", type(EJ_GetNumTiers))
  local ok, tiers = try(EJ_GetNumTiers)
  add("EJ.numTiers", ok and Show(tiers) or tiers)
  if not ok or not truthy(tiers) then return end

  for tier = 1, tiers do
    try(EJ_SelectTier, tier)
    for _, isRaid in ipairs({ false, true }) do
      local count, first, firstID = 0, nil, nil
      for i = 1, 200 do
        local okI, instanceID, name = try(EJ_GetInstanceByIndex, i, isRaid)
        if not okI or (not IsSecret(instanceID) and instanceID == nil) then break end
        count = count + 1
        if i == 1 then first, firstID = Show(name), Show(instanceID) end
      end
      add(("EJ.tier%d.%s"):format(tier, isRaid and "raids" or "dungeons"),
        count .. (first and (" (first: " .. first .. " id " .. firstID .. ")") or ""))
    end
  end

  -- If there is a current instance, try to read its encounter list.
  local _, mapID = try(C_Map and C_Map.GetBestMapForUnit, "player")
  if not truthy(mapID) then
    add("EJ.instanceForMap", "no mapID")
    return
  end
  local okC, curInstance = try(EJ_GetInstanceForMap, mapID)
  add("EJ.instanceForMap", okC and Show(curInstance) or curInstance)
  if okC and truthy(curInstance) and curInstance ~= 0 then
    try(EJ_SelectInstance, curInstance)
    local names = {}
    for i = 1, 30 do
      local okE, name, _, encounterID = try(EJ_GetEncounterInfoByIndex, i, curInstance)
      if not okE or (not IsSecret(name) and name == nil) then break end
      names[#names + 1] = Show(name) .. "#" .. Show(encounterID)
    end
    add("EJ.encounters", #names > 0 and table.concat(names, "; ") or "none")
  end
end

-- Main collector --------------------------------------------------------------

local function Collect(label)
  local lines = {}
  local function add(key, value)
    lines[#lines + 1] = key .. " = " .. tostring(value)
  end

  add("label", label ~= "" and label or "(none)")
  add("addon", ns.VERSION)

  local okB, version, build, buildDate, toc = try(GetBuildInfo)
  if okB then
    add("build", Show(version) .. "." .. Show(build) .. " (" .. Show(buildDate) .. ")")
    add("interface", Show(toc))
  else
    add("build", version)
  end

  local okI, iName, iType, diffID, diffName, maxPlayers, _, _, instanceID = try(GetInstanceInfo)
  if okI then
    add("instance", ("%s | type %s | diff %s %s | max %s | id %s"):format(
      Show(iName), Show(iType), Show(diffID), Show(diffName), Show(maxPlayers), Show(instanceID)))
  else
    add("instance", iName)
  end

  local okM, mapID = try(C_Map and C_Map.GetBestMapForUnit, "player")
  add("mapID", okM and Show(mapID) or mapID)

  local _, lockdown = try(InCombatLockdown)
  local _, inCombat = try(UnitAffectingCombat, "player")
  add("InCombatLockdown", Show(lockdown))
  add("playerInCombat", Show(inCombat))

  add("issecretvalue", type(issecretvalue))
  add("C_Secrets", type(C_Secrets))

  local _, exists = try(UnitExists, "target")
  add("target.exists", Show(exists))
  if truthy(exists) then
    local okS, shouldSecret = try(C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret, "target")
    add("target.ShouldUnitIdentityBeSecret", okS and Show(shouldSecret) or shouldSecret)

    local _, isPlayer = try(UnitIsPlayer, "target")
    add("target.isPlayer", Show(isPlayer))

    local okG, guid = try(UnitGUID, "target")
    add("target.guidIsSecret", okG and Show(IsSecret(guid)) or guid)
    add("target.guid", okG and Show(guid) or "-")
    add("target.npcID", Show(ns.NpcIDFromGUID(okG and guid or nil)))

    local okN, name = try(UnitName, "target")
    add("target.nameIsSecret", okN and Show(IsSecret(name)) or name)
    add("target.name", okN and Show(name) or "-")

    local _, classification = try(UnitClassification, "target")
    add("target.classification", Show(classification))
    local _, level = try(UnitLevel, "target")
    add("target.level", Show(level))
  end

  ProbeEJ(add)

  add("ev.ENCOUNTER_START", watch.encounterStart or "not seen")
  add("ev.ENCOUNTER_END", watch.encounterEnd or "not seen")
  add("ev.targetChanges", watch.targetChanges .. " (secret at change: " .. watch.targetChangesSecret .. ")")

  local okT, tf = try(function() return TargetFrame end)
  add("ui.TargetFrame", okT and type(tf) or tf)

  return lines
end

-- Copy window -----------------------------------------------------------------

local copyFrame
local function ShowCopy(text)
  if not copyFrame then
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("ForeverTactics diag: Ctrl+A, Ctrl+C, then Escape")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(560)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    f.edit = edit
    copyFrame = f
  end
  copyFrame.edit:SetText(text)
  copyFrame.edit:HighlightText()
  copyFrame:Show()
  copyFrame.edit:SetFocus()
end

-- Command -----------------------------------------------------------------------

local function RunsText()
  local out = {}
  for _, run in ipairs(ns.db.diag) do
    out[#out + 1] = "### " .. run.time
    for _, line in ipairs(run.lines) do out[#out + 1] = line end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

ns.Command("diag", "[label] | copy | clear  Record API facts for the current target and place.", function(arg)
  local sub = (arg or ""):lower()
  if sub == "copy" then
    if #ns.db.diag == 0 then
      ns.Print("No diag runs saved yet. Run /ft diag <label> first.")
    else
      ShowCopy(RunsText())
    end
    return
  elseif sub == "clear" then
    wipe(ns.db.diag)
    ns.Print("Diag runs cleared.")
    return
  end

  local lines = Collect(arg or "")
  table.insert(ns.db.diag, { time = date("%Y-%m-%d %H:%M:%S"), lines = lines })
  while #ns.db.diag > MAX_RUNS do table.remove(ns.db.diag, 1) end

  ns.Print("diag run " .. #ns.db.diag .. " saved:")
  for _, line in ipairs(lines) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
  end
end)
