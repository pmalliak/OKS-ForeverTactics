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

-- Shift on top of the loot key shows the whole list in the tooltip.
function ns.LootFullKeyDown()
  local k = (ns.db and ns.db.lootKey) or "ctrl"
  return k ~= "shift" and IsShiftKeyDown()
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
    local hint = ((ns.db and ns.db.lootKey) == "shift") and "type /ft loot" or "hold Shift too"
    tt:AddLine(string.format("|cff888888+%d more, %s to see all|r", #list - max, hint))
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
  if npcID then ns.AddLootLines(tt, npcID, ns.LootFullKeyDown() and 999 or nil) end
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

-- Loot window ------------------------------------------------------------------
-- A small window with the whole loot table of one mob: /ft loot, a right click
-- on the target button, or a macro bound to a key.

local win, rows = nil, {}
local ROW_H = 24

local function NameOf(npcID)
  local npc = ns.Data.npcs[npcID]
  return (npc and npc.name) or (ns.Loot and ns.Loot.names and ns.Loot.names[npcID]) or ("NPC " .. npcID)
end

local function Row(i)
  local b = rows[i]
  if b then return b end
  b = CreateFrame("Button", nil, win.child)
  b:SetSize(win.child:GetWidth(), ROW_H)
  b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(1, 1, 1, i % 2 == 1 and 0.04 or 0)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.right:SetPoint("RIGHT", -6, 0)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
      GameTooltip:AddLine(self.itemName or "?")
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = b
  return b
end

local function BuildWindow()
  win = CreateFrame("Frame", "ForeverTacticsLoot", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(320, 420)
  win:SetPoint("CENTER", 300, 0)
  win:SetFrameStrata("HIGH")
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverTacticsLoot") -- close with Escape
  if type(win.TitleText) ~= "table" then
    win.TitleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.TitleText:SetPoint("TOP", 0, -5)
  end
  win.sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.sub:SetPoint("TOPLEFT", 14, -32)
  win.sub:SetPoint("TOPRIGHT", -14, -32)
  win.sub:SetJustifyH("LEFT")
  local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -50)
  scroll:SetPoint("BOTTOMRIGHT", -30, 30)
  win.child = CreateFrame("Frame", nil, scroll)
  win.child:SetSize(280, 10)
  scroll:SetScrollChild(win.child)
  win.scroll = scroll
  win.journal = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.journal:SetSize(110, 22)
  win.journal:SetPoint("BOTTOMRIGHT", -10, 6)
  win.journal:SetText("Journal page")
  win.journal:SetScript("OnClick", function()
    if win.npc and ns.Data.npcs[win.npc] and ns.Journal then ns.Journal.Open({ npc = win.npc }) end
  end)
  win.note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.note:SetPoint("BOTTOMLEFT", 14, 12)
  win.note:SetText("Classic drop rates")
end

function ns.ShowLootWindow(npcID)
  if not win then BuildWindow() end
  win.npc = npcID
  win.TitleText:SetText("Loot: " .. NameOf(npcID))
  local list = ns.LootFor(npcID) or {}
  win.sub:SetText(#list > 0 and (#list .. " items, sorted by drop chance") or "No loot data for this mob.")
  for i, e in ipairs(list) do
    local b = Row(i)
    b.itemID, b.itemName = e.id, e.name
    b.icon:SetTexture(ns.LootItemIcon(e.id))
    b.text:SetText("|c" .. (QUALITY_HEX[e.quality] or QUALITY_HEX[1]) .. e.name .. "|r")
    b.right:SetText(e.quest and "|cffffd100quest|r" or ns.LootChanceText(e))
    b:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.child:SetHeight(math.max(10, #list * ROW_H))
  win.scroll:SetVerticalScroll(0)
  win.journal:SetShown(ns.Data.npcs[npcID] ~= nil)
  win:Show()
end

-- NPC ID of a unit, or nil when the game hides it.
local function UnitNpcID(unit)
  local exists = UnitExists(unit)
  if IsSecret(exists) or not exists then return nil end
  return ns.NpcIDFromGUID(UnitGUID(unit))
end

-- Mobs whose name contains text, exact matches first. Journal names win
-- over Classic names (some mobs were renamed in Forever).
local function FindByName(text)
  local q = text:lower()
  local exact, partial, seen = {}, {}, {}
  local function test(id, name)
    if seen[id] or not ns.LootFor(id) then return end
    local n = name:lower()
    if n == q then exact[#exact + 1] = id; seen[id] = true
    elseif n:find(q, 1, true) then partial[#partial + 1] = id; seen[id] = true end
  end
  for id, npc in pairs(ns.Data.npcs) do test(id, npc.name) end
  for id, name in pairs(ns.Loot and ns.Loot.names or {}) do
    if not ns.Data.npcs[id] then test(id, name) end
  end
  table.sort(partial, function(a, b) return NameOf(a) < NameOf(b) end)
  return exact, partial
end

ns.Command("loot", "[mob name]  Show the whole loot table of your target, the mob under the mouse, the current boss, or a mob by name.", function(arg)
  if arg and arg ~= "" then
    local exact, partial = FindByName(arg)
    local id = exact[1] or (#partial == 1 and partial[1])
    if id then ns.ShowLootWindow(id); return end
    if #partial == 0 then ns.Print("No mob with loot matches \"" .. arg .. "\".") return end
    ns.Print(#partial .. " mobs match, be more specific:")
    for i = 1, math.min(#partial, 10) do DEFAULT_CHAT_FRAME:AddMessage("  " .. NameOf(partial[i])) end
    if #partial > 10 then DEFAULT_CHAT_FRAME:AddMessage("  ...") end
    return
  end
  local id = UnitNpcID("target") or UnitNpcID("mouseover") or (ns.encounter and ns.encounter.npcID)
  if id then ns.ShowLootWindow(id); return end
  ns.Print("The game hides which mob this is right now (dungeons, combat). Try /ft loot <name>, or open /ft.")
end)
