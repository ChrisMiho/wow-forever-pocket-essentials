-- Pocket Essentials: module "bags" (Bag sorter).
-- Uses Blizzard's own combined bag window (ContainerFrameCombinedBags) and adds
-- a large Sort button, a stick-click shortcut (left, right or none: the "Sort
-- key" choice), a size choice and, as choices of their own, a d-pad route onto
-- the Sort button ("D-pad to Sort") and the bag pictures in one row at the top
-- ("Bag icons").
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
--   * Exception (d-pad route): Blizzard's own navigation setters
--     SmartNavigation_AddJumpNavigationOverride /
--     SmartNavigation_ClearJumpNavigationOverridesInDirection are called, out of
--     a fight only, with a frame (never a function) as the target. They store
--     the value through Blizzard's SecureHelper; we still never write a field
--     ourselves. (A function as the target would hand Blizzard's cursor a value
--     made by addon code, which the item actions then read.)
--   * The Sort button carries none of the fields the bag's own code reads from
--     the button under the cursor (buttonContext and the like).
--   * "Bag icons" moves Blizzard's own buttons, with the widget methods
--     ClearAllPoints and SetPoint only. A button's place is not a Lua value, so
--     nothing Blizzard's item code later reads is ours. What we remember about
--     a button is kept in a table of our own.
local ADDON_NAME, PE = ...

local type, pcall, tostring, pairs, next = type, pcall, tostring, pairs, next
local max, abs, floor = math.max, math.abs, math.floor
local sort = table.sort

local FRAME_NAME = "ContainerFrameCombinedBags"
local LAYOUT_FUNC = "UpdateContainerFrameAnchors"
local CVAR = "combinedBags"
local SORT_ATLAS = "bags-button-autosort-up" -- Blizzard's own sort button (ContainerFrame.xml)
-- Stick clicks (Blizzard_SharedXML/Shared/GamepadConstants.lua). "none": no stick is taken.
local SORT_KEYS = { l3 = "PADLSTICK", r3 = "PADRSTICK" }
local SORT_KEY_LABELS = { l3 = "left stick click", r3 = "right stick click" }
local KEY_BUTTON_NAME = "PocketEssentialsBagSortKey"
local SIZE_FACTOR = { normal = 1, large = 1.25, xlarge = 1.5 }
local RELOAD_REASON = "Reload to finish changing the bags."
-- The d-pad route (Blizzard_GamepadSmartNavigation/Utility.lua). Reached by
-- name: the gamepad code is only loaded with the Gamepad UI.
local NAV_ADD = "SmartNavigation_AddJumpNavigationOverride"
local NAV_CLEAR = "SmartNavigation_ClearJumpNavigationOverridesInDirection"
local NAV_DIRS = "SMART_NAV_INPUT_DIRECTION"
local NAV_KEY = "smartNavigationOverride-" -- plus the direction's name; read only, to see whose it is
local CONFIRM_BUTTON_NAME = "PocketEssentialsBagSortConfirm"
-- The frame that holds the bag pictures drawn inside the bag in the controller
-- style, in its list BagButtonArray (Blizzard_MainMenuBarBagButtons/Camelot/
-- MainMenuBarBagButtons.xml). Reached by name; read only.
local BAR_NAME = "GamepadBagBar"
local COLUMNS = 10 -- the combined bag's width in buttons (ContainerFrame.lua, GetColumns)

local mod            -- set by RegisterModule below
local active = false -- true between OnEnable and OnDisable; every hook checks it
local bagFrame       -- ContainerFrameCombinedBags once found
local hooksDone = false
local layoutHooked = false
local metricsHooked = false
local sortButton     -- the big button (child of UIParent, anchored to the bag)
local keyButton      -- hidden named button the chosen stick click is pointed at
local confirmButton  -- hidden; holds the A button and is what A clicks while the cursor is on the tab
local routed = {}    -- [item button] = true: buttons we put a Left jump on
local tabRight       -- the item button the tab's Right jump points at, or nil
local tabFocused = false -- the controller cursor is on the Sort tab
local confirmHeld = false -- A is taken for Sort right now
local bagWatched = false -- BAG_UPDATE_DELAYED is registered (only while the cursor is on the tab)
local navNote        -- what the debug log last said about the route (a line only on change)
local confirmNote    -- and about the A button
local logoutFrame
local logoutWatching = false
local lastSort = 0
local base           -- { scale, x, y }: what Blizzard's layout pass last set
local applied        -- { scale, x, y }: what we set on top of it, or nil
local baseStale = false -- Blizzard's layout pass ran since we last read its values
local clamped = false
-- "Bag icons": [button] = { ox, oy, nx, ny }, the place Blizzard's layout gave
-- the button and the place we gave it. A table of ours; nothing is written on
-- the button.
local placed = setmetatable({}, { __mode = "k" })
local gridPoint, gridRel, gridRelPoint -- the anchor Blizzard's grid uses, read from the buttons
local lastIconLine   -- what the debug log last said about the bag icons (a line only on change)

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

-- Blizzard's list of bag-picture buttons (backpack, bags, key ring), or nil.
local function BagIconList()
    local bar = _G[BAR_NAME]
    local list = type(bar) == "table" and bar.BagButtonArray
    if type(list) ~= "table" then return nil end
    return list
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
        -- Already the combined bag. Only cancel a "switch back" left over from
        -- switching the feature off earlier in this session.
        if opts.cvarWant ~= nil and opts.cvarWant ~= "1" then
            opts.cvarWant, opts.cvarTried = nil, nil
        end
        UpdateLogoutWatch()
        CancelReload() -- nothing visible waits for a reload in this style
        if PE.debugOn then PE:Debug("bags", "combined: Gamepad UI is on, the game always uses one bag") end
        return
    end
    local current = ReadCVar()
    if current == nil then
        if PE.debugOn then PE:Debug("bags", "not combined: the combinedBags setting cannot be read") end
        return
    end
    if current == "1" then
        if PE.debugOn then PE:Debug("bags", "combined: the setting is already on") end
        opts.cvarWant, opts.cvarTried, opts.cvarFailed, opts.userSeparate = nil, nil, nil, nil
        opts.sawCombined = true
        UpdateLogoutWatch()
        CancelReload()
        return
    end
    if opts.cvarFailed then
        if PE.debugOn then PE:Debug("bags", "not combined: the game did not keep the setting last time") end
        return
    end
    if opts.cvarWant ~= "1" and (opts.sawCombined or opts.userSeparate) then
        -- It was the combined bag while this feature was on and now it is not, and
        -- not by our doing: the player changed it in Blizzard's bag menu.
        -- Respect that; do not queue the setting again.
        opts.sawCombined, opts.userSeparate = nil, true
        ForgetCVar(opts)
        UpdateLogoutWatch()
        if PE.debugOn then PE:Debug("bags", "not combined: switched back in the game's bag menu, left alone") end
        return
    end
    if opts.cvarPrev == nil then opts.cvarPrev = current end
    opts.cvarWant, opts.cvarTried = "1", nil
    UpdateLogoutWatch()
    if PE.debugOn then PE:Debug("bags", "not combined yet: setting is " .. current .. ", change waits for a reload") end
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
        if PE.debugOn then PE:Debug("bags", "switched off: no bag setting of ours to put back") end
        return
    end
    opts.cvarWant, opts.cvarTried = prev, nil
    UpdateLogoutWatch()
    if PE.debugOn then PE:Debug("bags", "switched off: setting goes back to " .. prev .. " at the next reload") end
    if IsGamepadStyle() then CancelReload() else mod:RequestReload(RELOAD_REASON) end
end

---------------------------------------------------------------------------
-- Sorting (same as Blizzard's own Clean Up button: a sound, then SortBags)
---------------------------------------------------------------------------

-- fromKey: false (a tap on the tab), true (the stick click) or "pad" (A with
-- the controller cursor on the tab).
local function DoSort(fromKey)
    if PE.debugOn then
        PE:Debug("bags", fromKey == "pad" and "Sort pressed: A on the tab"
            or fromKey and "Sort pressed: stick click" or "Sort pressed: the tab")
    end
    if not active or not BagShown() then -- also covers a stale key binding
        if PE.debugOn then PE:Debug("bags", "Sort ignored: bag not open or feature off") end
        return
    end
    local now = (GetTime and GetTime()) or 0
    if now - lastSort < 0.5 and now >= lastSort then
        if PE.debugOn then PE:Debug("bags", "Sort ignored: pressed again within half a second") end
        return
    end
    if not (C_Container and C_Container.SortBags) then
        if PE.debugOn then PE:Debug("bags", "Sort ignored: no C_Container.SortBags") end
        return
    end
    lastSort = now
    if PE.debugOn then PE:Debug("bags", "sorting") end
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
    if IsModifierKeyDown and IsModifierKeyDown() then
        if PE.debugOn then PE:Debug("bags", "stick click left to the game: a modifier is held") end
        return
    end
    DoSort(true)
end

---------------------------------------------------------------------------
-- The Sort button and the stick click
---------------------------------------------------------------------------

-- The tab's width in UIParent units (also the room the bag size leaves for it).
local function TabWidth()
    return PE.UI:Metrics().button
end

-- How far the round bag picture reaches below the bag's top edge, in the
-- bag's own units (62-tall picture at y +7: SharedUIPanelTemplates.xml), plus
-- a little room.
local PICTURE_DROP = 58

-- One bag unit in UIParent units, or nil if it cannot be read.
local function BagToUI()
    local bagScale = Plain(bagFrame:GetEffectiveScale())
    local uiScale = Plain(UIParent:GetEffectiveScale())
    if not (bagScale and uiScale) or bagScale <= 0 or uiScale <= 0 then return nil end
    return bagScale / uiScale
end

local function LayoutButton()
    if not sortButton or not bagFrame then return end
    local m = PE.UI:Metrics()
    local width = TabWidth()
    local toUI = BagToUI()
    local bagHeight = Plain(bagFrame:GetHeight())
    -- About half the bag's height, never shorter than three and a half
    -- buttons (room for the icon and four letters).
    local height = max(m.button * 3.5, (toUI and bagHeight and bagHeight * toUI or 0) * 0.5)
    -- Starts below the round picture, at any bag size.
    local drop = max(m.button, toUI and PICTURE_DROP * toUI or 0)
    sortButton:SetSize(width, height)
    sortButton:ClearAllPoints()
    -- A tab against the window's left edge, outside it: clear of the item
    -- slots, money, search box and close button, of the controller hints
    -- Blizzard hangs below the window and of the extra bags it stacks from the
    -- bottom left. It starts below the round picture, which sticks out of
    -- the top left corner. Being beside the window, it costs the bag no height.
    -- (Anchored to the bag, the offset is in the tab's own UIParent units.)
    sortButton:SetPoint("TOPRIGHT", bagFrame, "TOPLEFT", 0, -drop)
    -- Icon at the top, the letters stacked in the space below it.
    local icon, letters = sortButton.peSortIcon, sortButton.peSortLetters
    local iconSize = width - m.gap
    if icon then
        icon:SetSize(iconSize, iconSize)
        icon:ClearAllPoints()
        icon:SetPoint("TOP", sortButton, "TOP", 0, -m.gap * 0.5)
    end
    if letters then
        local top = (icon and icon:IsShown()) and (iconSize + m.gap) or m.gap * 0.5
        letters:ClearAllPoints()
        letters:SetPoint("TOPLEFT", sortButton, "TOPLEFT", 0, -top)
        letters:SetPoint("BOTTOMRIGHT", sortButton, "BOTTOMRIGHT", 0, m.gap * 0.5)
    end
end

-- The "Sort button" choice: shown unless the player hid it (they sort with
-- the stick click instead).
local function TabWanted()
    local opts = Opts()
    return not (opts and opts.showTab == false)
end

local function SyncButton()
    if not sortButton then return end
    if active and BagShown() and TabWanted() then
        LayoutButton()
        sortButton:Show()
    else
        sortButton:Hide()
    end
end

-- The "Sort key" choice: "l3", "r3" or "none". Anything else reads as "l3".
local function SortKeyChoice()
    local opts = Opts()
    local value = opts and opts.sortKey
    if value == "none" or SORT_KEYS[value] then return value end
    return "l3"
end

-- Only ever run through PE:RunOutOfCombat (bindings cannot change in combat).
-- The key is never held during a fight: OnCombatStart gives it back.
-- What the debug log last said about the stick: nil (nothing taken), "l3" or
-- "r3" (that stick is taken), "none" (bag open, Button only). A line is only
-- written when this changes, so fights with the bag closed write nothing.
local stickState

local function NoteStick(state)
    if state == stickState then return end
    local was = stickState
    stickState = state
    if not PE.debugOn then return end
    if state == nil then
        if was ~= "none" then PE:Debug("bags", "stick click given back to the game") end
    elseif state == "none" then
        if was then PE:Debug("bags", "stick click given back to the game") end
        PE:Debug("bags", "no stick taken: button only")
    else
        PE:Debug("bags", SORT_KEY_LABELS[state] .. " taken for Sort (bag open)")
    end
end

local function ApplyBinding()
    if not keyButton then return end
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return end
    -- Always hand back whatever was taken before, so a changed choice never
    -- leaves the old stick taken.
    ClearOverrideBindings(keyButton)
    if active and BagShown() then
        local choice = SortKeyChoice()
        if SORT_KEYS[choice] then
            SetOverrideBindingClick(keyButton, true, SORT_KEYS[choice], KEY_BUTTON_NAME, "LeftButton")
            NoteStick(choice)
        else
            NoteStick("none")
        end
    else
        NoteStick(nil)
    end
end

local function SyncBinding()
    PE:RunOutOfCombat("bags:bind", ApplyBinding)
end

---------------------------------------------------------------------------
-- "D-pad to Sort": a Left jump from the bag's first column onto the Sort
-- tab, and the A button while the cursor is on it.
--
-- Blizzard's cursor looks for a "jump override" on the current button before
-- anything else and goes to that frame if it is visible, whether or not the
-- frame belongs to the focused window (SmartNavigation.lua, Navigate). Its
-- own round bag picture is reached the same way (ContainerFrame.lua,
-- ApplySmartNavOverrideForLeftmostButton). The tab stays a child of UIParent.
--
-- A needs help: with the bag focused, A belongs to the bag's own "Select"
-- action, which only fires for buttons carrying the bag's own tag, and one
-- key has one binding. So A is taken with our own override binding while the
-- cursor is on the tab, the way the stick click is taken.
---------------------------------------------------------------------------

local function DpadWanted()
    local opts = Opts()
    return opts ~= nil and opts.dpad == true
end

-- Blizzard's two setters and its table of directions, or nil and why not.
local function NavApi()
    local add, clear, dirs = _G[NAV_ADD], _G[NAV_CLEAR], _G[NAV_DIRS]
    if type(add) ~= "function" or type(clear) ~= "function" or type(dirs) ~= "table"
        or type(dirs.LEFT) ~= "table" or type(dirs.RIGHT) ~= "table"
        or type(dirs.LEFT.dirKey) ~= "string" or type(dirs.RIGHT.dirKey) ~= "string" then
        return nil, "no navigation helpers on this client"
    end
    return add, clear, dirs
end

local function NoteNav(text)
    if text == navNote then return end
    navNote = text
    if text and PE.debugOn then PE:Debug("bags", "d-pad: " .. text) end
end

-- A region's vertical centre on the screen (its own units times its scale), or nil.
local function ScreenY(region)
    if type(region.GetCenter) ~= "function" or type(region.GetEffectiveScale) ~= "function" then return nil end
    local ok, _, y = pcall(region.GetCenter, region)
    local ok2, scale = pcall(region.GetEffectiveScale, region)
    y, scale = ok and Plain(y) or nil, ok2 and Plain(scale) or nil
    if not (y and scale) then return nil end
    return y * scale
end

-- The item buttons that sit in the bag's leftmost column right now, as an
-- array, or nil and why not. Works from where the buttons are on the screen
-- after the bag has been laid out, so it gives the right answer again after
-- any re-flow. The bag pictures in the grid count as part of the grid (a slot
-- with a bag picture to its left is not in the first column) but are never
-- returned: they are not item buttons and keep the game's own navigation.
-- Reads only.
local function FirstColumn()
    local items = bagFrame and bagFrame.Items
    if type(items) ~= "table" then return nil, "bag has no item list" end
    local seen, lefts, least = {}, {}, nil
    for i = 1, #items do
        local button = items[i]
        if type(button) == "table" and type(button.IsVisible) == "function"
            and type(button.GetLeft) == "function" then
            local ok, visible = pcall(button.IsVisible, button)
            if ok and visible then
                local ok2, left = pcall(button.GetLeft, button)
                left = ok2 and Plain(left) or nil
                if left then
                    seen[#seen + 1], lefts[#lefts + 1] = button, left
                    if least == nil or left < least then least = left end
                end
            end
        end
    end
    if #seen == 0 then return nil, "bag has no item list" end
    local icons = BagIconList()
    for i = 1, icons and #icons or 0 do
        local button = icons[i]
        if type(button) == "table" and type(button.IsVisible) == "function"
            and type(button.GetLeft) == "function" then
            local ok, visible = pcall(button.IsVisible, button)
            if ok and visible then
                local ok2, left = pcall(button.GetLeft, button)
                left = ok2 and Plain(left) or nil
                if left and left < least then least = left end
            end
        end
    end
    local out = {}
    for i = 1, #seen do
        if lefts[i] - least <= 0.5 then out[#out + 1] = seen[i] end
    end
    if #out == 0 then return nil, "no slot in the first column" end
    return out
end

-- The single place that sets or clears jump overrides. Only ever run through
-- PE:RunOutOfCombat, and not while the game's combat restriction is on either
-- (that, not lockdown, is what Blizzard's setter asks: SecureHelper.lua).
-- An override is only cleared if it is still ours, and one that is already
-- there and not ours is left alone.
local function ApplyRoute()
    local wanted = active and DpadWanted()
    local hadRoute = next(routed) ~= nil or tabRight ~= nil
    if not wanted and not hadRoute then
        navNote = nil
        return
    end
    local reason
    if wanted and not IsGamepadStyle() then reason = "Gamepad UI off" end
    local add, clear, dirs = NavApi()
    if not add then
        -- Without the setters nothing of ours can be on any button.
        for button in pairs(routed) do routed[button] = nil end
        tabRight = nil
        if wanted then NoteNav("not set up: " .. (reason or clear)) else navNote = nil end
        return
    end
    if PE:CombatRestricted() then
        -- What is already there stays (a jump to a hidden tab does nothing:
        -- the cursor only goes to a visible frame). The next call tries again.
        if wanted and not hadRoute then NoteNav("not set up: waiting for the fight to end") end
        return
    end
    local leftKey, rightKey = NAV_KEY .. dirs.LEFT.dirKey, NAV_KEY .. dirs.RIGHT.dirKey

    local cols
    if wanted and not reason and sortButton and TabWanted() and BagShown() then
        local why
        cols, why = FirstColumn()
        if not cols then reason = why end
    end

    local keep = {}
    if cols then
        for i = 1, #cols do keep[cols[i]] = true end
    end
    for button in pairs(routed) do
        if not keep[button] then
            if button[leftKey] == sortButton then pcall(clear, button, dirs.LEFT) end
            -- Forgotten only once it is really gone (a refused call is tried again).
            if button[leftKey] ~= sortButton then routed[button] = nil end
        end
    end

    if not cols then
        if tabRight then
            pcall(clear, sortButton, dirs.RIGHT)
            if sortButton[rightKey] == nil then tabRight = nil end
        end
        if reason then
            NoteNav("not set up: " .. reason)
        elseif hadRoute then
            NoteNav("route removed")
        else
            navNote = nil
        end
        return
    end

    local count = 0
    local tabY = ScreenY(sortButton)
    local nearest, nearestGap
    for i = 1, #cols do
        local button = cols[i]
        local current = button[leftKey]
        if current == nil then
            pcall(add, button, dirs.LEFT, sortButton)
            routed[button] = true
            count = count + 1
        elseif current == sortButton then
            routed[button] = true
            count = count + 1
        end
        local y = ScreenY(button)
        local gap = (y and tabY) and abs(y - tabY) or nil
        if nearest == nil or (gap and (nearestGap == nil or gap < nearestGap)) then
            nearest, nearestGap = button, gap
        end
    end
    -- Right from the tab goes back into the bag, to the slot level with the tab's middle.
    if nearest ~= tabRight then
        pcall(add, sortButton, dirs.RIGHT, nearest)
        tabRight = nearest
    end
    NoteNav(("route set on %d first-column slots"):format(count))
end

-- Clears the Left jumps that no longer belong and puts them on whatever item
-- buttons are in the bag's first column now (and takes them all away when the
-- choice, the tab or the bag is not there). Call it after anything that moves
-- the bag's buttons. In a fight it waits for the fight to end.
local function RefreshSortJump()
    local wanted = active and DpadWanted()
    if not wanted and next(routed) == nil and tabRight == nil then
        navNote = nil
        return
    end
    if wanted and PE:InCombat() and next(routed) == nil and BagShown() and TabWanted() then
        NoteNav("not set up: waiting for the fight to end")
    end
    PE:RunOutOfCombat("bags:dpad", ApplyRoute)
end

local function ConfirmKey()
    return type(GAMEPAD_FACE_BOTTOM) == "string" and GAMEPAD_FACE_BOTTOM or "PAD1"
end

local function ConfirmWanted()
    return active and DpadWanted() and tabFocused and BagShown()
        and sortButton ~= nil and sortButton:IsVisible() and true or false
end

local function IsTakenNote(text)
    return text ~= nil and text:find("^A taken") ~= nil
end

-- nil: A is the game's. A line is only written when something changed.
local function NoteConfirm(text)
    if text == confirmNote then return end
    local was = confirmNote
    confirmNote = text
    if not PE.debugOn then return end
    if IsTakenNote(was) and not IsTakenNote(text) then PE:Debug("bags", "d-pad: A given back") end
    if text then PE:Debug("bags", "d-pad: " .. text) end
end

-- Only ever run through PE:RunOutOfCombat (bindings cannot change in combat).
-- A is never held during a fight: OnCombatStart gives it back.
local function ApplyConfirm()
    if not confirmButton then return end
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return end
    local want = ConfirmWanted()
    if not want and not confirmHeld then
        NoteConfirm(nil)
        return
    end
    -- Always handed back first, so nothing stale is ever left.
    ClearOverrideBindings(confirmButton)
    confirmHeld = false
    if not want then
        NoteConfirm(nil)
    elseif PE:CombatRestricted() then
        NoteConfirm("A not taken: game restrictions on")
    else
        local key = ConfirmKey()
        SetOverrideBindingClick(confirmButton, true, key, CONFIRM_BUTTON_NAME, "LeftButton")
        confirmHeld = true
        if not IsTakenNote(confirmNote) then
            -- What the game says holds A now (the bag's footer holds it too;
            -- which of the two wins is the game's to decide).
            local holder = "unknown"
            if PE.debugOn and type(GetBindingAction) == "function" then
                local ok, action = pcall(GetBindingAction, key, true)
                if ok then holder = tostring(action) end
            end
            NoteConfirm("A taken for Sort (A is now: " .. holder .. ")")
        end
    end
end

local function SyncConfirm()
    if not confirmHeld and not ConfirmWanted() then
        NoteConfirm(nil)
        return
    end
    if PE:InCombat() and not confirmHeld then NoteConfirm("A not taken: in a fight") end
    PE:RunOutOfCombat("bags:confirm", ApplyConfirm)
end

-- The bag's footer sets its own A binding again on every bag update
-- (ContainerFrame.lua, ContainerFrameCombinedBagsMixin:Update), so ours is
-- set again after each one, but only while the cursor is on the tab.
local function OnBagUpdate()
    if not active then return end
    SyncConfirm()
end

local function WatchBag(want)
    want = want and true or false
    if want == bagWatched then return end
    if want then
        bagWatched = mod:RegisterEvent("BAG_UPDATE_DELAYED", OnBagUpdate) and true or false
    else
        mod:UnregisterEvent("BAG_UPDATE_DELAYED")
        bagWatched = false
    end
end

-- The cursor has left the tab in any way (moved off, bag closed, choice or
-- feature switched off).
local function DropFocus()
    local was = tabFocused
    tabFocused = false
    WatchBag(false)
    if was and PE.debugOn then PE:Debug("bags", "d-pad: left the Sort tab") end
    SyncConfirm()
end

-- Blizzard's cursor calls these two on the button it arrives on and leaves
-- (SmartNavigation.lua, SelectButton), each behind its own taint barrier.
local function OnTabFocused()
    if not active or not DpadWanted() then return end
    tabFocused = true
    if PE.debugOn then PE:Debug("bags", "d-pad: on the Sort tab") end
    WatchBag(true)
    -- One frame later, so it lands after the bag's footer has set its own A
    -- binding again in the same call chain. A one-shot, not a ticker.
    mod:After(0, SyncConfirm)
end

local function OnTabUnfocused()
    DropFocus()
end

local function OnConfirmKey(_, _, down)
    if down then return end
    -- A binding that outlived its moment never sorts by surprise.
    if not tabFocused then
        if PE.debugOn then PE:Debug("bags", "A left alone: the cursor is not on the Sort tab") end
        return
    end
    DoSort("pad")
end

-- PLAYER_REGEN_DISABLED: lockdown starts only after this event's handlers, so
-- the stick click can still be handed back to the game (auto-run) here.
local function OnCombatStart()
    if not keyButton or not ClearOverrideBindings then return end
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(ClearOverrideBindings, keyButton)
    if stickState ~= "none" then NoteStick(nil) end    -- Button only: nothing was taken, nothing to say
    if confirmHeld and confirmButton then
        pcall(ClearOverrideBindings, confirmButton)
        confirmHeld = false
        NoteConfirm(nil)
    end
end

local function OnCombatEnd()
    SyncBinding()
    SyncConfirm()
    RefreshSortJump()
end

local function CreateButtons()
    if not keyButton then
        keyButton = CreateFrame("Button", KEY_BUTTON_NAME, UIParent)
        keyButton:SetSize(1, 1)
        keyButton:RegisterForClicks("AnyUp")
        keyButton:SetScript("OnClick", mod:Wrap(OnSortKey))
    end
    if not confirmButton then
        confirmButton = CreateFrame("Button", CONFIRM_BUTTON_NAME, UIParent)
        confirmButton:SetSize(1, 1)
        confirmButton:RegisterForClicks("AnyUp")
        confirmButton:SetScript("OnClick", mod:Wrap(OnConfirmKey))
    end
    if not sortButton and PE.UI and PE.UI.CreateButton then
        local btn = PE.UI:CreateButton(UIParent, "Sort")
        btn:Hide()
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(50)
        btn:SetStyle("tab")
        -- The label stays "Sort" (it is what the button is called); what is
        -- drawn is Blizzard's sort icon over the letters one per line.
        btn.peText:Hide()
        local m = PE.UI:Metrics()
        local icon = btn:CreateTexture(nil, "OVERLAY")
        -- An unknown atlas raises no error, it just draws nothing: ask first.
        local hasAtlas = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, SORT_ATLAS)
            hasAtlas = ok and type(info) == "table"
        end
        if not (hasAtlas and pcall(icon.SetAtlas, icon, SORT_ATLAS)) then icon:Hide() end
        btn.peSortIcon = icon
        local letters = btn:CreateFontString(nil, "OVERLAY", m.font)
        if not letters:GetFont() and GameFontHighlight then letters:SetFontObject(GameFontHighlight) end
        letters:SetWordWrap(true)
        letters:SetJustifyH("CENTER")
        letters:SetJustifyV("MIDDLE")
        letters:SetTextColor(1, 0.82, 0, 1)
        letters:SetText("S\no\nr\nt")
        btn.peSortLetters = letters
        btn:SetScript("OnClick", mod:Wrap(OnSortTapped))
        -- Called by Blizzard's controller cursor when it arrives and leaves.
        -- No other field its bag code reads from the current button is set
        -- here (see the header).
        btn.OnSmartNavSelect = mod:Wrap(OnTabFocused)
        btn.OnSmartNavDeselect = mod:Wrap(OnTabUnfocused)
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
        local buttonRoom = TabWanted() and (TabWidth() + m.gap) * toParent or 0
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
        if ours then
            SetAnchor(frame, rel, base.scale, base.x, base.y)
            if PE.debugOn then PE:Debug("bags", "size: back to the game's own scale") end
        end
        applied = nil
    elseif not (ours and Near(target, applied.scale)) then
        local nx, ny = base.x * base.scale / target, base.y * base.scale / target
        SetAnchor(frame, rel, target, nx, ny)
        if PE.debugOn then
            PE:Debug("bags", ("size applied: scale %.2f (game's %.2f, wanted %.2f%s)"):format(
                target, base.scale, want, clamped and ", held to the screen" or ""))
        end
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
        if PE.debugOn then PE:Debug("bags", "switched off: the game's own bag scale put back") end
    elseif PE.debugOn then
        PE:Debug("bags", "switched off: bag scale left alone, it is no longer what was set here")
    end
end

local function SyncScale()
    local frame = bagFrame
    if not frame then return end
    if PE:InCombat() and IsProtectedNow(frame) then
        if PE.debugOn then PE:Debug("bags", "size held for after the fight") end
        PE:RunOutOfCombat("bags:scale", SyncScale)
        return
    end
    if active then
        ApplyScaleNow(frame)
        -- The bag's height and scale may have changed: the tab follows.
        SyncButton()
    else
        RestoreScaleNow(frame)
    end
end

---------------------------------------------------------------------------
-- "Bag icons": the bag pictures in one row at the top.
--
-- In the controller style Blizzard puts one button per bag into the same
-- ten-wide grid as the item slots, each at the start of its bag's slots
-- (ContainerFrame.lua, UpdateItemLayout), so they look like items lying in
-- the bag. After each of Blizzard's layout passes the same buttons are given
-- other cells of the same grid: the bag pictures side by side in the top row
-- from the left, the slots below in Blizzard's order. Every offset used is one
-- Blizzard set on some button; none is calculated. Nothing is made, hidden,
-- given another parent or resized, and no item is moved.
--
-- Columns stay filled from the bottom up (Blizzard's d-pad grid lines columns
-- up from the bottom: SmartNavigation.lua, gridHeightCompensate), so a row
-- that is not full is the first row of slots, not the last.
---------------------------------------------------------------------------

local function IconRowWanted()
    local opts = Opts()
    return active and opts ~= nil and opts.iconRow == true
end

local function NoteIcons(text)
    if text == lastIconLine then return end
    lastIconLine = text
    if text and PE.debugOn then PE:Debug("bags", "bag icons: " .. text) end
end

local function ForgetPlaced()
    for button in pairs(placed) do placed[button] = nil end
end

local function NothingToPutBack(announce)
    lastIconLine = nil
    if announce and PE.debugOn then PE:Debug("bags", "bag icons: nothing of ours to put back") end
end

-- Every bag picture and slot that is in the grid now (shown, with exactly one
-- anchor point), as an array of { button, icon, x, y, cx, cy }: x, y is the
-- cell Blizzard's layout gave the button, cx, cy where it is at this moment.
-- Second result: true when the buttons are where we last put them (then x, y
-- come from what we remembered), false when Blizzard has laid them out since.
-- The whole grid is judged together: either every button is where we put it,
-- or none of what we remembered is used. Returns nil and why when the grid is
-- not the one Blizzard's layout makes. Reads only.
local function ReadGrid()
    local icons = BagIconList()
    if not icons then return nil, "no " .. BAR_NAME end
    local items = bagFrame.Items
    if type(items) ~= "table" then return nil, "no item list" end
    local cells, seen = {}, {}
    local point, rel, relPoint
    for pass = 1, 2 do
        local list = pass == 1 and icons or items
        for i = 1, #list do
            local button = list[i]
            if type(button) == "table" and not seen[button] and type(button.IsShown) == "function"
                and type(button.GetNumPoints) == "function" and type(button.GetPoint) == "function"
                and type(button.SetPoint) == "function" and type(button.ClearAllPoints) == "function" then
                seen[button] = true
                local ok, shown = pcall(button.IsShown, button)
                local ok2, count = pcall(button.GetNumPoints, button)
                if ok and shown and ok2 and Plain(count) == 1 then
                    local ok3, p, r, rp, x, y = pcall(button.GetPoint, button, 1)
                    x, y = Plain(x), Plain(y)
                    if not ok3 or type(p) ~= "string" or type(r) ~= "table" or type(rp) ~= "string"
                        or not x or not y then
                        return nil, "a button's place cannot be read"
                    end
                    if point == nil then
                        point, rel, relPoint = p, r, rp
                    elseif p ~= point or r ~= rel or rp ~= relPoint then
                        return nil, "mixed anchors"
                    end
                    cells[#cells + 1] = { button = button, icon = pass == 1, x = x, y = y, cx = x, cy = y }
                end
            end
        end
    end

    local ours = next(placed) ~= nil
    if ours then
        local known = 0
        for _ in pairs(placed) do known = known + 1 end
        ours = known == #cells
    end
    for i = 1, ours and #cells or 0 do
        local cell = cells[i]
        local was = placed[cell.button]
        if not (was and Near(cell.cx, was.nx) and Near(cell.cy, was.ny)) then
            ours = false
            break
        end
    end
    if ours then
        for i = 1, #cells do
            local cell = cells[i]
            local was = placed[cell.button]
            cell.x, cell.y = was.ox, was.oy
        end
    end

    local taken = {}
    for i = 1, #cells do
        local cell = cells[i]
        local key = floor(cell.x * 10 + 0.5) .. ":" .. floor(cell.y * 10 + 0.5)
        if taken[key] then return nil, "two buttons in one place" end
        taken[key] = true
    end
    gridPoint, gridRel, gridRelPoint = point, rel, relPoint
    return cells, ours
end

-- Blizzard's reading order: top row first, each row from the left. (Its grid
-- is anchored at the bottom right, so a higher row has the larger y and a
-- column further left the smaller x.)
local function ReadingOrder(a, b)
    if abs(a.y - b.y) >= 0.01 then return a.y > b.y end
    return a.x < b.x
end

-- The different values in `values`, ascending.
local function Distinct(values)
    sort(values)
    local out = {}
    for i = 1, #values do
        if #out == 0 or not Near(values[i], out[#out]) then out[#out + 1] = values[i] end
    end
    return out
end

-- Which cell each button goes to. `icons` and `slots` are arrays of cells in
-- Blizzard's reading order. Returns an array of { cell, x, y }, or nil and why
-- not. Works on numbers only; every x and y handed back is one of the inputs'.
--   * bag pictures: top row, from the left;
--   * slots: the rows below, in order. If they do not fill whole rows, the
--     short row is their first one, filled from the left;
--   * if the rows below cannot hold them all, the first slots finish the top
--     row at its right end.
local function PlanCells(icons, slots)
    local xs, ys = {}, {}
    for pass = 1, 2 do
        local list = pass == 1 and icons or slots
        for i = 1, #list do
            xs[#xs + 1], ys[#ys + 1] = list[i].x, list[i].y
        end
    end
    xs, ys = Distinct(xs), Distinct(ys)
    if #xs < COLUMNS then return nil, "fewer than ten columns" end
    if #xs > COLUMNS then return nil, "more than ten columns" end
    local rows = #ys
    local topY = ys[rows]
    local h, s = #icons, #slots
    if h > COLUMNS then return nil, "more bag icons than columns" end
    local extra = s - COLUMNS * (rows - 1)
    if extra < 0 then extra = 0 end
    if extra > COLUMNS - h then return nil, "no room in the top row" end

    local out = {}
    for i = 1, h do
        out[#out + 1] = { cell = icons[i], x = xs[i], y = topY }
    end
    local below = s - extra
    local short = below % COLUMNS
    local firstRow = rows - floor((below + COLUMNS - 1) / COLUMNS) + 1 -- counted from the top; the top row is 1
    local shift = short > 0 and (COLUMNS - short) or 0
    for i = 1, s do
        local row, col
        if i <= extra then
            row, col = 1, COLUMNS - extra + i
        else
            local k = i - extra
            if k <= short then
                row, col = firstRow, k
            else
                local index = k - 1 + shift
                row, col = firstRow + floor(index / COLUMNS), index % COLUMNS + 1
            end
        end
        out[#out + 1] = { cell = slots[i], x = xs[col], y = ys[rows - row + 1] }
    end
    return out
end

local function MoveButton(button, x, y)
    button:ClearAllPoints()
    button:SetPoint(gridPoint, gridRel, gridRelPoint, x, y)
end

local SyncIcons -- defined below; the function held for after a fight calls it

local function SyncIconsAfterFight()
    SyncIcons()
    RefreshSortJump() -- the first column may be other buttons now
end

-- The single place that moves the bag's buttons: into the row when the choice
-- is on, back to the places Blizzard gave them when it is not (also when the
-- feature is switched off). `announce`: say so in the debug log when there
-- was nothing to put back.
SyncIcons = function(announce)
    local wanted = IconRowWanted()
    if not wanted and next(placed) == nil then
        NothingToPutBack(announce)
        return
    end
    if not bagFrame or not bagFrame:IsShown() then
        -- Closed: Blizzard lays the bag out afresh every time it opens.
        ForgetPlaced()
        if not wanted then NothingToPutBack(announce) end
        return
    end
    local cells, ours = ReadGrid()
    if not cells then
        ForgetPlaced()
        if wanted then
            NoteIcons("left alone, the grid is not as expected (" .. tostring(ours) .. ")")
        else
            NothingToPutBack(announce)
        end
        return
    end
    if not ours then
        -- Blizzard has laid the buttons out since: what we remembered is void.
        ForgetPlaced()
        if not wanted then
            NothingToPutBack(announce)
            return
        end
    end

    local icons, slots = {}, {}
    for i = 1, #cells do
        local cell = cells[i]
        if cell.icon then icons[#icons + 1] = cell else slots[#slots + 1] = cell end
    end
    if wanted and #icons == 0 then
        NoteIcons("left alone, no bag icons in the grid (not the controller style)")
        return
    end
    if PE:InCombat() then
        for i = 1, #cells do
            if IsProtectedNow(cells[i].button) then
                NoteIcons("held for after the fight")
                PE:RunOutOfCombat("bags:icons", SyncIconsAfterFight)
                return
            end
        end
    end

    if not wanted then
        for i = 1, #cells do
            local cell = cells[i]
            if not (Near(cell.cx, cell.x) and Near(cell.cy, cell.y)) then
                MoveButton(cell.button, cell.x, cell.y)
            end
        end
        ForgetPlaced()
        lastIconLine = nil
        if PE.debugOn then PE:Debug("bags", "bag icons: the game's own places put back") end
        return
    end

    sort(icons, ReadingOrder)
    sort(slots, ReadingOrder)
    local plan, why = PlanCells(icons, slots)
    if not plan then
        NoteIcons("left alone, the grid is not as expected (" .. tostring(why) .. ")")
        return
    end
    for i = 1, #plan do
        local move = plan[i]
        local cell = move.cell
        if not (Near(cell.cx, move.x) and Near(cell.cy, move.y)) then
            MoveButton(cell.button, move.x, move.y)
        end
        local was = placed[cell.button]
        if not was then
            was = {}
            placed[cell.button] = was
        end
        was.ox, was.oy, was.nx, was.ny = cell.x, cell.y, move.x, move.y
    end
    NoteIcons(("%d icons in the top row, %d slots below"):format(#icons, #slots))
end

---------------------------------------------------------------------------
-- Hooks (installed once, no-ops while the module is off)
---------------------------------------------------------------------------

local function OnLayoutPass()
    if not active then return end
    baseStale = true
    SyncIcons()       -- first: Blizzard has just laid the buttons out
    SyncScale()
    RefreshSortJump() -- the item buttons may have moved (by Blizzard, or by us just now)
end

local function OnBagShown()
    if not active then return end
    SyncButton()
    SyncBinding()
    RefreshSortJump()
end

local function OnBagHidden()
    if not active then return end
    SyncButton()
    SyncBinding()
    DropFocus()
    RefreshSortJump()
end

local function OnMetricsChanged()
    if not active then return end
    SyncButton()
    SyncScale()
    RefreshSortJump() -- the tab changed size: Right from it may now belong to another slot
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
    SyncIcons()
    SyncScale()
    RefreshSortJump()
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
        SyncIcons()
        SyncScale()
        SyncConfirm()
        RefreshSortJump()
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
            if opts and opts.cvarWant == "1" then return "Reload to switch to the combined bag." end
            if not (opts and opts.cvarFailed) then
                return "You switched back to separate bags in the game's bag menu."
            end
            local item = type(BAG_COMMAND_CONVERT_TO_COMBINED) == "string" and BAG_COMMAND_CONVERT_TO_COMBINED
                or "Convert to Combined Bag"
            return "Could not switch the bags for you. Open a bag, tap its picture and choose \"" .. item .. "\"."
        end
    end
    local lines = {}
    local choice = SortKeyChoice()
    if SORT_KEYS[choice] then
        lines[1] = "Controller: click the " .. (choice == "l3" and "left" or "right") .. " stick to sort while the bag is open."
    else
        lines[1] = "Sort with the Sort button; no stick is taken."
    end
    if opts and opts.showTab == false then
        lines[#lines + 1] = "The Sort button is hidden; show it again here if you need it."
    end
    if DpadWanted() and gamepad then
        if NavApi() then
            lines[#lines + 1] = "D-pad: press Left from the first column to reach Sort, then A."
        else
            lines[#lines + 1] = "This client has no way to reach Sort with the d-pad."
        end
    end
    if opts and opts.iconRow == true then
        lines[#lines + 1] = gamepad and "Bag icons are in one row at the top of the bag."
            or "Bag icons: only in the controller style."
    end
    if clamped then lines[#lines + 1] = "The bag is as big as the screen allows." end
    return lines
end

mod = PE:RegisterModule({
    key = "bags",
    label = "Bag sorter",
    desc = "Sort your bags with a big button or a stick click.",
    order = 30,
    defaults = { size = "normal", showTab = true, sortKey = "l3", dpad = false, iconRow = false },

    options = {
        { key = "size", label = "Bag size",
          choices = {
              { value = "normal", label = "Normal" },
              { value = "large", label = "Large" },
              { value = "xlarge", label = "Extra large" },
          },
          OnChange = function()
              if PE.debugOn then
                  local opts = Opts()
                  PE:Debug("bags", "size choice: " .. tostring(opts and opts.size))
              end
              if active then SyncScale() end
          end },
        { key = "sortKey", label = "Sort key",
          choices = {
              { value = "l3", label = "Left stick click" },
              { value = "r3", label = "Right stick click" },
              { value = "none", label = "Button only" },
          },
          -- Hands the old stick back before the new one is taken (ApplyBinding).
          OnChange = function()
              if PE.debugOn then PE:Debug("bags", "sort key choice: " .. SortKeyChoice()) end
              if active then SyncBinding() end
          end },
        { key = "showTab", label = "Sort button",
          choices = {
              { value = true, label = "Show" },
              { value = false, label = "Hide" },
          },
          -- The bag may now grow into the tab's space, or make room for it.
          OnChange = function()
              if PE.debugOn then PE:Debug("bags", TabWanted() and "Sort tab choice: show" or "Sort tab choice: hide") end
              if active then
                  SyncScale()
                  SyncConfirm()
                  RefreshSortJump()
              end
          end },
        -- Its own choice, off until it has passed a device test: it is the one
        -- part of this feature that has a value stored on Blizzard's item
        -- buttons (by Blizzard's own setter).
        { key = "dpad", label = "D-pad to Sort",
          choices = {
              { value = false, label = "Off" },
              { value = true, label = "On" },
          },
          OnChange = function()
              if PE.debugOn then PE:Debug("bags", DpadWanted() and "d-pad choice: on" or "d-pad choice: off") end
              if not DpadWanted() then DropFocus() end
              SyncConfirm()
              RefreshSortJump()
          end },
        -- Its own choice, off until it has passed a device test: it moves the
        -- bag's own buttons (their places only).
        { key = "iconRow", label = "Bag icons",
          choices = {
              { value = false, label = "In the grid" },
              { value = true, label = "One row at the top" },
          },
          OnChange = function()
              local opts = Opts()
              local row = opts ~= nil and opts.iconRow == true
              if PE.debugOn then PE:Debug("bags", row and "bag icons choice: row" or "bag icons choice: grid") end
              lastIconLine = nil
              if active then
                  SyncIcons(true)
                  RefreshSortJump() -- the first column may be other buttons now
              end
          end },
    },

    status = Status,

    OnLoad = function(self)
        local opts = self.opts
        if type(opts) ~= "table" then return end
        if not SIZE_FACTOR[opts.size] then opts.size = "normal" end
        if type(opts.showTab) ~= "boolean" then opts.showTab = true end
        if opts.sortKey ~= "none" and not SORT_KEYS[opts.sortKey] then opts.sortKey = "l3" end
        if type(opts.dpad) ~= "boolean" then opts.dpad = false end
        if type(opts.iconRow) ~= "boolean" then opts.iconRow = false end
        ResolvePendingCVar()
    end,

    OnEnable = function(self)
        active = true
        if Setup() then
            Start()
        else
            -- Blizzard's bag code is not loaded (yet): wait for it, do nothing else.
            if PE.debugOn then PE:Debug("bags", "combined bag window not found yet: waiting for it to load") end
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
        -- The bag's buttons go back to the game's own places (with the bag open;
        -- closed, the game lays them out afresh at the next opening).
        local opts = Opts()
        SyncIcons(opts ~= nil and opts.iconRow == true)
        SyncScale()
        -- A goes back now; the jumps come off now, or after the fight (until
        -- then they point at a hidden tab, which the cursor never goes to).
        DropFocus()
        RefreshSortJump()
        RestoreCVar()
    end,
})
