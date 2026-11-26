-- ForeverTactics: loot and drop chances, in unit tooltips and the journal.
--
-- Data comes from Data/Loot.lua (Classic server values, generated). It is
-- kept as one string per mob and parsed only when someone looks at that mob.
--
-- Hold the loot key (Ctrl by default) while hovering a mob to see its loot.
-- That needs the mob's NPC ID, which the game only gives us when the unit
-- identity is not secret: the open world out of combat. Inside dungeons the
-- tooltip points to the journal instead. Display only, no decisions.
local _, ns = ...

local IsSecret = ns.IsSecret
local TOOLTIP_MAX = 10

local QUALITY_HEX = {
  [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
  [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80",
}
ns.QUALITY_HEX = QUALITY_HEX

local cache = {}

-- Loot list for an NPC ID: { { id, pct, quest, quality, name }, ... } sorted
-- by chance, or nil when we have no data for it.
function ns.LootFor(npcID)
  if type(npcID) ~= "number" or not ns.Loot then return nil end
  local hit = cache[npcID]
  if hit ~= nil then return hit or nil end
  local raw = ns.Loot.npcs[npcID]
  if not raw then
    cache[npcID] = false
    return nil
  end
  local list = {}
  for sid, pct, q in raw:gmatch("(%d+),([%d%.]+)(q?)") do
    local id = tonumber(sid)
    local item = ns.Loot.items[id] or "1?"
    list[#list + 1] = {
      id = id,
      pct = tonumber(pct),
      quest = q == "q",
      quality = tonumber(item:sub(1, 1)) or 1,
      name = item:sub(2),
    }
  end
  cache[npcID] = list
  return list
end

function ns.LootChanceText(e)
  if e.quest then return "quest" end
  local p = e.pct
  if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
  local t = string.format(p >= 1 and "%.1f" or "%.2f", p):gsub("0+$", ""):gsub("%.$", "")
  return t .. "%"
end

function ns.LootItemIcon(id)
  local get = C_Item and C_Item.GetItemIconByID or GetItemIcon
  local ok, icon = pcall(get, id)
  return ok and icon or 134400 -- question mark
end

-- Loot key ---------------------------------------------------------------------

ns.LOOT_KEYS = { "ctrl", "alt", "shift", "always", "off" }
ns.LOOT_KEY_LABEL = { ctrl = "Ctrl", alt = "Alt", shift = "Shift", always = "Always", off = "Off" }

function ns.LootKeyDown()
  local k = (ns.db and ns.db.lootKey) or "ctrl"
  if k == "off" then return false end
  if k == "always" then return true end
  if k == "alt" then return IsAltKeyDown() end
  if k == "shift" then return IsShiftKeyDown() end
  return IsControlKeyDown()
end

-- Tooltip ----------------------------------------------------------------------

-- Adds loot lines for npcID to a tooltip. Returns true when it added any.
function ns.AddLootLines(tt, npcID, max)
  local list = ns.LootFor(npcID)
  tt:AddLine(" ")
  if not list then
    tt:AddLine("|cffffd100Loot|r  |cff888888no loot data for this mob|r")
    return false
  end
  tt:AddLine("|cffffd100Loot|r  |cff888888drop chance|r")
  max = max or TOOLTIP_MAX
  for i = 1, math.min(#list, max) do
    local e = list[i]
    local left = "|T" .. ns.LootItemIcon(e.id) .. ":14:14:0:0:64:64:5:59:5:59|t |c"
      .. (QUALITY_HEX[e.quality] or QUALITY_HEX[1]) .. e.name .. "|r"
    local right = e.quest and "|cffffd100quest|r" or ns.LootChanceText(e)
    tt:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
  end
  if #list > max then
    tt:AddLine(string.format("|cff888888+%d more on its /ft page|r", #list - max))
  end
  return true
end

local function UnitGUIDFromTooltip(tt, data)
  local guid = data and data.guid
  if guid == nil then
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if ok and unit and not IsSecret(unit) then
      guid = UnitGUID(unit)
    end
  end
  return guid
end

local function OnUnitTooltip(tt, data)
  if tt ~= GameTooltip or not ns.LootKeyDown() then return end
  local guid = UnitGUIDFromTooltip(tt, data)
  if guid == nil then return end
  if IsSecret(guid) then
    tt:AddLine(" ")
    tt:AddLine("|cffffd100Loot|r  |cff888888the game hides which mob this is right now (dungeons, combat). In a boss fight, hover the book on the target frame, or open /ft|r", 1, 1, 1, true)
    return
  end
  local npcID = ns.NpcIDFromGUID(guid)
  if npcID then ns.AddLootLines(tt, npcID) end
end

-- Pressing or releasing the key while a unit tooltip is up redraws it.
local function RefreshTooltip()
  if not GameTooltip:IsShown() then return end
  local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
  if ok and unit and not IsSecret(unit) then
    pcall(GameTooltip.SetUnit, GameTooltip, unit)
    return
  end
  local owner = GameTooltip:GetOwner()
  if owner and owner.ftLootTooltip then
    local onEnter = owner:GetScript("OnEnter")
    if onEnter then onEnter(owner) end
  end
end

ns.On("PLAYER_LOGIN", function()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
      local ok, err = pcall(OnUnitTooltip, tt, data)
      if not ok and ns.db and ns.db.debug then ns.Print("loot tooltip:", err) end
    end)
  elseif GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(OnUnitTooltip, tt, nil) end)
  end
end)

ns.On("MODIFIER_STATE_CHANGED", function()
  if (ns.db and ns.db.lootKey) == "always" then return end
  RefreshTooltip()
end)
