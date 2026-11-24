local ADDON_NAME, PE = ...

-- Loot sparkles: the sparkle on things you can loot or use, kept on at every
-- graphics setting.
--
-- Based on ForeverLootSparkles by Ashtar Senior (GPL-3.0-or-later),
-- https://github.com/svengabr/ForeverLootSparkles
--
-- On low graphics the game hides the sparkle. One engine setting brings it
-- back: outlineModeShowLootEffectWhenDisabled = 1. A graphics preset change
-- puts it back to 0, so it is set again whenever the game says one of the
-- graphics settings (or this one) changed (CVAR_UPDATE), and at login, which
-- is when a saved-on feature is switched on.
--
--   * Before the first write, the setting's own value is saved (options
--     "previous") and put back when the feature is switched off.
--   * No write during a fight: it waits for PLAYER_REGEN_ENABLED.
--   * No frames, no timers, no OnUpdate. Its events exist only while it is on.
--   * Switching off only takes effect after a full restart of the game (a
--     reload is not enough), so its card says so. It asks for no reload: the
--     reload bar's "Reload now" would not remove the sparkles.
--
-- The setting is engine-only (not in Blizzard's interface source): if this
-- client does not have it, the write does nothing and nothing changes.

local type, tostring, pcall = type, tostring, pcall
local lower = string.lower

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local WANT = "1"
-- CVAR_UPDATE names, compared in lower case: the game's own case may differ.
local WATCHED = {
    graphicsquality = true,
    raidgraphicsquality = true,
    [lower(CVAR)] = true,
}

local TEXT_ON = "Things you can loot or use sparkle instead of showing an outline."
local TEXT_RESTART = "Fully restart the game to remove the sparkles."

local mod                     -- the module
local on = false              -- true from switch-on to switch-off (set before OnEnable returns)
local shownThisSession = false -- the setting was 1 under this feature since the game started
local waiting = false         -- a write waits for the fight to end

local function ReadCVar()
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, CVAR)
    if not ok or value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return tostring(value)
end

local function WriteCVar(value)
    if not (C_CVar and C_CVar.SetCVar) then return false end
    local ok = pcall(C_CVar.SetCVar, CVAR, value)
    return ok
end

-- Sets the sparkle on, now or after the fight.
local function Apply()
    if not on then return end
    if PE:InCombat() then
        if not waiting then
            waiting = true
            mod:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                waiting = false
                mod:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if PE.debugOn then PE:Debug("sparkles", "fight over, setting the sparkle again") end
                Apply()
            end)
            if PE.debugOn then PE:Debug("sparkles", "in a fight: the write waits for it to end") end
        end
        return
    end
    local current = ReadCVar()
    if current == WANT then
        shownThisSession = true
        return
    end
    WriteCVar(WANT)
    shownThisSession = true
    if PE.debugOn then
        PE:Debug("sparkles", "set to 1 (was " .. PE.Plain(current) .. ", now " .. PE.Plain(ReadCVar()) .. ")")
    end
end

local function OnCVarUpdate(_, _, name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
    if not WATCHED[lower(name)] then return end
    -- Our own write announces itself too; the value is then already 1.
    if ReadCVar() == WANT then return end
    if PE.debugOn then PE:Debug("sparkles", "reset by a change to " .. name) end
    Apply()
end

local function OnEnable(m)
    on, waiting = true, false
    local opts = m.opts
    if type(opts) == "table" and opts.previous == nil then
        local current = ReadCVar()
        if current ~= nil then opts.previous = current end
    end
    m:RegisterEvent("CVAR_UPDATE", OnCVarUpdate)
    Apply()
end

local restorePending = false -- switched off: the put-back waits for the fight to end

-- The value switching off puts back: the one saved before the first write, or 0.
local function PutBackValue()
    local opts = mod.opts
    local previous = type(opts) == "table" and opts.previous or nil
    return type(previous) == "string" and previous or "0"
end

-- Puts the saved value back (or 0), then forgets it.
local function Restore()
    restorePending = false
    if on then return end -- switched on again meanwhile
    local opts = mod.opts
    local value = PutBackValue()
    if ReadCVar() ~= value then WriteCVar(value) end
    if type(opts) == "table" then opts.previous = nil end
    if PE.debugOn then PE:Debug("sparkles", "put back to " .. PE.Plain(value)) end
    PE:RefreshSettings()
end

local function OnDisable()
    on, waiting = false, false
    restorePending = true
    -- Its events go with the switch; a fight only delays putting the value back.
    PE:RunOutOfCombat("sparkles:restore", Restore)
end

-- Switched off in a fight and reloaded before it ended: the queued put-back
-- was lost with the reload, and OnEnable and OnDisable do not run while the
-- feature is saved off, so the waiting value is put back here.
local function OnLoad(m)
    local opts = m.opts
    if type(opts) ~= "table" or opts.previous == nil or PE:IsModuleSavedOn("sparkles") then return end
    -- The sparkles from before the reload stay until a full restart.
    if ReadCVar() == WANT then shownThisSession = true end
    restorePending = true
    if PE.debugOn then PE:Debug("sparkles", "a put-back was waiting from the last session") end
    PE:RunOutOfCombat("sparkles:restore", Restore)
end

mod = PE:RegisterModule({
    key = "sparkles",
    label = "Loot sparkles",
    desc = "Brings back the loot sparkle, even on the lowest graphics.",
    order = 80,
    -- Its status line also shows while off: the restart line.
    statusWhenOff = true,

    status = function(m)
        if m:IsEnabled() then return TEXT_ON end
        if not shownThisSession then return nil end
        -- A restart removes them only when the setting is off (or will be, once
        -- the fight ends); one the player had at 1 before stays at 1.
        local after = restorePending and PutBackValue() or ReadCVar()
        if after == WANT then return nil end
        return TEXT_RESTART
    end,

    OnLoad = OnLoad,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
