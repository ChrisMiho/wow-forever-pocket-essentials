-- Pocket Essentials: quick slots, first slot: the mount.
-- The rules behind the "Quick slots" line at the bottom of the Chat picker's
-- window (Chat.lua draws it): which mount the square stands for, what the
-- square says, and what a tap does. A tap gets on the chosen mount or gets
-- off, the way the game's own Mount button in the Collections menu does it
-- (Blizzard_Collections/Classic/Blizzard_MountCollection.lua:498-511,
-- MountJournalMountButton_UseMount: C_MountJournal.Dismiss() when the mount
-- is active, else C_MountJournal.SummonByID(mountID); the same call is at
-- Mainline/Blizzard_MountCollection.lua:833).
--
-- This file makes no frame, registers no event and starts no timer (Chat.lua
-- registers the events of the row "Mount square, live"). The game is asked
-- only when the window is drawn, when the square is tapped and when the
-- settings show the "Mount" row. Nothing is put on a spell bar.
--
-- SummonByID(0), the game's "random favourite", is never used: the game's own
-- button for it is commented out on this client
-- (Classic/Blizzard_MountCollection.lua:622-643), so a mount is always
-- summoned by its own id.
--
-- The rule functions (Mounts, Pick, Next, State) take what they need as
-- arguments and ask the game nothing, so the offline tests can run them.
local ADDON_NAME, PE = ...

local type, pcall = type, pcall
local issecretvalue = issecretvalue -- nil on clients without secret values

local QS = {}
PE.QuickSlots = QS

local LABEL_NONE = "No mount yet"
local LABEL_OFF = "Get off"
local LABEL_DEFAULT = "First favourite"
local NAME_UNKNOWN = "Mount" -- shown when the game does not give a mount's name

---------------------------------------------------------------------------
-- Secret values.
-- The game may hand an addon a "secret" value that it may not compare, store
-- or join (Chat.lua has the same check for whisper names). Nothing from the
-- mount journal is looked at before IsSecret() said it is safe; a hidden
-- answer counts as "no": not owned, not usable, not a favourite, not active.
---------------------------------------------------------------------------

local function IsSecret(value)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return true end
    return secret and true or false
end

-- True only for a plain true the game let us see.
local function Yes(value)
    if IsSecret(value) then return false end
    return value == true
end

---------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------

-- One mount from the answers of GetMountInfoByID
-- (Blizzard_APIDocumentationGenerated/MountJournalDocumentation.lua:273:
-- name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
-- isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID), or nil
-- when the call failed, the mount is not owned, or the game hides it on this
-- character.
local function Entry(id, ok, name, _, icon, active, usable, _, favourite, _, _, hide, collected)
    if not ok or not Yes(collected) or Yes(hide) then return nil end
    if IsSecret(name) or type(name) ~= "string" or name == "" then name = NAME_UNKNOWN end
    if IsSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = nil end
    return { id = id, name = name, icon = icon, favourite = Yes(favourite), usable = Yes(usable), active = Yes(active) }
end

