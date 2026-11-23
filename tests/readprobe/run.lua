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
-- Probe 0.6.0: the performance report (--perf, --perf --diff)
-- Source: docs/superpowers/specs/2026-11-21-perf-recorder.md, section C. The
-- sample lines are written by hand in the layout at the top of
-- probe/PocketProbe/Perf.lua; the numbers are chosen so the sums are round.
---------------------------------------------------------------------------

local function perfRun()
    return {
        started = "2026-11-22 14:00:00", ended = "2026-11-22 14:00:45", why = "stopped", t0 = 500, interval = 15,
        addon = "0.11.0", profiler = "on", features = true, reloads = 1,
        keys = { "questicons", "core" },
        feat = {
            ["*"] = { ms = 24, calls = 800, max = 6.5 },
            questicons = { ms = 19, calls = 600, max = 6.5, events = {
                QUEST_LOG_UPDATE = { ms = 12, calls = 20 }, OnUpdate = { ms = 5, calls = 570 },
                BAG_UPDATE = { ms = 1.5, calls = 8 }, SMALLEST = { ms = 0.5, calls = 2 }, junk = "x" } },
            core = { ms = 5, calls = 200, max = 0.2, events = { BAG_UPDATE = { ms = 5, calls = 200 } } },
            broken = "junk",
        },
        session = { pe = { avg = 0.05, peak = 3.5 }, all = { avg = 0.5, peak = 20 } },
        samples = {
            "t=0;dt=0;a=s;fps=60;mem=800,10000,300",
            "t=15;dt=15;a=ms;fps=60;mem=820,10000,300;pe=6,300,1.5;f=1:4:200:1.5,2:2:100:0.2;p=0.03,4,1,0,0,0,0,0;all=0.3,20,2,0;app=16.6",
            "t=30;dt=15;a=cm;fps=40;mem=860,10000,310;pe=18,500,6.5;f=1:15:400:6.5,2:3:100:0.2;p=0.05,10,2,1,0,0,0,0;all=0.5,30,4,1;app=20",
            7, "not a sample",
            "t=45;dt=15;a=s;fps=60;mem=830,10000,310;p=0.01,0,0,0,0,0,0,0;all=0.2,5,0,0;app=16.6",
        },
    }
end

local function perfFile(runs)
    return { version = 1, game = "1.60.1 (71037)", probe = "0.6.0", perf = { on = false, stopped = true, runs = runs } }
end

local function has(lines, part)
    return table.concat(lines, "\n"):find(part, 1, true) ~= nil
end

