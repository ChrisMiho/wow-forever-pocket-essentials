-- Rules for the measuring hook in Core.lua: PE:StartMeasure, PE:StopMeasure
-- and PE:MeasureCounters, and the timing of the shared paths (the event
-- dispatcher, mod:After, PE:Wrap, PE:Safe and mod:Safe).
-- Source: docs/superpowers/specs/2026-11-21-perf-recorder.md, "A. Measuring hook",
-- ruling 4 (the counters' shape), "Where the per-stretch numbers come from"
-- (the "*" total counts outermost runs only) and "Hook tests".
-- The clock is the stand-in debugprofilestop: it reads c.profileMs, which a
-- test moves on by hand, so every time here is exact.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

-- A client whose clock counts how often it was read.
local function new(opts)
    local c, PE = T.new(opts or {})
    c.profileMs = 0
    local reads = { n = 0 }
    rawset(c.env, "debugprofilestop", function()
        reads.n = reads.n + 1
        return c.profileMs
    end)
    return c, PE, reads
end

local function feature(PE, key)
    local mod = PE:RegisterModule({ key = key, label = key, order = 99 })
    PE:SetModuleEnabled(key, true)
    return mod
end

-- A function that takes `ms` on the clock and returns what it was given.
local function takes(c, ms)
    return function(...)
        c.profileMs = c.profileMs + ms
        return ...
    end
end

local function errorsOf(PE, key)
    local n = 0
    for _, e in ipairs(PE.errors) do
        if e.module == key then n = n + (tonumber(e.count) or 1) end
    end
    return n
end

---------------------------------------------------------------------------
-- Off
---------------------------------------------------------------------------

-- Spec "While not measuring" and "Hook tests: off".
test("measure: never started, there are no counters, the clock is not read and results pass through", function()
    local c, PE, reads = new()
    local mod = feature(PE, "probe")
    eq(PE:MeasureCounters(), nil)
    local wrapped = PE:Wrap("probe", takes(c, 2))
    eq({ wrapped(1, nil, 3) }, { 1, nil, 3 })
    eq(select("#", wrapped(1, nil, nil)), 3, "trailing nils were dropped")
    eq({ PE:Safe("probe", takes(c, 2), "a", "b") }, { true, "a", "b" })
    eq({ mod:Safe(takes(c, 2), "a") }, { true, "a" })
    eq({ mod:Wrap(takes(c, 2))(7) }, { 7 })
    local fired = 0
    mod:After(1, function() fired = fired + 1 end)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", function() fired = fired + 1 end)
    c:advance(2)
    c:fire("PLAYER_REGEN_ENABLED")
    eq(fired, 2)
    eq(reads.n, 0, "the clock was read while measuring was off")
    eq(PE:MeasureCounters(), nil)
    c:assertClean("off")
end)

-- Spec: "Nothing in Pocket Essentials calls them".
test("measure: a login with features on never starts measuring", function()
    local c, PE = T.new({ saved = { version = 1, enabled = { sellJunk = true, chat = true }, options = {}, errors = {} } })
    c:fire("PLAYER_REGEN_ENABLED")
    c:advance(2)
    eq(PE:MeasureCounters(), nil)
    c:assertClean("login")
end)

-- The task's guard: without the clock nothing changes.
test("measure: without debugprofilestop StartMeasure returns nil and nothing is measured", function()
    local c, PE = new()
    rawset(c.env, "debugprofilestop", nil)
    eq(PE:StartMeasure(), nil)
    eq(PE:MeasureCounters(), nil)
    eq({ PE:Wrap("probe", takes(c, 2))(5) }, { 5 })
    eq(PE:MeasureCounters(), nil)
    PE:StopMeasure()
    c:assertClean("no clock")
end)

-- Spec "Turning it on and off"; ruling 4.
test("measure: StopMeasure freezes the counters and a second StartMeasure carries on in the same table", function()
    local c, PE, reads = new()
    local wrapped = PE:Wrap("probe", takes(c, 2))
    local counters = PE:StartMeasure()
    check(type(counters) == "table", "StartMeasure did not return the counters")
    check(rawget(c.env, "PocketEssentials") == PE, "PE is not reachable as _G.PocketEssentials")
    eq(counters, { ["*"] = { ms = 0, calls = 0, max = 0 } })
    wrapped()
    check(PE:StartMeasure() == counters, "a second StartMeasure returned another table")
    check(PE:MeasureCounters() == counters, "MeasureCounters returned another table")
    eq(counters.probe, { ms = 2, calls = 1, max = 2 }, "a second StartMeasure reset the counters")
    PE:StopMeasure()
    local before = reads.n
    eq({ wrapped(9) }, { 9 })
    eq(reads.n, before, "the clock was read after StopMeasure")
    eq(counters.probe, { ms = 2, calls = 1, max = 2 })
    check(PE:MeasureCounters() == counters, "the counters were dropped by StopMeasure")
    check(PE:StartMeasure() == counters, "StartMeasure after a stop returned another table")
    wrapped()
    eq(counters.probe, { ms = 4, calls = 2, max = 2 })
    eq(counters["*"], { ms = 4, calls = 2, max = 2 })
    c:assertClean("stop and start")
end)

---------------------------------------------------------------------------
-- On: each shared path
---------------------------------------------------------------------------

-- Spec "Where it times": PE:Wrap, which covers mod:Wrap.
test("measure: PE:Wrap and mod:Wrap are counted by feature key and pass results through", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    local a, b = PE:Wrap("other", takes(c, 3)), mod:Wrap(takes(c, 5))
    local noKey = PE:Wrap(nil, takes(c, 1))
    local counters = PE:StartMeasure()
    eq({ a(1, nil, 3) }, { 1, nil, 3 })
    eq(select("#", a(1, nil, nil)), 3, "trailing nils were dropped")
    eq({ b("x") }, { "x" })
    eq(select("#", b()), 0)
    b()
    c.profileMs = c.profileMs + 100 -- time outside our code is not counted
    noKey()
    eq(counters.other, { ms = 6, calls = 2, max = 3 })
    eq(counters.probe, { ms = 15, calls = 3, max = 5 })
    eq(counters.core, { ms = 1, calls = 1, max = 1 }, "a wrap without a key is counted as core")
    eq(counters["*"], { ms = 22, calls = 6, max = 5 })
    c:assertClean("wrap")
end)

-- Spec "Where it times": PE:Safe and mod:Safe.
test("measure: PE:Safe and mod:Safe are counted and still return ok and the results", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    local counters = PE:StartMeasure()
    eq({ PE:Safe("other", takes(c, 4), "a", nil, "c") }, { true, "a", nil, "c" })
    eq({ PE:Safe("", takes(c, 1)) }, { true })
    eq({ mod:Safe(takes(c, 7), 1, 2) }, { true, 1, 2 })
    eq({ PE:Safe("other", "not a function") }, { false })
    eq({ mod:Safe(nil) }, { false })
    eq(counters.other, { ms = 4, calls = 1, max = 4 })
    eq(counters.core, { ms = 1, calls = 1, max = 1 })
    eq(counters.probe, { ms = 7, calls = 1, max = 7 })
    eq(counters["*"], { ms = 12, calls = 3, max = 7 })
    c:assertClean("safe")
end)

-- Spec "Where it times": mod:After timers.
test("measure: a mod:After timer is counted under its feature, and not when its feature went off", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    local counters = PE:StartMeasure()
    mod:After(1, takes(c, 6))
    c:advance(2)
    eq(counters.probe, { ms = 6, calls = 1, max = 6 })
    mod:After(1, takes(c, 6))
    PE:SetModuleEnabled("probe", false)
    c:advance(2)
    eq(counters.probe, { ms = 6, calls = 1, max = 6 }, "a skipped timer was counted")
    c:assertClean("after")
end)

-- Spec "Where it times": the event dispatcher; ruling 4: events[event] = { ms, calls }.
test("measure: the dispatcher counts each feature's handler per event, and the core list as core", function()
    local c, PE = new()
    local a, b = feature(PE, "probeA"), feature(PE, "probeB")
    a:RegisterEvent("PLAYER_REGEN_ENABLED", takes(c, 2))
    a:RegisterEvent("PLAYER_REGEN_DISABLED", takes(c, 9))
    b.PLAYER_REGEN_ENABLED = takes(c, 4)
    b:RegisterEvent("PLAYER_REGEN_ENABLED") -- a method named after the event
    PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "measureTest", takes(c, 1))
    local counters = PE:StartMeasure()
    c:fire("PLAYER_REGEN_ENABLED")
    c:fire("PLAYER_REGEN_ENABLED")
    c:fire("PLAYER_REGEN_DISABLED")
    eq(counters.probeA, { ms = 13, calls = 3, max = 9, events = {
        PLAYER_REGEN_ENABLED = { ms = 4, calls = 2 }, PLAYER_REGEN_DISABLED = { ms = 9, calls = 1 } } })
    eq(counters.probeB, { ms = 8, calls = 2, max = 4, events = { PLAYER_REGEN_ENABLED = { ms = 8, calls = 2 } } })
    local core = counters.core
    check(core and core.events, "the core's own handlers were not counted per event")
    eq(core.events.PLAYER_REGEN_DISABLED, { ms = 1, calls = 1 })
    -- The core's own work on PLAYER_REGEN_ENABLED (the combat queue) takes no time on this clock.
    eq(core.events.PLAYER_REGEN_ENABLED.ms, 0)
    eq(counters["*"].ms, 22)
    eq(counters["*"].max, 9)
    c:assertClean("events")
end)

