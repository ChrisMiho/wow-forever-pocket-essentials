-- Pocket Essentials: the settings window.
-- A standalone window made of large controls (no Blizzard settings rows):
-- tabs on the left, the chosen tab's cards on the right (spec
-- 2026-11-20-0.9.0-ui-redesign, "Settings window").
-- Built the first time it is opened; redrawn only when something changes.
local ADDON_NAME, PE = ...

local type, tostring, tonumber, ipairs, pairs, pcall = type, tostring, tonumber, ipairs, pairs, pcall
local max, min, floor = math.max, math.min, math.floor

local PANEL_NAME = "PocketEssentialsSettingsPanel"
local TITLE_MAIN = "Pocket Essentials"

local COLOR = {
    font = { 1, 1, 1 },
    small = { 0.84, 0.84, 0.84 },
    title = { 1, 0.82, 0 },
    option = { 1, 0.82, 0 },
    status = { 0.65, 0.85, 1 },
    warn = { 1, 0.60, 0.20 },
    dim = { 0.62, 0.62, 0.62 },
    name = { 0.92, 0.92, 0.92 },
}

local TEXT_SWITCH_ON_FIRST = "Switch it on to choose how it works."
local TEXT_FAILED = "Switched on, but it hit a problem. See the Errors tab."

-- The tabs, top to bottom. `features`: the helpers whose cards the tab holds,
-- in order (its dot is green while any of them is on). `heading`: the tab
-- starts with the card that says what the fixes are.
local TABS = {
    { id = "questIcons", label = "Quest icons", features = { "questIcons" } },
    { id = "questArrow", label = "Quest arrow", features = { "questArrow" } },
    { id = "bags", label = "Bags", features = { "bagWindow", "bags" } },
    { id = "vendors", label = "Vendors", features = { "sellJunk", "repair" } },
    { id = "chat", label = "Chat", features = { "chat" } },
    { id = "gameFixes", label = "Game fixes", features = { "menuBg", "sparkles" }, heading = true },
    { id = "general", label = "General" },
    { id = "errors", label = "Errors" },
}
PE.SETTINGS_TABS = TABS

local UI           -- PE.UI, set when the first list drawer is made
local M            -- current metrics
local panel, area
local list         -- this window's list drawer (see below)
local header = {}  -- fixed widgets above the scrolling page
local tabButtons = {}
local navList = {} -- tappable buttons in reading order, rebuilt on every redraw
local tab = "questIcons"  -- the chosen tab
local page = "main"       -- "main", or "key" (the Quest Icon Key, inside the Quest icons tab)
local drawnTab, drawnPage = tab, page
local built, buildFailed = false, false
local drawing, drawQueued = false, false

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

local function TabById(id)
    for _, t in ipairs(TABS) do
        if t.id == id then return t end
    end
end

local function SetText(fontString, kind, text, width, color)
    text = text == nil and "" or tostring(text)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    local c = color or COLOR[kind] or COLOR.font
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    return UI:TextHeight(fontString, kind)
end

local function ResetButton(btn)
    btn:SetSelected(false)
    btn:SetStyle("normal")
    btn:SetBadgeText(nil)
    btn:ClearAllPoints()
end

