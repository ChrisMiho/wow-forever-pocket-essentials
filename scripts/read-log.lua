-- Reader for the debug log (scripts/read-log.sh runs this).
--
--   luajit scripts/read-log.lua <saved PocketEssentials.lua> [--grep <lua pattern>] [--errors]
--
-- The saved file is Lua that sets PocketEssentialsDB. It is run in an empty
-- environment (no os, io, require or any other global), text only (compiled
-- code is refused), with a limit on how long it may run.
--
-- The log is a ring (Core.lua "Debug log"): `next` is the slot written next,
-- so once the list has wrapped the oldest line is at `next`.
--
-- Loaded with dofile from a test, this returns its functions and prints nothing.

local M = {}

local SESSION_MARKS = { "---- session ----", "---- debug log switched on ----" }
local STEP_LIMIT = 1e7   -- far more than the largest real file needs

-- The saved table from the file at `path`, or nil and a reason.
function M.load(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, "cannot open " .. tostring(path) .. ": " .. tostring(err) end
    local text = f:read("*a")
    f:close()
    if not text then return nil, "cannot read " .. tostring(path) end
    if text:sub(1, 1) == "\27" then return nil, "this is compiled code, not a saved-settings file; not loading it" end
    local chunk, syntaxErr = loadstring(text, "=saved file")
    if not chunk then return nil, "not a saved-settings file: " .. tostring(syntaxErr) end
    local env = {}
    setfenv(chunk, env)
    -- The step limit needs the interpreter: compiled loops do not count steps.
    if jit then jit.off(chunk, true) end
    debug.sethook(function() error("the file ran for too long; stopped", 0) end, "", STEP_LIMIT)
    local ok, runErr = pcall(chunk)
    debug.sethook()
    if not ok then return nil, "the file could not be read as saved settings: " .. tostring(runErr) end
    local db = rawget(env, "PocketEssentialsDB")
    if type(db) ~= "table" then return nil, "no PocketEssentialsDB in this file" end
    return db
end

-- The debug lines oldest first. `debugTable` is PocketEssentialsDB.debug (anything else gives {}).
function M.ordered(debugTable)
    local out = {}
    if type(debugTable) ~= "table" or type(debugTable.lines) ~= "table" then return out end
    local lines = debugTable.lines
    local n = #lines
    local first = debugTable.next
    -- Not yet wrapped: next is one past the end, and the list starts at 1.
    if type(first) ~= "number" or first % 1 ~= 0 or first < 1 or first > n then first = 1 end
    for i = 0, n - 1 do
        local line = lines[(first - 1 + i) % n + 1]
        if type(line) == "string" then out[#out + 1] = line end
    end
    return out
end

local function isSessionStart(line)
    for _, mark in ipairs(SESSION_MARKS) do
        if line:find(mark, 1, true) then return true end
    end
    return false
end

-- The debug log as output lines: a blank line and a heading before each
-- session. With `pattern`, only matching lines (and the headings of sessions
-- that have one). Returns nil and a reason for a bad pattern.
function M.formatLog(db, pattern)
    local lines = M.ordered(type(db) == "table" and db.debug or nil)
    local out = {}
    if pattern then
        local ok, err = pcall(string.find, "", pattern)
        if not ok then return nil, "bad pattern for --grep: " .. tostring(err) end
    end
    local state = type(db) == "table" and type(db.debug) == "table" and db.debug.on == true and "on" or "off"
    out[#out + 1] = "Debug log: " .. #lines .. " line" .. (#lines == 1 and "" or "s") .. ", switch " .. state
    local session, heading = 0, nil
    if #lines > 0 and not isSessionStart(lines[1]) then
        heading = "== Earlier lines (the start of this session is no longer in the log) =="
    end
    for _, line in ipairs(lines) do
        if isSessionStart(line) then
            session = session + 1
            heading = "== Session " .. session .. " =="
        end
        if not pattern or line:find(pattern) then
            if heading then
                out[#out + 1] = ""
                out[#out + 1] = heading
                heading = nil
            end
            out[#out + 1] = line
        end
    end
    return out
end

-- The Errors page entries as output lines.
function M.formatErrors(db)
    local list = type(db) == "table" and db.errors
    local out, shown = {}, 0
    if type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" then
                shown = shown + 1
                local head = tostring(e.module) .. "   x" .. tostring(tonumber(e.count) or 1)
                if type(e.last) == "number" and e.last > 0 then head = head .. "   last: " .. os.date("%Y-%m-%d %H:%M", e.last) end
                out[#out + 1] = ""
                out[#out + 1] = head
                out[#out + 1] = "  " .. tostring(e.msg)
                if type(e.stack) == "string" and e.stack ~= "" then
                    for stackLine in (e.stack .. "\n"):gmatch("(.-)\r?\n") do
                        if stackLine ~= "" then out[#out + 1] = "    " .. stackLine end
                    end
                end
            end
        end
    end
    table.insert(out, 1, "== Errors page: " .. shown .. " entr" .. (shown == 1 and "y" or "ies") .. " ==")
    return out
end

-- Catch all errors: the other addons' and the game's errors
-- (PocketEssentialsDB.otherErrors, newest first), grouped by source. The
-- source with the most errors comes first; within a source, newest first.
function M.formatOthers(db)
    local list = type(db) == "table" and db.otherErrors
    local groups, order, shown = {}, {}, 0
    if type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" then
                shown = shown + 1
                local source = tostring(e.source or "Unknown")
                local g = groups[source]
                if not g then
                    g = { name = source, total = 0, entries = {} }
                    groups[source] = g
                    order[#order + 1] = g
                end
                g.total = g.total + (tonumber(e.count) or 1)
                g.entries[#g.entries + 1] = e
            end
        end
    end
    table.sort(order, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    local warnings = type(db) == "table" and tonumber(db.luaWarnings) or 0
    local out = { "== Other errors (Catch all errors): " .. shown .. " entr" .. (shown == 1 and "y" or "ies")
        .. ", " .. warnings .. " Lua warning" .. (warnings == 1 and "" or "s") .. " ==" }
    for _, g in ipairs(order) do
        out[#out + 1] = ""
        out[#out + 1] = g.name .. "   " .. g.total .. " time" .. (g.total == 1 and "" or "s")
        for _, e in ipairs(g.entries) do
            local head = "  x" .. tostring(tonumber(e.count) or 1)
            if type(e.last) == "number" and e.last > 0 then head = head .. "   last: " .. os.date("%Y-%m-%d %H:%M", e.last) end
            out[#out + 1] = head
            out[#out + 1] = "    " .. tostring(e.msg)
            if type(e.stack) == "string" and e.stack ~= "" then
                for stackLine in (e.stack .. "\n"):gmatch("(.-)\r?\n") do
                    if stackLine ~= "" then out[#out + 1] = "      " .. stackLine end
                end
            end
        end
    end
    return out
end

-- Everything the command prints. opts: { grep = pattern or nil, errorsOnly = bool }.
function M.format(db, opts)
    opts = opts or {}
    local out = {}
    if not opts.errorsOnly then
        local log, err = M.formatLog(db, opts.grep)
        if not log then return nil, err end
        for _, line in ipairs(log) do out[#out + 1] = line end
    end
    -- A search is for log lines: the Errors page is left out unless asked for.
    if opts.errorsOnly or not opts.grep then
        if #out > 0 then out[#out + 1] = "" end
        for _, line in ipairs(M.formatErrors(db)) do out[#out + 1] = line end
        -- Only when Catch all errors has written something.
        local others = type(db) == "table" and db.otherErrors
        if (type(others) == "table" and #others > 0) or (type(db) == "table" and (tonumber(db.luaWarnings) or 0) > 0) then
            out[#out + 1] = ""
            for _, line in ipairs(M.formatOthers(db)) do out[#out + 1] = line end
        end
    end
    return out
end

local USAGE = "usage: scripts/read-log.sh <saved PocketEssentials.lua> [--grep <lua pattern>] [--errors]"

function M.main(args)
    local path, opts = nil, {}
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--errors" then
            opts.errorsOnly = true
        elseif a == "--grep" then
            i = i + 1
            opts.grep = args[i]
            if not opts.grep then return 2, { USAGE } end
        elseif a:sub(1, 2) == "--" or path then
            return 2, { USAGE }
        else
            path = a
        end
        i = i + 1
    end
    if not path then return 2, { USAGE } end
    local db, err = M.load(path)
    if not db then return 1, { "error: " .. err } end
    local out, formatErr = M.format(db, opts)
    if not out then return 2, { "error: " .. formatErr } end
    return 0, out
end

-- Run as a command only when this file is the script luajit was given.
if type(arg) == "table" and type(arg[0]) == "string" and arg[0]:match("read%-log%.lua$") then
    local status, out = M.main(arg)
    local stream = status == 0 and io.stdout or io.stderr
    for _, line in ipairs(out) do stream:write(line, "\n") end
    os.exit(status)
end

return M
