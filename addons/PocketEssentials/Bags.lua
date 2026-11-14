-- Pocket Essentials: module "bags" (One big bag).
-- Uses Blizzard's own combined bag window (ContainerFrameCombinedBags) and adds
-- a large Sort button, a left-stick-click shortcut and a size choice.
--
-- Taint rules followed here (item use must never be blocked):
--   * No field is ever written onto a Blizzard frame or table.
--   * No Blizzard Lua function is called from this file (only game API and
--     widget methods), so nothing in Blizzard's bag code runs in our name.
--   * Our buttons are children of UIParent, not of the bag: the gamepad
--     "smart navigation" walks the bag's children looking for buttons
--     (Blizzard_GamepadSmartNavigation/Utility.lua) and must not find ours.
--   * The "combinedBags" setting is never changed in the middle of a session.
--     Its change event is synchronous (ContainerDocumentation.lua), so Blizzard's
--     handler would run inside our call and store its result in our name; every
--     later bag opening would then be tainted. It is written at logout/reload
--     instead, and Blizzard reads it cleanly on the way back in.
local ADDON_NAME, PE = ...

local type, pcall, tostring = type, pcall, tostring
local max, abs = math.max, math.abs

local FRAME_NAME = "ContainerFrameCombinedBags"
local LAYOUT_FUNC = "UpdateContainerFrameAnchors"
local CVAR = "combinedBags"
local SORT_KEY = "PADLSTICK" -- left stick click (Blizzard_SharedXML/Shared/GamepadConstants.lua)
local KEY_BUTTON_NAME = "PocketEssentialsBagSortKey"
local SIZE_FACTOR = { normal = 1, large = 1.25, xlarge = 1.5 }
local RELOAD_REASON = "Reload to finish changing the bags."

local mod            -- set by RegisterModule below
local active = false -- true between OnEnable and OnDisable; every hook checks it
local bagFrame       -- ContainerFrameCombinedBags once found
local hooksDone = false
local layoutHooked = false
local metricsHooked = false
local sortButton     -- the big button (child of UIParent, anchored to the bag)
local keyButton      -- hidden named button the left stick click is pointed at
local logoutFrame
local logoutWatching = false
local lastSort = 0
local base           -- { scale, x, y }: what Blizzard's layout pass last set
local applied        -- { scale, x, y }: what we set on top of it, or nil
local baseStale = false -- Blizzard's layout pass ran since we last read its values
local clamped = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- A normal number we may calculate with (not nil, not a hidden "secret" value).
local function Plain(v)
    if type(v) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    if v ~= v then return nil end
    return v
end

local function Near(a, b)
    return a ~= nil and b ~= nil and abs(a - b) < 0.01
end

local function Opts()
    local opts = mod and mod.opts
    if type(opts) == "table" then return opts end
    return nil
end

local function FindFrame()
    local frame = _G[FRAME_NAME]
    if type(frame) ~= "table" then return nil end
    if type(frame.HookScript) ~= "function" or type(frame.IsShown) ~= "function"
        or type(frame.SetScale) ~= "function" or type(frame.GetPoint) ~= "function" then
        return nil
    end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden then return nil end
    end
    return frame
end

local function BagShown()
    -- IsVisible: with the whole UI hidden (a cinematic) the bag does not count as open.
    return bagFrame ~= nil and bagFrame:IsVisible() and true or false
end

-- Blizzard always uses the combined bag in its gamepad style, whatever the
-- setting says (ContainerFrameSettingsManager:IsUsingCombinedBags).
local function IsGamepadStyle()
    if not (C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle) then return false end
    if not (Enum and Enum.InputDeviceInterfaceType) then return false end
    local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
    return ok and style ~= nil and style == Enum.InputDeviceInterfaceType.Gamepad
end

local function ReadCVar()
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, CVAR)
    if not ok or value == nil then return nil end
    return tostring(value)
end

-- True unless the game says plainly that the frame is not protected.
local function IsProtectedNow(frame)
    if type(frame.IsProtected) ~= "function" then return true end
    local ok, protected = pcall(frame.IsProtected, frame)
    if not ok then return true end
    if type(issecretvalue) == "function" then
        local ok2, secret = pcall(issecretvalue, protected)
        if not ok2 or secret then return true end
    end
    return protected and true or false