-- A feature that is off is not called, so it is not counted.
test("measure: a feature switched off gets no event counts", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", takes(c, 2))
    PE:SetModuleEnabled("probe", false)
    local counters = PE:StartMeasure()
    c:fire("PLAYER_REGEN_ENABLED")
    eq(counters.probe, nil)
    c:assertClean("off feature")
end)

---------------------------------------------------------------------------
-- Nested runs and errors
---------------------------------------------------------------------------

-- Spec "Nested runs ... are counted in both"; "Only the outermost runs are counted" in the total.
test("measure: a nested run is counted under both keys and once in the total", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    local inner = PE:Wrap("inner", takes(c, 3))
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        c.profileMs = c.profileMs + 2
        inner()
        PE:Safe("inner", takes(c, 1))
    end)
    local counters = PE:StartMeasure()
    c:fire("PLAYER_REGEN_DISABLED")
    eq(counters.inner, { ms = 4, calls = 2, max = 3 })
    eq(counters.probe, { ms = 6, calls = 1, max = 6, events = { PLAYER_REGEN_DISABLED = { ms = 6, calls = 1 } } })
    eq(counters["*"], { ms = 6, calls = 1, max = 6 })
    inner()
    eq(counters["*"], { ms = 9, calls = 2, max = 6 }, "a run after a nested one was not counted as outermost")
    c:assertClean("nested")
