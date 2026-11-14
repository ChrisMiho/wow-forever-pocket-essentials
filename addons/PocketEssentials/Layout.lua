-- Pocket Essentials: Layout helper (module "layout", experimental).
--
-- What it does: switches between ready-made Edit Mode layouts with one tap.
--   A. "Use Blizzard's Gamepad layout" and "Go back to my previous layout".
--   C. "Install the handheld layout" (a layout shipped inside this file; none
--      is shipped yet, see BUNDLED_LAYOUT below).
--
-- What it deliberately does NOT do: nudge or resize frames inside Edit Mode
-- (item B of the brief). Blizzard's arrow-key nudge runs
--   EditModeSystemSettingsDialog:OnKeyDown -> systemFrame:OnKeyDown ->
--   ProcessMovementKey -> BreakFrameSnap -> EditModeManagerFrame:OnSystemPositionChange
-- (Blizzard_EditMode/Shared/EditModeDialogs.lua:511, EditModeSystemTemplates.lua:49-78,
-- 737-764, EditModeManager.lua:316-386). Those functions write fields on the
-- action bars and unit frames and on the manager's layout tables. Called
-- from an addon button, every one of those writes is tainted, and Blizzard's
-- own code reads them back later (also in combat) -> "action blocked". There
-- is no way for an addon to press a key, and this client's Gamepad UI has no
-- controller nudging in Edit Mode (GamepadHudModeMixin:ToggleEditMode is an
-- empty stub, Blizzard_Gamepad/UI/HUDMode/GamepadHudMode.lua:322). So no
-- helper frame, and no hooks on Edit Mode at all.
--
-- How A and C change the layout: data only, the way Blizzard's own code and
-- LibEditModeOverride do it. C_EditMode.SetActiveLayout(index) /
-- C_EditMode.SaveLayouts(info) hand the data to the game, the game sends
-- EDIT_MODE_LAYOUTS_UPDATED, and Blizzard's manager places its own frames.
-- We never call a method that changes EditModeManagerFrame and never write a
-- field on a Blizzard frame or table.
--
-- Taint caveat (why every change ends with "Reload now"): the game sends
-- that event from inside our call (EditModeManager.lua:1551-1557 reads the
-- new layout on the line after SetActiveLayout), so Blizzard's handler may
-- run with our taint and store tainted values on its frames. Out of combat
-- nothing is blocked at that moment, but the values would stay until the
-- interface is reloaded. The chosen layout is stored by the game itself, so
-- one reload gives the same layout applied by Blizzard code alone.
--
-- Index arithmetic: the game numbers layouts presets first, then saved
-- layouts. C_EditMode.GetLayouts() returns only the saved ones, but its
-- activeLayout counts the presets (EditModeManager.lua:1010-1020, 1527-1532).
-- A preset's index is its Enum.EditModePresetLayouts value + 1
-- (Blizzard_Gamepad/Core.lua:105-106 does exactly that for Modern).
local ADDON_NAME, PE = ...

local type, tostring, ipairs, pcall = type, tostring, ipairs, pcall
local tinsert = table.insert

---------------------------------------------------------------------------
-- The bundled handheld layout
---------------------------------------------------------------------------

-- No layout is bundled yet. To add one, the owner first arranges the screen
-- on the device in Edit Mode, saves it as a layout, then uses Edit Mode's own
-- Layout box > Share > Copy To Clipboard (EditModeManager.lua:1461-1465) and
-- sends that text to whoever maintains this addon. Paste the whole string
-- between the quotes, e.g.  local BUNDLED_LAYOUT = "1 39 0 0 0 ..."
local BUNDLED_LAYOUT = nil

-- Only used when the game cannot tell from the string itself which interface
-- style the layout was made for. Set to "gamepad" if it was exported while
-- "Enable Gamepad UI" was on, "mouse" if it was off, or leave nil.
local BUNDLED_LAYOUT_STYLE = nil