end

---------------------------------------------------------------------------
-- The "combinedBags" setting: only ever written at logout / reload
---------------------------------------------------------------------------

local function OnLogout()
    local opts = Opts()
    if not opts or opts.cvarWant == nil then return end
    local current = ReadCVar()
    if current == nil then return end
    if current ~= opts.cvarWant and C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, CVAR, opts.cvarWant)
    end
    opts.cvarTried = true
end

local function UpdateLogoutWatch()
    local opts = Opts()
    local want = opts ~= nil and opts.cvarWant ~= nil
    if want == logoutWatching then return end
    if want and not logoutFrame then
        logoutFrame = CreateFrame("Frame")
        logoutFrame:SetScript("OnEvent", mod:Wrap(OnLogout))
    end
    if not logoutFrame then return end
    if want then
        local ok = pcall(logoutFrame.RegisterEvent, logoutFrame, "PLAYER_LOGOUT")
        logoutWatching = ok and true or false
    else
        pcall(logoutFrame.UnregisterEvent, logoutFrame, "PLAYER_LOGOUT")
        logoutWatching = false
    end
end

-- Withdraws our "Reload now" request once nothing is waiting for a reload.
local function CancelReload()
    if mod and mod.CancelReload then mod:CancelReload() end
end

local function ForgetCVar(opts)
    opts.cvarPrev, opts.cvarWant, opts.cvarTried = nil, nil, nil
    CancelReload()
end

-- At login: did the change we left for the last logout take?
local function ResolvePendingCVar()
    local opts = Opts()
    if not opts then return end
    local current = ReadCVar()
    if current == "1" then opts.cvarFailed = nil end
    if opts.cvarWant == nil then
        opts.cvarTried = nil
        return
    end
    if current == opts.cvarWant then
        if opts.cvarPrev == current then opts.cvarPrev = nil end -- put back as found
        opts.cvarWant, opts.cvarTried = nil, nil
    elseif opts.cvarTried or current == nil then
        -- The game did not keep it. Do not ask for reload after reload.
        if opts.cvarWant == "1" then opts.cvarFailed = true end
        ForgetCVar(opts)
    end
    UpdateLogoutWatch()
end

-- Module on. Returns nothing; the panel text comes from Status().
local function WantCombined()
    local opts = Opts()
    if not opts then return end
    if IsGamepadStyle() then
        -- Already one big bag. Only cancel a "switch back" left over from
        -- switching the feature off earlier in this session.
        if opts.cvarWant ~= nil and opts.cvarWant ~= "1" then
            opts.cvarWant, opts.cvarTried = nil, nil
        end
        UpdateLogoutWatch()
        CancelReload() -- nothing visible waits for a reload in this style
        return
    end
    local current = ReadCVar()
    if current == nil then return end
    if current == "1" then
        opts.cvarWant, opts.cvarTried, opts.cvarFailed, opts.userSeparate = nil, nil, nil, nil
        opts.sawCombined = true
        UpdateLogoutWatch()
        CancelReload()
        return
    end
    if opts.cvarFailed then return end
    if opts.cvarWant ~= "1" and (opts.sawCombined or opts.userSeparate) then
        -- It was one big bag while this feature was on and now it is not, and
        -- not by our doing: the owner changed it in Blizzard's bag menu.
        -- Respect that; do not queue the setting again.
        opts.sawCombined, opts.userSeparate = nil, true
        ForgetCVar(opts)
        UpdateLogoutWatch()
        return
    end
    if opts.cvarPrev == nil then opts.cvarPrev = current end
    opts.cvarWant, opts.cvarTried = "1", nil
    UpdateLogoutWatch()
    mod:RequestReload(RELOAD_REASON)
end

