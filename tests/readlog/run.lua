-- Tests for the debug log reader (scripts/read-log.lua).
--
--   luajit tests/readlog/run.lua <repo root>
--
-- Sources: docs/superpowers/specs/2026-11-17-debug-log.md ("scripts/read-log.sh <file> prints
-- the log and the Errors page as plain text, one block per play session"; "the saved file is
-- loaded with no access to files or the system") and Core.lua "Debug log" (the ring: once
-- full, the oldest line is at `next`).
-- Saved files for the loader are written under the system temp folder and removed.
--
-- Prints "Read-log: N checks" on pass; exit 1 and FAIL: lines otherwise.
local root = arg[1]
if not root then
    io.stderr:write("usage: luajit tests/readlog/run.lua <repo root>\n")
    os.exit(2)
end

local R = dofile(root .. "/scripts/read-log.lua")
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
-- Order: the ring is unwrapped from `next`
---------------------------------------------------------------------------

eq(R.ordered({ lines = { "a", "b", "c" }, next = 4 }), { "a", "b", "c" }, "a log that has not wrapped reads from slot 1")
eq(R.ordered({ lines = { "d", "e", "b", "c" }, next = 3 }), { "b", "c", "d", "e" }, "a wrapped log reads from next")
eq(R.ordered({ lines = { "e", "b", "c", "d" }, next = 2 }), { "b", "c", "d", "e" }, "wrapped, next at slot 2")
eq(R.ordered({ lines = { "a", "b", "c" }, next = 1 }), { "a", "b", "c" }, "full with next back at slot 1")
eq(R.ordered({ lines = {}, next = 1 }), {}, "an empty log")
eq(R.ordered(nil), {}, "no debug table")
eq(R.ordered({ on = true }), {}, "a debug table with no lines")
eq(R.ordered({ lines = { "a", "b" } }), { "a", "b" }, "no next")
eq(R.ordered({ lines = { "a", "b" }, next = "2" }), { "a", "b" }, "next is not a number")
eq(R.ordered({ lines = { "a", "b" }, next = 1.5 }), { "a", "b" }, "next is not a whole number")
eq(R.ordered({ lines = { "a", 7, "b" }, next = 4 }), { "a", "b" }, "an entry that is not text is left out")

