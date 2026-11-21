-- Lists the game names the addon uses: luajit tests/api/extract.lua <repo root>
-- Output: "kind<TAB>name" per line, sorted. With a third argument "where" each
-- line also gets the first file:line it was seen at (used by audit.lua).
--
-- How it works
--  * Globals come from LuaJIT bytecode (luajit -bl): a GGET is a real global
--    read, so comments, strings and shadowing locals do not count.
--  * Everything else comes from a small tokenizer over the source that skips
--    comments and strings: C_Namespace.Function, widget methods (":Name(" and
--    "pcall(x.Name,"), Enum.X, events (all-caps strings with an underscore),
--    CVars (string passed to GetCVar/SetCVar, or the Bags CVAR constant).
--  * Names reached only through a string held in a variable cannot be seen by
--    either; those are listed in INDIRECT below and checked to still exist.
-- Blind spots: fields read from a frame (WorldMapFrame.ScrollContainer) are not
-- listed; methods are matched by name alone, so a method our own code also
-- defines (and calls on our own objects) is left out unless it is called on a
-- Blizzard object in the pcall(x.Name, ...) form.

local root, withWhere = arg[1] or ".", arg[2] == "where"
local dir = root .. "/addons/PocketEssentials/"

local function readfile(p)
    local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s
end

