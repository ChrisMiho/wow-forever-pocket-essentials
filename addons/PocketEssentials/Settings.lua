-- Pocket Essentials: the settings panel and its Errors page.
-- A standalone window made of large buttons (no Blizzard settings rows).
-- Built the first time it is opened; redrawn only when something changes.
local ADDON_NAME, PE = ...

local type, tostring, tonumber, ipairs, pcall = type, tostring, tonumber, ipairs, pcall
local max, min, ceil, floor = math.max, math.min, math.ceil, math.floor

local PANEL_NAME = "PocketEssentialsSettingsPanel"
local TITLE_MAIN = "Pocket Essentials"
local TITLE_ERRORS = "Pocket Essentials - Errors"
local TITLE_KEY = "Pocket Essentials - Icon key"

local COLOR = {
    font = { 1, 1, 1 },
    small = { 0.84, 0.84, 0.84 },
    title = { 1, 0.82, 0 },
    option = { 1, 0.82, 0 },
    status = { 0.65, 0.85, 1 },
    warn = { 1, 0.60, 0.20 },
    dim = { 0.62, 0.62, 0.62 },
}

local UI           -- PE.UI, set when the first list drawer is made
local M            -- current metrics
local panel, area
local list         -- this window's list drawer (see below)
local header = {}  -- fixed widgets above the scrolling list
local navList = {} -- tappable buttons in reading order, rebuilt on every redraw
local page = "main"
local drawnPage = "main"
local built, buildFailed = false, false
local drawing, drawQueued = false, false
local refocusKey   -- feature whose fold button the controller highlight returns to after the next redraw

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

