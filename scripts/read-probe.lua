-- Reader for the restriction probe's saved file (scripts/read-probe.sh runs this).
--
--   luajit scripts/read-probe.lua <saved PocketProbe.lua> [--markdown | --details | --log | --diff <other PocketProbe.lua>]
--   luajit scripts/read-probe.lua <saved PocketProbe.lua> --perf [--diff <other PocketProbe.lua>]
--
-- --perf prints the performance recordings (probe 0.6.0) instead of the
-- trial results; with --diff it puts the newest recording of each file side
-- by side. Its plain words (probe 0.7.0) leave out the pauses for the fight
-- tests and the 30 seconds after each reload, and give no verdict on less
-- than 10 minutes of samples.
--
-- --details also prints the watchers' armings (probe 0.7.0), as does the
-- full report.
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

-- Area names of probe 0.1.0 and 0.2.0, and the area that holds those trials
-- since 0.3.0, so files of either version group (and compare) the same way.
local AREA_ALIASES = {
    Bags = "Bags and vendor", Vendor = "Bags and vendor",
    Controller = "Controller and layout", Layout = "Controller and layout", Settings = "Controller and layout",
}
M.AREA_ALIASES = AREA_ALIASES

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
        area = AREA_ALIASES[area] or area
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
        plural(#situations, "situation", "situations") .. ", " .. plural(trialCount(areas), "trial", "trials")
            .. (type(tbl(db.options).risky) == "boolean"
                and (", risky trials " .. (db.options.risky and "on" or "off")) or "")
            .. (type(tbl(db.options).auto) == "boolean"
                and (", automatic passes " .. (db.options.auto and "on" or "off")) or ""),
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

-- Trials whose detail entries are readings or answers, not refusals (probe
-- 0.3.0): "info" trials report what they read (counts, settings, names) and
-- "guided" trials the player's answer. A detail entry whose result is
-- "readable" is a reading too (a value trial that noted numbers, probe 0.4.0).
local READING_KINDS = { info = true, guided = true }

local function readingIds(db)
    local ids = {}
    for _, t in ipairs(tbl(tbl(db).trials)) do
        if type(t) == "table" and type(t.id) == "string" and READING_KINDS[t.kind] then ids[t.id] = true end
    end
    return ids
end

-- The detail entries, grouped by trial, printed under a heading.
-- readings: true for the readings and answers, false for the refusals.
local function formatEntries(db, byKey, areas, readings, heading)
    db = tbl(db)
    local reading = readingIds(db)
    local byTrial, total = {}, 0
    for _, d in ipairs(tbl(db.details)) do
        if type(d) == "table" and type(d.trial) == "string" and ((reading[d.trial] == true or d.result == "readable") == readings) then
            byTrial[d.trial] = byTrial[d.trial] or {}
            table.insert(byTrial[d.trial], d)
            total = total + 1
        end
    end
    local out = { heading .. ": " .. plural(total, "entry", "entries") }
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

-- The "Not allowed" section: every refusal entry, grouped by trial.
function M.formatDetails(db, byKey, areas)
    return formatEntries(db, byKey, areas, false, "Not allowed")
end

-- The "Readings and answers" section (probe 0.3.0): what the Errors and
-- Graphics trials read, and the answers to the guided trials. Empty when the
-- file has none.
function M.formatReadings(db, byKey, areas)
    local out = formatEntries(db, byKey, areas, true, "Readings and answers")
    if #out == 1 and out[1]:find(": 0 entries$") then return {} end
    return out
end

local STAGE_WORDS = { restart = "waiting for a full restart of the game", ask = "waiting for the answer" }

-- Guided trials started and not answered yet, with the settings they will put back.
function M.formatGuided(db)
    local guided = tbl(tbl(db).guided)
    local ids = sortedKeys(guided)
    if #ids == 0 then return {} end
    local out = { "Guided trials not answered yet:" }
    for _, id in ipairs(ids) do
        local g = tbl(guided[id])
        local stage = type(g.stage) == "string" and (STAGE_WORDS[g.stage] or clean(g.stage)) or "stage unknown"
        local line = "  " .. clean(id) .. ": " .. stage
        if g.started ~= nil then line = line .. ", started " .. clean(g.started) end
        local back = {}
        local old = tbl(g.old)
        for _, name in ipairs(sortedKeys(old)) do
            local v = old[name]
            back[#back + 1] = clean(name) .. " " .. (v == false and "(not on this client)" or clean(v))
        end
        if #back > 0 then line = line .. "; to put back: " .. table.concat(back, ", ") end
        out[#out + 1] = line
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
-- Which trial had just run when the game first refused something outside a
-- trial (probe 0.2.0, the saved "spoiled" table), one line per situation.
function M.formatSpoiled(db, byKey)
    local spoiled = tbl(tbl(db).spoiled)
    local keys = sortedKeys(spoiled)
    if #keys == 0 then return {} end
    local out = { "The game's own actions were first refused after:" }
    for _, key in ipairs(keys) do
        local s = byKey and byKey[key]
        local name = type(s) == "table" and s.name or nil
        out[#out + 1] = "  " .. clean(spoiled[key]) .. "  (" .. (name ~= nil and clean(name) or clean(key)) .. ")"
    end
    return out
end

function M.format(db, opts)
    opts = opts or {}
    db = tbl(db)
    if opts.logOnly then return M.formatLog(db) end
    local situations, byKey = M.situations(db)
    local areas = M.areas(db)
    if opts.detailsOnly then
        local out = M.formatDetails(db, byKey, areas)
        -- The watchers' armings (probe 0.7.0), when the file has any.
        local watch = M.formatWatch(db)
        if #watch > 0 then
            out[#out + 1] = ""
            for _, line in ipairs(watch) do out[#out + 1] = line end
        end
        return out
    end
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
    if not opts.markdown then
        add(M.formatSpoiled(db, byKey), true)
        add(M.formatGuided(db), true)
        add(M.formatWatch(db), true)
        add(M.formatReadings(db, byKey, areas), true)
        add(M.formatDetails(db, byKey, areas), true)
    end
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
-- Performance recordings (probe 0.6.0, the saved "perf" table; its layout is
-- at the top of probe/PocketProbe/Perf.lua)
---------------------------------------------------------------------------

local ADDON_ROWS = { "Pocket Essentials", "QuestieDB", "Pocket Probe" }
-- The activity letters of a sample, in the order they are printed.
local ACTIVITIES = {
    { letter = "c", word = "in a fight" },
    { letter = "d", word = "in a dungeon" },
    { letter = "v", word = "at a vendor" },
    { letter = "w", word = "world map open" },
    { letter = "b", word = "bags open" },
    { letter = "m", word = "moving" },
    { letter = "s", word = "standing still" },
}
-- The rough marks of the plain-language lines.
local LIGHT_MS, HEAVY_MS = 0.1, 1          -- ms per frame, on average
local LIGHT_KB = 2048                      -- Pocket Essentials' own memory
local GROWING_KB = 60                      -- KB per minute, over at least five minutes
local FEW_HITCHES = 1                      -- frames over 5 ms, per minute

local function num(v)
    return type(v) == "number" and v == v and v or nil
end

-- "1,2,,4" as { 1, 2, nil, 4 }.
local function numberList(text)
    local out, i = {}, 0
    if type(text) ~= "string" then return out end
    for part in (text .. ","):gmatch("([^,]*),") do
        i = i + 1
        out[i] = tonumber(part)
    end
    return out
end

-- One sample line as a table, or nil when it is not a sample line.
function M.perfSample(line)
    if type(line) ~= "string" then return nil end
    local f = {}
    for name, value in line:gmatch("(%a+)=([^;]*)") do f[name] = value end
    if not f.t and not f.dt then return nil end
    local s = {
        t = tonumber(f.t) or 0, dt = math.max(tonumber(f.dt) or 0, 0), tags = f.a or "",
        fps = tonumber(f.fps), mem = numberList(f.mem), pe = numberList(f.pe),
        p = numberList(f.p), all = numberList(f.all), app = tonumber(f.app), f = {},
    }
    for part in (f.f or ""):gmatch("[^,]+") do
        local key, ms, calls, slowest = part:match("^(%d+):([%d%.]+):(%d+):([%d%.]+)$")
        if key then
            s.f[#s.f + 1] = { key = tonumber(key), ms = tonumber(ms) or 0, calls = tonumber(calls) or 0, slowest = tonumber(slowest) or 0 }
        end
    end
    return s
end

-- The runs in the file that can be read, oldest first.
function M.perfRuns(db)
    local out = {}
    for _, r in ipairs(tbl(tbl(tbl(db).perf).runs)) do
        if type(r) == "table" then out[#out + 1] = r end
    end
    return out
end

local function newTally()
    return { seconds = 0, ms = 0, calls = 0, slowest = 0, frames = 0, over = { 0, 0, 0 }, allOver = { 0, 0, 0 },
        recent = 0, recentN = 0, allRecent = 0, shareN = 0, peShare = 0, fps = 0, fpsN = 0, feature = {} }
end

-- Adds one sample to a tally. frames: the frames in its time, estimated.
local function tallyAdd(t, s, frames, keys)
    t.seconds = t.seconds + s.dt
    t.ms, t.calls = t.ms + (s.pe[1] or 0), t.calls + (s.pe[2] or 0)
    if (s.pe[3] or 0) > t.slowest then t.slowest = s.pe[3] end
    if frames then t.frames = t.frames + frames end
    for i = 1, 3 do
        t.over[i] = t.over[i] + (s.p[i + 1] or 0)
        t.allOver[i] = t.allOver[i] + (s.all[i + 1] or 0)
    end
    if s.p[1] then
        t.recent, t.recentN = t.recent + s.p[1], t.recentN + 1
        if s.all[1] then t.peShare, t.allRecent, t.shareN = t.peShare + s.p[1], t.allRecent + s.all[1], t.shareN + 1 end
    end
    if s.fps then
        t.fps, t.fpsN = t.fps + s.fps, t.fpsN + 1
        if not t.low or s.fps < t.low then t.low = s.fps end
    end
    for _, e in ipairs(s.f) do
        local name = keys[e.key]
        if type(name) == "string" then t.feature[name] = (t.feature[name] or 0) + e.ms end
    end
end

local function busiest(t)
    local best, bestMs
    for _, name in ipairs(sortedKeys(t.feature)) do
        if not bestMs or t.feature[name] > bestMs then best, bestMs = name, t.feature[name] end
    end
    return best
end

local RELOAD_GAP = 30                      -- seconds after a reload left out of the plain words
local PLAIN_MIN = 600                      -- seconds of samples the plain words need

-- The reloads in a run's samples, in seconds since its start: a sample
-- marked r (probe 0.7.0), or (older files) any sample after the first with
-- dt=0 that is not marked p. Also how many pauses (p) there were.
local function reloadsOf(samples)
    local at, pauses, n = {}, 0, 0
    for _, s in ipairs(samples) do
        n = n + 1
        if s.tags:find("p", 1, true) then
            pauses = pauses + 1
        elseif s.tags:find("r", 1, true) or (n > 1 and s.dt == 0) then
            at[#at + 1] = s.t
        end
    end
    return at, pauses
end

-- True when a sample is left out of the plain words: a pause (p), or any
-- part of its time inside the 30 seconds after a reload.
local function leftOut(s, reloads)
    if s.tags:find("p", 1, true) then return true end
    for _, r in ipairs(reloads) do
        if s.t >= r and s.t - s.dt < r + RELOAD_GAP then return true end
    end
    return false
end

-- Everything the report prints about one run, worked out from its samples.
-- opts.plain (probe 0.7.0): only what the plain words go on, leaving out the
-- pauses for the fight tests and the 30 seconds after each reload.
function M.perfSummary(run, opts)
    run = tbl(run)
    local plain = type(opts) == "table" and opts.plain == true
    local keys = tbl(run.keys)
    local out = {
        started = type(run.started) == "string" and clean(run.started) or nil,
        ended = type(run.ended) == "string" and clean(run.ended) or nil,
        why = type(run.why) == "string" and clean(run.why) or nil,
        addon = type(run.addon) == "string" and clean(run.addon) or nil,
        profiler = type(run.profiler) == "string" and clean(run.profiler) or "unknown",
        features = run.features == true,
        reloads = num(run.reloads) or 0,
        interval = num(run.interval) or 15,
        missing = {}, samples = 0, total = newTally(), byTag = {}, memory = {}, featureRows = {},
    }
    for _, name in ipairs(sortedKeys(tbl(run.missing))) do out.missing[#out.missing + 1] = clean(name) end
    local parsed = {}
    for _, line in ipairs(tbl(run.samples)) do
        local s = M.perfSample(line)
        if s then parsed[#parsed + 1] = s end
    end
    out.reloadsAt, out.pauses = reloadsOf(parsed)
    local lastFps
    for _, s in ipairs(parsed) do
        if plain and leftOut(s, out.reloadsAt) then
            out.leftOutSamples = (out.leftOutSamples or 0) + 1
        else
            out.samples = out.samples + 1
            for i = 1, 3 do
                local kb = s.mem[i]
                -- 0 is no reading (a 0.6.0 file stored it right after a reload).
                if kb and kb > 0 then
                    local m = out.memory[i]
                    if not m then
                        m = { start = kb, min = kb, max = kb, startAt = s.t }
                        out.memory[i] = m
                    end
                    m.min, m.max, m.finish, m.finishAt = math.min(m.min, kb), math.max(m.max, kb), kb, s.t
                end
            end
            if s.dt > 0 then
                local rate = s.fps and lastFps and (s.fps + lastFps) / 2 or s.fps or lastFps
                local frames = rate and rate * s.dt or nil
                if not frames then out.framesUnknown = true end
                tallyAdd(out.total, s, frames, keys)
                for _, a in ipairs(ACTIVITIES) do
                    if s.tags:find(a.letter, 1, true) then
                        out.byTag[a.letter] = out.byTag[a.letter] or newTally()
                        tallyAdd(out.byTag[a.letter], s, frames, keys)
                    end
                end
            end
            lastFps = s.fps or lastFps
        end
    end
    for _, m in ipairs({ 1, 2, 3 }) do
        local mem = out.memory[m]
        if mem then
            local minutes = (mem.finishAt - mem.startAt) / 60
            mem.growth = minutes > 0 and (mem.finish - mem.start) / minutes or nil
        end
    end
    local t = out.total
    out.seconds = t.seconds
    if out.features and t.frames > 0 and not out.framesUnknown then out.msPerFrame = t.ms / t.frames end
    if t.recentN > 0 then out.recent = t.recent / t.recentN end
    if t.shareN > 0 and t.allRecent > 0 then out.share = 100 * t.peShare / t.allRecent end
    local session = tbl(tbl(run.session).pe)
    out.sessionAvg, out.sessionPeak = num(session.avg), num(session.peak)
    -- The per-feature rows: the run's totals, the busiest first.
    for _, key in ipairs(sortedKeys(tbl(run.feat))) do
        local c = run.feat[key]
        if key ~= "*" and type(c) == "table" then
            local row = { key = clean(key), ms = num(c.ms) or 0, calls = num(c.calls) or 0, slowest = num(c.max) or 0 }
            local events = {}
            for _, event in ipairs(sortedKeys(tbl(c.events))) do
                local e = c.events[event]
                if type(e) == "table" then events[#events + 1] = { name = clean(event), ms = num(e.ms) or 0, calls = num(e.calls) or 0 } end
            end
            table.sort(events, function(a, b)
                if a.ms ~= b.ms then return a.ms > b.ms end
                return a.name < b.name
            end)
            row.events = events
            out.featureRows[#out.featureRows + 1] = row
        end
    end
    table.sort(out.featureRows, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.key < b.key
    end)
    return out
end

-- A number for a table cell: up to `places` decimals, "-" when unknown.
local function show(v, places)
    if not num(v) then return "-" end
    local text = string.format("%." .. (places or 1) .. "f", v)
    if text:find(".", 1, true) then text = text:gsub("0+$", ""):gsub("%.$", "") end
    if text == "-0" then text = "0" end
    return text
end

local function duration(seconds)
    seconds = math.floor((num(seconds) or 0) + 0.5)
    if seconds >= 3600 then return string.format("%d h %02d min", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    if seconds >= 60 then return string.format("%d min %d s", math.floor(seconds / 60), seconds % 60) end
    return seconds .. " s"
end

local function perMinute(count, seconds)
    if not num(count) or not num(seconds) or seconds <= 0 then return nil end
    return count * 60 / seconds
end

-- Rows of cells as lines, the columns padded to line up.
local function columns(rows, indent)
    local widths = {}
    for _, row in ipairs(rows) do
        for i, cellText in ipairs(row) do
            if #cellText > (widths[i] or 0) then widths[i] = #cellText end
        end
    end
    local out = {}
    for _, row in ipairs(rows) do
        local cells = {}
        for i, cellText in ipairs(row) do cells[i] = i < #row and pad(cellText, widths[i]) or cellText end
        out[#out + 1] = indent .. table.concat(cells, "  ")
    end
    return out
end

local WHY_WORDS = { stopped = "stopped with Stop", full = "stopped by itself after 2 hours" }

local function runTitle(sum)
    local line = "started " .. (sum.started or "at an unknown time")
    if sum.ended then
        line = line .. ", ended " .. sum.ended
    elseif not sum.why then
        line = line .. ", still running when the file was written"
    end
    if sum.why then line = line .. " (" .. (WHY_WORDS[sum.why] or sum.why) .. ")" end
    return line
end

-- The lines for one run.
function M.formatPerfRun(run, heading)
    local sum = M.perfSummary(run)
    local t = sum.total
    local out = { heading .. ": " .. runTitle(sum) }
    local function add(lines) for _, line in ipairs(lines) do out[#out + 1] = line end end
    out[#out + 1] = "  " .. duration(sum.seconds) .. " recorded, " .. plural(sum.samples, "sample", "samples") .. " (one every "
        .. show(sum.interval, 0) .. " s)" .. (sum.addon and (", Pocket Essentials " .. sum.addon) or "")
        .. (sum.reloads > 0 and (", carried on over " .. plural(sum.reloads, "reload", "reloads")) or "")
    if #sum.missing > 0 then out[#out + 1] = "  Not on this client, so left out: " .. table.concat(sum.missing, ", ") end
    if #sum.reloadsAt > 0 then
        local at = {}
        for i, t in ipairs(sum.reloadsAt) do at[i] = math.floor(t / 60) .. " min" end
        out[#out + 1] = "  Reloads at: " .. table.concat(at, ", ")
    end
    if sum.seconds <= 0 then
        out[#out + 1] = "  Too short: no full sample yet."
        return out, sum
    end
    out[#out + 1] = ""
    if sum.features then
        out[#out + 1] = "  Time in Pocket Essentials' code (its own counters, nothing counted twice)"
        add(columns({
            { "per frame, average", sum.msPerFrame and (show(sum.msPerFrame, 4) .. " ms (frames estimated from the frame rate: about "
                .. show(t.frames, 0) .. ")") or "unknown (no frame rate)" },
            { "total", show(t.ms, 1) .. " ms in " .. plural(t.calls, "run", "runs") .. " (" .. show(perMinute(t.ms, sum.seconds), 1) .. " ms per minute)" },
            { "slowest single run", show(t.slowest, 2) .. " ms" },
        }, "    "))
    else
        out[#out + 1] = "  Time in Pocket Essentials' code: no per-feature numbers (this Pocket Essentials has no measuring hook)."
    end
    out[#out + 1] = ""
    if sum.profiler == "on" then
        out[#out + 1] = "  The game's profiler, for Pocket Essentials"
        local rows = { { "recent average", show(sum.recent, 4) .. " ms per frame (the mean of " .. plural(t.recentN, "reading", "readings") .. ")" } }
        for i, limit in ipairs({ 1, 5, 10 }) do
            rows[#rows + 1] = { "frames over " .. limit .. " ms", show(t.over[i], 0) .. " (" .. show(perMinute(t.over[i], sum.seconds), 2) .. " per minute)" }
        end
        rows[#rows + 1] = { "share of all addons' time", sum.share and (show(sum.share, 1) .. " %") or "unknown" }
        rows[#rows + 1] = { "since the game started", "average " .. show(sum.sessionAvg, 4) .. " ms per frame, peak " .. show(sum.sessionPeak, 2) .. " ms" }
        add(columns(rows, "    "))
    elseif sum.profiler == "off" then
        out[#out + 1] = "  The game's profiler: profiler off on this device, so no numbers from the game."
    else
        out[#out + 1] = "  The game's profiler: not on this client, so no numbers from the game."
    end
    out[#out + 1] = ""
    local rows = { { "Memory (KB)", "start", "least", "most", "end", "growth per minute" } }
    for i, name in ipairs(ADDON_ROWS) do
        local m = sum.memory[i]
        if m then
            rows[#rows + 1] = { name, show(m.start, 0), show(m.min, 0), show(m.max, 0), show(m.finish, 0),
                m.growth and ((m.growth > 0 and "+" or "") .. show(m.growth, 1)) or "-" }
        else
            rows[#rows + 1] = { name, "-", "-", "-", "-", "not loaded or not read" }
        end
    end
    add(columns(rows, "  "))
    out[#out + 1] = "  Frame rate: " .. (t.fpsN > 0 and ("average " .. show(t.fps / t.fpsN, 1) .. ", lowest " .. show(t.low, 1)) or "not read")
    if sum.features then
        out[#out + 1] = ""
        out[#out + 1] = "  Per feature, the busiest first (a run inside another counts in both, so the rows overlap)"
        rows = { { "Feature", "Total ms", "Runs", "ms per run", "Slowest ms", "Busiest events (ms / runs)" } }
        for _, row in ipairs(sum.featureRows) do
            local events = {}
            for i = 1, math.min(3, #row.events) do
                local e = row.events[i]
                events[i] = e.name .. " " .. show(e.ms, 1) .. " / " .. show(e.calls, 0)
            end
            rows[#rows + 1] = { row.key, show(row.ms, 1), show(row.calls, 0), row.calls > 0 and show(row.ms / row.calls, 3) or "-",
                show(row.slowest, 2), #events > 0 and table.concat(events, ", ") or "-" }
        end
        if #rows == 1 then rows[#rows + 1] = { "(nothing ran)" } end
        add(columns(rows, "    "))
    end
    out[#out + 1] = ""
    out[#out + 1] = "  By activity (a sample counts under every activity seen in its " .. show(sum.interval, 0) .. " s, so the rows overlap)"
    rows = { { "Activity", "Time", "ms per frame", "Slowest ms", "Over 5 ms per min", "Frame rate", "Busiest feature" } }
    for _, a in ipairs(ACTIVITIES) do
        local tag = sum.byTag[a.letter]
        if tag then
            rows[#rows + 1] = { a.word, duration(tag.seconds),
                sum.features and tag.frames > 0 and show(tag.ms / tag.frames, 4) or "-",
                sum.features and show(tag.slowest, 2) or "-",
                sum.profiler == "on" and show(perMinute(tag.over[2], tag.seconds), 2) or "-",
                tag.fpsN > 0 and show(tag.fps / tag.fpsN, 1) or "-",
                busiest(tag) or "-" }
        end
    end
    add(columns(rows, "    "))
    return out, sum
end

-- The plain-language lines for one run, and the overall word.
function M.perfVerdict(sum)
    local out, words = {}, {}
    local perFrame, from = sum.msPerFrame, "its own counters"
    if not perFrame and sum.profiler == "on" then perFrame, from = sum.recent, "the game's profiler" end
    if perFrame then
        local word = perFrame < LIGHT_MS and "light" or perFrame >= HEAVY_MS and "heavy" or "in between"
        words[#words + 1] = word
        out[#out + 1] = "  Time: " .. word .. ". Pocket Essentials used about " .. show(perFrame, 4) .. " ms of each frame, by " .. from
            .. " (light is under " .. LIGHT_MS .. " ms, heavy is " .. HEAVY_MS .. " ms or more)."
    else
        out[#out + 1] = "  Time: cannot tell. No per-feature numbers and no profiler numbers in this run."
    end
    local mem = sum.memory[1]
    if mem then
        local growing = sum.seconds >= 300 and mem.growth and mem.growth >= GROWING_KB
        local word = growing and "heavy" or mem.max < LIGHT_KB and "light" or "in between"
        words[#words + 1] = word
        out[#out + 1] = "  Memory: " .. word .. ". Pocket Essentials held at most " .. show(mem.max / 1024, 2) .. " MB (light is under "
            .. show(LIGHT_KB / 1024, 0) .. " MB) and " .. (growing and ("kept growing, by about " .. show(mem.growth, 0) .. " KB a minute")
                or "did not keep growing") .. "."
    else
        out[#out + 1] = "  Memory: not read."
    end
    if sum.profiler == "on" then
        local rate = perMinute(sum.total.over[2], sum.seconds) or 0
        local few = rate < FEW_HITCHES
        if not few then words[#words + 1] = "in between" end
        out[#out + 1] = "  Hitches: " .. (few and "few" or "some") .. ". " .. plural(sum.total.over[2], "frame", "frames")
            .. " spent over 5 ms in Pocket Essentials in " .. duration(sum.seconds) .. " (few is under " .. FEW_HITCHES .. " a minute)."
    else
        out[#out + 1] = "  Hitches: cannot tell (profiler " .. (sum.profiler == "off" and "off" or "not on this client") .. ")."
    end
    local overall = #words == 0 and "cannot tell" or "light"
    for _, word in ipairs(words) do
        if word == "heavy" then overall = "heavy" elseif word == "in between" and overall ~= "heavy" then overall = "in between" end
    end
    out[#out + 1] = "  Overall: " .. overall .. "."
    return out, overall
end

-- Everything --perf prints for one file.
function M.formatPerf(db)
    db = tbl(db)
    local runs = M.perfRuns(db)
    local out = {
        "Performance recording",
        "Game " .. (db.game ~= nil and clean(db.game) or "unknown") .. ", probe " .. (db.probe ~= nil and clean(db.probe) or "unknown"),
    }
    if #runs == 0 then
        out[#out + 1] = ""
        out[#out + 1] = "No recording in this file. (Recording needs probe 0.6.0 or later with Pocket Essentials switched on.)"
        return out
    end
    out[#out + 1] = plural(#runs, "run", "runs") .. " in this file, the newest last"
    local newest
    for i, run in ipairs(runs) do
        out[#out + 1] = ""
        local lines, sum = M.formatPerfRun(run, "Run " .. i .. " of " .. #runs)
        for _, line in ipairs(lines) do out[#out + 1] = line end
        newest = sum
    end
    out[#out + 1] = ""
    out[#out + 1] = "In plain words (the newest run)"
    if newest.seconds <= 0 then
        out[#out + 1] = "  Too short to say anything."
    else
        for _, line in ipairs(M.perfPlain(runs[#runs])) do out[#out + 1] = line end
    end
    return out
end

-- What the plain words leave out of a run, as words, or nil.
local function leftOutText(sum)
    local parts = {}
    if #sum.reloadsAt > 0 then parts[#parts + 1] = "the 30 s after each of " .. plural(#sum.reloadsAt, "reload", "reloads") end
    if sum.pauses > 0 then parts[#parts + 1] = plural(sum.pauses, "pause", "pauses") .. " for the fight tests" end
    if #parts == 0 then return nil end
    return table.concat(parts, " and ")
end

-- The plain words for one run (probe 0.7.0): they leave out the pauses for
-- the fight tests and the 30 seconds after each reload, and give no verdict
-- on less than 10 minutes of samples. Returns the lines, then the overall
-- word ("too short to judge" when there is none) and the reason.
function M.perfPlain(run)
    local sum = M.perfSummary(run, { plain = true })
    local left = leftOutText(sum)
    if sum.seconds < PLAIN_MIN then
        local have, need = duration(sum.seconds) .. " of samples to go on", (duration(PLAIN_MIN):gsub(" 0 s$", "")) .. " needed"
        return { "  Too short to judge: " .. have .. " (" .. need .. ")" .. (left and (", after leaving out " .. left) or "") .. "." },
            "too short to judge", have .. ", " .. need
    end
    local lines, overall = M.perfVerdict(sum)
    if left then table.insert(lines, 1, "  Left out of these words: " .. left .. ".") end
    return lines, overall
end

local function change(before, after)
    if not num(before) or not num(after) then return "-" end
    if before == after then return "same" end
    if before == 0 then return "new" end
    local pct = (after - before) / math.abs(before) * 100
    return (pct > 0 and "+" or "") .. show(pct, 0) .. " %"
end

-- The newest run of two files side by side (`a` the earlier file, `b` the later one).
function M.perfDiff(a, b, nameA, nameB)
    a, b = tbl(a), tbl(b)
    local runsA, runsB = M.perfRuns(a), M.perfRuns(b)
    local out = { "Comparing performance recordings (the newest run of each file)" }
    local sides = { { "before", nameA or "first file", runsA }, { "after", nameB or "second file", runsB } }
    local sums = {}
    for i, side in ipairs(sides) do
        local run = side[3][#side[3]]
        if not run then
            out[#out + 1] = "  " .. side[1] .. ": " .. side[2] .. " has no recording."
        else
            sums[i] = M.perfSummary(run)
            out[#out + 1] = "  " .. pad(side[1] .. ":", 8) .. side[2] .. " (" .. runTitle(sums[i]) .. ", " .. duration(sums[i].seconds)
                .. (sums[i].addon and (", Pocket Essentials " .. sums[i].addon) or "") .. ")"
        end
    end
    local x, y = sums[1], sums[2]
    if not x or not y then
        out[#out + 1] = ""
        out[#out + 1] = "Nothing to compare."
        return out
    end
    if x.seconds <= 0 or y.seconds <= 0 then
        out[#out + 1] = ""
        out[#out + 1] = "Nothing to compare: a run is too short."
        return out
    end
    local function mem(sum, field) return sum.memory[1] and sum.memory[1][field] or nil end
    local function fps(sum) return sum.total.fpsN > 0 and sum.total.fps / sum.total.fpsN or nil end
    local function hook(sum, v) return sum.features and v or nil end
    local function prof(sum, v) return sum.profiler == "on" and v or nil end
    local rows = { { "Headline", "Before", "After", "Change" } }
    local function row(name, before, after, places)
        rows[#rows + 1] = { name, show(before, places), show(after, places), change(before, after) }
    end
    row("ms per frame, average", x.msPerFrame, y.msPerFrame, 4)
    row("ms per minute", hook(x, perMinute(x.total.ms, x.seconds)), hook(y, perMinute(y.total.ms, y.seconds)), 1)
    row("slowest single run, ms", hook(x, x.total.slowest), hook(y, y.total.slowest), 2)
    row("profiler: recent ms per frame", x.recent, y.recent, 4)
    for i, limit in ipairs({ 1, 5, 10 }) do
        row("profiler: frames over " .. limit .. " ms per minute", prof(x, perMinute(x.total.over[i], x.seconds)),
            prof(y, perMinute(y.total.over[i], y.seconds)), 2)
    end
    row("share of all addons' time, %", x.share, y.share, 1)
    row("Pocket Essentials memory, most, KB", mem(x, "max"), mem(y, "max"), 0)
    row("Pocket Essentials memory growth, KB per minute", mem(x, "growth"), mem(y, "growth"), 1)
    row("frame rate, average", fps(x), fps(y), 1)
    row("frame rate, lowest", x.total.low, y.total.low, 1)
    out[#out + 1] = ""
    for _, line in ipairs(columns(rows, "  ")) do out[#out + 1] = line end
    out[#out + 1] = ""
    if not x.features or not y.features then
        out[#out + 1] = "Per feature: no per-feature numbers in " .. (not x.features and not y.features and "either file"
            or not x.features and "the first file" or "the second file") .. "."
    else
        local byKey, order = {}, {}
        for i, sum in ipairs({ x, y }) do
            for _, f in ipairs(sum.featureRows) do
                if not byKey[f.key] then
                    byKey[f.key] = {}
                    order[#order + 1] = f.key
                end
                byKey[f.key][i] = f
            end
        end
        local function rate(f, sum) return f and perMinute(f.ms, sum.seconds) or nil end
        table.sort(order, function(k1, k2)
            local m1 = math.max(rate(byKey[k1][1], x) or 0, rate(byKey[k1][2], y) or 0)
            local m2 = math.max(rate(byKey[k2][1], x) or 0, rate(byKey[k2][2], y) or 0)
            if m1 ~= m2 then return m1 > m2 end
            return k1 < k2
        end)
        out[#out + 1] = "Per feature (ms per minute, so runs of different lengths compare)"
        rows = { { "Feature", "Before", "After", "Change", "ms per run before", "after", "Slowest ms before", "after" } }
        for _, key in ipairs(order) do
            local f, g = byKey[key][1], byKey[key][2]
            local function perRun(v) return v and v.calls > 0 and v.ms / v.calls or nil end
            rows[#rows + 1] = { key, show(rate(f, x), 1), show(rate(g, y), 1), change(rate(f, x), rate(g, y)),
                show(perRun(f), 3), show(perRun(g), 3), show(f and f.slowest, 2), show(g and g.slowest, 2) }
        end
        if #order == 0 then rows[#rows + 1] = { "(nothing ran)" } end
        for _, line in ipairs(columns(rows, "  ")) do out[#out + 1] = line end
    end
    out[#out + 1] = ""
    out[#out + 1] = "In plain words"
    for i = 1, 2 do
        local side = sides[i]
        local lines, overall, why = M.perfPlain(side[3][#side[3]])
        if why then
            out[#out + 1] = "  " .. side[1] .. ": " .. overall .. " (" .. why .. ")"
        else
            out[#out + 1] = "  " .. side[1] .. ": " .. overall
            for k = 1, #lines - 1 do out[#out + 1] = "  " .. lines[k] end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The watchers (probe 0.7.0, the saved "watch" table; its layout is at the
-- top of probe/PocketProbe/Watch.lua). Printed by --details and in the full
-- report; nothing when the file has none.
---------------------------------------------------------------------------

local WATCH_WHY = { disarmed = "Disarm", reload = "ended by a reload or a logout", cleared = "ended by Clear saved results" }
local WATCH_BARS = { "main", "left", "right", "both", "other", "secret", "error" }
local WATCH_PRESS = { "main", "left", "right", "both" }
local WATCH_EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "UPDATE_BONUS_ACTIONBAR" }

local function count(pair, side)
    return num(tbl(pair)[side]) or 0
end

local function armingLines(i, w)
    local out = {}
    local line = "  Arming " .. i .. ": started " .. (w.started ~= nil and clean(w.started) or "at an unknown time")
    if w.ended ~= nil then line = line .. ", ended " .. clean(w.ended) end
    if w.why ~= nil then
        line = line .. " (" .. (WATCH_WHY[w.why] or clean(w.why)) .. ")"
    elseif w.ended == nil then
        line = line .. " (still armed when the file was written)"
    end
    out[#out + 1] = line
    local events = tbl(w.events)
    local secs = tbl(events._secs)
    local inFight, outFight = num(secs.c) or 0, num(secs.o) or 0
    out[#out + 1] = "    Time: " .. duration(inFight) .. " in fights, " .. duration(outFight) .. " out of them"
    -- The active bar.
    local bar = tbl(w.bar)
    if bar.missing ~= nil then out[#out + 1] = "    Active bar: not watched (not found: " .. clean(bar.missing) .. ")" end
    local parts = {}
    for _, name in ipairs(WATCH_BARS) do
        if type(bar[name]) == "table" then
            parts[#parts + 1] = name .. " " .. show(count(bar[name], "c"), 0) .. " / " .. show(count(bar[name], "o"), 0)
        end
    end
    if #parts > 0 then
        out[#out + 1] = "    Active bar, in a fight / out of one: " .. table.concat(parts, ", ")
    elseif bar.missing == nil then
        out[#out + 1] = "    Active bar: no change seen"
    end
    local first = {}
    for _, change in ipairs(tbl(bar.first)) do
        if type(change) == "string" then first[#first + 1] = clean(change) end
    end
    if #first > 0 then
        out[#out + 1] = "    First changes (seconds since Arm; bar; c in a fight, o out of one): " .. table.concat(first, ", ")
    end
    -- The presses.
    local press = tbl(w.press)
    if press.missing ~= nil then
        out[#out + 1] = "    Presses: not watched (not found: " .. clean(press.missing) .. ")"
    else
        local sides = {}
        for _, side in ipairs({ "c", "o" }) do
            local per = {}
            for _, name in ipairs(WATCH_PRESS) do
                local p = press[name]
                if type(p) == "table" then
                    local down, up, other = count(p.down, side), count(p.up, side), count(p.other, side)
                    if down + up + other > 0 then
                        per[#per + 1] = name .. " " .. show(down, 0) .. " / " .. show(up, 0)
                            .. (other > 0 and (" (" .. show(other, 0) .. " unreadable)") or "")
                    end
                end
            end
            sides[#sides + 1] = (side == "c" and "in a fight: " or "out of one: ") .. (#per > 0 and table.concat(per, ", ") or "none")
        end
        out[#out + 1] = "    Presses (down / up), " .. table.concat(sides, "; ")
        out[#out + 1] = "    \"pressed\" read as: " .. (press.kind ~= nil and clean(press.kind) or "nothing pressed")
            .. "; buttons hooked: " .. show(num(press.hooked), 0)
    end
    -- The events.
    if events.missing ~= nil then out[#out + 1] = "    Events not on this client: " .. clean(events.missing) end
    local rows, listed = {}, {}
    local names = {}
    for _, name in ipairs(WATCH_EVENTS) do names[#names + 1] = name end
    for _, name in ipairs(sortedKeys(events)) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local pair = events[name]
        if not listed[name] and name ~= "_secs" and type(pair) == "table" then
            listed[name] = true
            local c, o = count(pair, "c"), count(pair, "o")
            rows[#rows + 1] = { clean(name), show(perMinute(c, inFight), 1) .. " / " .. show(perMinute(o, outFight), 1),
                "(" .. show(c, 0) .. " / " .. show(o, 0) .. ")" }
        end
    end
    if #rows > 0 then
        out[#out + 1] = "    Events per minute, in a fight / out of one (the counts in brackets):"
        for _, l in ipairs(columns(rows, "      ")) do out[#out + 1] = l end
    end
    -- The cooldown sweep.
    local sw = tbl(w.sweep)
    if sw.result ~= nil then
        out[#out + 1] = "    Cooldown sweep: " .. clean(sw.result)
            .. ", frame shown by itself " .. (sw.shownByItself ~= nil and clean(sw.shownByItself) or "unknown")
            .. ", duration afterwards " .. (sw.durClass ~= nil and clean(sw.durClass) or "unknown")
            .. ", screenshot " .. (sw.screenshot ~= nil and clean(sw.screenshot) or "none")
            .. (num(sw.t) and (", " .. duration(sw.t) .. " after Arm") or "")
            .. (sw.missing ~= nil and (" (not found: " .. clean(sw.missing) .. ")") or "")
    elseif sw.missing ~= nil then
        out[#out + 1] = "    Cooldown sweep: not tried (not found: " .. clean(sw.missing) .. ")"
    else
        out[#out + 1] = "    Cooldown sweep: not tried (nothing was on cooldown in a fight)"
    end
    return out
end

function M.formatWatch(db)
    local list = {}
    for _, w in ipairs(tbl(tbl(db).watch)) do
        if type(w) == "table" then list[#list + 1] = w end
    end
    if #list == 0 then return {} end
    local out = { "Watch my next fights: " .. plural(#list, "arming", "armings") .. ", the newest last" }
    for i, w in ipairs(list) do
        for _, line in ipairs(armingLines(i, w)) do out[#out + 1] = line end
    end
    return out
end

---------------------------------------------------------------------------
-- The command
---------------------------------------------------------------------------

local USAGE = "usage: scripts/read-probe.sh <saved PocketProbe.lua> [--markdown | --details | --log | --diff <other PocketProbe.lua>]\n"
    .. "       scripts/read-probe.sh <saved PocketProbe.lua> --perf [--diff <other PocketProbe.lua>]"

function M.main(args)
    local path, other, opts, modes, perf = nil, nil, {}, 0, false
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
        elseif a == "--perf" then
            perf = true
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
    -- --perf goes alone or with --diff.
    if perf and modes == 1 and not other then return 2, { USAGE } end
    local db, err = M.load(path)
    if not db then return 1, { "error: " .. err } end
    if other then
        local otherDb, otherErr = M.load(other)
        if not otherDb then return 1, { "error: " .. otherErr } end
        if perf then return 0, M.perfDiff(db, otherDb, path, other) end
        return 0, M.diff(db, otherDb, path, other)
    end
    if perf then return 0, M.formatPerf(db) end
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
