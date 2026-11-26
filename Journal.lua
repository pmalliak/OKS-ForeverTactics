-- ForeverTactics: journal window.
-- Same look as OKS Writ Shopper: a standard Blizzard window with an inset,
-- tabs under it, striped list rows and a dark summary bar.
-- Journal tab: dungeons and mobs on the left, the selected page on the right.
-- Options tab: target button and text size.
local _, ns = ...

local J = {}
ns.Journal = J

local W, H = 940, 600
local LIST_W = 250
local ROW_H = 22
local DETAIL_W = W - LIST_W - 76 -- width of the scrolling page
local BAR_H = 40

local KIND_LABEL = { boss = "Boss", rare = "Rare", trash = "Trash" }
local KIND_COLOR = { boss = "ffff8040", rare = "ffc0c0ff", trash = "ffb0b0b0" }
local KIND_RGB = { boss = { 1, 0.5, 0.25 }, rare = { 0.6, 0.6, 1 }, trash = { 0.45, 0.45, 0.45 } }
local KIND_ICON = {
  boss = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
  rare = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  trash = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
}
local TRICK_LABEL = {
  ["clever-use"] = { "Clever use", "ff40ff40" },
  ["bug-abuse"] = { "Bug abuse, may get hotfixed or punished", "ffff4040" },
  ["unverified"] = { "Unverified", "ffffd100" },
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROLES = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { tank = "0:19:22:41", healer = "20:39:1:20", dps = "20:39:22:41" }
local ROLE_TEX = { tank = { 0, 19 / 64, 22 / 64, 41 / 64 }, healer = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, dps = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- Text sizes for the page body, picked in the Options tab.
local SIZES = {
  { key = "small", label = "Small", body = "GameFontHighlightSmall", name = "GameFontNormalSmall" },
  { key = "normal", label = "Normal", body = "GameFontHighlight", name = "GameFontNormal" },
  { key = "large", label = "Large", body = "GameFontHighlightMedium", name = "GameFontNormalLarge" },
}

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

-- Helpers --------------------------------------------------------------------

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

local function LevelText(lv)
  if not lv then return "" end
  return lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. "-" .. lv[2])
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

local function Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function Button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function Tip(owner, title, body)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Draw the creature's own portrait (like the target frame) from its display
-- ID. A mob without a known model gets no picture at all: a stand-in icon
-- would look like the real thing. Pages that are not mobs pass an icon.
-- Returns true when something is shown.
local function SetPortrait(tex, npc, icon)
  tex:SetTexCoord(0, 1, 0, 1)
  if npc then
    if npc.displayID and SetPortraitTextureFromCreatureDisplayID
      and pcall(SetPortraitTextureFromCreatureDisplayID, tex, npc.displayID) then
      tex:Show()
      return true
    end
    tex:Hide()
    return false
  end
  tex:SetTexture(icon)
  tex:Show()
  return true
end

local function Size()
  local key = ns.db and ns.db.textSize or "normal"
  for _, s in ipairs(SIZES) do if s.key == key then return s end end
  return SIZES[2]
end

-- State --------------------------------------------------------------------

local state = {
  instance = nil, -- open dungeon key
  npc = nil,      -- selected npcID
  guess = nil,    -- { level, classification, name } from the target button
  likely = nil,   -- npcIDs that match the guess
  search = "",
}

local frame, journalPage, optionsPage, tabs
local listScroll, listChild, rows, search
local header, portrait, title, subtitle, targetLabel
local bar, stats, detailScroll, detailChild

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
    if e.s == best then state.likely[#state.likely + 1] = e.id end
  end
  if #state.likely == 1 and not state.npc then
    state.npc = state.likely[1]
  end
end

-- Left list ------------------------------------------------------------------

local function GetRow(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, listChild)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.stripe = row:CreateTexture(nil, "BORDER")
  row.stripe:SetPoint("TOPLEFT", 0, 0)
  row.stripe:SetPoint("BOTTOMLEFT", 0, 0)
  row.stripe:SetWidth(4)
  row.portrait = row:CreateTexture(nil, "ARTWORK")
  row.portrait:SetSize(18, 18)
  row.text = Text(row, "GameFontHighlightSmall")
  row.text:SetWordWrap(false)
  row.right = Text(row, "GameFontDisableSmall", "RIGHT")
  row.right:SetPoint("RIGHT", -6, 0)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row:SetScript("OnClick", function(self)
    if self.instance then
      if state.instance == self.instance and not state.npc then
        state.instance = nil -- clicking the open dungeon again closes it
      else
        state.instance = self.instance
      end
      state.npc, state.likely = nil, nil
    elseif self.npc then
      state.npc = self.npc
      state.instance = ns.Data.npcs[self.npc].instance
    end
    J.Refresh()
  end)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(_, delta)
    local v = listScroll:GetVerticalScroll() - delta * ROW_H * 3
    local max = listScroll:GetVerticalScrollRange() or 0
    listScroll:SetVerticalScroll(math.max(0, math.min(v, max)))
  end)
  rows[i] = row
  return row
end

-- kind: "dungeon", "npc", "label"
local function AddRow(n, kind, opts)
  local row = GetRow(n)
  row.instance, row.npc = opts.instance, opts.npc
  row.text:ClearAllPoints()
  row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
  row.right:SetText(opts.right or "")
  if kind == "dungeon" then
    row.portrait:Hide()
    row.stripe:Hide()
    row.text:SetFontObject("GameFontNormal")
    row.text:SetPoint("LEFT", 8, 0)
    row.bg:SetColorTexture(0, 0, 0, opts.selected and 0.55 or 0.35)
  elseif kind == "npc" then
    local data = ns.Data.npcs[opts.npc]
    row.text:SetFontObject("GameFontHighlightSmall")
    row.portrait:ClearAllPoints()
    row.portrait:SetPoint("LEFT", opts.indent or 14, 0)
    if SetPortrait(row.portrait, data) then
      row.text:SetPoint("LEFT", row.portrait, "RIGHT", 6, 0)
    else
      row.text:SetPoint("LEFT", opts.indent or 14, 0)
    end
    local c = KIND_RGB[data.kind]
    row.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
    row.stripe:Show()
    if opts.selected then
      row.bg:SetColorTexture(0.2, 0.5, 1, 0.3)
    else
      row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.04 or 0)
    end
  else
    row.portrait:Hide()
    row.stripe:Hide()
    row.text:SetFontObject("GameFontDisableSmall")
    row.text:SetPoint("LEFT", 10, 0)
    row.bg:SetColorTexture(0, 0, 0, 0)
  end
  row.text:SetText(opts.text)
  row:SetEnabled(opts.instance ~= nil or opts.npc ~= nil)
  row:Show()