local function TextHeight(fontString, kind, text, width)
    local size = (kind == "small" and M.smallFontSize) or (kind == "title" and M.fontSize * 1.12) or M.fontSize
    local ok, height = pcall(fontString.GetStringHeight, fontString)
    if ok and type(height) == "number" and height >= size * 0.8 then return height end
    -- The game could not measure it yet: estimate from the text length.
    local perLine = max(floor(width / (size * 0.5)), 1)
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + max(ceil(#line / perLine), 1)
    end
    return max(lines, 1) * size * 1.2
end

local function SetText(fontString, kind, text, width, color)
    text = text == nil and "" or tostring(text)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    local c = color or COLOR[kind] or COLOR.font
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    return TextHeight(fontString, kind, text, width)
end

local function ResetButton(btn)
    btn:SetSelected(false)
    btn:SetStyle("normal")
    btn:SetBadgeText(nil)
    btn.peFoldKey = nil
    btn:ClearAllPoints()
end

---------------------------------------------------------------------------
-- The list drawer. One per window: the settings window has one, the setup
-- guide (Setup.lua) has another. It places texts, lines and buttons in a
-- window's scrolling list and draws a feature's options. Because both
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
--   ... list:Text / Line / Button / Flow / Options / Status ...
--   list:End()      after it: hides what the redraw did not use
--
-- Widgets are reused on every redraw, never thrown away. y grows downwards
-- from the top of the list. list.lowest is how far down this redraw got.
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

-- kind: "font", "small" or "title". Returns the height of the text.
function Drawer:Text(kind, text, x, y, width, color)
    local fontString = self:Acquire(kind)
    fontString:ClearAllPoints()
    fontString:SetJustifyH("LEFT") -- a reused one may have been a centred text between buttons
    fontString:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    local height = SetText(fontString, kind, text, width, color)
    if y + height > self.lowest then self.lowest = y + height end
    return height
end

function Drawer:Line(y, width)
    local line = self:Acquire("line")
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
    line:SetSize(max(width, 1), M.border)
    return M.border
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
    btn.peScrollTop, btn.peScrollBottom = y, y + height
    self.navList[#self.navList + 1] = btn
    if y + height > self.lowest then self.lowest = y + height end
    return btn
end

-- The number control's width: two square ends and the well between them,
-- their borders overlapping so each joint is one line.
local function NumberBoxWidth()
    return M.button * 2 + M.button * 2.2 - M.border * 2
end

-- One end of a number control: "-" or "+". With no step it is dimmed, and a
-- press does nothing (it still redraws, like any press). dim: drawn dimmed
-- although it has a press (one that only notes there is no further step).
function Drawer:NumberEnd(sign, step, dim, x, y)
    local btn = self:Acquire("button")
    ResetButton(btn)
    btn:SetLabel(sign)
    btn:SetSize(M.button, M.button)
    btn:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
    btn:SetStyle((step and not dim) and "step" or "stepDim")
    btn:SetScript("OnClick", step or self.noStep)
    btn.peScrollTop, btn.peScrollBottom = y, y + M.button
    self.navList[#self.navList + 1] = btn
    return btn
end

-- The number control (spec 2026-11-18-number-control-design): "-", a dark
-- well with the value in gold and a small grey unit word under it, "+", as
-- one box. box: { text, unit, down = onClick or nil, up = onClick or nil,
-- downDim, upDim }.
-- The well is not a d-pad stop.
function Drawer:NumberBox(box, x, y)
    local endWidth, wellWidth = M.button, M.button * 2.2
    self:NumberEnd("-", box.down, box.downDim, x, y)
    local well = self:Acquire("well")
    local wx = x + endWidth - M.border
    well:ClearAllPoints()
    well:SetSize(wellWidth, M.button)
    well:SetPoint("TOPLEFT", self.child, "TOPLEFT", wx, -y)
    well.fill:ClearAllPoints()
    well.fill:SetPoint("TOPLEFT", well, "TOPLEFT", M.border, -M.border)
    well.fill:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -M.border, M.border)
    local inner = wellWidth - M.border * 2
    local unit = box.unit ~= nil and tostring(box.unit) or ""
    -- The unit word goes under the value only when both lines fit.
    local showUnit = unit ~= "" and M.fontSize + M.smallFontSize <= M.button - M.border * 2
    local valueHeight = SetText(well.value, "font", box.text, inner, COLOR.option)
    well.value:ClearAllPoints()
    if showUnit then
        local unitHeight = SetText(well.unit, "small", unit, inner, COLOR.dim)
        local top = max((M.button - valueHeight - unitHeight) * 0.5, M.border)
        well.value:SetPoint("TOP", well, "TOP", 0, -top)
        well.unit:ClearAllPoints()
        well.unit:SetPoint("TOP", well, "TOP", 0, -(top + valueHeight))
        well.unit:Show()
    else
        well.value:SetPoint("TOP", well, "TOP", 0, -max((M.button - valueHeight) * 0.5, 0))
        well.unit:Hide()
    end
    self:NumberEnd("+", box.up, box.upDim, wx + wellWidth - M.border, y)
    return NumberBoxWidth()
end

-- A run of buttons sized to their labels, wrapping onto new lines.
-- items: { { label =, selected =, style =, onClick = }, ... }. An item
-- { text = } is not a button: it is a short centred text in the run. An
-- item { box = } is a number control (NumberBox), kept whole on one line.
-- Returns the new y.
function Drawer:Flow(items, x0, y, maxWidth, minWidth)
    local x, height = x0, M.button
    local navList = self.navList
    for i = 1, #items do
        local item = items[i]
        local width
        if item.box ~= nil then
            width = NumberBoxWidth()
            if x > x0 and x + width > x0 + maxWidth then
                x = x0
                y = y + height + M.gap
            end
            self:NumberBox(item.box, x, y)
        elseif item.text ~= nil then
            local text = tostring(item.text)
            -- A fixed width for short texts, so the button after it stays put
            -- when the number changes.
            width = min(max(M.button * 1.6, #text * M.fontSize * 0.6 + M.pad), maxWidth)
            if x > x0 and x + width > x0 + maxWidth then
                x = x0
                y = y + height + M.gap
            end
            local fontString = self:Acquire("font")
            fontString:ClearAllPoints()
            fontString:SetJustifyH("CENTER")
            local textHeight = SetText(fontString, "font", text, width)
            fontString:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -(y + max((height - textHeight) * 0.5, 0)))
        else
            local btn = self:Acquire("button")
            ResetButton(btn)
            btn:SetLabel(item.label)
            btn:SetHeight(height)
            width = btn:FitWidth(minWidth or M.button * 2.2, maxWidth)
            if x > x0 and x + width > x0 + maxWidth then
                x = x0
                y = y + height + M.gap
            end
            btn:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
            if item.style then btn:SetStyle(item.style) end
            btn:SetSelected(item.selected)
            btn:SetScript("OnClick", item.onClick)
            btn.peScrollTop, btn.peScrollBottom = y, y + height
            navList[#navList + 1] = btn
        end
        if y + height > self.lowest then self.lowest = y + height end
        x = x + width + M.gap
    end
    return y + height
end

-- Which option rows of a feature are drawn right now. Options are drawn
-- while the feature is on; a feature that is not on (off, or cannot be
-- switched on) still shows its rows marked `always`.
-- Returns: any row to draw, only the `always` rows.
function Drawer:OptionsShown(mod)
    local onlyAlways = PE:GetModuleState(mod.key) ~= "on"
    local hasOptions = false
    if type(mod.options) == "table" then
        if not onlyAlways then
            hasOptions = #mod.options > 0
        else
            for _, opt in ipairs(mod.options) do
                if type(opt) == "table" and opt.always == true then hasOptions = true end
            end
        end
    end
    return hasOptions, onlyAlways
end

-- How far the list has got: what Rewind needs to take back a part just drawn.
function Drawer:Mark()
    local used = {}
    for name, pool in pairs(self.pools) do used[name] = pool.used end
    return { used = used, nav = #self.navList, lowest = self.lowest }
end

-- Takes back everything drawn since Mark: the widgets go back to their pools
-- (hidden by End unless the redraw uses them again) and leave the d-pad list.
function Drawer:Rewind(mark)
    for name, pool in pairs(self.pools) do
        if mark.used[name] then pool.used = mark.used[name] end
    end
    for i = #self.navList, mark.nav + 1, -1 do self.navList[i] = nil end
    self.lowest = mark.lowest
end

-- The width a text takes in the small font, on one line.
function Drawer:Measure(text)
    -- One hidden text per window, made on the first measure, used only to measure.
    if self.measure == nil then
        local ok, made = pcall(UI.CreateText, UI, self.child, "small")
        self.measure = ok and made or false
        if self.measure then self.measure:Hide() end
    end
    local fontString = self.measure
    local width
    if fontString then
        fontString:SetText(text)
        local ok, got = pcall(fontString.GetUnboundedStringWidth, fontString)
        if ok and type(got) == "number" and got > 0 then width = got end
    end
    return width or #text * M.smallFontSize * 0.55
end

-- The heading column of a group of rows: wide enough for the widest heading,
-- and never more than 40% of the row. 0 when there is no heading.
function Drawer:LabelColumn(texts, innerWidth)
    local widest = 0
    for i = 1, #texts do widest = max(widest, self:Measure(texts[i])) end
    if widest <= 0 then return 0 end
    return min(widest + M.gap * 1.5, innerWidth * 0.4)
end

-- A heading and its run of buttons. With a heading column the heading goes on
-- the buttons' line, left of them, when the buttons fit on one line beside it
-- and the heading fits its column; otherwise the heading goes above them, as
-- before. Returns the new y (the bottom of the row).
function Drawer:LabeledRow(text, items, x, y, innerWidth, labelWidth)
    if text ~= "" and labelWidth and labelWidth > 0 and self:Measure(text) <= labelWidth - M.gap then
        local mark = self:Mark()
        local bottom = self:Flow(items, x + labelWidth, y, innerWidth - labelWidth)
        if bottom <= y + M.button + 0.01 then
            local fontString = self:Acquire("small")
            fontString:ClearAllPoints()
            fontString:SetJustifyH("LEFT")
            local height = SetText(fontString, "small", text, labelWidth - M.gap, COLOR.option)
            local top = y + max((M.button - height) * 0.5, 0)
            fontString:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -top)
            if top + height > self.lowest then self.lowest = top + height end
            return max(bottom, top + height)
        end
        self:Rewind(mark)
    end
    if text ~= "" then
        y = y + self:Text("small", text, x, y, innerWidth, COLOR.option) + M.gap * 0.4
    end
    return self:Flow(items, x, y, innerWidth)
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

local function IsToggleRow(opt)
    return opt.toggle == true and IsChoiceRow(opt) and #opt.choices == 2
        and type(opt.choices[1]) == "table" and type(opt.choices[2]) == "table"
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
-- After max comes `all`, when the row has one.
local function NumberSteps(n, v)
    local hasAll = n.all ~= nil and n.all ~= false
    if hasAll and v == n.all then return n.max, nil end
    local down = v > n.min and v - 1 or nil
    local up = (v < n.max and v + 1) or (hasAll and n.all) or nil
    return down, up
end

local function NumberText(n, v)
    if n.all ~= nil and n.all ~= false and v == n.all then return n.allLabel or "All" end
    if v == 0 and n.offLabel then return n.offLabel end
    return tostring(v)
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

-- Option rows: the list `options` of a feature, drawn under its switch while
-- the feature is on. A row with `always = true` is also drawn while the
-- feature is not on (it must not need the feature). Each row is a table of
-- one of these kinds:
--   choices: { key, label, choices = { { value, label }, ... }, OnChange }
--            a row of buttons; the tapped one is saved as mod.opts[key].
--            Instead of key, a row may have get = function(mod) -> value and
--            set = function(mod, value), when one choice stands for more
--            than one saved value. With toggle = true and two choices, it is
--            one button "label: choice" that flips to the other choice;
--            toggles that follow each other share a line. A toggle showing
--            the value true is green, otherwise grey.
--            The heading goes beside the buttons when they fit (LabeledRow).
--   action:  { label, action = function(mod) }
--            one wide button that runs the action.
--   buttons: { label, value = function(mod) -> text, buttons = { { label,
--            action = function(mod) }, ... } }
--            the label with the value text after it ("label: text"), then a
--            row of buttons. `buttons` may also be a function(mod) that
--            returns that list (an empty list draws no buttons). Each tap
--            runs its action, then the window is drawn again, so the value
--            text is read again. An entry { text = } in the list is drawn
--            as a short text at that place in the row instead of a button.
--            A button entry with style = "disabled" is drawn dim (it has
--            nothing to do right now); it can still be pressed.
--   number:  { key, label, number = { min, max, default, unit, all,
--            allLabel, offLabel }, OnChange }
--            the number control "- value +" (NumberBox); each end saves
--            mod.opts[key] one step down or up. `all` (optional) is the
--            value after max, shown as allLabel ("All"); offLabel (optional)
--            is shown at 0. A saved value that is not a whole number in the
--            range shows the default. An end with no step is dimmed.
--   stepper: { label, value = function(mod) -> text, stepper =
--            function(mod) -> { text, unit, down = fn, up = fn, downDim,
--            upDim } or nil }
--            the same control for a value the feature keeps itself; a
--            missing down or up, or downDim / upDim = true, is a dimmed end
--            (a dimmed end with a function still runs it). nil draws the
--            label only.
-- onlyAlways: draw only the rows marked `always`.
-- Returns the new y.
function Drawer:Options(mod, y, width, onlyAlways)
    local x = M.pad * 2
    local innerWidth = width - x - M.gap
    local refresh = self.refresh

    -- The headings of this feature's rows, for one shared heading column.
    local rows, headings = {}, {}
    for _, opt in ipairs(mod.options) do
        if type(opt) == "table" and (not onlyAlways or opt.always == true) then
            local text
            if IsToggleRow(opt) or type(opt.action) == "function" then
                text = nil
            elseif IsChoiceRow(opt) or IsNumberRow(opt) then
                text = type(opt.label) == "string" and opt.label or ""
            elseif type(opt.buttons) == "table" or type(opt.buttons) == "function"
                or type(opt.stepper) == "function" then
                text = type(opt.label) == "string" and opt.label or ""
                if type(opt.value) == "function" then
                    local ok, shown = pcall(opt.value, mod)
                    if ok and shown ~= nil then text = (text ~= "" and (text .. ": ") or "") .. tostring(shown) end
                end
            end
            rows[#rows + 1] = { opt = opt, text = text }
            if text and text ~= "" then headings[#headings + 1] = text end
        end
    end
    local labelWidth = self:LabelColumn(headings, innerWidth)

    -- Toggles waiting to be drawn together on one line.
    local toggles = {}
    local function FlushToggles()
        if #toggles == 0 then return end
        y = self:Flow(toggles, x, y, innerWidth) + M.gap
        toggles = {}
    end

    for _, row in ipairs(rows) do
        local opt = row.opt
        if not IsToggleRow(opt) then FlushToggles() end
        do
            if IsToggleRow(opt) then
                local current = CurrentChoice(mod, opt)
                local first, second = opt.choices[1], opt.choices[2]
                local shown = (current == second.value) and second or first
                -- The other side from the one shown, so a tap always changes what
                -- the button says (a damaged value shows as the first choice).
                -- Not "and ... or": the value may be false.
                local nextValue = second.value
                if shown == second then nextValue = first.value end
                local label = tostring(shown.label ~= nil and shown.label or shown.value)
                if type(opt.label) == "string" and opt.label ~= "" then label = opt.label .. ": " .. label end
                toggles[#toggles + 1] = {
                    label = label,
                    style = (current == true) and "on" or "off",
                    onClick = ChooseHandler(mod, opt, nextValue, refresh),
                }
            elseif IsChoiceRow(opt) then
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
                y = self:LabeledRow(row.text, items, x, y, innerWidth, labelWidth) + M.gap
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
                y = self:LabeledRow(row.text, { { box = box } }, x, y, innerWidth, labelWidth) + M.gap
            elseif type(opt.stepper) == "function" then
                local text = row.text or ""
                local ok, got = pcall(opt.stepper, mod)
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
                    y = self:LabeledRow(text, { { box = box } }, x, y, innerWidth, labelWidth) + M.gap
                elseif text ~= "" then
                    y = y + self:Text("small", text, x, y, innerWidth, COLOR.option) + M.gap * 0.4
                end
            elseif type(opt.action) == "function" then
                local items = { {
                    label = (type(opt.label) == "string" and opt.label ~= "") and opt.label or "Do it",
                    onClick = PE:Wrap("core", function()
                        PE:Safe(mod.key, opt.action, mod)
                        refresh()
                    end),
                } }
                y = self:Flow(items, x, y, innerWidth, M.button * 4) + M.gap
            elseif type(opt.buttons) == "table" or type(opt.buttons) == "function" then
                local text = row.text or ""
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
                            -- dim: nothing to do right now (still safe to press)
                            style = b.style == "disabled" and "disabled" or nil,
                            onClick = PE:Wrap("core", function()
                                PE:Safe(mod.key, b.action, mod)
                                refresh()
                            end),
                        }
                    end
                end
                if #items > 0 then
                    y = self:LabeledRow(text, items, x, y, innerWidth, labelWidth) + M.gap
                elseif text ~= "" then
                    y = y + self:Text("small", text, x, y, innerWidth, COLOR.option) + M.gap * 0.4
                end
            end
        end
    end
    FlushToggles()
    return y
end

-- The lines under a feature's name that say how it is doing: its own status
-- text (blue), why it cannot be switched on, or that it hit a problem
-- (amber). failedText: the sentence for the last case. Returns the new y.
function Drawer:Status(mod, x, y, width, failedText)
    local key = mod.key
    local state, detail = PE:GetModuleState(key)
    if type(mod.status) == "function" then
        local ok, status = PE:Safe(key, mod.status, mod)
        if ok then
            if type(status) == "table" then
                local lines = {}
                for i = 1, #status do lines[i] = tostring(status[i]) end
                status = table.concat(lines, "\n")
            end
            if type(status) == "string" and status ~= "" then
                y = y + self:Text("small", status, x, y, width, COLOR.status) + M.gap * 0.3
            end
        end
    end
    if state == "blocked" then
        y = y + self:Text("small", detail or "This cannot be switched on right now.", x, y, width, COLOR.warn) + M.gap * 0.3
    elseif state == "failed" then
        y = y + self:Text("small", failedText, x, y, width, COLOR.warn) + M.gap * 0.3
    end
    return y
end

local SIZE_CHOICES = {
    { value = "small", label = "Small" },
    { value = "medium", label = "Medium" },
    { value = "large", label = "Large" },
}

-- The settings that belong to no feature: "Button size", "Round button
-- position" and "Touch screen". Returns the new y.
function Drawer:CoreChoices(y, width)
    local x = M.pad * 2
    local innerWidth = width - x - M.gap
    local ui = PE.db and PE.db.ui or {}
    local positions = PE.Hub and PE.Hub.POSITIONS
    local labelWidth = self:LabelColumn(type(positions) == "table" and { "Button size", "Round button position" }
        or { "Button size" }, innerWidth)

    local items = {}
    for i, choice in ipairs(SIZE_CHOICES) do
        local value = choice.value
        items[i] = {
            label = choice.label,
            selected = (ui.size == value),
            onClick = PE:Wrap("core", function() PE:SetUISetting("size", value) end),
        }
    end
    y = self:LabeledRow("Button size", items, x, y, innerWidth, labelWidth) + M.gap

    if type(positions) == "table" then
        items = {}
        for i, choice in ipairs(positions) do
            local value = choice.value
            items[i] = {
                label = choice.label,
                selected = (ui.hubPos == value),
                onClick = PE:Wrap("core", function() PE:SetUISetting("hubPos", value) end),
            }
        end
        y = self:LabeledRow("Round button position", items, x, y, innerWidth, labelWidth) + M.gap
    end

    -- Shows or hides the scroll bar's Up and Down tabs in every window.
    local touch = PE:UsesTouch()
    y = self:Flow({ {
        label = "Touch screen: " .. (touch and "Yes" or "No"),
        style = touch and "on" or "off",
        onClick = PE:Wrap("core", function() PE:SetUISetting("touch", not touch) end),
    } }, x, y, innerWidth) + M.gap
    return y
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
    drawer:AddPool("well", function()
        local well = CreateFrame("Frame", nil, child)
        well.border = well:CreateTexture(nil, "BACKGROUND")
        well.border:SetAllPoints(well)
        well.border:SetColorTexture(0.62, 0.52, 0.22, 1)
        well.fill = well:CreateTexture(nil, "BORDER")
        well.fill:SetColorTexture(0.03, 0.03, 0.04, 1)
        well.value = UI:CreateText(well, "font")
        well.value:SetJustifyH("CENTER")
        well.value:SetWordWrap(false)
        well.unit = UI:CreateText(well, "small")
        well.unit:SetJustifyH("CENTER")
        well.unit:SetWordWrap(false)
        return well
    end)
    drawer:AddPool("button", function() return UI:CreateButton(child, "") end)
    drawer:AddPool("font", function() return UI:CreateText(child, "font") end)
    drawer:AddPool("small", function() return UI:CreateText(child, "small") end)
    drawer:AddPool("title", function() return UI:CreateText(child, "title") end)
    drawer:AddPool("line", function()
        local line = child:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.30, 0.30, 0.34, 1)
        return line
    end)
    return drawer
end

---------------------------------------------------------------------------
-- Placing things in this window's list
---------------------------------------------------------------------------

local function PlaceText(kind, text, x, y, width, color)
    return list:Text(kind, text, x, y, width, color)
end

local function PlaceLine(y, width)
    return list:Line(y, width)
end

local function PlaceButton(text, x, y, width, height, style, onClick)
    return list:Button(text, x, y, width, height, style, onClick)
end

local function FlowButtons(items, x0, y, maxWidth, minWidth)
    return list:Flow(items, x0, y, maxWidth, minWidth)
end

---------------------------------------------------------------------------
-- Main page
---------------------------------------------------------------------------

-- The saved folds: { [feature key] = true }. Core.lua keeps this a table;
-- the check here covers a table that was damaged while the game ran.
local function FoldTable()
    local ui = PE.db and PE.db.ui
    if type(ui) ~= "table" then return {} end
    if type(ui.folded) ~= "table" then ui.folded = {} end
    return ui.folded
end

-- Fold or unfold one feature's options. A plain saved write: nothing else
-- depends on it, so there is no metrics refresh, only a redraw.
local function ToggleFold(key)
    local folded = FoldTable()
    local nowFolded = folded[key] ~= true
    folded[key] = nowFolded and true or nil
    if PE.debugOn then PE:Debug("settings", key .. (nowFolded and " folded" or " unfolded")) end
    -- The redraw reuses buttons, so remember by feature where the controller
    -- highlight was, and put it back on that feature's fold button.
    local focus = panel and panel.peNavFocus
    refocusKey = (focus and focus.peFoldKey == key) and key or nil
    PE:RefreshSettings()
end

local function BuildModuleRow(mod, y, width, separator)
    if separator then
        y = y + PlaceLine(y, width) + M.gap
    else
        y = y + M.gap * 0.5
    end
    local key = mod.key
    local state = PE:GetModuleState(key)
    local savedOn = PE:IsModuleSavedOn(key)
    local toggleWidth = M.button * 2.8
    local textX = M.gap
    local hasOptions, onlyAlways = list:OptionsShown(mod)
    local folded = hasOptions and FoldTable()[key] == true
    -- "Hide options" / "Show options" sits left of the switch. 3.4 buttons
    -- wide holds the longer label at the Large size (about 230 of the
    -- roughly 780 units the text has beside the switch at 720p).
    local foldWidth = hasOptions and M.button * 3.4 or 0
    local textWidth = width - toggleWidth - textX - M.pad - (hasOptions and (foldWidth + M.gap) or 0)

    local title = Escape(mod.label)
    if mod.experimental then title = title .. "   |cffff9a33Experimental|r" end
    local ty = y + M.gap * 0.3
    ty = ty + PlaceText("font", title, textX, ty, textWidth) + M.gap * 0.3
    if not folded and type(mod.desc) == "string" and mod.desc ~= "" then
        ty = ty + PlaceText("small", mod.desc, textX, ty, textWidth) + M.gap * 0.3
    end
    ty = list:Status(mod, textX, ty, textWidth, "Switched on, but it hit a problem. See Errors at the bottom of this list.")
    local rowHeight = max(M.row, ty - y)

    local label, style = PE:GetModuleSwitch(key)
    -- The switch is placed (and so pooled) before the fold button: the buttons
    -- after it come and go when it is tapped, and it must keep its own place so
    -- the controller highlight stays on it.
    local toggle = PlaceButton(label, width - toggleWidth, y + (M.row - M.button) * 0.5, toggleWidth, M.button, style,
        PE:Wrap("core", function()
            if state == "blocked" then return end
            PE:SetModuleEnabled(key, not savedOn)
        end))
    -- When the controller lands on the switch, bring the whole row into view.
    toggle.peScrollTop, toggle.peScrollBottom = y, y + rowHeight
    if hasOptions then
        local fold = PlaceButton(folded and "Show options" or "Hide options",
            width - toggleWidth - M.gap - foldWidth, y + (M.row - M.button) * 0.5, foldWidth, M.button, nil,
            PE:Wrap("core", function() ToggleFold(key) end))
        fold.peFoldKey = key
        fold.peScrollTop, fold.peScrollBottom = y, y + rowHeight
        -- Reading order for the d-pad: the fold button, then the switch beside it.
        local n = #navList
        navList[n - 1], navList[n] = fold, toggle
    end

    y = y + rowHeight + M.gap * 0.5
    if hasOptions and not folded then
        y = list:Options(mod, y, width, onlyAlways)
    end
    return y
end

local function BuildCoreSection(y, width)
    local x = M.pad * 2
    local innerWidth = width - x - M.gap

    y = y + PlaceLine(y, width) + M.gap
    y = y + PlaceText("title", TITLE_MAIN, M.gap, y, width - M.gap * 2) + M.gap

    y = list:CoreChoices(y, width)
    local positions = PE.Hub and PE.Hub.POSITIONS
    if type(positions) == "table" then
        y = y + PlaceText("small", "Tip: press and hold the round button to open this window.", x, y, innerWidth, COLOR.dim) + M.gap
    end

    local count = #PE.errors
    local items = {
        {
            label = "Reload UI",
            -- Called straight from the tap, in case reloading needs a real button press.
            onClick = function() PE:ReloadNow() end,
        },
        {
            label = "Errors (" .. count .. ")",
            style = count > 0 and "warn" or nil,
            onClick = PE:Wrap("core", function() PE:OpenSettings("errors") end),
        },
    }
    -- Last in the row, so the buttons before it keep their places.
    if PE.Move and PE.Move.Open then
        items[#items + 1] = {
            label = "Move things",
            onClick = PE:Wrap("core", function() PE.Move:Open() end),
        }
    end
    if PE.Setup and PE.Setup.Open then
        items[#items + 1] = {
            label = "Setup guide",
            onClick = PE:Wrap("core", function() PE.Setup:Open("settings") end),
        }
    end
    y = FlowButtons(items, x, y, innerWidth, M.button * 3)
    return y + M.pad
end

local function BuildMain(width)
    local y = 0
    local mods = PE.moduleList
    for i = 1, #mods do
        -- Each row on its own: a row that fails is logged against its
        -- feature and the rest of the page is still drawn below it.
        local ok, nextY = PE:Safe(mods[i].key, BuildModuleRow, mods[i], y, width, i > 1)
        if ok and type(nextY) == "number" then
            y = nextY
        else
            y = max(y, list.lowest) + M.gap
        end
    end
    if #mods == 0 then
        y = y + M.gap
        y = y + PlaceText("font", "No features were loaded.", M.gap, y, width - M.gap * 2) + M.gap
    end
    return BuildCoreSection(y, width)
end

---------------------------------------------------------------------------
-- Errors page
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

-- The debug log's switch, line count and buttons. The count is read when the
-- page is drawn (on opening, and after the switch or a button), never per
-- logged line.
local function BuildDebugLog(y, width)
    local x = M.gap
    local toggleWidth = M.button * 2.8
    local textWidth = width - toggleWidth - x - M.pad
    local on = PE.debugOn == true
    local ty = y + M.gap * 0.3
    ty = ty + PlaceText("font", "Debug log", x, ty, textWidth, COLOR.title) + M.gap * 0.3
    ty = ty + PlaceText("small", "Turn this on, play until the problem happens, tap Save log now, then send the file "
        .. "WTF/Account/<account>/SavedVariables/PocketEssentials.lua.", x, ty, textWidth) + M.gap * 0.3
    ty = ty + PlaceText("small", WithCommas(PE:DebugCount()) .. " of " .. WithCommas(PE.DEBUG_CAP) .. " lines",
        x, ty, textWidth, COLOR.status) + M.gap * 0.3
    local rowHeight = max(M.row, ty - y)
    local toggle = PlaceButton(on and "ON" or "OFF", width - toggleWidth, y + (M.row - M.button) * 0.5, toggleWidth, M.button,
        on and "on" or "off", PE:Wrap("core", function() PE:SetDebug(not PE.debugOn) end))
    toggle.peScrollTop, toggle.peScrollBottom = y, y + rowHeight
    y = y + rowHeight + M.gap * 0.5
    y = FlowButtons({
        {
            label = "Save log now",
            -- A reload is what writes the file. Called straight from the tap,
            -- in case reloading needs a real button press.
            onClick = function() PE:ReloadNow() end,
        },
        {
            label = "Clear log",
            onClick = PE:Wrap("core", function() PE:ClearDebug() end),
        },
    }, x, y, width - x * 2, M.button * 3) + M.gap
    return y + PlaceLine(y, width) + M.gap
end

local function BuildErrors(width)
    local x = M.gap
    local innerWidth = width - x * 2
    local y = M.gap * 0.5
    -- On its own, so a problem drawing it still leaves the error list below.
    local ok, nextY = PE:Safe("core", BuildDebugLog, y, width)
    y = (ok and type(nextY) == "number") and nextY or (max(y, list.lowest) + M.gap)
    local list = PE.errors
    if #list == 0 then
        return y + PlaceText("font", "No errors recorded.", x, y, innerWidth) + M.gap
    end
    local first = true
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" then
            if not first then y = y + PlaceLine(y, width) + M.gap end
            first = false
            local head = Escape(PE:ModuleLabel(e.module)) .. "   x" .. tostring(tonumber(e.count) or 1)
            if type(e.last) == "number" and e.last > 0 then
                local ok, when = pcall(date, "%b %d %H:%M", e.last)
                if ok and type(when) == "string" then head = head .. "   last: " .. when end
            end
            y = y + PlaceText("font", head, x, y, innerWidth, COLOR.title) + M.gap * 0.3
            y = y + PlaceText("small", Escape(e.msg), x, y, innerWidth, COLOR.font) + M.gap * 0.3
            if type(e.stack) == "string" and e.stack ~= "" then
                y = y + PlaceText("small", Escape(e.stack), x, y, innerWidth, COLOR.dim)
            end
            y = y + M.gap
        end
    end
    return y
end

---------------------------------------------------------------------------
-- Icon key page
---------------------------------------------------------------------------

local function BuildKey(width)
    local x = M.gap
    local y = M.gap * 0.5
    local key = PE.QuestIconKey -- made when QuestIcons.lua loads, so read it here
    if type(key) ~= "table" or #key == 0 then
        return y + PlaceText("font", "The quest icons part of this addon did not load. See Errors.", x, y, width - x * 2) + M.gap
    end
    local side = M.button
    local textX = x + side + M.gap
    local textWidth = width - textX - M.pad
    for i = 1, #key do
        local entry = key[i]
        if type(entry) == "table" then
            if i > 1 then y = y + PlaceLine(y, width) + M.gap end
            -- A reused texture gets its picture, colour and size set again every time.
            local icon = list:Acquire("icon")
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
            icon:SetSize(side, side)
            icon:SetTexture(entry.tex)
            local c = type(entry.color) == "table" and entry.color or COLOR.font
            icon:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1)
            local ty = y
            ty = ty + PlaceText("font", Escape(entry.label or ""), textX, ty, textWidth) + M.gap * 0.3
            ty = ty + PlaceText("small", Escape(entry.desc or ""), textX, ty, textWidth)
            local rowHeight = max(M.row, side, ty - y)
            if y + rowHeight > list.lowest then list.lowest = y + rowHeight end
            y = y + rowHeight + M.gap * 0.5
        end
    end
    y = y + M.gap * 0.5
    y = y + PlaceText("small", "Tap an icon on the map to see what it is for.", x, y, width - x * 2, COLOR.dim) + M.gap * 0.5
    y = y + PlaceText("small", "\"Spots per objective\" in Quest icons sets how many spots each objective shows.", x, y, width - x * 2, COLOR.dim) + M.gap
    return y
end

---------------------------------------------------------------------------
-- Fixed header above the list
---------------------------------------------------------------------------

local function LayoutHeader(width)
    local y = 0
    local content = panel.content

    if PE.oldQuestDotsLoaded then
        header.warn:ClearAllPoints()
        header.warn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + SetText(header.warn, "small", "The old QuestDots folder is still installed. Delete it from AddOns.", width, COLOR.warn) + M.gap
        header.warn:Show()
    else
        header.warn:Hide()
    end

    local reasons = PE.reloadReasons
    if page == "main" and type(reasons) == "table" and #reasons > 0 then
        local buttonWidth = M.button * 4.5
        local lines = {}
        for i = 1, min(#reasons, 2) do
            lines[i] = Escape(reasons[i].label) .. ": " .. Escape(reasons[i].reason)
        end
        header.reloadButton:ClearAllPoints()
        header.reloadButton:SetSize(buttonWidth, M.button)
        header.reloadButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        header.reloadButton:Show()
        header.reloadText:ClearAllPoints()
        header.reloadText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        local textHeight = SetText(header.reloadText, "small", table.concat(lines, "\n"), width - buttonWidth - M.gap, COLOR.warn)
        header.reloadText:Show()
        y = y + max(M.button, textHeight) + M.gap
        navList[#navList + 1] = header.reloadButton
    else
        header.reloadButton:Hide()
        header.reloadText:Hide()
    end

    if page ~= "main" then
        local buttonWidth = M.button * 3.5
        header.back:ClearAllPoints()
        header.back:SetSize(buttonWidth, M.button)
        header.back:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        header.back:Show()
        navList[#navList + 1] = header.back
        if page == "errors" then
            header.clear:ClearAllPoints()
            header.clear:SetSize(buttonWidth, M.button)
            header.clear:SetPoint("TOPLEFT", content, "TOPLEFT", buttonWidth + M.gap, -y)
            header.clear:Show()
            navList[#navList + 1] = header.clear
        else
            header.clear:Hide()
        end
        y = y + M.button + M.gap
    else
        header.back:Hide()
        header.clear:Hide()
    end
    return y
end

---------------------------------------------------------------------------
-- Redraw
---------------------------------------------------------------------------

local function DoRefresh()
    M = UI:Metrics()
    for i = #navList, 1, -1 do navList[i] = nil end
    list:Begin()

    panel:SetTitle(page == "errors" and TITLE_ERRORS or page == "key" and TITLE_KEY or TITLE_MAIN)
    local contentWidth, contentHeight = panel.contentWidth, panel.contentHeight
    local headerHeight = LayoutHeader(contentWidth)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -headerHeight)
    area:Layout(contentWidth, max(contentHeight - headerHeight, M.button * 2 + M.gap))

    local width = area.viewWidth
    local ok, total = PE:Safe("core", page == "errors" and BuildErrors or page == "key" and BuildKey or BuildMain, width)
    if not ok or type(total) ~= "number" then total = list.lowest + M.pad end
    list:End()
    area:SetContentHeight(total)

    if page ~= "main" and area.upButton:IsShown() then
        -- Little or nothing in these lists can take the controller
        -- highlight, so the scroll bar's tabs do.
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    navList[#navList + 1] = panel.closeButton
    if refocusKey then
        local wanted
        for i = 1, #navList do
            if navList[i].peFoldKey == refocusKey then wanted = navList[i] end
        end
        refocusKey = nil
        if wanted and panel.peNavFocus then panel:NavSetFocus(wanted) end
    end
    if page ~= drawnPage then
        -- A different page: if the controller highlight is in use, restart it at the top.
        drawnPage = page
        if panel.peNavFocus then panel:NavSetFocus(navList[1]) end
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

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, TITLE_MAIN, width, height)
    area = UI:CreateScrollArea(panel.content)

    list = PE:NewListDrawer({ child = area.child, navList = navList })
    list:AddPool("icon", function() return area.child:CreateTexture(nil, "ARTWORK") end)

    header.warn = UI:CreateText(panel.content, "small")
    header.reloadText = UI:CreateText(panel.content, "small")
    header.reloadButton = UI:CreateButton(panel.content, "Reload now")
    header.reloadButton:SetStyle("warn")
    -- Called straight from the tap, in case reloading needs a real button press.
    header.reloadButton:SetScript("OnClick", function() PE:ReloadNow() end)
    header.back = UI:CreateButton(panel.content, "Back")
    header.back:SetScript("OnClick", PE:Wrap("core", function() PE:OpenSettings() end))
    header.clear = UI:CreateButton(panel.content, "Clear")
    header.clear:SetScript("OnClick", PE:Wrap("core", function() PE:ClearErrors() end))

    UI:AttachNav(panel, function() return navList end)
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
    local newPage = (which == "errors" or which == "key") and which or "main"
    if newPage ~= page then
        page = newPage
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
