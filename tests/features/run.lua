-- Rule tests, one file per feature area.
--
--   luajit tests/features/run.lua <repo root> [QuestieDB dir] [--addon-dir=PATH]
--
-- Runs every *_test.lua in this folder, in name order. Each file is called with
-- a table T and registers tests with T.test(name, fn); it returns
-- { known = KNOWN_FAILURES }. Every test gets a fresh stand-in client
-- (tests/lib/fakeclient.lua) and a fresh load of the addon. A test file that
-- crashes while loading is reported as one failure and the others still run.
--
-- A test listed in a file's KNOWN_FAILURES that fails prints "known failure"
-- and does not fail the run; a listed test that passes fails the run (the entry
-- must then be removed). Each entry is a real addon problem, reported as a finding.
--
-- Passing here means "passes offline": the rule holds against our stand-in for
-- the game, not that the game behaves the same.
--
-- The quest tests need the unpacked QuestieDB release (T.questieDB, nil when not given): a file
-- that needs it returns { skip = "reason" } when T.questieDB is nil, and the run prints a notice
-- and goes on with the other files. T.new{ quest = true } loads that data into the client (one
-- load per run, shared by every test; the data is only read).
--
-- Prints "Features: N tests, K known failures" on pass; exit 1 and FAIL: lines otherwise.

local root, addonDir, qdbDir
for i = 1, #arg do
    local a = arg[i]
    local dir = a:match("^%-%-addon%-dir=(.+)$")
    if dir then addonDir = dir elseif not root then root = a elseif not qdbDir then qdbDir = a end
end
if not root then
    io.stderr:write("usage: luajit tests/features/run.lua <repo root> [QuestieDB dir] [--addon-dir=PATH]\n")
    os.exit(2)
end

local Client = dofile(root .. "/tests/lib/fakeclient.lua")

---------------------------------------------------------------------------
-- Shared helpers handed to every test file
---------------------------------------------------------------------------

local T = { root = root, Client = Client, questieDB = qdbDir, addonDir = addonDir or (root .. "/addons/PocketEssentials") }
local clients = {}

local function show(v, depth)
    depth = depth or 0
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    if depth > 4 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for _, k in ipairs(keys) do
        local key = (type(k) == "number" and #out + 1 == k) and "" or (tostring(k) .. "=")
        out[#out + 1] = key .. show(v[k], depth + 1)
    end
    return "{" .. table.concat(out, ", ") .. "}"
end
T.show = show

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function T.check(cond, msg)
    if not cond then error(msg or "check failed", 2) end
end

-- Deep equality; the message shows both values.
function T.eq(actual, expected, msg)
    if not same(actual, expected) then
        error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end

-- A fresh client with the addon loaded (the addon runs at login with the saved
-- values given). opts.setup(c) runs before the addon loads; opts.on lists the
-- features to switch on afterwards; opts.saved is the saved-variables table;
-- opts.addonDir loads another copy of the addon (for a test that needs one changed value);
-- opts.quest = true loads QuestieDB into the client (T.questieDB must be set).
function T.new(opts)
    opts = opts or {}
    local c = Client.new({ root = root, addonDir = opts.addonDir or addonDir, saved = opts.saved, gamepadUI = opts.gamepadUI,
        questieDB = opts.quest and qdbDir or nil, shareQuestieDB = true, screen = opts.screen })
    clients[#clients + 1] = c
    if opts.setup then opts.setup(c) end
    local PE = c:loadAddon()
    for _, key in ipairs(opts.on or {}) do PE:SetModuleEnabled(key, true) end
    c:advance(0.1)
    return c, PE
end

-- The addon's chat lines, without the "Pocket Essentials: " tag.
local TAG = "|cffffd100Pocket Essentials|r: "
function T.chatLines(c)
    local out = {}
    for _, line in ipairs(c.chat) do
        if line:sub(1, #TAG) == TAG then out[#out + 1] = line:sub(#TAG + 1) end
    end
    return out
end

-- The (bag, slot) pairs passed to C_Container.UseContainerItem, in order.
function T.sold(c)
    local out = {}
    for _, call in ipairs(c:callsTo("C_Container.UseContainerItem")) do
        out[#out + 1] = { call.args[1], call.args[2] }
    end
    return out
end

-- The text of one of the addon's buttons.
function T.labelOf(btn)
    return btn.GetLabel and btn:GetLabel() or ""
end

local tests = {}
function T.test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

local files = {}
do
    local p = assert(io.popen("ls '" .. root .. "/tests/features/' 2>/dev/null"))
    for line in p:lines() do
        if line:match("_test%.lua$") then files[#files + 1] = line end
    end
    p:close()
    table.sort(files)
end

local failures, known, total, knownCount = {}, {}, 0, 0
for _, file in ipairs(files) do
    tests = {}
    local chunk, err = loadfile(root .. "/tests/features/" .. file)
    local result
    if chunk then
        local ok, res = xpcall(chunk, debug.traceback, T)
        if ok then result = res else err = res end
        chunk = ok and chunk or nil
    end
    if not chunk then
        failures[#failures + 1] = file .. ": could not run the file: " .. tostring(err)
    else
        local knownList = (type(result) == "table" and result.known) or {}
        if type(result) == "table" and result.skip then
            print("notice: " .. file .. " skipped: " .. result.skip)
            tests = {}
        end
        for _, t in ipairs(tests) do
            total = total + 1
            local ok, e = xpcall(t.fn, debug.traceback)
            for i = #clients, 1, -1 do clients[i]:destroy() clients[i] = nil end
            local reason = knownList[t.name]
            local label = t.name
            if ok and reason then
                failures[#failures + 1] = label .. ": listed in KNOWN_FAILURES (" .. reason .. ") but passed; remove the entry"
            elseif not ok and reason then
                knownCount = knownCount + 1
                known[#known + 1] = label .. " (" .. reason .. ")"
            elseif not ok then
                failures[#failures + 1] = label .. ": " .. tostring(e)
            end
        end
        for name in pairs(knownList) do
            local found = false
            for _, t in ipairs(tests) do if t.name == name then found = true end end
            if not found then failures[#failures + 1] = file .. ": KNOWN_FAILURES names no test: " .. name end
        end
    end
end

for _, k in ipairs(known) do print("known failure: " .. k) end
if #files == 0 then failures[#failures + 1] = "no *_test.lua files found in tests/features" end
if #failures > 0 then
    for _, f in ipairs(failures) do print("FAIL: " .. f) end
    os.exit(1)
end
print(string.format("Features: %d tests, %d known failure%s", total, knownCount, knownCount == 1 and "" or "s"))