end

local function SortedInstances()
  local keys = {}
  for key in pairs(ns.Data.instances) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ia, ib = ns.Data.instances[a], ns.Data.instances[b]
    if ia.levels[1] ~= ib.levels[1] then return ia.levels[1] < ib.levels[1] end
    return ia.name < ib.name
  end)
  return keys
end

local function NpcRow(n, id, indent)
  local npc = ns.Data.npcs[id]
  AddRow(n, "npc", {
    npc = id,
    text = C(KIND_COLOR[npc.kind], npc.name),
    right = LevelText(npc.level),
    selected = id == state.npc,
    indent = indent,
  })
end

local function RenderList()
  local n = 0
  local query = (state.search or ""):lower()
  if query ~= "" then
    -- Search: matching mobs from every dungeon, grouped under their dungeon.
    for _, key in ipairs(SortedInstances()) do
      local inst = ns.Data.instances[key]
      local hits = {}
      for _, id in ipairs(inst.order) do
        if ns.Data.npcs[id].name:lower():find(query, 1, true) then hits[#hits + 1] = id end
      end
      if #hits > 0 then
        n = n + 1
        AddRow(n, "label", { text = inst.name })
        for _, id in ipairs(hits) do
          n = n + 1
          NpcRow(n, id)
        end
      end
    end
    if n == 0 then
      n = 1
      AddRow(n, "label", { text = "No mob matches." })
    end
  else
    for _, key in ipairs(SortedInstances()) do
      local inst = ns.Data.instances[key]
      local open = key == state.instance
      n = n + 1
      AddRow(n, "dungeon", {
        instance = key,
        text = (open and "|cffffd100" or "|cffd8c890") .. inst.name .. "|r" .. (inst.forever and "  |cff40ff40NEW|r" or ""),
        right = inst.levels[1] .. "-" .. inst.levels[2],
        selected = open and not state.npc,
      })
      if open then
        if state.likely then
          n = n + 1
          AddRow(n, "label", { text = "|cff40ff40Likely your target|r" })
          for _, id in ipairs(state.likely) do
            n = n + 1
            NpcRow(n, id)
          end
          n = n + 1
          AddRow(n, "label", { text = "Everything here" })
        end
        local lastKind
        for _, id in ipairs(inst.order) do
          local kind = ns.Data.npcs[id].kind
          if kind ~= lastKind then
            n = n + 1
            AddRow(n, "label", { text = kind == "boss" and "Bosses" or kind == "rare" and "Rares" or "Trash" })
            lastKind = kind
          end
          n = n + 1
          NpcRow(n, id)
        end
      end
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  listChild:SetHeight(math.max(1, n * ROW_H))
end

-- Page items -----------------------------------------------------------------
-- A page is a list of items laid out top to bottom:
--   { header = text, icon = path }      section title with a line under it
--   { text = s, color = "ffrrggbb" }      a paragraph
--   { note = s }                          small grey paragraph
--   { ability = a }                       icon, name, tags, timing, note
--   { role = "tank", text = s }           tactic line with a role icon
--   { trick = t }                         trick card
--   { link = npcID }                      clickable mob row
--   { phase = text, note = s }            phase title inside abilities

local pools = {}

local function Pool(kind, make)
  local p = pools[kind]
  if not p then
    p = { n = 0 }
    pools[kind] = p
  end
  p.n = p.n + 1
  local w = p[p.n]
  if not w then
    w = make()
    p[p.n] = w
  end
  w:Show()
  return w
end

local function ResetPools()
  for _, p in pairs(pools) do
    for i = 1, #p do p[i]:Hide() end
    p.n = 0
  end
end

local function MakeHeader()
  local f = CreateFrame("Frame", nil, detailChild)
  f:SetSize(DETAIL_W, 26)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(20, 20)
  f.icon:SetPoint("LEFT", 0, 2)
  f.text = Text(f, "GameFontNormal")
  f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.line = f:CreateTexture(nil, "ARTWORK")
  f.line:SetColorTexture(1, 0.82, 0, 0.35)
  f.line:SetPoint("BOTTOMLEFT", 0, 0)
  f.line:SetPoint("BOTTOMRIGHT", 0, 0)
  f.line:SetHeight(1)
  return f
end

local function MakeText()
  local fs = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  return fs
end

local function MakeAbility()
  local b = CreateFrame("Frame", nil, detailChild)
  b:SetWidth(DETAIL_W)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(36, 36)
  b.icon:SetPoint("TOPLEFT", 6, -6)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.name = Text(b, "GameFontNormal")
  b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, 0)
  b.name:SetWidth(DETAIL_W - 64)
  b.timing = Text(b, "GameFontHighlightSmall")
  b.timing:SetWidth(DETAIL_W - 64)
  b.timing:SetTextColor(0.55, 0.8, 1)
  b.note = Text(b, "GameFontHighlight")
  b.note:SetWidth(DETAIL_W - 64)
  b.note:SetSpacing(2)
  b.note:SetTextColor(0.9, 0.9, 0.9)
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
  return b
