-- ForeverTactics: small book button next to the target frame.
--
-- What it can know (tested in game 2026-11-25):
--  * Open world: target GUID is readable, so we know the exact mob (NPC ID).
--  * Inside instances: target identity is always secret. We only know the
--    instance, the target's level and classification, so the button opens the
--    dungeon page with the likely mobs on top.
--  * During a boss fight: ENCOUNTER_START is readable, so the button opens
--    that boss directly.
-- The button only shows and hides our own non-protected frames. It never
-- makes decisions for the player.
local _, ns = ...

local IsSecret = ns.IsSecret
local btn
local current = nil -- { npc = id } or { instance = key, guess = {...} }

local function Readable(v)
  if IsSecret(v) then return nil end
  return v
end

local function Anchor()
  btn:ClearAllPoints()
  local pos = ns.db and ns.db.button
  local x, y = (pos and pos.x) or -6, (pos and pos.y) or -6
  if TargetFrame then
    btn:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", x, y)
  else
    btn:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
end

local function Build()
  btn = CreateFrame("Button", nil, UIParent)
  btn:SetSize(24, 24)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(20)
  btn:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  btn:SetMovable(true)
  btn.ftLootTooltip = true -- redraw the tooltip when the loot key changes
  btn:RegisterForDrag("LeftButton")
  btn:Hide()

  -- Shift+drag moves the button; the offset is saved relative to TargetFrame.
  btn:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not ns.db.button.locked then self:StartMoving() end
  end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if TargetFrame then
      local x = self:GetRight() - TargetFrame:GetRight()
      local y = self:GetTop() - TargetFrame:GetTop()
      ns.db.button.x, ns.db.button.y = x, y
    end
    Anchor()
  end)

  btn:SetScript("OnClick", function()
    if current then ns.Journal.Open(current) end
  end)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("OKS Forever Tactics")
    if current and current.npc then
      GameTooltip:AddLine("Open " .. ns.Data.npcs[current.npc].name, 1, 1, 1)
      if ns.LootKeyDown and ns.LootKeyDown() then ns.AddLootLines(GameTooltip, current.npc) end
    elseif current and current.instance then
      GameTooltip:AddLine("Open " .. ns.Data.instances[current.instance].name, 1, 1, 1)
      GameTooltip:AddLine("The game hides mob names in dungeons, so likely matches are listed first.", 0.7, 0.7, 0.7, true)
    end
    if ns.db.button.locked then
      GameTooltip:AddLine("Locked. Unlock it in /ft options to move it.", 0.5, 0.5, 0.5)
    else
      GameTooltip:AddLine("Hold Shift and drag to move it.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Anchor()
end

local function Update()
  if not btn then return end
  current = nil

  local exists = Readable(UnitExists("target"))
  local isPlayer = Readable(UnitIsPlayer("target"))
  if exists and not isPlayer then
    -- 1. Exact mob from the GUID (open world).
    local npcID = ns.NpcIDFromGUID(UnitGUID("target"))
    if npcID and ns.Data.npcs[npcID] then
      current = { npc = npcID }
    else
      -- 2. Current boss fight.
      local enc = ns.encounter and ns.encounter.npcID
      if enc then
        current = { npc = enc }
      else
        -- 3. Current dungeon, with a best guess.
        local key = ns.CurrentInstanceKey()
        if key then
          current = {
            instance = key,
            guess = {
              level = Readable(UnitLevel("target")),
              classification = Readable(UnitClassification("target")),
              name = UnitName("target"), -- may be secret; only displayed
            },
          }
        end
      end
    end
  end

  btn:SetShown(current ~= nil and not ns.db.button.hidden)
end

ns.UpdateTargetButton = Update
ns.AnchorTargetButton = function() if btn then Anchor() end end

ns.OnEncounterChanged = Update

ns.On("PLAYER_TARGET_CHANGED", Update)
ns.On("PLAYER_ENTERING_WORLD", function()
  if not btn then Build() end
  Update()
end)

ns.Command("button", "reset  Put the target button back in its default spot.", function(arg)
  if (arg or ""):lower() == "reset" then
    ns.db.button.x, ns.db.button.y = nil, nil
    if btn then Anchor() end
    ns.Print("Target button position reset.")
  else
    ns.Print("Use /ft button reset")
  end
end)