-- The mounts this character owns, in the game's order:
--   { { id =, name =, icon =, favourite =, usable =, active = }, ... }
-- api: a table with GetMountIDs and GetMountInfoByID. Without both, or when
-- the list cannot be read, the answer is an empty list.
function QS.Mounts(api)
    local out = {}
    if type(api) ~= "table" then return out end
    local getIDs, getInfo = api.GetMountIDs, api.GetMountInfoByID
    if type(getIDs) ~= "function" or type(getInfo) ~= "function" then return out end
    local ok, ids = pcall(getIDs)
    if not ok or IsSecret(ids) or type(ids) ~= "table" then return out end
    for i = 1, #ids do
        local id = ids[i]
        -- Id 0 is the game's "random favourite", which is never used here.
        if not IsSecret(id) and type(id) == "number" and id > 0 then
            local entry = Entry(id, pcall(getInfo, id))
            if entry then out[#out + 1] = entry end
        end
    end
    return out
end

local function Find(list, id)
    if type(id) ~= "number" then return nil end
    for i = 1, #list do
        if list[i].id == id then return i end
    end
    return nil
end

-- The mount the square stands for, and whether it is the built-in choice.
-- The saved one when it is owned. Else the first favourite that can be used,
-- else the first favourite, else the first mount that can be used, else the
-- first mount. nil for an empty list. The saved id is only read.
function QS.Pick(list, savedId)
    local at = Find(list, savedId)
    if at then return list[at], false end
    local favourite, usable
    for i = 1, #list do
        local e = list[i]
        if e.favourite and e.usable then return e, true end
        if e.favourite and not favourite then favourite = e end
        if e.usable and not usable then usable = e end
    end
    return favourite or usable or list[1], true
end

-- The saved value one step on (step 1) or back (step -1) in the circle
-- "First favourite" (nil), each owned mount, and round again. A saved mount
-- that is not owned counts as "First favourite".
function QS.Next(list, savedId, step)
    local count = #list
    if count == 0 then return nil end
    local at = (Find(list, savedId) or 0) + ((type(step) == "number" and step < 0) and -1 or 1)
    if at < 0 then at = count elseif at > count then at = 0 end
    return at > 0 and list[at].id or nil
end

-- What the square shows and what a tap does:
--   { icon =, label =, greyed =, bright =, action = }
-- action: "none" (no mount), "combat" (in a fight: nothing is asked of the
-- game), "dismiss" (mounted: get off) or "summon". A mount that cannot be
-- used here (indoors, swimming) is greyed and a tap still asks the game,
-- which says why in its own red text.
function QS.State(entry, mounted, inCombat)
    if type(entry) ~= "table" then
        return { icon = nil, label = LABEL_NONE, greyed = true, bright = false, action = "none" }
    end
    mounted = mounted and true or false
    if inCombat then
        return { icon = entry.icon, label = mounted and LABEL_OFF or entry.name, greyed = true, bright = mounted, action = "combat" }
    end
    if mounted then
        return { icon = entry.icon, label = LABEL_OFF, greyed = false, bright = true, action = "dismiss" }
    end
    return { icon = entry.icon, label = entry.name, greyed = not entry.usable, bright = false, action = "summon" }
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------

-- The two read calls, taken from the game each time (nothing is kept):
-- C_MountJournal.GetMountIDs (MountJournalDocumentation.lua:264) and
-- C_MountJournal.GetMountInfoByID (:273). nil on a client without them.
local function GameApi()
    if type(C_MountJournal) ~= "table" then return nil end
    return { GetMountIDs = C_MountJournal.GetMountIDs, GetMountInfoByID = C_MountJournal.GetMountInfoByID }
end

-- The mount id this character chose (PocketEssentialsCharDB.quickSlots.mount),
-- or nil for "First favourite". Mounts differ by character, so it is not in
-- the account-wide file.
local function SavedId()
    local charDB = PE.charDB
    local saved = type(charDB) == "table" and charDB.quickSlots
    local id = type(saved) == "table" and saved.mount
    if type(id) == "number" and id > 0 then return id end
    return nil
end

-- On a mount right now: the picked mount says it is the active one, or
-- IsMounted() (Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua:1399)
-- says so, which also covers a mount other than the picked one.
local function Mounted(entry)
    if entry and entry.active then return true end
    if type(IsMounted) ~= "function" then return false end
    local ok, mounted = pcall(IsMounted)
    return ok and Yes(mounted)
end

-- The square as it is right now: its state, the mount it stands for (nil
-- with none), the owned mounts and whether the mount is the built-in choice.
-- fight: true or false to say it, when the caller knows (the combat event
-- arrives before the game's combat lock is on); nil asks the game.
function QS:Line(fight)
    local list = QS.Mounts(GameApi())
    local entry, isDefault = QS.Pick(list, SavedId())
    -- PE:InCombat() is InCombatLockdown() (RestrictedActionsDocumentation.lua:45).
    if fight == nil then fight = PE:InCombat() end
    return QS.State(entry, Mounted(entry), fight), entry, list, isDefault
end

-- A tap on the square. Returns what was done: "summon" or "dismiss" (the one
-- game call was made), "combat" or "none" (nothing was called), or "missing"
-- (this game version has no such call; nothing was called).
-- C_MountJournal.SummonByID (MountJournalDocumentation.lua:614) and
-- C_MountJournal.Dismiss (:49) are not marked as locked there, and the game's
-- own button calls them from plain Lua. Whether an addon's tap may call them
-- on this client is not known until it is tried on a device
-- (docs/ARCHITECTURE.md, "Unverified API").
function QS:Tap()
    -- In a fight the journal is not even read.
    if PE:InCombat() then
        if PE.debugOn then PE:Debug("chat", "quick slots: mount tapped: combat") end
        return "combat"
    end
    local state, entry = self:Line()
    local action = state.action
    if action ~= "summon" and action ~= "dismiss" then
        if PE.debugOn then PE:Debug("chat", "quick slots: mount tapped: " .. action) end
        return action
    end
    local call
    if type(C_MountJournal) == "table" then
        if action == "summon" then call = C_MountJournal.SummonByID else call = C_MountJournal.Dismiss end
    end
    if type(call) ~= "function" then
        if PE.debugOn then PE:Debug("chat", "quick slots: mount tapped: no " .. action .. " call on this game version") end
        return "missing"
    end
    if PE.debugOn then
        PE:Debug("chat", "quick slots: mount tapped: " .. action .. (action == "summon" and (" " .. entry.id) or ""))
    end
    if action == "summon" then
        PE:Safe("chat", call, entry.id)
    else
        PE:Safe("chat", call)
    end
    return action
end

---------------------------------------------------------------------------
-- The "Mount" settings row
---------------------------------------------------------------------------

-- The row's value: the chosen mount's name, "First favourite" until one is
-- chosen (or when the chosen one is not owned), "No mount yet" with none.
-- The second answer is the small line under it: which mount "First
-- favourite" stands for right now, or the chosen mount's place in the list.
function QS:MountLabel()
    local _, entry, list, isDefault = self:Line()
    if not entry then return LABEL_NONE, nil end
    if isDefault then return LABEL_DEFAULT, entry.name end
    return entry.name, (Find(list, entry.id) or 1) .. " of " .. #list
end

-- One step of the row (1 on, -1 back). Saves the new choice for this
-- character; "First favourite" is saved as nothing. With no mount owned
-- nothing is saved.
function QS:StepMount(step)
    local list = QS.Mounts(GameApi())
    if #list == 0 then return end
    local charDB = PE.charDB
    if type(charDB) ~= "table" then return end
    local id = QS.Next(list, SavedId(), step)
    local saved = charDB.quickSlots
    if type(saved) ~= "table" then
        if id == nil then return end
        saved = {}
        charDB.quickSlots = saved
    end
    saved.mount = id
    if PE.debugOn then PE:Debug("chat", "quick slots: mount choice: " .. (id and tostring(id) or "first favourite")) end
end
