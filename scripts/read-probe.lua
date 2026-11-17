-- Reader for the restriction probe's saved file (scripts/read-probe.sh runs this).
--
--   luajit scripts/read-probe.lua <saved PocketProbe.lua> [--markdown | --details | --log | --diff <other PocketProbe.lua>]
--
-- The saved file is Lua that sets PocketProbeDB. It is run in an empty
-- environment (no os, io, require or any other global), text only (compiled
-- code is refused), with a limit on how long it may run.
--
-- The file comes from a device, so nothing in it is trusted to have the right
-- type: anything that is not what was expected is left out or printed as text.
--
-- Loaded with dofile from a test, this returns its functions and prints nothing.

local M = {}

local STEP_LIMIT = 1e7   -- far more than the largest real file needs

-- The saved table from the file at `path`, or nil and a reason.
function M.load(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, "cannot open " .. tostring(path) .. ": " .. tostring(err) end
    local text = f:read("*a")
    f:close()
    if not text then return nil, "cannot read " .. tostring(path) end
    if text:sub(1, 1) == "\27" then return nil, "this is compiled code, not a saved probe file; not loading it" end
    local chunk, syntaxErr = loadstring(text, "=saved file")
    if not chunk then return nil, "not a saved probe file: " .. tostring(syntaxErr) end
    local env = {}
    setfenv(chunk, env)
    -- The step limit needs the interpreter: compiled loops do not count steps.
    if jit then jit.off(chunk, true) end
    debug.sethook(function() error("the file ran for too long; stopped", 0) end, "", STEP_LIMIT)
    local ok, runErr = pcall(chunk)
    debug.sethook()
    if not ok then return nil, "the file could not be read as a saved probe file: " .. tostring(runErr) end
    local db = rawget(env, "PocketProbeDB")
    if type(db) ~= "table" then return nil, "no PocketProbeDB in this file" end
    return db
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Any value as one line of text with no control characters (the text is
-- printed to a terminal).
local function clean(v)
    return (tostring(v):gsub("%c", " "))
end

local function tbl(v)
    return type(v) == "table" and v or {}
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

---------------------------------------------------------------------------
-- Situations
---------------------------------------------------------------------------

-- The six restrictions in the order of the key's "rest=" letters.
local RESTRICTIONS = {
    { letter = "c", field = "combat", word = "combat" },
    { letter = "e", field = "encounter", word = "encounter" },
    { letter = "h", field = "challenge", word = "challenge" },
    { letter = "p", field = "pvp", word = "PvP" },
    { letter = "m", field = "map", word = "map" },
    { letter = "t", field = "chat", word = "chat" },
}
local WHERE_WORDS = { world = "open world", dungeon = "dungeon", raid = "raid", battleground = "battleground" }
local WHERE_RANK = { world = 0, dungeon = 1, raid = 2, battleground = 3 }
local TRIGGER_WORDS = { auto = "automatic", press = "from a press", clean = "clean (first thing after a reload)" }
local TRIGGER_RANK = { auto = 0, press = 1, clean = 2 }

-- The facts written in a situation key:
-- "gp=on fight=no rest=c----- where=world trig=auto".
function M.parseKey(key)
    local s = { restrictions = {} }
    if type(key) ~= "string" then return s end
    local gp = key:match("gp=(%a+)")
    if gp == "on" then s.gamepad = true elseif gp == "off" then s.gamepad = false end
    local fight = key:match("fight=(%a+)")
    if fight == "yes" then s.lockdown = true elseif fight == "no" then s.lockdown = false end
    local rest = key:match("rest=(%S+)")
    if rest then
        for _, r in ipairs(RESTRICTIONS) do
            s.restrictions[r.field] = rest:find(r.letter, 1, true) ~= nil
        end
    end
    s.where = key:match("where=(.-) trig=") or key:match("where=(.*)$")
    s.trigger = key:match("trig=(%a+)")
    return s
end

-- One situation's facts: the saved table's where it has them with the right
-- type, the key's otherwise.
local function situationFacts(key, saved)
    local s = M.parseKey(key)
    s.key = key
    if type(saved) == "table" then
        if type(saved.gamepad) == "boolean" then s.gamepad = saved.gamepad end
        if type(saved.lockdown) == "boolean" then s.lockdown = saved.lockdown end
        if type(saved.restrictions) == "table" then
            for _, r in ipairs(RESTRICTIONS) do
                if type(saved.restrictions[r.field]) == "boolean" then s.restrictions[r.field] = saved.restrictions[r.field] end
            end
        end
        if type(saved.where) == "string" then s.where = saved.where end
        if type(saved.trigger) == "string" then s.trigger = saved.trigger end
        if type(saved.first) == "string" then s.first = saved.first end
        if type(saved.passes) == "number" then s.passes = saved.passes end
    end
    s.active = {}
    for _, r in ipairs(RESTRICTIONS) do
        if s.restrictions[r.field] then s.active[#s.active + 1] = r.word end
    end
    return s
end

-- A situation in plain words: "Gamepad UI on, no fight, open world, automatic".
function M.describe(s)
    local parts = {}
    parts[#parts + 1] = s.gamepad == true and "Gamepad UI on" or s.gamepad == false and "Gamepad UI off" or "Gamepad UI unknown"
    parts[#parts + 1] = s.lockdown == true and "in a fight" or s.lockdown == false and "no fight" or "fight unknown"
    if #s.active > 0 then parts[#parts + 1] = "game restrictions on: " .. table.concat(s.active, ", ") end
    local where = s.where and s.where ~= "" and clean(s.where) or "place unknown"
    parts[#parts + 1] = WHERE_WORDS[where] or where
    local trigger = s.trigger and clean(s.trigger) or "start unknown"
    parts[#parts + 1] = TRIGGER_WORDS[trigger] or trigger
    return table.concat(parts, ", ")
end

local function rankOf(s)
    return {
        s.gamepad == true and 0 or s.gamepad == false and 1 or 2,
        s.lockdown == false and 0 or s.lockdown == true and 1 or 2,
        #s.active,
        WHERE_RANK[s.where] or 4,
        tostring(s.where or ""),
        TRIGGER_RANK[s.trigger] or 3,
        s.key,
    }
end

-- Every situation in the file (the saved list, plus any that only a result or
-- a detail names), in display order, each with its short column name:
-- Gamepad UI on first; no fight before a fight; open world before instances;
-- automatic, press, clean.
function M.situations(db)
    db = tbl(db)
    local seen, list = {}, {}
    local saved = tbl(db.situations)
    local function add(key)
        if type(key) ~= "string" or seen[key] then return end
        seen[key] = true
        list[#list + 1] = situationFacts(key, saved[key])
    end
    for _, key in ipairs(sortedKeys(saved)) do add(key) end
    for _, id in ipairs(sortedKeys(tbl(db.results))) do
        for _, key in ipairs(sortedKeys(tbl(db.results[id]))) do add(key) end
    end
    for _, d in ipairs(tbl(db.details)) do
        if type(d) == "table" then add(d.situation) end
    end
    for _, s in ipairs(list) do s.rank = rankOf(s) end
    table.sort(list, function(a, b)
        for i = 1, #a.rank do
            if a.rank[i] ~= b.rank[i] then return a.rank[i] < b.rank[i] end
        end
        return false
    end)
    local byKey = {}
    for i, s in ipairs(list) do
        s.name = "S" .. i
        s.text = M.describe(s)
        byKey[s.key] = s
    end
    return list, byKey
end

---------------------------------------------------------------------------
-- Trials
---------------------------------------------------------------------------

local OTHER = "Other"

-- The trials grouped by area, in the file's display order:
-- { { area = "Chat box", trials = { { id, label, kind }, ... } }, ... }.
-- A trial that has results or details but is not in the list goes under "Other".
function M.areas(db)
    db = tbl(db)
    local areas, byArea, seen = {}, {}, {}
    local function add(id, label, kind, area)
        if type(id) ~= "string" or seen[id] then return end
        local trial = {
            id = id,
            label = type(label) == "string" and label ~= "" and clean(label) or clean(id),
            kind = type(kind) == "string" and kind or nil,
        }
        seen[id] = trial
        area = type(area) == "string" and area ~= "" and clean(area) or OTHER
        if not byArea[area] then
            byArea[area] = { area = area, trials = {} }
            areas[#areas + 1] = byArea[area]
        end
        local list = byArea[area].trials
        list[#list + 1] = trial
    end
    for _, t in ipairs(tbl(db.trials)) do
        if type(t) == "table" then add(t.id, t.label, t.kind, t.area) end
    end
    for _, id in ipairs(sortedKeys(tbl(db.results))) do add(id) end
    local fromDetails = {}
    for _, d in ipairs(tbl(db.details)) do
        if type(d) == "table" and type(d.trial) == "string" then fromDetails[d.trial] = true end
    end
    for _, id in ipairs(sortedKeys(fromDetails)) do add(id) end
    -- "Other" is printed last.
    for i, a in ipairs(areas) do
        if a.area == OTHER and i < #areas then
            table.remove(areas, i)
            areas[#areas + 1] = a
            break
        end
    end
    return areas, seen
end

-- The result of one trial in one situation, or nil when it was not run.
function M.cell(db, id, key)
    local row = tbl(db).results
    row = type(row) == "table" and row[id] or nil
    local v = type(row) == "table" and row[key] or nil
    if v == nil then return nil end
    v = clean(v)
    return v ~= "" and v or nil
end

local function trialCount(areas)
    local n = 0
    for _, a in ipairs(areas) do n = n + #a.trials end
    return n
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local function pad(text, width)
    return text .. string.rep(" ", width - #text)
end

local function mdCell(text)
    return (text:gsub("|", "\\|"))
end

function M.formatHeader(db, situations, areas)
    db = tbl(db)
    return {
        "Restriction probe",
        "Game " .. (db.game ~= nil and clean(db.game) or "unknown") .. ", probe " .. (db.probe ~= nil and clean(db.probe) or "unknown"),
        plural(#situations, "situation", "situations") .. ", " .. plural(trialCount(areas), "trial", "trials"),
    }
end

local function seenText(s)
    local parts = {}
    if s.first then parts[#parts + 1] = "first seen " .. clean(s.first) end
    if s.passes then parts[#parts + 1] = plural(s.passes, "pass", "passes") end
    return table.concat(parts, ", ")
end

function M.formatLegend(situations, markdown)
    local out = {}
    if #situations == 0 then return out end
    if markdown then
        out[#out + 1] = "| Column | Situation |"
        out[#out + 1] = "|---|---|"
        for _, s in ipairs(situations) do
            out[#out + 1] = "| " .. s.name .. " | " .. mdCell(s.text) .. " |"
        end
        return out
    end
    out[#out + 1] = "Situations (the columns below)"
    local width = #situations[#situations].name
    for _, s in ipairs(situations) do
        local seen = seenText(s)
        out[#out + 1] = "  " .. pad(s.name, width) .. "  " .. s.text .. (seen ~= "" and " (" .. seen .. ")" or "")
    end
    return out
end

-- One table per area: a row per trial, a column per situation.
function M.formatTables(db, situations, areas, markdown)
    local out = {}
    for _, a in ipairs(areas) do
        if #out > 0 then out[#out + 1] = "" end
        local rows = {}
        for _, t in ipairs(a.trials) do
            local row = { t.label }
            for i, s in ipairs(situations) do row[i + 1] = M.cell(db, t.id, s.key) or "-" end
            rows[#rows + 1] = row
        end
        local head = { "Trial" }
        for i, s in ipairs(situations) do head[i + 1] = s.name end
        if markdown then
            out[#out + 1] = "#### " .. a.area
            out[#out + 1] = ""
            for i = 1, #head do head[i] = mdCell(head[i]) end
            out[#out + 1] = "| " .. table.concat(head, " | ") .. " |"
            out[#out + 1] = "|" .. string.rep("---|", #head)
            for _, row in ipairs(rows) do
                for i = 1, #row do row[i] = mdCell(row[i]) end
                out[#out + 1] = "| " .. table.concat(row, " | ") .. " |"
            end
        else
            out[#out + 1] = a.area
            local widths = {}
            for i = 1, #head do
                widths[i] = #head[i]
                for _, row in ipairs(rows) do
                    if #row[i] > widths[i] then widths[i] = #row[i] end
                end
            end
            local function line(row)
                local cells = {}
                for i = 1, #row do cells[i] = i < #row and pad(row[i], widths[i]) or row[i] end
                return "  " .. table.concat(cells, "  ")
            end
            out[#out + 1] = line(head)
            for _, row in ipairs(rows) do out[#out + 1] = line(row) end
        end
    end
    return out
end

-- The "Not allowed" section: every detail entry, grouped by trial.
function M.formatDetails(db, byKey, areas)
    db = tbl(db)
    local byTrial, total = {}, 0
    for _, d in ipairs(tbl(db.details)) do
        if type(d) == "table" and type(d.trial) == "string" then
            byTrial[d.trial] = byTrial[d.trial] or {}
            table.insert(byTrial[d.trial], d)
            total = total + 1
        end
    end
    local out = { "Not allowed: " .. plural(total, "entry", "entries") }
    for _, a in ipairs(areas) do
        for _, t in ipairs(a.trials) do
            local list = byTrial[t.id]
            if list then
                out[#out + 1] = ""
                out[#out + 1] = t.label == clean(t.id) and t.label or t.label .. " (" .. clean(t.id) .. ")"
                for _, d in ipairs(list) do
                    local s = byKey[d.situation]
                    local head = "  " .. (d.result ~= nil and clean(d.result) or "no result") .. " in "
                        .. (s and s.name .. " (" .. s.text .. ")" or "an unknown situation")
                    if d.at ~= nil then head = head .. ", at " .. clean(d.at) end
                    out[#out + 1] = head
                    if d.func ~= nil then out[#out + 1] = "    function: " .. clean(d.func) end
                    if d.message ~= nil then out[#out + 1] = "    message: " .. clean(d.message) end
                    if d.inPress ~= nil then
                        out[#out + 1] = "    straight from a press: " .. (d.inPress == true and "yes" or d.inPress == false and "no" or clean(d.inPress))
                    end
                    if d.focus ~= nil then out[#out + 1] = "    controller focus: " .. clean(d.focus) end
                    if type(d.stack) == "string" and d.stack ~= "" then
                        out[#out + 1] = "    stack:"
                        for stackLine in (d.stack .. "\n"):gmatch("(.-)\r?\n") do
                            if stackLine:find("%S") then out[#out + 1] = "      " .. clean(stackLine) end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- The probe's activity log.
function M.formatLog(db)
    local lines = {}
    for _, line in ipairs(tbl(tbl(db).log)) do
        if type(line) == "string" then lines[#lines + 1] = clean(line) end
    end
    table.insert(lines, 1, "Activity log: " .. plural(#lines, "line", "lines"))
    return lines
end

-- Everything the command prints for one file.
-- opts: { markdown = bool, detailsOnly = bool, logOnly = bool }.
function M.format(db, opts)
    opts = opts or {}
    db = tbl(db)
    if opts.logOnly then return M.formatLog(db) end
    local situations, byKey = M.situations(db)
    local areas = M.areas(db)
    if opts.detailsOnly then return M.formatDetails(db, byKey, areas) end
    local out = {}
    local function add(lines, gap)
        if #lines == 0 then return end
        if gap and #out > 0 then out[#out + 1] = "" end
        for _, line in ipairs(lines) do out[#out + 1] = line end
    end
    local header = M.formatHeader(db, situations, areas)
    if opts.markdown then
        add({ header[2] .. ". " .. header[3] .. "." })
    else
        add(header)
    end
    add(M.formatLegend(situations, opts.markdown), true)
    if #situations == 0 and #areas == 0 then
        add({ "No results in this file yet." }, true)
    end
    add(M.formatTables(db, situations, areas, opts.markdown), true)
    if not opts.markdown then add(M.formatDetails(db, byKey, areas), true) end
    return out
end

---------------------------------------------------------------------------
-- Comparing two files
---------------------------------------------------------------------------

-- "blocked / allowed" and "allowed / blocked" are the same answers.
local function answers(cell)
    local parts = {}
    for part in (cell .. " / "):gmatch("(.-) / ") do parts[#parts + 1] = part end
    table.sort(parts)
    return table.concat(parts, " / ")
end

-- Only the cells that differ between two saved tables (`a` the earlier file,
-- `b` the later one). A cell that one of the files does not have is counted,
-- not listed: a situation that was not visited is not a change in the game.
function M.diff(a, b, nameA, nameB)
    a, b = tbl(a), tbl(b)
    local out = {
        "Comparing probe files",
        "  before: " .. (nameA or "first file") .. " (game " .. (a.game ~= nil and clean(a.game) or "unknown") .. ", probe " .. (a.probe ~= nil and clean(a.probe) or "unknown") .. ")",
        "  after:  " .. (nameB or "second file") .. " (game " .. (b.game ~= nil and clean(b.game) or "unknown") .. ", probe " .. (b.probe ~= nil and clean(b.probe) or "unknown") .. ")",
    }
    -- Labels and order from the later file, then anything only the earlier one has.
    local merged = {
        trials = {}, results = {}, situations = {},
    }
    for _, db in ipairs({ b, a }) do
        for _, t in ipairs(tbl(db.trials)) do merged.trials[#merged.trials + 1] = t end
        for id, row in pairs(tbl(db.results)) do
            if type(id) == "string" and type(row) == "table" then
                merged.results[id] = merged.results[id] or {}
                for key in pairs(row) do
                    if type(key) == "string" then merged.results[id][key] = true end
                end
            end
        end
        for key, s in pairs(tbl(db.situations)) do
            if merged.situations[key] == nil then merged.situations[key] = s end
        end
    end
    local situations = M.situations(merged)
    local areas = M.areas(merged)
    local changed, onlyA, onlyB = 0, 0, 0
    for _, area in ipairs(areas) do
        local areaShown = false
        for _, t in ipairs(area.trials) do
            local trialShown = false
            for _, s in ipairs(situations) do
                local before, after = M.cell(a, t.id, s.key), M.cell(b, t.id, s.key)
                if before and not after then
                    onlyA = onlyA + 1
                elseif after and not before then
                    onlyB = onlyB + 1
                elseif before and after and answers(before) ~= answers(after) then
                    changed = changed + 1
                    if not areaShown then
                        out[#out + 1] = ""
                        out[#out + 1] = area.area
                        areaShown = true
                    end
                    if not trialShown then
                        out[#out + 1] = "  " .. (t.label == clean(t.id) and t.label or t.label .. " (" .. clean(t.id) .. ")")
                        trialShown = true
                    end
                    out[#out + 1] = "    " .. s.text .. ": " .. before .. " -> " .. after
                end
            end
        end
    end
    out[#out + 1] = ""
    out[#out + 1] = changed == 0 and "No cell that both files have differs."
        or plural(changed, "cell differs.", "cells differ.")
    if onlyA > 0 then out[#out + 1] = plural(onlyA, "cell is", "cells are") .. " only in the first file (not run in the second)." end
    if onlyB > 0 then out[#out + 1] = plural(onlyB, "cell is", "cells are") .. " only in the second file (not run in the first)." end
    return out
end

---------------------------------------------------------------------------
-- The command
---------------------------------------------------------------------------

local USAGE = "usage: scripts/read-probe.sh <saved PocketProbe.lua> [--markdown | --details | --log | --diff <other PocketProbe.lua>]"

function M.main(args)
    local path, other, opts, modes = nil, nil, {}, 0
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--markdown" then
            opts.markdown = true
            modes = modes + 1
        elseif a == "--details" then
            opts.detailsOnly = true
            modes = modes + 1
        elseif a == "--log" then
            opts.logOnly = true
            modes = modes + 1
        elseif a == "--diff" then
            i = i + 1
            other = args[i]
            modes = modes + 1
            if not other then return 2, { USAGE } end
        elseif a:sub(1, 2) == "--" or path then
            return 2, { USAGE }
        else
            path = a
        end
        i = i + 1
    end
    if not path or modes > 1 then return 2, { USAGE } end
    local db, err = M.load(path)
    if not db then return 1, { "error: " .. err } end
    if other then
        local otherDb, otherErr = M.load(other)
        if not otherDb then return 1, { "error: " .. otherErr } end
        return 0, M.diff(db, otherDb, path, other)
    end
    return 0, M.format(db, opts)
end

-- Run as a command only when this file is the script luajit was given.
if type(arg) == "table" and type(arg[0]) == "string" and arg[0]:match("read%-probe%.lua$") then
    local status, out = M.main(arg)
    local stream = status == 0 and io.stdout or io.stderr
    for _, line in ipairs(out) do stream:write(line, "\n") end
    os.exit(status)
end

return M
