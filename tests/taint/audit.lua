-- Offline check for calls into Blizzard's Lua (charter 2026-11-24-away-batch.md, rule 2;
-- docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md, Task 2).
--
--   luajit tests/taint/audit.lua <repo root> [wow-ui-source clone] [--list]
--
-- Why: a function Blizzard wrote in Lua runs "in the addon's name" when the addon calls
-- it. If it writes a field or a global, that value carries the addon's mark, and the game
-- may later refuse its own protected actions when it reads it (FCF_SetWindowAlpha wrote
-- oldAlpha on the chat windows, 0.16.0 to 0.16.2). An engine call (a frame's own method,
-- a C_ function) cannot do that.
--
-- What it does: reads every .lua file in the addon's and the probe's TOC, lists each name
-- that is called (Name(...), x:Name(...), x.Name(...), pcall(x.Name, ...)) or named in a
-- string (a hook's target, a function looked up by name), and keeps the ones Blizzard
-- defines in Lua somewhere under Interface/AddOns (function Name(, function X:Name(,
-- function X.Name(, Name = function(), outside Blizzard_APIDocumentationGenerated.
-- Every such name, per file of ours, must have a line in tests/taint/calls.txt:
--
--   name<TAB>our file<TAB>verdict<TAB>reason
--
-- "our file" is the path from the repo root, or * for every file (only with the verdicts
-- ours and engine, where the same reading holds wherever the name is used; a line for one
-- file wins over a * line).
--
-- Verdicts:
--   clean         Blizzard's Lua function is called; it writes no field and no global
--   writes        it writes one: not allowed, the check fails until the call is gone
--   writes-known  it writes one and the call stays for the reason given; printed on every run
--   ours          the same name, but the function called is the addon's own
--   engine        the same name, but what is called is a frame's own engine method or a
--                 C function (on our frame, or on a game frame that has no Lua function of
--                 that name), or the name is only hooked or read, never called
-- The line number of a call is not stored (it moves with every edit); --list prints them.
--
-- A match is by name only, so the verdict is a person's reading of each call, written in
-- the reason. What this cannot see: a function reached through a variable holding it
-- (local f = t.Name; f()), and what a Blizzard function's own callees write beyond the
-- ones read for the reason.
--
-- With the clone (default ~/.cache/wow-ui-source/forever) the names Blizzard defines are
-- read from it and tests/taint/names.txt is rewritten when it changed. Without the clone
-- (CI before the audit step, a fresh machine) names.txt is used as it is, and a called
-- name that is in neither list fails: run this once with the clone.
--
-- Exit 0 and one summary line on pass; exit 1 and FAIL: lines otherwise.

local root, clone, listMode
for i = 1, #arg do
    local a = arg[i]
    if a == "--list" then listMode = true elseif not root then root = a elseif not clone then clone = a end
end
root = root or "."
clone = clone or ((os.getenv("HOME") or "") .. "/.cache/wow-ui-source/forever")
local ADDONS = clone .. "/Interface/AddOns"
local SKIP_DIR = "Blizzard_APIDocumentationGenerated"

local function readfile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function fail(lines)
    for _, l in ipairs(lines) do print(l) end
    os.exit(1)
end

---------------------------------------------------------------------------
-- Our files
---------------------------------------------------------------------------

local TOCS = {
    { dir = "addons/PocketEssentials/", toc = "PocketEssentials.toc" },
    { dir = "probe/PocketProbe/", toc = "PocketProbe.toc", optional = true },
}

local files = {} -- { path = repo-relative, text }
for _, t in ipairs(TOCS) do
    local toc = readfile(root .. "/" .. t.dir .. t.toc)
    if not toc and not t.optional then fail({ "FAIL: " .. t.dir .. t.toc .. " is missing" }) end
    for line in (toc or ""):gmatch("[^\r\n]+") do
        if line:match("%.lua%s*$") and not line:match("^#") then
            local name = line:gsub("%s+$", ""):gsub("\\", "/")
            local text = readfile(root .. "/" .. t.dir .. name)
            if not text then fail({ "FAIL: " .. t.dir .. name .. " is listed in the TOC and missing" }) end
            files[#files + 1] = { path = t.dir .. name, text = text }
        end
    end
end

-- Lua source with comments blanked and each string replaced by "" (line breaks kept), and
-- the strings that are one plain name, as { name, line }.
local function strip(src)
    local out, named = {}, {}
    local i, n, line = 1, #src, 1
    local function keepLines(s)
        local _, c = s:gsub("\n", "\n")
        line = line + c
        return ("\n"):rep(c)
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "-" and src:sub(i, i + 1) == "--" then
            local eq = src:match("^%-%-%[(=*)%[", i)
            if eq then
                local close = src:find("]" .. eq .. "]", i, true) or n
                out[#out + 1] = keepLines(src:sub(i, close + #eq + 1))
                i = close + #eq + 2
            else
                local nl = src:find("\n", i, true) or n + 1
                i = nl
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then j = j + 2 elseif d == c or d == "\n" then break else j = j + 1 end
            end
            local body = src:sub(i + 1, j - 1)
            -- A plain name in a string (a hook's target, a function looked up by name). All
            -- capitals is an event or a constant, not a function.
            if body:match("^[%a_][%w_]*$") and body:match("%l") then named[#named + 1] = { body, line } end
            out[#out + 1] = '""'
            i = j + 1
        elseif c == "[" and src:match("^%[=*%[", i) then
            local eq = src:match("^%[(=*)%[", i)
            local close = src:find("]" .. eq .. "]", i, true) or n
            out[#out + 1] = '""' .. keepLines(src:sub(i, close + #eq + 1))
            i = close + #eq + 2
        else
            if c == "\n" then line = line + 1 end
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out), named
end

local KEYWORD = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%S+") do
    KEYWORD[w] = true
end

-- seen[name][path] = { line, ... } for every name called or named in a string; and the
-- names each file defines itself (for the reviewer's "ours").
local seen, order = {}, {}
local function note(name, path, line)
    if KEYWORD[name] then return end
    local byFile = seen[name]
    if not byFile then
        byFile = {}
        seen[name] = byFile
        order[#order + 1] = name
    end
    local lines = byFile[path]
    if not lines then
        lines = {}
        byFile[path] = lines
    end
    if lines[#lines] ~= line then lines[#lines + 1] = line end
end

for _, f in ipairs(files) do
    local text, named = strip(f.text)
    for _, s in ipairs(named) do note(s[1], f.path, s[2]) end
    local lineNo = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        -- Name(  x.Name(  x:Name(   (a definition, "function Name(", is not a call)
        local pos = 1
        while true do
            local s, e, name = line:find("([%a_][%w_]*)%s*%(", pos)
            if not s then break end
            local before = line:sub(1, s - 1)
            if not before:match("function%s+[%w_%.:]*$") then note(name, f.path, lineNo) end
            pos = e + 1
        end
        -- A function handed over by name: pcall(x.Name, ...), PE:Safe(key, x.Name, ...),
        -- securecallfunction(Name, ...): any "x.Name" or "Name" followed by a comma or a
        -- closing bracket inside a call is taken as a possible function value.
        for name in line:gmatch("[%.:]([%a_][%w_]*)%s*[,%)]") do note(name, f.path, lineNo) end
        for name in line:gmatch("pcall%s*%(%s*([%a_][%w_]*)%s*[,%)]") do note(name, f.path, lineNo) end
    end
end

---------------------------------------------------------------------------
-- The names Blizzard defines in Lua
---------------------------------------------------------------------------

local NAMES_FILE = root .. "/tests/taint/names.txt"
local defined = {} -- [name] = "path:line" of one definition (the first in path order)
local haveClone = readfile(ADDONS .. "/Blizzard_FrameXMLBase/Constants.lua") ~= nil
    or io.open(ADDONS .. "/Blizzard_GamepadActionBars/PageUnit.lua", "rb") ~= nil

if haveClone then
    -- One grep over the tree for every way a function gets a name.
    local cmd = "cd '" .. ADDONS:gsub("'", "'\\''") .. "' && LC_ALL=C grep -rn --include='*.lua' -E "
        .. "'(function[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[.:])?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=[[:space:]]*function[[:space:]]*\\(|\\()' . 2>/dev/null"
    local p = io.popen(cmd)
    local all = {}
    for l in p:lines() do all[#all + 1] = l end
    p:close()
    table.sort(all)
    for _, l in ipairs(all) do
        local path, lineNo, code = l:match("^%./([^:]+):(%d+):(.*)$")
        if path and not path:find(SKIP_DIR, 1, true) then
            code = code:gsub("%-%-.*$", "")
            local name = code:match("function%s+[%w_%.]*[%.:]([%a_][%w_]*)%s*%(")
                or code:match("^%s*function%s+([%a_][%w_]*)%s*%(")
                or code:match("([%a_][%w_]*)%s*=%s*function%s*%(")
            if name and not code:match("^%s*local%s+function") and not code:match("^%s*local%s+[%w_]+%s*=%s*function") then
                if seen[name] and not defined[name] then defined[name] = path .. ":" .. lineNo end
            end
        end
    end
    local outLines = {}
    for name, where in pairs(defined) do outLines[#outLines + 1] = name .. "\t" .. where end
    table.sort(outLines)
    -- Every other called name, so a run without the clone can tell a new name from a known one.
    local rest = {}
    for _, name in ipairs(order) do if not defined[name] then rest[#rest + 1] = name .. "\t-" end end
    table.sort(rest)
    for _, l in ipairs(rest) do outLines[#outLines + 1] = l end
    local textOut = table.concat(outLines, "\n") .. "\n"
    if readfile(NAMES_FILE) ~= textOut then
        local f = assert(io.open(NAMES_FILE, "wb"))
        f:write(textOut)
        f:close()
        io.stderr:write("tests/taint/names.txt rewritten from Blizzard's source\n")
    end
else
    local text = readfile(NAMES_FILE)
    if not text then
        fail({ "FAIL: tests/taint/names.txt is missing and there is no copy of Blizzard's source at " .. clone,
            "Run scripts/audit-api.sh once (it fetches the source), then luajit tests/taint/audit.lua ." })
    end
    local known = {}
    for l in text:gmatch("[^\n]+") do
        local name, where = l:match("^([^\t]+)\t(.+)$")
        if name then
            known[name] = true
            if where ~= "-" then defined[name] = where end
        end
    end
    local new = {}
    for _, name in ipairs(order) do
        if not known[name] then new[#new + 1] = name end
    end
    if #new > 0 then
        table.sort(new)
        local out = { "FAIL: names the taint check has not looked up in Blizzard's source (no copy of it here):" }
        for _, name in ipairs(new) do out[#out + 1] = "  " .. name end
        out[#out + 1] = "Run scripts/audit-api.sh (it fetches the source and runs this check with it)."
        fail(out)
    end
end

---------------------------------------------------------------------------
-- calls.txt
---------------------------------------------------------------------------

local VERDICTS = { clean = true, writes = true, ["writes-known"] = true, ours = true, engine = true }
local listed, listOrder = {}, {}
do
    local text = readfile(root .. "/tests/taint/calls.txt")
    if not text then fail({ "FAIL: tests/taint/calls.txt is missing" }) end
    local n = 0
    for l in (text .. "\n"):gmatch("(.-)\r?\n") do
        n = n + 1
        if l ~= "" and l:sub(1, 1) ~= "#" then
            local name, path, verdict, reason = l:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
            if not name or not VERDICTS[verdict] or reason:match("^%s*$") then
                fail({ "FAIL: tests/taint/calls.txt line " .. n .. " is not name<TAB>file<TAB>verdict<TAB>reason: " .. l })
            end
            if path == "*" and verdict ~= "ours" and verdict ~= "engine" then
                fail({ "FAIL: tests/taint/calls.txt line " .. n .. ": * (every file) is only for the verdicts ours and engine: " .. l })
            end
            local key = name .. "\t" .. path
            if listed[key] then fail({ "FAIL: tests/taint/calls.txt lists " .. name .. " in " .. path .. " twice" }) end
            listed[key] = { name = name, path = path, verdict = verdict, reason = reason }
            listOrder[#listOrder + 1] = key
        end
    end
end

local missing, used, tally = {}, {}, { clean = 0, writes = 0, ["writes-known"] = 0, ours = 0, engine = 0 }
local names = {}
for name in pairs(defined) do if seen[name] then names[#names + 1] = name end end
table.sort(names)
for _, name in ipairs(names) do
    local paths = {}
    for path in pairs(seen[name]) do paths[#paths + 1] = path end
    table.sort(paths)
    for _, path in ipairs(paths) do
        local key = name .. "\t" .. path
        local lines = table.concat(seen[name][path], ",")
        local entry = listed[key]
        if not entry and listed[name .. "\t*"] then
            key = name .. "\t*"
            entry = listed[key]
        end
        if listMode then
            print(name .. "\t" .. path .. ":" .. lines .. "\t" .. (entry and entry.verdict or "NOT LISTED") .. "\t" .. defined[name])
        end
        if entry then
            if not used[key] then tally[entry.verdict] = tally[entry.verdict] + 1 end
            used[key] = true
        else
            missing[#missing + 1] = "  " .. name .. "\t" .. path .. ":" .. lines .. "\t(Blizzard: " .. defined[name] .. ")"
        end
    end
end

local out = {}
if #missing > 0 then
    out[#out + 1] = "FAIL: calls into Blizzard's Lua that tests/taint/calls.txt does not list:"
    for _, l in ipairs(missing) do out[#out + 1] = l end
    out[#out + 1] = "Read each function in Blizzard's source. If it writes a field or a global, do the same with the"
    out[#out + 1] = "frame's own engine methods instead. Then add a line: name<TAB>file<TAB>verdict<TAB>reason."
end
local stale, writes, known = {}, {}, {}
for _, key in ipairs(listOrder) do
    local e = listed[key]
    if not used[key] then stale[#stale + 1] = "  " .. e.name .. "\t" .. e.path end
    if used[key] and e.verdict == "writes" then writes[#writes + 1] = "  " .. e.name .. "\t" .. e.path .. "\t" .. e.reason end
    if used[key] and e.verdict == "writes-known" then known[#known + 1] = "  " .. e.name .. "  (" .. e.path .. ")" end
end
if #stale > 0 then
    out[#out + 1] = "FAIL: tests/taint/calls.txt lists calls that are no longer in the code (remove the lines):"
    for _, l in ipairs(stale) do out[#out + 1] = l end
end
if #writes > 0 then
    out[#out + 1] = "FAIL: calls to a Blizzard Lua function that writes a field or a global (charter rule 2):"
    for _, l in ipairs(writes) do out[#out + 1] = l end
end
if #out > 0 then fail(out) end

if #known > 0 then
    print("Taint check: calls that write and are kept (the reason for each is in tests/taint/calls.txt):")
    for _, l in ipairs(known) do print(l) end
end
print(string.format("Taint check: %d calls by name into Blizzard's Lua: %d clean, %d writes kept, %d ours, %d engine%s",
    tally.clean + tally["writes-known"] + tally.ours + tally.engine, tally.clean, tally["writes-known"], tally.ours, tally.engine,
    haveClone and "" or " (names from tests/taint/names.txt; no copy of Blizzard's source here)"))