local HANDHELD_NAME = "Handheld"  -- the saved layout's name in Edit Mode
local NO_HANDHELD = "No handheld layout saved yet"
local CONFIRM_SECONDS = 20
local COMBAT_KEY = "layout:apply" -- one pending change at most
local RELOAD_REASON = "Reload to finish changing the screen layout."

local mod
local note               -- last result, shown in the status text
local confirmUntil = 0   -- a second tap before this time replaces "Handheld"
local presetCache        -- { { name =, id =, style = }, ... } once read

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Plain(text)
    -- for chat and panel text: a "|" would start a colour code
    return (tostring(text):gsub("|", "||"))
end

local function HasBundled()
    return type(BUNDLED_LAYOUT) == "string" and Trim(BUNDLED_LAYOUT) ~= ""
end

local function Say(text)
    note = text
    if mod then mod:Print(text) end
end

local function Now()
    if type(GetTime) == "function" then
        local ok, t = pcall(GetTime)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

local function Api()
    local api = C_EditMode
    if type(api) == "table" and type(api.GetLayouts) == "function" and type(api.SetActiveLayout) == "function" then
        return api
    end
    return nil
end

local function LayoutTypes()
    local types = type(Enum) == "table" and Enum.EditModeLayoutType
    if type(types) == "table" and types.Preset ~= nil and types.Account ~= nil and types.Character ~= nil then
        return types
    end
    return nil
end

local function Styles()
    local styles = type(Enum) == "table" and Enum.InputDeviceInterfaceType
    if type(styles) == "table" and styles.Mkb ~= nil and styles.Gamepad ~= nil then return styles end
    return nil
end

-- The interface style in use now (Enum.InputDeviceInterfaceType), or nil if
-- this client cannot say.
local function CurrentStyle()
    local api = C_InputInterfaceStyle
    if type(api) ~= "table" or type(api.GetCurrentStyle) ~= "function" then return nil end
    local ok, style = pcall(api.GetCurrentStyle)
    if ok and style ~= nil then return style end
    return nil
end

-- Does this client have the "Enable Gamepad UI" setting at all?
-- (InputUtil.IsGamepadUISupported: the CVar exists.)
local function GamepadUISupported()
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return false end
    local ok, value = pcall(C_CVar.GetCVar, "InputDeviceInterfaceStyle")
    return ok and value ~= nil
end

-- A layout without a style counts as mouse and keyboard, as in Blizzard's
-- own layout list (EditModeManager.lua:886-891, 1386-1387).
local function StyleFits(layoutStyle)
    local styles, current = Styles(), CurrentStyle()
    if not styles or current == nil then return layoutStyle == nil end
    if layoutStyle == nil then layoutStyle = styles.Mkb end
    return layoutStyle == current
end

local function IsGamepadStyle(layoutStyle)
    local styles = Styles()
    return styles ~= nil and layoutStyle == styles.Gamepad
end

local function GamepadSettingName()
    local label = type(ENABLE_GAMEPAD_UI) == "string" and ENABLE_GAMEPAD_UI ~= "" and ENABLE_GAMEPAD_UI or "Enable Gamepad UI"
    local section = type(GAMEPAD_LABEL) == "string" and GAMEPAD_LABEL ~= "" and GAMEPAD_LABEL or "Gamepad"
    return Plain(label), Plain(section)
end

-- Plain-language reason a layout of that style cannot be used right now.
local function StyleReason(layoutStyle)
    if not Styles() or CurrentStyle() == nil then
        return "The game could not say which control style is in use, so the layout was not changed."
    end
    local label, section = GamepadSettingName()
    if IsGamepadStyle(layoutStyle) then
        if not GamepadUISupported() then return "This game version has no Gamepad UI, so that layout cannot be used." end
        return "Turn on \"" .. label .. "\" in the game's options (" .. section .. ") first, then tap this again."
    end
    return "That layout is for mouse and keyboard. Turn off \"" .. label .. "\" in the game's options (" .. section .. ") first."