end)

-- Spec "Errors" and "Hook tests: an error in a handler is still reported once".
test("measure: an error is reported once, its time is counted and the next run is still outermost", function()
    local c, PE = new()
    local mod = feature(PE, "probe")
    local function breaks(...)
        c.profileMs = c.profileMs + 5
        error("measure test " .. tostring((...)))
    end
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", function() breaks("event") end)
    local wrapped = PE:Wrap("probe", breaks)
    local counters = PE:StartMeasure()

    eq(select("#", wrapped("wrap")), 0, "a failed wrapped run returned something")
    eq(errorsOf(PE, "probe"), 1)
    local ok = PE:Safe("probe", breaks, "safe")
    eq(ok, false)
    eq(errorsOf(PE, "probe"), 2)
    eq((mod:Safe(breaks, "modsafe")), false)
    eq(errorsOf(PE, "probe"), 3)
    mod:After(1, function() breaks("after") end)
    c:advance(2)
    eq(errorsOf(PE, "probe"), 4)
    c:fire("PLAYER_REGEN_DISABLED")
    eq(errorsOf(PE, "probe"), 5)

    eq(counters.probe.ms, 25)
    eq(counters.probe.calls, 5)
    eq(counters.probe.max, 5)
    eq(counters.probe.events, { PLAYER_REGEN_DISABLED = { ms = 5, calls = 1 } })
    eq(counters["*"], { ms = 25, calls = 5, max = 5 }, "an error left the depth counter wrong")

    -- An error inside a nested run: the outer run goes on and is counted once.
    local outer = PE:Wrap("outer", function()
        wrapped("nested")
        c.profileMs = c.profileMs + 1
        return "done"
    end)
    eq(outer(), "done")
    eq(errorsOf(PE, "probe"), 6)
    eq(counters.outer, { ms = 6, calls = 1, max = 6 })
    eq(counters["*"], { ms = 31, calls = 6, max = 6 })
    eq(#c.errors, 0, "an error reached the game")
end)

-- The same errors with measuring off, for comparison with the test above.
test("measure: with measuring off the same errors are reported the same way", function()
    local c, PE, reads = new()
    local mod = feature(PE, "probe")
    local function breaks(...) error("measure test " .. tostring((...))) end
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", function() breaks("event") end)
    local wrapped = PE:Wrap("probe", breaks)
    eq(select("#", wrapped("wrap")), 0)
    eq((PE:Safe("probe", breaks, "safe")), false)
    eq((mod:Safe(breaks, "modsafe")), false)
    mod:After(1, function() breaks("after") end)
    c:advance(2)
    c:fire("PLAYER_REGEN_DISABLED")
    eq(errorsOf(PE, "probe"), 5)
    eq(reads.n, 0)
    eq(#c.errors, 0, "an error reached the game")
end)

return { known = KNOWN_FAILURES }
