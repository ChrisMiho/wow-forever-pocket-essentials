-- A stand-in for the WoW Forever game client (interface 16001), for running the
-- whole addon off the device under LuaJIT. Used by tests/smoke/run.lua and the
-- feature tests.
--
--   local Client = dofile(root .. "/tests/lib/fakeclient.lua")
--   local c = Client.new({ root = root, questieDB = dir, saved = db, screen = { w, h }, gamepadUI = false })
--   (questieDB = dir loads the release for each client; shareQuestieDB = true loads it once per process.)
--   local PE = c:loadAddon()
--   c:fire("MERCHANT_SHOW"); c:advance(2); c:assertClean(); c:destroy()
--
-- Strict where Blizzard's source lets it be:
--   * A widget has a method only if (a) the method is listed as `method` in
--     tests/api/verified.txt or unverified.txt, and (b) that widget type has it in
--     Blizzard's generated API documentation. Anything else reads as nil, as
--     on the real client, so `frame:Bogus()` raises "attempt to call method
--     'Bogus' (a nil value)" and `type(frame.Bogus) == "function"` is false.
--   * A C_Namespace function exists only if the snapshot lists it, and a
--     global function only if the snapshot lists it. Unknown globals read nil.
--   * Events: RegisterEvent and c:fire refuse names the snapshot does not list.
--   * The addon runs in its own global table (c.env), which holds only what
--     this file installs plus the Lua functions the game has (no os, io,
--     debug, require, loadfile). Nothing it writes reaches the real _G.
--
-- Every name a lookup asked for and did not find is kept in c.missing
-- (["kind name"] = count): the smoke test checks that list.
--
-- Sections: snapshot, widgets (frames and regions), layout, scripts and
-- dispatch, Blizzard frames, namespaces and globals, world, addon loading,
-- test helpers.

local Client = {}
Client.__index = Client

local unpack = unpack or table.unpack
local floor, max, min, huge = math.floor, math.max, math.min, math.huge

