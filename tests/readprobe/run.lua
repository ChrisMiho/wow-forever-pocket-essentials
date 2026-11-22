-- Tests for the restriction probe's reader (scripts/read-probe.lua).
--
--   luajit tests/readprobe/run.lua <repo root>
--
-- Source: docs/superpowers/specs/2026-11-17-restriction-probe.md ("Reading it": one table, a
-- row per trial, a column per situation, the result in each cell, and under it the function
-- names and stack lines of every block; "--markdown prints the table ready to paste"; "if a
-- cell gets two different answers both are kept").
-- The saved file here is written by hand and holds no real names.
-- Saved files for the loader are written under the system temp folder and removed.
--
-- Prints "Read-probe: N checks" on pass; exit 1 and FAIL: lines otherwise.
local root = arg[1]
if not root then
    io.stderr:write("usage: luajit tests/readprobe/run.lua <repo root>\n")
    os.exit(2)
end

local R = dofile(root .. "/scripts/read-probe.lua")
local failures, checks = {}, 0

local function show(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    local out = {}
    for i, item in ipairs(v) do out[i] = show(item) end
    return "{" .. table.concat(out, ", ") .. "}"
end

local function eq(actual, expected, what)
    checks = checks + 1
    if show(actual) ~= show(expected) then
        failures[#failures + 1] = what .. ": expected " .. show(expected) .. ", got " .. show(actual)
    end
end

local function check(cond, what)
    checks = checks + 1
    if not cond then failures[#failures + 1] = what end
end

local temps = {}
local function tempFile(text)
    local path = os.tmpname()
    temps[#temps + 1] = path
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    return path
end

---------------------------------------------------------------------------
-- The saved file used below
---------------------------------------------------------------------------

local TOWN_AUTO = "gp=on fight=no rest=------ where=world trig=auto"
local TOWN_PRESS = "gp=on fight=no rest=------ where=world trig=press"
local TOWN_CLEAN = "gp=on fight=no rest=------ where=world trig=clean"
local FIGHT_AUTO = "gp=on fight=yes rest=c----- where=world trig=auto"
local DUNGEON_AUTO = "gp=on fight=no rest=------ where=dungeon trig=auto"
local OFF_AUTO = "gp=off fight=no rest=------ where=world trig=auto"

local function fixture()
    return {
        version = 1,
        game = "1.60.1 (70959)", probe = "0.1.0",
        options = { vendor = true },
        clean = { index = 0, running = false },
        trials = {
            { id = "chat.open", area = "Chat box", label = "Open the chat box", kind = "action" },
            { id = "chat.focus", area = "Chat box", label = "Give the edit box focus", kind = "action" },
            { id = "bags.sort", area = "Bags", label = "Sort the bags", kind = "action" },
            { id = "value.money", area = "Values", kind = "value" },               -- no label: the id is shown
            "junk",
            { area = "Bags", label = "A trial with no id" },
        },
        situations = {
            [OFF_AUTO] = { gamepad = false, lockdown = false, where = "world", trigger = "auto", first = "2026-11-17 15:00:00", passes = 1,
                restrictions = { combat = false, encounter = false, challenge = false, pvp = false, map = false, chat = false } },
            [FIGHT_AUTO] = { gamepad = true, lockdown = true, where = "world", trigger = "auto", first = "2026-11-17 16:05:00", passes = 1,
                restrictions = { combat = true, encounter = false, challenge = false, pvp = false, map = false, chat = false } },
            [TOWN_PRESS] = { gamepad = true, lockdown = false, where = "world", trigger = "press", first = "2026-11-17 16:01:00", passes = 1,
                restrictions = { combat = false, encounter = false, challenge = false, pvp = false, map = false, chat = false } },
            [TOWN_AUTO] = { gamepad = true, lockdown = false, where = "world", trigger = "auto", first = "2026-11-17 16:00:44", passes = 2,
                restrictions = { combat = false, encounter = false, challenge = false, pvp = false, map = false, chat = false } },
            -- TOWN_CLEAN and DUNGEON_AUTO are not listed here: their facts come from the key.
        },
        results = {
            ["chat.open"] = { [TOWN_AUTO] = "allowed / blocked", [TOWN_PRESS] = "allowed", [TOWN_CLEAN] = "allowed", [FIGHT_AUTO] = "blocked", [DUNGEON_AUTO] = "blocked", [OFF_AUTO] = "allowed" },
            ["chat.focus"] = { [TOWN_AUTO] = "no effect", [TOWN_PRESS] = "allowed" },
            ["bags.sort"] = { [TOWN_AUTO] = "allowed", [FIGHT_AUTO] = "forbidden" },
            ["value.money"] = { [TOWN_AUTO] = "readable", [FIGHT_AUTO] = "secret" },
            ["old.trial"] = { [TOWN_AUTO] = "missing" },                            -- not in the trial list
            ["broken.row"] = "junk",
        },
        details = {
            { trial = "chat.open", situation = FIGHT_AUTO, result = "blocked", func = "ChatFrameUtil.OpenChat", message = "Interface action failed because of an AddOn",
                stack = "Interface/A.lua:10: in function 'x'\nInterface/B.lua:20: in function 'y'\n", focus = "none", inPress = false, at = "2026-11-17 16:05:02" },
            { trial = "bags.sort", situation = FIGHT_AUTO, result = "forbidden", func = "C_Container.SortBags", inPress = false },
            "junk",
            { trial = "chat.open", situation = TOWN_AUTO, result = "blocked", func = "ChatFrameUtil.OpenChat", inPress = true, at = "2026-11-17 16:00:50" },
            { trial = "old.trial", situation = "gp=on fight=no rest=------ where=raid trig=auto", result = "error", message = "attempt to call a nil value" },
        },
        log = { "16:00:44 pass started (automatic)", 7, "16:00:50 pass done" },
    }
end

---------------------------------------------------------------------------
-- Situations: their order, short names and plain words
---------------------------------------------------------------------------

do
    local list, byKey = R.situations(fixture())
    local keys, texts = {}, {}
    for i, s in ipairs(list) do keys[i], texts[i] = s.key, s.name .. " " .. s.text end
    eq(keys, {
        TOWN_AUTO, TOWN_PRESS, TOWN_CLEAN, DUNGEON_AUTO, "gp=on fight=no rest=------ where=raid trig=auto", FIGHT_AUTO, OFF_AUTO,
    }, "order: Gamepad UI on first, no fight before a fight, world before instances, automatic then press then clean")
    eq(texts, {
        "S1 Gamepad UI on, no fight, open world, automatic",
        "S2 Gamepad UI on, no fight, open world, from a press",
        "S3 Gamepad UI on, no fight, open world, clean (first thing after a reload)",
        "S4 Gamepad UI on, no fight, dungeon, automatic",
        "S5 Gamepad UI on, no fight, raid, automatic",
        "S6 Gamepad UI on, in a fight, game restrictions on: combat, open world, automatic",
        "S7 Gamepad UI off, no fight, open world, automatic",
    }, "each situation in plain words")
    eq(byKey[FIGHT_AUTO] and byKey[FIGHT_AUTO].name, "S6", "a situation is found by its key")
end

do
    local s = R.parseKey("gp=off fight=yes rest=ce-p-t where=battleground trig=press")
    eq({ s.gamepad, s.lockdown, s.where, s.trigger }, { false, true, "battleground", "press" }, "the facts in a key")
    eq({ s.restrictions.combat, s.restrictions.encounter, s.restrictions.challenge, s.restrictions.pvp, s.restrictions.map, s.restrictions.chat },
        { true, true, false, true, false, true }, "the six restriction letters in a key")
    local list = R.situations({ results = { t = { ["gp=off fight=yes rest=ce-p-t where=battleground trig=press"] = "blocked", ["not a key"] = "allowed" } } })
    eq(list[1].text, "Gamepad UI off, in a fight, game restrictions on: combat, encounter, PvP, chat, battleground, from a press", "a situation known only from its key")
    eq(list[2].text, "Gamepad UI unknown, fight unknown, place unknown, start unknown", "a key that cannot be read still gets a column")
    -- The saved table wins over the key where it has the right type; wrong types are ignored.
    list = R.situations({ situations = { [TOWN_AUTO] = { gamepad = "yes", lockdown = true, where = 5, trigger = "press" } } })
    eq(list[1].text, "Gamepad UI on, in a fight, open world, from a press", "saved facts of the wrong type fall back to the key")
end

---------------------------------------------------------------------------
-- Trials: display order, the id when there is no label, unknown ids
---------------------------------------------------------------------------

do
    local areas = R.areas(fixture())
    local got = {}
    for _, a in ipairs(areas) do
        local labels = {}
        for i, t in ipairs(a.trials) do labels[i] = t.label end
        got[#got + 1] = a.area .. ": " .. table.concat(labels, "; ")
    end
    eq(got, {
        "Chat box: Open the chat box; Give the edit box focus",
        "Bags and vendor: Sort the bags",
        "Values: value.money",
        "Other: broken.row; old.trial",
    }, "trials by area in the file's order, unknown ones under Other")
    eq(R.cell(fixture(), "chat.open", TOWN_AUTO), "allowed / blocked", "a cell with two answers")
    eq(R.cell(fixture(), "chat.focus", FIGHT_AUTO), nil, "a cell that was not run")
    eq(R.cell(fixture(), "broken.row", TOWN_AUTO), nil, "a damaged row has no cells")
end

do
    -- Area names of probe 0.2.0 and of 0.3.0 land in the same group, in a file and in --diff.
    local old = { trials = {
        { id = "bags.sort", area = "Bags", label = "Sort the bags" },
        { id = "vendor.sell1", area = "Vendor", label = "Sell" },
        { id = "pad.bind", area = "Controller", label = "Bind" },
        { id = "layout.set", area = "Layout", label = "Layout" },
        { id = "cvar.write", area = "Settings", label = "Setting" },
    }, results = { ["vendor.sell1"] = { [TOWN_AUTO] = "allowed" }, ["cvar.write"] = { [TOWN_AUTO] = "allowed" } } }
    local new = { trials = {
        { id = "bags.sort", area = "Bags and vendor", label = "Sort the bags" },
        { id = "vendor.sell1", area = "Bags and vendor", label = "Sell" },
        { id = "pad.bind", area = "Controller and layout", label = "Bind" },
        { id = "layout.set", area = "Controller and layout", label = "Layout" },
        { id = "cvar.write", area = "Controller and layout", label = "Setting" },
    }, results = { ["vendor.sell1"] = { [TOWN_AUTO] = "blocked" }, ["cvar.write"] = { [TOWN_AUTO] = "allowed" } } }
    local function groups(db)
        local out = {}
        for _, a in ipairs(R.areas(db)) do out[#out + 1] = a.area .. " " .. #a.trials end
        return out
    end
    eq(groups(old), { "Bags and vendor 2", "Controller and layout 3" }, "0.2.0 area names grouped as in 0.3.0")
    eq(groups(new), { "Bags and vendor 2", "Controller and layout 3" }, "0.3.0 area names")
    local d = R.diff(old, new)
    eq({ d[5], d[6], d[9] }, { "Bags and vendor", "  Sell (vendor.sell1)", "1 cell differs." }, "--diff across the rename")
end

---------------------------------------------------------------------------
-- The default output
---------------------------------------------------------------------------

eq(R.format(fixture()), {
    "Restriction probe",
    "Game 1.60.1 (70959), probe 0.1.0",
    "7 situations, 6 trials",
    "",
    "Situations (the columns below)",
    "  S1  Gamepad UI on, no fight, open world, automatic (first seen 2026-11-17 16:00:44, 2 passes)",
    "  S2  Gamepad UI on, no fight, open world, from a press (first seen 2026-11-17 16:01:00, 1 pass)",
    "  S3  Gamepad UI on, no fight, open world, clean (first thing after a reload)",
    "  S4  Gamepad UI on, no fight, dungeon, automatic",
    "  S5  Gamepad UI on, no fight, raid, automatic",
    "  S6  Gamepad UI on, in a fight, game restrictions on: combat, open world, automatic (first seen 2026-11-17 16:05:00, 1 pass)",
    "  S7  Gamepad UI off, no fight, open world, automatic (first seen 2026-11-17 15:00:00, 1 pass)",
    "",
    "Chat box",
    "  Trial                    S1                 S2       S3       S4       S5  S6       S7",
    "  Open the chat box        allowed / blocked  allowed  allowed  blocked  -   blocked  allowed",
    "  Give the edit box focus  no effect          allowed  -        -        -   -        -",
    "",
    "Bags and vendor",
    "  Trial          S1       S2  S3  S4  S5  S6         S7",
    "  Sort the bags  allowed  -   -   -   -   forbidden  -",
    "",
    "Values",
    "  Trial        S1        S2  S3  S4  S5  S6      S7",
    "  value.money  readable  -   -   -   -   secret  -",
    "",
    "Other",
    "  Trial       S1       S2  S3  S4  S5  S6  S7",
    "  broken.row  -        -   -   -   -   -   -",
    "  old.trial   missing  -   -   -   -   -   -",
    "",
    "Not allowed: 4 entries",
    "",
    "Open the chat box (chat.open)",
    "  blocked in S6 (Gamepad UI on, in a fight, game restrictions on: combat, open world, automatic), at 2026-11-17 16:05:02",
    "    function: ChatFrameUtil.OpenChat",
    "    message: Interface action failed because of an AddOn",
    "    straight from a press: no",
    "    controller focus: none",
    "    stack:",
    "      Interface/A.lua:10: in function 'x'",
    "      Interface/B.lua:20: in function 'y'",
    "  blocked in S1 (Gamepad UI on, no fight, open world, automatic), at 2026-11-17 16:00:50",
    "    function: ChatFrameUtil.OpenChat",
    "    straight from a press: yes",
    "",
    "Sort the bags (bags.sort)",
    "  forbidden in S6 (Gamepad UI on, in a fight, game restrictions on: combat, open world, automatic)",
    "    function: C_Container.SortBags",
    "    straight from a press: no",
    "",
    "old.trial",
    "  error in S5 (Gamepad UI on, no fight, raid, automatic)",
    "    message: attempt to call a nil value",
}, "the whole default output")

---------------------------------------------------------------------------
-- --markdown, --details, --log
---------------------------------------------------------------------------

do
    local md = R.format(fixture(), { markdown = true })
    eq({ md[1], md[2], md[3], md[4], md[5] }, {
        "Game 1.60.1 (70959), probe 0.1.0. 7 situations, 6 trials.",
        "",
        "| Column | Situation |",
        "|---|---|",
        "| S1 | Gamepad UI on, no fight, open world, automatic |",
    }, "--markdown: the build line and the legend table")
    local at
    for i, line in ipairs(md) do
        if line == "#### Chat box" then at = i end
    end
    check(at, "--markdown has no heading for the Chat box area")
    at = at or 1
    eq({ md[at + 1], md[at + 2], md[at + 3], md[at + 4], md[at + 5] }, {
        "",
        "| Trial | S1 | S2 | S3 | S4 | S5 | S6 | S7 |",
        "|---|---|---|---|---|---|---|---|",
        "| Open the chat box | allowed / blocked | allowed | allowed | blocked | - | blocked | allowed |",
        "| Give the edit box focus | no effect | allowed | - | - | - | - | - |",
    }, "--markdown: a GitHub table per area")
    for _, line in ipairs(md) do
        check(not line:find("Not allowed", 1, true), "--markdown printed the Not allowed section")
    end
    -- A bar inside a cell would end the cell early.
    local bars = R.format({ trials = { { id = "a", label = "this | that", area = "One" } }, results = { a = { [TOWN_AUTO] = "x|y" } } }, { markdown = true })
    eq(bars[#bars], "| this \\| that | x\\|y |", "--markdown escapes a bar inside a cell")
end

do
    local details = R.format(fixture(), { detailsOnly = true })
    eq(details[1], "Not allowed: 4 entries", "--details starts with the Not allowed section")
    eq(#details, 23, "--details line count")
    eq(R.format({}, { detailsOnly = true }), { "Not allowed: 0 entries" }, "--details with no details")
    eq(R.format({ details = { { trial = "t", situation = TOWN_AUTO, result = "blocked" } } }, { detailsOnly = true }), {
        "Not allowed: 1 entry",
        "",
        "t",
        "  blocked in S1 (Gamepad UI on, no fight, open world, automatic)",
    }, "a detail with only the three fixed fields")
end

eq(R.format(fixture(), { logOnly = true }), {
    "Activity log: 2 lines",
    "16:00:44 pass started (automatic)",
    "16:00:50 pass done",
}, "--log prints the activity log, leaving out an entry that is not text")

---------------------------------------------------------------------------
-- Empty and damaged saved tables
---------------------------------------------------------------------------

local EMPTY = {
    "Restriction probe",
    "Game unknown, probe unknown",
    "0 situations, 0 trials",
    "",
    "No results in this file yet.",
    "",
    "Not allowed: 0 entries",
}
eq(R.format({}), EMPTY, "a saved table with nothing in it")
eq(R.format({ trials = "junk", situations = 7, results = true, details = "junk", log = 1 }), EMPTY, "damaged tables")
eq(R.format({ trials = {}, situations = {}, results = {}, details = {}, log = {} }), EMPTY, "empty tables")
eq(R.format({}, { logOnly = true }), { "Activity log: 0 lines" }, "no log")
eq(R.format({ game = 7, probe = true, results = { t = { [TOWN_AUTO] = 12 } } })[2], "Game 7, probe true", "values of the wrong type are printed as text")
do
    -- Text from the device is printed on one line with no control characters.
    local out = R.format({ game = "1.0\27[2J", trials = { { id = "t", label = "two\nlines", area = "A\tB" } }, results = { t = { [TOWN_AUTO] = "allowed\r" } } })
    for _, line in ipairs(out) do
        check(not line:find("%c"), "a control character reached the output: " .. show(line))
    end
end

---------------------------------------------------------------------------
-- --diff: only the cells that differ
---------------------------------------------------------------------------

do
    local before, after = fixture(), fixture()
    after.game = "1.60.2 (71000)"
    after.results["chat.open"][FIGHT_AUTO] = "allowed"                 -- changed
    after.results["chat.open"][TOWN_AUTO] = "blocked / allowed"        -- the same two answers in another order
    after.results["bags.sort"][TOWN_AUTO] = "allowed / blocked"        -- one answer became two
    after.results["chat.focus"][TOWN_PRESS] = nil                      -- not run in the later file
    after.results["value.money"][DUNGEON_AUTO] = "readable"            -- only in the later file
    eq(R.diff(before, after, "old.lua", "new.lua"), {
        "Comparing probe files",
        "  before: old.lua (game 1.60.1 (70959), probe 0.1.0)",
        "  after:  new.lua (game 1.60.2 (71000), probe 0.1.0)",
        "",
        "Chat box",
        "  Open the chat box (chat.open)",
        "    Gamepad UI on, in a fight, game restrictions on: combat, open world, automatic: blocked -> allowed",
        "",
        "Bags and vendor",
        "  Sort the bags (bags.sort)",
        "    Gamepad UI on, no fight, open world, automatic: allowed -> allowed / blocked",
        "",
        "2 cells differ.",
        "1 cell is only in the first file (not run in the second).",
        "1 cell is only in the second file (not run in the first).",
    }, "--diff")
    eq(R.diff(fixture(), fixture()), {
        "Comparing probe files",
        "  before: first file (game 1.60.1 (70959), probe 0.1.0)",
        "  after:  second file (game 1.60.1 (70959), probe 0.1.0)",
        "",
        "No cell that both files have differs.",
    }, "--diff of a file with itself")
    eq(#R.diff({}, "junk"), 5, "--diff of empty and damaged tables")
end

---------------------------------------------------------------------------
-- Probe 0.4.0: a value trial's noted numbers print as readings, not refusals
---------------------------------------------------------------------------

do
    local PRESS = TOWN_PRESS
    local db = {
        version = 1, game = "1.60.1 (70959)", probe = "0.4.0",
        options = { vendor = true, risky = true, auto = false },
        trials = {
            { id = "layout.sizes", area = "Values", label = "Read the sizes", kind = "value" },
            { id = "val.money", area = "Values", label = "Money", kind = "value" },
        },
        situations = {},
        results = { ["layout.sizes"] = { [PRESS] = "readable" }, ["val.money"] = { [PRESS] = "secret" } },
        details = {
            { trial = "layout.sizes", situation = PRESS, result = "readable", message = "MinimapCluster w=230 h=230 scale=1" },
            { trial = "val.money", situation = PRESS, result = "secret", message = "money=secret" },
        },
        log = {},
    }
    local refusals = R.format(db, { detailsOnly = true })
    eq(refusals[1], "Not allowed: 1 entry", "a readable value entry is not a refusal")
    local text = table.concat(refusals, "\n")
    check(not text:find("MinimapCluster", 1, true), "the numbers are not under Not allowed")
    local readings = R.formatReadings(db, select(2, R.situations(db)), R.areas(db))
    eq(readings[1], "Readings and answers: 1 entry")
    check(table.concat(readings, "\n"):find("message: MinimapCluster w=230 h=230 scale=1", 1, true), "the numbers are readings")
end

---------------------------------------------------------------------------
-- Probe 0.3.0: the Errors and Graphics areas, readings, guided answers
---------------------------------------------------------------------------

do
    local PRESS = TOWN_PRESS
    local db = {
        version = 1, game = "1.60.1 (70959)", probe = "0.3.0",
        options = { vendor = true, risky = false, auto = false },
        trials = {
            { id = "err.handler", area = "Errors", label = "Error handler is there", kind = "info" },
            { id = "err.hook", area = "Errors", label = "Hook sees a test error", kind = "action" },
            { id = "err.chain", area = "Errors", label = "Own handler", kind = "action", risky = true },
            { id = "gfx.read", area = "Graphics", label = "Read sparkle and outline settings", kind = "info" },
            { id = "gfx.outlines", area = "Graphics", label = "Outlines off, then restart", kind = "guided" },
            { id = "gfx.icons", area = "Graphics", label = "Interact icons on loot", kind = "guided" },
        },
        situations = {},
        results = {
            ["err.handler"] = { [PRESS] = "function" },
            ["err.hook"] = { [PRESS] = "blocked" },
            ["gfx.read"] = { [PRESS] = "sparkle 0 · outline 2" },
            ["gfx.icons"] = { [PRESS] = "icon seen" },
        },
        details = {
            { trial = "err.handler", situation = PRESS, result = "function", message = "geterrorhandler function; seterrorhandler function", at = "2026-11-20 20:00:00" },
            { trial = "err.hook", situation = PRESS, result = "blocked", func = "hooksecurefunc()" },
            { trial = "gfx.icons", situation = PRESS, result = "icon seen", message = "set: SoftTargetLowPriorityIcons 0 -> 1; old values put back" },
        },
        guided = {
            ["gfx.outlines"] = { stage = "restart", started = "2026-11-20 20:05:00",
                old = { graphicsOutlineMode = "2", raidGraphicsOutlineMode = "2", outlineModeShowLootEffectWhenDisabled = false } },
            ["broken"] = "junk",
        },
        log = {},
    }
    local out = R.format(db)
    eq(out[3], "1 situation, 6 trials, risky trials off, automatic passes off", "the header names the Auto switch")
    local text = table.concat(out, "\n")
    check(text:find("Errors\n  Trial                   S1\n  Error handler is there  function\n  Hook sees a test error  blocked\n  Own handler             -", 1, true),
        "the Errors area table:\n" .. text)
    check(text:find("Graphics\n", 1, true) and text:find("  Interact icons on loot             icon seen", 1, true), "the guided answer is a cell")
    local function section(heading)
        for i, line in ipairs(out) do
            if line:find("^" .. heading) then
                local lines = {}
                for k = i, #out do
                    if out[k] == "" and k > i and out[k + 1] and not out[k + 1]:find("^ ") and not out[k + 1]:find("%(") then break end
                    lines[#lines + 1] = out[k]
                end
                return lines
            end
        end
    end
    eq(section("Guided trials not answered yet"), {
        "Guided trials not answered yet:",
        "  broken: stage unknown",
        "  gfx.outlines: waiting for a full restart of the game, started 2026-11-20 20:05:00; to put back: graphicsOutlineMode 2, "
            .. "outlineModeShowLootEffectWhenDisabled (not on this client), raidGraphicsOutlineMode 2",
    }, "guided trials still waiting, with what they will put back")
    local readings = R.formatReadings(db, select(2, R.situations(db)), R.areas(db))
    eq(readings, {
        "Readings and answers: 2 entries",
        "",
        "Error handler is there (err.handler)",
        "  function in S1 (Gamepad UI on, no fight, open world, from a press), at 2026-11-20 20:00:00",
        "    message: geterrorhandler function; seterrorhandler function",
        "",
        "Interact icons on loot (gfx.icons)",
        "  icon seen in S1 (Gamepad UI on, no fight, open world, from a press)",
        "    message: set: SoftTargetLowPriorityIcons 0 -> 1; old values put back",
    }, "readings and guided answers are their own section")
    local refusals = R.format(db, { detailsOnly = true })
    eq(refusals[1], "Not allowed: 1 entry", "--details lists only the refusals")
    eq(refusals[3], "Hook sees a test error (err.hook)")
    -- An action that could not see its outcome is printed as "can't tell", never as allowed.
    local tell = { trials = { { id = "err.hide", area = "Errors", label = "Hide the error box", kind = "action" } },
        results = { ["err.hide"] = { [PRESS] = "allowed / can't tell" } } }
    local printed = R.format(tell)
    eq(printed[#printed - 2], "  Hide the error box  allowed / can't tell", "a can't-tell cell")
    eq(R.cell(tell, "err.hide", PRESS), "allowed / can't tell")
    eq(R.formatReadings(fixture(), {}, R.areas(fixture())), {}, "a 0.2.0 file has no readings section")
    eq(R.formatGuided(fixture()), {}, "nor a guided section")
end

---------------------------------------------------------------------------
-- Loading the file: text only, nothing reachable from inside it
---------------------------------------------------------------------------

do
    local good = tempFile('\nPocketProbeDB = {\n["version"] = 1,\n["game"] = "1.60.1 (70959)",\n["probe"] = "0.1.0",\n["trials"] = {\n{\n["id"] = "chat.open",\n["area"] = "Chat box",\n["label"] = "Open the chat box",\n["kind"] = "action",\n}, -- [1]\n},\n["situations"] = {\n},\n["results"] = {\n["chat.open"] = {\n["'
        .. TOWN_AUTO .. '"] = "allowed",\n},\n},\n["details"] = {\n},\n["log"] = {\n"16:00:44 pass done", -- [1]\n},\n}\n')
    local changed = tempFile('PocketProbeDB = { results = { ["chat.open"] = { ["' .. TOWN_AUTO .. '"] = "blocked" } } }')
    local loaded, err = R.load(good)
    check(type(loaded) == "table", "a saved file as the game writes it did not load: " .. tostring(err))
    eq(loaded and R.cell(loaded, "chat.open", TOWN_AUTO), "allowed", "a cell from a loaded file")

    local status, out = R.main({ good })
    eq(status, 0, "exit status for a good file")
    eq(out and out[3], "1 situation, 1 trial", "the counts printed for a good file")
    status, out = R.main({ good, "--markdown" })
    eq({ status, out and out[#out] }, { 0, "| Open the chat box | allowed |" }, "--markdown from the command")
    status, out = R.main({ "--details", good })
    eq({ status, out and out[1] }, { 0, "Not allowed: 0 entries" }, "--details from the command, option first")
    status, out = R.main({ good, "--log" })
    eq({ status, out and out[2] }, { 0, "16:00:44 pass done" }, "--log from the command")
    status, out = R.main({ good, "--diff", changed })
    eq({ status, out and out[#out], out and out[#out - 2] }, { 0, "1 cell differs.", "    Gamepad UI on, no fight, open world, automatic: allowed -> blocked" }, "--diff from the command")
    eq((R.main({ good, "--diff" })), 2, "--diff with no file is a usage error")
    eq((R.main({ good, "--diff", good .. ".missing" })), 1, "--diff with a missing file")
    eq((R.main({ good, "--markdown", "--details" })), 2, "two ways of printing at once is a usage error")
    eq((R.main({})), 2, "no file is a usage error")
    eq((R.main({ good, "--bogus" })), 2, "an unknown option is a usage error")
    eq((R.main({ good, good })), 2, "two files without --diff is a usage error")

    for name, body in pairs({
        os = "PocketProbeDB = { log = { os.date() } }",
        io = "local f = io.open('/etc/hosts') PocketProbeDB = {}",
        require = "require('os') PocketProbeDB = {}",
        loadstring = "loadstring('return 1')() PocketProbeDB = {}",
        getfenv = "getfenv(0).os.exit(0) PocketProbeDB = {}",
        dofile = "dofile('/etc/hosts') PocketProbeDB = {}",
    }) do
        local got, reason = R.load(tempFile(body))
        check(got == nil and type(reason) == "string", "a file that uses " .. name .. " was loaded")
    end

    local empty = R.load(tempFile("PocketProbeDB = { seen = _G, count = (function() local n = 0 return n end)() }"))
    check(type(empty) == "table" and empty.seen == nil, "the file can see the real globals")

    local compiled = tempFile(string.dump(function() PocketProbeDB = {} end))
    local got, reason = R.load(compiled)
    check(got == nil and tostring(reason):find("compiled", 1, true), "compiled code was loaded")

    check(R.load(tempFile("this is not lua")) == nil, "a file that is not Lua was loaded")
    check(R.load(tempFile("PocketProbeDB = {\n[\"trials\"] = {\n{ [\"id\"] = \"chat.op")) == nil, "a file cut off part-way was loaded")
    check(R.load(tempFile("PocketEssentialsDB = {}")) == nil, "a file without PocketProbeDB was loaded")
    check(R.load(tempFile("PocketProbeDB = 5")) == nil, "a PocketProbeDB that is not a table was loaded")
    check(R.load(tempFile("")) == nil, "an empty file was loaded")
    local missing = good .. ".missing"
    check(R.load(missing) == nil, "a missing file was loaded")
    eq((R.main({ missing })), 1, "exit status for a missing file")

    -- A file that never finishes is stopped.
    local stuck, why = R.load(tempFile("while true do end"))
    check(stuck == nil and tostring(why):find("too long", 1, true), "a file that never finishes was not stopped: " .. tostring(why))
end

for _, path in ipairs(temps) do os.remove(path) end

if #failures > 0 then
    for _, f in ipairs(failures) do print("FAIL: " .. f) end
    os.exit(1)
end
print(string.format("Read-probe: %d checks", checks))
