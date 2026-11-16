-- Fast API check: every name the addon uses (stdin, from extract.lua) must be
-- in tests/api/verified.txt or tests/api/unverified.txt. Needs no network and
-- no copy of Blizzard's source.   luajit tests/api/fastcheck.lua <repo root>
local root = arg[1] or "."
local known, nUnverified = {}, 0
local function load(name, countUnverified)
    local f = io.open(root .. "/tests/api/" .. name, "rb")
    if not f then return end
    for line in f:lines() do
        local k, n = line:match("^([^\t]+)\t([^\t]+)")
        if k then known[k .. "\t" .. n] = true; if countUnverified then nUnverified = nUnverified + 1 end end
    end
    f:close()
end
load("verified.txt"); load("unverified.txt", true)

local total, new = 0, {}
for line in io.lines() do
    total = total + 1
    if not known[line] then new[#new + 1] = line:gsub("\t", " ") end
end
if #new > 0 then
    print("FAIL: the addon uses names the API audit has not seen:")
    for _, n in ipairs(new) do print("  " .. n) end
    print("Run scripts/audit-api.sh to check them against Blizzard's source and update tests/api/.")
    os.exit(1)
end
print(string.format("API audit: %d names, %d unverified, 0 new", total, nUnverified))
