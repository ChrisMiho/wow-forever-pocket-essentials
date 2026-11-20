-- Pocket Essentials: the setup guide (PE.Setup).
-- A window of a few screens that shows each feature as a card with its switch
-- and lets the player switch on the ones they want (spec
-- 2026-11-20-0.9.0-ui-redesign, "Setup guide"). Every feature starts off;
-- this is how a player finds out what exists.
--
-- It opens by itself a moment after the first loading screen, on an account
-- that never pressed Finish or Skip in it (PocketEssentialsDB.setup is then
-- nil; Finish stores "finished", Skip stores "skipped"). It can be opened
-- again from the settings (General tab, "Setup guide") and with /pe setup.
--
-- The cards are drawn by the settings window's list drawer (Settings.lua,
-- PE:NewListDrawer), so both windows show the same names, controls and saved
-- values, and a press takes the same path. A switch here writes through
-- PE:SetModuleEnabled, as the settings switch does; this file never writes
-- the saved on/off table itself.
--
-- "Move things now" (and "Move the arrow" in the quest arrow's card) opens
-- Move on screen: the guide goes away and comes back on the same screen when
-- that window closes (Move.lua calls Setup:BackFromMove).
--
-- Nothing is built until the guide is first opened. It has no per-frame code.
-- While open it listens for one thing (a fight starting, which hides it);
-- while closed it listens for nothing, except the single "fight ended" wait
-- after a fight hid it or kept it from opening at login.
local ADDON_NAME, PE = ...

local Setup = {}
PE.Setup = Setup

local type, tostring, ipairs, pairs, pcall = type, tostring, ipairs, pairs, pcall
local max, min, sin, cos, pi = math.max, math.min, math.sin, math.cos, math.pi

local PANEL_NAME = "PocketEssentialsSetupPanel" -- the prefix matters: our windows close each other by it
local TITLE = "Setup"
local FIRST_LOGIN_DELAY = 1.5 -- seconds after the first loading screen

local TEXT_CLOSED = "Setup guide closed. It will show again next time you log in. Press Skip in it to stop that. "
    .. "You can open it any time from the settings."
local TEXT_FIGHT = "The setup guide cannot be opened during a fight. Try again afterwards."
local TEXT_BROKEN = "The setup guide could not be opened. See Errors in the settings."
local TEXT_FAILED = "Switched on, but it hit a problem. See the Errors tab in the settings."

local COLOR = {
    line = { 0.88, 0.88, 0.88 },
    name = { 0.92, 0.92, 0.92 },
    small = { 0.84, 0.84, 0.84 },
    dim = { 0.62, 0.62, 0.62 },
    gold = { 1, 0.82, 0 },
    warn = { 1, 0.60, 0.20 },
    dotOff = { 0.35, 0.35, 0.38 },
    glyph = { 0.70, 0.70, 0.72 },
    glyphFill = { 0.16, 0.16, 0.18 },
    tile = { 0.12, 0.12, 0.14 },
    screen = { 0.20, 0.17, 0.13 },
    screenEdge = { 0.35, 0.35, 0.38 },
}

-- The "How:" line of a feature's card in the guide.
local HOW = {
    questIcons = "Tap an icon on the map to see what it is for.",
    questArrow = "Focus a quest in your quest log, and the arrow points to it.",
    chat = "Tap PE, pick who to talk to, then press A to type.",
    menuBg = "For menus like Track, Focus and Share on a quest.",
}

---------------------------------------------------------------------------
-- The screens, in order.
--
-- A screen: { id =, title =, lines = { ... }, draw = name, cards = { ... },
--             needsOn = feature key }
--   lines: short sentences under the title.
--   draw:  the name of a function below that draws the screen's own cards
--          (before its feature cards).
--   cards: feature cards, { key = <feature key>, only = { option keys } }.
--          A card is shown only when its feature is in this build. A screen
--          that has cards but no draw, and none of whose features is in this
--          build, is skipped.
--   needsOn: the screen is shown only while that feature is on.
---------------------------------------------------------------------------

local SCREENS = {
    { id = "welcome", title = "Welcome", draw = "Welcome",
      lines = { "A few helpers for playing on a handheld. They all start off: switch on the ones you want.",
                "You can change everything later in the settings." } },
    { id = "questIcons", title = "Quest icons",
      lines = { "Quest locations come from QuestieDB, which is included." },
      cards = { { key = "questIcons", only = { "show", "Icons on", "size" } } } },
    { id = "questDetails", title = "Quest icon details", draw = "QuestDetails", needsOn = "questIcons" },
    { id = "questArrow", title = "Quest arrow", cards = { { key = "questArrow" } } },
    { id = "bags", title = "Bags", cards = { { key = "bagWindow" }, { key = "bags" } } },
    { id = "vendors", title = "Vendors and menus", cards = { { key = "sellJunk" }, { key = "repair" }, { key = "menuBg" } } },
    { id = "chat", title = "Round button and chat", draw = "RoundButton",
      lines = { "The PE button is always on screen. With Chat picker on, a tap opens the chat window." },
      cards = { { key = "chat" } } },
    { id = "layout", title = "Your screen", draw = "Layout",
      lines = { "This is where each piece sits to start with. Move any of them to suit your screen." } },
    { id = "finish", title = "All set", draw = "Finish" },
}

local UI           -- PE.UI, set when the window is built
local M            -- current metrics
local panel, area
local list         -- the list drawer of this window (PE:NewListDrawer in Settings.lua)
local backButton, skipButton, nextButton, reloadButton
local dots = {}    -- one per screen, between Skip and Next
local built, buildFailed = false, false
local drawing, drawQueued = false, false
local navList = {}  -- tappable buttons in reading order, rebuilt on every draw
local current = SCREENS[1].id -- the screen showing
local closeWhy      -- why the window is being hidden, for OnHidden
local waiting       -- "login" or "fight": the guide comes (back) when the fight ends
local resumeScreen  -- the screen a fight or Move on screen interrupted
local toldClosed = false -- the "closed, will show again" chat line was printed this session
local handlers = {} -- tap handlers made once, at build

local function Debug(text)
    if PE.debugOn then PE:Debug("setup", text) end
end

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

---------------------------------------------------------------------------
-- What was answered before
---------------------------------------------------------------------------

-- False when the saved settings did not load: the addon then runs on a
-- stand-in table that the game never writes, so an answer could not be kept.
local function SavedLoaded()
    return PE.db ~= nil and PE.db == _G.PocketEssentialsDB
end

-- "finished", "skipped" or nil. Any other saved value reads as never seen.
function Setup:Seen()
    local value = PE.db and PE.db.setup
    if value == "finished" or value == "skipped" then return value end
    return nil
end

-- Finish is never turned back into Skip.
local function Remember(value)
    if not SavedLoaded() then return end
    if value == "skipped" and PE.db.setup == "finished" then return end
    PE.db.setup = value
end

---------------------------------------------------------------------------
-- Which screens show right now
---------------------------------------------------------------------------

local function ScreenShown(screen)
    if screen.needsOn then
        return PE:GetModule(screen.needsOn) ~= nil and PE:IsModuleEnabled(screen.needsOn)
    end
    if screen.cards and not screen.draw then
        for _, card in ipairs(screen.cards) do
            if PE:GetModule(card.key) then return true end
        end
        return false
    end
    return true
end

local function Visible()
    local out = {}
    for _, screen in ipairs(SCREENS) do
        if ScreenShown(screen) then out[#out + 1] = screen end
    end
    return out
end

-- The place of the current screen among the shown ones. A current screen
-- that is not shown (its feature went off) counts as the shown one before it.
local function PositionOf(shown)
    local pos = 0
    local seen = {}
    for _, screen in ipairs(shown) do seen[screen] = true end
    for _, screen in ipairs(SCREENS) do
        if seen[screen] then pos = pos + 1 end
        if screen.id == current then
            if seen[screen] then return pos, true end
            return max(pos, 1), false
        end
    end
    return 1, false
end

local function ScreenById(id)
    for _, screen in ipairs(SCREENS) do
        if screen.id == id then return screen end
    end
end

---------------------------------------------------------------------------
-- Switches: the settings switch's path, with the guide's debug lines
---------------------------------------------------------------------------

local QueueDraw -- defined below

local function OnSwitch(key)
    if key == nil then return end
    if PE:GetModuleState(key) == "blocked" then
        Debug("switch tapped: " .. tostring(key) .. " cannot be switched on")
        return
    end
    local on = not PE:IsModuleSavedOn(key)
    Debug("switch tapped: " .. tostring(key) .. " -> " .. (on and "on" or "off"))
    PE:SetModuleEnabled(key, on)
    QueueDraw()
end

local switchHandlers = {}
local function SwitchHandler(key)
    local fn = switchHandlers[key]
    if not fn then
        fn = PE:Wrap("core", function() OnSwitch(key) end)
        switchHandlers[key] = fn
    end
    return fn
end

---------------------------------------------------------------------------
-- Small pictures (all from the drawer's pools, set again on every draw)
---------------------------------------------------------------------------

-- A plain rectangle. pool: "low", "mid", "shape" or "top" (drawn in that
-- order, each above the one before; all above the card fill).
local function Rect(pool, x, y, w, h, c, alpha)
    local tex = list:Acquire(pool)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", list.child, "TOPLEFT", x, -y)
    tex:SetSize(max(w, 0.01), max(h, 0.01))
    tex:SetColorTexture(c[1], c[2], c[3], alpha or 1)
    list:Reach(y + h)
    return tex
end

-- A round picture: an outer disc, an inner disc and a word in the middle.
-- Used for the A / B glyphs and for the PE button.
-- wordSize: the word's own size (the A / B letters); nil keeps the font's.
local function Round(x, y, d, outer, inner, innerD, word, wordColor, wordSize)
    local f = list:Acquire("round")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", list.child, "TOPLEFT", x, -y)
    f:SetSize(d, d)
    f.outer:SetColor(outer[1], outer[2], outer[3], 1)
    f.outer:Layout(f, d)
    f.inner:SetColor(inner[1], inner[2], inner[3], 1)
    f.inner:Layout(f, max(innerD, 1))
    -- Pooled: the shared font first, in case an earlier use changed its size.
    pcall(f.word.SetFontObject, f.word, M.font)
    if wordSize then
        local ok, face, _, flags = pcall(f.word.GetFont, f.word)
        if ok and type(face) == "string" and face ~= "" then
            pcall(f.word.SetFont, f.word, face, max(wordSize, 1), flags or "")
        end
    end
    f.word:SetWidth(d)
    f.word:SetText(word or "")
    local c = wordColor or COLOR.name
    f.word:SetTextColor(c[1], c[2], c[3], 1)
    list:Reach(y + d)
    return f
end

-- A d-pad cross, d wide.
local function DpadGlyph(x, y, d)
    local a, b = d / 3, M.border
    Rect("shape", x + a, y, a, d, COLOR.glyph)
    Rect("shape", x, y + a, d, a, COLOR.glyph)
    Rect("top", x + a + b, y + a + b, max(a - 2 * b, 1), max(a - 2 * b, 1), COLOR.glyphFill)
end

-- A box of gold dashes over a faint fill.
local function DashedBox(x, y, w, h, c, alpha, fill)
    if fill then Rect("shape", x, y, w, h, c, 0.15) end
    local dash, gap, t = max(UI:Px(5), 2), max(UI:Px(3), 1), max(UI:Px(1.5), 1)
    local function Run(length, place)
        local pos = 0
        while pos < length do
            place(pos, min(dash, length - pos))
            pos = pos + dash + gap
        end
    end
    Run(w, function(p, s) Rect("top", x + p, y, s, t, c, alpha) end)
    Run(w, function(p, s) Rect("top", x + p, y + h - t, s, t, c, alpha) end)
    Run(h, function(p, s) Rect("top", x, y + p, t, s, c, alpha) end)
    Run(h, function(p, s) Rect("top", x + w - t, y + p, t, s, c, alpha) end)
end

-- A text placed by the drawer, then moved to (x, y) and centred in width.
local function CenteredText(kind, text, x, y, width, color)
    local h, fs = list:Text(kind, text, x, y, width, color)
    fs:SetJustifyH("CENTER")
    return h, fs
end

local function HubColors()
    local Hub = PE.Hub
    local colors = Hub and Hub.Colors and Hub:Colors()
    if type(colors) ~= "table" or type(colors.ring) ~= "table" or type(colors.fill) ~= "table" then
        colors = { ring = COLOR.gold, fill = { 0.07, 0.07, 0.10 } }
    end
    return colors
end

-- The round PE button, d wide; ring: a dashed ring around it (the Hold tile).
local function HubPicture(x, y, d, ring)
    local colors = HubColors()
    Round(x, y, d, colors.ring, colors.fill, d - max(UI:Px(4), 2) * 2 * (d / max(M.hub, 1)), "PE", colors.ring)
    if ring then
        local r = d * 0.5 + UI:Px(5)
        local s = max(UI:Px(2.5), 1)
        local cx, cy = x + d * 0.5, y + d * 0.5
        for k = 0, 17 do
            local a = k * pi * 2 / 18
            Rect("shape", cx + cos(a) * r - s * 0.5, cy + sin(a) * r - s * 0.5, s, s, colors.ring)
        end
    end
end

-- The gold outline that Move on screen draws, d wide.
local function MovePicture(x, y, d)
    local e = max(UI:Px(3), 2)
    Rect("shape", x, y, d, d, COLOR.gold, 0.15)
    Rect("top", x - e, y - e, d + 2 * e, e, COLOR.gold)
    Rect("top", x - e, y + d, d + 2 * e, e, COLOR.gold)
    Rect("top", x - e, y, e, d, COLOR.gold)
    Rect("top", x + d, y, e, d, COLOR.gold)
end

---------------------------------------------------------------------------
-- Each screen's own cards
---------------------------------------------------------------------------

local SIZE_CHOICES = {
    { value = "small", label = "Small" },
    { value = "medium", label = "Medium" },
    { value = "large", label = "Large" },
}

local COLOR_CHOICES = {
    { value = "gold", label = "Gold" },
    { value = "horde", label = "Horde" },
    { value = "alliance", label = "Alliance" },
}

local function Items(choices, currentValue, handlerOf)
    local items = {}
    for i, choice in ipairs(choices) do
        items[i] = { label = choice.label, selected = (currentValue == choice.value), onClick = handlerOf[choice.value] }
    end
    return items
end

local DRAW = {}

-- Welcome: the play-style question and the controls card.
function DRAW.Welcome(y, width)
    local touch = PE:UsesTouch()
    y = list:Card(0, y, width, function(ix, iy, iw)
        return list:ChoiceRow("How do you play?", {
            { label = "Touch controls", selected = touch, onClick = handlers.touch },
            { label = "Controller", selected = not touch, onClick = handlers.controller },
        }, ix, iy, iw)
    end) + M.gap
    return list:Card(0, y, width, function(ix, iy, iw)
        local yy = iy
        yy = yy + list:Text("small", "Getting around these windows", ix, yy, iw, COLOR.gold) + M.gap * 0.6
        local d = M.button * 0.75
        local cw = (iw - 2 * M.gap) / 3
        local items = {
            { glyph = "dpad", text = "Move the blue highlight" },
            { glyph = "A", text = "Press the highlighted button" },
            { glyph = "B", text = "Close the window" },
        }
        local rowHeight = d
        for i, item in ipairs(items) do
            local cx = ix + (i - 1) * (cw + M.gap)
            if item.glyph == "dpad" then
                DpadGlyph(cx, yy, d)
            else
                Round(cx, yy, d, COLOR.glyph, COLOR.glyphFill, d - 2 * M.border, item.glyph, { 1, 1, 1 }, d * 0.55)
            end
            local tw = max(cw - d - M.gap, 10)
            local h, fs = list:Text("font", item.text, cx + d + M.gap, yy, tw, COLOR.name)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", list.child, "TOPLEFT", cx + d + M.gap, -(yy + max((d - h) * 0.5, 0)))
            rowHeight = max(rowHeight, h)
        end
        list:Reach(yy + rowHeight)
        yy = yy + rowHeight + M.gap * 0.8
        yy = yy + list:Text("small", touch and "Or just tap any button on the screen." or "Touch works too, any time.",
            ix, yy, iw, COLOR.dim)
        return yy + M.gap
    end)
end

-- Quest icon details: the rest of the Quest icons rows, then what each icon means.
function DRAW.QuestDetails(y, width)
    local mod = PE:GetModule("questIcons")
    if not mod then return y end
    y = list:Card(0, y, width, function(ix, iy, iw)
        return list:Options(mod, ix, iy, iw, { only = { "cluster", "spots", "hideHaze" }, setup = true })
    end) + M.gap
    return list:Card(0, y, width, function(ix, iy, iw)
        local yy = iy + list:Text("small", "What the icons mean", ix, iy, iw, COLOR.gold) + M.gap * 0.6
        local key = PE.QuestIconKey -- made when QuestIcons.lua loads, so read it here
        if type(key) ~= "table" then return yy + M.gap end
        local side = M.button * 0.7
        local n = min(#key, 5)
        local colWidth = iw / max(n, 1)
        local rowHeight = side
        for i = 1, n do
            local entry = key[i]
            if type(entry) == "table" then
                local cx = ix + (i - 1) * colWidth
                local icon = list:Acquire("icon")
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", list.child, "TOPLEFT", cx, -yy)
                icon:SetSize(side, side)
                icon:SetTexture(entry.tex)
                local c = type(entry.color) == "table" and entry.color or COLOR.name
                icon:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1)
                local tx = cx + side + M.gap * 0.5
                local h, fs = list:Text("font", Escape(entry.label or ""), tx, yy, max(colWidth - side - M.gap, 10), COLOR.name)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", list.child, "TOPLEFT", tx, -(yy + max((side - h) * 0.5, 0)))
                rowHeight = max(rowHeight, h)
            end
        end
        list:Reach(yy + rowHeight)
        return yy + rowHeight + M.gap
    end)
end

-- Round button and chat: a live picture of the round button beside its two choices.
function DRAW.RoundButton(y, width)
    local ui = PE.db and PE.db.ui or {}
    return list:Card(0, y, width, function(ix, iy, iw)
        local pv = M.hub * 1.6
        HubPicture(ix, iy, pv)
        local rx = ix + pv + M.gap * 2
        local rw = max(iw - pv - M.gap * 2, 10)
        local ry = iy
        ry = list:ChoiceRow("Colour", Items(COLOR_CHOICES, ui.hubColor or "gold", handlers.color), rx, ry, rw)
        ry = list:ChoiceRow("Size of all Pocket Essentials buttons", Items(SIZE_CHOICES, M.size, handlers.size), rx, ry, rw)
        return max(iy + pv + M.gap, ry)
    end)
end

-- A small picture of the screen with a gold dashed box where each piece of
-- Move on screen sits now, and the minimap's outline. Returns its height.
local function ScreenPicture(x, y, w)
    local h = w * 9 / 16
    Rect("low", x, y, w, h, COLOR.screenEdge)
    local edge = max(UI:Px(1), 1)
    Rect("mid", x + edge, y + edge, w - 2 * edge, h - 2 * edge, COLOR.screen)
    local sl, sr, st, sb = UIParent:GetLeft(), UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (sl and sr and st and sb) or sr - sl < 1 or st - sb < 1 then return h end
    local fx, fy = w / (sr - sl), h / (st - sb)
    -- A rectangle of the screen (left, bottom, width, height) in the picture.
    local function Place(l, b, rw, rh)
        local bx = min(max((l - sl) * fx, 0), w - 2)
        local by = min(max((st - (b + rh)) * fy, 0), h - 2)
        local bw = min(max(rw * fx, 2), w - bx)
        local bh = min(max(rh * fy, 2), h - by)
        return x + bx, y + by, bw, bh
    end
    local minimap = _G.Minimap
    if type(minimap) == "table" and type(minimap.GetLeft) == "function" then
        local ok, l, r, t, b = pcall(function() return minimap:GetLeft(), minimap:GetRight(), minimap:GetTop(), minimap:GetBottom() end)
        if ok and l and r and t and b then
            local bx, by, bw, bh = Place(l, b, r - l, t - b)
            DashedBox(bx, by, bw, bh, { 1, 1, 1 }, 0.35, false)
        end
    end
    local Move = PE.Move
    if not (Move and Move.Pieces and Move.PieceRect) then return h end
    for _, piece in ipairs(Move:Pieces()) do
        local l, b, rw, rh = Move:PieceRect(piece.key)
        if l then
            local bx, by, bw, bh = Place(l, b, rw, rh)
            DashedBox(bx, by, bw, bh, COLOR.gold, 1, true)
            local label = tostring(piece.label):gsub("\"", "")
            local tw = min(bw + UI:Px(80), w)
            local tx = min(max(bx + bw * 0.5 - tw * 0.5, x), x + w - tw)
            CenteredText("small", Escape(label), tx, by + bh + UI:Px(3), tw, COLOR.gold)
        end
    end
    return h
end

-- Your screen: the picture, and Move things now beside it.
function DRAW.Layout(y, width)
    return list:Card(0, y, width, function(ix, iy, iw)
        local room = max((area.viewHeight or 0) - M.button * 3, M.button * 2)
        local pw = min(iw * 0.62, room * 16 / 9)
        local ph = ScreenPicture(ix, iy, pw)
        local rx = ix + pw + M.gap * 2
        local rw = max(iw - pw - M.gap * 2, 10)
        local ry = iy
        ry = ry + list:Text("font", "Gold boxes show where each piece starts.", rx, ry, rw, COLOR.name) + M.gap
        list:Button("Move things now", rx, ry, rw, M.button, "normal", handlers.moveNow)
        ry = ry + M.button + M.gap * 0.6
        ry = ry + list:Text("small", "You can do this later too: Settings, General tab.", rx, ry, rw, COLOR.dim)
        list:Reach(ry)
        return iy + max(ph, ry - iy) + M.gap
    end)
end

-- Three tiles of the same size: Tap, Hold, Move things.
local TILES = {
    { title = "Tap", text = "Opens the settings, or Chat picker when it is on.", picture = "hub" },
    { title = "Hold", text = "Always opens the settings.", picture = "hold" },
    { title = "Move things", text = "Settings, General tab.", picture = "move" },
}

local function Tiles(x, y, width)
    local n = #TILES
    local tw = (width - (n - 1) * M.gap) / n
    local inner = max(tw - 2 * M.pad, 10)
    local d = M.hub * 0.8
    local boxHeight = d + UI:Px(14)
    -- The texts first, to know the tallest; they are moved into place below.
    local texts, textHeight = {}, 0
    for i, tile in ipairs(TILES) do
        local h, fs = CenteredText("small", tile.text, x, y, inner, COLOR.small)
        texts[i] = fs
        textHeight = max(textHeight, h)
    end
    local titleHeight = M.fontSize * 1.15
    local tileHeight = M.pad + boxHeight + M.gap + titleHeight + M.gap * 0.3 + textHeight + M.pad
    for i, tile in ipairs(TILES) do
        local tx = x + (i - 1) * (tw + M.gap)
        Rect("low", tx, y, tw, tileHeight, COLOR.tile)
        local px, py = tx + tw * 0.5 - d * 0.5, y + M.pad + UI:Px(7)
        if tile.picture == "move" then
            MovePicture(px, py, d)
        else
            HubPicture(px, py, d, tile.picture == "hold")
        end
        local ty = y + M.pad + boxHeight + M.gap
        CenteredText("font", tile.title, tx + M.pad, ty, inner, COLOR.gold)
        texts[i]:ClearAllPoints()
        texts[i]:SetPoint("TOPLEFT", list.child, "TOPLEFT", tx + M.pad, -(ty + titleHeight + M.gap * 0.3))
    end
    list:Reach(y + tileHeight)
    return y + tileHeight
end

-- All set: what is on and off, the three tiles, and the reload offer when a
-- feature asked for one.
function DRAW.Finish(y, width)
    local on, off = {}, {}
    for _, mod in ipairs(PE.moduleList) do
        local into = PE:IsModuleEnabled(mod.key) and on or off
        into[#into + 1] = Escape(mod.label)
    end
    y = list:Card(0, y, width, function(ix, iy, iw)
        local yy = iy
        yy = yy + list:Text("font", "|cff59eb73On: |r" .. (#on > 0 and table.concat(on, ", ") or "nothing yet"),
            ix, yy, iw, COLOR.name) + M.gap * 0.5
        if #off > 0 then
            yy = yy + list:Text("font", "|cff9e9ea3Off: |r" .. table.concat(off, ", "), ix, yy, iw, COLOR.name) + M.gap * 0.5
        end
        return yy + M.gap * 0.5
    end) + M.gap
    y = Tiles(0, y, width) + M.gap

    local reasons = PE.reloadReasons
    if type(reasons) == "table" and #reasons > 0 then
        local buttonWidth = M.button * 4.5
        local why = {}
        for i = 1, min(#reasons, 2) do
            why[i] = Escape(reasons[i].label) .. ": " .. Escape(reasons[i].reason)
        end
        local textHeight = list:Text("small", table.concat(why, "\n"), 0, y, width - buttonWidth - M.gap, COLOR.warn)
        local rowHeight = max(M.button, textHeight)
        reloadButton:ClearAllPoints()
        reloadButton:SetSize(buttonWidth, M.button)
        reloadButton:SetPoint("TOPLEFT", area.child, "TOPLEFT", width - buttonWidth, -y)
        reloadButton.peScrollTop, reloadButton.peScrollBottom = y, y + rowHeight
        reloadButton:Show()
        navList[#navList + 1] = reloadButton
        list:Reach(y + rowHeight)
        y = y + rowHeight + M.gap
    end
    return y
end

---------------------------------------------------------------------------
-- Drawing one screen
---------------------------------------------------------------------------

-- A feature's card, with the guide's own tap on its switch (same path as the
-- settings switch, plus the guide's debug line). Returns the new y.
local function FeatureCard(mod, card, y, width)
    local mark = #navList
    local ok, nextY = PE:Safe(mod.key, list.FeatureCard, list, mod, 0, y, width,
        { setup = true, only = card.only, how = HOW[mod.key], failedText = TEXT_FAILED })
    for i = mark + 1, #navList do
        local btn = navList[i]
        if btn.peKey == mod.key and btn.SetSwitch then btn:SetScript("OnClick", SwitchHandler(mod.key)) end
    end
    if ok and type(nextY) == "number" then return nextY end
    return max(y, list.lowest) + M.gap
end

-- Title, lines, the screen's own cards, then its feature cards. Returns the
-- total height.
local function DrawScreen(screen, width)
    local y = 0
    y = y + list:Text("title", screen.title, 0, y, width) + M.gap * 0.5
    for _, line in ipairs(screen.lines or {}) do
        y = y + list:Text("font", line, 0, y, width, COLOR.line) + M.gap * 0.5
    end
    y = y + M.gap * 0.5
    if screen.draw and DRAW[screen.draw] then
        local ok, nextY = PE:Safe("core", DRAW[screen.draw], y, width)
        y = (ok and type(nextY) == "number") and nextY or (max(y, list.lowest) + M.gap)
    end
    for _, card in ipairs(screen.cards or {}) do
        local mod = PE:GetModule(card.key)
        -- Two gaps after each feature card, as between the cards in the settings.
        if mod then y = FeatureCard(mod, card, y, width) + M.gap end
    end
    return max(y, list.lowest) + M.pad
end

local function PanelSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    return min(screenWidth * 0.96, UI:Px(1180)), screenHeight * 0.92
end

-- Back and Skip at the bottom left, Next at the bottom right: always in the
-- same place, so pressing A again and again walks through the guide. One dot
-- per screen between them, the current one gold.
local function LayoutBottomRow(count, pos)
    local width = M.button * 3.5
    local content = panel.content
    backButton:ClearAllPoints()
    backButton:SetSize(width, M.button)
    backButton:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    skipButton:ClearAllPoints()
    skipButton:SetSize(width, M.button)
    skipButton:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", width + M.gap, 0)
    nextButton:ClearAllPoints()
    nextButton:SetSize(width, M.button)
    nextButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    -- The dots are centred in the room between Skip's right edge and Next's
    -- left edge; when they do not fit there with a full gap, the gap shrinks.
    local d = M.smallFontSize * 0.6
    local roomLeft = 2 * width + M.gap
    local roomRight = (panel.contentWidth or 0) - width
    local room = roomRight - roomLeft - 2 * M.gap
    local dotGap = M.gap
    if count > 1 and count * d + (count - 1) * dotGap > room then
        dotGap = max((room - count * d) / (count - 1), d * 0.25)
    end
    local total = count * d + (count - 1) * dotGap
    local x0 = (roomLeft + roomRight) * 0.5 - total * 0.5
    for k = 1, #dots do
        local dot = dots[k]
        if k <= count then
            dot:ClearAllPoints()
            dot:SetSize(d, d)
            dot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", x0 + (k - 1) * (d + dotGap), (M.button - d) * 0.5)
            local c = k == pos and COLOR.gold or COLOR.dotOff
            dot.disc:SetColor(c[1], c[2], c[3], 1)
            dot.disc:Layout(dot, d)
            dot.peCurrent = k == pos
            dot:Show()
        else
            dot:Hide()
        end
    end
end

-- True while the guide's first screen has not yet put the highlight on Start.
local focusStart = false

local function DoDraw()
    M = UI:Metrics()

    local shown = Visible()
    local pos, isShown = PositionOf(shown)
    if not isShown and shown[pos] then current = shown[pos].id end
    local screen = shown[pos]
    if not screen then return end
    local count = #shown
    local isFirst, isLast = pos == 1, pos == count
    panel:SetTitle(TITLE)

    LayoutBottomRow(count, pos)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    local areaHeight = max(panel.contentHeight - M.button - M.gap, M.button * 2 + M.gap)
    local total
    -- First with no paging buttons and the whole width. Only a screen that
    -- turns out too long is drawn again, narrower, with Up and Down.
    for pass = 1, 2 do
        for i = #navList, 1, -1 do navList[i] = nil end
        list:Begin()
        area:Layout(panel.contentWidth, areaHeight, pass == 1)
        reloadButton:Hide()
        local ok
        ok, total = PE:Safe("core", DrawScreen, screen, area.viewWidth)
        if not ok or type(total) ~= "number" then total = area.viewHeight end
        if total <= area.viewHeight + 0.5 then break end
    end
    list:End()
    area:SetContentHeight(total)

    -- Reading order for the d-pad: what is in the list, the paging buttons
    -- when there is something to page, the bottom row, Close.
    if area:GetRange() > 0 and area.upButton:IsShown() then
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    backButton:SetShown(not isFirst)
    skipButton:SetShown(not isLast)
    nextButton:SetLabel(isLast and "Finish" or isFirst and "Start" or "Next")
    nextButton:SetStyle(isLast and "on" or "normal")
    if not isFirst then navList[#navList + 1] = backButton end
    if not isLast then navList[#navList + 1] = skipButton end
    navList[#navList + 1] = nextButton
    navList[#navList + 1] = panel.closeButton

    -- The highlighted button went away with the screen (Back on the first
    -- screen): the highlight goes to Next.
    local focus = panel.peNavFocus
    if focusStart and isFirst then
        focusStart = false
        panel:NavSetFocus(nextButton)
    elseif focus then
        local still = false
        for i = 1, #navList do
            if navList[i] == focus then still = true end
        end
        if not still then panel:NavSetFocus(nextButton) end
    end
    panel:NavRefresh()
end

local function Draw()
    if drawing or not built or not panel:IsShown() then return end
    drawing = true
    PE:Safe("core", DoDraw)
    drawing = false
end

local function QueuedDraw()
    drawQueued = false
    Draw()
end

-- Redraw once on the next frame, however many times this is asked for.
-- Returns at its first line while the guide is closed.
QueueDraw = function()
    if drawQueued or not built or not panel:IsShown() then return end
    if C_Timer and C_Timer.After then
        drawQueued = true
        C_Timer.After(0, PE:Wrap("core", QueuedDraw))
    else
        Draw()
    end
end

local function ScreenIds(shown)
    local ids = {}
    for i, screen in ipairs(shown) do ids[i] = screen.id end
    return ids
end

-- Back (-1) and Next / Start / Finish (+1).
local function Go(step)
    local shown = Visible()
    local pos, isShown = PositionOf(shown)
    if step > 0 and isShown and pos >= #shown then
        Setup:Close("finished")
        return
    end
    -- From a screen that is no longer shown, pos is the shown one before it.
    if not isShown and step < 0 then pos = pos + 1 end
    pos = max(min(pos + step, #shown), 1)
    current = shown[pos].id
    area.offset = 0
    Debug("screen " .. pos .. " of " .. #shown .. ": " .. current)
    Draw()
end

---------------------------------------------------------------------------
-- Fights
---------------------------------------------------------------------------

local function OtherWindowShown()
    if type(UISpecialFrames) ~= "table" then return false end
    for _, name in ipairs(UISpecialFrames) do
        local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
        if other and other ~= panel and other.IsShown and other:IsShown() then return true end
    end
    return false
end

-- Runs once, at the end of the fight that hid the guide or kept it from
-- opening at login. The game's lockdown starts after the "fight started"
-- event, so this wait cannot be a PE:RunOutOfCombat call made from there:
-- it would run at once.
local function OnFightOver()
    PE:UnregisterCoreEvent("PLAYER_REGEN_ENABLED", "setup")
    local why = waiting
    waiting = nil
    if not why then return end
    if OtherWindowShown() then
        Debug("not reopened: another window is open")
        return
    end
    if why == "login" then
        if Setup:Seen() then return end
        Setup:Open("first login")
    else
        Setup:Open("after the fight")
    end
end

local function WaitForFightEnd(why)
    waiting = why
    PE:RegisterCoreEvent("PLAYER_REGEN_ENABLED", "setup", OnFightOver)
end

local function OnFight()
    Setup:Close("fight")
end

-- Whenever the window comes onto the screen: from Setup:Open, and when the
-- game shows its whole interface again after hiding it (cinematic,
-- full-screen view) with the guide still open. The watch for a fight starts
-- here. A fight that began while the guide was out of sight hides it now,
-- to come back at the same screen afterwards.
local function OnShown()
    if PE:InCombat() then
        Debug("back on screen in a fight")
        Setup:Close("fight")
        return
    end
    PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "setup", OnFight)
end

-- Every way the window goes away ends here: our buttons, B, Escape, another
-- of our windows, and the game closing its windows by itself (loading screen,
-- death, loss of control). Only Finish and Skip are remembered.
local function OnHidden()
    PE:UnregisterCoreEvent("PLAYER_REGEN_DISABLED", "setup")
    if panel:IsShown() then
        -- Not a closing: the game hid its whole interface and the guide went
        -- with it. It is still open and comes back by itself (OnShown).
        Debug("hidden with the game's interface, still open")
        return
    end
    local why = closeWhy
    closeWhy = nil
    if why == "finished" then
        Remember("finished")
        Debug("closed: finished")
    elseif why == "skipped" then
        Remember("skipped")
        Debug("closed: skipped")
    elseif why == "fight" then
        resumeScreen = current
        WaitForFightEnd("fight")
        Debug("closed: fight started, will come back")
    elseif why == "move" then
        resumeScreen = current
        Debug("closed: Move on screen opened, will come back")
    else
        Debug("closed: not remembered (" .. (why == "Close" and "Close" or "B, Escape or another window") .. ")")
        if Setup:Seen() == nil and not toldClosed then
            toldClosed = true
            PE:Print(TEXT_CLOSED)
        end
    end
end

---------------------------------------------------------------------------
-- Building the window (first opening only)
---------------------------------------------------------------------------

local function ReloadClicked()
    pcall(Remember, "finished")
    PE:ReloadNow()
end

local function MakeHandlers()
    handlers.touch = PE:Wrap("core", function() PE:SetPlayStyle(true) end)
    handlers.controller = PE:Wrap("core", function() PE:SetPlayStyle(false) end)
    handlers.color, handlers.size = {}, {}
    for _, choice in ipairs(COLOR_CHOICES) do
        handlers.color[choice.value] = PE:Wrap("core", function() PE:SetUISetting("hubColor", choice.value) end)
    end
    for _, choice in ipairs(SIZE_CHOICES) do
        handlers.size[choice.value] = PE:Wrap("core", function() PE:SetUISetting("size", choice.value) end)
    end
    -- Move on screen hides the guide and brings it back when it closes.
    handlers.moveNow = PE:Wrap("core", function()
        if PE.Move and PE.Move.Open then PE.Move:Open() end
    end)
end

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, TITLE, width, height)
    panel.closeButton:SetScript("OnClick", PE:Wrap("core", function() Setup:Close("Close") end))
    area = UI:CreateScrollArea(panel.content)
    list = PE:NewListDrawer({ child = area.child, navList = navList })
    local child = area.child
    local layers = { low = { "BORDER", 0 }, mid = { "BORDER", 2 }, shape = { "ARTWORK", 1 }, top = { "ARTWORK", 3 } }
    for name, layer in pairs(layers) do
        list:AddPool(name, function() return child:CreateTexture(nil, layer[1], nil, layer[2]) end)
    end
    list:AddPool("round", function()
        local f = CreateFrame("Frame", nil, child)
        f.outer = UI:CreateDisc(f, "BACKGROUND", 0)
        f.inner = UI:CreateDisc(f, "BORDER", 0)
        f.word = UI:CreateText(f, "font")
        f.word:SetJustifyH("CENTER")
        f.word:SetWordWrap(false)
        f.word:SetPoint("CENTER", f, "CENTER", 0, 0)
        return f
    end)
    MakeHandlers()

    backButton = UI:CreateButton(panel.content, "Back")
    backButton:SetScript("OnClick", PE:Wrap("core", function() Go(-1) end))
    skipButton = UI:CreateButton(panel.content, "Skip")
    skipButton:SetScript("OnClick", PE:Wrap("core", function() Setup:Close("skipped") end))
    nextButton = UI:CreateButton(panel.content, "Next")
    nextButton:SetScript("OnClick", PE:Wrap("core", function() Go(1) end))
    for k = 1, #SCREENS do
        local dot = CreateFrame("Frame", nil, panel.content)
        dot.disc = UI:CreateDisc(dot, "ARTWORK", 0)
        dot:Hide()
        dots[k] = dot
    end

    reloadButton = UI:CreateButton(area.child, "Reload now")
    reloadButton:SetStyle("warn")
    reloadButton:Hide()
    -- Called straight from the tap, in case reloading needs a real button
    -- press (PE:Safe runs it at once, inside the tap). The button is on the
    -- last screen and the reload ends the session, so Finish is stored first:
    -- otherwise the reload would bring the guide back.
    reloadButton:SetScript("OnClick", function() PE:Safe("core", ReloadClicked) end)

    UI:AttachNav(panel, function() return navList end)
    panel.peNavArea = area   -- lets the d-pad page the list when touch is off (UI.lua NavMove)
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end
    panel:HookScript("OnShow", PE:Wrap("core", OnShown))
    panel:HookScript("OnHide", PE:Wrap("core", OnHidden))

    UI:OnMetricsChanged(PE:Wrap("core", function()
        if not built then return end
        M = UI:Metrics()
        panel:SetPanelSize(PanelSize())
        QueueDraw()
    end))
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- how: "first login", "settings", "slash", "after the fight" or "after move".
function Setup:Open(how)
    how = type(how) == "string" and how or "settings"
    local resuming = how == "after the fight" or how == "after move"
    local byHand = how ~= "first login" and not resuming
    if PE:InCombat() then
        if byHand then
            Debug("not opened: in a fight")
            PE:Print(TEXT_FIGHT)
        else
            WaitForFightEnd(how == "first login" and "login" or "fight")
            Debug("waiting for the fight to end")
        end
        return false
    end
    if not built and not buildFailed then
        if PE.UI and PE:Safe("core", Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        PE:Print(TEXT_BROKEN)
        return false
    end
    -- Opened: any wait for the end of a fight is over.
    if waiting then
        waiting = nil
        PE:UnregisterCoreEvent("PLAYER_REGEN_ENABLED", "setup")
    end
    -- Never on top of another Pocket Essentials window.
    PE:CloseSettings()
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other ~= panel and other.IsShown and other:IsShown() then pcall(other.Hide, other) end
        end
    end
    current = (resuming and resumeScreen and ScreenById(resumeScreen)) and resumeScreen or SCREENS[1].id
    resumeScreen = nil
    closeWhy = nil
    focusStart = current == SCREENS[1].id
    area.offset = 0
    -- The watch for a fight starts in OnShown. Asked for by hand while the
    -- game's whole interface is hidden, the guide is out of sight and OnShown
    -- runs when the interface comes back.
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    if PE.debugOn then
        local shown = Visible()
        local pos = PositionOf(shown)
        Debug("opened (" .. how .. ")")
        Debug("screens: " .. table.concat(ScreenIds(shown), ", "))
        Debug("screen " .. pos .. " of " .. #shown .. ": " .. tostring(current))
    end
    Draw()
    return true
end

-- why: "finished", "skipped", "Close", "fight" or "move"; anything else is a
-- plain hide. The bookkeeping is in OnHidden, so B and Escape take the same path.
function Setup:Close(why)
    if built and panel:IsShown() then
        closeWhy = type(why) == "string" and why or nil
        panel:Hide()
    end
end

function Setup:IsOpen()
    return built and panel:IsShown() or false
end

-- Move on screen closed after it hid the guide: the guide comes back on the
-- screen it was showing, unless another of our windows is open now. In a
-- fight it waits for the fight to end.
function Setup:BackFromMove()
    if not built or panel:IsShown() or waiting or not resumeScreen then return end
    if OtherWindowShown() then
        resumeScreen = nil
        Debug("not reopened: another window is open")
        return
    end
    if PE:InCombat() then
        WaitForFightEnd("fight")
        Debug("waiting for the fight to end")
        return
    end
    self:Open("after move")
end

-- The screen showing: its id, its place among the shown screens, how many
-- screens are shown. For tests and the debug log.
function Setup:Screen()
    local shown = Visible()
    local pos = PositionOf(shown)
    return current, pos, #shown
end

---------------------------------------------------------------------------
-- At file load: two hooks, nothing else
---------------------------------------------------------------------------

-- Anything that changes a feature's state asks the settings window to redraw
-- (PE:RefreshSettings); the guide redraws with it when it is open.
local innerRefresh = PE.RefreshSettings
function PE:RefreshSettings()
    if innerRefresh then innerRefresh(self) end
    QueueDraw()
end

-- True when the guide should open by itself. Asked twice: when the character
-- enters the world (no timer is started when the answer is already no), and
-- again when the timer fires. The offline tests rely on the second reading
-- (tests/features/run.lua, T.new): do not drop it.
local function WantedAtLogin()
    if not SavedLoaded() then
        Debug("first login check: saved settings not loaded, guide not shown")
        return false
    end
    local seen = Setup:Seen()
    if seen then
        Debug("first login check: not needed (" .. seen .. ")")
        return false
    end
    return true
end

local function FirstLoginCheck()
    if Setup:IsOpen() or waiting then return end
    if not WantedAtLogin() then return end
    if #PE.moduleList == 0 or not PE.UI then return end
    Setup:Open("first login") -- in a fight this waits for the fight to end
end

-- After the first loading screen, not at login: the game closes every window
-- of this kind when the character enters the world, ours included.
if PE.RegisterCoreEvent then
    PE:RegisterCoreEvent("PLAYER_ENTERING_WORLD", "setup", function()
        PE:UnregisterCoreEvent("PLAYER_ENTERING_WORLD", "setup") -- the first one only
        if not WantedAtLogin() then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(FIRST_LOGIN_DELAY, PE:Wrap("core", FirstLoginCheck))
        end
    end)
end
