local ADDON_NAME, PE = ...

-- Pocket Essentials: the 0.22.0 batch rows (PE.Batch).
-- Spec: docs/superpowers/specs/2026-11-27-0.22.0-parked-batch.md, "How the batch is made safe
-- to test".
--
-- Every new part of the batch has one switch, Off until it is turned on. The switches are
-- saved in the Controller layout's own options (PE.db.options.ctrlLayout), so no new saved
-- table is made. This file only keeps the list of switches, reads them, tells the parts when
-- one changes, and writes the one line at login that says which are On. It draws nothing,
-- listens for no game event and makes no game call.

local Batch = {}
PE.Batch = Batch

Batch.VERSION = "0.22.0"

-- In the order of the spec. reload: the part counts from the next reload.
Batch.ROWS = {
    { key = "b22Empty", label = "Empty slots, clean", reload = false },
    { key = "b22Arrows", label = "Menu arrows, always", reload = false },
    { key = "b22Dpad", label = "D-pad moves by direction", reload = false },
    { key = "b22Strip", label = "Map name strip, tidy", reload = false },
    { key = "b22Marks", label = "Bigger direction marks", reload = false },
    { key = "b22Menu", label = "Target menu above the tooltip", reload = true },
    { key = "b22More", label = "Arrange: cast bar and focus frame", reload = true },
    { key = "b22Timers", label = "Place the game's timers", reload = true },
    { key = "b22OwnLayout", label = "A layout for each character", reload = true },
    { key = "b22Panels", label = "Large spell panels, whole", reload = false },
    { key = "b22Mount", label = "Mount square, live", reload = false },
}

local listeners = {} -- [key] = { fn, ... }

local function Saved()
    local db = PE.db
    local options = type(db) == "table" and db.options
    local saved = type(options) == "table" and options.ctrlLayout
    return type(saved) == "table" and saved or nil
end

-- True only when that row is saved On (1). False before the saved table exists.
function Batch.On(key)
    local saved = Saved()
    return saved ~= nil and saved[key] == 1
end

-- fn(on) is called when the row changes. Several may listen to one row.
function Batch.Listen(key, fn)
    if type(key) ~= "string" or type(fn) ~= "function" then return end
    local list = listeners[key]
    if not list then
        list = {}
        listeners[key] = list
    end
    list[#list + 1] = fn
end

-- Tells the listeners of one row its value now.
function Batch.Changed(key)
    local list = listeners[key]
    if not list then return end
    local on = Batch.On(key)
    for _, fn in ipairs(list) do PE:Safe("batch", fn, on) end
end

-- "Turn all on" and "Turn all off": sets every row, then tells the rows that changed.
function Batch.SetAll(on)
    local saved = Saved()
    if not saved then return end
    local value = on and 1 or 0
    local changed = {}
    for _, row in ipairs(Batch.ROWS) do
        if saved[row.key] ~= value then changed[#changed + 1] = row.key end
        saved[row.key] = value
    end
    for _, key in ipairs(changed) do Batch.Changed(key) end
end

-- The login line: every row and whether it is On, in table order.
function Batch.Line()
    local parts = {}
    for _, row in ipairs(Batch.ROWS) do
        parts[#parts + 1] = row.key .. "=" .. (Batch.On(row.key) and "on" or "off")
    end
    return "batch: " .. Batch.VERSION .. " rows: " .. table.concat(parts, " ")
end