end

local function MakeRole()
  local f = CreateFrame("Frame", nil, detailChild)
  f:SetWidth(DETAIL_W)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(22, 22)
  f.icon:SetPoint("TOPLEFT", 2, 0)
  f.icon:SetTexture(ROLES)
  f.label = Text(f, "GameFontNormal")
  f.label:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
  f.text = Text(f, "GameFontHighlight")
  f.text:SetSpacing(3)
  f.text:SetWidth(DETAIL_W - 34)
  f.text:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3)
  return f
end

local function MakeTrick()
  local f = CreateFrame("Frame", nil, detailChild)
  f:SetWidth(DETAIL_W)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(1, 0.82, 0, 0.06)
  f.stripe = f:CreateTexture(nil, "BORDER")
  f.stripe:SetPoint("TOPLEFT")
  f.stripe:SetPoint("BOTTOMLEFT")
  f.stripe:SetWidth(4)
  f.title = Text(f, "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 14, -8)
  f.kind = Text(f, "GameFontHighlightSmall")
  f.kind:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.text = Text(f, "GameFontHighlight")
  f.text:SetSpacing(3)
  f.text:SetWidth(DETAIL_W - 28)
  f.text:SetPoint("TOPLEFT", f.kind, "BOTTOMLEFT", 0, -5)
  return f
end

local function MakeLink()
  local b = CreateFrame("Button", nil, detailChild)
  b:SetSize(DETAIL_W, 26)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.stripe = b:CreateTexture(nil, "BORDER")
  b.stripe:SetPoint("TOPLEFT")
  b.stripe:SetPoint("BOTTOMLEFT")
  b.stripe:SetWidth(4)
  b.portrait = b:CreateTexture(nil, "ARTWORK")
  b.portrait:SetSize(22, 22)
  b.portrait:SetPoint("LEFT", 12, 0)
  b.text = Text(b, "GameFontHighlight")
  b.text:SetPoint("LEFT", b.portrait, "RIGHT", 8, 0)
  b.right = Text(b, "GameFontDisableSmall", "RIGHT")
  b.right:SetPoint("RIGHT", -8, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    state.npc = self.npc
    J.Refresh()
  end)
  return b
end

local function MakeLoot()
  local b = CreateFrame("Button", nil, detailChild)
  b:SetSize(DETAIL_W / 2 - 4, 24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.right = Text(b, "GameFontHighlightSmall", "RIGHT")
  b.right:SetPoint("RIGHT", -6, 0)
  b.text = Text(b, "GameFontHighlight")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
  b.text:SetWordWrap(false)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
      GameTooltip:AddLine(self.itemName or "?")
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function Layout(items)
  ResetPools()
  local size = Size()
  local y = 0
  local nAbility = 0
  for _, it in ipairs(items) do
    if it.header then
      local f = Pool("header", MakeHeader)
      f.icon:SetTexture(it.icon or QUESTION)
      f.text:SetText(it.header:upper())
      if y > 0 then y = y + 10 end
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", 0, -y)
      y = y + 26 + 8
      nAbility = 0
    elseif it.text or it.note then
      local fs = Pool("text", MakeText)
      fs:SetFontObject(it.note and "GameFontDisableSmall" or size.body)
      fs:SetWidth(DETAIL_W - 4)
      fs:SetText(it.note or (it.color and C(it.color, it.text) or it.text))
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 2, -y)
      y = y + fs:GetStringHeight() + (it.gap or 8)
    elseif it.phase then
      local fs = Pool("text", MakeText)
      fs:SetFontObject(size.name)
      fs:SetWidth(DETAIL_W - 4)
      fs:SetText(C("ffff8040", it.phase) .. (it.note and ("  |cffaaaaaa" .. it.note .. "|r") or ""))
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 2, -y - 2)
      y = y + fs:GetStringHeight() + 8
    elseif it.ability then
      local a = it.ability
      local b = Pool("ability", MakeAbility)
      nAbility = nAbility + 1
      b.bg:SetColorTexture(1, 1, 1, nAbility % 2 == 1 and 0.05 or 0.02)
      b.spellID = a.spellID
      b.icon:SetTexture(AbilityIcon(a))
      b.name:SetFontObject(size.name)
      local line = "|cffffffff" .. a.name .. "|r"
      if a.tags and #a.tags > 0 then
        local tags = {}
        for _, t in ipairs(a.tags) do tags[#tags + 1] = TagText(t) end
        line = line .. "    " .. table.concat(tags, "   ")
      end
      if a.verified == false then line = line .. "  |cff666666(unverified)|r" end
      b.name:SetText(line)
      local last, h = b.name, b.name:GetStringHeight()
      if a.timing then
        b.timing:ClearAllPoints()
        b.timing:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -3)
        b.timing:SetText(Icon(CLOCK, 12) .. " " .. a.timing)
        b.timing:Show()
        last, h = b.timing, h + 3 + b.timing:GetStringHeight()
      else
        b.timing:Hide()
      end
      if a.note and a.note ~= "" then
        b.note:SetFontObject(size.body)
        b.note:ClearAllPoints()
        b.note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -4)
        b.note:SetText(a.note)
        b.note:Show()
        h = h + 4 + b.note:GetStringHeight()
      else
        b.note:Hide()
      end
      local bh = math.max(48, h + 14)
      b:SetHeight(bh)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -y)
      y = y + bh + 2
    elseif it.role then
      local f = Pool("role", MakeRole)
      local tc = ROLE_TEX[it.role]
      f.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      f.label:SetText(C(TAG_STYLE[it.role][1], TAG_STYLE[it.role][2]))
      f.text:SetFontObject(size.body)
      f.text:SetText(it.text)
      local h = f.label:GetStringHeight() + 3 + f.text:GetStringHeight()
      f:SetHeight(h)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", 0, -y)
      y = y + h + 12
    elseif it.trick then
      local t = it.trick
      local f = Pool("trick", MakeTrick)
      local kl = TRICK_LABEL[t.kind] or { t.kind, "ffaaaaaa" }
      f.title:SetText(Icon("Interface\\Icons\\INV_Misc_Note_01", 16) .. " |cffffffff" .. t.title .. "|r")
      local build = t.confirmedBuild and ("confirmed on " .. t.confirmedBuild) or "not confirmed in Forever yet"
      f.kind:SetText(C(kl[2], kl[1]) .. "|cff888888, " .. build .. "|r")
      local r, g, b = tonumber(kl[2]:sub(3, 4), 16) / 255, tonumber(kl[2]:sub(5, 6), 16) / 255, tonumber(kl[2]:sub(7, 8), 16) / 255
      f.stripe:SetColorTexture(r, g, b, 0.9)
      f.text:SetFontObject(size.body)
      f.text:SetText(t.text)
      local h = 8 + f.title:GetStringHeight() + 3 + f.kind:GetStringHeight() + 5 + f.text:GetStringHeight() + 10
      f:SetHeight(h)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", 0, -y)
      y = y + h + 6
    elseif it.loot then
      local half = DETAIL_W / 2
      for i, e in ipairs(it.loot) do
        local b = Pool("loot", MakeLoot)
        local col = (i - 1) % 2
        b.itemID, b.itemName = e.id, e.name
        b.bg:SetColorTexture(1, 1, 1, (math.floor((i - 1) / 2) % 2 == 0) and 0.04 or 0.0)
        b.icon:SetTexture(ns.LootItemIcon(e.id))
        b.text:SetText("|c" .. (ns.QUALITY_HEX[e.quality] or "ffffffff") .. e.name .. "|r")
        b.right:SetText(e.quest and "|cffffd100quest|r" or ns.LootChanceText(e))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", col * half, -y)
        if col == 1 or i == #it.loot then y = y + 26 end
      end
      y = y + 4
    elseif it.link then
      local npc = ns.Data.npcs[it.link]
      local b = Pool("link", MakeLink)
      b.npc = it.link
      local c = KIND_RGB[npc.kind]
      b.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
      b.bg:SetColorTexture(1, 1, 1, it.alt and 0.04 or 0.0)
      b.text:ClearAllPoints()
      if SetPortrait(b.portrait, npc) then
        b.text:SetPoint("LEFT", b.portrait, "RIGHT", 8, 0)
      else
        b.text:SetPoint("LEFT", 12, 0)
      end
      b.text:SetText(C(KIND_COLOR[npc.kind], npc.name) .. (npc.tactics and "" or "  |cff666666no tactics yet|r"))
      b.right:SetText(KIND_LABEL[npc.kind] .. "   level " .. LevelText(npc.level))
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -y)
      y = y + 26
    end
  end
  detailChild:SetHeight(y + 20)
  detailScroll:SetVerticalScroll(0)