-- Module off: put the setting back the way it was found.
local function RestoreCVar()
    local opts = Opts()
    if not opts then return end
    opts.sawCombined, opts.userSeparate = nil, nil
    local prev = opts.cvarPrev
    local current = ReadCVar()
    if prev == nil or current == nil or current == prev or current ~= "1" then
        -- Nothing of ours to undo (never applied, or changed by hand since).
        ForgetCVar(opts)
        UpdateLogoutWatch()
        return
    end
    opts.cvarWant, opts.cvarTried = prev, nil
    UpdateLogoutWatch()
    if IsGamepadStyle() then CancelReload() else mod:RequestReload(RELOAD_REASON) end
end

---------------------------------------------------------------------------
-- Sorting (same as Blizzard's own Clean Up button: a sound, then SortBags)
---------------------------------------------------------------------------

local function DoSort(fromKey)
    if not active or not BagShown() then return end -- also covers a stale key binding
    local now = (GetTime and GetTime()) or 0
    if now - lastSort < 0.5 and now >= lastSort then return end
    if not (C_Container and C_Container.SortBags) then return end
    lastSort = now
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then
        pcall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01)
    end
    C_Container.SortBags()
    if fromKey and sortButton and sortButton.Flash and sortButton:IsVisible() then
        sortButton:Flash()
    end
end

local function OnSortTapped()
    DoSort(false)
end

local function OnSortKey(_, _, down)
    if down then return end
    -- The shoulder "modifier" buttons held: that press belongs to the game.
    if IsModifierKeyDown and IsModifierKeyDown() then return end
    DoSort(true)
end

---------------------------------------------------------------------------
-- The Sort button and the left stick click
---------------------------------------------------------------------------

local function LayoutButton()
    if not sortButton or not bagFrame then return end
    local m = PE.UI:Metrics()
    sortButton:SetSize(max(m.button * 2.4, PE.UI:Px(110)), m.button)
    sortButton:ClearAllPoints()
    -- Sits to the left of the top left corner, outside the window: clear of the
    -- item slots, money, search box and close button, of the controller hints
    -- Blizzard hangs below the window and of the extra bags it stacks from the
    -- bottom left. The gap keeps it off the round picture, which sticks out a
    -- little. Being beside the window, it costs the bag no height.
    sortButton:SetPoint("TOPRIGHT", bagFrame, "TOPLEFT", -m.gap * 1.5, 0)
end

local function SyncButton()
    if not sortButton then return end
    if active and BagShown() then
        LayoutButton()
        sortButton:Show()
    else
        sortButton:Hide()
    end
end

-- Only ever run through PE:RunOutOfCombat (bindings cannot change in combat).
-- The key is never held during a fight: OnCombatStart gives it back.
local function ApplyBinding()
    if not keyButton then return end
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return end
    if active and BagShown() then
        SetOverrideBindingClick(keyButton, true, SORT_KEY, KEY_BUTTON_NAME, "LeftButton")
    else
        ClearOverrideBindings(keyButton)
    end
end

local function SyncBinding()
    PE:RunOutOfCombat("bags:bind", ApplyBinding)
end

-- PLAYER_REGEN_DISABLED: lockdown starts only after this event's handlers, so
-- the left stick click can still be handed back to the game (auto-run) here.
local function OnCombatStart()
    if not keyButton or not ClearOverrideBindings then return end
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(ClearOverrideBindings, keyButton)
end

local function OnCombatEnd()
    SyncBinding()
end

local function CreateButtons()
    if not keyButton then
        keyButton = CreateFrame("Button", KEY_BUTTON_NAME, UIParent)
        keyButton:SetSize(1, 1)
        keyButton:RegisterForClicks("AnyUp")
        keyButton:SetScript("OnClick", mod:Wrap(OnSortKey))
    end
    if not sortButton and PE.UI and PE.UI.CreateButton then
        local btn = PE.UI:CreateButton(UIParent, "Sort")
        btn:Hide()
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(50)
        btn:SetScript("OnClick", mod:Wrap(OnSortTapped))
        sortButton = btn
    end
end

---------------------------------------------------------------------------
-- Bag size. Blizzard's layout pass sets scale and anchor every time; we go
-- after it, keep its bottom right corner where it put it, and grow up/left.
---------------------------------------------------------------------------

local function SetAnchor(frame, rel, scale, x, y)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", x, y)
end