local files = {}
for line in readfile(dir .. "PocketEssentials.toc"):gmatch("[^\r\n]+") do
    if line:match("%.lua%s*$") and not line:match("^#") then files[#files + 1] = (line:gsub("%s+$", "")) end
end

-- Lua standard library and names the addon or QuestieDB itself own.
local STD = {}
for w in ([[_G math table string os io type pcall xpcall pairs ipairs next select tostring
    tonumber setmetatable getmetatable rawget rawset rawequal error assert unpack coroutine
    bit require]]):gmatch("%S+") do STD[w] = true end
-- Fields that look like methods but are plain data on a Blizzard frame.
-- (enum values and QuestieDB library members)
local FIELD = {}
for w in ("Account Character Combat Gamepad Mkb NumValues Poor Preset Quest Get RequireContract"):gmatch("%S+") do FIELD[w] = true end
local STRMETHOD = {}   -- (lowercase ones are skipped anyway; kept for clarity)
local OWN = {}
for w in ([[PocketEssentials PocketEssentialsDB LibQuestieDB PocketEssentialsSettingsPanel
    PocketEssentialsFrame QuestieDB]]):gmatch("%S+") do OWN[w] = true end
-- Global names we assign to (slash command tables and the like) are ours.
local function isOwnGlobal(n) return OWN[n] or n:match("^SLASH_") or n:match("^PocketEssentials") end

-- Names the addon reaches through a string in a variable.
local INDIRECT = {
    { "frame",  "ContainerFrameCombinedBags", "Bags.lua", "ContainerFrameCombinedBags" },
    { "global", "UpdateContainerFrameAnchors", "Bags.lua", "UpdateContainerFrameAnchors" },
    { "global", "DisplayInterfaceActionBlockedMessage", "Core.lua", "BLOCKED_MESSAGE_FN" },
    { "method", "OnMapChanged", "QuestIcons.lua", '"OnMapChanged"' },
    { "method", "OnCanvasScaleChanged", "QuestIcons.lua", '"OnCanvasScaleChanged"' },
    -- Real widget methods whose names we also define on our own objects (so by-name exclusion skips them).
    { "method", "RegisterEvent", "Core.lua", "eventFrame.RegisterEvent" },
    { "method", "UnregisterEvent", "Core.lua", "eventFrame.UnregisterEvent" },
    -- Functions read off a Blizzard table into a local and called later (the field-read rule only sees "x and x.Name").
    { "namespace", "ChatFrameUtil.ChooseBoxForSend", "Chat.lua", "util.ChooseBoxForSend" },
    { "namespace", "ChatFrameUtil.OpenChat", "Chat.lua", "util.OpenChat" },
    { "namespace", "ChatFrameUtil.GetActiveWindow", "Chat.lua", "util.GetActiveWindow" },
    { "namespace", "ChatFrameUtil.ResolveChannelName", "Chat.lua", "ChatFrameUtil.ResolveChannelName" },
    -- Real widget methods whose names the addon also defines on its own objects.
    { "method", "SetShown", "UI.lua", ":SetShown(" },
    { "method", "IsEnabled", "UI.lua", "btn:IsEnabled()" },
    -- The addon no longer uses these (the Layout helper went in 0.3.0); the stand-in client offers
    -- them only for the restriction probe's tests, so they are checked against the probe's file.
    { "method", "IsEditModeActive", "../../probe/PocketProbe/Trials.lua", "IsEditModeActive" },
    { "frame", "EditModeManagerFrame", "../../probe/PocketProbe/Trials.lua", "EditModeManagerFrame" },
    { "namespace", "C_EditMode.GetLayouts", "../../probe/PocketProbe/Trials.lua", "C_EditMode.GetLayouts" },
    { "namespace", "C_EditMode.SetActiveLayout", "../../probe/PocketProbe/Trials.lua", "C_EditMode.SetActiveLayout" },
    -- Menu background: the quest menu's function is hooked by its name in a string, and
    -- GetManager is a function on Blizzard's plain "Menu" table (only C_ namespaces are picked up).
    { "global", "QuestMapLogTitleButton_CreateContextMenu", "MenuBackground.lua", "QuestMapLogTitleButton_CreateContextMenu" },
    { "namespace", "Menu.GetManager", "MenuBackground.lua", "Menu.GetManager" },
    { "cvar",   "combinedBags", "Bags.lua", '"combinedBags"' },
    -- Loot sparkles: the setting it writes and the two it watches are held in constants.
    { "cvar",   "outlineModeShowLootEffectWhenDisabled", "LootSparkles.lua", '"outlineModeShowLootEffectWhenDisabled"' },
    { "cvar",   "graphicsQuality", "LootSparkles.lua", "graphicsquality" },
    { "cvar",   "raidGraphicsQuality", "LootSparkles.lua", "raidgraphicsquality" },
    -- D-pad to Sort: Blizzard's two navigation setters and its table of directions are reached by
    -- name (Blizzard_GamepadSmartNavigation/Utility.lua, loaded only with the Gamepad UI); the two
    -- methods are ones we define on our own Sort button for Blizzard's cursor to call
    -- (SmartNavigation.lua, SelectButton).
    { "global", "SmartNavigation_AddJumpNavigationOverride", "Bags.lua", "NAV_ADD" },
    { "global", "SmartNavigation_ClearJumpNavigationOverridesInDirection", "Bags.lua", "NAV_CLEAR" },
    { "frame", "SMART_NAV_INPUT_DIRECTION", "Bags.lua", "NAV_DIRS" },
    { "method", "OnSmartNavSelect", "Bags.lua", "OnSmartNavSelect" },
    { "method", "OnSmartNavDeselect", "Bags.lua", "OnSmartNavDeselect" },
    -- Bag icons: the frame that holds the bag buttons drawn inside the combined bag is reached
    -- by name (Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml:99).
    { "frame", "GamepadBagBar", "Bags.lua", "BAR_NAME" },
    -- Restriction probe 0.3.0, areas Errors and Graphics (not used by the addon itself): checked
    -- against the probe's files so the audit verifies them and the probe's tests may offer them.
    { "event", "LUA_WARNING", "../../probe/PocketProbe/Run.lua", "LUA_WARNING" },
    { "frame", "ScriptErrorsFrame", "../../probe/PocketProbe/Errors.lua", '"ScriptErrorsFrame"' },
    { "method", "DisplayMessageInternal", "../../probe/PocketProbe/Errors.lua", '"DisplayMessageInternal"' },
    { "global", "geterrorhandler", "../../probe/PocketProbe/Errors.lua", '"geterrorhandler"' },
    { "global", "seterrorhandler", "../../probe/PocketProbe/Errors.lua", '"seterrorhandler"' },
    { "global", "ConsoleGetAllCommands", "../../probe/PocketProbe/Errors.lua", '"ConsoleGetAllCommands"' },
    { "namespace", "C_CVar.GetCVarInfo", "../../probe/PocketProbe/Errors.lua", '"C_CVar.GetCVarInfo"' },
    { "namespace", "C_CVar.GetCVarDefault", "../../probe/PocketProbe/Errors.lua", '"C_CVar.GetCVarDefault"' },
    { "namespace", "C_VideoOptions.IsOutlineModeSupported", "../../probe/PocketProbe/Errors.lua", '"C_VideoOptions.IsOutlineModeSupported"' },
    { "namespace", "C_VideoOptions.IsSpellVisualDensitySystemSupported", "../../probe/PocketProbe/Errors.lua", '"C_VideoOptions.IsSpellVisualDensitySystemSupported"' },
    { "cvar", "scriptErrors", "../../probe/PocketProbe/Errors.lua", '"scriptErrors"' },
    { "cvar", "graphicsOutlineMode", "../../probe/PocketProbe/Errors.lua", '"graphicsOutlineMode"' },
    { "cvar", "raidGraphicsOutlineMode", "../../probe/PocketProbe/Errors.lua", '"raidGraphicsOutlineMode"' },
    { "cvar", "graphicsSpellDensity", "../../probe/PocketProbe/Errors.lua", '"graphicsSpellDensity"' },
    { "cvar", "graphicsParticleDensity", "../../probe/PocketProbe/Errors.lua", '"graphicsParticleDensity"' },
    { "cvar", "SoftTargetLowPriorityIcons", "../../probe/PocketProbe/Errors.lua", '"SoftTargetLowPriorityIcons"' },
    { "cvar", "SoftTargetInteract", "../../probe/PocketProbe/Errors.lua", '"SoftTargetInteract"' },
    { "cvar", "OutlineEngineMode", "../../probe/PocketProbe/Errors.lua", '"OutlineEngineMode"' },
    { "cvar", "SoftTargetIconInteract", "../../probe/PocketProbe/Errors.lua", '"SoftTargetIconInteract"' },
    { "cvar", "SoftTargetIconGameObject", "../../probe/PocketProbe/Errors.lua", '"SoftTargetIconGameObject"' },
    { "cvar", "SoftTargetIconEnemy", "../../probe/PocketProbe/Errors.lua", '"SoftTargetIconEnemy"' },}
-- Event names held as table keys rather than strings.
-- Strings that look like events but are other constants.
-- (SMART_NAV_INPUT_DIRECTION is the name of a Blizzard table, listed in INDIRECT above.)
local NOT_AN_EVENT = { PIN_FRAME_LEVEL_QUEST_PING = true, SMART_NAV_INPUT_DIRECTION = true }
local EVENT_TABLES = { ["QuestData.lua"] = "EVENTS" }
-- Tables whose first string in each row is a method name called as obj[name](...).
local METHOD_TABLES = { ["QuestIcons.lua"] = "BLOB_SETTINGS" }

local function tokenize(src)
    local toks, i, n, line = {}, 1, #src, 1
    local function add(t, v) toks[#toks + 1] = { t = t, v = v, line = line } end
    while i <= n do
        local c = src:sub(i, i)
        if c == "\n" then line = line + 1; i = i + 1
        elseif c:match("%s") then i = i + 1
        elseif src:sub(i, i + 1) == "--" then
            local eq = src:match("^%-%-%[(=*)%[", i)
            if eq then
                local _, e = src:find("]" .. eq .. "]", i, true)
                e = e or n
                for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
                i = e + 1
            else
                local e = src:find("\n", i, true) or n + 1
                i = e
            end
        elseif c == '"' or c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
                elseif d == c then break
                else buf[#buf + 1] = d; j = j + 1 end
            end
            add("str", table.concat(buf)); i = j + 1
        elseif src:match("^%[=*%[", i) then
            local eq = src:match("^%[(=*)%[", i)
            local _, e = src:find("]" .. eq .. "]", i, true)
            e = e or n
            local s = src:sub(i, e)
            add("str", s)
            for _ in s:gmatch("\n") do line = line + 1 end
            i = e + 1
        elseif c:match("[%a_]") then
            local w = src:match("^[%w_]+", i); add("name", w); i = i + #w
        elseif c:match("%d") then
            local w = src:match("^[%w%.]+", i); add("num", w); i = i + #w
        elseif src:sub(i, i + 2) == "..." then add("p", "..."); i = i + 3
        elseif src:sub(i, i + 1) == ".." then add("p", ".."); i = i + 2
        else add("p", c); i = i + 1 end
    end
    return toks
end

local out, where = {}, {}
local function emit(kind, name, file, line)
    local k = kind .. "\t" .. name
    if not out[k] then out[k] = true; where[k] = file .. ":" .. line end
end

-- Pass 1: names we define ourselves (methods and fields we assign).
local own = {}
local parsed = {}
for _, f in ipairs(files) do
    local src = readfile(dir .. f)
    local toks = tokenize(src)
    parsed[f] = toks
    for i, t in ipairs(toks) do
        if t.t == "name" and t.v == "function" then
            -- function A.B:Name( / function A.Name(
            local j = i + 1
            local last
            while toks[j] and (toks[j].t == "name" or toks[j].v == "." or toks[j].v == ":") do
                if toks[j].t == "name" then last = toks[j].v end
                j = j + 1
            end
            if last and toks[i + 2] and (toks[i + 2].v == ":" or toks[i + 2].v == ".") then own[last] = true end
        end
        if t.t == "name" and toks[i + 1] and toks[i + 1].v == "=" and toks[i + 2] and toks[i + 2].v == "function" then
            own[t.v] = true
        end
    end
end

-- Pass 2: globals from bytecode.
local function listing(path)
    local p = io.popen("luajit -bl '" .. path .. "' 2>&1")
    local s = p:read("*a"); p:close(); return s
end
local function firstLine(toks, name)
    for _, t in ipairs(toks) do if t.t == "name" and t.v == name then return t.line end end
    return 0
end
for _, f in ipairs(files) do
    local toks = parsed[f]
    for name in listing(dir .. f):gmatch('GGET[^\n]-; "([^"]+)"') do
        if not STD[name] and not isOwnGlobal(name) then
            if not name:match("^C_") and name ~= "Enum" then
                local isFrame = not name:match("%l") or name:match("Frame$") or name:match("Manager$")
                    or name:match("Util$") or name:match("^GameFont") or name == "Minimap"
                    or name == "Constants" or name == "SlashCmdList" or name == "UIParent"
                    or name == "UISpecialFrames"
                if name == "CreateFrame" then isFrame = false end
                emit(isFrame and "frame" or "global", name, f, firstLine(toks, name))
            end
        end
    end
end

-- Pass 3: tokens.
local function isName(t, v) return t and t.t == "name" and (v == nil or t.v == v) end
local function isP(t, v) return t and t.t == "p" and t.v == v end
for _, f in ipairs(files) do
    local toks = parsed[f]
    local eventTable = EVENT_TABLES[f]
    local alias = {}   -- local api = C_Foo  ->  alias.api = "C_Foo"
    local enumAlias = {}   -- local types = ... Enum.Foo  ->  "Enum.Foo" (kept for the file)
    for i, t in ipairs(toks) do
        local nx, n2, pv = toks[i + 1], toks[i + 2], toks[i - 1]
        if isName(pv, "local") and t.t == "name" and isP(nx, "=") then
            local rhs = toks[i + 2]
            local after = toks[i + 3]
            if rhs and rhs.t == "name" and rhs.v:match("^C_%u") and not isP(after, ".") then
                alias[t.v] = rhs.v
            else
                alias[t.v] = nil
            end
        end
        if isName(pv, "local") and t.t == "name" and isP(nx, "=") then
            local j = i + 2
            while toks[j] and toks[j].line == t.line do
                if (isName(toks[j], "Enum") or isName(toks[j], "Constants")) and isP(toks[j + 1], ".") and isName(toks[j + 2]) then
                    enumAlias[t.v] = toks[j].v .. "." .. toks[j + 2].v
                end
                j = j + 1
            end
        end
        -- Enum.A.B, Constants.A.B, and the same through a local alias
        if (isName(t, "Enum") or isName(t, "Constants")) and isP(nx, ".") and isName(n2) and isP(toks[i + 3], ".")
            and isName(toks[i + 4]) and not isP(pv, ".") and not isP(pv, ":") then
            emit("enum", t.v .. "." .. n2.v .. "." .. toks[i + 4].v, f, t.line)
        end
        if t.t == "name" and enumAlias[t.v] and isP(nx, ".") and isName(n2) and not isP(pv, ".") and not isP(pv, ":") then
            emit("enum", enumAlias[t.v] .. "." .. n2.v, f, t.line)
        end
        -- alias.Name -> C_Namespace.Name
        if t.t == "name" and alias[t.v] and isP(nx, ".") and isName(n2) and not isP(pv, ".") and not isP(pv, ":") then
            emit("namespace", alias[t.v] .. "." .. n2.v, f, t.line)
        end
        -- C_Namespace.Function and Enum.X
        if t.t == "name" and t.v:match("^C_%u") and isP(nx, ".") and isName(n2) and not isP(pv, ".") and not isP(pv, ":") then
            emit("namespace", t.v .. "." .. n2.v, f, t.line)
        elseif t.t == "name" and t.v == "Enum" and isP(nx, ".") and isName(n2) and not isP(pv, ".") and not isP(pv, ":") then
            emit("frame", "Enum." .. n2.v, f, t.line)
        end
        -- obj:Method(
        if isP(t, ":") and isName(nx) and not isP(pv, ":") then
            local after = toks[i + 2]
            if after and (isP(after, "(") or after.t == "str" or isP(after, "{")) and not own[nx.v]
                and nx.v:match("^%u") and not STRMETHOD[nx.v] then
                emit("method", nx.v, f, nx.line)
            end
        end
        -- x.Name used as a value: type(x.Name), pcall(x.Name, ...), "x and x.Name"
        if isP(t, ".") and isName(nx) and nx.v:match("^%u%l") and not own[nx.v] and isName(pv)
            and not alias[pv.v] and not pv.v:match("^C_") and pv.v ~= "Enum" and not FIELD[nx.v] then
            local k = i - 1
            while toks[k - 2] and isP(toks[k - 1], ".") and toks[k - 2].t == "name" do k = k - 2 end
            local head, bef = toks[k - 1], toks[k - 2]
            local ctx = false
            if isP(head, "(") and bef and (bef.v == "pcall" or bef.v == "xpcall" or bef.v == "type") then ctx = true end
            if head and (head.v == "and" or head.v == "not") then ctx = true end
            if isP(head, "(") and bef and (bef.v == "not" or bef.v == "and" or bef.v == "if") then ctx = true end
            local nn = toks[i + 2]
            local endsOK = nn and (isP(nn, ",") or isP(nn, ")") or isName(nn, "and") or isName(nn, "then") or isName(nn, "or")
                or isP(nn, "=") or isP(nn, "~"))
            if ctx and endsOK and not isP(nn, "(") then emit("method", nx.v, f, nx.line) end
        end
        -- events: any all-caps string with an underscore (NOT_AN_EVENT lists the few that are not)
        if t.t == "str" and t.v:match("^%u[%u%d]*_[%u%d_]+$") and not NOT_AN_EVENT[t.v] then
            emit("event", t.v, f, t.line)
        end
        -- CVars
        if t.t == "str" and isP(pv, "(") and toks[i - 2] and (toks[i - 2].v == "GetCVar" or toks[i - 2].v == "SetCVar") then
            emit("cvar", t.v, f, t.line)
        end
    end
    -- method names held as strings in a table
    local mt = METHOD_TABLES[f]
    if mt then
        for i, t in ipairs(toks) do
            if isName(t, mt) and isP(toks[i + 1], "=") and isP(toks[i + 2], "{") then
                local depth, j = 1, i + 3
                while toks[j] and depth > 0 do
                    local u = toks[j]
                    if isP(u, "{") then depth = depth + 1 elseif isP(u, "}") then depth = depth - 1 end
                    if depth == 2 and u.t == "str" and isP(toks[j - 1], "{") and u.v:match("^%u%l") then
                        emit("method", u.v, f, u.line)
                    end
                    j = j + 1
                end
            end
        end
    end
    -- event table keys
    if eventTable then
        for i, t in ipairs(toks) do
            if isName(t, eventTable) and isP(toks[i + 1], "=") and isP(toks[i + 2], "{") then
                local depth, j = 1, i + 3
                while toks[j] and depth > 0 do
                    local u = toks[j]
                    if isP(u, "{") then depth = depth + 1 elseif isP(u, "}") then depth = depth - 1 end
                    if depth == 1 and u.t == "name" and isP(toks[j + 1], "=") and u.v:match("^%u[%u%d]*_[%u%d_]+$") then
                        emit("event", u.v, f, u.line)
                    end
                    j = j + 1
                end
            end
        end
    end
end

-- Indirect names: check each is still in the file named.
for _, e in ipairs(INDIRECT) do
    local src = readfile(dir .. e[3])
    local pos = src:find(e[4], 1, true)
    if pos then
        local line = select(2, src:sub(1, pos):gsub("\n", ""))
        emit(e[1], e[2], e[3], line + 1)
    else
        io.stderr:write("extract.lua: indirect name " .. e[2] .. " no longer found in " .. e[3] .. "\n")
        os.exit(1)
    end
end

-- Real methods that share a name with something we define: listed if the
-- addon calls them on a Blizzard object (checked by hand, see the report).
local keys = {}
for k in pairs(out) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
    if withWhere then print(k .. "\t" .. where[k]) else print(k) end
end
