-- Whole-addon smoke test.
--
--   luajit tests/smoke/run.lua <repo root> [QuestieDB dir] [--addon-dir=PATH]
--
-- Loads every file of PocketEssentials.toc into the stand-in client
-- (tests/lib/fakeclient.lua), each scenario on a fresh client, and fails on
-- any Lua error, any PE:LogError, any action the game would block, and any
-- OnUpdate or event a switched-off feature keeps. --addon-dir loads another
-- copy of the addon (used to check that this test notices a broken one).
--
-- Passing here means "passes offline": it proves the code runs against our
-- stand-in, not that the game accepts what it does.
--
-- Prints one line on pass: "Smoke: 6 scenarios, 0 errors". Exit 1 and FAIL
-- lines otherwise.

local root, qdbDir, addonDir
for i = 1, #arg do
    local a = arg[i]
    local dir = a:match("^%-%-addon%-dir=(.+)$")
    if dir then addonDir = dir
    elseif not root then root = a
    elseif not qdbDir then qdbDir = a end
end
if not root then
    io.stderr:write("usage: luajit tests/smoke/run.lua <repo root> [QuestieDB dir] [--addon-dir=PATH]\n")
    os.exit(2)
end

local Client = dofile(root .. "/tests/lib/fakeclient.lua")