---------------------------------------------------------------------------
-- The list drawer. One per window: the settings window has one, the setup
-- guide (Setup.lua) has another. It places cards, rows, texts and controls in
-- a window's scrolling list and draws a feature's options. Because both
-- windows draw options with this code, they show the same labels, the same
-- controls and the same saved values, and a press takes the same path.
--
--   local list = PE:NewListDrawer({ child = area.child, navList = navList })
--     child:   the frame the list is drawn in (a scroll area's child).
--     navList: the window's d-pad list; every button placed is added to it.
--     refresh: optional; called after an option changed something. By
--              default PE:RefreshSettings, which redraws whichever of the
--              two windows is open.
--   list:Begin()    before a redraw (may be called again to start over)
--   ... list:Card / Row / FeatureCard / Options / Text / Divider ...
--   list:End()      after it: hides what the redraw did not use
--
-- Widgets are reused on every redraw, never thrown away. y grows downwards
-- from the top of the list. list.lowest is how far down this redraw got.
--
-- The calls (x, y: the top-left corner inside the list; w: the width):
--   list:Card(x, y, w, body)          a card; body(ix, iy, iw) draws inside it
--                                     and returns its y after the last row
--                                     (rows end one gap below themselves).
--                                     Returns the y one gap below the card.
--   list:Row(label, help, x, y, w, draw)
--                                     a row: the name (and help line) on the
--                                     left, draw(cx, cy, cw, top, bottom) puts
--                                     the control on the right. Returns the y
--                                     one gap below the row.
--   list:ChoiceRow(label, items, x, y, w, help)       items as Segmented
--   list:ActionRow(label, buttonText, onClick, x, y, w, style, help)
--   list:FeatureCard(mod, x, y, w, opts)
--                                     a feature's card: name, line, switch,
--                                     then its option rows. opts = { setup =
--                                     bool, only = { option keys }, how =
--                                     text }. Returns like Card.
--   list:Options(mod, x, y, w, opts)  only the option rows (opts as above,
--                                     plus onlyAlways). Returns the new y.
--   list:Switch(x, y, state, onClick) list:Segmented(x, y, w, items)
--   list:Number(x, y, w, box)         list:Divider(x, y, w)
--   list:Button(text, x, y, w, h, style, onClick)
--   list:Status(mod, x, y, w, failedText, skipInfo)
--                                     the status lines under a feature's name
-- The setup guide (Setup.lua) uses these same calls, plus its own pools.
---------------------------------------------------------------------------

local Drawer = {}

function Drawer:AddPool(name, create)
    self.pools[name] = { items = {}, used = 0, shown = 0, create = create }
end

function Drawer:Acquire(name)
    local pool = self.pools[name]
    pool.used = pool.used + 1
    local item = pool.items[pool.used]
    if not item then
        item = pool.create()
        pool.items[pool.used] = item
    end
    if pool.used > pool.shown then pool.shown = pool.used end
    item:Show()
    return item
end

function Drawer:Begin()
    M = UI:Metrics()
    self.lowest = 0
    for _, pool in pairs(self.pools) do pool.used = 0 end
end

function Drawer:End()
    for _, pool in pairs(self.pools) do
        for i = pool.used + 1, pool.shown do pool.items[i]:Hide() end
        pool.shown = pool.used
    end
end

function Drawer:Reach(bottom)
    if bottom > self.lowest then self.lowest = bottom end
end

-- kind: "font", "small" or "title". Returns the height of the text and the
-- text itself (the caller may move it).
function Drawer:Text(kind, text, x, y, width, color)
    local fontString = self:Acquire(kind)
    fontString:ClearAllPoints()
    fontString:SetJustifyH("LEFT") -- a reused one may have been a centred text between buttons
    fontString:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local height = SetText(fontString, kind, text, width, color)
    self:Reach(y + height)
    return height, fontString
end

-- The thin line between a card's header and its rows.
function Drawer:Divider(x, y, width)
    local line = self:Acquire("divider")
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local height = max(M.border * 0.5, 1)
    line:SetSize(max(width, 1), height)
    return height
end

local function AddStop(self, btn, top, bottom)
    btn.peScrollTop, btn.peScrollBottom = top, bottom
    self.navList[#self.navList + 1] = btn
end

-- One button at a fixed place and size.
function Drawer:Button(text, x, y, width, height, style, onClick)
    local btn = self:Acquire("button")
    ResetButton(btn)
    btn:SetLabel(text)
    btn:SetSize(width, height)
    btn:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    if style then btn:SetStyle(style) end
    btn:SetScript("OnClick", onClick)
    AddStop(self, btn, y, y + height)
    self:Reach(y + height)
    return btn
end

-- The switch (UI:CreateSwitch). state: "on", "off", "blocked", "failed".
function Drawer:Switch(x, y, state, onClick)
    local sw = self:Acquire("switch")
    sw:ClearAllPoints()
    sw:SetSwitch(state)
    sw:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    sw:SetScript("OnClick", onClick)
    AddStop(self, sw, y, y + M.button)
    self:Reach(y + M.button)
    return sw
end

-- The segmented choice (UI:CreateSegmented). items: { { label, selected,
-- onClick }, ... }. Returns the part buttons.
function Drawer:Segmented(x, y, width, items)
    local seg = self:Acquire("segmented")
    seg:ClearAllPoints()
    seg:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local parts = seg:Set(width, items)
    for _, part in ipairs(parts) do AddStop(self, part, y, y + M.button) end
    self:Reach(y + M.button)
    return parts
end

-- The number control (UI:CreateNumber). box: { text, unit, down, up,
-- downDim, upDim }; a missing step is a dim end whose press only redraws.
function Drawer:Number(x, y, width, box)
    local num = self:Acquire("number")
    num:ClearAllPoints()
    num:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local shown = {}
    for k, v in pairs(box) do shown[k] = v end
    shown.noStep = self.noStep
    local minus, plus = num:Set(width, shown)
    AddStop(self, minus, y, y + M.button)
    AddStop(self, plus, y, y + M.button)
    self:Reach(y + M.button)
    return minus, plus
end

-- A card: the card fill from x to x + width, with pad inside on every side.
-- body(ix, iy, iw) returns its y after the last row. Returns the y one gap
-- below the card.
function Drawer:Card(x, y, width, body)
    local fill = self:Acquire("card")
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local inner = max(width - 2 * M.pad, 1)
    local bottom = body(x + M.pad, y + M.pad, inner)
    if type(bottom) ~= "number" then bottom = max(self.lowest, y + M.pad) + M.gap end
    local height = max(bottom - y + M.pad - M.gap, 1)
    fill:SetSize(max(width, 1), height)
    self:Reach(y + height)
    return y + height + M.gap
end

-- A row: the name on the left (with an optional help line under it), the
-- control on the right, both centred on the row. draw(cx, cy, cw, top,
-- bottom) places the control (may be nil). Returns the y one gap below.
function Drawer:Row(label, help, x, y, innerWidth, draw)
    local cw = UI:ControlWidth(innerWidth)
    local lw = max(innerWidth - cw - M.gap, 10)
    local nameHeight, name = self:Text("font", label or "", x, y, lw, COLOR.name)
    local helpHeight, helpText = 0, nil
    if type(help) == "string" and help ~= "" then
        helpHeight, helpText = self:Text("small", help, x, y, lw, COLOR.dim)
        helpHeight = helpHeight + M.gap * 0.15
    end
    local textHeight = nameHeight + helpHeight
    local height = max(M.button, textHeight)
    local top = y + (height - textHeight) * 0.5
    name:ClearAllPoints()
    name:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -top)
    if helpText then
        helpText:ClearAllPoints()
        helpText:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -(top + nameHeight + M.gap * 0.15))
    end
    self:Reach(y + height)
    if draw then
        local mark = #self.navList
        draw(x + innerWidth - cw, y + (height - M.button) * 0.5, cw)
        -- When the controller lands on the control, bring the whole row into view.
        for i = mark + 1, #self.navList do
            local btn = self.navList[i]
            btn.peScrollTop, btn.peScrollBottom = y, y + height
        end
    end
    return y + height + M.gap
end

function Drawer:ChoiceRow(label, items, x, y, innerWidth, help)
    return self:Row(label, help, x, y, innerWidth, function(cx, cy, cw)
        self:Segmented(cx, cy, cw, items)
    end)
end

function Drawer:ActionRow(label, buttonText, onClick, x, y, innerWidth, style, help)
    return self:Row(label, help, x, y, innerWidth, function(cx, cy, cw)
        self:Button(buttonText or "Open", cx, cy, cw, M.button, style or "normal", onClick)
    end)
end

-- The saved value a choices row shows: its `get`, or mod.opts[key].
local function CurrentChoice(mod, opt)
    if type(opt.get) == "function" then
        local ok, value = PE:Safe(mod.key, opt.get, mod)
        if ok then return value end
        return nil
    end
    if type(mod.opts) ~= "table" then return nil end
    return mod.opts[opt.key] -- may be false: not "and ... or nil"
end

-- A choices row can be drawn: a list of choices and where to save them.
local function IsChoiceRow(opt)
    return type(opt.choices) == "table"
        and (opt.key ~= nil or (type(opt.get) == "function" and type(opt.set) == "function"))
end

local function IsNumberRow(opt)
    local n = opt.number
    return opt.key ~= nil and type(n) == "table" and type(n.min) == "number" and type(n.max) == "number"
        and n.min <= n.max
end

-- The value a number row shows: the saved one when it is a whole number in
-- the range (or the `all` value), else the row's default.
local function NumberCurrent(mod, opt)
    local n = opt.number
    local v = type(mod.opts) == "table" and mod.opts[opt.key] or nil
    if n.all ~= nil and n.all ~= false and v == n.all then return v end
    if type(v) == "number" and v == floor(v) and v >= n.min and v <= n.max then return v end
    local d = n.default
    if type(d) == "number" and d >= n.min and d <= n.max then return d end
    return n.min
end

-- The values one step down and one step up from v (nil: no step that way).
-- The step is n.step (1 when not given). After max comes `all`, when the row
-- has one.
local function NumberSteps(n, v)
    local step = (type(n.step) == "number" and n.step > 0) and n.step or 1
    local hasAll = n.all ~= nil and n.all ~= false
    if hasAll and v == n.all then return n.max, nil end
    local down = v > n.min and max(v - step, n.min) or nil
    local up = (v < n.max and min(v + step, n.max)) or (hasAll and n.all) or nil
    return down, up
