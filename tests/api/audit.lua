-- Checks every name tests/api/extract.lua lists against Blizzard's interface
-- source and rewrites tests/api/verified.txt and tests/api/unverified.txt.
--
--   luajit tests/api/audit.lua <repo root> <wow-ui-source clone>
--
-- Exit 0 when every name is verified or already explained in unverified.txt;
-- exit 1 (after writing the files) when a name is neither.
--
-- Evidence in verified.txt is "<path under Interface/AddOns/> documented" (the
-- name is in Blizzard's generated API documentation) or "... used" (the name
-- is only called or defined by Blizzard's own Lua or XML, so its restrictions
-- are unknown). Methods are checked by name only (some widget type has it).

local root, clone = arg[1] or ".", arg[2]
assert(clone, "usage: audit.lua <repo root> <wow-ui-source clone>")
local ADDONS = clone .. "/Interface/AddOns/"
local DOCS = "Blizzard_APIDocumentationGenerated/"

local function sh(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    local s = p:read("*a"); p:close(); return s
end
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function readfile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

-- Index the generated documentation ----------------------------------------
local docNS, docGlobal, docMethod, docEvent, docEnum = {}, {}, {}, {}, {}
local listing = sh("ls " .. q(ADDONS .. DOCS))
for file in listing:gmatch("[^\n]+") do
    local src = readfile(ADDONS .. DOCS .. file)
    if src then
        local path = DOCS .. file
        local ns = src:match('\n\tNamespace = "([^"]+)"')
        local isObject = src:match('Type = "ScriptObject"') ~= nil
        -- Name = "X", Type = "Function", optionally followed by Namespace = "..."
        -- (an empty Namespace on one function means a plain global function).
        for name, ty, after in src:gmatch('Name = "([^"]+)",%s*Type = "([^"]+)",()') do
            local rest = src:sub(after, after + 400)
            if ty == "Function" then
                rest = rest:match("^(.-)\n\t\t},") or rest
                local own = rest:match('Namespace = "([^"]*)"')
                local space = own ~= nil and own or ns
                if space and space ~= "" then docNS[space .. "." .. name] = docNS[space .. "." .. name] or path
                elseif isObject then docMethod[name] = docMethod[name] or path
                else docGlobal[name] = docGlobal[name] or path end
            elseif ty == "Enumeration" then
                docEnum[name] = docEnum[name] or path
            end
        end
        for ev in src:gmatch('LiteralName = "([^"]+)"') do docEvent[ev] = docEvent[ev] or path end
    end
end

-- Searches of the whole Blizzard tree --------------------------------------
local function grepFirst(pattern, extended)
    local flag = extended and "-E" or "-F"
    local out = sh("grep -rIl " .. flag .. " --include='*.lua' --include='*.xml' --exclude-dir=Blizzard_APIDocumentationGenerated -e "
        .. q(pattern) .. " " .. q(ADDONS) .. " | sort | head -1")
    out = out:gsub("\n", "")
    if out == "" then return nil end
    return (out:gsub("^" .. ADDONS:gsub("%p", "%%%0"), ""))
end

local function verify(kind, name)
    if kind == "event" then
        if docEvent[name] then return docEvent[name] .. " documented" end
        local p = grepFirst('"' .. name .. '"')
        return p and (p .. " used")
    elseif kind == "namespace" then
        if docNS[name] then return docNS[name] .. " documented" end
        local ns, fn = name:match("^(.-)%.(.+)$")
        local p = grepFirst("function " .. ns .. "." .. fn .. "(")
            or grepFirst(ns .. "." .. fn .. "(")
        return p and (p .. " used")
    elseif kind == "global" then
        if docGlobal[name] then return docGlobal[name] .. " documented" end
        local p = grepFirst("^[[:space:]]*function " .. name .. "[(]", true)
            or grepFirst("^" .. name .. " = ", true)
            or grepFirst("[^A-Za-z0-9_.:]" .. name .. "[(]", true)
        return p and (p .. " used")
    elseif kind == "method" then
        if docMethod[name] then return docMethod[name] .. " documented" end
        local p = grepFirst("function [A-Za-z_.]*[:.]" .. name .. "[(]", true)
            or grepFirst(name .. " = function", false)
            or grepFirst("[:.]" .. name .. "[(]", true)
        return p and (p .. " used")
    elseif kind == "cvar" then
        local p = grepFirst('"' .. name .. '"')
        return p and (p .. " used")
    elseif kind == "frame" then
        local enum = name:match("^Enum%.(.+)$")
        if enum then
            if docEnum[enum] then return docEnum[enum] .. " documented" end
            local p = grepFirst("Enum[.]" .. enum .. "([^A-Za-z0-9_]|$)", true)
            return p and (p .. " used")
        end
        local p = grepFirst('name="' .. name .. '"')
            or grepFirst("^" .. name .. " = ", true)
            or grepFirst("^local " .. name .. " = ", true)
            or grepFirst("_G[.]" .. name .. " = ", true)
            or grepFirst("(^|[^A-Za-z0-9_.])" .. name .. "($|[^A-Za-z0-9_])", true)
            or grepFirst("_G\\[\"" .. name .. "\"\\] = ", true)
        return p and (p .. " used")
    end
end

-- Run ------------------------------------------------------------------------
local names = {}
local p = io.popen("luajit " .. q(root .. "/tests/api/extract.lua") .. " " .. q(root) .. " where")
for line in p:lines() do
    local kind, name, at = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
    names[#names + 1] = { kind = kind, name = name, at = at }
end
assert(p:close(), "extract.lua failed")

local oldReason = {}
local old = readfile(root .. "/tests/api/unverified.txt")
if old then
    for line in old:gmatch("[^\n]+") do
        local k, n, r = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
        if k then oldReason[k .. "\t" .. n] = r end
    end
end

local verified, unverified, unexplained = {}, {}, {}
for _, e in ipairs(names) do
    local key = e.kind .. "\t" .. e.name
    local ev = verify(e.kind, e.name)
    if ev then
        verified[#verified + 1] = key .. "\t" .. ev
    elseif oldReason[key] then
        unverified[#unverified + 1] = key .. "\t" .. oldReason[key]
    else
        unverified[#unverified + 1] = key .. "\tNOT YET EXPLAINED"
        unexplained[#unexplained + 1] = e
    end
end
table.sort(verified); table.sort(unverified)

local function write(path, lines)
    local f = assert(io.open(path, "wb"))
    for _, l in ipairs(lines) do f:write(l, "\n") end
    f:close()
end
write(root .. "/tests/api/verified.txt", verified)
write(root .. "/tests/api/unverified.txt", unverified)

local nDoc, nUsed = 0, 0
for _, l in ipairs(verified) do if l:match("documented$") then nDoc = nDoc + 1 else nUsed = nUsed + 1 end end
print(string.format("API audit: %d names, %d documented, %d used only, %d unverified",
    #names, nDoc, nUsed, #unverified))
if #unexplained > 0 then
    print("Names that are neither verified nor explained in tests/api/unverified.txt:")
    for _, e in ipairs(unexplained) do print("  " .. e.kind .. " " .. e.name .. "  (" .. e.at .. ")") end
    os.exit(1)
end
