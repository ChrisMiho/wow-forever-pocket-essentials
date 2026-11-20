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
--     reload is not enough), so the settings say so.
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

local TEXT_ON = "Quest items show the sparkle instead of the outline."
local TEXT_RESTART = "Fully restart the game to remove the sparkles."
local RELOAD_REASON = "Fully restart the game to remove the sparkles; a reload is not enough."

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
    m:CancelReload()
    m:RegisterEvent("CVAR_UPDATE", OnCVarUpdate)
    Apply()
end

-- Puts the saved value back (or 0), then forgets it.
local function Restore()
    if on then return end -- switched on again meanwhile
    local opts = mod.opts
    local previous = type(opts) == "table" and opts.previous or nil
    local value = type(previous) == "string" and previous or "0"
    if ReadCVar() ~= value then WriteCVar(value) end
    if type(opts) == "table" then opts.previous = nil end
    if PE.debugOn then PE:Debug("sparkles", "put back to " .. PE.Plain(value)) end
end

local function OnDisable(m)
    on, waiting = false, false
    -- Its events go with the switch; a fight only delays putting the value back.
    PE:RunOutOfCombat("sparkles:restore", Restore)
    if shownThisSession then m:RequestReload(RELOAD_REASON) end
end

mod = PE:RegisterModule({
    key = "sparkles",
    label = "Loot sparkles",
    desc = "Brings back the sparkle on things you can loot or use, even on the lowest graphics.",
    order = 80,
    -- Its status line also shows while off: the restart line.
    statusWhenOff = true,

    status = function(m)
        if m:IsEnabled() then return TEXT_ON end
        if shownThisSession then return TEXT_RESTART end
        return nil
    end,

    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
