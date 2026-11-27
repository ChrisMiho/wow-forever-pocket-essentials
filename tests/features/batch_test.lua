-- Rules for the 0.22.0 batch rows (Batch.lua): every row Off by default, the one login line,
-- "Turn all on / off", and the rows under the 0.22.0 heading of the Controller tab.
-- Sources: docs/superpowers/specs/2026-11-27-0.22.0-parked-batch.md, "How the batch is made
-- safe to test" (points 1, 3 and 5); CLAUDE.md "Features default off until device-tested".
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local KEYS = { "b22Empty", "b22Arrows", "b22Dpad", "b22Strip", "b22Marks", "b22Menu", "b22More", "b22Timers",
    "b22OwnLayout", "b22Panels", "b22Mount" }
local LABELS = { "Empty slots, clean", "Menu arrows, always", "D-pad moves by direction", "Map name strip, tidy",
    "Bigger direction marks", "Target menu above the tooltip (reload)", "Arrange: cast bar and focus frame (reload)",
    "Place the game's timers (reload)", "A layout for each character (reload)", "Large spell panels, whole",
    "Mount square, live" }

local function opts(PE) return PE.db.options.ctrlLayout end

local function walk(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walk(c, ch, fn, seen) end
    if st.scrollChild then walk(c, st.scrollChild, fn, seen) end
end

-- Every text drawn in the settings window, top to bottom.
local function settingsTexts(c)
    local out = {}
    walk(c, rawget(c.env, "PocketEssentialsSettingsPanel"), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and st.text ~= "" then out[#out + 1] = { text = st.text, top = select(5, r:GetPoint()) } end
        end
    end)
    table.sort(out, function(a, b) return (a.top or 0) > (b.top or 0) end)
    local texts = {}
    for i, t in ipairs(out) do texts[i] = t.text end
    return texts
end

local function indexOf(list, text)
    for i, t in ipairs(list) do if t == text then return i end end
    return nil
end

local function loginLines(c)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        if line:find(" core: batch: ", 1, true) then out[#out + 1] = line end
    end
    return out
end

test("batch: every row is Off on a fresh login, and On reads only a saved 1", function()
    local c, PE = T.new({})
    eq(PE.Batch.VERSION, "0.22.0")
    eq(#PE.Batch.ROWS, 11)
    for i, key in ipairs(KEYS) do
        eq(PE.Batch.ROWS[i].key, key)
        eq(PE.Batch.On(key), false, key)
    end
    eq(opts(PE).b22BarsSide, 0)
    for _, key in ipairs(KEYS) do
        opts(PE)[key] = 1
        eq(PE.Batch.On(key), true, key)
    end
    opts(PE).b22Empty = true
    eq(PE.Batch.On("b22Empty"), false, "only 1 counts")
    c:assertClean()
end)

test("batch: the rows that need a reload are the five the spec names", function()
    local _, PE = T.new({})
    local reload = {}
    for _, r in ipairs(PE.Batch.ROWS) do if r.reload then reload[#reload + 1] = r.key end end
    eq(reload, { "b22Menu", "b22More", "b22Timers", "b22OwnLayout" })
end)

test("batch: the login line lists the eleven rows in table order, all off", function()
    local _, PE = T.new({})
    local words = {}
    for _, key in ipairs(KEYS) do words[#words + 1] = key .. "=off" end
    eq(PE.Batch.Line(), "batch: 0.22.0 rows: " .. table.concat(words, " "))
    check(#PE.Batch.Line() <= 200, "longer than a debug line")
    opts(PE).b22Dpad = 1
    check(PE.Batch.Line():find("b22Dpad=on", 1, true), "an On row reads off")
end)

test("batch: SetAll flips every row and tells a listener only when its row changed", function()
    local c, PE = T.new({})
    local seen = {}
    PE.Batch.Listen("b22Empty", function(on) seen[#seen + 1] = on end)
    PE.Batch.Listen("b22Empty", function(on) seen[#seen + 1] = "second" end)
    PE.Batch.SetAll(true)
    for _, key in ipairs(KEYS) do eq(opts(PE)[key], 1, key) end
    eq(seen, { true, "second" })
    PE.Batch.SetAll(true)
    eq(seen, { true, "second" }, "a second Turn all on told a listener again")
    PE.Batch.SetAll(false)
    for _, key in ipairs(KEYS) do eq(opts(PE)[key], 0, key) end
    eq(seen, { true, "second", false, "second" })
    c:assertClean()
end)

test("batch: a listener that fails is caught and the others still run", function()
    local c, PE = T.new({})
    local ran = false
    PE.Batch.Listen("b22Arrows", function() error("boom") end)
    PE.Batch.Listen("b22Arrows", function() ran = true end)
    PE.Batch.SetAll(true)
    check(ran, "the second listener did not run")
    check(#PE.errors >= 1, "the failure was not logged")
end)

test("batch: with the Debug log on, a login writes the batch line once, under core", function()
    local c, PE = T.new({ saved = { setup = "skipped", debug = { on = true, lines = {}, next = 1 }, options = { ctrlLayout = { b22Mount = 1 } } } })
    local lines = loginLines(c)
    eq(#lines, 1)
    check(lines[1]:match("^%d%d:%d%d:%d%d%.%d%d%d core: ") ~= nil, lines[1])
    check(lines[1]:find(PE.Batch.Line(), 1, true), "not the batch line: " .. lines[1])
    check(lines[1]:find("b22Mount=on", 1, true), "the saved On row reads off")
    c:assertClean()
end)

test("batch: with the Debug log off, nothing is written", function()
    local c = T.new({})
    eq(rawget(c.env, "PocketEssentialsDB").debug.lines, {})
end)

test("batch: the Controller tab lists the 0.22.0 heading, Turn all on / off, the rows and Buff timer bars, also while Controller layout is Off", function()
    local c, PE = T.new({})
    PE:OpenSettings("controller")
    c:advance(0.2)
    check(PE:GetModuleState("ctrlLayout") ~= "on", "the layout is on")
    local texts = settingsTexts(c)
    local heading = indexOf(texts, "0.22.0")
    check(heading ~= nil, "no 0.22.0 heading: " .. table.concat(texts, " | "))
    local everything = indexOf(texts, "Everything in 0.22.0")
    check(everything and everything > heading, "no Everything in 0.22.0 row after the heading")
    local buttons = {}
    walk(c, rawget(c.env, "PocketEssentialsSettingsPanel"), function(w)
        if c._state(w).type == "Button" and w:IsVisible() then buttons[T.labelOf(w)] = true end
    end)
    check(buttons["Turn all on"] and buttons["Turn all off"], "no Turn all on / off buttons")
    local last = everything
    for i, label in ipairs(LABELS) do
        local at = indexOf(texts, label)
        check(at ~= nil, "no row " .. label .. ": " .. table.concat(texts, " | "))
        check(at > last, "row " .. label .. " is out of order")
        last = at
    end
    local bars = indexOf(texts, "Buff timer bars")
    check(bars and bars > last, "no Buff timer bars row after the rows")
    c:assertClean()
end)

test("batch: with Controller layout Off, Turn all on raises nothing and makes no game call a fresh login does not", function()
    local c, PE = T.new({})
    local before = #T.gameCalls(c)
    PE:OpenSettings("controller")
    c:advance(0.2)
    local opened = #T.gameCalls(c)
    local mod = PE:GetModule("ctrlLayout")
    local row
    for _, o in ipairs(mod.options) do if o.label == "Everything in 0.22.0" then row = o end end
    check(row ~= nil, "no Everything in 0.22.0 row")
    eq(row.buttons[1].label, "Turn all on")
    eq(row.buttons[2].label, "Turn all off")
    PE:Safe("ctrlLayout", row.buttons[1].action, mod)
    c:advance(0.2)
    for _, key in ipairs(KEYS) do eq(opts(PE)[key], 1, key) end
    eq(#T.gameCalls(c), opened, "Turn all on made game calls")
    PE:Safe("ctrlLayout", row.buttons[2].action, mod)
    for _, key in ipairs(KEYS) do eq(opts(PE)[key], 0, key) end
    eq(#T.gameCalls(c), opened, "Turn all off made game calls")
    eq(#PE.errors, 0)
    c:assertClean()
end)

test("batch: Buff timer bars has two choices and Left, by your name is the default", function()
    local _, PE = T.new({})
    local row
    for _, o in ipairs(PE:GetModule("ctrlLayout").options) do if o.key == "b22BarsSide" then row = o end end
    check(row ~= nil, "no row")
    eq(row.label, "Buff timer bars")
    eq({ row.choices[1].value, row.choices[1].label, row.choices[2].value, row.choices[2].label },
        { 0, "Left, by your name", 1, "Right, by the target" })
    check(row.always, "not always")
end)

return { known = KNOWN_FAILURES }