do
    local s = R.perfSample("t=30;dt=15;a=cm;fps=40;mem=860,,310;pe=18,500,6.5;f=1:15:400:6.5,2:3:100:0.2;p=0.05,10,2,1;all=0.5,30,4,1;app=20")
    eq({ s.t, s.dt, s.tags, s.fps, s.app }, { 30, 15, "cm", 40, 20 }, "a sample line's plain fields")
    eq({ s.mem[1], s.mem[2] == nil, s.mem[3] }, { 860, true, 310 }, "an addon that was not read leaves a gap in the memory list")
    eq({ s.pe[1], s.pe[2], s.pe[3], s.p[2], s.all[3] }, { 18, 500, 6.5, 10, 4 }, "a sample line's number lists")
    eq({ #s.f, s.f[1].key, s.f[1].ms, s.f[2].calls, s.f[2].slowest }, { 2, 1, 15, 100, 0.2 }, "a sample line's per-feature entries")
    eq(R.perfSample(7), nil, "a sample that is not text is left out")
    eq(R.perfSample("hello"), nil, "text that is not a sample is left out")
end

do
    local sum = R.perfSummary(perfRun())
    eq({ sum.samples, sum.seconds, sum.total.ms, sum.total.calls, sum.total.slowest }, { 4, 45, 24, 800, 6.5 }, "a run's totals")
    eq(sum.total.frames, 2400, "frames estimated from the frame rate at both ends of each sample")
    eq(string.format("%.4f", sum.msPerFrame), "0.0100", "ms per frame is the total over the estimated frames")
    eq({ sum.total.over[1], sum.total.over[2], sum.total.over[3] }, { 14, 3, 1 }, "frames over 1, 5 and 10 ms")
    eq({ string.format("%.3f", sum.recent), string.format("%.1f", sum.share) }, { "0.030", "9.0" }, "recent average and share of all addons")
    local m = sum.memory[1]
    eq({ m.start, m.min, m.max, m.finish, m.growth }, { 800, 800, 860, 830, 40 }, "Pocket Essentials' memory: start, least, most, end, growth per minute")
    eq({ sum.featureRows[1].key, sum.featureRows[2].key, #sum.featureRows }, { "questicons", "core", 2 }, "features sorted by total time; junk left out")
    eq({ sum.featureRows[1].events[1].name, sum.featureRows[1].events[2].name, sum.featureRows[1].events[3].name },
        { "QUEST_LOG_UPDATE", "OnUpdate", "BAG_UPDATE" }, "a feature's events, the busiest first")
    eq({ sum.byTag.c.seconds, sum.byTag.c.ms, sum.byTag.c.frames }, { 15, 18, 750 }, "the fight's share of the run")
    eq({ sum.byTag.m.seconds, sum.byTag.s.seconds, sum.byTag.s.ms }, { 30, 30, 6 }, "a sample counts under every activity seen in it")
    eq(sum.byTag.w, nil, "an activity never seen has no row")
end

do
    local out = R.formatPerf(perfFile({ perfRun() }))
    eq({ out[1], out[2], out[3] }, { "Performance recording", "Game 1.60.1 (71037), probe 0.6.0", "1 run in this file, the newest last" }, "the report's heading")
    for _, part in ipairs({
        "Run 1 of 1: started 2026-11-22 14:00:00, ended 2026-11-22 14:00:45 (stopped with Stop)",
        "45 s recorded, 4 samples (one every 15 s), Pocket Essentials 0.11.0, carried on over 1 reload",
        "per frame, average  0.01 ms (frames estimated from the frame rate: about 2400)",
        "total               24 ms in 800 runs (32 ms per minute)",
        "slowest single run  6.5 ms",
        "recent average             0.03 ms per frame (the mean of 3 readings)",
        "frames over 1 ms           14 (18.67 per minute)",
        "frames over 5 ms           3 (4 per minute)",
        "frames over 10 ms          1 (1.33 per minute)",
        "share of all addons' time  9 %",
        "since the game started     average 0.05 ms per frame, peak 3.5 ms",
        "Memory (KB)        start  least  most   end    growth per minute",
        "Pocket Essentials  800    800    860    830    +40",
        "QuestieDB          10000  10000  10000  10000  0",
        "Frame rate: average 53.3, lowest 40",
        "Feature     Total ms  Runs  ms per run  Slowest ms  Busiest events (ms / runs)",
        "questicons  19        600   0.032       6.5         QUEST_LOG_UPDATE 12 / 20, OnUpdate 5 / 570, BAG_UPDATE 1.5 / 8",
        "core        5         200   0.025       0.2         BAG_UPDATE 5 / 200",
        "Activity        Time  ms per frame  Slowest ms  Over 5 ms per min  Frame rate  Busiest feature",
        "in a fight      15 s  0.024         6.5         8                  40          questicons",
        "moving          30 s  0.0145        6.5         6                  50          questicons",
        "standing still  30 s  0.0036        1.5         2                  60          questicons",
        "In plain words (the newest run)",
        -- Probe 0.7.0: a run under 10 minutes gets no verdict.
        "Too short to judge: 45 s of samples to go on (10 min needed).",
    }) do
        check(has(out, part), "--perf: the report lacks \"" .. part .. "\"\n" .. table.concat(out, "\n"))
    end
    check(not has(out, "Overall:"), "--perf: no verdict for a run this short")
    check(not has(out, "SMALLEST"), "--perf: only the three busiest events are printed")
    check(not has(out, "in a dungeon"), "--perf: an activity that was never seen has no row")
    -- The words themselves, for this run's numbers.
    local words = R.perfVerdict(R.perfSummary(perfRun()))
    for _, part in ipairs({
        "Time: light. Pocket Essentials used about 0.01 ms of each frame, by its own counters (light is under 0.1 ms, heavy is 1 ms or more).",
        "Memory: light. Pocket Essentials held at most 0.84 MB (light is under 2 MB) and did not keep growing.",
        "Hitches: some. 3 frames spent over 5 ms in Pocket Essentials in 45 s (few is under 1 a minute).",
        "Overall: in between.",
    }) do
        check(has(words, part), "the plain words lack \"" .. part .. "\"\n" .. table.concat(words, "\n"))
    end
end

do
    -- Profiler off: the hook's numbers, memory and frame rate still print.
    local off = perfRun()
    off.profiler, off.session = "off", nil
    for i, line in ipairs(off.samples) do
        if type(line) == "string" then off.samples[i] = line:gsub(";p=.*$", "") end
    end
    local out = R.formatPerf(perfFile({ off }))
    check(has(out, "profiler off"), "profiler off: the report says so")
    check(has(out, "per frame, average  0.01 ms"), "profiler off: the hook's numbers are still there")
    local words = R.perfVerdict(R.perfSummary(off))
    check(has(words, "Hitches: cannot tell (profiler off)."), "profiler off: no word on hitches")
    check(has(words, "Overall: light."), "profiler off: the verdict uses what there is")
    check(not has(out, "frames over 5 ms"), "profiler off: no profiler rows")
    -- No profiler on the client.
    off.profiler = "missing"
    check(has(R.formatPerf(perfFile({ off })), "The game's profiler: not on this client"), "a client without the profiler: the report says so")

    -- An older Pocket Essentials: no per-feature numbers; the time comes from the profiler.
    local old = perfRun()
    old.features, old.feat, old.keys = false, {}, {}
    for i, line in ipairs(old.samples) do
        if type(line) == "string" then old.samples[i] = line:gsub(";pe=[^;]*", ""):gsub(";f=[^;]*", "") end
    end
    out = R.formatPerf(perfFile({ old }))
    check(has(out, "no per-feature numbers"), "no hook: the report says there are no per-feature numbers")
    check(not has(out, "Per feature, the busiest first"), "no hook: no per-feature table")
    check(has(R.perfVerdict(R.perfSummary(old)), "Time: light. Pocket Essentials used about 0.03 ms of each frame, by the game's profiler"),
        "no hook: the time comes from the profiler")
    check(has(out, "frames over 5 ms           3 (4 per minute)"), "no hook: the profiler rows still print")

    -- Heavy: a millisecond a frame, or memory that keeps growing.
    local heavy = perfRun()
    heavy.samples[2] = heavy.samples[2]:gsub("pe=6,", "pe=6000,")
    words = R.perfVerdict(R.perfSummary(heavy))
    check(has(words, "Time: heavy.") and has(words, "Overall: heavy."), "a millisecond a frame is heavy")
    local growing = perfRun()
    growing.samples = { "t=0;dt=0;a=s;fps=60;mem=800,,", "t=300;dt=300;a=s;fps=60;mem=1100,,", "t=600;dt=300;a=s;fps=60;mem=1500,,;pe=1,1,1" }
    out = R.formatPerf(perfFile({ growing }))
    check(has(out, "Memory: heavy. Pocket Essentials held at most 1.46 MB (light is under 2 MB) and kept growing, by about 70 KB a minute."),
        "memory that keeps growing is heavy\n" .. table.concat(out, "\n"))
    check(has(out, "QuestieDB          -      -      -     -     not loaded or not read"), "an addon that is not loaded has an empty memory row")
    check(has(out, "10 min 0 s recorded"), "minutes and seconds")

    -- What the client lacked, a run that filled up, a run still going, a run too short.
    local odd = perfRun()
    odd.missing = { GetFramerate = true, ["C_Timer.NewTicker"] = true }
    odd.why, odd.ended = "full", "2026-11-22 16:00:00"
    out = R.formatPerf(perfFile({ odd }))
    check(has(out, "Not on this client, so left out: C_Timer.NewTicker, GetFramerate"), "the names the client lacked are listed")
    check(has(out, "(stopped by itself after 2 hours)"), "a run that filled up says so")
    local going = perfRun()
    going.why, going.ended = nil, nil
    check(has(R.formatPerf(perfFile({ going })), "still running when the file was written"), "a run with no end says so")
    local short = { started = "2026-11-22 15:00:00", samples = { "t=0;dt=0;a=s" } }
    out = R.formatPerf(perfFile({ perfRun(), "junk", short }))
    check(has(out, "2 runs in this file") and has(out, "Run 2 of 2: started 2026-11-22 15:00:00"), "runs that are not tables are left out")
    check(has(out, "Too short: no full sample yet.") and has(out, "Too short to say anything."), "a run with one sample is too short")

    -- Files without recordings, and odd types, print and do not raise.
    for name, db in pairs({
        ["an empty file"] = {}, ["a 0.5.0 file"] = { probe = "0.5.0", results = {} },
        ["perf of the wrong type"] = { perf = "x" }, ["runs of the wrong type"] = { perf = { runs = 5 } },
    }) do
        local ok, lines = pcall(R.formatPerf, db)
        check(ok and has(lines, "No recording in this file."), name .. ": --perf says there is no recording")
    end
    local ok, lines = pcall(R.formatPerf, perfFile({ { started = 5, samples = "x", feat = "y", keys = 3, missing = "z", session = 1, reloads = "a" },
        { samples = { "t=x;dt=y;a=;fps=;mem=a,b;pe=;f=junk;p=,,", "t=15;dt=15;a=zz;f=9:1:1:1" }, features = true, feat = { k = { ms = "a", events = { e = 1 } } } } }))
    check(ok, "--perf: odd types do not raise: " .. tostring(lines))
    -- The ordinary report of a file that also holds recordings is unchanged by them.
    local both = fixture()
    local before = table.concat(R.format(both), "\n")
    both.perf = perfFile({ perfRun() }).perf
    eq(table.concat(R.format(both), "\n"), before, "the trial tables do not change when the file also holds recordings")
end

do
    -- --perf --diff: the newest run of each file, side by side.
    local after = perfRun()
    after.started, after.addon = "2026-11-23 09:00:00", "0.11.1"
    after.samples[2] = after.samples[2]:gsub("pe=6,300,1.5", "pe=3,300,1.5")
    after.samples[3] = "t=30;dt=15;a=cm;fps=40;mem=840,10000,310;pe=9,500,2;f=1:7:400:2,2:2:100:0.2;p=0.02,5,0,0,0,0,0,0;all=0.5,30,4,1;app=20"
    after.feat.questicons.ms, after.feat.questicons.max = 9.5, 2
    after.feat.core = nil
    after.feat.bags = { ms = 1.5, calls = 3, max = 0.9 }
    local out = R.perfDiff(perfFile({ { started = "old", samples = {} }, perfRun() }), perfFile({ after }), "before.lua", "after.lua")
    for _, part in ipairs({
        "Comparing performance recordings (the newest run of each file)",
        "before: before.lua (started 2026-11-22 14:00:00, ended 2026-11-22 14:00:45 (stopped with Stop), 45 s, Pocket Essentials 0.11.0)",
        "after:  after.lua (started 2026-11-23 09:00:00,",
        "Headline                                        Before  After  Change",
        "ms per frame, average                           0.01    0.005  -50 %",
        "ms per minute                                   32      16     -50 %",
        "slowest single run, ms                          6.5     2      -69 %",
        "profiler: frames over 5 ms per minute           4       1.33   -67 %",
        "profiler: frames over 10 ms per minute          1.33    0      -100 %",
        "Pocket Essentials memory, most, KB              860     840    -2 %",
        "frame rate, lowest                              40      40     same",
        "Feature     Before  After  Change  ms per run before  after  Slowest ms before  after",
        "questicons  25.3    12.7   -50 %   0.032              0.016  6.5                2",
        "core        6.7     -      -       0.025              -      0.2                -",
        "bags        -       2      -       -                  0.5    -                  0.9",
        -- Probe 0.7.0: both runs are under 10 minutes.
        "before: too short to judge (45 s of samples to go on, 10 min needed)",
        "after: too short to judge (45 s of samples to go on, 10 min needed)",
    }) do
        check(has(out, part), "--perf --diff: the comparison lacks \"" .. part .. "\"\n" .. table.concat(out, "\n"))
    end
    out = R.perfDiff(perfFile({ perfRun() }), {}, "a.lua", "b.lua")
    check(has(out, "after: b.lua has no recording.") and has(out, "Nothing to compare."), "--perf --diff: a file with no recording")
    local old = perfRun()
    old.features = false
    check(has(R.perfDiff(perfFile({ old }), perfFile({ perfRun() })), "Per feature: no per-feature numbers in the first file."),
        "--perf --diff: one side without per-feature numbers")
end

do
    -- The command: --perf alone or with --diff; an old file still prints both ways.
    local function lua(v, indent)
        if type(v) == "string" then return string.format("%q", v) end
        if type(v) ~= "table" then return tostring(v) end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "] = " .. lua(x)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    local clean = perfRun()
    clean.samples = { clean.samples[1], clean.samples[2], clean.samples[3], clean.samples[6] }
    clean.feat.broken, clean.feat.questicons.events.junk = nil, nil
    local path = tempFile("PocketProbeDB = " .. lua(perfFile({ clean })))
    local status, out = R.main({ path, "--perf" })
    eq(status, 0, "read-probe --perf prints a 0.6.0 file")
    check(has(out, "Run 1 of 1") and has(out, "In plain words") and has(out, "Too short to judge"),
        "read-probe --perf prints the run and the plain words")
    status, out = R.main({ path, "--perf", "--diff", path })
    eq(status, 0, "read-probe --perf --diff compares two files")
    check(has(out, "ms per frame, average") and has(out, "same"), "read-probe --perf --diff prints the comparison")
    status, out = R.main({ path })
    eq(status, 0, "a 0.6.0 file prints without --perf too")
    check(has(out, "Restriction probe") and not has(out, "Performance recording"), "without --perf the trial results print")
    eq((R.main({ path, "--perf", "--log" })), 2, "--perf does not go with --log")
    eq((R.main({ path, "--perf", "--markdown" })), 2, "--perf does not go with --markdown")
    eq((R.main({ "--perf" })), 2, "--perf needs a file")
    local oldFile = tempFile("PocketProbeDB = { probe = \"0.5.0\", trials = { { id = \"cd.sweep.object\", area = \"Our own windows\", label = \"Sweep\", kind = \"action\" } }, "
        .. "results = { [\"cd.sweep.object\"] = { [\"gp=on fight=no rest=------ where=world trig=press\"] = \"allowed\" } } }")
    status, out = R.main({ oldFile, "--perf" })
    eq(status, 0, "--perf on a 0.5.0 file is not an error")
    check(has(out, "No recording in this file."), "--perf on a 0.5.0 file says there is no recording")
    status, out = R.main({ oldFile })
    check(status == 0 and has(out, "allowed"), "a 0.5.0 file still prints its results")
end

---------------------------------------------------------------------------
-- Probe 0.7.0: the report's fixes (spec 2026-11-23-pocket-probe-0.7.0.md,
-- section 5) and the watchers' table (--details)
---------------------------------------------------------------------------

-- A quiet run: one sample every 15 s up to `last` seconds; special[t] replaces a line.
local function quietRun(last, special)
    local samples = {}
    for t = 0, last, 15 do
        samples[#samples + 1] = special[t] or ("t=" .. t .. ";dt=" .. (t == 0 and 0 or 15) .. ";a=s;fps=60;mem=800,,;pe=0.6,10,0.1")
    end
    return { started = "2026-11-23 12:00:00", ended = "2026-11-23 12:15:00", why = "stopped", interval = 15, features = true,
        profiler = "missing", keys = {}, feat = {}, samples = samples }
end

do
    -- least / kept growing / heavy skip missing memory (0 in a 0.6.0 file, empty in a 0.7.0 one).
    local run = quietRun(750, {
        [300] = "t=300;dt=15;a=s;fps=60;mem=0,,;pe=0.6,10,0.1",
        [315] = "t=315;dt=15;a=s;fps=60;mem=,,;pe=0.6,10,0.1",
    })
    local sum = R.perfSummary(run)
    eq({ sum.memory[1].min, sum.memory[1].max }, { 800, 800 }, "a memory reading of 0 or none is left out of least and most")
    local out = R.formatPerf(perfFile({ run }))
    check(has(out, "Pocket Essentials  800    800    800   800  0"), "least is not 0\n" .. table.concat(out, "\n"))
    check(has(out, "Memory: light.") and has(out, "did not keep growing"), "missing readings do not make memory heavy or growing")
end

do
    -- Reloads: listed in minutes, and the 30 s after each is left out of the plain words.
    local heavy = "fps=60;mem=9000,,;pe=60000,10,50"
    local run = quietRun(750, {
        [300] = "t=300;dt=0;a=sr;fps=60;mem=,,",
        [315] = "t=315;dt=15;a=s;" .. heavy,
        [330] = "t=330;dt=15;a=s;" .. heavy,
        -- A 0.6.0 file has no r: a sample with dt=0 after the first is a reload too.
        [600] = "t=600;dt=0;a=s;fps=60;mem=0,,",
    })
    local out = R.formatPerf(perfFile({ run }))
    check(has(out, "Reloads at: 5 min, 10 min"), "the reloads are listed\n" .. table.concat(out, "\n"))
    check(has(out, "9000"), "the tables still show everything")
    check(has(out, "Left out of these words: the 30 s after each of 2 reloads."), "the plain words say what they leave out\n" .. table.concat(out, "\n"))
    check(has(out, "Time: light.") and has(out, "Memory: light.") and has(out, "Overall: light."),
        "the stretch after a reload does not colour the words\n" .. table.concat(out, "\n"))
    local plain = R.perfSummary(run, { plain = true })
    eq(plain.seconds, 660, "720 s less the 30 s after each reload")
    -- The same stretch counted (no reload mark, dt=15): it is heavy.
    local counted = quietRun(750, { [315] = "t=315;dt=15;a=s;" .. heavy, [330] = "t=330;dt=15;a=s;" .. heavy })
    check(has(R.formatPerf(perfFile({ counted })), "Time: heavy."), "without the reload the same numbers are heavy")
end

do
    -- Under 10 minutes left: too short to judge.
    local out = R.formatPerf(perfFile({ quietRun(300, {}) }))
    check(has(out, "Too short to judge: 5 min 0 s of samples to go on (10 min needed)."), "a 5 minute run\n" .. table.concat(out, "\n"))
    check(not has(out, "Overall:"), "no verdict")
    -- 10 min 15 s, a reload in it (its own sample has dt=0): 9 min 30 s left.
    out = R.formatPerf(perfFile({ quietRun(615, { [300] = "t=300;dt=0;a=sr;fps=60;mem=800,," }) }))
    check(has(out, "Too short to judge: 9 min 30 s of samples to go on (10 min needed), after leaving out the 30 s after each of 1 reload."),
        "too short once the reload is left out\n" .. table.concat(out, "\n"))
    -- Exactly 10 minutes is enough.
    check(has(R.formatPerf(perfFile({ quietRun(600, {}) })), "Overall: light."), "10 minutes is enough")
end

do
    -- Samples marked p (the fight tests' pause) are left out of the plain words, and are not reloads.
    local run = quietRun(750, { [300] = "t=300;dt=0;a=csp;fps=60;mem=5000,," })
    local out = R.formatPerf(perfFile({ run }))
    check(not has(out, "Reloads at"), "a pause is not a reload")
    check(has(out, "5000"), "the table shows the reading")
    check(has(out, "Memory: light."), "the pause's reading is left out of the words\n" .. table.concat(out, "\n"))
    check(has(out, "Left out of these words: 1 pause for the fight tests."), "the words say so\n" .. table.concat(out, "\n"))
    -- In --perf --diff too.
    local diff = R.perfDiff(perfFile({ run }), perfFile({ quietRun(300, {}) }), "a.lua", "b.lua")
    check(has(diff, "before: light") and has(diff, "after: too short to judge (5 min 0 s of samples to go on, 10 min needed)"),
        "--perf --diff uses the same words\n" .. table.concat(diff, "\n"))
end

local function watchFile()
    local db = fixture()
    db.watch = {
        { started = "2026-11-23 11:00:00", ended = "2026-11-23 11:05:00", why = "reload", bar = { missing = "PageUnit" },
          press = { missing = "the bars' buttons", hooked = 0 }, events = { _secs = { c = 0, o = 300 }, missing = "UPDATE_BONUS_ACTIONBAR" },
          sweep = { missing = "the main bar" } },
        { started = "2026-11-23 12:00:00", ended = "2026-11-23 12:30:00", why = "disarmed",
          bar = { main = { c = 3, o = 10 }, left = { c = 2, o = 0 }, both = { c = 1, o = 1 }, first = { "t=0;left;o", "t=5;main;o" } },
          press = { main = { down = { c = 5, o = 3 }, up = { c = 5, o = 3 } }, left = { down = { c = 1, o = 0 }, other = { c = 2, o = 0 } },
              kind = "boolean / secret", hooked = 32 },
          events = { ACTIONBAR_UPDATE_COOLDOWN = { c = 120, o = 30 }, SPELL_UPDATE_COOLDOWN = { c = 60, o = 0 }, _secs = { c = 120, o = 1680 } },
          sweep = { result = "allowed", shownByItself = "yes", durClass = "readable", screenshot = "taken", t = 95 } },
        "junk",
        { started = "2026-11-23 13:00:00", bar = {}, press = {}, events = { _secs = { c = 0, o = 0 } }, sweep = {} },
    }
    return db
end

do
    local db = watchFile()
    local out = R.format(db, { detailsOnly = true })
    for _, part in ipairs({
        "Watch my next fights: 3 armings, the newest last",
        "  Arming 1: started 2026-11-23 11:00:00, ended 2026-11-23 11:05:00 (ended by a reload or a logout)",
        "    Active bar: not watched (not found: PageUnit)",
        "    Presses: not watched (not found: the bars' buttons)",
        "    Events not on this client: UPDATE_BONUS_ACTIONBAR",
        "    Cooldown sweep: not tried (not found: the main bar)",
        "  Arming 2: started 2026-11-23 12:00:00, ended 2026-11-23 12:30:00 (Disarm)",
        "    Time: 2 min 0 s in fights, 28 min 0 s out of them",
        "    Active bar, in a fight / out of one: main 3 / 10, left 2 / 0, both 1 / 1",
        "    First changes (seconds since Arm; bar; c in a fight, o out of one): t=0;left;o, t=5;main;o",
        "    Presses (down / up), in a fight: main 5 / 5, left 1 / 0 (2 unreadable); out of one: main 3 / 3",
        "    \"pressed\" read as: boolean / secret; buttons hooked: 32",
        "    Events per minute, in a fight / out of one (the counts in brackets):",
        "ACTIONBAR_UPDATE_COOLDOWN  60 / 1.1  (120 / 30)",
        "SPELL_UPDATE_COOLDOWN      30 / 0    (60 / 0)",
        "    Cooldown sweep: allowed, frame shown by itself yes, duration afterwards readable, screenshot taken, 1 min 35 s after Arm",
        "  Arming 3: started 2026-11-23 13:00:00 (still armed when the file was written)",
        "    Cooldown sweep: not tried (nothing was on cooldown in a fight)",
    }) do
        check(has(out, part), "--details: the watch table lacks \"" .. part .. "\"\n" .. table.concat(out, "\n"))
    end
    check(has(R.format(db), "Watch my next fights: 3 armings"), "the full report has the watch table too")
    -- An old file without a watch table prints as before.
    local old = fixture()
    local before, beforeDetails = table.concat(R.format(old), "\n"), table.concat(R.format(old, { detailsOnly = true }), "\n")
    check(not before:find("Watch my next fights", 1, true), "no watch table in an old file")
    old.watch = {}
    eq(table.concat(R.format(old), "\n"), before, "an empty watch table changes nothing")
    eq(table.concat(R.format(old, { detailsOnly = true }), "\n"), beforeDetails, "nor --details")
    old.watch = "junk"
    local ok = pcall(R.format, old, { detailsOnly = true })
    check(ok, "a watch table of the wrong type does not raise")
end

---------------------------------------------------------------------------
-- Probe 0.5.0: a saved file holding the new ids prints like any other
---------------------------------------------------------------------------

do
    local FIGHT_PRESS = "gp=on fight=yes rest=c----- where=world trig=press"
    local db = {
        version = 1, game = "1.60.1 (71037)", probe = "0.5.0",
        options = { vendor = true, risky = true, auto = false },
        trials = {
            { id = "cd.duration", area = "Our own windows", label = "Read the main bar's cooldown duration objects", kind = "value" },
            { id = "cd.sweep.object", area = "Our own windows", label = "Cooldown sweep, duration object", kind = "action" },
            { id = "cd.sweep.numbers", area = "Our own windows", label = "Cooldown sweep, numbers", kind = "action" },
            { id = "bars.fade", area = "Blizzard windows", label = "Fade the left bar to nothing and back", kind = "action", risky = true },
            { id = "bars.park", area = "Blizzard windows", label = "Park the main bar", kind = "guided", risky = true },
            { id = "bars.fadecast", area = "Blizzard windows", label = "Fade the main bar", kind = "guided", risky = true },
        },
        situations = {},
        results = {
            ["cd.duration"] = { [FIGHT_PRESS] = "readable" }, ["cd.sweep.object"] = { [FIGHT_PRESS] = "allowed" },
            ["cd.sweep.numbers"] = { [FIGHT_PRESS] = "blocked" }, ["bars.fade"] = { [FIGHT_PRESS] = "allowed" },
            ["bars.park"] = { [TOWN_PRESS] = "spell cast" }, ["bars.fadecast"] = { [FIGHT_PRESS] = "nothing happened" },
        },
        details = {
            { trial = "cd.duration", situation = FIGHT_PRESS, result = "readable", message = "buttons 8, with a spell 4; duration readable 4" },
            { trial = "cd.sweep.numbers", situation = FIGHT_PRESS, result = "blocked", func = "SetCooldown()",
                message = "slot on cooldown yes; sweep frame shown by itself no; duration afterwards readable", inPress = false },
            { trial = "bars.park", situation = TOWN_PRESS, result = "spell cast",
                message = "set: top bar anchor moved up 3000; main bar off screen yes; before: top shown 683,97 on screen; bars shown and on screen: 4; "
                    .. "after: top shown 683,3097 off screen; bars shown and on screen: 3, screenshots: 2; started 2026-11-22 20:00:00; old values put back" },
            { trial = "bars.fadecast", situation = FIGHT_PRESS, result = "nothing happened",
                message = "set: main bar see-through 1 -> 0, screenshots: 2, still invisible at the answer: yes; started 2026-11-22 20:05:00; old values put back" },
        },
        guided = { ["bars.park"] = { stage = "prepare", started = "2026-11-22 20:10:00", old = {} } },
        log = { "20:06:00 fight tests: bars.spells secret, cd.duration readable, cd.sweep.object allowed, cd.sweep.numbers blocked" },
    }
    local text = table.concat(R.format(db), "\n")
    for _, part in ipairs({ "Our own windows", "Blizzard windows", "Cooldown sweep, numbers", "blocked", "spell cast", "nothing happened",
        "function: SetCooldown()", "sweep frame shown by itself no", "bars shown and on screen: 3", "screenshots: 2",
        "still invisible at the answer: yes", "duration readable 4", "bars.park: prepare, started 2026-11-22 20:10:00" }) do
        check(text:find(part, 1, true), "0.5.0 file: the output lacks \"" .. part .. "\"")
    end
    local refusals = R.format(db, { detailsOnly = true })
    eq(refusals[1], "Not allowed: 1 entry", "only the blocked sweep is a refusal; the answers and the reading are not")
    local readings = R.formatReadings(db, select(2, R.situations(db)), R.areas(db))
    eq(readings[1], "Readings and answers: 3 entries", "the reading and the two answers")
    local log = R.format(db, { logOnly = true })
    check(log[2] and log[2]:find("cd.sweep.numbers blocked", 1, true), "the fight tests' log line prints whole")
    local path = tempFile("PocketProbeDB = { probe = \"0.5.0\", trials = { { id = \"cd.sweep.object\", area = \"Our own windows\", "
        .. "label = \"Cooldown sweep\", kind = \"action\" } }, results = { [\"cd.sweep.object\"] = { [\"" .. FIGHT_PRESS .. "\"] = \"allowed\" } } }")
    local status, out = R.main({ path })
    eq(status, 0, "read-probe prints a 0.5.0 file")
    check(type(out) == "table" and table.concat(out, "\n"):find("Cooldown sweep", 1, true), "its rows are in the output")
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