---------------------------------------------------------------------------
-- Snapshot (tests/api/*.txt, from Task 1's audit)
---------------------------------------------------------------------------

local snapshotCache = {}

local function ReadSnapshot(root)
    if snapshotCache[root] then return snapshotCache[root] end
    local s = { method = {}, namespace = {}, global = {}, event = {}, cvar = {}, frame = {}, enum = {} }
    local found = false
    for _, file in ipairs({ "verified.txt", "unverified.txt" }) do
        local f = io.open(root .. "/tests/api/" .. file, "rb")
        if f then
            found = true
            for line in f:lines() do
                local kind, name = line:match("^([^\t]+)\t([^\t]+)")
                if kind and s[kind] then s[kind][name] = true end
            end
            f:close()
        end
    end
    if not found then error("fakeclient: tests/api/verified.txt is missing under " .. tostring(root), 2) end
    snapshotCache[root] = s
    return s
end

---------------------------------------------------------------------------
-- Widget types: which methods each has (Blizzard_APIDocumentationGenerated:
-- Simple*APIDocumentation.lua and MinimapFrameAPIDocumentation.lua). Region
-- types inherit ScriptRegion + Region; frame types inherit ScriptRegion + Frame.
---------------------------------------------------------------------------

local function list(s) local t = {} for w in s:gmatch("%S+") do t[#t + 1] = w end return t end

local M_OBJECT = list("GetParent IsForbidden")
local M_SCRIPT_REGION = list([[Show Hide SetShown IsShown IsVisible GetWidth GetHeight GetCenter GetTop
    GetBottom GetLeft GetRight EnableMouse EnableMouseWheel SetMouseMotionEnabled SetScript GetScript HookScript IsProtected
    SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetPoint GetNumPoints]])
local M_REGION = list("GetAlpha SetAlpha GetScale SetScale GetEffectiveScale SetVertexColor CreateAnimationGroup")
local M_TEXTURE = list("SetColorTexture SetTexture SetAtlas SetRotation")
local M_LINE = list("SetColorTexture SetTexture SetStartPoint SetEndPoint SetThickness")
local M_FONT_INSTANCE = list("SetFont GetFont SetFontObject SetTextColor SetShadowColor SetShadowOffset SetJustifyH SetJustifyV")
local M_FONTSTRING = list("SetText GetText SetWordWrap SetMaxLines GetStringHeight GetUnboundedStringWidth SetRotation")
local M_FRAME = list([[GetAlpha SetAlpha GetScale SetScale GetEffectiveScale CreateTexture CreateFontString CreateLine
    CreateAnimationGroup RegisterEvent UnregisterEvent UnregisterAllEvents IsEventRegistered SetFrameStrata
    GetFrameStrata SetFrameLevel GetFrameLevel SetClampedToScreen SetHitRectInsets Raise]])
local M_BUTTON = list("RegisterForClicks IsEnabled SetText GetText")
local M_SCROLLFRAME = list("SetScrollChild SetVerticalScroll")
local M_EDITBOX = list("SetText GetText IsEnabled SetFont GetFont SetFontObject SetTextColor")
local M_MESSAGEFRAME = list("AddMessage SetFont GetFont SetFontObject")
local M_MINIMAP = list([[GetZoom SetQuestBlobInsideAlpha SetQuestBlobOutsideAlpha SetQuestBlobRingAlpha
    SetQuestBlobRingScalar SetTaskBlobInsideAlpha SetTaskBlobOutsideAlpha SetTaskBlobRingAlpha SetTaskBlobRingScalar]])
local M_ANIMGROUP = list("CreateAnimation Play Stop SetToFinalAlpha SetScript GetScript HookScript GetParent IsForbidden")
local M_ANIM = list("SetFromAlpha SetToAlpha SetDuration Play Stop SetScript GetScript HookScript GetParent IsForbidden")
local M_FONT = list("SetFont GetFont SetFontObject SetTextColor SetShadowColor SetShadowOffset SetJustifyH SetJustifyV GetAlpha SetAlpha IsForbidden")

local function concat(...)
    local out = {}
    for i = 1, select("#", ...) do for _, v in ipairs((select(i, ...))) do out[#out + 1] = v end end
    return out
end

local TYPE_METHODS = {
    Texture = concat(M_OBJECT, M_SCRIPT_REGION, M_REGION, M_TEXTURE),
    Line = concat(M_OBJECT, M_SCRIPT_REGION, M_REGION, M_LINE),
    FontString = concat(M_OBJECT, M_SCRIPT_REGION, M_REGION, M_FONT_INSTANCE, M_FONTSTRING),
    Frame = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME),
    Button = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME, M_BUTTON),
    ScrollFrame = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME, M_SCROLLFRAME),
    EditBox = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME, M_EDITBOX),
    ScrollingMessageFrame = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME, M_MESSAGEFRAME),
    Minimap = concat(M_OBJECT, M_SCRIPT_REGION, M_FRAME, M_MINIMAP),
    AnimationGroup = M_ANIMGROUP,
    Alpha = M_ANIM,
    Font = M_FONT,
}
local IS_FRAME = { Frame = true, Button = true, ScrollFrame = true, EditBox = true, ScrollingMessageFrame = true, Minimap = true }
local CREATABLE = { Frame = true, Button = true, ScrollFrame = true } -- what CreateFrame accepts here

local FRAME_SCRIPTS = list([[OnEvent OnUpdate OnShow OnHide OnMouseDown OnMouseUp OnMouseWheel OnEnter OnLeave
    OnSizeChanged OnLoad OnAttributeChanged OnDragStart OnDragStop OnReceiveDrag OnKeyDown OnKeyUp
    OnGamePadButtonDown OnGamePadButtonUp OnGamePadStick]])
local SCRIPTS = {
    Frame = FRAME_SCRIPTS,
    Button = concat(FRAME_SCRIPTS, list("OnClick PreClick PostClick OnDoubleClick")),
    ScrollFrame = concat(FRAME_SCRIPTS, list("OnScrollRangeChanged OnVerticalScroll OnHorizontalScroll")),
    EditBox = concat(FRAME_SCRIPTS, list("OnTextChanged OnEnterPressed OnEscapePressed OnEditFocusGained OnEditFocusLost OnChar")),
    ScrollingMessageFrame = concat(FRAME_SCRIPTS, list("OnHyperlinkClick OnHyperlinkEnter OnHyperlinkLeave")),
    Minimap = FRAME_SCRIPTS,
    AnimationGroup = list("OnPlay OnFinished OnStop OnLoop OnPause OnUpdate"),
    Alpha = list("OnPlay OnFinished OnStop OnLoop OnPause OnUpdate"),
    Texture = {}, Line = {}, FontString = {},
}
local SCRIPT_SET = {}
for t, names in pairs(SCRIPTS) do
    SCRIPT_SET[t] = {}
    for _, n in ipairs(names) do SCRIPT_SET[t][n] = true end
end

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local STRATA = { PARENT = true, BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
    FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

-- Plain Lua the game provides (WoW's Lua 5.1 has no os, io, debug or require).
local STD = {}
for _, k in ipairs(list([[string table math bit coroutine type pairs ipairs next select tostring tonumber pcall
    xpcall error assert setmetatable getmetatable rawget rawset rawequal unpack loadstring setfenv getfenv
    collectgarbage gcinfo _VERSION]])) do STD[k] = _G[k] end

local function DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[DeepCopy(k, seen)] = DeepCopy(x, seen) end
    return out
end
Client.DeepCopy = DeepCopy

local function Pack(...) return { n = select("#", ...), ... } end

---------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------

function Client.new(opts)
    opts = opts or {}
    local root = assert(opts.root, "fakeclient: opts.root (the repo root) is required")
    local snap = ReadSnapshot(root)
    local c = setmetatable({}, Client)
    c.root = root
    c.opts = opts
    c.addonDir = opts.addonDir or (root .. "/addons/PocketEssentials")
    c.snapshot = snap
    c.calls, c.chat, c.errors, c.blocked = {}, {}, {}, {}
    c.missing = {}
    c.now = 1000
    c.stats = { callbacks = 0, addonOnUpdate = 0, addonTimers = 0, timers = 0 }
    c.reloads = 0

    local allowedMethod = {}
    for k in pairs(snap.method) do allowedMethod[k] = true end
    c.allowedMethod = allowedMethod

    local screen = opts.screen or { 1280, 720 }
    local SW, SH = screen.w or screen[1], screen.h or screen[2]
    local UI_H = 768
    local UI_W = UI_H * SW / SH

    -----------------------------------------------------------------------
    -- World: what the game functions below read. Scenarios change it freely.
    -----------------------------------------------------------------------
    local world = {
        bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },  -- [bag][slot] = { itemID, quality, price, locked, count, name }
        bagSizes = { [0] = 16, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
        ignoreJunk = {},             -- [bag] = true: the bag menu's "Ignore when selling junk"
        money = 0,
        merchant = { open = false, canRepair = false, repairCost = 0 },
        inCombat = false,
        group = "none",              -- "none" | "party" | "raid"
        channels = {},               -- { { id = 1, name = "General", disabled = false }, ... }
        guild = nil,                 -- guild name, or nil
        player = { map = nil, x = 0, y = 0, facing = 0 },   -- map nil: no position (loading screen)
        maps = {},                   -- [uiMapID] = { name =, width =, height = } (yards)
        questLog = { quests = {}, focus = nil, watched = {} }, -- quests: { { id, title, complete, objectives, header } }
        cvars = { combinedBags = "0", rotateMinimap = "0" },
        chatLockdown = false,
        layouts = { layouts = {}, activeLayout = 1 },        -- C_EditMode.GetLayouts(); presets not included
        layoutImport = nil,          -- what C_EditMode.ConvertStringToLayoutInfo returns (a layout table), or nil
        gamepadUI = opts.gamepadUI and true or false,
        instance = false, indoors = false,
        minimapZoom = 0,
        realm = "Camelot",
        cursor = { SW / 2, SH / 2 },
        secrets = {},                -- [value] = true: issecretvalue(value) is true
        addons = { Blizzard_WorldMap = true },
        editMode = false,
        worldMapID = nil,            -- the map the world map shows (nil: the player's)
        bagProtected = false,
        spellTargeting = false,      -- a spell is waiting for a target (the cursor)
        repairMode = false,          -- the vendor's repair cursor is up
        openMenu = nil,              -- the open root pop-up menu's frame (Menu.GetManager():GetOpenMenu())
        questMenu = nil,             -- c:openMenu options for the quest log's menu ({ silent = true }: no announcement)
        menuArt = false,             -- true: the atlas "common-dropdown-bg" exists
    }
    c.world = world

    -----------------------------------------------------------------------
    -- Errors and protected calls
    -----------------------------------------------------------------------
    local function Record(where, err)
        c.errors[#c.errors + 1] = { where = where, msg = tostring(err), stack = debug.traceback("", 3) }
    end
    -- Runs fn the way the game runs a script handler: an error goes to the
    -- client's error list (the game's error frame) and does not stop anything else.
    local function Protect(where, fn, ...)
        c.stats.callbacks = c.stats.callbacks + 1
        if c.stats.callbacks > (c.callbackLimit or huge) then
            error("fakeclient: more than 100000 callbacks in one c:advance() (a runaway timer or script loop)", 0)
        end
        local res = Pack(xpcall(fn, function(e)
            c.errors[#c.errors + 1] = { where = where, msg = tostring(e), stack = debug.traceback("", 2) }
            return e
        end, ...))
        if res[1] then return unpack(res, 2, res.n) end
    end
    c._protect = Protect
    c._record = Record

    local function Miss(kind, name)
        local key = kind .. " " .. tostring(name)
        c.missing[key] = (c.missing[key] or 0) + 1
    end

    local function Log(name, ...)
        c.calls[#c.calls + 1] = { name = name, args = Pack(...) }
    end

    -- Where a widget was made: the addon's own file name, or nil.
    -- The first Lua caller outside this file decides (C functions such as pcall are skipped).
    local addonPrefix = "@" .. c.addonDir .. "/"
    local selfSource = debug.getinfo(1, "S").source
    local function CallerFile()
        for level = 3, 30 do
            local info = debug.getinfo(level, "S")
            if not info then return nil end
            local src = info.source or ""
            if info.what ~= "C" and src ~= selfSource then
                if src:sub(1, #addonPrefix) == addonPrefix then return src:sub(#addonPrefix + 1) end
                return nil
            end
        end
        return nil
    end

    -----------------------------------------------------------------------
    -- Widgets
    -----------------------------------------------------------------------
    local W = setmetatable({}, { __mode = "k" }) -- [widget] = state (also the inspection record)
    local allFrames = {}                         -- every frame, in creation order
    local eventOrder = {}                        -- [event] = { frame, ... } in registration order
    local animGroups = {}                        -- playing animation groups
    local env                                    -- the game's global table (made below)
    local UIParent

    local function St(w)
        local st = W[w]
        if not st then error("fakeclient: not a widget of this client: " .. tostring(w), 3) end
        return st
    end

    local function IsWidget(v) return type(v) == "table" and W[v] ~= nil end

    local function IsVisible(w)
        local st = W[w]
        while st do
            if not st.shown then return false end
            local p = st.parent
            if not p then return true end
            st = W[p]
        end
        return false
    end

    local function RunScript(w, name, ...)
        local st = W[w]
        local where = (st.name or st.type) .. ":" .. name
        local main = st.scripts[name]
        if main then Protect(where, main, w, ...) end
        local hooks = st.hooks[name]
        if hooks then
            for i = 1, #hooks do Protect(where .. " (hook)", hooks[i], w, ...) end
        end
    end
    c._runScript = RunScript

    local function VisibilityChanged(w, nowVisible)
        local st = W[w]
        if IS_FRAME[st.type] then RunScript(w, nowVisible and "OnShow" or "OnHide") end
        for _, ch in ipairs(st.children) do
            if W[ch].shown then VisibilityChanged(ch, nowVisible) end
        end
    end

    local function SetShownState(w, v)
        local st = W[w]
        v = v and true or false
        if st.shown == v then return end
        local before = IsVisible(w)
        st.shown = v
        local after = IsVisible(w)
        if before ~= after then VisibilityChanged(w, after) end
    end

    local function EffScale(w)
        local s, st, guard = 1, W[w], 0
        while st do
            s = s * (st.scale or 1)
            if not st.parent then break end
            st = W[st.parent]
            guard = guard + 1
            if guard > 200 then break end
        end
        return s
    end

    -- Screen rectangle (left, right, top, bottom) in UIParent units, or nil
    -- when the region has no position (no anchor), as the game reports it.
    local Rect
    Rect = function(w, depth)
        depth = (depth or 0) + 1
        if depth > 60 then return nil end
        if w == UIParent then return 0, UI_W, UI_H, 0 end
        local st = W[w]
        local s = EffScale(w)
        local pts = st.points
        local width = st.width and st.width * s
        local height = st.height and st.height * s
        if #pts == 0 then
            local sf = st.scrollParent
            if sf then
                local l, _, t = Rect(sf, depth)
                if not l then return nil end
                local top = t + (W[sf].vscroll or 0) * EffScale(sf)
                return l, l + (width or 0), top, top - (height or 0)
            end
            return nil
        end
        local left, right, cx, top, bottom, cy
        for _, p in ipairs(pts) do
            local rel = p.rel or st.parent
            local rl, rr, rt, rb
            if rel then rl, rr, rt, rb = Rect(rel, depth) else rl, rr, rt, rb = 0, UI_W, UI_H, 0 end
            if not rl then return nil end
            local rp = p.relPoint
            local ax = rp:find("LEFT") and rl or rp:find("RIGHT") and rr or (rl + rr) / 2
            local ay = rp:find("TOP") and rt or rp:find("BOTTOM") and rb or (rt + rb) / 2
            ax, ay = ax + p.x * s, ay + p.y * s
            local pt = p.point
            if pt:find("LEFT") then left = ax elseif pt:find("RIGHT") then right = ax else cx = ax end
            if pt:find("TOP") then top = ay elseif pt:find("BOTTOM") then bottom = ay else cy = ay end
        end
        if not (left and right) then
            local wv = width or 0
            if left then right = left + wv
            elseif right then left = right - wv
            else left, right = cx - wv / 2, cx + wv / 2 end
        end
        if not (top and bottom) then
            local hv = height or 0
            if top then bottom = top - hv
            elseif bottom then top = bottom + hv
            else top, bottom = cy + hv / 2, cy - hv / 2 end
        end
        return left, right, top, bottom
    end
    c._rect = Rect

    -- True if `w` (directly or through its anchors) depends on `target`.
    local function DependsOn(w, target, seen)
        if w == nil then return false end
        if w == target then return true end
        seen = seen or {}
        if seen[w] then return false end
        seen[w] = true
        local st = W[w]
        if not st then return false end
        for _, p in ipairs(st.points) do
            if DependsOn(p.rel or st.parent, target, seen) then return true end
        end
        if st.scrollParent and DependsOn(st.scrollParent, target, seen) then return true end
        return false
    end

    local function ResolveRegion(v)
        if type(v) == "string" then
            local r = rawget(env, v)
            if not IsWidget(r) then error("SetPoint(): Couldn't find region named '" .. v .. "'", 3) end
            return r
        end
        return v
    end

    -- Text metrics: about half the font size per character, 1.2 lines.
    local function FontOf(st)
        if st.font then return st.font end
        local obj = st.fontObject
        while obj do
            local ost = W[obj]
            if ost.font then return ost.font end
            obj = ost.fontObject
        end
        return nil
    end
    local function PlainText(text)
        return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|"))
    end

    local METHODS = {}

    local function CheckNumber(v, what)
        if type(v) ~= "number" or v ~= v then error(what .. ": number expected, got " .. tostring(v), 3) end
    end

    -- Object / ScriptRegion
    function METHODS:GetParent() return St(self).parent end
    function METHODS:IsForbidden() return false end
    function METHODS:Show() SetShownState(self, true) end
    function METHODS:Hide() SetShownState(self, false) end
    function METHODS:SetShown(v) SetShownState(self, v) end
    function METHODS:IsShown() return St(self).shown end
    function METHODS:IsVisible() return IsVisible(self) end
    function METHODS:GetWidth()
        local st = St(self)
        if st.width then return st.width end
        local l, r = Rect(self)
        return l and (r - l) / EffScale(self) or 0
    end
    function METHODS:GetHeight()
        local st = St(self)
        if st.height then return st.height end
        local _, _, t, b = Rect(self)
        return t and (t - b) / EffScale(self) or 0
    end
    function METHODS:GetCenter()
        local l, r, t, b = Rect(self)
        if not l then return nil end
        local s = EffScale(self)
        return (l + r) / 2 / s, (t + b) / 2 / s
    end
    function METHODS:GetTop()
        local _, _, t = Rect(self)
        return t and t / EffScale(self) or nil
    end
    function METHODS:GetBottom()
        local _, _, _, b = Rect(self)
        return b and b / EffScale(self) or nil
    end
    function METHODS:GetLeft()
        local l = Rect(self)
        return l and l / EffScale(self) or nil
    end
    function METHODS:GetRight()
        local _, r = Rect(self)
        return r and r / EffScale(self) or nil
    end
    function METHODS:EnableMouse(v) St(self).mouse = v and true or false end
    function METHODS:EnableMouseWheel(v) St(self).wheel = v and true or false end
    function METHODS:SetMouseMotionEnabled(v) St(self).motion = v and true or false end
    function METHODS:SetScript(name, fn)
        local st = St(self)
        if not SCRIPT_SET[st.type][name] then
            error(st.type .. ":SetScript(): " .. st.type .. " has no '" .. tostring(name) .. "' script", 2)
        end
        if fn ~= nil and type(fn) ~= "function" then error(st.type .. ":SetScript(): function or nil expected", 2) end
        st.scripts[name] = fn
        st.hooks[name] = nil -- SetScript replaces the hooks too
    end
    function METHODS:GetScript(name)
        local st = St(self)
        if not SCRIPT_SET[st.type][name] then
            error(st.type .. ":GetScript(): " .. st.type .. " has no '" .. tostring(name) .. "' script", 2)
        end
        return st.scripts[name]
    end
    function METHODS:HookScript(name, fn)
        local st = St(self)
        if not SCRIPT_SET[st.type][name] then
            error(st.type .. ":HookScript(): " .. st.type .. " has no '" .. tostring(name) .. "' script", 2)
        end
        if type(fn) ~= "function" then error(st.type .. ":HookScript(): function expected", 2) end
        local h = st.hooks[name] or {}
        h[#h + 1] = fn
        st.hooks[name] = h
    end
    function METHODS:IsProtected() return St(self).protected and true or false, false end
    function METHODS:SetPoint(point, a, b, cc, d)
        local st = St(self)
        if not POINTS[point] then error("SetPoint(): Invalid region point '" .. tostring(point) .. "'", 2) end
        local rel, relPoint, x, y
        if type(a) == "number" then
            x, y = a, b
        else
            rel = ResolveRegion(a)
            if rel ~= nil and not IsWidget(rel) then error("SetPoint(): relative region expected", 2) end
            if type(b) == "string" then
                if not POINTS[b] then error("SetPoint(): Invalid relative point '" .. b .. "'", 2) end
                relPoint, x, y = b, cc, d
            else
                x, y = b, cc
            end
        end
        relPoint = relPoint or point
        x, y = x or 0, y or 0
        CheckNumber(x, "SetPoint() x offset")
        CheckNumber(y, "SetPoint() y offset")
        if rel == self then error("SetPoint(): Cannot anchor to itself", 2) end
        if rel and DependsOn(rel, self) then error("SetPoint(): Cannot anchor to a region dependent on it", 2) end
        local entry = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        for i, p in ipairs(st.points) do
            if p.point == point then st.points[i] = entry return end
        end
        st.points[#st.points + 1] = entry
    end
    function METHODS:ClearAllPoints() St(self).points = {} end
    function METHODS:SetAllPoints(rel)
        local st = St(self)
        rel = ResolveRegion(rel) or st.parent or UIParent
        if rel == self then error("SetAllPoints(): Cannot anchor to itself", 2) end
        st.points = {
            { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
            { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
        }
    end
    function METHODS:SetSize(w, h)
        CheckNumber(w, "SetSize() width"); CheckNumber(h, "SetSize() height")
        local st = St(self)
        st.width, st.height = w, h
    end
    function METHODS:SetWidth(w) CheckNumber(w, "SetWidth()"); St(self).width = w end
    function METHODS:SetHeight(h) CheckNumber(h, "SetHeight()"); St(self).height = h end
    function METHODS:GetPoint(i)
        local p = St(self).points[i or 1]
        if not p then return nil end
        return p.point, p.rel, p.relPoint, p.x, p.y
    end
    function METHODS:GetNumPoints() return #St(self).points end

    -- Region / Frame shared
    function METHODS:GetAlpha() return St(self).alpha end
    function METHODS:SetAlpha(a)
        CheckNumber(a, "SetAlpha()")
        St(self).alpha = max(0, min(1, a))
    end
    function METHODS:GetScale() return St(self).scale end
    function METHODS:SetScale(s)
        CheckNumber(s, "SetScale()")
        if s <= 0 then error("SetScale(): Scale must be > 0", 2) end
        St(self).scale = s
    end
    function METHODS:GetEffectiveScale() return EffScale(self) end
    function METHODS:SetVertexColor(r, g, b, a) St(self).vertexColor = { r, g, b, a or 1 } end

    -- Textures and lines
    function METHODS:SetColorTexture(r, g, b, a)
        local st = St(self)
        st.color, st.texture = { r, g, b, a or 1 }, nil
    end
    function METHODS:SetTexture(path)
        if path ~= nil and type(path) ~= "string" and type(path) ~= "number" then
            error("SetTexture(): file path or file id expected", 2)
        end
        St(self).texture = path
        return path ~= nil
    end
    function METHODS:SetAtlas(atlas)
        if type(atlas) ~= "string" then error("SetAtlas(): atlas name expected", 2) end
        local st = St(self)
        st.atlas, st.texture, st.color = atlas, nil, nil
    end
    function METHODS:SetRotation(r) CheckNumber(r, "SetRotation()"); St(self).rotation = r end
    function METHODS:SetStartPoint(point, rel, x, y)
        if not POINTS[point] then error("SetStartPoint(): Invalid point", 2) end
        St(self).startPoint = { point, rel, x or 0, y or 0 }
    end
    function METHODS:SetEndPoint(point, rel, x, y)
        if not POINTS[point] then error("SetEndPoint(): Invalid point", 2) end
        St(self).endPoint = { point, rel, x or 0, y or 0 }
    end
    function METHODS:SetThickness(t) CheckNumber(t, "SetThickness()"); St(self).thickness = t end

    -- Fonts and font strings
    function METHODS:SetFont(file, size, flags)
        local st = St(self)
        if type(file) ~= "string" or file == "" or type(size) ~= "number" or size <= 0 then
            if st.type == "Font" then return end
            return false
        end
        st.font = { file, size, flags or "" }
        if st.type ~= "Font" then return true end
    end
    function METHODS:GetFont()
        local f = FontOf(St(self))
        if not f then return nil end
        return f[1], f[2], f[3]
    end
    function METHODS:SetFontObject(obj)
        if type(obj) == "string" then obj = rawget(env, obj) end
        if obj ~= nil and not (IsWidget(obj) and W[obj].type == "Font") then error("SetFontObject(): Font object expected", 2) end
        local st = St(self)
        st.fontObject, st.font = obj, nil
    end
    function METHODS:SetTextColor(r, g, b, a) St(self).textColor = { r, g, b, a or 1 } end
    function METHODS:SetShadowColor(r, g, b, a) St(self).shadowColor = { r, g, b, a or 1 } end
    function METHODS:SetShadowOffset(x, y) St(self).shadowOffset = { x, y } end
    function METHODS:SetJustifyH(v)
        if v ~= "LEFT" and v ~= "CENTER" and v ~= "RIGHT" then error("SetJustifyH(): LEFT, CENTER or RIGHT expected", 2) end
        St(self).justifyH = v
    end
    function METHODS:SetJustifyV(v)
        if v ~= "TOP" and v ~= "MIDDLE" and v ~= "BOTTOM" then error("SetJustifyV(): TOP, MIDDLE or BOTTOM expected", 2) end
        St(self).justifyV = v
    end
    function METHODS:SetText(text)
        local st = St(self)
        if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then error("SetText(): string expected", 2) end
        st.text = text ~= nil and tostring(text) or nil
    end
    function METHODS:GetText() return St(self).text end
    function METHODS:SetWordWrap(v) St(self).wordWrap = v and true or false end
    function METHODS:SetMaxLines(n) CheckNumber(n, "SetMaxLines()"); St(self).maxLines = n end
    function METHODS:GetUnboundedStringWidth()
        local st = St(self)
        local f = FontOf(st)
        if not f then return 0 end
        local widest = 0
        for line in (PlainText(st.text) .. "\n"):gmatch("(.-)\n") do widest = max(widest, #line) end
        return widest * f[2] * 0.5
    end
    function METHODS:GetStringHeight()
        local st = St(self)
        local f = FontOf(st)
        local text = PlainText(st.text)
        if not f or text == "" then return 0 end
        local size = f[2]
        local width = METHODS.GetWidth(self)
        local lines = 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if st.wordWrap ~= false and width and width > 0 then
                lines = lines + max(1, math.ceil(#line * size * 0.5 / width))
            else
                lines = lines + 1
            end
        end
        if st.maxLines and st.maxLines > 0 then lines = min(lines, st.maxLines) end
        return lines * size * 1.2
    end

    -- Frames
    local CreateWidget -- below
    function METHODS:CreateTexture(name, layer, template, sublevel)
        if template ~= nil then error("CreateTexture(): templates are not modelled by the stand-in", 2) end
        return CreateWidget("Texture", name, self, { layer = layer, sublevel = sublevel, level = 3 })
    end
    function METHODS:CreateLine(name, layer, template, sublevel)
        if template ~= nil then error("CreateLine(): templates are not modelled by the stand-in", 2) end
        return CreateWidget("Line", name, self, { layer = layer, sublevel = sublevel, level = 3 })
    end
    function METHODS:CreateFontString(name, layer, fontObject)
        local obj = fontObject
        if type(obj) == "string" then
            obj = rawget(env, fontObject)
            if not (IsWidget(obj) and W[obj].type == "Font") then
                error("CreateFontString(): no font object named '" .. fontObject .. "'", 2)
            end
        end
        local fs = CreateWidget("FontString", name, self, { layer = layer, level = 3 })
        W[fs].fontObject = obj
        return fs
    end
    function METHODS:CreateAnimationGroup(name)
        return CreateWidget("AnimationGroup", name, self, { level = 3 })
    end
    function METHODS:RegisterEvent(event)
        local st = St(self)
        if type(event) ~= "string" or not c.snapshot.event[event] then
            error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
        end
        if not st.events[event] then
            st.events[event] = true
            local order = eventOrder[event] or {}
            order[#order + 1] = self
            eventOrder[event] = order
        end
        return true
    end
    local function DropEvent(self, event)
        local st = W[self]
        st.events[event] = nil
        local order = eventOrder[event]
        if order then
            for i = #order, 1, -1 do if order[i] == self then table.remove(order, i) end end
        end
    end
    function METHODS:UnregisterEvent(event)
        local st = St(self)
        if type(event) ~= "string" or not c.snapshot.event[event] then
            error("Frame:UnregisterEvent(): Attempt to unregister unknown event \"" .. tostring(event) .. "\"", 2)
        end
        if st.events[event] then DropEvent(self, event) end
    end
    function METHODS:UnregisterAllEvents()
        local st = St(self)
        for event in pairs(st.events) do DropEvent(self, event) end
    end
    function METHODS:IsEventRegistered(event)
        local st = St(self)
        if st.events[event] then return true, nil end
        return false, nil
    end
    function METHODS:SetFrameStrata(s)
        if not STRATA[s] then error("SetFrameStrata(): unknown strata '" .. tostring(s) .. "'", 2) end
        St(self).strata = s
    end
    -- A frame that was never given a layer reports the default one.
    function METHODS:GetFrameStrata() return St(self).strata or "MEDIUM" end
    function METHODS:SetFrameLevel(n) CheckNumber(n, "SetFrameLevel()"); St(self).level = floor(n) end
    function METHODS:GetFrameLevel() return St(self).level end
    function METHODS:SetClampedToScreen(v) St(self).clamped = v and true or false end
    function METHODS:SetHitRectInsets(l, r, t, b)
        CheckNumber(l, "SetHitRectInsets()"); CheckNumber(r, "SetHitRectInsets()")
        CheckNumber(t, "SetHitRectInsets()"); CheckNumber(b, "SetHitRectInsets()")
        St(self).hitInsets = { l, r, t, b }
    end
    function METHODS:Raise() local st = St(self); st.raised = (st.raised or 0) + 1 end
    function METHODS:RegisterForClicks(...)
        local st = St(self)
        st.clicks = { ... }
    end
    function METHODS:IsEnabled() return St(self).enabled ~= false end
    function METHODS:SetScrollChild(child)
        local st = St(self)
        if not IsWidget(child) or not IS_FRAME[W[child].type] then error("SetScrollChild(): frame expected", 2) end
        if st.scrollChild then W[st.scrollChild].scrollParent = nil end
        st.scrollChild = child
        W[child].scrollParent = self
    end
    function METHODS:SetVerticalScroll(v) CheckNumber(v, "SetVerticalScroll()"); St(self).vscroll = v end
    function METHODS:AddMessage(text, r, g, b)
        c.chat[#c.chat + 1] = tostring(text)
    end
    function METHODS:GetZoom() return world.minimapZoom end
    local function BlobSetter(name)
        METHODS[name] = function(self, v)
            CheckNumber(v, name .. "()")
            St(self).blob = St(self).blob or {}
            W[self].blob[name] = v
            Log("Minimap:" .. name, v)
        end
    end
    for _, n in ipairs(M_MINIMAP) do if n ~= "GetZoom" then BlobSetter(n) end end

    -- Animation groups (the button flash): played by c:advance().
    function METHODS:CreateAnimation(kind)
        if kind ~= "Alpha" then error("CreateAnimation(): only 'Alpha' is modelled by the stand-in", 2) end
        local a = CreateWidget("Alpha", nil, self, {})
        local st = St(self)
        st.anims[#st.anims + 1] = a
        return a
    end
    function METHODS:SetFromAlpha(v) CheckNumber(v, "SetFromAlpha()"); St(self).fromAlpha = v end
    function METHODS:SetToAlpha(v) CheckNumber(v, "SetToAlpha()"); St(self).toAlpha = v end
    function METHODS:SetDuration(v) CheckNumber(v, "SetDuration()"); St(self).duration = v end
    function METHODS:SetToFinalAlpha(v) St(self).toFinal = v and true or false end
    function METHODS:Play()
        local st = St(self)
        if st.type ~= "AnimationGroup" then return end
        st.playing, st.elapsed = true, 0
        animGroups[self] = true
        RunScript(self, "OnPlay")
    end
    function METHODS:Stop()
        local st = St(self)
        if st.type ~= "AnimationGroup" then return end
        if st.playing then
            st.playing = false
            animGroups[self] = nil
            RunScript(self, "OnStop", true)
        end
    end

    -- Per-type method tables, limited to the allowed names.
    local typeIndex = {}
    for t, names in pairs(TYPE_METHODS) do
        local m = {}
        for _, n in ipairs(names) do
            if allowedMethod[n] then
                m[n] = METHODS[n] or error("fakeclient: no implementation for " .. n)
            end
        end
        typeIndex[t] = m
    end
    c.typeMethods = typeIndex

    local meta = {}
    for t, m in pairs(typeIndex) do
        meta[t] = {
            __index = function(_, k)
                local f = m[k]
                if f ~= nil then return f end
                if type(k) == "string" and k:match("^%u") then Miss("method", t .. ":" .. k) end
                return nil
            end,
            __tostring = function(w) return t .. "(" .. tostring(W[w] and W[w].name or "") .. ")" end,
        }
    end

    -- Inspection record: the state table, which also answers frame methods.
    local recordMeta = {
        __index = function(rec, k)
            local w = rawget(rec, "frame")
            local f = w and w[k]
            if type(f) == "function" then
                return function(r, ...) return f(rawget(r, "frame"), ...) end
            end
            return nil
        end,
    }

    CreateWidget = function(kind, name, parent, o)
        if parent ~= nil and not IsWidget(parent) then error("CreateFrame(): parent must be a frame", 3) end
        local w = setmetatable({}, meta[kind])
        local st = setmetatable({
            frame = w, type = kind, name = name, parent = parent,
            shown = true, alpha = 1, scale = 1, points = {}, scripts = {}, hooks = {}, events = {},
            children = {}, regions = {}, anims = {},
            level = (o and o.level) or (parent and W[parent].level and W[parent].level + 1) or 0,
            layer = o and o.layer, blizzard = o and o.blizzard or false,
            addonFile = (not (o and o.blizzard)) and CallerFile(4) or nil,
        }, recordMeta)
        W[w] = st
        if parent then
            local pst = W[parent]
            if IS_FRAME[kind] then pst.children[#pst.children + 1] = w
            elseif kind ~= "Alpha" and kind ~= "AnimationGroup" then pst.regions[#pst.regions + 1] = w end
        end
        if IS_FRAME[kind] then allFrames[#allFrames + 1] = w end
        if type(name) == "string" and env then rawset(env, name, w) end
        return w
    end
    c._createWidget = CreateWidget
    c._state = function(w) return W[w] end
    c._isWidget = IsWidget
    c._allFrames = function() return allFrames end
    c._eventOrder = function(_, event)
        local out = {}
        for i, f in ipairs(eventOrder[event] or {}) do out[i] = f end
        return out
    end
    c._animGroups = function()
        local out = {}
        for g in pairs(animGroups) do out[#out + 1] = W[g] end
        table.sort(out, function(a, b) return tostring(a.frame) < tostring(b.frame) end)
        return out
    end
    c._animDone = function(_, rec)
        animGroups[rec.frame] = nil
        if rec.toFinal then
            local target = rec.parent
            local last = rec.anims[#rec.anims]
            local to = last and W[last].toAlpha
            if target and to then W[target].alpha = to end
        end
        RunScript(rec.frame, "OnFinished", false)
    end

    -----------------------------------------------------------------------
    -- The game's global table
    -----------------------------------------------------------------------
    env = setmetatable({}, {
        __index = function(_, k)
            local v = STD[k]
            if v ~= nil then return v end
            Miss("global", k)
            return nil
        end,
    })
    env._G = env
    c.env = env

    local definedGlobals = {} -- functions this file installs (checked against the snapshot)
    local function Global(name, fn, side)
        if not snap.global[name] then
            error("fakeclient: global " .. name .. " is not in the API snapshot", 2)
        end
        if side then
            local inner = fn
            fn = function(...) Log(name, ...) return inner(...) end
        end
        rawset(env, name, fn)
        definedGlobals[name] = true
    end

    local function Namespace(ns, fns, side)
        local t = {}
        for k, fn in pairs(fns) do
            local full = ns .. "." .. k
            if snap.namespace[full] then
                if side and side[k] then
                    local inner = fn
                    t[k] = function(...) Log(full, ...) return inner(...) end
                else
                    t[k] = fn
                end
            end
        end
        rawset(env, ns, setmetatable(t, {
            __index = function(_, k) Miss("namespace", ns .. "." .. tostring(k)) return nil end,
            __newindex = function() error(ns .. " is read only in the stand-in", 2) end,
        }))
    end

    -- Blizzard frames and Lua-defined methods on them (each name must be in the snapshot).
    local function Blizz(kind, name, parent, o)
        o = o or {}
        o.blizzard = true
        local w = CreateWidget(kind, name, parent, o)
        return w
    end
    local function BlizzMethod(w, name, fn)
        if not allowedMethod[name] then error("fakeclient: Blizzard method " .. name .. " is not in the API snapshot", 2) end
        rawset(w, name, fn)
    end
    -- Mutating widget methods called on Blizzard frames go into c.calls.
    local function LogBlizzardMutations(w, label)
        local mt = getmetatable(w)
        local base = mt.__index
        setmetatable(w, {
            __index = function(t, k)
                local f = base(t, k)
                if type(f) == "function" and type(k) == "string"
                    and (k:match("^Set") or k:match("^Clear") or k:match("^Hook") or k == "Show" or k == "Hide") then
                    return function(self, ...) Log(label .. ":" .. k, ...) return f(self, ...) end
                end
                return f
            end,
            __tostring = mt.__tostring,
        })
    end
    c._logMutations = LogBlizzardMutations

    -----------------------------------------------------------------------
    -- Blizzard frames the addon touches
    -----------------------------------------------------------------------
    UIParent = Blizz("Frame", "UIParent", nil)
    W[UIParent].width, W[UIParent].height = UI_W, UI_H
    c.UIParent = UIParent

    local function FontObject(name, size, file)
        local f = CreateWidget("Font", name, nil, { blizzard = true })
        W[f].font = { file or "Fonts\\FRIZQT__.TTF", size, "" }
        return f
    end
    FontObject("GameFontNormal", 12)
    FontObject("GameFontHighlight", 12)
    FontObject("GameFontNormalLarge", 16)
    FontObject("GameFontHighlightLarge", 16)

    -- World map (Blizzard_WorldMap / Blizzard_MapCanvas).
    local worldMap = Blizz("Frame", "WorldMapFrame", UIParent)
    worldMap:SetAllPoints(UIParent)
    W[worldMap].shown = false
    local scrollContainer = Blizz("Frame", nil, worldMap)
    scrollContainer:SetAllPoints(worldMap)
    local canvas = Blizz("Frame", nil, scrollContainer)
    canvas:SetSize(1002, 668)
    canvas:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, 0)
    rawset(scrollContainer, "Child", canvas)
    rawset(worldMap, "ScrollContainer", scrollContainer)
    local blobPin = Blizz("Frame", nil, canvas)
    blobPin:SetAllPoints(canvas)
    local pinLevels = setmetatable({}, { __index = function(_, k) Miss("method", "PinFrameLevelsManager:" .. tostring(k)) end })
    rawset(pinLevels, "GetValidFrameLevel", function(_, kind, index)
        -- MapCanvas_PinFrameLevelsManager.lua: startLevel + (index - 1); quest pings sit around 2400.
        local start = (kind == "PIN_FRAME_LEVEL_QUEST_PING") and 2400 or 2000
        return start + (index or 1) - 1
    end)
    BlizzMethod(worldMap, "GetCanvas", function() return canvas end)
    BlizzMethod(worldMap, "GetMapID", function() return world.worldMapID or world.player.map end)
    BlizzMethod(worldMap, "EnumeratePinsByTemplate", function(_, template)
        if template == "QuestBlobPinTemplate" then return pairs({ [blobPin] = true }) end
        return function() end
    end)
    BlizzMethod(worldMap, "GetPinFrameLevelsManager", function() return pinLevels end)
    BlizzMethod(worldMap, "OnMapChanged", function() end)
    BlizzMethod(worldMap, "OnCanvasScaleChanged", function() end)
    -- The map's border with its book icon (Blizzard_WorldMap.xml:85, a portrait frame,
    -- strata HIGH; PortraitFrame.lua:34 GetPortrait). Full screen hides the book
    -- (Blizzard_WorldMap.lua:62-65, SetPortraitShown(false)).
    -- Its pieces sit well above it (SharedUIPanelTemplates.xml:381, :574;
    -- PortraitFrame.lua:110-115): the ring art (NineSlice) at +500, the book's
    -- container at +400, title and close button at +510.
    local border = Blizz("Frame", nil, worldMap)
    border:SetAllPoints(worldMap)
    border:SetFrameStrata("HIGH")
    border:SetFrameLevel(20)
    local nineSlice = Blizz("Frame", nil, border)
    nineSlice:SetAllPoints(border)
    nineSlice:SetFrameLevel(520)
    local container = Blizz("Frame", nil, border)
    container:SetSize(1, 1)
    container:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    container:SetFrameLevel(420)
    local title = Blizz("Frame", nil, border)
    title:SetFrameLevel(530)
    local portrait = container:CreateTexture(nil, "OVERLAY")
    portrait:SetSize(60, 60)
    portrait:SetPoint("TOPLEFT", border, "TOPLEFT", -5, 7)
    BlizzMethod(border, "GetPortrait", function() return portrait end)
    rawset(border, "NineSlice", nineSlice)
    rawset(border, "PortraitContainer", container)
    rawset(border, "TitleContainer", title)
    local close = Blizz("Button", nil, border)
    close:SetFrameLevel(530)
    rawset(border, "CloseButton", close)
    rawset(worldMap, "BorderFrame", border)
    -- WorldMapMixin:Maximize / Minimize, in the game's order: the announcement
    -- comes before the book is hidden or shown again.
    BlizzMethod(worldMap, "Maximize", function()
        c:triggerRegistry("WorldMapMaximized")
        portrait:Hide()
    end)
    BlizzMethod(worldMap, "Minimize", function()
        c:triggerRegistry("WorldMapMinimized")
        portrait:Show()
    end)
    c.worldMap, c.worldMapCanvas, c.blobPin = worldMap, canvas, blobPin
    c.worldMapBorder, c.worldMapPortrait = border, portrait
    LogBlizzardMutations(blobPin, "QuestBlobPin")

    -- Minimap (Blizzard_Minimap/Mainline/Minimap.xml: 198 x 198 in MinimapCluster).
    local cluster = Blizz("Frame", "MinimapCluster", UIParent)
    cluster:SetSize(230, 230)
    cluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    local minimap = Blizz("Minimap", "Minimap", cluster)
    minimap:SetSize(198, 198)
    minimap:SetPoint("CENTER", cluster, "CENTER", 0, 0)
    W[minimap].level = 2
    c.minimap = minimap

    -- The combined bag (Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml), hidden until opened.
    local bag = Blizz("Frame", "ContainerFrameCombinedBags", UIParent)
    bag:SetSize(388, 420)
    W[bag].shown = false
    c.bagFrame = bag
    LogBlizzardMutations(bag, "ContainerFrameCombinedBags")

    local merchant = Blizz("Frame", "MerchantFrame", UIParent)
    W[merchant].shown = false
    local trade = Blizz("Frame", "TradeFrame", UIParent)
    W[trade].shown = false
    local editMode = Blizz("Frame", "EditModeManagerFrame", UIParent)
    W[editMode].shown = false
    BlizzMethod(editMode, "IsEditModeActive", function() return world.editMode and true or false end)
    Blizz("Frame", "AddonCompartmentFrame", UIParent)
    local tooltip = Blizz("Frame", "GameTooltip", UIParent)
    W[tooltip].shown = false

    -- Chat frame 1 and its edit box (Blizzard_ChatFrameBase).
    local chatFrame = Blizz("ScrollingMessageFrame", "ChatFrame1", UIParent)
    chatFrame:SetSize(430, 180)
    chatFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
    local editBox = Blizz("EditBox", "ChatFrame1EditBox", chatFrame)
    W[editBox].shown = false
    rawset(chatFrame, "editBox", editBox)
    rawset(editBox, "chatFrame", chatFrame)
    local box = { chatType = "SAY" }
    c.chatBox = box
    -- ChatFrameEditBoxBaseMixin (Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:18-48, 626)
    BlizzMethod(editBox, "SetChatType", function(_, t) Log("ChatFrame1EditBox:SetChatType", t) box.chatType = t end)
    BlizzMethod(editBox, "SetChannelTarget", function(_, t) Log("ChatFrame1EditBox:SetChannelTarget", t) box.channelTarget = t end)
    BlizzMethod(editBox, "SetTellTarget", function(_, t) Log("ChatFrame1EditBox:SetTellTarget", t) box.tellTarget = t end)
    BlizzMethod(editBox, "UpdateHeader", function() Log("ChatFrame1EditBox:UpdateHeader") end)
    c.chatFrame, c.editBox = chatFrame, editBox

    -- Chat windows ChatFrame1 .. NUM_CHAT_WINDOWS (Constants.ChatFrameConstants.MaxChatWindows = 10,
    -- ChatConstantsDocumentation.lua:214; Deprecated_ChatFrame.lua:18) with the game's default font
    -- size (CHAT_FRAME_DEFAULT_FONT_SIZE = 18, FloatingChatFrame.lua:31).
    local chatWindows = { chatFrame }
    c.chatWindows, c.chatSizes = chatWindows, {}
    for i = 2, 10 do chatWindows[i] = Blizz("ScrollingMessageFrame", "ChatFrame" .. i, UIParent) end
    for i, f in ipairs(chatWindows) do
        rawset(f, "GetID", function() return i end)
        f:SetFont("Fonts\\ARIALN.TTF", 18, "")
    end
    rawset(env, "NUM_CHAT_WINDOWS", 10)
    rawset(env, "CHAT_FONT_HEIGHTS", { 12, 14, 16, 18, 20, 24, 27 })    -- FloatingChatFrame.lua:33
    -- FloatingChatFrame.lua:1090-1109, minus the GM and Communities chat (not in this stand-in).
    -- SetChatWindowSize is the game's own saver (C side): the stand-in records it.
    rawset(env, "FCF_SetChatWindowFontSize", function(self, frame, fontSize)
        if not frame then error("FCF_SetChatWindowFontSize: no frame (the stand-in has no current chat frame)", 2) end
        if not fontSize then fontSize = self.value end
        local fontFile, _, fontFlags = frame:GetFont()
        frame:SetFont(fontFile, fontSize, fontFlags)
        Log("SetChatWindowSize", frame:GetID(), fontSize)
        c.chatSizes[frame:GetID()] = fontSize
    end)

    -----------------------------------------------------------------------
    -- Constants, enums and Blizzard Lua tables
    -----------------------------------------------------------------------
    rawset(env, "DEFAULT_CHAT_FRAME", chatFrame)
    rawset(env, "STANDARD_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
    rawset(env, "BACKPACK_CONTAINER", 0)
    rawset(env, "NUM_BAG_SLOTS", 4)
    rawset(env, "BAG_COMMAND_CONVERT_TO_COMBINED", "Convert to Combined Bag")
    rawset(env, "ENABLE_GAMEPAD_UI", "Enable Gamepad UI")
    rawset(env, "GAMEPAD_LABEL", "Gamepad")
    rawset(env, "SOUNDKIT", { UI_BAG_SORTING_01 = 43937 }) -- SoundKitConstants.lua:152
    rawset(env, "GAMEPAD_FACE_BOTTOM", "PAD1")              -- GamepadConstants.lua:8
    -- Blizzard_GamepadSmartNavigation/Utility.lua:6. That addon is only loaded with the
    -- Gamepad UI, so the table (and the two setters further down) exist only then.
    if world.gamepadUI then
        rawset(env, "SMART_NAV_INPUT_DIRECTION", {
            UP = { x = 0, y = 1, dirKey = "up" }, DOWN = { x = 0, y = -1, dirKey = "down" },
            LEFT = { x = -1, y = 0, dirKey = "left" }, RIGHT = { x = 1, y = 0, dirKey = "right" },
        })
    end
    rawset(env, "SlashCmdList", {})
    rawset(env, "UISpecialFrames", {})
    -- Enum and Constants values: only those the audit verified (`enum` rows) are
    -- visible to the addon; the full tables below are what this file itself uses.
    local function Gated(rootName, full)
        local any = next(snap.enum) ~= nil
        local out = {}
        for group, values in pairs(full) do
            local t = {}
            for k, v in pairs(values) do
                if not any or snap.enum[rootName .. "." .. group .. "." .. k] then t[k] = v end
            end
            out[group] = setmetatable(t, { __index = function(_, k) Miss("enum", rootName .. "." .. group .. "." .. tostring(k)) end })
        end
        return setmetatable(out, { __index = function(_, k) Miss("enum", rootName .. "." .. tostring(k)) end })
    end
    local CONSTANTS = { EditModeConsts = { EditModeMaxLayoutsPerType = 5 } } -- EditModeManagerConstantsDocumentation.lua:1044
    rawset(env, "Constants", Gated("Constants", CONSTANTS))
    local Enum = {
        ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7 },
        BagSlotFlags = { DisableAutoSort = 1, ClassEquipment = 2, ClassConsumables = 4, ClassProfessionGoods = 8,
            ClassJunk = 16, ClassQuestItems = 32, ExcludeJunkSell = 64, ClassReagents = 128 },
        EditModeLayoutType = { Preset = 0, Account = 1, Character = 2, Override = 3 },
        EditModePresetLayouts = { Modern = 0, Classic = 1, Gamepad = 2 },
        EditModePresetLayoutsMeta = { MinValue = 0, MaxValue = 2, NumValues = 3 },
        InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 },
        -- RestrictedActionsConstantsDocumentation.lua
        AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    }
    rawset(env, "Enum", Gated("Enum", Enum))

    -- EditModePresetLayoutsManager.lua: three presets, layoutIndex = enum value.
    local PRESETS = {
        { layoutIndex = 0, layoutName = "Modern", layoutType = 0, interfaceStyle = 0, systems = { {} } },
        { layoutIndex = 1, layoutName = "Classic", layoutType = 0, interfaceStyle = 0, systems = { {} } },
        { layoutIndex = 2, layoutName = "Gamepad", layoutType = 0, interfaceStyle = 1, systems = { {} } },
    }
    -- (The preset manager frame went with the Layout helper in 0.3.0; the list
    -- stays for C_EditMode.SetActiveLayout, which the restriction probe tries.)

    -- ChatFrameUtil (Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua): the
    -- classic chat style always picks DEFAULT_CHAT_FRAME.editBox.
    local activeBox
    local function OpenChat(text, frame)
        Log("ChatFrameUtil.OpenChat", text, frame)
        activeBox = editBox
        SetShownState(editBox, true)
        box.text = text
        return editBox
    end
    rawset(env, "ChatFrameUtil", {
        ChooseBoxForSend = function() return editBox end,                    -- line 572
        OpenChat = OpenChat,                                                 -- line 448
        GetActiveWindow = function() return activeBox end,                  -- line 511
        SendTell = function(name, frame)                                     -- line 383
            Log("ChatFrameUtil.SendTell", name, frame)
            OpenChat("", frame)
            box.tellTarget, box.chatType = name, "WHISPER"
        end,
        ResolveChannelName = function(name) return name end,                -- line 987
    })
    c.closeChat = function()
        activeBox = nil
        SetShownState(editBox, false)
    end

    -----------------------------------------------------------------------
    -- Pop-up menus (Blizzard_Menu) and the EventRegistry they announce through
    -----------------------------------------------------------------------
    -- EventRegistry (Blizzard_SharedXMLBase/GlobalCallbackRegistry.lua:1, CallbackRegistry.lua:112-240):
    -- one callback per owner per event, called as func(owner, ...).
    local registry = {}          -- [event] = { { owner =, func = }, ... } in registration order
    if snap.global.EventRegistry then
        local reg = {}
        if allowedMethod.RegisterCallback then
            function reg.RegisterCallback(self, event, func, owner)
                if type(event) ~= "string" then error("CallbackRegistryMixin::RegisterCallback 'event' requires string type.", 2) end
                if type(func) ~= "function" then error("CallbackRegistryMixin::RegisterCallback 'func' requires function type.", 2) end
                if type(owner) == "number" then error("CallbackRegistryMixin:RegisterCallback 'owner' as number is reserved internally.", 2) end
                if owner == nil then owner = {} end
                Log("EventRegistry.RegisterCallback", event)
                local list = registry[event] or {}
                registry[event] = list
                for _, e in ipairs(list) do
                    if e.owner == owner then e.func = func return owner end
                end
                list[#list + 1] = { owner = owner, func = func }
                return owner
            end
        end
        if allowedMethod.UnregisterCallback then
            function reg.UnregisterCallback(self, event, owner)
                if type(event) ~= "string" then error("CallbackRegistryMixin:UnregisterCallback 'event' requires string type.", 2) end
                if owner == nil then error("CallbackRegistryMixin:UnregisterCallback 'owner' is required.", 2) end
                Log("EventRegistry.UnregisterCallback", event)
                local list = registry[event] or {}
                for i = #list, 1, -1 do
                    if list[i].owner == owner then table.remove(list, i) end
                end
            end
        end
        rawset(env, "EventRegistry", reg)
    end
    -- What the game does when it triggers a registry event. An error in a
    -- callback goes to the client's error list and the rest still run.
    c.triggerRegistry = function(_, event, ...)
        local list = {}
        for i, e in ipairs(registry[event] or {}) do list[i] = e end
        for _, e in ipairs(list) do Protect("EventRegistry " .. event, e.func, e.owner, ...) end
    end
    c.registryCount = function(_, event) return #(registry[event] or {}) end

    -- A menu frame as MenuManagerMixin:AcquireMenu makes it (Menu.lua:2182-2283): no parent,
    -- layer FULLSCREEN_DIALOG, level owner + 500 + menu level; shown, then announced with
    -- "MenuProxy.OnShow" (Menu.lua:1848). opts: w, h, x, y (TOPLEFT on UIParent), strata, level,
    -- root = false (a side menu: not the manager's open menu), silent = true (a client that
    -- never announces), forbidden = true, breakStrata = true (GetFrameStrata raises).
    -- Every Set*, Clear*, Hook*, Show and Hide called on it afterwards lands in c.calls as "Menu:<name>".
    c.openMenu = function(_, o)
        o = o or {}
        local menu = Blizz("Frame", nil, nil)
        local st = W[menu]
        st.width, st.height = o.w or 200, o.h or 120
        st.points = { { point = "TOPLEFT", rel = UIParent, relPoint = "TOPLEFT", x = o.x or 300, y = o.y or -200 } }
        st.strata, st.level = o.strata or "FULLSCREEN_DIALOG", o.level or 503
        st.shown = true
        if o.forbidden then rawset(menu, "IsForbidden", function() return true end) end
        if o.breakStrata then rawset(menu, "GetFrameStrata", function() error("GetFrameStrata: broken for this test", 2) end) end
        LogBlizzardMutations(menu, "Menu")
        if o.root ~= false then world.openMenu = menu end
        if not o.silent then c:triggerRegistry("MenuProxy.OnShow", menu) end
        return menu
    end
    -- "MenuProxy.OnClose" (Menu.lua:1755), the frame hidden, then "MenuProxy.OnHide" (Menu.lua:1852).
    -- opts.noClose / opts.noHide leave an announcement out.
    c.closeMenu = function(_, menu, o)
        o = o or {}
        if not o.noClose then c:triggerRegistry("MenuProxy.OnClose", menu, 1) end
        W[menu].shown = false
        if not o.noHide then c:triggerRegistry("MenuProxy.OnHide", menu) end
        if world.openMenu == menu then world.openMenu = nil end
    end
    -- Menu.GetManager():GetOpenMenu() (Menu.lua:2712, :2667): the open root menu's frame.
    if snap.global.Menu then
        local manager = {}
        if allowedMethod.GetOpenMenu then manager.GetOpenMenu = function() return world.openMenu end end
        local menuTable = {}
        if snap.namespace["Menu.GetManager"] then menuTable.GetManager = function() return manager end end
        rawset(env, "Menu", menuTable)
    end

    -----------------------------------------------------------------------
    -- Timers and clock
    -----------------------------------------------------------------------
    local timers, timerSeq = {}, 0
    local function After(seconds, fn)
        if type(seconds) ~= "number" then error("C_Timer.After(): seconds must be a number", 2) end
        if type(fn) ~= "function" then error("C_Timer.After(): callback must be a function", 2) end
        timerSeq = timerSeq + 1
        timers[#timers + 1] = { due = c.now + max(seconds, 0), fn = fn, seq = timerSeq, addon = CallerFile(3) ~= nil }
    end
    c._timers = timers

    -----------------------------------------------------------------------
    -- Namespaces
    -----------------------------------------------------------------------
    Namespace("C_Timer", { After = After })

    Namespace("C_UI", { Reload = function() c.reloads = c.reloads + 1 end }, { Reload = true })

    Namespace("C_AddOns", {
        IsAddOnLoaded = function(name)
            local on = world.addons[name] and true or false
            return on, on
        end,
        -- Only the addon's own version line is modelled.
        GetAddOnMetadata = function(name, field)
            if name == "PocketEssentials" and field == "Version" then return "0.0.0-test" end
            return nil
        end,
    })

    Namespace("C_CVar", {
        GetCVar = function(name) return world.cvars[name] end,
        SetCVar = function(name, value)
            if world.cvars[name] == nil then return false end
            world.cvars[name] = tostring(value)
            return true
        end,
    }, { SetCVar = true })

    Namespace("C_ChatInfo", { InChatMessagingLockdown = function() return world.chatLockdown and true or false end })

    local function ItemAt(bag, slot)
        local b = world.bags[bag]
        return b and b[slot]
    end
    local function ItemData(itemID)
        for _, b in pairs(world.bags) do
            for _, it in pairs(b) do
                if type(it) == "table" and it.itemID == itemID then return it end
            end
        end
        return world.items and world.items[itemID]
    end
    Namespace("C_Container", {
        GetContainerNumSlots = function(bag) return world.bagSizes[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local it = ItemAt(bag, slot)
            if not it then return nil end
            return {
                iconFileID = 134400, stackCount = it.count or 1, isLocked = it.locked and true or false,
                quality = it.quality, isReadable = false, hasLoot = false,
                hyperlink = "|cff9d9d9d|Hitem:" .. it.itemID .. "::::::::|h[" .. (it.name or "Item") .. "]|h|r",
                isFiltered = false, hasNoValue = not (it.price and it.price > 0), itemID = it.itemID,
                isBound = false, itemName = it.name or "Item",
            }
        end,
        UseContainerItem = function(bag, slot)
            local it = ItemAt(bag, slot)
            if not it or it.locked then return end
            -- world.forbidUse: a test's function standing in for the game refusing the
            -- call (it fires ADDON_ACTION_FORBIDDEN synchronously, inside the call).
            if world.forbidUse then world.forbidUse(bag, slot) return end
            if world.merchant.open then
                world.money = world.money + (it.price or 0) * (it.count or 1)
                world.bags[bag][slot] = nil
            end
        end,
        SortBags = function() end,
        GetBackpackSellJunkDisabled = function() return world.ignoreJunk[0] and true or false end,
        GetBagSlotFlag = function(bag, flag)
            return flag == Enum.BagSlotFlags.ExcludeJunkSell and world.ignoreJunk[bag] and true or false
        end,
    }, { UseContainerItem = true, SortBags = true })

    Namespace("C_Item", {
        -- name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice, ...
        GetItemInfo = function(item)
            local it = ItemData(item)
            if not it or it.noData then return nil end -- noData: the item's data has not arrived from the server
            -- dbQuality / dbPrice: what the item database says when it differs from the bag slot.
            local quality, price = it.dbQuality or it.quality, it.dbPrice or it.price
            return it.name or "Item", "|Hitem:" .. it.itemID .. "|h", quality, 1, 1, "Junk", "Junk", 20, "",
                134400, price or 0, 15, 0, 0, 0, nil, false
        end,
    })

    local function CoinText(copper)
        local g, s, cc = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
        local parts = {}
        if g > 0 then parts[#parts + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
        if s > 0 then parts[#parts + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
        if cc > 0 or #parts == 0 then parts[#parts + 1] = cc .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
        return table.concat(parts, " ")
    end
    Namespace("C_CurrencyInfo", { GetCoinTextureString = function(amount) return CoinText(amount) end })
    -- TextureUtilsDocumentation.lua: an AtlasInfo table, or nothing for an unknown atlas.
    Namespace("C_Texture", { GetAtlasInfo = function(atlas)
        if atlas == "bags-button-autosort-up" then return { width = 28, height = 26 } end
        if atlas == "common-dropdown-bg" and world.menuArt then return { width = 32, height = 32 } end
    end })

    local function NumPresets() return #PRESETS end
    Namespace("C_EditMode", {
        GetLayouts = function() return DeepCopy(world.layouts) end,
        SetActiveLayout = function(index)
            if type(index) == "number" and index >= 1 and index <= NumPresets() + #world.layouts.layouts then
                world.layouts.activeLayout = index
            end
        end,
        SaveLayouts = function(info)
            local saved = {}
            for _, l in ipairs(info.layouts or {}) do
                if l.layoutType ~= Enum.EditModeLayoutType.Preset then saved[#saved + 1] = DeepCopy(l) end
            end
            world.layouts = { layouts = saved, activeLayout = info.activeLayout or world.layouts.activeLayout }
        end,
        OnLayoutAdded = function(index, activate)
            if activate then world.layouts.activeLayout = index end
        end,
        -- world.layoutImport: the layout the game would read out of any string (nil: the string is refused).
        ConvertStringToLayoutInfo = function(text) return world.layoutImport and DeepCopy(world.layoutImport) or nil end,
    }, { SetActiveLayout = true, SaveLayouts = true, OnLayoutAdded = true })

    -- world.combatRestricted: the game's "Combat" addon restriction, which Blizzard's controller
    -- navigation asks instead of InCombatLockdown (RestrictedActionsDocumentation.lua).
    Namespace("C_RestrictedActions", {
        IsAddOnRestrictionActive = function(kind)
            return kind == 0 and (world.combatRestricted or world.inCombat) and true or false
        end,
    })

    Namespace("C_InputInterfaceStyle", {
        GetCurrentStyle = function()
            return world.gamepadUI and Enum.InputDeviceInterfaceType.Gamepad or Enum.InputDeviceInterfaceType.Mkb
        end,
    })

    Namespace("C_Map", {
        GetBestMapForUnit = function(unit)
            if unit ~= "player" then return nil end
            return world.player.map
        end,
        GetPlayerMapPosition = function(mapID, unit)
            local p = world.player
            if unit ~= "player" or world.instance or mapID ~= p.map or p.map == nil then return nil end
            return { x = p.x, y = p.y, GetXY = function(self) return self.x, self.y end }
        end,
        GetMapWorldSize = function(mapID)
            local m = world.maps[mapID]
            if not m then return 0, 0 end
            return m.width, m.height
        end,
        GetMapInfo = function(mapID)
            local m = world.maps[mapID]
            if not m then return nil end
            return { mapID = mapID, name = m.name, mapType = 3, parentMapID = m.parent or 0, flags = 0 }
        end,
    })

    local function QuestEntries() return world.questLog.quests end
    local function FindQuest(id)
        for _, q in ipairs(QuestEntries()) do
            if not q.header and q.id == id then return q end
        end
    end
    Namespace("C_QuestLog", {
        GetNumQuestLogEntries = function()
            local n, quests = 0, 0
            for _, q in ipairs(QuestEntries()) do
                n = n + 1
                if not q.header then quests = quests + 1 end
            end
            return n, quests
        end,
        GetInfo = function(i)
            local q = QuestEntries()[i]
            if not q then return nil end
            return {
                title = q.title or "", questLogIndex = i, questID = q.header and 0 or q.id, level = q.level or 10,
                difficultyLevel = q.level or 10, suggestedGroup = 0, isHeader = q.header and true or false,
                useMinimalHeader = false, sortAsNormalQuest = false, isTask = false, isBounty = false,
                isStory = false, isScaling = false, isOnMap = true, hasLocalPOI = false, isHidden = false,
                isAutoComplete = false, overridesSortOrder = false, readyForTranslation = true,
                isCollapsed = false, isInternalOnly = false, isAbandonOnDisable = false,
            }
        end,
        IsComplete = function(id) local q = FindQuest(id) return q and q.complete and true or false end,
        GetQuestObjectives = function(id)
            local q = FindQuest(id)
            local out = {}
            for i, o in ipairs(q and q.objectives or {}) do
                out[i] = { text = o.text or "", type = o.type or "monster", finished = o.finished and true or false,
                    numFulfilled = o.numFulfilled or (o.finished and 1 or 0), numRequired = o.numRequired or 1 }
            end
            return out
        end,
        IsOnQuest = function(id) return FindQuest(id) ~= nil end,
        GetTitleForQuestID = function(id) local q = FindQuest(id) return q and q.title or nil end,
        GetNumQuestWatches = function() return #(world.questLog.watched or {}) end,
        GetQuestIDForQuestWatchIndex = function(i) return (world.questLog.watched or {})[i] end,
    })

    Namespace("C_SuperTrack", {
        GetSuperTrackedQuestID = function() return world.questLog.focus or 0 end,
        SetSuperTrackedQuestID = function(id) world.questLog.focus = (id ~= 0) and id or nil end,
    }, { SetSuperTrackedQuestID = true })

    -----------------------------------------------------------------------
    -- Global functions (each must be in the snapshot)
    -----------------------------------------------------------------------
    Global("CreateFrame", function(kind, name, parent, template)
        if not CREATABLE[kind] then error("CreateFrame(): Unknown frame type '" .. tostring(kind) .. "'", 2) end
        if template ~= nil then error("CreateFrame(): templates are not modelled by the stand-in", 2) end
        if name ~= nil and type(name) ~= "string" then error("CreateFrame(): name must be a string", 2) end
        return CreateWidget(kind, name, parent)
    end)
    Global("CreateFont", function(name)
        if type(name) ~= "string" then error("CreateFont(): name expected", 2) end
        local f = CreateWidget("Font", name, nil, {})
        return f
    end)
    Global("Ambiguate", function(name, context)
        local short, realm = name:match("^([^%-]+)%-(.+)$")
        if short and (realm == world.realm or context == "short") then return short end
        return name
    end)
    Global("CanMerchantRepair", function() return world.merchant.open and world.merchant.canRepair and true or false end)
    Global("GetRepairAllCost", function()
        local cost = world.merchant.repairCost or 0
        -- The second value means "something is repairable", not "affordable"
        -- (Blizzard_UIPanels_Game/Vanilla/MerchantFrame.lua:732-734; MerchantFrame.xml:217-218).
        -- world.merchant.canRepairAll overrides it.
        local can = world.merchant.canRepairAll
        if can == nil then can = cost > 0 end
        return cost, can
    end)
    Global("RepairAllItems", function(guildBank)
        local cost = world.merchant.repairCost or 0
        if world.merchant.open and world.merchant.canRepair and cost > 0 and world.money >= cost then
            world.money = world.money - cost
            world.merchant.repairCost = 0
        end
    end, true)
    Global("GetMoney", function() return world.money end)
    Global("InRepairMode", function() return world.repairMode and true or false end)
    Global("SpellIsTargeting", function() return world.spellTargeting and true or false end)
    Global("InCombatLockdown", function() return world.inCombat and true or false end)
    Global("IsInGroup", function() return world.group ~= "none" end)
    Global("IsInRaid", function() return world.group == "raid" end)
    Global("IsInGuild", function() return world.guild ~= nil end)
    Global("IsInInstance", function()
        if world.instance then return true, "party" end
        return false, "none"
    end)
    Global("IsIndoors", function() return world.indoors and true or false end)
    Global("IsModifierKeyDown", function() return false end)
    Global("GetChannelList", function()
        local out = {}
        for _, ch in ipairs(world.channels) do
            out[#out + 1] = ch.id
            out[#out + 1] = ch.name
            out[#out + 1] = ch.disabled and true or false
        end
        return unpack(out)
    end)
    Global("GetCVar", function(name) return world.cvars[name] end)
    Global("GetCursorPosition", function() return world.cursor[1], world.cursor[2] end)
    Global("GetPlayerFacing", function()
        if world.instance or world.player.map == nil then return nil end
        return world.player.facing
    end)
    Global("GetTime", function() return c.now end)
    -- time() counts whole seconds on its own clock: c.wallOffset (default 0) shifts its
    -- second boundaries against GetTime(), as in the game where the two are not aligned.
    Global("time", function() return 1763200000 + floor(c.now + (c.wallOffset or 0)) end)
    Global("date", function(fmt, t) return os.date(fmt, t) end)
    -- debugstack([start[, count1[, count2]]]): the top count1 lines (default 12) and the
    -- bottom count2 (default 10), "..." between when lines are left out, as in the game.
    Global("debugstack", function(level, top, bottom)
        top, bottom = top or 12, bottom or 10
        local lines = {}
        local i = (level or 1) + 1
        while true do
            local info = debug.getinfo(i, "Sln")
            if not info then break end
            lines[#lines + 1] = info.short_src .. ":" .. (info.currentline or 0) .. ": in function "
                .. (info.name and ("'" .. info.name .. "'") or "<anonymous>")
            i = i + 1
        end
        if #lines > top + bottom then
            local kept = {}
            for j = 1, top do kept[#kept + 1] = lines[j] end
            kept[#kept + 1] = "..."
            for j = #lines - bottom + 1, #lines do kept[#kept + 1] = lines[j] end
            lines = kept
        end
        return table.concat(lines, "\n") .. "\n"
    end)
    Global("wipe", function(t) for k in pairs(t) do t[k] = nil end return t end)
    Global("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        c.chat[#c.chat + 1] = table.concat(parts, " ")
    end)
    Global("issecretvalue", function(v) return v ~= nil and world.secrets[v] == true end)
    -- version, build, date, interface number
    Global("GetBuildInfo", function() return "1.16.0", "60000", "Nov 1 2026", 16001 end)
    Global("PlaySound", function() return true end, true)
    Global("ReloadUI", function() c.reloads = c.reloads + 1 end, true)
    -- Protected: in combat the game refuses ("action blocked"), it does not raise.
    local function Protected(name, fn)
        Global(name, function(...)
            if world.inCombat then
                c.blocked[#c.blocked + 1] = { name = name, stack = debug.traceback("", 2) }
                return
            end
            return fn(...)
        end, true)
    end
    Protected("SetOverrideBindingClick", function(owner, isPriority, key, buttonName, mouseButton)
        if not IsWidget(owner) then error("SetOverrideBindingClick(): owner must be a frame", 2) end
        if type(key) ~= "string" or type(buttonName) ~= "string" then error("SetOverrideBindingClick(): key and button name expected", 2) end
        local st = W[owner]
        st.bindings = st.bindings or {}
        st.bindings[key] = buttonName
    end)
    -- A key pointed at one of the game's own binding commands (stored as "command:NAME").
    Protected("SetOverrideBinding", function(owner, isPriority, key, command)
        if not IsWidget(owner) then error("SetOverrideBinding(): owner must be a frame", 2) end
        if type(key) ~= "string" then error("SetOverrideBinding(): key expected", 2) end
        local st = W[owner]
        st.bindings = st.bindings or {}
        st.bindings[key] = command and ("command:" .. tostring(command)) or nil
    end)
    Protected("ClearOverrideBindings", function(owner)
        if not IsWidget(owner) then error("ClearOverrideBindings(): owner must be a frame", 2) end
        W[owner].bindings = nil
    end)
    -- What the game says a key does (override bindings looked at when checkOverride is true):
    -- here, the click target of the stand-in's override for the key, or "" (as the game answers).
    Global("GetBindingAction", function(key, checkOverride)
        if not checkOverride then return "" end
        for _, f in ipairs(allFrames) do
            local b = W[f].bindings
            if b and b[key] then return "CLICK " .. tostring(b[key]) .. ":LeftButton" end
        end
        return ""
    end)
    -- Blizzard's jump-override setters (Blizzard_GamepadSmartNavigation/Utility.lua:414, :470). They
    -- hand the write to SecureHelper:SetSecureValue, which refuses an addon's call while the game's
    -- combat restriction is on (SecureHelper.lua:26; device: probe trial pad.mark) and otherwise
    -- stores the value on the button. A function as the target is legal in the game but is
    -- the one thing the addon must never pass (its return value would be tainted): the stand-in
    -- records an error for it, which no pcall in the addon can hide.
    if world.gamepadUI then
        local function NavSetter(name, clears)
            Global(name, function(button, direction, value)
                if not button or not direction then return end
                if clears then value = nil end
                if type(value) == "function" then
                    Record(name, "a function was passed as the jump target")
                    error(name .. "(): the stand-in refuses a function as the jump target", 2)
                end
                if world.inCombat or world.combatRestricted then
                    c.blocked[#c.blocked + 1] = { name = name, stack = debug.traceback("", 2) }
                    return
                end
                rawset(button, "smartNavigationOverride-" .. direction.dirKey, value)
            end, true)
        end
        NavSetter("SmartNavigation_AddJumpNavigationOverride", false)
        NavSetter("SmartNavigation_ClearJumpNavigationOverridesInDirection", true)
    end
    -- Blizzard's layout pass for open bags (ContainerFrame.lua:1380-1405).
    Global("UpdateContainerFrameAnchors", function()
        if not W[bag].shown then return end
        local scale = 1
        bag:SetScale(scale)
        bag:ClearAllPoints()
        bag:SetPoint("BOTTOMRIGHT", bag:GetParent(), "BOTTOMRIGHT", 4 / scale, 85 / scale)
    end)
    -- The quest log's menu (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2367): opens a
    -- menu with world.questMenu as its c:openMenu options.
    if snap.global.QuestMapLogTitleButton_CreateContextMenu then
        Global("QuestMapLogTitleButton_CreateContextMenu", function(button, parent)
            local o = {}
            for k, v in pairs(world.questMenu or {}) do o[k] = v end
            c.lastQuestMenu = c:openMenu(o)
        end)
    end
    -- ChatFrameUtil.lua (Shared): prints INTERFACE_ACTION_BLOCKED once, then turns itself off.
    Global("DisplayInterfaceActionBlockedMessage", function()
        c.chat[#c.chat + 1] = "Interface action failed because of an AddOn"
        rawset(env, "DisplayInterfaceActionBlockedMessage", function() end)
    end)
    Global("hooksecurefunc", function(a, b, cc)
        local tbl, name, hook = a, b, cc
        if type(a) == "string" then tbl, name, hook = env, a, b end
        if type(tbl) ~= "table" or type(name) ~= "string" or type(hook) ~= "function" then
            error("hooksecurefunc(): usage: hooksecurefunc([table,] \"name\", function)", 2)
        end
        local orig = rawget(tbl, name)
        if type(orig) ~= "function" then error("hooksecurefunc(): " .. name .. " is not a function", 2) end
        rawset(tbl, name, function(...)
            local res = Pack(orig(...))
            Protect("hooksecurefunc " .. name, hook, ...)
            return unpack(res, 1, res.n)
        end)
    end, true)
    c.definedGlobals = definedGlobals

    -----------------------------------------------------------------------
    -- QuestieDB: the real release, loaded through tests/questiedb/stubs.lua
    -- into the real _G (it runs there, with the stand-ins that harness
    -- provides). The addon sees only LibQuestieDB.
    -----------------------------------------------------------------------
    c._realG = {}
    for k, v in pairs(_G) do c._realG[k] = v end
    if opts.questieDB then
        local S = Client._stubs
        if not S then
            S = dofile(root .. "/tests/questiedb/stubs.lua")
            S.init(root)
            Client._stubs = S
        end
        c._stubsS = S
        S.install(opts.persona)
        -- opts.shareQuestieDB: load the release once per process and give later
        -- clients the same loaded data (what the load wrote into _G is put back
        -- after each install). The rule tests use it; QuestieDB's data is only read.
        local sharedKey = opts.shareQuestieDB and (opts.questieDB .. "|" .. tostring((opts.persona or {}).faction)
            .. "|" .. tostring((opts.persona or {}).class))
        Client._shared = Client._shared or {}
        local shared = sharedKey and Client._shared[sharedKey]
        local lib
        if shared then
            for k, v in pairs(shared.globals) do _G[k] = v end
            lib = shared.lib
        else
            local before = {}
            for k, v in pairs(_G) do before[k] = v end
            lib = S.loadQuestieDB(opts.questieDB)
            S.runTimers()
            if sharedKey then
                local globals = {}
                for k, v in pairs(_G) do if before[k] ~= v then globals[k] = v end end
                Client._shared[sharedKey] = { lib = lib, globals = globals }
            end
        end
        if type(lib) ~= "table" then error("fakeclient: QuestieDB did not load from " .. tostring(opts.questieDB), 2) end
        rawset(env, "LibQuestieDB", lib)
        world.addons.QuestieDB = true
    end

    return c
end

---------------------------------------------------------------------------
-- Addon loading
---------------------------------------------------------------------------

local function ReadToc(dir, name)
    local f = assert(io.open(dir .. "/" .. name .. ".toc", "rb"), "fakeclient: no " .. name .. ".toc in " .. dir)
    local files = {}
    for line in f:lines() do
        line = line:gsub("\r$", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
    end
    f:close()
    return files
end

-- Runs the TOC's files in order with ("PocketEssentials", PE), sets the saved
-- variables, then fires ADDON_LOADED, PLAYER_LOGIN and PLAYER_ENTERING_WORLD as
-- the client does at login. A file that fails to load is recorded in c.errors
-- and the rest still load (as in the game). Returns PE.
-- opts.addonName loads another addon the same way (its <name>.toc from
-- opts.addonDir, saved variables <name>DB): the restriction probe's tests use it.
function Client:loadAddon()
    if self.PE then error("fakeclient: loadAddon() was already called on this client", 2) end
    local PE = {}
    self.PE = PE
    local addonName = self.opts.addonName or "PocketEssentials"
    for _, file in ipairs(ReadToc(self.addonDir, addonName)) do
        local path = self.addonDir .. "/" .. file
        local chunk, err = loadfile(path)
        if not chunk then
            self._record("loading " .. file, err)
        else
            setfenv(chunk, self.env)
            self._protect("loading " .. file, chunk, addonName, PE)
        end
    end
    if self.opts.saved ~= nil then rawset(self.env, addonName .. "DB", self.opts.saved) end
    self:fire("ADDON_LOADED", addonName, false)
    self:fire("PLAYER_LOGIN")
    self:fire("PLAYER_ENTERING_WORLD", true, false)
    return PE
end

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------

-- Delivers an event to every frame registered for it, in registration order.
function Client:fire(event, ...)
    if not self.snapshot.event[event] then error("fakeclient: c:fire(): unknown event " .. tostring(event), 2) end
    for _, f in ipairs(self:_eventOrder(event)) do
        local rec = self._state(f)
        if rec.events[event] then -- an earlier handler may have unregistered it
            local fn = rec.scripts.OnEvent
            if fn then self._protect(rec.type .. ":OnEvent " .. event, fn, rec.frame, event, ...) end
            local hooks = rec.hooks.OnEvent
            if hooks then for _, h in ipairs(hooks) do self._protect("OnEvent hook " .. event, h, rec.frame, event, ...) end end
        end
    end
end

-- Moves the clock in 0.1 s steps; each step runs the timers that are due,
-- the playing animations and every visible frame's OnUpdate.
function Client:advance(seconds)
    local steps = math.max(1, math.floor((seconds or 0) / 0.1 + 0.5))
    if (seconds or 0) <= 0 then steps = 1 end
    local dt = (seconds or 0) <= 0 and 0 or 0.1
    self.stats.callbacks = 0
    self.callbackLimit = 100000
    local ok, err = pcall(function()
        for _ = 1, steps do
            self.now = self.now + dt
            -- timers due now (callbacks added meanwhile wait for the next step)
            local timers = self._timers
            local due = {}
            local i = 1
            while i <= #timers do
                if timers[i].due <= self.now + 1e-9 then
                    due[#due + 1] = table.remove(timers, i)
                else
                    i = i + 1
                end
            end
            table.sort(due, function(a, b)
                if a.due ~= b.due then return a.due < b.due end
                return a.seq < b.seq
            end)
            for _, t in ipairs(due) do
                self.stats.timers = self.stats.timers + 1
                if t.addon then self.stats.addonTimers = self.stats.addonTimers + 1 end
                self._protect("C_Timer callback", t.fn)
            end
            -- animations
            for _, rec in ipairs(self:_animGroups()) do
                rec.elapsed = rec.elapsed + dt
                local duration = 0
                for _, a in ipairs(rec.anims) do duration = math.max(duration, self._state(a).duration or 0) end
                if rec.elapsed >= duration then
                    rec.playing = false
                    self:_animDone(rec)
                end
            end
            -- OnUpdate on visible frames
            for _, rec in ipairs(self:frames()) do
                local fn = rec.scripts.OnUpdate
                if fn and rec.frame:IsVisible() then
                    if rec.addonFile then self.stats.addonOnUpdate = self.stats.addonOnUpdate + 1 end
                    self._protect((rec.name or rec.type) .. ":OnUpdate", fn, rec.frame, dt)
                end
            end
            if self._stubsS then self._stubsS.runTimers() end
        end
    end)
    self.callbackLimit = nil
    if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------

-- Every frame created (Blizzard's stand-ins and the addon's), as inspection
-- records: rec.frame, rec.type, rec.name, rec.shown, rec.scripts, rec.hooks,
-- rec.events, rec.children, rec.regions, rec.addonFile (the addon file that
-- made it, or nil), rec.blizzard; frame methods work on the record too
-- (rec:IsShown()).
function Client:frames()
    local out = {}
    for _, w in ipairs(self:_allFrames()) do out[#out + 1] = self._state(w) end
    return out
end

function Client:find(pred)
    for _, rec in ipairs(self:frames()) do
        if pred(rec) then return rec end
    end
    return nil
end

local function Frame(c, f)
    if type(f) == "table" and rawget(f, "frame") then return rawget(f, "frame") end
    return f
end

-- Runs one script of a frame (and its hooks), as the game would.
function Client:script(f, name, ...)
    f = Frame(self, f)
    local st = self._state(f)
    if not st then error("fakeclient: c:script(): not a frame", 2) end
    self._runScript(f, name, ...)
end

-- A tap: OnMouseDown, OnMouseUp, OnClick("LeftButton", false). The button must be visible.
function Client:click(f, button)
    f = Frame(self, f)
    local st = self._state(f)
    if not st or st.type ~= "Button" then error("fakeclient: c:click(): not a button", 2) end
    if not f:IsVisible() then error("fakeclient: c:click(): the button is not visible", 2) end
    self._runScript(f, "OnMouseDown", button or "LeftButton")
    self._runScript(f, "OnMouseUp", button or "LeftButton")
    self._runScript(f, "OnClick", button or "LeftButton", false)
end

function Client:callsTo(name)
    local out = {}
    for _, call in ipairs(self.calls) do
        if call.name == name then out[#out + 1] = call end
    end
    return out
end

-- The errors that count: the client's own (script errors) plus the addon's
-- error log and any action the game would have blocked. Empty table if clean.
function Client:problems()
    local out = {}
    for _, e in ipairs(self.errors) do out[#out + 1] = "Lua error in " .. e.where .. ": " .. e.msg end
    local PE = self.PE
    local list = PE and PE.errors
    if type(list) == "table" then
        for _, e in ipairs(list) do
            out[#out + 1] = "PE:LogError(" .. tostring(e.module) .. "): " .. tostring(e.msg)
                .. (e.stack and e.stack ~= "" and ("\n      " .. e.stack:gsub("\n", "\n      ")) or "")
        end
    end
    for _, b in ipairs(self.blocked) do out[#out + 1] = "action blocked in combat: " .. b.name end
    return out
end

function Client:assertClean(where)
    local p = self:problems()
    if #p > 0 then
        error((where and (where .. ": ") or "") .. table.concat(p, "\n  "), 2)
    end
end

-- Puts back the real _G (QuestieDB's loader writes there).
function Client:destroy()
    local saved = self._realG
    if not saved then return end
    for k in pairs(_G) do if saved[k] == nil then _G[k] = nil end end
    for k, v in pairs(saved) do if _G[k] ~= v then _G[k] = v end end
    self._realG = nil
end

---------------------------------------------------------------------------
-- World actions (the things a player does), so tests read like play
---------------------------------------------------------------------------

function Client:openWorldMap(mapID)
    self.world.worldMapID = mapID
    self.worldMap:Show()
    self._protect("WorldMapFrame:OnMapChanged", self.worldMap.OnMapChanged, self.worldMap)
end

function Client:zoomWorldMap(scale)
    self._state(self.worldMapCanvas).scale = scale
    self._protect("WorldMapFrame:OnCanvasScaleChanged", self.worldMap.OnCanvasScaleChanged, self.worldMap)
end

function Client:closeWorldMap()
    self.worldMap:Hide()
end

-- WorldMapMixin:Maximize / Minimize (Blizzard_WorldMap.lua:40-73).
function Client:maximizeWorldMap()
    self.worldMap:Maximize()
end

function Client:minimizeWorldMap()
    self.worldMap:Minimize()
end

function Client:openBag()
    -- ContainerFrameCombinedBagsMixin:OnShow lays the items out, then runs the layout pass.
    if self.bagButtons then self:layoutBagItems() end
    self._state(self.bagFrame).shown = false
    self.bagFrame:Show()
    self._protect("UpdateContainerFrameAnchors", self.env.UpdateContainerFrameAnchors)
end

function Client:closeBag()
    self.bagFrame:Hide()
end

-- Gives the combined bag item buttons on a grid (ContainerFrame.lua: the frame's `Items` array,
-- AcquireNewItemButton). Returns them as grid[column][row], column 1 leftmost, row 1 at the top.
function Client:fillBag(columns, rows)
    local bag = self.bagFrame
    local items, grid = {}, {}
    for col = 1, columns do grid[col] = {} end
    for row = 1, rows do
        for col = 1, columns do
            local b = self._createWidget("Button", nil, bag, { blizzard = true })
            b:SetSize(37, 37)
            b:SetPoint("TOPLEFT", bag, "TOPLEFT", 8 + (col - 1) * 42, -60 - (row - 1) * 42)
            items[#items + 1] = b
            grid[col][row] = b
        end
    end
    rawset(bag, "Items", items)
    return grid
end

-- The combined bag as the game builds it, in place of fillBag's plain grid: a money frame,
-- `GamepadBagBar` with its seven bag buttons in `BagButtonArray` (backpack, four bags, reagent
-- bag, key ring: Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml:99-138) and
-- one item button per slot in the bag's `Items` (ContainerFrame.lua:1058-1078).
-- `sizes`: the slot counts of the backpack and the four bags (default 16, 12, 12, 10, 10);
-- `keyring`: the key ring's slot count (default 4; it starts collapsed, as in the game).
-- world.collapsed[bagID] = true leaves that bag's slots out of the layout (bag IDs 0 to 5, key
-- ring -2). Widget calls the addon makes on these buttons go into c.calls as
-- "GamepadBagButton:<method>" and "ContainerItemButton:<method>"; the stand-in's own layout
-- writes the anchors directly, so everything logged is the addon's doing.
local KEYRING = -2
function Client:buildBag(sizes, keyring)
    if not self.snapshot.frame.GamepadBagBar then
        error("fakeclient: frame GamepadBagBar is not in the API snapshot", 2)
    end
    sizes = sizes or { 16, 12, 12, 10, 10 }
    local bag, world = self.bagFrame, self.world
    local make, state = self._createWidget, self._state
    local money = make("Frame", nil, bag, { blizzard = true })
    money:SetSize(168, 17)
    money:SetPoint("BOTTOMRIGHT", bag, "BOTTOMRIGHT", -7, 7)
    rawset(bag, "MoneyFrame", money)
    local bar = make("Frame", "GamepadBagBar", bag, { blizzard = true })
    bar:SetSize(215, 50)
    local info, all, icons, array = {}, {}, {}, {}
    local function Button(parent, label, entry)
        local b = make("Button", nil, parent, { blizzard = true })
        b:SetSize(37, 37)
        self._logMutations(b, label)
        entry.button = b
        info[b] = entry
        all[#all + 1] = b
        return b
    end
    for i, bagID in ipairs({ 0, 1, 2, 3, 4, 5, KEYRING }) do
        local b = Button(bar, "GamepadBagButton", { kind = "icon", bag = bagID })
        -- GamepadBagBarMixin:OnLoad: hidden unless the Gamepad UI is on.
        if not world.gamepadUI then state(b).shown = false end
        icons[bagID], array[i] = b, b
    end
    rawset(bar, "BagButtonArray", array)
    -- UpdateItemSlots: bags from the last to the first, each bag's slots from the last to the first.
    local size = { [KEYRING] = keyring or 4, [5] = 0 }
    for i = 1, 5 do size[i - 1] = sizes[i] or 0 end
    local items, slots = {}, {}
    for _, bagID in ipairs({ 5, 4, 3, 2, 1, 0, KEYRING }) do
        slots[bagID] = {}
        for slot = size[bagID], 1, -1 do
            local b = Button(bag, "ContainerItemButton", { kind = "slot", bag = bagID, slot = slot })
            state(b).shown = false
            items[#items + 1] = b
            slots[bagID][slot] = b
        end
    end
    rawset(bag, "Items", items)
    world.collapsed = world.collapsed or {}
    if world.collapsed[KEYRING] == nil then world.collapsed[KEYRING] = true end
    self.bagButtons, self.bagInfo, self.bagIcons, self.bagSlots, self.bagMoney = all, info, icons, slots, money
    self.bagSizes = size
    return self
end

-- Blizzard's item layout (ContainerFrameMixin:UpdateItemLayout, ContainerFrame.lua:1080-1106):
-- one list of every slot of every bag that is not collapsed plus, with the Gamepad UI on, one
-- bag button per bag; sorted by bag from the last to the first (key ring ahead of all), a bag's
-- slots ahead of its own button; laid out ten to a row from the bottom right upward, 42 apart,
-- each button with the one point BOTTOMRIGHT on the money frame's TOPRIGHT (AnchorUtil.GridLayout,
-- ContainerFrame.lua:3033-3035). Buttons left out have no points (Pool_HideAndClearAnchors).
function Client:layoutBagItems()
    assert(self.bagButtons, "fakeclient: buildBag first")
    local world, state = self.world, self._state
    local list = {}
    for _, bagID in ipairs({ KEYRING, 5, 4, 3, 2, 1, 0 }) do
        -- Mouse style: no bag is collapsed, and the key ring is not part of the combined bag.
        local absent = not world.gamepadUI and bagID == KEYRING
        local collapsed = absent or (world.gamepadUI and world.collapsed[bagID])
        for slot = self.bagSizes[bagID], 1, -1 do
            local b = self.bagSlots[bagID][slot]
            local st = state(b)
            -- A collapsed bag's buttons are still shown (ContainerFrameItemButtonMixin:Initialize)
            -- but have no place: the pool cleared their points and the layout skips them.
            st.points, st.shown = {}, not absent
            if not collapsed then list[#list + 1] = b end
        end
        if world.gamepadUI then list[#list + 1] = self.bagIcons[bagID] end
    end
    for i, b in ipairs(list) do
        local row, col = math.floor((i - 1) / 10), (i - 1) % 10
        state(b).points = { { point = "BOTTOMRIGHT", rel = self.bagMoney, relPoint = "TOPRIGHT",
            x = -col * 42, y = 4 + row * 42 } }
        self.bagInfo[b].order = #list - i + 1   -- reading order: 1 is the top left button
    end
    -- UpdateFrameSize: the window is as tall as its rows.
    local bst = state(self.bagFrame)
    bst.width, bst.height = 436, 96 + math.ceil(#list / 10) * 42
end

-- Blizzard's X on a bag button (Gamepad_ToggleCollapseBag, ContainerFrame.lua:3346-3355): the
-- bag is collapsed or expanded, the items are laid out again and the layout pass runs.
function Client:collapseBag(bagID, collapsed)
    self.world.collapsed[bagID] = collapsed and true or nil
    self:relayoutBag()
end

-- A full Blizzard layout of the open bag: the items, then the layout pass.
function Client:relayoutBag()
    self:layoutBagItems()
    self._protect("UpdateContainerFrameAnchors", self.env.UpdateContainerFrameAnchors)
end

-- Blizzard hands its pooled item buttons back to the slots in no fixed order each time the
-- bag is generated (ContainerFrame_GenerateFrame; the pool's free list is walked with pairs,
-- Pools.lua), so after the bag is closed and opened, or a bag is folded, a slot may be served
-- by another button. This changes which button serves which slot: every slot gets the button
-- that served the slot `by` places on (default 7), over all bags together. Nothing is laid out
-- here; follow it with c:openBag(), c:collapseBag() or c:relayoutBag(). c.bagSlots and
-- c.bagInfo follow, so c:bagCells() still tells the truth.
function Client:shuffleBagButtons(by)
    assert(self.bagButtons, "fakeclient: buildBag first")
    local places, buttons = {}, {}
    for _, bagID in ipairs({ KEYRING, 5, 4, 3, 2, 1, 0 }) do
        for slot = 1, self.bagSizes[bagID] do
            places[#places + 1] = { bag = bagID, slot = slot }
            buttons[#buttons + 1] = self.bagSlots[bagID][slot]
        end
    end
    local n = #places
    if n < 2 then return end
    by = (by or 7) % n
    if by == 0 then by = 1 end
    for i, place in ipairs(places) do
        local b = buttons[(i - 1 + by) % n + 1]
        self.bagSlots[place.bag][place.slot] = b
        local e = self.bagInfo[b]
        e.bag, e.slot = place.bag, place.slot
    end
end

-- A client whose bag has no bag bar (the name is gone, the buttons stay where they are).
function Client:removeBagBar()
    rawset(self.env, "GamepadBagBar", nil)
end

-- Where every laid-out button of the built bag is now, in Blizzard's reading order (the order
-- its own layout gives: backpack button, backpack slots 1.., first bag's button, ...). Each
-- entry: button, kind ("icon" or "slot"), bag, slot, x, y (the anchor's offsets), col (1 is the
-- leftmost of the ten columns) and row (1 is the top row in use). Buttons that are hidden or
-- have no point (a collapsed bag's slots) are left out.
function Client:bagCells()
    local out, top = {}, nil
    for _, b in ipairs(self.bagButtons) do
        local st = self._state(b)
        local p = st.points[1]
        if st.shown and #st.points == 1 then
            local e = self.bagInfo[b]
            out[#out + 1] = { button = b, kind = e.kind, bag = e.bag, slot = e.slot, order = e.order,
                point = p.point, rel = p.rel, relPoint = p.relPoint, x = p.x, y = p.y }
            if not top or p.y > top then top = p.y end
        end
    end
    for _, e in ipairs(out) do
        e.col = 10 + e.x / 42
        e.row = 1 + (top - e.y) / 42
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

-- A client without Blizzard's controller navigation helpers (world.noSmartNav).
function Client:removeSmartNav()
    self.world.noSmartNav = true
    rawset(self.env, "SMART_NAV_INPUT_DIRECTION", nil)
    rawset(self.env, "SmartNavigation_AddJumpNavigationOverride", nil)
    rawset(self.env, "SmartNavigation_ClearJumpNavigationOverridesInDirection", nil)
end

-- The controller cursor leaves the button it is on (SmartNavigation.lua:680: the button's
-- optional OnSmartNavDeselect is called).
function Client:padLeave()
    local prev = self.padFocus
    self.padFocus = nil
    local fn = prev and rawget(prev, "OnSmartNavDeselect")
    if type(fn) == "function" then self._protect("OnSmartNavDeselect", fn, prev) end
end

-- One d-pad press with the cursor on `from`, by the rule at the top of Blizzard's Navigate
-- (SmartNavigation.lua:1503-1530): a jump override for that direction ("left", "right", "up",
-- "down") that is a visible frame takes the cursor there, whatever window it belongs to.
-- Returns the button the cursor went to, or nil when there is no usable override (the game
-- then moves inside the window's own grid, which the stand-in does not model).
function Client:padMove(from, dir)
    local target = rawget(from, "smartNavigationOverride-" .. dir)
    if not (self._isWidget(target) and target:IsVisible()) then return nil end
    if self.padFocus == nil then self.padFocus = from end
    self:padLeave()
    self.padFocus = target
    local fn = rawget(target, "OnSmartNavSelect")
    if type(fn) == "function" then self._protect("OnSmartNavSelect", fn, target) end
    return target
end

function Client:openMerchant()
    self.world.merchant.open = true
    self.env.MerchantFrame:Show()
    self:fire("MERCHANT_SHOW")
end

function Client:closeMerchant()
    self.world.merchant.open = false
    self.env.MerchantFrame:Hide()
    self:fire("MERCHANT_CLOSED")
end

-- The quest log's menu, opened the way the game does (by the global name, so a
-- hook on it runs). Returns the menu frame.
function Client:openQuestMenu()
    local fn = rawget(self.env, "QuestMapLogTitleButton_CreateContextMenu")
    if type(fn) ~= "function" then error("fakeclient: c:openQuestMenu(): this client has no quest menu function", 2) end
    self.lastQuestMenu = nil
    self._protect("QuestMapLogTitleButton_CreateContextMenu", fn, { questID = 1 })
    return self.lastQuestMenu
end

function Client:enterCombat()
    self:fire("PLAYER_REGEN_DISABLED") -- lockdown starts after this event's handlers
    self.world.inCombat = true
end

function Client:leaveCombat()
    self.world.inCombat = false
    self:fire("PLAYER_REGEN_ENABLED")
end

-- (text, playerName, languageName, channelName, playerName2, specialFlags,
-- zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, ...)
-- (ChatInfoDocumentation.lua CHAT_MSG_WHISPER payload)
function Client:whisperIn(from, text)
    self.lineID = (self.lineID or 0) + 1
    self:fire("CHAT_MSG_WHISPER", text or "hi", from, "Common", "", from, "", 0, 0, "", 7, self.lineID,
        "Player-1-0000ABCD", 0, false, false, false, false)
end

function Client:whisperOut(to, text)
    self.lineID = (self.lineID or 0) + 1
    self:fire("CHAT_MSG_WHISPER_INFORM", text or "hello", to, "Common", "", to, "", 0, 0, "", 7, self.lineID,
        "Player-1-0000ABCE", 0, false, false, false, false)
end

return Client
