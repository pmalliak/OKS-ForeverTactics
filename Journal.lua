-- ForeverTactics: journal window.
-- Left: instances and their mobs. Right: abilities, tactics and tricks.
local _, ns = ...

local J = {}
ns.Journal = J

local ROW_H = 20
local KIND_LABEL = { boss = "Boss", rare = "Rare", trash = "Trash" }
local KIND_COLOR = { boss = "ffff8040", rare = "ffc0c0ff", trash = "ffb0b0b0" }
local KIND_ICON = {
  boss = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
  rare = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  trash = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
}
local TRICK_LABEL = {
  ["clever-use"] = "|cff40ff40clever use|r",
  ["bug-abuse"] = "|cffff4040bug abuse, may get hotfixed or punished|r",
  ["unverified"] = "|cffffd100unverified|r",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROLES = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { tank = "0:19:22:41", healer = "20:39:1:20", dps = "20:39:22:41" }

-- Tag name -> color and optional label.
local TAG_STYLE = {
  tank = { "ff4f9bff", "Tank" },
  healer = { "ff40ff80", "Healer" },
  dps = { "ffff6060", "DPS" },
  interrupt = { "ffd080ff", "Interrupt" },
  avoid = { "ffff5050", "Avoid" },
  spread = { "ffffa040", "Spread" },
  fear = { "ffffd100", "Fear" },
  purge = { "ff40e0ff", "Purge" },
  bleed = { "ffd04040", "Bleed" },
}

local SCHOOLS = {
  { "fire", "Fire", "ffff6a00", "Spell_Fire_Fire" },
  { "frost", "Frost", "ff69ccf0", "Spell_Frost_FrostBolt02" },
  { "nature", "Nature", "ff4dff4d", "Spell_Nature_ProtectionformNature" },
  { "shadow", "Shadow", "ffb070ff", "Spell_Shadow_AntiShadow" },
  { "arcane", "Arcane", "ffff80ff", "Spell_Nature_WispSplode" },
  { "holy", "Holy", "ffffe680", "Spell_Holy_HolyBolt" },
}

local function Icon(path, size)
  size = size or 16
  return ("|T%s:%d:%d:0:0|t"):format(path, size, size)
end

local function RoleIcon(role, size)
  size = size or 14
  return ("|T%s:%d:%d:0:0:64:64:%s|t"):format(ROLES, size, size, ROLE_COORDS[role])
end

local function C(color, text)
  return "|c" .. color .. text .. "|r"
end

local function Num(n)
  local s = tostring(n)
  while true do
    local k
    s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end

local function AbilityIcon(a)
  if a.icon then return "Interface\\Icons\\" .. a.icon end
  if a.spellID and C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, a.spellID)
    if ok and tex then return tex end
  end
  return QUESTION
end

local function TagText(tag)
  local school = tag:match("^dispel:(%a+)")
  if school then return C("ff40e0ff", "Dispel " .. school) end
  local st = TAG_STYLE[tag]
  local text = st and C(st[1], st[2]) or C("ffaaaaaa", tag)
  if ROLE_COORDS[tag] then text = RoleIcon(tag, 12) .. " " .. text end
  return text
end

local state = {
  instance = nil, -- selected instance key
  npc = nil,      -- selected npcID
  guess = nil,    -- { level, classification, name } from the target button
  likely = nil,   -- set of npcIDs that match the guess
}

local frame, listChild, rows, title, subtitle, portrait, targetLabel, detailChild

-- Guessing -------------------------------------------------------------------

-- Score how well a mob matches what we can read about a secret target.
function ns.GuessScore(npc, guess)
  local score = 0
  local level = guess.level
  if level and level > 0 and npc.level then
    if level >= npc.level[1] and level <= npc.level[2] then
      score = score + 2
    elseif level >= npc.level[1] - 1 and level <= npc.level[2] + 1 then
      score = score + 1
    end
  elseif level == -1 and npc.kind == "boss" then
    score = score + 2 -- skull level
  end
  local c = guess.classification
  if c == "rare" or c == "rareelite" then
    if npc.kind == "rare" then score = score + 3 end
  elseif c == "worldboss" then
    if npc.kind == "boss" then score = score + 3 end
  elseif c == "normal" or c == "minus" or c == "trivial" then
    if npc.kind == "trash" then score = score + 1 end
  end
  return score