end

local function EditModeOpen()
    local manager = EditModeManagerFrame
    if type(manager) ~= "table" then return false end
    if type(manager.IsShown) == "function" then
        local ok, shown = pcall(manager.IsShown, manager)
        if ok and shown then return true end
    end
    if type(manager.IsEditModeActive) == "function" then
        local ok, active = pcall(manager.IsEditModeActive, manager)
        if ok and active then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Reading the game's layouts (read only)
---------------------------------------------------------------------------

local function CopyOfPresets()
    local manager = EditModePresetLayoutManager
    if type(manager) ~= "table" or type(manager.GetCopyOfPresetLayouts) ~= "function" then return nil end
    local ok, list = pcall(manager.GetCopyOfPresetLayouts, manager)
    if ok and type(list) == "table" then return list end
    return nil
end

-- A short description of each built-in layout, in the game's order. nil if
-- the list cannot be trusted (then nothing is ever switched).
local function Presets()
    if presetCache then return presetCache end
    local types = LayoutTypes()
    local list = types and CopyOfPresets()
    if not list then return nil end
    local out = {}
    for i = 1, #list do
        local preset = list[i]
        if type(preset) ~= "table" or preset.layoutType ~= types.Preset then return nil end
        out[i] = { name = preset.layoutName, id = preset.layoutIndex, style = preset.interfaceStyle }
    end
    -- The game counts its presets with this number (EditModeManager.lua:1580).
    local meta = Enum.EditModePresetLayoutsMeta
    if type(meta) == "table" and type(meta.NumValues) == "number" and meta.NumValues ~= #out then return nil end
    presetCache = out
    return out
end