local function ApplyScaleNow(frame)
    if not frame:IsShown() then return end -- Blizzard lays it out again when it opens
    clamped = false

    local current = Plain(frame:GetScale())
    local parent = frame:GetParent()
    if not current or current <= 0 or type(parent) ~= "table" then return end

    local point, rel, relPoint, x, y = frame:GetPoint(1)
    x, y = Plain(x), Plain(y)
    local known = frame:GetNumPoints() == 1 and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT"
        and type(rel) == "table" and x ~= nil and y ~= nil

    -- After Blizzard's layout pass its values are always read afresh. Only for
    -- our own calls (size option, button size) do we check whether what is on
    -- the frame is still what we put there.
    local ours = not baseStale and known and applied ~= nil and base ~= nil
        and Near(current, applied.scale) and Near(x, applied.x) and Near(y, applied.y)
    baseStale = false
    if not ours then
        applied = nil
        if not known then
            -- Not the anchor Blizzard's layout pass sets: leave it alone.
            base = nil
            return
        end
        base = base or {}
        base.scale, base.x, base.y = current, x, y
    end

    local opts = Opts()
    local factor = (opts and SIZE_FACTOR[opts.size]) or 1
    local pw, ph = Plain(parent:GetWidth()), Plain(parent:GetHeight())
    local fw, fh = Plain(frame:GetWidth()), Plain(frame:GetHeight())
    local parentScale = Plain(parent:GetEffectiveScale())
    local uiScale = Plain(UIParent:GetEffectiveScale())
    if not (pw and ph and fw and fh and parentScale and uiScale) then return end
    if fw < 1 or fh < 1 or pw < 100 or ph < 100 or parentScale <= 0 or uiScale <= 0 then return end

    -- Never smaller than Blizzard's own size; at Normal its layout is left alone.
    local want = base.scale * factor
    local target = want
    if factor > 1 then
        local m = PE.UI:Metrics()
        local toParent = uiScale / parentScale -- our sizes are in UIParent units
        local offX = -base.x * base.scale -- Blizzard's gap to the right edge, in parent units
        local offY = base.y * base.scale  -- and to the bottom edge
        local buttonRoom = (max(m.button * 2.4, PE.UI:Px(110)) + m.gap * 2.5) * toParent
        local fitW = (pw - offX - buttonRoom) / fw
        local fitH = (ph - offY - PE.UI:Px(4) * toParent) / fh
        if fitW < target then target = fitW end
        if fitH < target then target = fitH end
        if target < base.scale then target = base.scale end
        clamped = target < want - 0.005
    else
        target = base.scale
    end

    if Near(target, base.scale) then
        if ours then SetAnchor(frame, rel, base.scale, base.x, base.y) end
        applied = nil
    elseif not (ours and Near(target, applied.scale)) then
        local nx, ny = base.x * base.scale / target, base.y * base.scale / target
        SetAnchor(frame, rel, target, nx, ny)
        applied = applied or {}
        applied.scale, applied.x, applied.y = target, nx, ny
    end
end

-- Module off: put back exactly what Blizzard's layout pass had set. (Calling
-- the layout pass ourselves would run Blizzard's code in our name.)
local function RestoreScaleNow(frame)
    clamped = false
    local was, orig = applied, base
    applied, base = nil, nil
    if not was or not orig then return end
    local current = Plain(frame:GetScale())
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if frame:GetNumPoints() == 1 and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT"
        and type(rel) == "table" and Near(current, was.scale)
        and Near(Plain(x), was.x) and Near(Plain(y), was.y) then
        SetAnchor(frame, rel, orig.scale, orig.x, orig.y)
    end
end

local function SyncScale()
    local frame = bagFrame
    if not frame then return end
    if PE:InCombat() and IsProtectedNow(frame) then
        PE:RunOutOfCombat("bags:scale", SyncScale)
        return
    end
    if active then ApplyScaleNow(frame) else RestoreScaleNow(frame) end
end

---------------------------------------------------------------------------
-- Hooks (installed once, no-ops while the module is off)
---------------------------------------------------------------------------

local function OnLayoutPass()
    if not active then return end
    baseStale = true
    SyncScale()