end

local function ComputeLikely()
  state.likely = nil
  if not state.guess or not state.instance then return end
  local inst = ns.Data.instances[state.instance]
  local best, list = 0, {}
  for _, id in ipairs(inst.order) do
    local s = ns.GuessScore(ns.Data.npcs[id], state.guess)
    list[#list + 1] = { id = id, s = s }
    if s > best then best = s end
  end
  if best < 2 then return end
  state.likely = {}
  for _, e in ipairs(list) do
    if e.s == best then
      state.likely[#state.likely + 1] = e.id
    end
  end
  if #state.likely == 1 and not state.npc then
    state.npc = state.likely[1]
  end
end

-- Text building --------------------------------------------------------------

local function H(icon, text)
  return Icon(icon, 18) .. " |cffffd100" .. text:upper() .. "|r"
end

local function TrickLines(out, tricks)
  for _, t in ipairs(tricks) do
    local build = t.confirmedBuild and ("confirmed on " .. t.confirmedBuild) or "not confirmed in Forever yet"
    out[#out + 1] = Icon("Interface\\Icons\\INV_Misc_Note_01", 14) .. " |cffffffff" .. t.title .. "|r"
    out[#out + 1] = "    " .. (TRICK_LABEL[t.kind] or t.kind) .. "|cff888888, " .. build .. "|r"
    out[#out + 1] = "    " .. t.text
    out[#out + 1] = ""
  end
end

local function StatsLines(out, st)
  if not st then return end
  out[#out + 1] = H("Interface\\Icons\\INV_Misc_Book_11", "Stats")
  local parts = {}
  if st.type then parts[#parts + 1] = "|cffffffff" .. st.type .. "|r" end
  parts[#parts + 1] = "Health " .. C("ff40ff40", st.health and Num(st.health) or "?")
  if st.mana then parts[#parts + 1] = "Mana " .. C("ff4f9bff", Num(st.mana)) end
  if st.armor then parts[#parts + 1] = "Armor " .. C("ffd0d0d0", Num(st.armor)) end
  if st.damage then parts[#parts + 1] = "Melee " .. C("ffff8080", st.damage) end
  out[#out + 1] = table.concat(parts, "   ")

  if not st.resist then
    out[#out + 1] = "|cff888888Health from Wowhead (Forever, normal mode).|r"
    out[#out + 1] = ""
    return
  end
  local res = {}
  local r = st.resist
  for _, sc in ipairs(SCHOOLS) do
    local v = r[sc[1]]
    if v ~= nil or sc[1] ~= "holy" then
      res[#res + 1] = Icon("Interface\\Icons\\" .. sc[4], 14) .. " " .. C(sc[3], v ~= nil and tostring(v) or "?")
    end
  end
  out[#out + 1] = "Resist  " .. table.concat(res, "   ")
  if st.immune and #st.immune > 0 then
    out[#out + 1] = "Immune  " .. C("ffff5050", table.concat(st.immune, ", "))
  elseif st.immune then
    out[#out + 1] = "Immune  " .. C("ff40ff40", "nothing, all crowd control works")
  end
  if st.statsSource == "cmangos-classic" then
    if st.healthSource == "wowhead-forever" then
      out[#out + 1] = "|cff888888Health from Wowhead (Forever). Armor, damage, resistances and immunities from Classic server data, may differ in Forever.|r"
    else
      out[#out + 1] = "|cff888888Stats from Classic server data, may differ in Forever.|r"
    end
  end
  out[#out + 1] = ""
end

local function InstanceText(key)
  local inst = ns.Data.instances[key]
  local out = {}
  if inst.forever then
    out[#out + 1] = "|cff40ff40New in WoW Forever.|r" .. (inst.bossesConfirmed and "" or "  |cffffa040Boss list is our best guess from Wowhead's NPC list, not confirmed yet.|r")
    out[#out + 1] = ""
  end
  if inst.summary then
    out[#out + 1] = inst.summary
    out[#out + 1] = ""
  end
  out[#out + 1] = H("Interface\\Icons\\INV_Misc_Head_Dragon_01", "Bosses")
  for _, id in ipairs(inst.order) do
    local npc = ns.Data.npcs[id]
    if npc.kind ~= "trash" then
      local lv = npc.level[1] == npc.level[2] and tostring(npc.level[1]) or (npc.level[1] .. "-" .. npc.level[2])
      out[#out + 1] = Icon(KIND_ICON[npc.kind], 14) .. " " .. C(KIND_COLOR[npc.kind], npc.name) .. "  |cff888888level " .. lv .. "|r"
    end
  end
  out[#out + 1] = ""
  if inst.tricks and #inst.tricks > 0 then
    out[#out + 1] = H("Interface\\Icons\\INV_Misc_Bomb_04", "Tricks for the whole dungeon")
    TrickLines(out, inst.tricks)
  end
  out[#out + 1] = "|cff888888Pick a mob on the left.|r"
  return table.concat(out, "\n")
end

local function NpcText(id)
  local npc = ns.Data.npcs[id]
  local out = {}

  StatsLines(out, npc.stats)

  if npc.fleesAt then
    local immune = {}
    for _, m in ipairs((npc.stats and npc.stats.immune) or {}) do immune[m] = true end
    local hint = (immune.stun and immune.snare) and "can pull more mobs, it cannot be stunned or slowed, so burst it"
      or "can pull more mobs, stun or slow it"
    out[#out + 1] = Icon("Interface\\Icons\\Ability_Rogue_Sprint", 14) .. " " .. C("ffffa040", "Runs away at " .. npc.fleesAt .. "% health") .. "  |cff888888(" .. hint .. ")|r"
    out[#out + 1] = ""
  end

  out[#out + 1] = H("Interface\\Icons\\Spell_Holy_SealOfMight", "Abilities")
  if #npc.abilities == 0 then
    out[#out + 1] = "|cff888888Nothing special known.|r"
  end
  local function inPhase(a, ph)
    if not a.phases then return true end
    for _, p in ipairs(a.phases) do if p == ph then return true end end
    return false
  end
  if npc.phases and #npc.phases > 1 then
    for _, ph in ipairs(npc.phases) do
      out[#out + 1] = C("ffff8040", ph.name or ("Phase " .. ph.id)) .. (ph.note and ("  |cffaaaaaa" .. ph.note .. "|r") or "")
      for _, a in ipairs(npc.abilities) do
        if inPhase(a, ph.id) then out[#out + 1] = { ability = a } end
      end
    end
  else
    for _, a in ipairs(npc.abilities) do out[#out + 1] = { ability = a } end
  end
  if npc.scripted then
    out[#out + 1] = "|cff888888This boss runs on a custom script, so timings and phases are not in the database yet.|r"
  end
  out[#out + 1] = ""
  if not npc.tactics and npc.kind == "boss" then
    out[#out + 1] = H("Interface\\Icons\\INV_Misc_Map_01", "Tactics")
    out[#out + 1] = "|cff888888Not written yet.|r"
    out[#out + 1] = ""
  end

  if npc.tactics then
    out[#out + 1] = H("Interface\\Icons\\INV_Misc_Map_01", "Tactics")
    for _, role in ipairs({ "general", "tank", "healer", "dps" }) do
      local t = npc.tactics[role]
      if t then
        if role == "general" then
          out[#out + 1] = t
        else
          out[#out + 1] = RoleIcon(role, 16) .. " " .. C(TAG_STYLE[role][1], TAG_STYLE[role][2] .. ":") .. " " .. t
        end
      end
    end
    out[#out + 1] = ""
  end

  if npc.tricks and #npc.tricks > 0 then
    out[#out + 1] = H("Interface\\Icons\\INV_Misc_Bomb_04", "Tricks")
    TrickLines(out, npc.tricks)
  end

  local note = ns.db and ns.db.notes[id]
  if note and note ~= "" then
    out[#out + 1] = H("Interface\\Icons\\INV_Misc_Note_06", "My notes")
    out[#out + 1] = note
  end
  return out
end

-- Rendering --------------------------------------------------------------------

-- Draw the creature's own portrait (like the target frame) from its display
-- ID. Falls back to an icon if the API is missing or fails.
local function SetPortrait(tex, npc, fallback)
  tex:SetTexCoord(0, 1, 0, 1)
  if npc and npc.displayID and SetPortraitTextureFromCreatureDisplayID then
    if pcall(SetPortraitTextureFromCreatureDisplayID, tex, npc.displayID) then
      return true
    end
  end
  tex:SetTexture(fallback)
  return false
end

local function GetRow(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, listChild)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
  row.portrait = row:CreateTexture(nil, "ARTWORK")
  row.portrait:SetSize(18, 18)
  row.portrait:SetPoint("LEFT", 14, 0)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", -2, 0)
  row.text:SetJustifyH("LEFT")
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 0.82, 0, 0.18)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row:SetScript("OnClick", function(self)
    if self.instance then
      if state.instance == self.instance and not state.npc then
        state.instance = nil -- clicking the open dungeon again closes it
      else
        state.instance = self.instance
      end
      state.npc = nil
      state.likely = nil
    elseif self.npc then
      state.npc = self.npc
    end
    J.Refresh()
  end)
  rows[i] = row
  return row
end

local function RowName(npc)
  local mark = npc.kind == "trash" and "" or (" " .. Icon(KIND_ICON[npc.kind], 10))
  return "|c" .. KIND_COLOR[npc.kind] .. npc.name .. "|r" .. mark
end

local function RenderList()
  local n = 0
  local function add(text, instance, npc, selected)
    n = n + 1
    local row = GetRow(n)
    row.instance, row.npc = instance, npc
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", -2, 0)
    if npc then
      local data = ns.Data.npcs[npc]
      SetPortrait(row.portrait, data, KIND_ICON[data.kind])
      row.portrait:Show()
      row.text:SetPoint("LEFT", row.portrait, "RIGHT", 5, 0)
    else
      row.portrait:Hide()
      row.text:SetPoint("LEFT", 4, 0)
    end
    row.text:SetText(text)
    row.hl:SetShown(selected and true or false)
    row:SetEnabled(instance ~= nil or npc ~= nil)
    row:Show()
  end

  local keys = {}
  for key in pairs(ns.Data.instances) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ia, ib = ns.Data.instances[a], ns.Data.instances[b]
    if ia.levels[1] ~= ib.levels[1] then return ia.levels[1] < ib.levels[1] end
    return ia.name < ib.name
  end)

  for _, key in ipairs(keys) do
    local inst = ns.Data.instances[key]
    local open = key == state.instance
    add(Icon("Interface\\Icons\\INV_Misc_Key_13", 14) .. (open and " |cffffd100" or " |cffd0b060") .. inst.name .. "|r" ..
      (inst.forever and " |cff40ff40new|r" or ""), key, nil, open and not state.npc)
    if open then
      if state.likely then
        add("  |cff40ff40Likely your target|r")
        for _, id in ipairs(state.likely) do
          local n2 = ns.Data.npcs[id]
          add(RowName(n2), nil, id, id == state.npc)
        end
        add("  |cff888888All|r")
      end
      for _, id in ipairs(inst.order) do
        local npc = ns.Data.npcs[id]
        add(RowName(npc), nil, id, id == state.npc)
      end
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  listChild:SetHeight(math.max(1, n * ROW_H))
end

local textPool, abPool = {}, {}
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local function GetAbilityBlock(i)
  local b = abPool[i]
  if b then return b end
  b = CreateFrame("Frame", nil, detailChild)
  b:SetWidth(480)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(32, 32)
  b.icon:SetPoint("TOPLEFT", 2, -1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.name:SetWidth(430)
  b.name:SetJustifyH("LEFT")
  b.timing = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.timing:SetWidth(430)
  b.timing:SetJustifyH("LEFT")
  b.timing:SetTextColor(0.55, 0.8, 1)
  b.note = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.note:SetWidth(430)
  b.note:SetJustifyH("LEFT")
  b.note:SetTextColor(0.85, 0.85, 0.85)
  b:EnableMouse(true)
  b:SetScript("OnEnter", function(self)
    if not self.spellID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
      GameTooltip:Show()
    else
      GameTooltip:Hide()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  abPool[i] = b
  return b
end

local function FillAbility(b, a)
  b.spellID = a.spellID
  b.icon:SetTexture(AbilityIcon(a))
  local line = "|cffffffff" .. a.name .. "|r"
  if a.tags and #a.tags > 0 then
    local tags = {}
    for _, t in ipairs(a.tags) do tags[#tags + 1] = TagText(t) end
    line = line .. "   " .. table.concat(tags, "  ")
  end
  if a.verified == false then line = line .. "  |cff666666(unverified)|r" end
  b.name:ClearAllPoints()
  b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 0)
  b.name:SetText(line)
  local last, h = b.name, b.name:GetStringHeight()
  if a.timing then
    b.timing:ClearAllPoints()
    b.timing:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
    b.timing:SetText(Icon(CLOCK, 11) .. " " .. a.timing)
    b.timing:Show()
    last, h = b.timing, h + 2 + b.timing:GetStringHeight()
  else
    b.timing:Hide()
  end
  if a.note and a.note ~= "" then
    b.note:ClearAllPoints()
    b.note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
    b.note:SetText(a.note)
    b.note:Show()
    h = h + 2 + b.note:GetStringHeight()
  else
    b.note:Hide()
  end
  b.h = math.max(34, h + 2)
  b:SetHeight(b.h)
end

-- items: strings (joined into text blocks) and { ability = a } entries.
local function Layout(items)
  for _, fs in ipairs(textPool) do fs:Hide() end
  for _, b in ipairs(abPool) do b:Hide() end
  local y, nt, na, buf = 0, 0, 0, {}
  local function flush()
    while #buf > 0 and buf[#buf] == "" do buf[#buf] = nil end
    if #buf == 0 then return end
    nt = nt + 1
    local fs = textPool[nt]
    if not fs then
      fs = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetWidth(480)
      fs:SetJustifyH("LEFT")
      fs:SetJustifyV("TOP")
      fs:SetSpacing(2)
      textPool[nt] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, -y)
    fs:SetText(table.concat(buf, "\n"))
    fs:Show()
    y = y + fs:GetStringHeight() + 10
    wipe(buf)
  end
  for _, it in ipairs(items) do
    if type(it) == "table" then
      flush()
      na = na + 1
      local b = GetAbilityBlock(na)
      FillAbility(b, it.ability)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -y)
      b:Show()
      y = y + b.h + 8
    else
      buf[#buf + 1] = it
    end
  end
  flush()
  detailChild:SetHeight(y + 20)
end

local function RenderDetail()
  if state.npc and ns.Data.npcs[state.npc] then
    local npc = ns.Data.npcs[state.npc]
    title:SetText(C(KIND_COLOR[npc.kind], npc.name))
    local lv = npc.level[1] == npc.level[2] and tostring(npc.level[1]) or (npc.level[1] .. "-" .. npc.level[2])
    local inst = ns.Data.instances[npc.instance]
    subtitle:SetText(Icon(KIND_ICON[npc.kind], 12) .. " " .. KIND_LABEL[npc.kind] ..
      (npc.subName and ("  |cffd0d0d0<" .. npc.subName .. ">|r") or "") .. "  |cff888888level " .. lv ..
      (inst and ("  |  " .. inst.name) or "") .. "|r")
    local first = npc.abilities[1]
    SetPortrait(portrait, npc, npc.icon and ("Interface\\Icons\\" .. npc.icon) or (first and AbilityIcon(first)) or KIND_ICON[npc.kind])
    Layout(NpcText(state.npc))
  elseif state.instance then
    local inst = ns.Data.instances[state.instance]
    title:SetText("|cffffd100" .. inst.name .. "|r")
    subtitle:SetText(("|cff888888Dungeon  |  levels %d-%d|r"):format(inst.levels[1], inst.levels[2]))
    SetPortrait(portrait, nil, "Interface\\Icons\\INV_Misc_Key_13")
    Layout({ InstanceText(state.instance) })
  else
    title:SetText("ForeverTactics")
    subtitle:SetText("")
    SetPortrait(portrait, nil, "Interface\\Icons\\INV_Misc_Book_09")
    Layout({ "Pick a dungeon on the left." })
  end
end

local function RenderTargetLabel()
  targetLabel:SetText("")
  if not state.guess then return end
  -- The target name is secret inside instances. FontStrings may display a
  -- secret, but addon code may not read it, so pcall in case that changes.
  local name = state.guess.name
  if name ~= nil then
    pcall(targetLabel.SetText, targetLabel, name)
  end
end

-- Frame -------------------------------------------------------------------------

local function Build()
  frame = CreateFrame("Frame", "ForeverTacticsJournal", UIParent, "BackdropTemplate")
  frame:SetSize(760, 500)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  frame:Hide()
  tinsert(UISpecialFrames, "ForeverTacticsJournal") -- close with Escape

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 16, -14)
  head:SetText("ForeverTactics " .. ns.VERSION)

  targetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  targetLabel:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)

  -- Left list
  local listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  listScroll:SetPoint("TOPLEFT", 14, -48)
  listScroll:SetPoint("BOTTOMLEFT", 14, 14)
  listScroll:SetWidth(200)
  listChild = CreateFrame("Frame", nil, listScroll)
  listChild:SetSize(200, 1)
  listScroll:SetScrollChild(listChild)
  rows = {}

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(1, 1, 1, 0.15)
  divider:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 26, 0)
  divider:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 26, 0)
  divider:SetWidth(1)

  -- Right detail header: icon, title, subtitle
  portrait = frame:CreateTexture(nil, "ARTWORK")
  portrait:SetSize(40, 40)
  portrait:SetPoint("TOPLEFT", divider, "TOPRIGHT", 12, 0)
  local ring = frame:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  ring:SetSize(68, 68)

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
  title:SetJustifyH("LEFT")
  subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetJustifyH("LEFT")

  local detailScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  detailScroll:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -12)
  detailScroll:SetPoint("BOTTOMRIGHT", -34, 14)
  detailChild = CreateFrame("Frame", nil, detailScroll)
  detailChild:SetSize(480, 1)
  detailScroll:SetScrollChild(detailChild)
end

function J.Refresh()
  if not frame or not frame:IsShown() then return end
  RenderList()
  RenderDetail()
  RenderTargetLabel()
end

-- opts: { instance = key, npc = id, guess = {...} }. Without opts, opens on
-- the current boss fight, else the current dungeon, else the last page.
function J.Open(opts)
  if not frame then Build() end
  opts = opts or {}
  state.guess = opts.guess
  if opts.npc and ns.Data.npcs[opts.npc] then
    state.npc = opts.npc
    state.instance = ns.Data.npcs[opts.npc].instance
  elseif opts.instance then
    state.instance = opts.instance
    state.npc = nil
  else
    local enc = ns.encounter and ns.encounter.npcID
    local here = ns.CurrentInstanceKey()
    if enc then
      state.npc, state.instance = enc, ns.Data.npcs[enc].instance
    elseif here and here ~= state.instance then
      state.instance, state.npc = here, nil
    end
  end
  ComputeLikely()
  frame:Show()
  J.Refresh()
end

function J.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    J.Open()
  end
end

ns.Command("help", "Show this list.", function()
  SlashCmdList.FOREVERTACTICS("?")
end)