-- The real _G before any client: it must look the same after every scenario
-- (the addon runs in each client's own global table; QuestieDB's loader writes
-- to _G and the client puts it back).
local realG = {}
for k, v in pairs(_G) do realG[k] = v end
local function gLeaks()
    local out = {}
    for k, v in pairs(_G) do if realG[k] ~= v then out[#out + 1] = tostring(k) end end
    for k in pairs(realG) do if _G[k] == nil then out[#out + 1] = tostring(k) end end
    table.sort(out)
    return out
end

-- A listed test that fails prints "known failure" and does not fail the run;
-- a listed test that passes fails the run (the entry must then be removed).
-- Each entry is a real addon problem, reported to the owner as a finding.
local KNOWN_FAILURES = {
}

-- Names the addon looked up that the stand-in does not have, and why that is
-- right. A lookup not listed here fails the run: either the addon probes for
-- something this client lacks (check it), or the stand-in is missing a real
-- game function (add it, with where it was read in Blizzard's source).
local EXPECTED_MISSING = {
    ["global PocketEssentialsDB"] = "first install: no saved variables yet (Core.lua InitDB checks)",
    ["global LibQuestieDB"] = "scenarios without QuestieDB (Core.lua CheckQuestieDB, QuestData.lua InitData)",
    ["global PocketEssentialsSettingsPanel"] = "Chat.lua HookSettings looks before the settings window was first opened",
    ["global SMART_NAV_INPUT_DIRECTION"] = "Bags.lua NavApi, with the Sort button showing: the stand-in has Blizzard's navigation helpers only when it starts with the Gamepad UI on (they load with it), and these scenarios start with it off",
    ["global SmartNavigation_AddJumpNavigationOverride"] = "Bags.lua NavApi, with the Sort button showing: the stand-in has Blizzard's navigation helpers only when it starts with the Gamepad UI on (they load with it), and these scenarios start with it off",
    ["global SmartNavigation_ClearJumpNavigationOverridesInDirection"] = "Bags.lua NavApi, with the Sort button showing: the stand-in has Blizzard's navigation helpers only when it starts with the Gamepad UI on (they load with it), and these scenarios start with it off",
}

-- Frames made by the addon that may keep an OnUpdate script while their
-- feature is off, because they are hidden (a hidden frame does not tick).
local HIDDEN_ONUPDATE_OK = {
    ["QuestArrow.lua"] = "the arrow's driver frame keeps its script and is hidden while off (QuestArrow.lua OnDisable)",
    ["Move.lua"] = "the hold driver keeps its script and is shown only while an arrow button is held (Move.lua StartHold / StopHold)",
}

-- The core's own events, registered whatever is switched on.
local CORE_EVENTS = {
    PLAYER_LOGIN = "Core.lua: login",
    PLAYER_REGEN_ENABLED = "Core.lua: runs the out-of-combat queue; UI.lua: re-arms the controller keys",
    PLAYER_REGEN_DISABLED = "UI.lua: releases the controller keys when combat starts",
    UI_SCALE_CHANGED = "UI.lua: resizes everything",
    ADDON_ACTION_BLOCKED = "Core.lua: names an action the game blocked",
    ADDON_ACTION_FORBIDDEN = "Core.lua: names an action the game forbade",
    DISPLAY_SIZE_CHANGED = "UI.lua: resizes everything",
}

local FEATURES = { "questIcons", "questArrow", "bags", "bagWindow", "sellJunk", "repair", "chat", "menuBg" }
local QUEST_FEATURES = { questIcons = true, questArrow = true }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function check(cond, msg, level)
    if not cond then error(msg, (level or 1) + 1) end
end

local missingSeen = {}
local clients = {}

local function newClient(opts)
    opts = opts or {}
    opts.root = root
    opts.addonDir = addonDir
    local c = Client.new(opts)
    clients[#clients + 1] = c
    return c
end

local function collectMissing(c)
    for k in pairs(c.missing) do missingSeen[k] = missingSeen[k] or true end
end

local function textOf(c, w)
    local st = c._state(w)
    return st and st.text or nil
end

-- The label of one of the addon's buttons: the text of its font string.
local function labelOf(c, btn)
    for _, r in ipairs(c._state(btn).regions) do
        local st = c._state(r)
        if st.type == "FontString" and st.text then return st.text end
    end
    return ""
end

local function walk(c, w, fn)
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walk(c, ch, fn) end
    if st.scrollChild then walk(c, st.scrollChild, fn) end
end

-- One look at a window: its visible buttons in reading order, each with its
-- label and its context (the nearest visible text at or above it: the row
-- title for a switch, the option name for a choice). Every rectangle is
-- measured once per look.
local function layoutOf(c, top)
    local buttons, texts = {}, {}
    walk(c, top, function(w)
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() then
            local l, _, t, bottom = c._rect(w)
            buttons[#buttons + 1] = { w = w, left = l or 0, top = t or 0, bottom = bottom or t or 0, label = labelOf(c, w) }
        end
        for _, r in ipairs(st.regions) do
            local rs = c._state(r)
            if rs.type == "FontString" and rs.text and rs.text ~= "" and r:IsVisible() then
                local _, _, t = c._rect(r)
                if t then texts[#texts + 1] = { top = t, text = rs.text, owner = w, onButton = st.type == "Button" } end
            end
        end
    end)
    table.sort(buttons, function(a, b)
        if math.abs(a.top - b.top) > 0.5 then return a.top > b.top end
        return a.left < b.left
    end)
    for _, b in ipairs(buttons) do
        local best, gap = "", math.huge
        -- The nearest heading above the button, or (since 0.6.0) the heading
        -- on the button's own line, left of it: a text that starts above the
        -- button's bottom edge, the closest to the button's top. Button labels
        -- are not headings.
        for _, t in ipairs(texts) do
            local d = math.abs(t.top - b.top)
            if not t.onButton and t.top >= b.bottom and d < gap then best, gap = t.text, d end
        end
        b.ctx = best
    end
    return buttons
end

local function panelOf(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function guideOf(c) return rawget(c.env, "PocketEssentialsSetupPanel") end
local function guideShown(c) return guideOf(c) ~= nil and guideOf(c):IsShown() end

-- The settings window's pages (0.9.0): one per tab, and the Quest Icon Key.
local PAGES = { "questIcons", "questArrow", "bags", "vendors", "chat", "menuBg", "general", "errors", "key" }

local function openPage(c, PE, page)
    PE:OpenSettings(page)
    c:advance(0.1)
end

-- "Reload" (General), "Reload now" (the header) and "Save" (the debug log) reload the interface.
local function isReload(label) return label == "Reload" or label == "Reload now" or label == "Save" end

-- Presses every button on one settings page once (re-opening the page after a
-- button closed it or moved to another page), until none is left unpressed.
local function pressAll(c, PE, page, skip)
    local pressed, count = {}, 0
    for _ = 1, 600 do
        openPage(c, PE, page)
        local panel = panelOf(c)
        check(panel and panel:IsShown(), "the settings window did not open on page " .. page)
        local target, key
        for _, b in ipairs(layoutOf(c, panel)) do
            local k = page .. "|" .. b.ctx .. "|" .. b.label
            if not pressed[k] and not isReload(b.label) and not (skip and skip(b.label, b.ctx, b.w)) then
                target, key = b.w, k
                break
            end
        end
        if not target then return count end
        pressed[key] = true
        count = count + 1
        -- Checked before and after every press: "Clear" on the errors page
        -- wipes the error log, so an error must be caught before it can be cleared.
        c:assertClean("before pressing \"" .. key .. "\"")
        c:click(target)
        c:advance(0.4)
        c:assertClean("after pressing \"" .. key .. "\"")
    end
    error("pressAll(" .. page .. "): more than 600 presses; the page keeps changing")
end

local function findButton(c, top, label, ctx)
    for _, b in ipairs(layoutOf(c, top)) do
        if b.label == label and (ctx == nil or b.ctx == ctx) then return b.w end
    end
    return nil
end

-- Walks the open setup guide from its first screen to its last with Next,
-- pressing no switch. eachScreen(i, n) runs on every screen. Returns the
-- number of screens; the guide is left on the last one.
local function walkGuide(c, where, eachScreen)
    local guide = guideOf(c)
    check(guideShown(c), where .. ": the setup guide is not open")
    local n = tonumber(guide.peTitle:GetText():match("%(1 of (%d+)%)$"))
    check(n and n >= 3, where .. ": the setup guide's title has no \"(1 of n)\": " .. tostring(guide.peTitle:GetText()))
    for i = 1, n do
        check(guide.peTitle:GetText():find("(" .. i .. " of " .. n .. ")", 1, true),
            where .. ": screen " .. i .. " is titled " .. tostring(guide.peTitle:GetText()))
        c:assertClean(where .. ", setup guide screen " .. i)
        if eachScreen then eachScreen(i, n) end
        if i < n then
            local nextBtn = findButton(c, guide, i == 1 and "Start" or "Next")
            check(nextBtn, where .. ": no " .. (i == 1 and "Start" or "Next") .. " button on screen " .. i)
            c:click(nextBtn)
            c:advance(0.2)
        end
    end
    check(findButton(c, guide, "Finish"), where .. ": the last screen has no Finish button")
    check(not findButton(c, guide, "Skip"), where .. ": the last screen has a Skip button")
    return n
end

-- The error log must still work: one deliberate error adds exactly one entry,
-- which is then taken out again. If the addon's logger broke, every other
-- check would go blind (they all read that log).
local canarySerial = 0
local function canary(c, PE, where)
    canarySerial = canarySerial + 1
    local msg = "smoke canary " .. canarySerial
    local before = #PE.errors
    PE:Safe("core", error, msg)
    local e = PE.errors[1]
    check(#PE.errors == before + 1 and type(e) == "table" and tostring(e.msg):find(msg, 1, true),
        where .. ": a deliberate error did not reach the error log (PE:LogError is not recording)")
    table.remove(PE.errors, 1)
end

local function visibleTexts(c, top)
    local out = {}
    walk(c, top, function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and r:IsVisible() then out[#out + 1] = st.text end
        end
    end)
    return out
end

local function tocField(field)
    local f = assert(io.open((addonDir or (root .. "/addons/PocketEssentials")) .. "/PocketEssentials.toc", "rb"))
    local v = f:read("*a"):match("## " .. field .. ":%s*([^\r\n]+)")
    f:close()
    return v and v:gsub("%s+$", "")
end

-- A feature's switch: the settings window's (a switch widget) or the setup guide's (ON / OFF / PROBLEM).
local function isSwitch(label, w)
    return (w ~= nil and w.peSwitchState ~= nil) or label == "ON" or label == "OFF" or label == "PROBLEM"
end

local function addonFrames(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then out[#out + 1] = rec end
    end
    return out
end

local function moduleStates(PE)
    local out = {}
    for _, key in ipairs(FEATURES) do
        local state, detail = PE:GetModuleState(key)
        out[key] = { state = state, detail = detail }
    end
    return out
end

---------------------------------------------------------------------------
-- The quest log for scenario 2: three real quests from QuestieDB 1.1.1.
--   33  "Wolves Across the Border" (Elwynn Forest, map 1429): many spots, focused
--   7   "Kobold Camp Cleanup" (Elwynn Forest), complete: a turn-in spot
--   55  "Morbent Fel" (Duskwood, map 1431): another zone
-- Each choice is checked once the pins are built, so a QuestieDB update that
-- changes them fails here instead of quietly testing less.
---------------------------------------------------------------------------

local QUEST_MANY, QUEST_DONE, QUEST_AWAY = 33, 7, 55
local MAP_HOME, MAP_AWAY = 1429, 1431

local function questObjectives(L, id, finished)
    local out = {}
    local function name(entity, eid)
        local ok, n = pcall(entity.name, eid)
        return ok and type(n) == "string" and n or nil
    end
    local function add(text, kind) out[#out + 1] = { text = text, type = kind, finished = finished } end
    local obj = L.Quest.objectives(id) or {}
    for _, o in ipairs(obj[1] or {}) do add((name(L.Npc, o[1]) or "Creature") .. " slain: 0/1", "monster") end
    for _, o in ipairs(obj[2] or {}) do add((o[2] or name(L.Object, o[1]) or "Object") .. ": 0/1", "object") end
    for _, o in ipairs(obj[3] or {}) do add((name(L.Item, o[1]) or "Item") .. ": 0/1", "item") end
    for _, o in ipairs(obj[5] or {}) do add((o[3] or name(L.Npc, o[2]) or "Creature") .. ": 0/1", "monster") end
    return out
end

local function setupWorld(c)
    local w = c.world
    w.maps[MAP_HOME] = { name = "Elwynn Forest", width = 3470, height = 2314 }
    w.maps[MAP_AWAY] = { name = "Duskwood", width = 2700, height = 1800 }
    w.player.map, w.player.x, w.player.y, w.player.facing = MAP_HOME, 0.45, 0.62, 0.5
    w.money = 50000
    w.merchant.canRepair, w.merchant.repairCost = true, 1234
    w.group, w.guild = "party", "Pocket Guild"
    w.channels = { { id = 1, name = "General - Elwynn Forest" }, { id = 2, name = "Trade - City" } }
    w.bagSizes[0] = 16
    w.bags[0][1] = { itemID = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 5 }
    w.bags[0][2] = { itemID = 4865, name = "Ruined Pelt", quality = 0, price = 5, count = 3 }
    w.bags[0][3] = { itemID = 7073, name = "Broken Fang", quality = 0, price = 6, count = 1 }
    w.bags[0][4] = { itemID = 7074, name = "Chipped Claw", quality = 0, price = 4, count = 2, locked = true }
    local L = rawget(c.env, "LibQuestieDB")
    local function title(id) return L and L.Quest.name(id) or ("Quest " .. id) end
    w.questLog.quests = {
        { header = true, title = "Elwynn Forest" },
        { id = QUEST_MANY, title = title(QUEST_MANY), objectives = L and questObjectives(L, QUEST_MANY, false) or {} },
        { id = QUEST_DONE, title = title(QUEST_DONE), complete = true, objectives = L and questObjectives(L, QUEST_DONE, true) or {} },
        { header = true, title = "Duskwood" },
        { id = QUEST_AWAY, title = title(QUEST_AWAY), objectives = L and questObjectives(L, QUEST_AWAY, false) or {} },
    }
    w.questLog.focus = QUEST_MANY
    w.questLog.watched = { QUEST_MANY, QUEST_DONE }
end

local function pinCount(byMap, mapID)
    local list = byMap and byMap[mapID]
    return type(list) == "table" and #list or 0
end

local function checkQuestChoice(c, PE)
    local QD = PE.QuestData
    local many = QD:GetPinsForQuest(QUEST_MANY)
    check(pinCount(many, MAP_HOME) >= 6, "quest " .. QUEST_MANY .. " no longer has many spots on map " .. MAP_HOME
        .. " (" .. pinCount(many, MAP_HOME) .. "); pick another quest")
    local done = QD:GetPinsForQuest(QUEST_DONE)
    local turnin = false
    for _, p in ipairs((done or {})[MAP_HOME] or {}) do if p.kind == "turnin" then turnin = true end end
    check(turnin, "complete quest " .. QUEST_DONE .. " has no turn-in spot on map " .. MAP_HOME)
    local away = QD:GetPinsForQuest(QUEST_AWAY)
    check(pinCount(away, MAP_AWAY) > 0 and pinCount(away, MAP_HOME) == 0,
        "quest " .. QUEST_AWAY .. " is no longer only in another zone (map " .. MAP_AWAY .. ")")
    -- stand next to the first wolf spot so the minimap has icons to draw
    local p = many[MAP_HOME][1]
    c.world.player.x, c.world.player.y = p.x + 0.01, p.y + 0.01
end

---------------------------------------------------------------------------
-- Plausible arguments for every event the addon registers. Events that
-- change the world go through the client's world actions so the game state
-- matches the event. A registered event missing here fails the run.
---------------------------------------------------------------------------

local EVENT_ORDER = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "QUEST_REMOVED",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "PLAYER_LOGOUT",
}
-- Fired once per session by the client; firing it again would not be plausible.
local NOT_REFIRED = { PLAYER_LOGIN = "fires once per session (Core.lua ignores a second one)" }

local function fireWorldEvent(c, event)
    local style = c.world.gamepadUI and 1 or 0
    if event == "ADDON_LOADED" then c:fire(event, "Blizzard_WorldMap", false)
    elseif event == "PLAYER_ENTERING_WORLD" then c:fire(event, false, false)
    elseif event == "QUEST_ACCEPTED" then c:fire(event, QUEST_MANY)
    elseif event == "QUEST_WATCH_LIST_CHANGED" then c:fire(event, QUEST_MANY, true)
    elseif event == "QUEST_REMOVED" then c:fire(event, 99999, false)
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then c:fire(event, style, style)
    elseif event == "PLAYER_REGEN_DISABLED" then c:enterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then c:leaveCombat()
    elseif event == "MERCHANT_SHOW" then c:openMerchant()
    elseif event == "MERCHANT_CLOSED" then c:closeMerchant()
    elseif event == "CHAT_MSG_WHISPER" then c:whisperIn("Thrall-Camelot", "hello")
    elseif event == "CHAT_MSG_WHISPER_INFORM" then c:whisperOut("Thrall-Camelot", "hi back")
    -- Another addon's block: ours would be a real problem (and is logged as one).
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        c:fire(event, "SomeOtherAddon", "CastSpellByName")
    else c:fire(event) end
end

local function registeredEvents(c)
    local set = {}
    for _, rec in ipairs(c:frames()) do
        for e in pairs(rec.events) do set[e] = true end
    end
    return set
end

local function fireEverything(c)
    local set = registeredEvents(c)
    local known = {}
    for _, e in ipairs(EVENT_ORDER) do known[e] = true end
    for e in pairs(set) do
        check(known[e] or NOT_REFIRED[e], "no plausible arguments for event " .. e .. "; add it to EVENT_ORDER")
    end
    local fired = 0
    for _, e in ipairs(EVENT_ORDER) do
        if set[e] then
            fireWorldEvent(c, e)
            fired = fired + 1
        end
    end
    return fired
end

---------------------------------------------------------------------------
-- Scenario bodies
---------------------------------------------------------------------------

-- Everything on, then the whole game around it (scenarios 2 and 3).
local function everythingOn(c, PE, hasQDB)
    -- Not a first install: the setup guide must not open in the middle of this.
    PE.db.setup = "skipped"
    for _, key in ipairs(FEATURES) do PE:SetModuleEnabled(key, true) end
    c:advance(1)
    if hasQDB then checkQuestChoice(c, PE) end
    c:assertClean("switching everything on")

    local fired = fireEverything(c)
    check(fired >= (hasQDB and 19 or 10), "only " .. fired .. " events registered with everything on")
    if os.getenv("SMOKE_VERBOSE") then print("  events fired: " .. fired) end
    c:advance(1)
    fireEverything(c)
    c:advance(1)
    c:assertClean("every event, twice")

    -- walk about for five seconds
    local before = c.stats.addonOnUpdate
    for _ = 1, 50 do
        c.world.player.x = c.world.player.x + 0.0004
        c.world.player.facing = (c.world.player.facing + 0.13) % (2 * math.pi)
        c:advance(0.1)
    end
    if hasQDB then
        check(c.stats.addonOnUpdate > before, "no OnUpdate of ours ran while walking with everything on")
    end
    if hasQDB then
        local shown = 0
        for _, rec in ipairs(c:frames()) do
            if rec.addonFile == "QuestIcons.lua" and rec.parent == c.minimap and rec.frame:IsVisible() then shown = shown + 1 end
        end
        check(shown > 0, "no quest icon on the minimap while standing next to the focused quest's spots")
        -- the quest arrow: a spot chosen and its display on screen
        local pin = PE.QuestData:GetArrowPin()
        check(type(pin) == "table" and pin.questID == QUEST_MANY,
            "the quest arrow chose no spot of the focused quest while standing next to its spots")
        local display = c:find(function(rec)
            return rec.addonFile == "QuestArrow.lua" and rec.parent == c.UIParent and rec.strata == "BACKGROUND"
        end)
        check(display and display.frame:IsVisible(), "the quest arrow is not on screen next to the focused quest's spots")
        local yards = false
        for _, t in ipairs(visibleTexts(c, display.frame)) do
            if t:find("%d+ yd$") or t == "Here" then yards = true end
        end
        check(yards, "the quest arrow shows no distance")
        -- into a dungeon (the arrow goes away) and out again (it comes back)
        c.world.instance = true
        c:fire("ZONE_CHANGED_NEW_AREA")
        c:advance(0.5)
        check(not display.frame:IsVisible(), "the quest arrow stayed on screen inside a dungeon")
        c.world.instance = false
        c:fire("ZONE_CHANGED_NEW_AREA")
        c:advance(0.5)
        check(display.frame:IsVisible(), "the quest arrow did not come back after leaving the dungeon")
        check(type(PE.QuestData:GetArrowPin()) == "table", "the quest arrow chose no spot after leaving the dungeon")
    end
    c:assertClean("walking")

    -- world map
    c:openWorldMap()
    c:advance(0.2)
    c:zoomWorldMap(1.5)
    c:advance(0.2)
    if hasQDB then
        local onMap = 0
        for _, rec in ipairs(c:frames()) do
            if rec.addonFile == "QuestIcons.lua" and rec.parent == c.worldMapCanvas and rec.frame:IsVisible() then onMap = onMap + 1 end
        end
        check(onMap > 0, "no quest icon on the open world map")
        check(c.blobPin:GetAlpha() == 0, "the world map's blue quest area was not hidden")
    end
    c:closeWorldMap()
    c:advance(0.2)
    c:assertClean("world map")

    -- a vendor with greys
    c.world.merchant.repairCost = 2000
    local money = c.world.money
    local sold = #c:callsTo("C_Container.UseContainerItem")
    local repairs = #c:callsTo("RepairAllItems")
    c:openMerchant()
    c:advance(3)
    c:closeMerchant()
    c:advance(1.5)
    sold = #c:callsTo("C_Container.UseContainerItem") - sold
    check(sold == 2, "at a vendor with two sellable greys, " .. sold .. " items were sold")
    local calls = c:callsTo("RepairAllItems")
    check(#calls - repairs == 1, "one vendor visit repaired " .. (#calls - repairs) .. " times, expected once")
    check(calls[#calls].args[1] == false, "the repair did not use the character's own money (RepairAllItems(false))")
    -- 3 Ruined Pelts at 5 and 1 Broken Fang at 6 sold, 2000 repair paid
    check(c.world.money == money + 21 - 2000, "money went from " .. money .. " to " .. c.world.money
        .. ", expected " .. (money + 21 - 2000) .. " (sales 21, repair 2000)")
    c:assertClean("vendor")

    -- the bag
    c:openBag()
    c:advance(0.2)
    local sort = findButton(c, c.UIParent, "Sort")
    check(sort ~= nil, "no Sort button next to the open bag")
    c:click(sort)
    c:advance(0.6)
    check(#c:callsTo("C_Container.SortBags") >= 1, "the Sort button did not sort")
    c:closeBag()
    c:advance(0.2)
    check(not sort:IsVisible(), "the Sort button stayed after the bag closed")
    c:assertClean("bag")

    -- a whisper in and out, then the chat window
    c:whisperIn("Jaina-Camelot", "need help?")
    c:advance(0.2)
    c:click(PE.Hub.button)
    c:advance(0.2)
    local chatPanel = rawget(c.env, "PocketEssentialsChatPanel")
    check(chatPanel and chatPanel:IsShown(), "a tap on the round button did not open the chat window")
    local jaina = findButton(c, chatPanel, "Jaina")
    check(jaina ~= nil, "no button for the player who whispered")
    for _, want in ipairs({ "Say", "Yell", "Party", "Guild", "1. General - Elwynn Forest", "2. Trade - City" }) do
        check(findButton(c, chatPanel, want), "the chat window has no \"" .. want .. "\" button (in a party, a guild and two channels)")
    end
    check(not findButton(c, chatPanel, "Raid"), "the chat window offers Raid while only in a party")
    c:click(jaina)
    c:advance(0.2)
    check(#c:callsTo("ChatFrame1EditBox:SetTellTarget") + #c:callsTo("ChatFrameUtil.SendTell") >= 1,
        "the whisper button did not address the chat box")
    c.closeChat()
    c:whisperOut("Jaina-Camelot", "on my way")
    c:advance(0.2)
    c:assertClean("chat")

    -- every settings page again
    for _, page in ipairs(PAGES) do openPage(c, PE, page) end
    PE:CloseSettings()
    c:advance(0.2)
    c:assertClean("settings pages")

    -- The player turns on the Gamepad UI (chat and bags depend on it); the client
    -- says so with this event.
    c.world.gamepadUI = true
    c:fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    c:advance(1.5)
    c:assertClean("switching to the Gamepad UI")

    -- every feature's options, at each button size (switches and reload left alone)
    local skip = function(label, ctx, w) return isSwitch(label, w) or ctx == "Button size" end
    local presses = 0
    for _, size in ipairs({ "small", "medium", "large" }) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        for _, page in ipairs(PAGES) do presses = presses + pressAll(c, PE, page, skip) end
    end
    -- "I play with" ends on Controller (its parts are pressed left to right), which leaves
    -- touch off; put it back so the pages after this are drawn with the scroll bar again.
    PE:SetUISetting("touch", true)
    c:advance(0.2)
    PE:CloseSettings()
    c:advance(0.2)
    if os.getenv("SMOKE_VERBOSE") then print("  option presses: " .. presses) end

    -- The setup guide, opened by hand with everything on, at each button size:
    -- every switch reads what the feature is, and the last screen lists them.
    for _, size in ipairs({ "small", "medium", "large" }) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        check(PE.Setup:Open("settings") == true, "the setup guide did not open at size " .. size)
        c:advance(0.2)
        local switches, counted = 0, {}
        walkGuide(c, "everything on, " .. size, function(i, n)
            for _, b in ipairs(layoutOf(c, guideOf(c))) do
                if b.w.peKey then
                    if not counted[b.w.peKey] then switches = switches + 1 end
                    counted[b.w.peKey] = true
                    local want = (QUEST_FEATURES[b.w.peKey] and not hasQDB) and "OFF" or "ON"
                    check(b.label == want, "the setup guide's switch for " .. b.w.peKey .. " reads " .. b.label .. ", expected " .. want)
                end
            end
            if i == n then
                local stillOff = false
                for _, t in ipairs(visibleTexts(c, guideOf(c))) do
                    if t:find("Still off:", 1, true) then stillOff = true end
                end
                check(stillOff == not hasQDB, "the setup guide's last screen "
                    .. (stillOff and "has" or "has no") .. " \"Still off\" line with everything on")
            end
        end)
        check(switches == #FEATURES, "the setup guide showed " .. switches .. " switches, expected " .. #FEATURES)
        c:click(findButton(c, guideOf(c), "Close"))
        c:advance(0.2)
        check(not guideShown(c), "Close did not close the setup guide")
    end
    check(PE.db.setup == "skipped", "walking the setup guide and pressing Close changed the saved answer")
    -- The counts at 0.6.0 are 205 with QuestieDB and 138 without (SMOKE_VERBOSE=1 prints them):
    -- fewer buttons (toggles, one "Icons on", one "How to sort"), and the chat
    -- text size buttons are no longer counted again for each size they show.
    -- 0.8.0: "Touch screen" is pressed once per button size and flips the scroll bar, so on
    -- some pages the bar's arrow tabs are not there to be pressed; touch is switched back
    -- on after the loop. The floors below are kept below the counts on purpose.
    -- 0.8.0 (Move on screen): the six round button position buttons and the five arrow
    -- position buttons are gone from the settings (the page now has "Move the round
    -- button" and "Move the arrow", which sit under "Button size" or open another window): about
    -- 207 with QuestieDB and 103 without.
    -- 0.8.0 (Bags in two): Bag window is a feature of its own with Bag size and Bag icons,
    -- and Bag sorter has two toggles: 243 with QuestieDB and 125 without. The floor stays.
    -- 0.9.0 (tabs): every tab is pressed through, its tab buttons included, at each size:
    -- 461 with QuestieDB and 322 without. The floor stays.
    check(presses >= (hasQDB and 195 or 100), "only " .. presses .. " option buttons were pressed")
    c:assertClean("pressing every option")

    local states = moduleStates(PE)
    for _, key in ipairs(FEATURES) do
        local s = states[key]
        if QUEST_FEATURES[key] and not hasQDB then
            check(s.state == "blocked", key .. " is " .. s.state .. " without QuestieDB, expected blocked")
            check(type(s.detail) == "string" and s.detail ~= "", key .. " is blocked without a reason")
        else
            check(s.state == "on", key .. " is " .. tostring(s.state) .. " (" .. tostring(s.detail) .. "), expected on")
        end
    end
    canary(c, PE, "everything on")
    c:assertClean("end")
    collectMissing(c)
end

local scenarios = {}
local shared = {}

scenarios[#scenarios + 1] = { name = "1 first install", run = function()
    local c = newClient()
    local PE = c:loadAddon()
    c:assertClean("loading")
    for _, key in ipairs(FEATURES) do
        check(PE:GetModule(key) ~= nil, "feature " .. key .. " did not register")
        check(not PE:IsModuleEnabled(key), key .. " is on at first install")
        local state = PE:GetModuleState(key)
        check(state == (QUEST_FEATURES[key] and "blocked" or "off"), key .. " is " .. state .. " at first install")
    end
    for _, rec in ipairs(addonFrames(c)) do
        check(rec.scripts.OnUpdate == nil, "a frame made by " .. rec.addonFile .. " has an OnUpdate at first install")
    end
    check(#addonFrames(c) > 0, "the addon made no frames (did it load?)")

    -- The setup guide opens by itself a moment after the first loading screen.
    check(guideOf(c) == nil, "the setup guide was built at load")
    c:advance(2)
    check(guideShown(c), "the setup guide did not open by itself at first install")
    local screens = walkGuide(c, "first install")
    check(screens == 9, "the setup guide has " .. screens .. " screens at first install, expected 9")
    local nothingOn = false
    for _, t in ipairs(visibleTexts(c, guideOf(c))) do
        if t:find("Nothing is switched on yet", 1, true) then nothingOn = true end
    end
    check(nothingOn, "the setup guide's last screen does not say that nothing is switched on")
    c:click(findButton(c, guideOf(c), "Finish"))
    c:advance(0.2)
    check(not guideShown(c), "Finish did not close the setup guide")
    check(PE.db.setup == "finished", "Finish stored " .. tostring(PE.db.setup))
    for _, key in ipairs(FEATURES) do
        check(not PE:IsModuleEnabled(key), key .. " is on after walking the setup guide without touching a switch")
    end
    c:assertClean("setup guide at first install")

    local presses = 0
    -- bags switched on asks for a reload ("Reload now" in the header)
    c.world.cvars.combinedBags = "0"
    for _, size in ipairs({ "Small", "Medium", "Large" }) do
        openPage(c, PE, "general")
        local btn = findButton(c, panelOf(c), size, "Button size")
        check(btn ~= nil, "no " .. size .. " button under \"Button size\"")
        c:click(btn)
        c:advance(0.4)
        check(PE.db.ui.size == size:lower(), "pressing " .. size .. " left the size at " .. tostring(PE.db.ui.size))
        local skip = function(label, ctx) return ctx == "Button size" end
        for _, page in ipairs(PAGES) do
            presses = presses + pressAll(c, PE, page, skip)
            c:assertClean("pressing every button on page " .. page .. " at " .. size)
        end
    end
    check(presses >= 60, "only " .. presses .. " buttons were pressed")
    if os.getenv("SMOKE_VERBOSE") then print("  buttons pressed: " .. presses) end

    -- Reload buttons: each press calls C_UI.Reload exactly once.
    PE:SetModuleEnabled("bags", true)
    openPage(c, PE, "general")
    for _, label in ipairs({ "Reload", "Reload now" }) do
        local btn = findButton(c, panelOf(c), label)
        check(btn ~= nil, "no \"" .. label .. "\" button")
        local before = #c:callsTo("C_UI.Reload")
        c:click(btn)
        check(#c:callsTo("C_UI.Reload") - before == 1, "\"" .. label .. "\" called C_UI.Reload "
            .. (#c:callsTo("C_UI.Reload") - before) .. " times")
    end
    PE:CloseSettings()
    c:advance(0.2)
    check(not panelOf(c):IsShown(), "the settings window did not close")
    c:assertClean("closing")

    -- The Errors page with an entry on it (what the player reads out to us).
    canary(c, PE, "first install")
    PE:LogError("bags", "smoke seeded error: this is what a problem looks like")
    openPage(c, PE, "errors")
    local seen = false
    for _, t in ipairs(visibleTexts(c, panelOf(c))) do
        if t:find("smoke seeded error", 1, true) then seen = true end
    end
    check(seen, "the Errors page does not show a logged error")
    local clear = findButton(c, panelOf(c), "Clear errors")
    check(clear, "no Clear errors button on the Errors page")
    -- "Save" is a reload (the game writes the saved file then): one call per press.
    local save = findButton(c, panelOf(c), "Save")
    check(save, "no Save button on the Errors page")
    local reloadsBefore = #c:callsTo("C_UI.Reload")
    c:click(save)
    check(#c:callsTo("C_UI.Reload") - reloadsBefore == 1, "\"Save\" did not call C_UI.Reload once")
    c:click(clear)
    c:advance(0.2)
    check(#PE.errors == 0, "Clear left " .. #PE.errors .. " entries in the error log")
    PE:CloseSettings()
    c:advance(0.2)
    c:assertClean("errors page")

    -- The minimap's addon list entry (## AddonCompartmentFunc in the TOC) and /pe.
    local fname = tocField("AddonCompartmentFunc")
    check(fname and type(rawget(c.env, fname)) == "function", "the TOC's AddonCompartmentFunc "
        .. tostring(fname) .. " is not a global function after loading")
    c._protect("AddonCompartmentFunc", rawget(c.env, fname), "PocketEssentials", "LeftButton")
    c:advance(0.2)
    check(panelOf(c):IsShown(), "the minimap's addon list entry did not open the settings")
    c._protect("AddonCompartmentFunc", rawget(c.env, fname), "PocketEssentials", "LeftButton")
    c:advance(0.2)
    check(not panelOf(c):IsShown(), "a second tap on the minimap's addon list entry did not close the settings")
    local slash = rawget(c.env, "SlashCmdList").POCKETESSENTIALS
    check(rawget(c.env, "SLASH_POCKETESSENTIALS1") == "/pe" and type(slash) == "function", "/pe is not registered")
    c._protect("/pe", slash, "")
    c:advance(0.2)
    check(panelOf(c):IsShown(), "/pe did not open the settings")
    c._protect("/pe errors", slash, "errors")
    c:advance(0.2)
    c._protect("/pe reset", slash, "reset")
    c:advance(0.2)
    check(PE.db.ui.size == "medium" and PE.db.ui.hubPos == "LEFT", "/pe reset did not reset the size and position")
    c._protect("/pe setup", slash, "setup")
    c:advance(0.2)
    check(guideShown(c), "/pe setup did not open the setup guide")
    check(not panelOf(c):IsShown(), "/pe setup left the settings open under the setup guide")
    c:click(findButton(c, guideOf(c), "Close"))
    c:advance(0.2)
    check(not guideShown(c), "Close did not close the setup guide")
    PE:CloseSettings()
    c:advance(0.2)
    canary(c, PE, "first install, end")
    c:assertClean("slash commands")
    collectMissing(c)
end }

scenarios[#scenarios + 1] = { name = "2 everything on, with QuestieDB", needsQDB = true, run = function()
    local c = newClient({ questieDB = qdbDir })
    setupWorld(c)
    local PE = c:loadAddon()
    c:assertClean("loading")
    everythingOn(c, PE, true)
    -- /qd: usage line, and one toggle there and back
    local qd = rawget(c.env, "SlashCmdList").POCKETESSENTIALSQD
    check(rawget(c.env, "SLASH_POCKETESSENTIALSQD1") == "/qd" and type(qd) == "function", "/qd is not registered")
    local lines = #c.chat
    c._protect("/qd", qd, "")
    check(#c.chat > lines, "/qd printed nothing")
    local mapOpt = PE:GetModule("questIcons").opts.map
    c._protect("/qd map", qd, "map")
    check(PE:GetModule("questIcons").opts.map == not mapOpt, "/qd map did not toggle the map icons")
    c._protect("/qd map", qd, "map")
    c:advance(0.5)
    c:assertClean("/qd")
    shared.everythingOn = { c = c, PE = PE }
    if os.getenv("SMOKE_DUMP") then
        local seen = {}
        for _, call in ipairs(c.calls) do seen[call.name] = (seen[call.name] or 0) + 1 end
        for k, n in pairs(seen) do print("  call " .. k .. " x" .. n) end
        for _, l in ipairs(c.chat) do print("  chat " .. l) end
        for k, n in pairs(c.missing) do print("  missing " .. k .. " x" .. n) end
        print("  addon OnUpdate calls " .. c.stats.addonOnUpdate .. ", addon timers " .. c.stats.addonTimers)
    end
end }

scenarios[#scenarios + 1] = { name = "3 everything on, QuestieDB missing", run = function()
    local c = newClient()
    setupWorld(c)
    local PE = c:loadAddon()
    everythingOn(c, PE, false)
end }

scenarios[#scenarios + 1] = { name = "4 everything off again", needsQDB = true, run = function()
    local s = shared.everythingOn
    check(s, "scenario 2 did not finish, so there is nothing to switch off")
    local c, PE = s.c, s.PE
    for _, key in ipairs(FEATURES) do PE:SetModuleEnabled(key, false) end
    for _, key in ipairs(FEATURES) do
        check(not PE:IsModuleEnabled(key), key .. " is still on")
    end
    local coreFrame
    for _, rec in ipairs(addonFrames(c)) do
        if rec.addonFile == "Core.lua" then coreFrame = coreFrame or rec end
    end
    local bagsOpts = PE:GetModule("bags").opts
    for _, rec in ipairs(addonFrames(c)) do
        if rec.scripts.OnUpdate then
            if os.getenv("SMOKE_VERBOSE") then print("  hidden OnUpdate kept: " .. rec.addonFile) end
            check(not rec.frame:IsVisible(), "a visible frame made by " .. rec.addonFile .. " still has an OnUpdate")
            check(HIDDEN_ONUPDATE_OK[rec.addonFile], "a hidden frame made by " .. rec.addonFile
                .. " still has an OnUpdate (not in HIDDEN_ONUPDATE_OK)")
        end
        for event in pairs(rec.events) do
            local ok = (rec == coreFrame and CORE_EVENTS[event])
                or (rec.addonFile == "Bags.lua" and event == "PLAYER_LOGOUT" and bagsOpts.cvarWant ~= nil)
            check(ok, "with everything off, a frame made by " .. rec.addonFile .. " still has " .. event)
            if os.getenv("SMOKE_VERBOSE") then print("  event kept while off: " .. rec.addonFile .. " " .. event) end
        end
    end
    local updates = c.stats.addonOnUpdate
    c:advance(5)
    check(c.stats.addonOnUpdate == updates, (c.stats.addonOnUpdate - updates) .. " OnUpdate calls of ours with everything off")
    local timers = c.stats.addonTimers
    c:advance(5)
    check(c.stats.addonTimers == timers, (c.stats.addonTimers - timers) .. " timers of ours still running with everything off")
    canary(c, PE, "everything off")
    c:assertClean("everything off")
    collectMissing(c)
end }

scenarios[#scenarios + 1] = { name = "5 saved settings from 0.0.2", needsQDB = true, run = function()
    local saved = {
        version = 1,
        enabled = { questIcons = true },
        options = { questIcons = { show = "focus", map = true, mini = true, hideHaze = true, size = "medium", cluster = 2 } },
        ui = { size = "medium", hubPos = "LEFT" },
        errors = {},
    }
    local c = newClient({ questieDB = qdbDir, saved = saved })
    setupWorld(c)
    local PE = c:loadAddon()
    c:advance(1)
    c:assertClean("loading old settings")
    local opts = PE:GetModule("questIcons").opts
    check(opts == rawget(c.env, "PocketEssentialsDB").options.questIcons, "the saved table was not used")
    check(opts.spots == 5, "spots is " .. tostring(opts.spots) .. " after an upgrade, expected 5")
    check(opts.show == "tracked", "show is " .. tostring(opts.show) .. " after an upgrade, expected tracked")
    check(PE:GetModuleState("questIcons") == "on", "quest icons did not come back on")
    -- A player who already uses the addon sees the setup guide once after
    -- updating, with the switches as they are; Skip changes none of them.
    c:advance(1.5)
    check(guideShown(c), "the setup guide did not open for saved settings that never answered it")
    c:click(findButton(c, guideOf(c), "Start"))
    c:advance(0.2)
    local iconsSwitch
    for _, b in ipairs(layoutOf(c, guideOf(c))) do
        if b.w.peKey == "questIcons" then iconsSwitch = b end
    end
    check(iconsSwitch and iconsSwitch.label == "ON", "the setup guide does not show Quest icons as ON")
    c:click(findButton(c, guideOf(c), "Skip"))
    c:advance(0.2)
    check(not guideShown(c), "Skip did not close the setup guide")
    check(PE.db.setup == "skipped", "Skip stored " .. tostring(PE.db.setup))
    local stillOn = 0
    for key, on in pairs(PE.db.enabled) do
        check(key == "questIcons" and on == true, "the setup guide changed the saved switch " .. tostring(key))
        stillOn = stillOn + 1
    end
    check(stillOn == 1, "the saved switches changed while the setup guide was open")
    canary(c, PE, "old settings")
    c:assertClean("old settings")
    collectMissing(c)
end }

local notes, zipsChecked = {}, 0
scenarios[#scenarios + 1] = { name = "6 zip contents", run = function()
    local f = assert(io.open(root .. "/addons/PocketEssentials/PocketEssentials.toc", "rb"))
    local version = f:read("*a"):match("## Version:%s*([^\r\n]+)")
    f:close()
    version = version and version:gsub("%s+$", "")
    local zips = {
        { path = root .. "/dist/PocketEssentials-" .. tostring(version) .. ".zip", toc = "PocketEssentials/PocketEssentials.toc" },
        { path = root .. "/dist/wow-forever-pocket-essentials.zip", toc = "PocketEssentials/PocketEssentials.toc" },
    }
    for _, z in ipairs(zips) do
        local name = z.path:match("[^/]+$")
        local fh = io.open(z.path, "rb")
        if not fh then
            notes[#notes + 1] = "zip contents: " .. name .. " not found (run scripts/build.sh)"
        else
            fh:close()
            local p = assert(io.popen("unzip -p '" .. z.path .. "' '" .. z.toc .. "' 2>/dev/null"))
            local zipVersion = (p:read("*a") or ""):match("## Version:%s*([^\r\n]+)")
            p:close()
            zipVersion = zipVersion and zipVersion:gsub("%s+$", "")
            if zipVersion ~= version then
                notes[#notes + 1] = "zip contents: skipped " .. name .. " (holds " .. tostring(zipVersion)
                    .. ", the TOC says " .. tostring(version) .. "; run scripts/build.sh)"
            else
                zipsChecked = zipsChecked + 1
                local l = assert(io.popen("unzip -Z1 '" .. z.path .. "' 2>/dev/null"))
                local n = 0
                for line in l:lines() do
                    n = n + 1
                    check(not line:find("tests/", 1, true) and not line:find("scripts/", 1, true), name .. " contains " .. line)
                    -- The restriction probe (probe/PocketProbe) is for testing only: players never get it.
                    check(not line:lower():find("pocketprobe", 1, true) and not line:find("probe/", 1, true),
                        name .. " contains a restriction probe file: " .. line)
                end
                l:close()
                check(n > 0, "could not list " .. name)
                notes[#notes + 1] = "zip contents: " .. name .. " (" .. version .. ", " .. n .. " files) has nothing from tests/, scripts/ or the probe"
            end
        end
    end
end }

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

-- Scenario 4 switches off what scenario 2 switched on, on the same client, so
-- it runs straight after 2; every other scenario has a client of its own.
local RUN_ORDER = { 1, 2, 4, 3, 5, 6 }
local failures, known, ran, skipped = {}, {}, 0, 0
for _, index in ipairs(RUN_ORDER) do
    local s = scenarios[index]
    if s.needsQDB and not qdbDir then
        skipped = skipped + 1
    else
        ran = ran + 1
        local t0 = os.clock()
        local ok, err = xpcall(s.run, debug.traceback)
        if os.getenv("SMOKE_VERBOSE") then print(string.format("  %s: %.2f s", s.name, os.clock() - t0)) end
        local reason = KNOWN_FAILURES[s.name]
        if ok and reason then
            failures[#failures + 1] = s.name .. ": listed in KNOWN_FAILURES (" .. reason .. ") but passed; remove the entry"
        elseif not ok and reason then
            known[#known + 1] = s.name .. " (" .. reason .. ")"
        elseif not ok then
            failures[#failures + 1] = s.name .. ": " .. tostring(err)
        end
    end
    if s.name:sub(1, 1) ~= "2" then -- put the clients away (scenario 2's after scenario 4)
        for i = #clients, 1, -1 do clients[i]:destroy() clients[i] = nil end
        local leaks = gLeaks()
        if #leaks > 0 then failures[#failures + 1] = s.name .. ": left globals in _G: " .. table.concat(leaks, ", ") end
    end
end
for i = #clients, 1, -1 do clients[i]:destroy() end

local unexpected = {}
for k in pairs(missingSeen) do
    if not EXPECTED_MISSING[k] then unexpected[#unexpected + 1] = k end
end
table.sort(unexpected)
if #unexpected > 0 then
    failures[#failures + 1] = "the addon looked up names the stand-in does not have (see EXPECTED_MISSING):\n    "
        .. table.concat(unexpected, "\n    ")
end

for _, k in ipairs(known) do print("known failure: " .. k) end
for _, n in ipairs(notes) do io.stderr:write("note: " .. n .. "\n") end   -- stderr: stdout stays one summary line
if #failures > 0 then
    for _, f in ipairs(failures) do print("FAIL: " .. f) end
    os.exit(1)
end
-- A zip check that found no zip to look at proved nothing, so it is not counted as a passed scenario.
local zipSkipped = zipsChecked == 0
if zipSkipped then ran = ran - 1 end
local line = string.format("Smoke: %d scenarios, 0 errors", ran)
if #known > 0 then line = line .. string.format(", %d known failure%s", #known, #known == 1 and "" or "s") end
if skipped > 0 then line = line .. string.format(" (%d skipped: no QuestieDB dir)", skipped) end
if zipSkipped then line = line .. " (zip check skipped: no usable dist/ zips)" end
print(line)