end

local function OnBagShown()
    if not active then return end
    SyncButton()
    SyncBinding()
end

local function OnBagHidden()
    if not active then return end
    SyncButton()
    SyncBinding()
end

local function OnMetricsChanged()
    if not active then return end
    SyncButton()
    SyncScale()
end

local function Setup()
    if not bagFrame then bagFrame = FindFrame() end
    if not bagFrame then return false end
    CreateButtons()
    if not hooksDone then
        hooksDone = true
        bagFrame:HookScript("OnShow", mod:Wrap(OnBagShown))
        bagFrame:HookScript("OnHide", mod:Wrap(OnBagHidden))
    end
    if not layoutHooked and type(hooksecurefunc) == "function" and type(_G[LAYOUT_FUNC]) == "function" then
        layoutHooked = true
        hooksecurefunc(LAYOUT_FUNC, mod:Wrap(OnLayoutPass))
    end
    if not metricsHooked and PE.UI and PE.UI.OnMetricsChanged then
        metricsHooked = true
        PE.UI:OnMetricsChanged(mod:Wrap(OnMetricsChanged))
    end
    return true
end

local function Start()
    WantCombined()
    SyncButton()
    SyncBinding()
    SyncScale()
end

local function OnAddonLoaded(self)
    if bagFrame or not active then return end
    if Setup() then
        self:UnregisterEvent("ADDON_LOADED")
        Start()
        self:RefreshPanel()
    end
end

local function OnStyleChanged(self)
    -- Let Blizzard finish switching between its mouse and gamepad styles first.
    self:After(1, function()
        if not active or not bagFrame then return end
        WantCombined()
        SyncButton()
        SyncBinding()
        SyncScale()
        self:RefreshPanel()
    end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

local function Status(self)
    if not FindFrame() then return "This client has no combined bag." end
    local opts = Opts()
    local gamepad = IsGamepadStyle()
    local current = ReadCVar()
    if not self:IsEnabled() then
        if opts and opts.cvarWant ~= nil and current ~= nil and current ~= opts.cvarWant and not gamepad then
            return "Reload to go back to separate bags."
        end
        return nil
    end
    if not gamepad then
        if current == nil then return "This client has no combined bag." end
        if current ~= "1" then
            if opts and opts.cvarWant == "1" then return "Reload to switch to one big bag." end
            if not (opts and opts.cvarFailed) then
                return "You switched back to separate bags in the game's bag menu."
            end
            local item = type(BAG_COMMAND_CONVERT_TO_COMBINED) == "string" and BAG_COMMAND_CONVERT_TO_COMBINED
                or "Convert to Combined Bag"
            return "Could not switch the bags for you. Open a bag, tap its picture and choose \"" .. item .. "\"."
        end
    end
    local lines = { "Controller: click the left stick to sort while the bag is open." }
    if clamped then lines[#lines + 1] = "The bag is as big as the screen allows." end
    return lines
end

mod = PE:RegisterModule({
    key = "bags",
    label = "One big bag",
    desc = "All your bags in one window, with a big Sort button.",
    order = 30,
    defaults = { size = "normal" },

    options = {
        { key = "size", label = "Bag size",
          choices = {
              { value = "normal", label = "Normal" },
              { value = "large", label = "Large" },
              { value = "xlarge", label = "Extra large" },
          },
          OnChange = function()
              if active then SyncScale() end
          end },
    },

    status = Status,

    OnLoad = function(self)
        local opts = self.opts
        if type(opts) ~= "table" then return end
        if not SIZE_FACTOR[opts.size] then opts.size = "normal" end
        ResolvePendingCVar()
    end,

    OnEnable = function(self)
        active = true
        if Setup() then
            Start()
        else
            -- Blizzard's bag code is not loaded (yet): wait for it, do nothing else.
            self:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
        end
        self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", OnStyleChanged)
        self:RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatStart)
        self:RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
    end,

    -- Also runs as the rollback of a half-finished OnEnable.
    OnDisable = function()
        active = false
        SyncButton()
        SyncBinding()
        SyncScale()
        RestoreCVar()
    end,
})