-- state = { api, info (the game's table: saved layouts + activeLayout),
--           presets, saved, numPresets, active (index), current (summary or nil) }
local function ReadState()
    local api = Api()
    local presets = api and Presets()
    if not presets then return nil end
    local ok, info = pcall(api.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" or type(info.activeLayout) ~= "number" then
        return nil
    end
    local state = {
        api = api, info = info, presets = presets, saved = info.layouts,
        numPresets = #presets, active = info.activeLayout,
    }
    local active = state.active
    if active >= 1 and active <= #presets then
        local preset = presets[active]
        state.current = { name = preset.name, preset = preset.id, style = preset.style, isPreset = true }
    else
        local layout = info.layouts[active - #presets]
        if type(layout) == "table" then
            state.current = { name = layout.layoutName, layoutType = layout.layoutType, style = layout.interfaceStyle }
        end
    end
    return state
end

-- Blizzard's Gamepad preset by its real identifier. Returns index, preset.
local function FindGamepadPreset(presets)
    local ids = type(Enum) == "table" and Enum.EditModePresetLayouts
    local want = type(ids) == "table" and ids.Gamepad
    if type(want) ~= "number" then return nil end
    for i, preset in ipairs(presets) do
        if preset.id == want then
            -- The list position and Blizzard's own "enum value + 1" must agree.
            if i ~= want + 1 then return nil end
            return i, preset
        end
    end
    return nil
end

local function FindPresetById(presets, id)
    if type(id) ~= "number" then return nil end
    for i, preset in ipairs(presets) do
        if preset.id == id then
            if i ~= id + 1 then return nil end
            return i, preset
        end
    end
    return nil
end

-- A saved (not built-in) layout by name. Returns its index in the game's
-- numbering and the layout table.
local function FindSaved(state, name, layoutType)
    if type(name) ~= "string" then return nil end
    for i, layout in ipairs(state.saved) do
        if type(layout) == "table" and layout.layoutName == name
            and (layoutType == nil or layout.layoutType == layoutType) then
            return state.numPresets + i, layout
        end
    end
    return nil
end

local function LayoutLabel(current)
    if not current or type(current.name) ~= "string" or current.name == "" then return "an unnamed layout" end
    if current.isPreset then return "Blizzard's " .. Plain(current.name) .. " layout" end
    return "\"" .. Plain(current.name) .. "\""
end

---------------------------------------------------------------------------
-- Changing the layout (out of combat, Edit Mode closed)
---------------------------------------------------------------------------

-- Returns true if the game now reports `index` as the layout in use.
local function Activate(state, index)
    local ok, err = pcall(state.api.SetActiveLayout, index)
    if not ok then
        PE:LogError("layout", "C_EditMode.SetActiveLayout failed: " .. tostring(err))
        return false
    end
    local after = ReadState()
    return after ~= nil and after.active == index
end

local function Finish(text)
    Say(text .. " Tap \"Reload now\" in Pocket Essentials to finish.")
    mod:RequestReload(RELOAD_REASON)
end

local function RememberPrevious(current)
    if type(mod.opts) ~= "table" or not current then return end
    mod.opts.prev = {
        name = current.name,
        layoutType = current.layoutType,
        preset = current.preset,
    }
end

local function DoGamepad(state)
    local index, preset = FindGamepadPreset(state.presets)
    if not index then
        Say("This game version has no Blizzard Gamepad layout.")
        return
    end
    if state.active == index then
        Say("Blizzard's Gamepad layout is already in use.")
        return
    end
    if not StyleFits(preset.style) then
        Say(StyleReason(preset.style))
        return
    end
    local before = state.current
    if Activate(state, index) then
        RememberPrevious(before)
        Finish("Now using Blizzard's Gamepad layout.")
    else
        Say("The game did not switch the layout. Nothing else was changed.")
    end
end

local function DoBack(state)
    local prev = type(mod.opts) == "table" and mod.opts.prev
    if type(prev) ~= "table" then
        Say("There is no earlier layout to go back to.")
        return
    end
    local index, style, label
    if prev.preset ~= nil then
        local preset
        index, preset = FindPresetById(state.presets, prev.preset)
        if index then
            style = preset.style
            label = LayoutLabel({ name = preset.name, isPreset = true })
        end
    else
        local layout
        index, layout = FindSaved(state, prev.name, prev.layoutType)
        if index then
            style = layout.interfaceStyle
            label = LayoutLabel({ name = layout.layoutName })
        end
    end
    if not index then
        mod.opts.prev = nil
        Say("Your earlier layout no longer exists, so there is nothing to go back to.")
        return
    end
    if state.active == index then
        mod.opts.prev = nil
        Say("You are already using " .. label .. ".")
        return
    end
    if not StyleFits(style) then
        Say(StyleReason(style))
        return
    end
    if Activate(state, index) then
        mod.opts.prev = nil
        Finish("Back to " .. label .. ".")
    else
        Say("The game did not switch the layout. Nothing else was changed.")
    end
end

-- Mirrors the data steps of Blizzard's own import
-- (EditModeManagerFrameMixin:ImportLayout -> MakeNewLayout,
-- EditModeManager.lua:1567-1589, 1642-1645) without touching the manager:
-- convert the string, name it, give it the Account type, put it after the
-- last Account layout, save, make it the layout in use.
local function DoInstall(state)
    if not HasBundled() then
        Say(NO_HANDHELD .. ".")
        return
    end
    local api, types = state.api, LayoutTypes()
    if not types or type(api.ConvertStringToLayoutInfo) ~= "function" or type(api.SaveLayouts) ~= "function" then
        Say("This game version cannot install a layout from an addon.")
        return
    end

    local ok, layout = pcall(api.ConvertStringToLayoutInfo, Trim(BUNDLED_LAYOUT))
    if not ok or type(layout) ~= "table" or type(layout.systems) ~= "table" or type(layout.systems[1]) ~= "table" then
        PE:LogError("layout", "The bundled layout string was not accepted by C_EditMode.ConvertStringToLayoutInfo.")
        Say("The built-in handheld layout could not be read by the game. Nothing was changed.")
        return
    end
    if type(api.IsValidLayoutName) == "function" then
        local okName, valid = pcall(api.IsValidLayoutName, HANDHELD_NAME)
        if okName and valid == false then
            Say("The game does not allow a layout called " .. HANDHELD_NAME .. ". Nothing was changed.")
            return
        end
    end

    local styles = Styles()
    if layout.interfaceStyle == nil and styles then
        if BUNDLED_LAYOUT_STYLE == "gamepad" then
            layout.interfaceStyle = styles.Gamepad
        elseif BUNDLED_LAYOUT_STYLE == "mouse" then
            layout.interfaceStyle = styles.Mkb
        end
    end
    if not StyleFits(layout.interfaceStyle) then
        Say(StyleReason(layout.interfaceStyle))
        return
    end

    -- The full list as the game numbers it: built-in layouts, then saved ones
    -- (what Blizzard's own Save hands to C_EditMode.SaveLayouts).
    local all = CopyOfPresets()
    if not all or #all ~= state.numPresets then
        Say("The game's layout list could not be read. Nothing was changed.")
        return
    end
    local lastAccount, accountCount = nil, 0
    for i, saved in ipairs(state.saved) do
        if type(saved) ~= "table" then
            Say("The game's layout list could not be read. Nothing was changed.")
            return
        end
        all[state.numPresets + i] = saved
        if saved.layoutType == types.Account then
            accountCount = accountCount + 1
            lastAccount = state.numPresets + i
        end
    end

    local newIndex
    local existingIndex, existing = FindSaved(state, HANDHELD_NAME)
    if existingIndex then
        -- Replacing throws away the owner's own changes: ask for a second tap.
        local now = Now()
        if confirmUntil <= 0 or now > confirmUntil then
            confirmUntil = now + CONFIRM_SECONDS
            Say("You already have a layout called " .. HANDHELD_NAME .. ". Tap again within "
                .. CONFIRM_SECONDS .. " seconds to replace it with the built-in one.")
            return
        end
        layout.layoutType = existing.layoutType
        layout.layoutName = HANDHELD_NAME
        all[existingIndex] = layout
        newIndex = existingIndex
    else
        local consts = type(Constants) == "table" and Constants.EditModeConsts
        local maxLayouts = type(consts) == "table" and consts.EditModeMaxLayoutsPerType
        if type(maxLayouts) ~= "number" then maxLayouts = 5 end
        if accountCount >= maxLayouts then
            Say("You already have " .. maxLayouts .. " saved layouts. Delete one in Edit Mode first, then tap this again.")
            return
        end
        layout.layoutType = types.Account
        layout.layoutName = HANDHELD_NAME
        newIndex = lastAccount and (lastAccount + 1) or (state.numPresets + 1)
        tinsert(all, newIndex, layout)
    end
    confirmUntil = 0

    local before = state.current
    local switching = not (existingIndex and state.active == existingIndex)
    local info = state.info
    info.layouts = all
    info.activeLayout = newIndex
    local savedOk, err = pcall(api.SaveLayouts, info)
    if not savedOk then
        PE:LogError("layout", "C_EditMode.SaveLayouts failed: " .. tostring(err))
        Say("The game refused to save the handheld layout.")
        return
    end
    pcall(api.SetActiveLayout, newIndex)

    local after = ReadState()
    local savedIndex = after and FindSaved(after, HANDHELD_NAME)
    if not savedIndex then
        Say("The game did not keep the handheld layout. Nothing else was changed.")
    elseif after.active ~= savedIndex then
        Finish("The handheld layout was saved as " .. HANDHELD_NAME .. ", but the game did not switch to it. Pick it in Edit Mode.")
    else
        if switching then RememberPrevious(before) end
        Finish("The handheld layout is installed and in use.")
    end
end

local ACTIONS = { gamepad = DoGamepad, back = DoBack, install = DoInstall }

local function Do(kind)
    if not mod or not mod:IsEnabled() then return end
    if PE:InCombat() then return end -- cannot happen: PE:RunOutOfCombat only calls us out of combat
    if EditModeOpen() then
        Say("Close Edit Mode first, then tap this again.")
    else
        local state = ReadState()
        if not state then
            Say("The game's layout list is not available right now. Nothing was changed.")
        else
            ACTIONS[kind](state)
        end
    end
    mod:RefreshPanel()
end

local function Request(kind)
    if PE:InCombat() then
        Say("This will be done when the fight is over.")
    end
    PE:RunOutOfCombat(COMBAT_KEY, function() Do(kind) end)
end

---------------------------------------------------------------------------
-- Panel: buttons and status text
---------------------------------------------------------------------------

local options = {}
local OPTION_GAMEPAD = { label = "Use Blizzard's Gamepad layout", action = function() Request("gamepad") end }
local OPTION_BACK = { label = "Go back to my previous layout", action = function() Request("back") end }
local OPTION_INSTALL = { label = "Install the handheld layout", action = function() Request("install") end }

-- The panel reads mod.options on every redraw, right after it asked for the
-- status text, so the list is rebuilt there. gamepadInUse: Blizzard's
-- Gamepad layout is already the one in use, so its button is left out.
local function RebuildOptions(gamepadInUse)
    for i = #options, 1, -1 do options[i] = nil end
    if not gamepadInUse then
        options[#options + 1] = OPTION_GAMEPAD
    end
    if mod and type(mod.opts) == "table" and type(mod.opts.prev) == "table" then
        options[#options + 1] = OPTION_BACK
    end
    if HasBundled() then
        options[#options + 1] = OPTION_INSTALL
    end
end

local function Status(self)
    local handheld = (not HasBundled()) and NO_HANDHELD or nil
    if not self:IsEnabled() then
        RebuildOptions()
        return handheld
    end

    local lines = {}
    local state = ReadState()
    if not state then
        RebuildOptions()
        lines[#lines + 1] = "The game's layout list is not available right now."
    else
        lines[#lines + 1] = "Layout in use: " .. LayoutLabel(state.current)
        local index, preset = FindGamepadPreset(state.presets)
        RebuildOptions(index ~= nil and state.active == index)
        if not index then
            lines[#lines + 1] = "This game version has no Blizzard Gamepad layout."
        elseif state.active ~= index and not StyleFits(preset.style) then
            local label, section = GamepadSettingName()
            if GamepadUISupported() then
                lines[#lines + 1] = "For Blizzard's Gamepad layout, turn on \"" .. label .. "\" in the game's options (" .. section .. ") first."
            else
                lines[#lines + 1] = "This game version has no Gamepad UI, so Blizzard's Gamepad layout cannot be used."
            end
        end
        if HasBundled() and FindSaved(state, HANDHELD_NAME) then
            lines[#lines + 1] = "The handheld layout is saved as \"" .. HANDHELD_NAME .. "\"."
        end
    end
    if note then lines[#lines + 1] = note end
    lines[#lines + 1] = "Tip: in Edit Mode, the Grid and Snap tick boxes make dragging by touch easier."
    if handheld then lines[#lines + 1] = handheld end
    if #lines == 1 then return lines[1] end
    return lines
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

mod = PE:RegisterModule({
    key = "layout",
    label = "Layout helper",
    desc = "Switch to a ready-made screen layout with one tap.",
    order = 70,
    experimental = true,
    defaults = {},
    options = options,
    status = Status,

    OnLoad = function(self)
        RebuildOptions()
    end,

    OnEnable = function(self)
        note = nil
        confirmUntil = 0
        RebuildOptions()
    end,

    -- Nothing of ours is on screen and nothing is hooked, so there is nothing
    -- to remove. The owner's layout is theirs: switching this off keeps it.
    OnDisable = function(self)
        local changed = type(self.opts) == "table" and type(self.opts.prev) == "table"
        note = nil
        confirmUntil = 0
        if changed then
            self:Print("Layout helper is off. Your screen layout stays as it is.")
        end
    end,
})
