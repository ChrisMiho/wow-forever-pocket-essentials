-- Fast API check: every name the addon uses (stdin, from extract.lua) must be
-- in tests/api/verified.txt or explained in tests/api/unverified.txt. Needs no
-- network and no copy of Blizzard's source.   luajit tests/api/fastcheck.lua <repo root>
-- Fails closed: no names, a missing snapshot, or a "NOT YET EXPLAINED" line is a failure.
local root = arg[1] or "."
local known, nUnverified, unexplained = {}, 0, {}

local function load(name, isUnverified)
    local f = io.open(root .. "/tests/api/" .. name, "rb")
    if not f then
        print("FAIL: tests/api/" .. name .. " is missing. Run scripts/audit-api.sh to create it.")
        os.exit(1)
    end
    for line in f:lines() do
        local k, n, rest = line:match("^([^\t]+)\t([^\t]+)\t?(.*)$")
        if k then
            known[k .. "\t" .. n] = true
            if isUnverified then
                nUnverified = nUnverified + 1
                if rest:find("NOT YET EXPLAINED", 1, true) then unexplained[#unexplained + 1] = k .. " " .. n end
            end
        end
    end
    f:close()
end
load("verified.txt"); load("unverified.txt", true)

local total, new = 0, {}
for line in io.lines() do
    total = total + 1
    if not known[line] then new[#new + 1] = (line:gsub("\t", " ")) end
end

if total == 0 then
    print("FAIL: the extractor listed no names, so nothing was checked. Run luajit tests/api/extract.lua . to see why.")
    os.exit(1)
end
if #unexplained > 0 then
    print("FAIL: tests/api/unverified.txt has names that were never explained (they were not found in Blizzard's source for this client):")
    for _, n in ipairs(unexplained) do print("  " .. n) end
    print("Explain each in docs/ARCHITECTURE.md \"Unverified API\" and give it a plain-language reason in unverified.txt, or fix the addon.")
    os.exit(1)
end
if #new > 0 then
    print("FAIL: the addon uses names the API audit has not seen:")
    for _, n in ipairs(new) do print("  " .. n) end
    print("Run scripts/audit-api.sh to check them against Blizzard's source and update tests/api/.")
    os.exit(1)
end
print(string.format("API audit: %d names, %d unverified, 0 new", total, nUnverified))