end

-- Page content ---------------------------------------------------------------

local function TrickItems(out, tricks)
  for _, t in ipairs(tricks) do out[#out + 1] = { trick = t } end
end

local function DefenseItems(out, npc)
  local st = npc.stats
  if not st or not st.resist then return end
  out[#out + 1] = { header = "Defenses", icon = "Interface\\Icons\\INV_Shield_06" }
  local res = {}
  for _, sc in ipairs(SCHOOLS) do
    local v = st.resist[sc[1]]
    if v ~= nil or sc[1] ~= "holy" then
      res[#res + 1] = Icon("Interface\\Icons\\" .. sc[4], 16) .. " " .. C(sc[3], v ~= nil and tostring(v) or "?")
    end
  end
  out[#out + 1] = { text = "|cffaaaaaaResistances|r   " .. table.concat(res, "     "), gap = 6 }
  if st.immune and #st.immune > 0 then
    out[#out + 1] = { text = "|cffaaaaaaImmune to|r   " .. C("ffff6060", table.concat(st.immune, ", ")) }
  elseif st.immune then
    out[#out + 1] = { text = "|cffaaaaaaImmune to|r   " .. C("ff40ff40", "nothing, all crowd control works") }
  end
  if npc.fleesAt then
    local immune = {}
    for _, m in ipairs(st.immune or {}) do immune[m] = true end
    local hint = (immune.stun and immune.snare) and "It can't be stunned or slowed, so burst it down before it runs."
      or "It can pull more mobs, so stun or slow it."
    out[#out + 1] = { text = Icon("Interface\\Icons\\Ability_Rogue_Sprint", 16) .. " " .. C("ffffa040", "Runs away at " .. npc.fleesAt .. "% health.") .. " " .. hint }
  end
  if st.statsSource == "cmangos-classic" then
    out[#out + 1] = { note = st.healthSource == "wowhead-forever"
      and "Health from Wowhead (Forever). Armor, damage, resistances and immunities from Classic server data, they may differ in Forever."
      or "Stats from Classic server data, they may differ in Forever." }
  end
end

local function NpcItems(id)
  local npc = ns.Data.npcs[id]
  local out = {}

  -- Tactics first: that is what people open the page for.
  out[#out + 1] = { header = "Tactics", icon = "Interface\\Icons\\INV_Misc_Map_01" }
  if npc.tactics then
    if npc.tactics.general then out[#out + 1] = { text = npc.tactics.general, gap = 12 } end
    for _, role in ipairs({ "tank", "healer", "dps" }) do
      if npc.tactics[role] then out[#out + 1] = { role = role, text = npc.tactics[role] } end
    end
  elseif npc.kind == "boss" then
    out[#out + 1] = { note = "Not written yet." }
  else
    out[#out + 1] = { note = "Nothing special. Check its abilities below." }
  end

  out[#out + 1] = { header = "Abilities", icon = "Interface\\Icons\\Spell_Holy_SealOfMight" }
  if #npc.abilities == 0 then
    out[#out + 1] = { note = "Nothing special known." }
  end
  local function inPhase(a, ph)
    if not a.phases then return true end
    for _, p in ipairs(a.phases) do if p == ph then return true end end
    return false
  end
  if npc.phases and #npc.phases > 1 then
    for _, ph in ipairs(npc.phases) do
      out[#out + 1] = { phase = ph.name or ("Phase " .. ph.id), note = ph.note }
      for _, a in ipairs(npc.abilities) do
        if inPhase(a, ph.id) then out[#out + 1] = { ability = a } end
      end
    end
  else
    for _, a in ipairs(npc.abilities) do out[#out + 1] = { ability = a } end
  end
  if npc.scripted then
    out[#out + 1] = { note = "This boss runs on a custom script, so timings and phases are not known yet." }
  end

  if npc.tricks and #npc.tricks > 0 then
    out[#out + 1] = { header = "Tricks", icon = "Interface\\Icons\\INV_Misc_Bomb_04" }
    TrickItems(out, npc.tricks)
  end

  DefenseItems(out, npc)

  local loot = ns.LootFor and ns.LootFor(id)
  out[#out + 1] = { header = "Loot", icon = "Interface\\Icons\\INV_Misc_Bag_10" }
  if loot then
    out[#out + 1] = { loot = loot }
    local key = ns.db and ns.db.lootKey or "ctrl"
    local how = (key == "off") and "" or (key == "always") and " Hover a mob in the open world to see this in its tooltip."
      or (" Hold " .. (ns.LOOT_KEY_LABEL[key] or "Ctrl") .. " over a mob in the open world to see this in its tooltip.")
    out[#out + 1] = { note = "Drop chances from Classic server data, they may differ in Forever." .. how }
  else
    out[#out + 1] = { note = "No loot data for this mob yet." }
  end

  local note = ns.db and ns.db.notes[id]
  if note and note ~= "" then
    out[#out + 1] = { header = "My notes", icon = "Interface\\Icons\\INV_Misc_Note_06" }
    out[#out + 1] = { text = note }
  end
  return out
end

local function InstanceItems(key)
  local inst = ns.Data.instances[key]
  local out = {}
  if inst.forever then
    out[#out + 1] = { text = "New in WoW Forever.", color = "ff40ff40", gap = 4 }
    if not inst.bossesConfirmed then
      out[#out + 1] = { note = "Boss list is our best guess from Wowhead's NPC list, not confirmed yet." }
    end
  end
  if inst.summary then out[#out + 1] = { text = inst.summary, gap = 4 } end
  local groups = { { "boss", "Bosses", "Interface\\Icons\\INV_Misc_Head_Dragon_01" }, { "rare", "Rares", "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze" } }
  for _, g in ipairs(groups) do
    local any = false
    local alt = false
    for _, id in ipairs(inst.order) do
      if ns.Data.npcs[id].kind == g[1] then
        if not any then
          out[#out + 1] = { header = g[2], icon = g[3] }
          any = true
        end
        alt = not alt
        out[#out + 1] = { link = id, alt = alt }
      end
    end
  end
  if inst.tricks and #inst.tricks > 0 then
    out[#out + 1] = { header = "Tricks for the whole dungeon", icon = "Interface\\Icons\\INV_Misc_Bomb_04" }
    TrickItems(out, inst.tricks)
  end
  return out
end

-- Header and summary bar -----------------------------------------------------

local function SetStats(list)
  for i, s in ipairs(stats) do
    local v = list and list[i]
    if v then
      s.label:SetText(v[1])
      s.value:SetText(v[2])
      s:Show()
    else
      s:Hide()
    end
  end
end

local function NpcStats(npc)
  local st = npc.stats or {}
  local list = {
    { "Type", st.type or "?" },
    { "Level", LevelText(npc.level) },
    { "Health", st.health and C("ff40ff40", Num(st.health)) or "|cff888888unknown|r" },
  }
  if st.mana then list[#list + 1] = { "Mana", C("ff4f9bff", Num(st.mana)) } end
  if st.armor then list[#list + 1] = { "Armor", Num(st.armor) } end
  if st.damage then list[#list + 1] = { "Melee hit", C("ffff8080", st.damage) } end
  if npc.fleesAt then list[#list + 1] = { "Runs away", C("ffffa040", npc.fleesAt .. "%") } end
  return list
end

local function InstanceStats(inst)
  local b, r, t = 0, 0, 0
  for _, id in ipairs(inst.order) do
    local k = ns.Data.npcs[id].kind
    if k == "boss" then b = b + 1 elseif k == "rare" then r = r + 1 else t = t + 1 end
  end
  return {
    { "Levels", inst.levels[1] .. "-" .. inst.levels[2] },
    { "Bosses", tostring(b) },
    { "Rares", tostring(r) },
    { "Other mobs", tostring(t) },
  }
end

-- Header without a picture: hide the ring and move the name to the left.
local function ShowPortrait(shown)
  header.ring:SetShown(shown)
  title:ClearAllPoints()
  if shown then
    title:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -4)
  else
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -6)
  end
end

local function RenderDetail()
  if state.npc and ns.Data.npcs[state.npc] then
    local npc = ns.Data.npcs[state.npc]
    local inst = ns.Data.instances[npc.instance]
    title:SetText(C(KIND_COLOR[npc.kind], npc.name))
    subtitle:SetText(C(KIND_COLOR[npc.kind], KIND_LABEL[npc.kind]) ..
      (npc.subName and ("  |cffd0d0d0<" .. npc.subName .. ">|r") or "") ..
      (inst and ("  |cff888888in " .. inst.name .. "|r") or ""))
    ShowPortrait(SetPortrait(portrait, npc))
    SetStats(NpcStats(npc))
    Layout(NpcItems(state.npc))
    frame.TitleText:SetText("OKS Forever Tactics: " .. npc.name)
  elseif state.instance then
    local inst = ns.Data.instances[state.instance]
    title:SetText("|cffffd100" .. inst.name .. "|r")
    subtitle:SetText("|cff888888Dungeon|r" .. (inst.forever and "  |cff40ff40new in Forever|r" or ""))
    ShowPortrait(SetPortrait(portrait, nil, "Interface\\Icons\\INV_Misc_Key_13"))
    SetStats(InstanceStats(inst))
    Layout(InstanceItems(state.instance))
    frame.TitleText:SetText("OKS Forever Tactics: " .. inst.name)
  else
    title:SetText("|cffffd100Forever Tactics|r")
    subtitle:SetText("|cff888888Boss and trash abilities, tactics and tricks|r")
    ShowPortrait(SetPortrait(portrait, nil, "Interface\\Icons\\INV_Misc_Book_09"))
    SetStats(nil)
    Layout({
      { text = "Pick a dungeon on the left, or type a mob's name in the search box." },
      { note = "The book button on your target frame opens the page for the mob you target. Inside dungeons the game hides the mob's name from addons, so it opens the dungeon with the likely matches on top." },
    })
    frame.TitleText:SetText("OKS Forever Tactics")
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

-- Options tab ----------------------------------------------------------------

local function Check(parent, label, tip, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb.label = Text(parent, "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(label)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
  if tip then Tip(cb, label, tip) end
  return cb
end

local function BuildOptions()
  local p = CreateFrame("Frame", nil, frame)
  p:SetAllPoints()
  p:Hide()

  local head = Text(p, "GameFontNormalLarge")
  head:SetPoint("TOPLEFT", 24, -40)
  head:SetText("Target button")

  local show = Check(p, "Show the book button on the target frame",
    "Opens the page for the mob you target.",
    function() return not ns.db.button.hidden end,
    function(v) ns.db.button.hidden = not v; if ns.UpdateTargetButton then ns.UpdateTargetButton() end end)
  show:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)

  local lock = Check(p, "Lock its position",
    "When unlocked, hold Shift and drag the button to move it.",
    function() return ns.db.button.locked end,
    function(v) ns.db.button.locked = v end)
  lock:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 0, -4)

  local reset = Button(p, "Reset position", 130, function()
    ns.db.button.x, ns.db.button.y = nil, nil
    if ns.AnchorTargetButton then ns.AnchorTargetButton() end
  end)
  reset:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 4, -8)

  local head2 = Text(p, "GameFontNormalLarge")
  head2:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", -4, -28)
  head2:SetText("Journal")

  local sizeLabel = Text(p, "GameFontHighlight")
  sizeLabel:SetPoint("TOPLEFT", head2, "BOTTOMLEFT", 0, -14)
  sizeLabel:SetText("Text size")
  local buttons = {}
  local function paint()
    local cur = Size().key
    for _, b in ipairs(buttons) do
      if b.key == cur then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
  for i, s in ipairs(SIZES) do
    local b = Button(p, s.label, 80, function()
      ns.db.textSize = s.key
      paint()
    end)
    b.key = s.key
    if i == 1 then b:SetPoint("LEFT", sizeLabel, "RIGHT", 16, 0)
    else b:SetPoint("LEFT", buttons[i - 1], "RIGHT", 6, 0) end
    buttons[i] = b
  end

  local head3 = Text(p, "GameFontNormalLarge")
  head3:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -34)
  head3:SetText("Loot in tooltips")
  local keyLabel = Text(p, "GameFontHighlight")
  keyLabel:SetPoint("TOPLEFT", head3, "BOTTOMLEFT", 0, -14)
  keyLabel:SetText("Show loot while holding")
  local keyButtons = {}
  local function paintKeys()
    local cur = ns.db.lootKey or "ctrl"
    for _, b in ipairs(keyButtons) do
      if b.key == cur then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
  for i, k in ipairs(ns.LOOT_KEYS) do
    local b = Button(p, ns.LOOT_KEY_LABEL[k], 70, function()
      ns.db.lootKey = k
      paintKeys()
    end)
    b.key = k
    if i == 1 then b:SetPoint("LEFT", keyLabel, "RIGHT", 16, 0)
    else b:SetPoint("LEFT", keyButtons[i - 1], "RIGHT", 6, 0) end
    keyButtons[i] = b
  end
  local keyNote = Text(p, "GameFontDisableSmall")
  keyNote:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -12)
  keyNote:SetWidth(600)
  keyNote:SetText("Works on any mob in the open world. In dungeons and in combat the game hides which mob it is, so use the Loot section on its journal page. During a boss fight the book on the target frame shows the boss loot too.")

  p:SetScript("OnShow", function() paint(); paintKeys() end)

  local help = Text(p, "GameFontDisableSmall")
  help:SetPoint("BOTTOMLEFT", 24, 18)
  help:SetText("/ft opens the journal  ·  /ft options opens this tab  ·  /ft help lists all commands")
  return p
end

-- Window ---------------------------------------------------------------------

local function ShowTab(i)
  ns.db.tab = i
  journalPage:SetShown(i == 1)
  optionsPage:SetShown(i == 2)
  if PanelTemplates_SetTab then PanelTemplates_SetTab(frame, i) end
  if i == 1 then
    J.Refresh()
  else
    frame.TitleText:SetText("OKS Forever Tactics: Options")
  end
end

local function Build()
  frame = CreateFrame("Frame", "ForeverTacticsJournal", UIParent, "BasicFrameTemplateWithInset")
  frame:Hide()
  frame:SetSize(W, H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverTacticsJournal") -- close with Escape
  if type(frame.TitleText) ~= "table" then
    frame.TitleText = Text(frame, "GameFontNormal", "CENTER")
    frame.TitleText:SetPoint("TOP", 0, -5)
  end

  journalPage = CreateFrame("Frame", nil, frame)
  journalPage:SetAllPoints()

  -- Left: search box and the dungeon list.
  search = CreateFrame("EditBox", nil, journalPage, "SearchBoxTemplate")
  search:SetSize(LIST_W - 8, 20)
  search:SetPoint("TOPLEFT", 20, -32)
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function(self)
    state.search = strtrim(self:GetText() or "")
    RenderList()
  end)
  Tip(search, "Search", "Type part of a mob's name to find it in every dungeon.")

  local listBg = journalPage:CreateTexture(nil, "BACKGROUND")
  listBg:SetColorTexture(0, 0, 0, 0.25)
  listBg:SetPoint("TOPLEFT", 12, -58)
  listBg:SetPoint("BOTTOMLEFT", 12, 10)
  listBg:SetWidth(LIST_W + 26)

  listScroll = CreateFrame("ScrollFrame", nil, journalPage, "UIPanelScrollFrameTemplate")
  listScroll:SetPoint("TOPLEFT", 14, -60)
  listScroll:SetPoint("BOTTOMLEFT", 14, 12)
  listScroll:SetWidth(LIST_W)
  listChild = CreateFrame("Frame", nil, listScroll)
  listChild:SetSize(LIST_W, 1)
  listScroll:SetScrollChild(listChild)
  rows = {}

  -- Right: header with portrait, name and subtitle.
  local left = 12 + LIST_W + 26 + 14
  header = CreateFrame("Frame", nil, journalPage)
  header:SetPoint("TOPLEFT", left, -32)
  header:SetPoint("TOPRIGHT", -14, -32)
  header:SetHeight(56)
  portrait = header:CreateTexture(nil, "ARTWORK")
  portrait:SetSize(50, 50)
  portrait:SetPoint("LEFT", 4, 0)
  local ring = header:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  ring:SetSize(84, 84)
  header.ring = ring
  title = Text(header, "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -4)
  subtitle = Text(header, "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
  targetLabel = Text(header, "GameFontDisableSmall", "RIGHT")
  targetLabel:SetPoint("TOPRIGHT", -4, -4)

  -- Summary bar like the writ window: label above, value below.
  bar = CreateFrame("Frame", nil, journalPage)
  bar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
  bar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
  bar:SetHeight(BAR_H)
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.45)
  stats = {}
  local boxW = math.floor((W - left - 14) / 7)
  for i = 1, 7 do
    local f = CreateFrame("Frame", nil, bar)
    f:SetPoint("TOPLEFT", (i - 1) * boxW, 0)
    f:SetSize(boxW, BAR_H)
    f.label = Text(f, "GameFontDisableSmall")
    f.label:SetPoint("TOPLEFT", 8, -5)
    f.value = Text(f, "GameFontHighlightMedium")
    f.value:SetPoint("BOTTOMLEFT", 8, 5)
    f.value:SetWidth(boxW - 10)
    f.value:SetWordWrap(false)
    if i > 1 then
      local sep = f:CreateTexture(nil, "ARTWORK")
      sep:SetColorTexture(1, 1, 1, 0.12)
      sep:SetPoint("TOPLEFT", 0, -5)
      sep:SetPoint("BOTTOMLEFT", 0, 5)
      sep:SetWidth(1)
    end
    stats[i] = f
  end

  detailScroll = CreateFrame("ScrollFrame", nil, journalPage, "UIPanelScrollFrameTemplate")
  detailScroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
  detailScroll:SetPoint("BOTTOMRIGHT", -34, 12)
  detailChild = CreateFrame("Frame", nil, detailScroll)
  detailChild:SetSize(DETAIL_W, 1)
  detailScroll:SetScrollChild(detailChild)

  optionsPage = BuildOptions()

  -- Tabs under the window, like the writ window.
  tabs = {}
  for i, label in ipairs({ "Journal", "Options" }) do
    local t = CreateFrame("Button", "ForeverTacticsJournalTab" .. i, frame, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(label)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(t, 0) end
    if i == 1 then t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else t:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0) end
    t:SetScript("OnClick", function() ShowTab(i) end)
    tabs[i] = t
  end
  frame.Tabs = tabs
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #tabs) end
end

function J.Refresh()
  if not frame or not frame:IsShown() or not journalPage:IsShown() then return end
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
  if opts.npc or opts.instance then
    state.search = ""
    search:SetText("")
  end
  ComputeLikely()
  frame:Show()
  ShowTab(1)
end

function J.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    J.Open()
  end
end

function J.ShowOptions()
  if not frame then Build() end
  frame:Show()
  ShowTab(2)
end

ns.Command("options", "Open the options tab.", function() J.ShowOptions() end)

ns.Command("help", "Show this list.", function()
  SlashCmdList.FOREVERTACTICS("?")
end)