end

local function NumberText(n, v)
    if n.all ~= nil and n.all ~= false and v == n.all then return n.allLabel or "All" end
    if v == 0 and n.offLabel then return n.offLabel end
    return tostring(v) .. (n.suffix or "")
end

-- The tap on a choice: save it (through `set`, or as mod.opts[key]), run
-- OnChange, redraw.
local function ChooseHandler(mod, opt, value, refresh)
    return PE:Wrap("core", function()
        if type(mod.opts) ~= "table" then return end
        if type(opt.set) == "function" then
            if not PE:Safe(mod.key, opt.set, mod, value) then
                refresh()
                return
            end
        else
            mod.opts[opt.key] = value
        end
        if type(opt.OnChange) == "function" then PE:Safe(mod.key, opt.OnChange, mod, value) end
        refresh()
    end)
end

-- The name of a row, with the text of its `value` after it when it has one
-- ("Chat text size: 20 (after the fight)").
local function RowName(mod, opt)
    local text = type(opt.label) == "string" and opt.label or ""
    if type(opt.value) == "function" then
        local ok, shown = pcall(opt.value, mod)
        if ok and shown ~= nil then text = (text ~= "" and (text .. ": ") or "") .. tostring(shown) end
    end
    return text
end

-- Option rows: the list `options` of a feature, drawn in its card while the
-- feature is on. A row with `always = true` is also drawn while the feature
-- is not on (it must not need the feature). Rows show in list order. Each row
-- is a table of one of these kinds; any of them may have help = "text", a
-- grey line under the row name:
--   choices: { key, label, choices = { { value, label }, ... }, OnChange }
--            a segmented choice; the tapped part is saved as mod.opts[key].
--            Instead of key, a row may have get = function(mod) -> value and
--            set = function(mod, value), when one choice stands for more
--            than one saved value. `toggle` (from older versions) changes
--            nothing in how it is drawn.
--   action:  { label, button = "text", action = function(mod), page }
--            a button reading `button` ("Open" when missing) that runs the
--            action. `page`: the action opens another settings page, so the
--            setup guide leaves the row out.
--   buttons: { label, value = function(mod) -> text, buttons = { { label,
--            action = function(mod) }, ... } }
--            the label with the value text after it ("label: text"), then
--            the buttons side by side in the control's place. `buttons` may
--            also be a function(mod) that returns that list. An entry
--            { text = } is a short text at that place instead of a button; a
--            button entry with style = "disabled" is drawn dim (it can still
--            be pressed). Each tap runs its action, then the window redraws.
--   number:  { key, label, number = { min, max, step, default, unit, suffix,
--            all, allLabel, offLabel }, OnChange }
--            the number control "- value +"; each end saves mod.opts[key]
--            one step (default 1) down or up. `all` (optional) is the value
--            after max, shown as allLabel ("All"); offLabel (optional) is
--            shown at 0. A saved value that is not a whole number in the
--            range shows the default. An end with no step is dimmed.
--   stepper: { label, value = function(mod) -> text, stepper =
--            function(mod) -> { text, unit, down = fn, up = fn, downDim,
--            upDim } or nil }
--            the same control for a value the feature keeps itself; a
--            missing down or up, or downDim / upDim = true, is a dimmed end
--            (a dimmed end with a function still runs it). nil draws the
--            row name only.
-- Returns the new y (one gap below the last row).
function Drawer:OptionRow(mod, opt, x, y, innerWidth)
    local refresh = self.refresh
    local help = type(opt.help) == "string" and opt.help or nil
    if IsChoiceRow(opt) then
        local current = CurrentChoice(mod, opt)
        local items = {}
        for _, choice in ipairs(opt.choices) do
            if type(choice) == "table" then
                local value = choice.value
                items[#items + 1] = {
                    label = tostring(choice.label ~= nil and choice.label or value),
                    selected = (current == value),
                    onClick = ChooseHandler(mod, opt, value, refresh),
                }
            end
        end
        return self:ChoiceRow(RowName(mod, opt), items, x, y, innerWidth, help)
    elseif IsNumberRow(opt) then
        local n = opt.number
        local current = NumberCurrent(mod, opt)
        local down, up = NumberSteps(n, current)
        local box = {
            text = NumberText(n, current),
            unit = n.unit,
            down = down ~= nil and ChooseHandler(mod, opt, down, refresh) or nil,
            up = up ~= nil and ChooseHandler(mod, opt, up, refresh) or nil,
        }
        return self:Row(RowName(mod, opt), help, x, y, innerWidth, function(cx, cy, cw)
            self:Number(cx, cy, cw, box)
        end)
    elseif type(opt.stepper) == "function" then
        local ok, got = pcall(opt.stepper, mod)
        local draw
        if ok and type(got) == "table" then
            local function Step(fn)
                if type(fn) ~= "function" then return nil end
                return PE:Wrap("core", function()
                    PE:Safe(mod.key, fn, mod)
                    refresh()
                end)
            end
            local box = { text = got.text, unit = got.unit, down = Step(got.down), up = Step(got.up),
                downDim = got.downDim == true, upDim = got.upDim == true }
            draw = function(cx, cy, cw) self:Number(cx, cy, cw, box) end
        end
        return self:Row(RowName(mod, opt), help, x, y, innerWidth, draw)
    elseif type(opt.action) == "function" then
        local label = (type(opt.label) == "string" and opt.label ~= "") and opt.label or ""
        local text = (type(opt.button) == "string" and opt.button ~= "") and opt.button or "Open"
        return self:ActionRow(label, text, PE:Wrap("core", function()
            PE:Safe(mod.key, opt.action, mod)
            refresh()
        end), x, y, innerWidth, "normal", help)
    elseif type(opt.buttons) == "table" or type(opt.buttons) == "function" then
        local buttons = opt.buttons
        if type(buttons) == "function" then
            local ok, got = pcall(buttons, mod)
            buttons = ok and got or nil
        end
        local items = {}
        for _, b in ipairs(type(buttons) == "table" and buttons or {}) do
            if type(b) == "table" and b.text ~= nil and b.action == nil then
                items[#items + 1] = { text = tostring(b.text) }
            elseif type(b) == "table" and type(b.action) == "function" then
                items[#items + 1] = {
                    label = tostring(b.label ~= nil and b.label or "Do it"),
                    style = b.style == "disabled" and "disabled" or "normal",
                    onClick = PE:Wrap("core", function()
                        PE:Safe(mod.key, b.action, mod)
                        refresh()
                    end),
                }
            end
        end
        local draw
        if #items > 0 then
            draw = function(cx, cy, cw)
                local each = (cw - (#items - 1) * M.gap) / #items
                for i, item in ipairs(items) do
                    local bx = cx + (i - 1) * (each + M.gap)
                    if item.text then
                        local height, fontString = self:Text("font", item.text, bx, cy, each)
                        fontString:SetJustifyH("CENTER")
                        fontString:ClearAllPoints()
                        fontString:SetPoint("TOPLEFT", self.child, "TOPLEFT", bx, -(cy + max((M.button - height) * 0.5, 0)))
                    else
                        self:Button(item.label, bx, cy, each, M.button, item.style, item.onClick)
                    end
                end
            end
        end
        return self:Row(RowName(mod, opt), help, x, y, innerWidth, draw)
    end
    return y
end

-- The rows of a feature to draw. opts: { only = { keys }, setup = bool,
-- onlyAlways = bool }. A row without a key is picked in `only` by its label. Without onlyAlways, it follows the feature's state:
-- all rows while it is on, only `always` rows while it is not.
function Drawer:OptionList(mod, opts)
    opts = opts or {}
    local onlyAlways = opts.onlyAlways
    if onlyAlways == nil then onlyAlways = PE:GetModuleState(mod.key) ~= "on" end
    local only
    if type(opts.only) == "table" then
        only = {}
        for _, k in ipairs(opts.only) do only[k] = true end
    end
    local rows = {}
    for _, opt in ipairs(type(mod.options) == "table" and mod.options or {}) do
        if type(opt) == "table"
            and (not onlyAlways or opt.always == true)
            and (not only or (opt.key ~= nil and only[opt.key]) or (opt.key == nil and opt.label ~= nil and only[opt.label]))
            and not (opts.setup and opt.page ~= nil) then
            rows[#rows + 1] = opt
        end
    end
    return rows
end

-- The option rows of a feature, innerWidth being the inner width of the
-- card. Returns the new y.
function Drawer:Options(mod, x, y, innerWidth, opts)
    for _, opt in ipairs(self:OptionList(mod, opts)) do
        local ok, nextY = PE:Safe(mod.key, self.OptionRow, self, mod, opt, x, y, innerWidth)
        if ok and type(nextY) == "number" then
            y = nextY
        else
            y = max(y, self.lowest) + M.gap
        end
    end
    return y
end

-- Features whose blue status lines stay out of their card (spec: Bag
-- sorting). Lines that say it is blocked or failed still show.
local NO_STATUS_LINES = { bags = true }

-- The lines under a feature's name that say how it is doing: its own status
-- text (blue), why it cannot be switched on, or that it hit a problem
-- (amber). failedText: the sentence for the last case. Returns the new y.
function Drawer:Status(mod, x, y, width, failedText, skipInfo)
    local key = mod.key
    local state, detail = PE:GetModuleState(key)
    if type(mod.status) == "function" and not skipInfo then
        local ok, status = PE:Safe(key, mod.status, mod)
        if ok then
            if type(status) == "table" then
                local lines = {}
                for i = 1, #status do lines[i] = tostring(status[i]) end
                status = table.concat(lines, "\n")
            end
            if type(status) == "string" and status ~= "" then
                y = y + M.gap * 0.3
                y = y + self:Text("small", status, x, y, width, COLOR.status)
            end
        end
    end
    if state == "blocked" then
        y = y + M.gap * 0.3
        y = y + self:Text("small", detail or "This cannot be switched on right now.", x, y, width, COLOR.warn)
    elseif state == "failed" then
        y = y + M.gap * 0.3
        y = y + self:Text("small", failedText, x, y, width, COLOR.warn)
    end
    return y
end

local SWITCH_STATE = { on = "on", off = "off", blocked = "blocked", failed = "failed" }

-- A feature's card: its name, its one-line description (and in the setup
-- guide a "How:" line), any blocked or failed line, the switch on the right;
-- then, while it is on, a divider and its option rows (rows marked `always`
-- show while it is off too). opts = { setup = bool, only = { keys }, how =
-- text, failedText = text }. Returns the y one gap below the card.
function Drawer:FeatureCard(mod, x, y, width, opts)
    opts = opts or {}
    local key = mod.key
    local refresh = self.refresh
    return self:Card(x, y, width, function(ix, iy, iw)
        local sw = M.button * 2
        local tw = max(iw - sw - M.gap, 10)
        local ty = iy
        local title = Escape(mod.label or key)
        if mod.experimental then title = title .. "   |cffff9a33Experimental|r" end
        ty = ty + self:Text("font", title, ix, ty, tw, COLOR.font) + M.gap * 0.2
        if type(mod.desc) == "string" and mod.desc ~= "" then
            ty = ty + self:Text("small", mod.desc, ix, ty, tw, COLOR.small)
        end
        if opts.setup and type(opts.how) == "string" and opts.how ~= "" then
            ty = ty + M.gap * 0.3
            ty = ty + self:Text("small", "|cffffd100How: |r" .. opts.how, ix, ty, tw, COLOR.small)
        end
        local state = PE:GetModuleState(key)
        -- A feature marked statusWhenOff keeps its line while off (Loot
        -- sparkles: the restart line).
        ty = self:Status(mod, ix, ty, tw, opts.failedText or TEXT_FAILED,
            NO_STATUS_LINES[key] or (state ~= "on" and not mod.statusWhenOff))
        local headerHeight = max(M.button, ty - iy)
        local switch = self:Switch(ix + iw - sw, iy + (headerHeight - M.button) * 0.5, SWITCH_STATE[state] or "off",
            PE:Wrap("core", function()
                if PE:GetModuleState(key) == "blocked" then return end
                PE:SetModuleEnabled(key, not PE:IsModuleSavedOn(key))
                refresh()
            end))
        switch.peKey = key
        -- When the controller lands on the switch, bring the whole header into view.
        switch.peScrollTop, switch.peScrollBottom = iy, iy + headerHeight
        local y2 = iy + headerHeight + M.gap
        local rows = self:OptionList(mod, opts)
        local hasOptions = type(mod.options) == "table" and #mod.options > 0
        if #rows > 0 then
            self:Divider(ix, y2 - M.gap * 0.5, iw)
            y2 = y2 + M.gap * 0.5
            y2 = self:Options(mod, ix, y2, iw, opts)
        elseif hasOptions and state ~= "on" and not opts.setup then
            y2 = y2 + self:Text("small", TEXT_SWITCH_ON_FIRST, ix, y2, iw, COLOR.dim) + M.gap
        end
        return y2
    end)
end

local function DefaultRefresh()
    PE:RefreshSettings()
end

-- Makes no frame by itself: widgets are made as a redraw first needs them.
function PE:NewListDrawer(spec)
    UI = PE.UI
    local child = spec.child
    local drawer = {
        child = child,
        navList = spec.navList,
        refresh = type(spec.refresh) == "function" and spec.refresh or DefaultRefresh,
        pools = {},
        lowest = 0,
    }
    for name, fn in pairs(Drawer) do drawer[name] = fn end
    -- A dimmed end of a number control: saves nothing, only redraws.
    drawer.noStep = PE:Wrap("core", function() drawer.refresh() end)
    drawer:AddPool("button", function() return UI:CreateButton(child, "") end)
    drawer:AddPool("switch", function() return UI:CreateSwitch(child) end)
    drawer:AddPool("segmented", function() return UI:CreateSegmented(child) end)
    drawer:AddPool("number", function() return UI:CreateNumber(child) end)
    drawer:AddPool("font", function() return UI:CreateText(child, "font") end)
    drawer:AddPool("small", function() return UI:CreateText(child, "small") end)
    drawer:AddPool("title", function() return UI:CreateText(child, "title") end)
    drawer:AddPool("card", function()
        local fill = child:CreateTexture(nil, "BACKGROUND")
        local c = UI.COLORS.card
        fill:SetColorTexture(c[1], c[2], c[3], 1)
        return fill
    end)
    drawer:AddPool("divider", function()
        local line = child:CreateTexture(nil, "ARTWORK")
        local c = UI.COLORS.divider
        line:SetColorTexture(c[1], c[2], c[3], 1)
        return line
    end)
    drawer:AddPool("icon", function() return child:CreateTexture(nil, "ARTWORK") end)
    return drawer
end

---------------------------------------------------------------------------
-- Feature tabs
---------------------------------------------------------------------------

local function BuildFeatureTab(t, width)
    local y = 0
    if t.heading then
        y = list:Card(0, y, width, function(ix, iy, iw)
            local yy = iy
            yy = yy + list:Text("font", "Fixes for the game's own interface", ix, yy, iw, COLOR.title) + M.gap * 0.2
            yy = yy + list:Text("small", "Parts of the default Blizzard UI that are hard to use on a handheld, "
                .. "or that low graphics hide.", ix, yy, iw, COLOR.small)
            return yy + M.gap
        end) + M.gap
    end
    local drawn = 0
    for _, key in ipairs(t.features or {}) do
        local mod = PE:GetModule(key)
        if mod then
            drawn = drawn + 1
            -- Each card on its own: one that fails is logged against its
            -- feature and the rest of the page is still drawn below it.
            local ok, nextY = PE:Safe(key, list.FeatureCard, list, mod, 0, y, width)
            if ok and type(nextY) == "number" then
                y = nextY + M.gap
            else
                y = max(y, list.lowest) + M.gap
            end
        end
    end
    if drawn == 0 then
        y = y + list:Text("font", "This part of the addon did not load. See the Errors tab.", 0, y, width) + M.gap
    end
    return y
end

---------------------------------------------------------------------------
-- General tab
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

-- "I play with": saves ui.touch, and moves Bag sorting's Sort button with it
-- (a controller player sorts with the stick click; a touch player taps the
-- button). Applied the way Bag sorting's own choice applies it.
function PE:SetPlayStyle(touch)
    touch = touch and true or false
    self:SetUISetting("touch", touch)
    local bags = self:GetModule("bags")
    local opts = bags and (bags.opts or (self.db and self.db.options and self.db.options.bags))
    if type(opts) ~= "table" then return end
    if (opts.showTab ~= false) == touch then return end
    opts.showTab = touch
    for _, opt in ipairs(type(bags.options) == "table" and bags.options or {}) do
        if type(opt) == "table" and opt.key == "showTab" and type(opt.OnChange) == "function" then
            self:Safe("bags", opt.OnChange, bags, touch)
        end
    end
    self:RefreshSettings()
end

local function Items(choices, current, pick)
    local items = {}
    for i, choice in ipairs(choices) do
        local value = choice.value
        items[i] = {
            label = choice.label,
            selected = (current == value),
            onClick = PE:Wrap("core", function() pick(value) end),
        }
    end
    return items
end

local function BuildGeneral(width)
    local ui = PE.db and PE.db.ui or {}
    local y = 0
    y = list:Card(0, y, width, function(ix, iy, iw)
        local yy = iy
        yy = list:ChoiceRow("Button size", Items(SIZE_CHOICES, M.size,
            function(v) PE:SetUISetting("size", v) end), ix, yy, iw)
        yy = list:ChoiceRow("Round button colour", Items(COLOR_CHOICES, ui.hubColor or "gold",
            function(v) PE:SetUISetting("hubColor", v) end), ix, yy, iw)
        yy = list:ChoiceRow("I play with", Items({
            { value = true, label = "Touch controls" },
            { value = false, label = "Controller" },
        }, PE:UsesTouch(), function(v) PE:SetPlayStyle(v) end), ix, yy, iw)
        return yy
    end) + M.gap
    y = list:Card(0, y, width, function(ix, iy, iw)
        local yy = iy
        if PE.Move and PE.Move.Open then
            yy = list:ActionRow("Move things on screen", "Open",
                PE:Wrap("core", function() PE.Move:Open() end), ix, yy, iw)
        end
        if PE.Setup and PE.Setup.Open then
            yy = list:ActionRow("Setup guide", "Open",
                PE:Wrap("core", function() PE.Setup:Open("settings") end), ix, yy, iw)
        end
        -- Called straight from the tap, in case reloading needs a real button press.
        yy = list:ActionRow("Reload the interface", "Reload", function() PE:ReloadNow() end, ix, yy, iw)
        return yy
    end) + M.gap
    return y
end

---------------------------------------------------------------------------
-- Errors tab
---------------------------------------------------------------------------

-- 12345 -> "12,345"
local function WithCommas(n)
    local text = tostring(floor(tonumber(n) or 0))
    local done
    repeat
        text, done = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until done == 0
    return text
end

-- The debug log's card: switch, line count and its two rows. The count is
-- read when the page is drawn (on opening, and after the switch or a
-- button), never per logged line.
local function DebugCard(y, width)
    return list:Card(0, y, width, function(ix, iy, iw)
        local sw = M.button * 2
        local tw = max(iw - sw - M.gap, 10)
        local on = PE.debugOn == true
        local ty = iy
        ty = ty + list:Text("font", "Debug log", ix, ty, tw, COLOR.font) + M.gap * 0.2
        ty = ty + list:Text("small", "Turn it on, play until the problem happens, then tap Save. "
            .. "Send the file SavedVariables/PocketEssentials.lua.", ix, ty, tw, COLOR.small)
        ty = ty + M.gap * 0.3
        ty = ty + list:Text("small", WithCommas(PE:DebugCount()) .. " of " .. WithCommas(PE.DEBUG_CAP) .. " lines",
            ix, ty, tw, COLOR.status) + M.gap * 0.3
        list:Switch(ix + iw - sw, iy, on and "on" or "off", PE:Wrap("core", function() PE:SetDebug(not PE.debugOn) end))
        local yy = max(iy + M.button, ty) + M.gap
        list:Divider(ix, yy - M.gap * 0.5, iw)
        yy = yy + M.gap * 0.5
        -- A reload is what writes the file. Called straight from the tap, in
        -- case reloading needs a real button press.
        yy = list:ActionRow("Save the log (reloads)", "Save", function() PE:ReloadNow() end, ix, yy, iw)
        yy = list:ActionRow("Empty the log", "Empty", PE:Wrap("core", function() PE:ClearDebug() end), ix, yy, iw)
        return yy
    end)
end

local function ErrorsCard(y, width)
    return list:Card(0, y, width, function(ix, iy, iw)
        local errors = PE.errors
        local cw = UI:ControlWidth(iw)
        local yy = iy
        local h, label = list:Text("font", "Errors", ix, yy, iw - cw - M.gap, COLOR.font)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", list.child, "TOPLEFT", ix, -(yy + max((M.button - h) * 0.5, 0)))
        list:Button("Clear errors", ix + iw - cw, yy, cw, M.button, #errors > 0 and "normal" or "disabled",
            PE:Wrap("core", function() PE:ClearErrors() end))
        yy = yy + M.button + M.gap
        if #errors == 0 then
            return yy + list:Text("small", "No errors recorded.", ix, yy, iw, COLOR.dim) + M.gap
        end
        for i = 1, #errors do
            local e = errors[i]
            if type(e) == "table" then
                local head = Escape(PE:ModuleLabel(e.module)) .. "   x" .. tostring(tonumber(e.count) or 1)
                if type(e.last) == "number" and e.last > 0 then
                    local ok, when = pcall(date, "%b %d %H:%M", e.last)
                    if ok and type(when) == "string" then head = head .. "   last: " .. when end
                end
                yy = yy + list:Text("font", head, ix, yy, iw, COLOR.title) + M.gap * 0.3
                yy = yy + list:Text("small", Escape(e.msg), ix, yy, iw, COLOR.font) + M.gap * 0.3
                if type(e.stack) == "string" and e.stack ~= "" then
                    yy = yy + list:Text("small", Escape(e.stack), ix, yy, iw, COLOR.dim)
                end
                yy = yy + M.gap
            end
        end
        return yy
    end)
end

local function BuildErrors(width)
    local y = 0
    -- On its own, so a problem drawing it still leaves the error list below.
    local ok, nextY = PE:Safe("core", DebugCard, y, width)
    y = (ok and type(nextY) == "number") and (nextY + M.gap) or (max(y, list.lowest) + M.gap)
    return ErrorsCard(y, width) + M.gap
end

---------------------------------------------------------------------------
-- Quest Icon Key page (inside the Quest icons tab)
---------------------------------------------------------------------------

local function BuildKey(width)
    list:Button("Back", 0, 0, M.button * 3, M.button, "normal", PE:Wrap("core", function() PE:OpenSettings("questIcons") end))
    local y = M.button + M.gap
    local key = PE.QuestIconKey -- made when QuestIcons.lua loads, so read it here
    if type(key) ~= "table" or #key == 0 then
        return y + list:Text("font", "The quest icons part of this addon did not load. See the Errors tab.", 0, y, width) + M.gap
    end
    return list:Card(0, y, width, function(ix, iy, iw)
        local side = M.button
        local tx = ix + side + M.gap
        local tw = max(iw - side - M.gap, 10)
        local yy = iy
        for i = 1, #key do
            local entry = key[i]
            if type(entry) == "table" then
                -- A reused texture gets its picture, colour and size set again every time.
                local icon = list:Acquire("icon")
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", list.child, "TOPLEFT", ix, -yy)
                icon:SetSize(side, side)
                icon:SetTexture(entry.tex)
                local c = type(entry.color) == "table" and entry.color or COLOR.font
                icon:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1)
                local nameHeight, name = list:Text("font", Escape(entry.label or ""), tx, yy, tw, COLOR.font)
                local descHeight, desc = list:Text("small", Escape(entry.desc or ""), tx, yy, tw, COLOR.small)
                local top = yy + max((side - nameHeight - descHeight) * 0.5, 0)
                name:ClearAllPoints()
                name:SetPoint("TOPLEFT", list.child, "TOPLEFT", tx, -top)
                desc:ClearAllPoints()
                desc:SetPoint("TOPLEFT", list.child, "TOPLEFT", tx, -(top + nameHeight))
                local rowHeight = max(side, nameHeight + descHeight)
                list:Reach(yy + rowHeight)
                yy = yy + rowHeight + M.gap
            end
        end
        return yy + list:Text("small", "Tap an icon on the map to see what it is for.", ix, yy, iw, COLOR.dim) + M.gap
    end) + M.gap
end

---------------------------------------------------------------------------
-- Fixed header above the page
---------------------------------------------------------------------------

local function LayoutHeader(x, width)
    local y = 0
    local content = panel.content

    if PE.oldQuestDotsLoaded then
        header.warn:ClearAllPoints()
        header.warn:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
        y = y + SetText(header.warn, "small", "The old QuestDots folder is still installed. Delete it from AddOns.", width, COLOR.warn) + M.gap
        header.warn:Show()
    else
        header.warn:Hide()
    end

    local reasons = PE.reloadReasons
    if type(reasons) == "table" and #reasons > 0 then
        local buttonWidth = M.button * 4.5
        local lines = {}
        for i = 1, min(#reasons, 2) do
            lines[i] = Escape(reasons[i].label) .. ": " .. Escape(reasons[i].reason)
        end
        header.reloadButton:ClearAllPoints()
        header.reloadButton:SetSize(buttonWidth, M.button)
        header.reloadButton:SetPoint("TOPLEFT", content, "TOPLEFT", x + width - buttonWidth, -y)
        header.reloadButton:Show()
        header.reloadText:ClearAllPoints()
        header.reloadText:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
        local textHeight = SetText(header.reloadText, "small", table.concat(lines, "\n"), width - buttonWidth - M.gap, COLOR.warn)
        header.reloadText:Show()
        y = y + max(M.button, textHeight) + M.gap
        navList[#navList + 1] = header.reloadButton
    else
        header.reloadButton:Hide()
        header.reloadText:Hide()
    end
    return y
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- Any helper of the tab is on.
local function TabIsOn(t)
    for _, key in ipairs(t.features or {}) do
        if PE:IsModuleEnabled(key) then return true end
    end
    return false
end

-- The tab height: one button, or less so that all the tabs fit the window.
local function TabHeight(contentHeight)
    local n = #TABS
    return min(M.button, (contentHeight - (n - 1) * M.border) / n)
end

local function LayoutTabs(contentHeight, tabsWidth)
    local th = TabHeight(contentHeight)
    local b = M.border
    local colors = UI.COLORS
    for i, t in ipairs(TABS) do
        local btn = tabButtons[i]
        local chosen = t.id == tab
        btn:ClearAllPoints()
        btn:SetSize(tabsWidth, th)
        btn:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(i - 1) * (th + b))
        btn:SetStyle(chosen and "tabOn" or "tabItem")
        btn.peText:ClearAllPoints()
        btn.peText:SetPoint("LEFT", btn, "LEFT", M.pad, 0)
        btn.peText:SetWidth(max(tabsWidth - M.pad * 3, 10))
        btn.peBar:ClearAllPoints()
        btn.peBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn.peBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn.peBar:SetWidth(max(UI:Px(4), b * 2))
        btn.peBar:SetShown(chosen)
        -- The dot: green while any helper of the tab is on.
        local hasDot = t.features ~= nil
        if hasDot then
            local d = M.smallFontSize * 0.55
            local on = TabIsOn(t)
            local c = on and colors.dotOn or colors.dotOff
            btn.peDotAnchor:ClearAllPoints()
            btn.peDotAnchor:SetSize(d, d)
            btn.peDotAnchor:SetPoint("RIGHT", btn, "RIGHT", -M.pad, 0)
            btn.peDot:SetColor(c[1], c[2], c[3], 1)
            btn.peDot:Layout(btn.peDotAnchor, d)
            btn.peDotOn = on
        end
        btn.peDot:SetShown(hasDot)
        -- The Errors tab's red badge with the count: a round dot, or a pill
        -- (two round ends and a bar between them) when the count is wider.
        local count = (t.id == "errors") and #PE.errors or 0
        if count > 0 then
            local d = M.smallFontSize * 1.3
            btn.peCount:SetText(tostring(count))
            local ok, textWidth = pcall(btn.peCount.GetUnboundedStringWidth, btn.peCount)
            if not ok or type(textWidth) ~= "number" or textWidth <= 0 then
                textWidth = #tostring(count) * M.smallFontSize * 0.55
            end
            local w = max(d, textWidth + M.smallFontSize * 0.6)
            btn.peDotAnchor:ClearAllPoints()
            btn.peDotAnchor:SetSize(w, d)
            btn.peDotAnchor:SetPoint("RIGHT", btn, "RIGHT", -M.pad, 0)
            local c = colors.badge
            btn.peBadgeLeft:ClearAllPoints()
            btn.peBadgeLeft:SetSize(d, d)
            btn.peBadgeLeft:SetPoint("LEFT", btn.peDotAnchor, "LEFT", 0, 0)
            btn.peBadgeRight:ClearAllPoints()
            btn.peBadgeRight:SetSize(d, d)
            btn.peBadgeRight:SetPoint("RIGHT", btn.peDotAnchor, "RIGHT", 0, 0)
            btn.peBadgeDisc:SetColor(c[1], c[2], c[3], 1)
            btn.peBadgeDisc:Layout(btn.peBadgeLeft, d)
            btn.peBadgeDisc:SetShown(true)
            local pill = w > d + 0.01
            btn.peBadgeEnd:SetColor(c[1], c[2], c[3], 1)
            btn.peBadgeEnd:Layout(btn.peBadgeRight, d)
            btn.peBadgeEnd:SetShown(pill)
            btn.peBadgeMid:ClearAllPoints()
            btn.peBadgeMid:SetPoint("TOPLEFT", btn.peDotAnchor, "TOPLEFT", d * 0.5, 0)
            btn.peBadgeMid:SetPoint("BOTTOMRIGHT", btn.peDotAnchor, "BOTTOMRIGHT", -d * 0.5, 0)
            btn.peBadgeMid:SetColorTexture(c[1], c[2], c[3], 1)
            btn.peBadgeMid:SetShown(pill)
            btn.peCount:ClearAllPoints()
            btn.peCount:SetPoint("CENTER", btn.peDotAnchor, "CENTER", 0, 0)
            btn.peCount:Show()
        else
            btn.peBadgeDisc:SetShown(false)
            btn.peBadgeEnd:SetShown(false)
            btn.peBadgeMid:Hide()
            btn.peCount:Hide()
        end
        navList[#navList + 1] = btn
    end
end

---------------------------------------------------------------------------
-- Controller: the tabs are one column, the page another
---------------------------------------------------------------------------

local function IsTab(btn)
    return btn ~= nil and btn.peTabId ~= nil
end

local function ChosenTabButton()
    for i, t in ipairs(TABS) do
        if t.id == tab then return tabButtons[i] end
    end
end

-- The page's stops: everything in the d-pad list that is not a tab.
local function PageColumn()
    local out = {}
    for _, btn in ipairs(navList) do
        if not IsTab(btn) then out[#out + 1] = btn end
    end
    return out
end

local function NavColumn(focus)
    if IsTab(focus) then
        local out = {}
        for i = 1, #tabButtons do out[i] = tabButtons[i] end
        return out
    end
    return PageColumn()
end

-- Right from a tab goes to the page's first stop; Left from the first stop
-- of a page row goes to the chosen tab. Before anything is highlighted the
-- first press lands on the chosen tab.
local function NavCross(focus, step, byRow)
    if focus == nil then return ChosenTabButton() end
    if byRow then return nil end
    if IsTab(focus) then
        if step > 0 then
            for _, btn in ipairs(navList) do
                if not IsTab(btn) and btn.peScrollTop then return btn end
            end
            return PageColumn()[1]
        end
        return focus
    end
    if step < 0 then
        local column = PageColumn()
        for i, btn in ipairs(column) do
            if btn == focus then
                if i == 1 or not UI:NavSameRow(column[i - 1], focus) then return ChosenTabButton() end
                return nil
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Redraw
---------------------------------------------------------------------------

local function BuildPage(width)
    if tab == "questIcons" and page == "key" then return BuildKey(width) end
    if tab == "general" then return BuildGeneral(width) end
    if tab == "errors" then return BuildErrors(width) end
    return BuildFeatureTab(TabById(tab) or TABS[1], width)
end

local function DoRefresh()
    M = UI:Metrics()
    for i = #navList, 1, -1 do navList[i] = nil end

    panel:SetTitle(TITLE_MAIN)
    local contentWidth, contentHeight = panel.contentWidth, panel.contentHeight
    local tabsWidth = M.button * 5
    LayoutTabs(contentHeight, tabsWidth)
    local pageX = tabsWidth + M.gap
    local pageWidth = max(contentWidth - pageX, M.button * 2)
    local headerHeight = LayoutHeader(pageX, pageWidth)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", pageX, -headerHeight)
    local areaHeight = max(contentHeight - headerHeight, M.button * 2 + M.gap)

    -- First with no scroll bar and the whole width. Only a page that turns
    -- out too long is drawn again, narrower, with the bar.
    local start = #navList
    local total
    for pass = 1, 2 do
        for i = #navList, start + 1, -1 do navList[i] = nil end
        list:Begin()
        area:Layout(pageWidth, areaHeight, pass == 1)
        local ok
        ok, total = PE:Safe("core", BuildPage, area.viewWidth)
        if not ok or type(total) ~= "number" then total = list.lowest + M.pad end
        if total <= area.viewHeight + 0.5 or not PE:UsesTouch() then break end
    end
    list:End()
    area:SetContentHeight(total)

    if (tab == "errors" or page == "key") and area.upButton:IsShown() then
        -- Little in these pages can take the controller highlight, so the
        -- scroll bar's tabs do.
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    navList[#navList + 1] = panel.closeButton
    if tab ~= drawnTab or page ~= drawnPage then
        local pageChanged = page ~= drawnPage
        drawnTab, drawnPage = tab, page
        -- The highlight in use: after a tab change it stays on its tab; on
        -- another page of the same tab it goes to the page's first stop.
        local focus = panel.peNavFocus
        if focus and (pageChanged or not IsTab(focus)) then
            local first = PageColumn()[1]
            if pageChanged and first then panel:NavSetFocus(first) else panel:NavSetFocus(ChosenTabButton()) end
        end
    end
    panel:NavRefresh()
end

-- Redraw now.
local function Draw()
    if drawing or not built or not panel:IsShown() then return end
    drawing = true
    PE:Safe("core", DoRefresh)
    drawing = false
end

local function QueuedDraw()
    drawQueued = false
    Draw()
end

-- Redraw once on the next frame, however many times this is asked for.
local function QueueDraw()
    if drawQueued or not built or not panel:IsShown() then return end
    if C_Timer and C_Timer.After then
        drawQueued = true
        C_Timer.After(0, QueuedDraw)
    else
        Draw()
    end
end

---------------------------------------------------------------------------
-- Building the window (first open only)
---------------------------------------------------------------------------

local function PanelSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    return min(screenWidth * 0.96, UI:Px(1180)), screenHeight * 0.92
end

local function SelectTab(id)
    if not TabById(id) then return end
    if PE.debugOn and (id ~= tab or page ~= "main") then PE:Debug("settings", "tab " .. id) end
    if id ~= tab or page ~= "main" then
        tab, page = id, "main"
        area.offset = 0
    end
    Draw()
end

local function MakeTab(t)
    local btn = UI:CreateButton(panel.content, t.label)
    btn.peTabId = t.id
    btn.peText:SetJustifyH("LEFT")
    btn.peBar = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    btn.peBar:SetColorTexture(1, 0.82, 0, 1)
    btn.peDotAnchor = CreateFrame("Frame", nil, btn)
    btn.peDot = UI:CreateDisc(btn, "ARTWORK", 3)
    btn.peBadgeDisc = UI:CreateDisc(btn, "ARTWORK", 3)
    btn.peBadgeDisc:SetShown(false)
    btn.peBadgeEnd = UI:CreateDisc(btn, "ARTWORK", 3)
    btn.peBadgeEnd:SetShown(false)
    btn.peBadgeMid = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    btn.peBadgeMid:Hide()
    btn.peBadgeLeft = CreateFrame("Frame", nil, btn)
    btn.peBadgeRight = CreateFrame("Frame", nil, btn)
    btn.peCount = btn:CreateFontString(nil, "OVERLAY", M.smallFont)
    if not btn.peCount:GetFont() and GameFontHighlight then btn.peCount:SetFontObject(GameFontHighlight) end
    btn.peCount:SetTextColor(1, 1, 1, 1)
    btn.peCount:Hide()
    btn:SetScript("OnClick", PE:Wrap("core", function() SelectTab(t.id) end))
    return btn
end

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, TITLE_MAIN, width, height)
    area = UI:CreateScrollArea(panel.content)

    list = PE:NewListDrawer({ child = area.child, navList = navList })

    for i, t in ipairs(TABS) do tabButtons[i] = MakeTab(t) end

    header.warn = UI:CreateText(panel.content, "small")
    header.reloadText = UI:CreateText(panel.content, "small")
    header.reloadButton = UI:CreateButton(panel.content, "Reload now")
    header.reloadButton:SetStyle("warn")
    -- Called straight from the tap, in case reloading needs a real button press.
    header.reloadButton:SetScript("OnClick", function() PE:ReloadNow() end)

    UI:AttachNav(panel, function() return navList end)
    panel.peNavArea = area   -- lets the d-pad page the list when touch is off (UI.lua NavMove)
    panel.navColumn = NavColumn
    panel.navCross = NavCross
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end

    UI:OnMetricsChanged(function()
        if not built then return end
        local newWidth, newHeight = PanelSize()
        panel:SetPanelSize(newWidth, newHeight)
        QueueDraw()
    end)
end

---------------------------------------------------------------------------
-- Public entry points (replace the placeholders in Core.lua)
---------------------------------------------------------------------------

-- which: nil (the tab shown last), a tab id from PE.SETTINGS_TABS, or "key"
-- (the Quest Icon Key, in the Quest icons tab).
function PE:OpenSettings(which)
    if not built and not buildFailed then
        if PE.UI and PE:Safe("core", Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        self:Print("The settings window could not be opened. The latest problems are listed here instead.")
        self:PrintErrors()
        return
    end
    local newTab, newPage = tab, page
    if which == "key" then
        newTab, newPage = "questIcons", "key"
    elseif type(which) == "string" and TabById(which) then
        newTab, newPage = which, "main"
    end
    if newTab ~= tab or newPage ~= page then
        tab, page = newTab, newPage
        area.offset = 0
    end
    -- Never stack on another Pocket Essentials window: every panel made by
    -- PE.UI:CreatePanel with a name is listed in UISpecialFrames.
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other ~= panel and other.IsShown and other:IsShown() then pcall(other.Hide, other) end
        end
    end
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Draw() -- opening and changing page draw at once; everything else waits a frame
end

function PE:CloseSettings()
    if built and panel:IsShown() then panel:Hide() end
end

function PE:ToggleSettings()
    if built and panel:IsShown() then
        panel:Hide()
    else
        self:OpenSettings()
    end
end

-- Does nothing unless the window is open. Several calls in one frame cost one redraw.
function PE:RefreshSettings()
    QueueDraw()
end

-- The chosen tab and page, for tests and the debug log.
function PE:SettingsPage()
    return tab, page
end
