-- ForeverTactics: core namespace, saved variables, events and slash command.
local ADDON, ns = ...

do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and get(ADDON, "Version")
  -- The CurseForge packager fills in the version; a raw git checkout shows the token.
  ns.VERSION = (v and not v:find("@", 1, true)) and v or "dev"
end
ns.Data = ns.Data or { instances = {}, npcs = {} }

local PREFIX = "|cff4fc3f7ForeverTactics|r: "

function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

-- Secret value helpers. Never compare, index or branch on a secret.
function ns.IsSecret(v)
  if issecretvalue then
    return issecretvalue(v) and true or false
  end
  return false
end

-- Safe string for display. Secrets are replaced, never touched.
function ns.Show(v)
  if ns.IsSecret(v) then
    return "<secret>"
  end
  return tostring(v)
end

-- Parse the NPC ID out of a creature GUID. Returns nil when the GUID is
-- missing, secret, or not a creature.
-- Format: Creature-0-[server]-[instance]-[zoneUID]-[npcID]-[spawnUID]
function ns.NpcIDFromGUID(guid)
  if guid == nil or ns.IsSecret(guid) then
    return nil
  end
  local unitType, _, _, _, _, npcID = strsplit("-", guid)
  if unitType == "Creature" or unitType == "Vehicle" then
    return tonumber(npcID)
  end
  return nil
end

-- Data lookups -------------------------------------------------------------

-- Instance key for a GetInstanceInfo() instanceID, or nil.
function ns.InstanceKeyByID(instanceID)
  if instanceID == nil or ns.IsSecret(instanceID) then return nil end
  for key, inst in pairs(ns.Data.instances) do
    if inst.instanceID == instanceID then return key end
  end
  return nil
end

-- Instance key by the name GetInstanceInfo reports, for dungeons whose
-- instance ID we do not know yet (the new Forever dungeons).
function ns.InstanceKeyByName(name)
  if type(name) ~= "string" or ns.IsSecret(name) then return nil end
  local lower = name:lower()
  for key, inst in pairs(ns.Data.instances) do
    if inst.name:lower() == lower then return key end
    for _, n in ipairs(inst.instanceNames or {}) do
      if n:lower() == lower then return key end
    end
  end
  return nil
end

-- Instance key for where the player is now, or nil.
function ns.CurrentInstanceKey()
  local ok, name, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
  if not ok or instanceType == "none" then return nil end
  local key = ns.InstanceKeyByID(instanceID) or ns.InstanceKeyByName(name)
  if key and ns.db and not ns.Data.instances[key].instanceID and type(instanceID) == "number" and not ns.IsSecret(instanceID) then
    ns.db.learnedInstanceIDs = ns.db.learnedInstanceIDs or {}
    ns.db.learnedInstanceIDs[key] = instanceID -- collected so the next data build can use it
  end
  return key
end

-- NPC ID for an encounter, matched by encounterID first, then by name.
function ns.NpcIDForEncounter(encounterID, encounterName)
  for id, npc in pairs(ns.Data.npcs) do
    if npc.encounterID and npc.encounterID == encounterID then return id end
  end
  if type(encounterName) == "string" then
    for id, npc in pairs(ns.Data.npcs) do
      if npc.name == encounterName then return id end
    end
  end
  return nil
end

-- Events ------------------------------------------------------------------

local frame = CreateFrame("Frame")
ns.EventFrame = frame
local handlers = {}

function ns.On(event, fn)
  handlers[event] = handlers[event] or {}
  table.insert(handlers[event], fn)
  frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    fn(event, ...)
  end
end)

ns.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ForeverTacticsDB = ForeverTacticsDB or {}
  ns.db = ForeverTacticsDB
  ns.db.notes = ns.db.notes or {}
  ns.db.diag = ns.db.diag or {}
  ns.db.seenEncounters = ns.db.seenEncounters or {}
  ns.db.button = ns.db.button or {}
  if ns.OnLoad then ns.OnLoad() end
end)

-- Current boss fight. ENCOUNTER_START args are readable in Forever (tested
-- 2026-11-25), unlike unit identity inside instances.
ns.encounter = nil -- { id, name, npcID }

local function Readable(v)
  if ns.IsSecret(v) then return nil end
  return v
end

ns.On("ENCOUNTER_START", function(_, encounterID, encounterName)
  encounterID, encounterName = Readable(encounterID), Readable(encounterName)
  ns.encounter = {
    id = encounterID,
    name = encounterName,
    npcID = ns.NpcIDForEncounter(encounterID, encounterName),
  }
  if encounterID and ns.db then
    ns.db.seenEncounters[encounterID] = {
      name = encounterName,
      instance = ns.CurrentInstanceKey(),
      seen = date("%Y-%m-%d"),
    }
  end
  if ns.OnEncounterChanged then ns.OnEncounterChanged() end
end)

ns.On("ENCOUNTER_END", function()
  ns.encounter = nil
  if ns.OnEncounterChanged then ns.OnEncounterChanged() end
end)

-- Slash command -----------------------------------------------------------

ns.commands = {}

function ns.Command(name, help, fn)
  ns.commands[name] = { help = help, fn = fn }
end

local function ShowHelp()
  ns.Print("v" .. ns.VERSION .. " commands:")
  DEFAULT_CHAT_FRAME:AddMessage("  /ft  Open or close the journal.")
  local names = {}
  for name in pairs(ns.commands) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    DEFAULT_CHAT_FRAME:AddMessage("  /ft " .. name .. "  " .. ns.commands[name].help)
  end
end

SLASH_FOREVERTACTICS1 = "/ft"
SLASH_FOREVERTACTICS2 = "/forevertactics"
SlashCmdList.FOREVERTACTICS = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local entry = ns.commands[cmd]
  if cmd == "" and ns.Journal then
    ns.Journal.Toggle()
  elseif entry then
    entry.fn(rest)
  else
    ShowHelp()
  end
end
