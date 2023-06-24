-- luacheck: globals LibStub CreateFrame UIParent hooksecurefunc
local _, ns = ...
local GetCursorPosition = _G.GetCursorPosition
local GetTime = _G.GetTime
local util = ns.util
local profile

ns.ADDON_NAME = "MouseCrosshair"
ns.ADDON_DB_NAME = "MouseCrosshairDB"

local addon = LibStub("AceAddon-3.0"):NewAddon(ns.ADDON_NAME, "AceEvent-3.0")
ns.addon = addon

addon.version = _G.GetAddOnMetadata(ns.ADDON_NAME, "Version")

function addon:OnInitialize()
  local defaults = self:getDefaults()
  self.db = LibStub("AceDB-3.0"):New(ns.ADDON_DB_NAME, defaults, "Default")
  profile = self.db.profile

  local options = self:getOptions()
  LibStub("AceConfig-3.0"):RegisterOptionsTable(ns.ADDON_NAME, options)

  self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
    ns.ADDON_NAME, ns.ADDON_NAME
  )
end

function addon:getOptions()
  return {
    name = ns.ADDON_NAME,
    type = "group",
    handler = self,
    args = {
      alwaysShow = {
        order = 1,
        name = "Always show",
        desc = util.Deindent([[
          Show even when cursor is hidden. Unchecked, this will instead pulse \
          the crosshair when mouse look ends.
        ]]),
        type = "toggle",
      },

      onlyInCombat = {
        order = 2,
        name = "Only in combat",
        desc = "Only show crosshair in combat.",
        type = "toggle",
      },

      color = {
        order = 3,
        name = "Color",
        type = "color",
        hasAlpha = true,
        get = function (info)
          return util.Unpack(profile[info[#info]])
        end,
        set = function (info, ...)
          profile[info[#info]] = util.Pack(...)
          self:updateParameters()
          self:updateVisibility()
        end,
      },

      thickness = {
        order = 4,
        name = "Thickness",
        type = "range",
        min = 0,
        max = 100,
        step = 1,
      },

      pulseDurationSec = {
        order = 5,
        name = "Pulse duration (sec)",
        type = "range",
        min = 0.1,
        max = 10,
        step = 0.1,
        disabled = function () return profile.alwaysShow end,
      },

      minTimeHiddenSec = {
        order = 6,
        name = "Minimum time hidden (sec)",
        desc = util.Deindent([[
          Minimum time required for the cursor to be hidden before it becomes \
          visible again.

          Use this to prevent flashing when rapidly clicking.
        ]]),

        type = "range",
        min = 0,
        max = 60,
        step = 1,
        disabled = function () return profile.alwaysShow end,
      },
    },

    get = function (info)
      return profile[info[#info]]
    end,

    set = function (info, value)
      profile[info[#info]] = value
      self:updateParameters()
      self:updateVisibility()
    end,
  }
end

function addon:getDefaults()
  return {
    profile = {
      color = util.Pack(1, 1, 1, 0.5),
      initialAlpha = 1,
      alwaysShow = false,
      onlyInCombat = true,
      pulseDurationSec = 1,
      minTimeHiddenSec = 0.333,
      thickness = 2,
    },
  }
end

function addon:OnEnable()
  if self.enabled then return end
  self.enabled = true

  self:createFrames()
  self:updateParameters()
  self:registerEvents()
  self:updateVisibility()
end

function addon:OnDisable()
  if not self.enabled then return end
  self.enabled = false

  self:unregisterEvents()
  self:updateVisibility()
end

function addon:registerEvents()
  self:RegisterEvent("CINEMATIC_START")
  self:RegisterEvent("CINEMATIC_STOP")
  self:RegisterEvent("SCREENSHOT_FAILED")
  self:RegisterEvent("SCREENSHOT_SUCCEEDED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function addon:unregisterEvents()
  self:UnregisterAllEvents()
end

function addon:createFrames()
  if self.center then
    return
  end

  local center = CreateFrame("Frame", nil, UIParent)

  center:SetScript("OnUpdate", function ()
    self:update()
  end)

  center:SetFrameLevel(0)
  center:SetFrameStrata("DIALOG")

  self.center = center
  self.horizontal = center:CreateTexture()
  self.vertical = center:CreateTexture()
end

function addon:update()
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  local offset = math.floor(profile.thickness / 2)

  self.center:SetPoint(
    "BOTTOMLEFT",
    x / scale - offset,
    y / scale - offset
  )

  if not profile.alwaysShow then
    local elapsedSec = GetTime() - (self.showTimeSec or 0)

    if elapsedSec >= profile.pulseDurationSec then
      self.center:Hide()

    else
      self.center:SetAlpha(
        (profile.pulseDurationSec - elapsedSec) / profile.pulseDurationSec
      )
    end
  end
end

function addon:updateParameters()
  local center = self.center
  center:ClearAllPoints()
  center:SetPoint("CENTER")
  center:SetSize(profile.thickness, profile.thickness)

  local horizontal = self.horizontal
  horizontal:ClearAllPoints()
  horizontal:SetWidth(UIParent:GetWidth())
  horizontal:SetHeight(profile.thickness)
  horizontal:SetPoint("LEFT", UIParent)
  horizontal:SetPoint("RIGHT", UIParent)
  horizontal:SetPoint("TOP", center)
  horizontal:SetColorTexture(util.Unpack(profile.color))

  local vertical = self.vertical
  vertical:ClearAllPoints()
  vertical:SetHeight(UIParent:GetHeight())
  vertical:SetWidth(profile.thickness)
  vertical:SetPoint("TOP", UIParent)
  vertical:SetPoint("BOTTOM", UIParent)
  vertical:SetPoint("LEFT", center)
  vertical:SetColorTexture(util.Unpack(profile.color))
end

function addon:updateVisibility(dontStopPulse)
  if not self.center then
    return
  end

  local nowSec = GetTime()

  if dontStopPulse and self:isPulsing(nowSec) then
    return
  end

  local shouldShow =
    self.enabled
    and not self.playingCinematic
    and not self.takingScreenshot
    and not self.playingMovie
    and (profile.alwaysShow or (
      not self.cameraLooking and
      not self.cameraTurning
    ))
    and (not profile.onlyInCombat or self.inCombat)


  if not shouldShow then
    return self:hide(nowSec)
  end

  if not self.center:IsShown() == not shouldShow then
    return
  end

  if profile.alwaysShow then
    return self:show(nowSec)
  end

  local timeHidden = nowSec - (self.hideTimeSec or 0)

  if timeHidden >= profile.minTimeHiddenSec then
    self:show(nowSec)
  end
end

function addon:isPulsing()
  if profile.alwaysShow then
    return false
  end

  return (GetTime() - (self.showTimeSec or 0)) < profile.pulseDurationSec
end

function addon:show(nowSec)
  self.showTimeSec = nowSec
  self.center:SetAlpha(profile.initialAlpha)
  self.center:Show()
end

function addon:hide(nowSec)
  self.hideTimeSec = nowSec
  self.center:Hide()
end

function addon:CINEMATIC_START()
  self.playingCinematic = true
  self:updateVisibility()
end

function addon:CINEMATIC_STOP()
  self.playingCinematic = false
  self:updateVisibility()
end

function addon:SCREENSHOT_FAILED()
  self.takingScreenshot = false
  self:updateVisibility()
end

function addon:SCREENSHOT_SUCCEEDED()
  self.takingScreenshot = false
  self:updateVisibility()
end

function addon:PLAYER_REGEN_DISABLED()
  self.inCombat = true
  -- self:updateVisibility()
end

function addon:PLAYER_REGEN_ENABLED()
  self.inCombat = false
  self:updateVisibility(true)
end

hooksecurefunc("Screenshot", function ()
  addon.takingScreenshot = true
  addon:updateVisibility()
end)

_G.MovieFrame:HookScript("OnShow", function ()
  addon.playingMovie = true
  addon:updateVisibility()
end)

_G.MovieFrame:HookScript("OnHide", function ()
  addon.playingMovie = false
  addon:updateVisibility()
end)

hooksecurefunc("CameraOrSelectOrMoveStart", function ()
  addon.cameraLooking = true
  addon:updateVisibility()
end)

hooksecurefunc("CameraOrSelectOrMoveStop", function ()
  addon.cameraLooking = false
  addon:updateVisibility()
end)

hooksecurefunc("TurnOrActionStart", function ()
  addon.cameraTurning = true
  addon:updateVisibility()
end)

hooksecurefunc("TurnOrActionStop", function ()
  addon.cameraTurning = false
  addon:updateVisibility()
end)