-- The size the addon uses: 10,000 lines, wrapped part-way.
do
    local lines = {}
    for i = 1, 10000 do lines[i] = "line " .. (i <= 250 and 10000 + i or i) end   -- slots 1..250 were written again
    local got = R.ordered({ lines = lines, next = 251 })
    eq(#got, 10000, "a full log keeps every line")
    eq(got[1], "line 251", "the oldest line of a full log")
    eq(got[10000], "line 10250", "the newest line of a full log")
end

---------------------------------------------------------------------------
-- Output: one block per session, --grep, the Errors page
---------------------------------------------------------------------------

local db = {
    debug = {
        on = true, next = 3,
        lines = {
            "10:00:07.000 sellJunk: sold 2",                                  -- slots 1 and 2 are the newest
            "10:00:08.000 core: fight started",
            "09:00:01.000 sellJunk: vendor opened",                           -- the oldest: its session header was replaced
            "09:30:00.000 core: ---- session ---- 2026-11-17 addon=0.0.7",
            "09:30:05.000 bags: combined",
            "10:00:00.000 core: ---- debug log switched on ---- 2026-11-17 addon=0.0.7",
            "10:00:06.000 sellJunk: vendor opened",
        },
    },
    errors = {
        { module = "bags", msg = "attempt to index a nil value", count = 3, last = 0, stack = "Bags.lua:10: in function 'x'\nCore.lua:5: in function 'y'\n" },
        "junk",
        { module = "blocked", msg = "The game blocked UseContainerItem", count = 1 },
    },
}

eq(R.format(db), {
    "Debug log: 7 lines, switch on",
    "",
    "== Earlier lines (the start of this session is no longer in the log) ==",
    "09:00:01.000 sellJunk: vendor opened",
    "",
    "== Session 1 ==",
    "09:30:00.000 core: ---- session ---- 2026-11-17 addon=0.0.7",
    "09:30:05.000 bags: combined",
    "",
    "== Session 2 ==",
    "10:00:00.000 core: ---- debug log switched on ---- 2026-11-17 addon=0.0.7",
    "10:00:06.000 sellJunk: vendor opened",
    "10:00:07.000 sellJunk: sold 2",
    "10:00:08.000 core: fight started",
    "",
    "== Errors page: 2 entries ==",
    "",
    "bags   x3",
    "  attempt to index a nil value",
    "    Bags.lua:10: in function 'x'",
    "    Core.lua:5: in function 'y'",
    "",
    "blocked   x1",
    "  The game blocked UseContainerItem",
}, "the whole output")

eq(R.format(db, { grep = "sellJunk: vendor" }), {
    "Debug log: 7 lines, switch on",
    "",
    "== Earlier lines (the start of this session is no longer in the log) ==",
    "09:00:01.000 sellJunk: vendor opened",
    "",
    "== Session 2 ==",
    "10:00:06.000 sellJunk: vendor opened",
}, "--grep prints only matching lines, under their session")

eq(R.format(db, { grep = "^10:00:0[78]" }), {
    "Debug log: 7 lines, switch on",
    "",
    "== Session 2 ==",
    "10:00:07.000 sellJunk: sold 2",
    "10:00:08.000 core: fight started",
}, "--grep takes a Lua pattern")

do
    local out, err = R.format(db, { grep = "[" })
    check(out == nil and type(err) == "string" and err:find("bad pattern", 1, true), "a bad pattern is reported, not raised")
end

eq(R.format(db, { errorsOnly = true })[1], "== Errors page: 2 entries ==", "--errors prints the Errors page only")
eq(#R.format(db, { errorsOnly = true }), 9, "--errors line count")
eq(R.format({}), { "Debug log: 0 lines, switch off", "", "== Errors page: 0 entries ==" }, "saved settings with no debug table and no errors")
eq(R.format({ debug = "junk", errors = "junk" }), { "Debug log: 0 lines, switch off", "", "== Errors page: 0 entries ==" }, "damaged tables")

---------------------------------------------------------------------------
-- Catch all errors: the others' list grouped by source (spec 2026-11-20-
-- error-catcher-and-probe-panel, "Reading")
---------------------------------------------------------------------------

do
    local others = {
        errors = {},
        luaWarnings = 2,
        otherErrors = {
            { source = "Blizzard", msg = "Blizzard_WorldMap/Map.lua:9: oops", stack = "Map.lua:9: in function 'A'\nMap.lua:3: in function 'B'", count = 1, last = 0 },
            { source = "ExampleAddon", msg = "ExampleAddon/Main.lua:40: boom", stack = "", count = 3, last = 0 },
            "junk",
            { source = "Blizzard", msg = "Blizzard_Other/X.lua:1: again", count = 4, last = 0 },
        },
    }
    eq(R.formatOthers(others), {
        "== Other errors (Catch all errors): 3 entries, 2 Lua warnings ==",
        "",
        "Blizzard   5 times",
        "  x1",
        "    Blizzard_WorldMap/Map.lua:9: oops",
        "      Map.lua:9: in function 'A'",
        "      Map.lua:3: in function 'B'",
        "  x4",
        "    Blizzard_Other/X.lua:1: again",
        "",
        "ExampleAddon   3 times",
        "  x3",
        "    ExampleAddon/Main.lua:40: boom",
    }, "the others' list grouped by source, the busiest first")
    local all = R.format(others, { errorsOnly = true })
    eq(all[3], "== Other errors (Catch all errors): 3 entries, 2 Lua warnings ==", "--errors prints the others' list after the Errors page")
    eq(R.formatOthers({ otherErrors = "junk" }), { "== Other errors (Catch all errors): 0 entries, 0 Lua warnings ==" }, "a damaged others' list")
end

---------------------------------------------------------------------------
-- Loading the file: text only, nothing reachable from inside it
---------------------------------------------------------------------------

do
    local good = tempFile('\nPocketEssentialsDB = {\n["debug"] = {\n["on"] = true,\n["next"] = 3,\n["lines"] = {\n"a", -- [1]\n"b", -- [2]\n},\n},\n["errors"] = {\n},\n}\n')
    local loaded, err = R.load(good)
    check(type(loaded) == "table", "a saved file as the game writes it did not load: " .. tostring(err))
    eq(loaded and R.ordered(loaded.debug), { "a", "b" }, "lines from a loaded file")

    local status, out = R.main({ good })
    eq(status, 0, "exit status for a good file")
    eq(out and out[1], "Debug log: 2 lines, switch on", "first line printed for a good file")
    eq((R.main({ good, "--grep" })), 2, "--grep with no pattern is a usage error")
    eq((R.main({})), 2, "no file is a usage error")
    eq((R.main({ good, "--bogus" })), 2, "an unknown option is a usage error")

    for name, body in pairs({
        os = "PocketEssentialsDB = { debug = { lines = { os.date() } } }",
        io = "local f = io.open('/etc/hosts') PocketEssentialsDB = {}",
        require = "require('os') PocketEssentialsDB = {}",
        loadstring = "loadstring('return 1')() PocketEssentialsDB = {}",
        getfenv = "getfenv(0).os.exit(0) PocketEssentialsDB = {}",
        dofile = "dofile('/etc/hosts') PocketEssentialsDB = {}",
    }) do
        local got, reason = R.load(tempFile(body))
        check(got == nil and type(reason) == "string", "a file that uses " .. name .. " was loaded")
    end

    local empty = R.load(tempFile("PocketEssentialsDB = { seen = _G, count = (function() local n = 0 return n end)() }"))
    check(type(empty) == "table" and empty.seen == nil, "the file can see the real globals")

    local compiled = tempFile(string.dump(function() PocketEssentialsDB = {} end))
    local got, reason = R.load(compiled)
    check(got == nil and tostring(reason):find("compiled", 1, true), "compiled code was loaded")

    check(R.load(tempFile("this is not lua")) == nil, "a file that is not Lua was loaded")
    check(R.load(tempFile("SomethingElse = {}")) == nil, "a file without PocketEssentialsDB was loaded")
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
print(string.format("Read-log: %d checks", checks))
