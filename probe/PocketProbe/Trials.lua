local ADDON_NAME, P = ...

-- The trials. Each one is a small table:
--
--   id, area, label, kind   what the saved file lists ("action", "value",
--                           "info" or "guided"; the last two are in Errors.lua)
--   manual = true           only from the panel (its Run button, Run all safe),
--                           never in the automatic passes
--   clean = true            also run alone, first thing after a reload
--   risky = true            may leave the game's controller code refusing its
--                           own actions until a reload; runs last in a pass,
--                           and only with the "Risky trials" switch on
--   vendor = true           costs something; only with a vendor window open
--   fight = true            worth running in a fight: first in the "Fight tests"
--                           pass (a risky one last, and only with Risky on)
--   noFight = true          known to be refused in a fight: left out of that pass
--   noRow = true            no row in the panel (its ten tabs are full at 16:9);
--                           it runs in the passes and its result is saved
--   shots = true            a guided trial that takes a screenshot before and
--                           after its change (Run.lua, the timed steps)
--   big = "..."             a guided trial's question in big letters on the screen
--   fightNext = true        a guided trial that waits for the next fight (Run.lua):
--                           startBig is shown at Start, prepare() runs then,
--                           apply() at the fight's start, onFight(true / false)
--                           as it starts and ends, atFightEnd() reads what it
--                           wants before restore(), then the question; `wait`
--                           is what Details says meanwhile
--   needs = { "A.B", ... }  game names it calls; one missing -> "missing"
--   gate()                  false: not this trial's moment (skipped silently)
--   ready()                 false, reason: nothing to try right now (logged)
--   run(state)              an action: does the thing and returns
--                             true   the expected thing happened
--                             false  it did not (-> "no effect"); a second
--                                    value is the reason
--                             nil    there is no way to check
--                             "missing", name   a method is not on this client
--                             "wait"            look again after `wait` seconds
--   check(state)            for "wait": returns true / false / nil as above
--   undo(state)             puts things back; always runs, in its own pcall
--   read(c)                 a value: c:add(name, value) for each value read
--
-- Which trials are risky, from the first run on the device (Gamepad UI on):
-- opening, focusing or closing the chat box and opening the bags all go
-- through Blizzard's controller focus code (FrameControlsManager:FrameShown
-- -> SmartNavigation:ActivateBinding / SetFallThroughCatcherActive), which
-- refused there, and afterwards the game refused its own interact and cancel
-- actions in this addon's name until a reload. Setting the layout is risky by
-- the source: the game sends its "layouts updated" event from inside our call,
-- so Blizzard's handler stores values on its own frames with our mark on
-- them. Taking a key and marking a button touch only our own frames and
-- showed no sign on the device, so they are not.
--
-- Run.lua calls these inside its error catcher and watches for the game's
-- "blocked" signals while one runs. Nothing here stores a value read from
-- the game: only classes ("readable", "secret", "nil") and our own text.

local type, pairs, ipairs, pcall, tostring, unpack = type, pairs, ipairs, pcall, tostring, unpack
local tconcat, floor, abs = table.concat, math.floor, math.abs
local Find, IsSecret, Num, Str = P.Find, P.IsSecret, P.Num, P.Str

P.trials = {}
P.trialById = {}

local function Add(t)
    P.trials[#P.trials + 1] = t
    P.trialById[t.id] = t
end
P.Add = Add

local function Has(obj, method)
    return type(obj) == "table" and type(obj[method]) == "function"
end

-- True if the frame says it is shown (false when that cannot be read).
local function Shown(frame)
    if not Has(frame, "IsShown") then return false end
    local shown = frame:IsShown()
    if IsSecret(shown) then return false end
    return shown and true or false
end

-- A frame's parent, or nil with "unreadable".
local function ParentOf(frame)
    local parent = frame:GetParent()
    if IsSecret(parent) then return nil, "unreadable" end
    return parent
end

---------------------------------------------------------------------------
-- Our own frames for the trials, all made now (at load, out of combat) so
-- that making them is never itself something done in a fight.
---------------------------------------------------------------------------

local ESCAPE_NAME = "PocketProbeEscapeWindow"
local KEY_BUTTON_NAME = "PocketProbeKeyButton"
local TEST_KEY = "PADRSTICK"       -- right stick click; held for one call only
local OWN_CHILD_LIMIT = 50         -- buttons made under our own window, per session

local holder = CreateFrame("Frame", nil, UIParent)      -- hidden home for spare frames
holder:Hide()

local ownWindow = CreateFrame("Frame", "PocketProbeWindow", UIParent)
ownWindow:SetSize(8, 8)
ownWindow:SetPoint("TOP", UIParent, "TOP", 0, 0)
ownWindow:Hide()

local escapeWindow = CreateFrame("Frame", ESCAPE_NAME, UIParent)
escapeWindow:SetSize(8, 8)
escapeWindow:SetPoint("TOP", UIParent, "TOP", 0, 0)
escapeWindow:Hide()
local escapeListed = false

local keyOwner = CreateFrame("Frame", nil, holder)
local keyButton = CreateFrame("Button", KEY_BUTTON_NAME, holder)
local markButton = CreateFrame("Button", nil, holder)

local ownChildren = 0
local children = {}                -- [which] = our one button under that Blizzard window

local function Orphan(child)
    if type(child) ~= "table" then return end
    child:Hide()
    if Has(child, "SetParent") then child:SetParent(holder) end
end

---------------------------------------------------------------------------
-- Chat box
---------------------------------------------------------------------------

local function ActiveBox()
    local fn = Find("ChatFrameUtil.GetActiveWindow")
    if type(fn) ~= "function" then return nil end
    local box = fn()
    if IsSecret(box) or type(box) ~= "table" then return nil end
    return box
end

local function ChatFrame()
    local frame = Find("DEFAULT_CHAT_FRAME")
    if type(frame) ~= "table" then frame = Find("ChatFrame1") end
    return type(frame) == "table" and frame or nil
end

local function SendBox()
    local box = Find("ChatFrameUtil.ChooseBoxForSend")()
    if IsSecret(box) or type(box) ~= "table" then return nil end
    return box
end

local BUSY = "the chat box was already open (left alone)"

-- Closes the chat box again if this trial touched it.
local function CloseChat(state)
    if not state.touched then return end
    local close = Find("ChatFrameUtil.DeactivateChat")
    if type(close) ~= "function" then return end
    local box = ActiveBox() or state.box
    if box and (ActiveBox() ~= nil or Shown(box)) then close(box) end
end

local function OpenedOk()
    local active = ActiveBox()
    return active ~= nil and Shown(active)
end

Add({
    id = "chat.open", area = "Chat box", label = "Open the chat box", kind = "action", clean = true, risky = true,
    needs = { "ChatFrameUtil.OpenChat", "ChatFrameUtil.GetActiveWindow" },
    run = function(state)
        if ActiveBox() then return false, BUSY end
        state.touched = true
        local box = Find("ChatFrameUtil.OpenChat")()
        if type(box) == "table" and not IsSecret(box) then state.box = box end
        return OpenedOk()
    end,
    undo = CloseChat,
})

Add({
    id = "chat.openframe", area = "Chat box", label = "Open the chat box on a named chat frame", kind = "action", clean = true,
    risky = true,
    needs = { "ChatFrameUtil.OpenChat", "ChatFrameUtil.GetActiveWindow" },
    run = function(state)
        local frame = ChatFrame()
        if not frame then return "missing", "ChatFrame1" end
        if ActiveBox() then return false, BUSY end
        state.touched = true
        local box = Find("ChatFrameUtil.OpenChat")(nil, frame)
        if type(box) == "table" and not IsSecret(box) then state.box = box end
        return OpenedOk()
    end,
    undo = CloseChat,
})

Add({
    id = "chat.focus", area = "Chat box", label = "Give the chat edit box focus", kind = "action", clean = true, risky = true,
    needs = { "ChatFrameUtil.ChooseBoxForSend", "ChatFrameUtil.GetActiveWindow" },
    run = function(state)
        if ActiveBox() then return false, BUSY end
        local box = SendBox()
        if not box then return false, "no chat edit box" end
        if not Has(box, "SetFocus") then return "missing", "EditBox:SetFocus" end
        if not Has(box, "HasFocus") then return "missing", "EditBox:HasFocus" end
        state.touched, state.box = true, box
        if not Shown(box) then box:Show() end
        box:SetFocus()
        local focused = box:HasFocus()
        if IsSecret(focused) then return false, "focus unreadable" end
        return focused and true or false
    end,
    undo = function(state)
        local box = state.box
        if not state.touched or not box then return end
        if Has(box, "ClearFocus") then box:ClearFocus() end
        CloseChat(state)
    end,
})

Add({
    id = "chat.type", area = "Chat box", label = "Set the chat type without opening the box", kind = "action", clean = true,
    needs = { "ChatFrameUtil.ChooseBoxForSend", "ChatFrameUtil.GetActiveWindow" },
    run = function(state)
        if ActiveBox() then return false, BUSY end
        local box = SendBox()
        if not box then return false, "no chat edit box" end
        if not Has(box, "SetChatType") then return "missing", "EditBox:SetChatType" end
        if not Has(box, "GetChatType") then return "missing", "EditBox:GetChatType" end
        local old = Str(box:GetChatType())
        if not old then return false, "chat type unreadable" end
        local new = (old == "SAY") and "YELL" or "SAY"
        state.box, state.old = box, old
        box:SetChatType(new)
        return Str(box:GetChatType()) == new
    end,
    undo = function(state)
        if state.box and state.old then state.box:SetChatType(state.old) end
    end,
})

Add({
    id = "chat.close", area = "Chat box", label = "Close the chat box again", kind = "action", clean = true, risky = true,
    needs = { "ChatFrameUtil.OpenChat", "ChatFrameUtil.GetActiveWindow", "ChatFrameUtil.DeactivateChat" },
    run = function(state)
        if ActiveBox() then return false, BUSY end
        state.touched = true
        Find("ChatFrameUtil.OpenChat")()
        local box = ActiveBox()
        if not box then return false, "the chat box did not open, so closing was not tried" end
        state.box = box
        Find("ChatFrameUtil.DeactivateChat")(box)
        return ActiveBox() == nil
    end,
    undo = CloseChat,
})

---------------------------------------------------------------------------
-- Our own windows
---------------------------------------------------------------------------

Add({
    id = "own.show", area = "Our own windows", label = "Show and hide a plain window of ours", kind = "action",
    run = function()
        ownWindow:Show()
        local shown = Shown(ownWindow)
        ownWindow:Hide()
        return shown and not Shown(ownWindow)
    end,
    undo = function() ownWindow:Hide() end,
})

Add({
    id = "own.escape", area = "Our own windows", label = "Show a window of ours registered for Escape", kind = "action",
    needs = { "UISpecialFrames" },
    run = function()
        local list = Find("UISpecialFrames")
        if type(list) ~= "table" then return "missing", "UISpecialFrames" end
        if not escapeListed then
            list[#list + 1] = ESCAPE_NAME
            escapeListed = true
        end
        escapeWindow:Show()
        return Shown(escapeWindow)
    end,
    undo = function() escapeWindow:Hide() end,
})

Add({
    id = "own.create", area = "Our own windows", label = "Create a button under our own window", kind = "action",
    ready = function()
        if ownChildren >= OWN_CHILD_LIMIT then return false, "enough buttons made this session" end
        return true
    end,
    run = function(state)
        ownChildren = ownChildren + 1
        local child = CreateFrame("Button", nil, ownWindow)
        state.child = child
        if type(child) ~= "table" then return false end
        return ParentOf(child) == ownWindow
    end,
    undo = function(state)
        if type(state.child) == "table" then state.child:Hide() end
    end,
})

---------------------------------------------------------------------------
-- Blizzard windows. One button of ours per window per session: frames
-- cannot be deleted, so "create" runs once and "attach" reuses that button.
---------------------------------------------------------------------------

local WINDOWS = {
    { key = "map", what = "the world map", find = function() return Find("WorldMapFrame"), "WorldMapFrame" end },
    { key = "bag", what = "the bag", find = function()
        return Find("ContainerFrameCombinedBags") or Find("ContainerFrame1"), "ContainerFrameCombinedBags"
    end },
    -- The chat frame's two are on the Chat box tab (probe 0.7.0, to make room).
    { key = "chat", what = "the chat frame", area = "Chat box", find = function() return Find("ChatFrame1"), "ChatFrame1" end },
}

local function BagFrame()
    local frame = WINDOWS[2].find()
    return type(frame) == "table" and frame or nil
end

for _, w in ipairs(WINDOWS) do
    local key, find = w.key, w.find

    Add({
        id = "win." .. key .. ".create", area = w.area or "Blizzard windows", label = "Create a button under " .. w.what,
        kind = "action", clean = true,
        ready = function()
            if children[key] then return false, "its one button for this session is already made" end
            return true
        end,
        run = function(state)
            local parent, name = find()
            if type(parent) ~= "table" then return "missing", name end
            local child = CreateFrame("Button", nil, parent)
            if type(child) ~= "table" then return false end
            children[key], state.child = child, child
            return ParentOf(child) == parent
        end,
        undo = function(state) Orphan(state.child) end,
    })

    Add({
        id = "win." .. key .. ".attach", area = w.area or "Blizzard windows", label = "Put our existing button back under " .. w.what,
        kind = "action",
        ready = function()
            if not children[key] then return false, "no button of ours was made under it this session" end
            return true
        end,
        run = function(state)
            local parent, name = find()
            if type(parent) ~= "table" then return "missing", name end
            local child = children[key]
            if not Has(child, "SetParent") then return "missing", "Button:SetParent" end
            state.child = child
            child:SetParent(parent)
            return ParentOf(child) == parent
        end,
        undo = function(state) Orphan(state.child) end,
    })
end

Add({
    id = "bag.toggle", area = "Bags and vendor", label = "Open and close the bags", kind = "action", clean = true, risky = true,
    needs = { "OpenAllBags", "CloseAllBags", "IsAnyBagOpen" },
    run = function(state)
        local open = Find("IsAnyBagOpen")()
        if IsSecret(open) then return false, "bag state unreadable" end
        state.wasOpen = open and true or false
        state.touched = true
        if state.wasOpen then Find("CloseAllBags")() else Find("OpenAllBags")() end
        local now = Find("IsAnyBagOpen")()
        if IsSecret(now) then return false, "bag state unreadable" end
        return (now and true or false) ~= state.wasOpen
    end,
    undo = function(state)
        if not state.touched then return end
        if state.wasOpen then Find("OpenAllBags")() else Find("CloseAllBags")() end
    end,
})

Add({
    id = "bag.move", area = "Bags and vendor", label = "Move the bag", kind = "action",
    run = function(state)
        local bag = BagFrame()
        if not bag then return "missing", "ContainerFrameCombinedBags" end
        local point, rel, relPoint, x, y = bag:GetPoint(1)
        if IsSecret(point) or IsSecret(rel) or IsSecret(relPoint) then return false, "bag position unreadable" end
        x, y = Num(x), Num(y)
        if type(point) ~= "string" or not x or not y then return false, "the bag has no position yet" end
        state.bag, state.point = bag, { point, rel, relPoint, x, y }
        bag:SetPoint(point, rel, relPoint, x + 1, y)
        local _, _, _, x2 = bag:GetPoint(1)
        x2 = Num(x2)
        if not x2 then return false, "bag position unreadable" end
        return x2 ~= x
    end,
    undo = function(state)
        local p = state.point
        if p then state.bag:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end,
})

Add({
    id = "bag.scale", area = "Bags and vendor", label = "Resize the bag", kind = "action",
    run = function(state)
        local bag = BagFrame()
        if not bag then return "missing", "ContainerFrameCombinedBags" end
        local scale = Num(bag:GetScale())
        if not scale or scale <= 0 then return false, "bag size unreadable" end
        state.bag, state.scale = bag, scale
        bag:SetScale(scale * 0.98)
        local now = Num(bag:GetScale())
        if not now then return false, "bag size unreadable" end
        return now ~= scale
    end,
    undo = function(state)
        if state.scale then state.bag:SetScale(state.scale) end
    end,
})

---------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------

Add({
    id = "pad.bind", area = "Controller and layout", label = "Take a controller button for ourselves and give it back",
    kind = "action", clean = true, noFight = true,
    needs = { "SetOverrideBindingClick", "ClearOverrideBindings" },
    run = function(state)
        state.touched = true
        Find("SetOverrideBindingClick")(keyOwner, true, TEST_KEY, KEY_BUTTON_NAME, "LeftButton")
        local read = Find("GetBindingAction")
        if type(read) ~= "function" then return nil end
        local action = Str(read(TEST_KEY, true))
        if not action then return false, "binding unreadable" end
        return action:find(KEY_BUTTON_NAME, 1, true) ~= nil
    end,
    undo = function(state)
        if state.touched then Find("ClearOverrideBindings")(keyOwner) end
    end,
})

Add({
    id = "pad.mark", area = "Controller and layout", label = "Mark one of our buttons for the controller's navigation",
    kind = "action", clean = true, noFight = true,
    needs = { "SmartNavigation_MarkFrameIgnored", "SmartNavigation_ClearIgnoreStatus" },
    run = function(state)
        state.touched = true
        Find("SmartNavigation_MarkFrameIgnored")(markButton)
        local mark = markButton.smartNavigationIgnored
        if IsSecret(mark) then return false, "mark unreadable" end
        return mark == true
    end,
    undo = function(state)
        if state.touched then Find("SmartNavigation_ClearIgnoreStatus")(markButton) end
    end,
})

---------------------------------------------------------------------------
-- Bags, settings, layout
---------------------------------------------------------------------------

Add({
    id = "bags.sort", area = "Bags and vendor", label = "Sort the bags", kind = "action",
    needs = { "C_Container.SortBags" },
    run = function()
        Find("C_Container.SortBags")()
        return nil
    end,
})

local BAG_SETTING = "combinedBags"

Add({
    id = "cvar.write", area = "Controller and layout", label = "Read the combined-bags setting and write it back unchanged", kind = "action",
    needs = { "C_CVar.GetCVar", "C_CVar.SetCVar" },
    run = function()
        local value = Find("C_CVar.GetCVar")(BAG_SETTING)
        if IsSecret(value) then return false, "setting unreadable" end
        if type(value) ~= "string" then return false, "this client has no combined-bags setting" end
        local ok = Find("C_CVar.SetCVar")(BAG_SETTING, value)
        if IsSecret(ok) then return false, "answer unreadable" end
        return ok and true or false
    end,
})

local function EditModeOpen()
    local manager = Find("EditModeManagerFrame")
    if type(manager) ~= "table" then return false end
    if Shown(manager) then return true end
    if Has(manager, "IsEditModeActive") then
        local active = manager:IsEditModeActive()
        if not IsSecret(active) and active then return true end
    end
    return false
end

-- The index of the layout in use. The game counts its own preset layouts
-- first, and both GetLayouts().activeLayout and SetActiveLayout use that
-- same numbering, so the number read is the number to write.
local function ActiveLayout()
    local info = Find("C_EditMode.GetLayouts")()
    if IsSecret(info) or type(info) ~= "table" then return nil end
    return Num(info.activeLayout)
end

Add({
    id = "layout.read", area = "Controller and layout", label = "Read the Edit Mode layouts", kind = "value",
    needs = { "C_EditMode.GetLayouts" },
    read = function(c)
        local info = Find("C_EditMode.GetLayouts")()
        if c:add("layouts", info) ~= "readable" or type(info) ~= "table" then return end
        c:add("activeLayout", info.activeLayout)
        c:add("list", info.layouts)
    end,
})

Add({
    id = "layout.set", area = "Controller and layout", label = "Set the active layout to the one already active", kind = "action", clean = true,
    risky = true,
    needs = { "C_EditMode.GetLayouts", "C_EditMode.SetActiveLayout" },
    run = function()
        if EditModeOpen() then return false, "Edit Mode open" end
        local active = ActiveLayout()
        if not active then return false, "active layout unreadable" end
        Find("C_EditMode.SetActiveLayout")(active)
        return ActiveLayout() == active
    end,
})

---------------------------------------------------------------------------
-- Controller layout: frame sizes, protection, the bar settings, and moves
-- the layout feature needs to know are allowed. Value trials note the
-- numbers they read as our own text (c:note); that is how a size gets to
-- the saved file.
---------------------------------------------------------------------------

local BAR = "GamepadMainActionBarFrame"
local ANCHORS = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }

-- A frame by its dotted name from the globals, or nil.
local function FrameAt(path)
    local f = Find(path)
    if type(f) == "table" then return f end
end

-- A number a frame method answers, or nil (never raises).
local function Dim(frame, method)
    if type(frame[method]) ~= "function" then return nil end
    local ok, v = pcall(frame[method], frame)
    if not ok then return nil end
    return Num(v)
end

local MAIN_BAR = BAR .. ".PageUnit.TopCenteredAnchor.Bar"

-- One of the main bar's eight spell buttons (1-4 the d-pad, 5-8 the face
-- buttons), or nil. The list is the bar's own: read, never written.
local function MainButton(i)
    local bar = FrameAt(MAIN_BAR)
    local list = bar and bar.actionButtons
    if IsSecret(list) or type(list) ~= "table" then return nil end
    local b = list[i]
    if type(b) == "table" then return b end
end

local SIZE_LIST = {
    { "MinimapCluster", "MinimapCluster" }, { "PlayerFrame", "PlayerFrame" }, { "PetFrame", "PetFrame" },
    { "TargetFrame", "TargetFrame" }, { "ChatFrame1", "ChatFrame1" },
    { "SwingTimerMainHandFrame", "SwingTimerMainHandFrame" }, { BAR, BAR },
}
for _, a in ipairs(ANCHORS) do SIZE_LIST[#SIZE_LIST + 1] = { a, BAR .. ".PageUnit." .. a } end
SIZE_LIST[#SIZE_LIST + 1] = { "TopCenteredAnchor.Bar", MAIN_BAR }
-- Probe 0.4.0, second round: the rest of what the layout places.
for _, entry in ipairs({
    { "BuffFrame", "BuffFrame" }, { "DebuffFrame", "DebuffFrame" }, { "ObjectiveTrackerFrame", "ObjectiveTrackerFrame" },
    { "MainStatusTrackingBarContainer", "MainStatusTrackingBarContainer" },
    { "LeftClassAction", BAR .. ".PageUnit.LeftClassAction" }, { "RightClassAction", BAR .. ".PageUnit.RightClassAction" },
    { "GamepadPetActionFlyout", "GamepadPetActionFlyout" },
    { "TopCenteredAnchor.Bar button 1", function() return MainButton(1) end },
}) do SIZE_LIST[#SIZE_LIST + 1] = entry end
-- Probe 0.5.0: the map's container (Edit Mode's map size is its scale, so
-- it tells which size a measurement was taken at), the map, the other bars.
SIZE_LIST[#SIZE_LIST + 1] = { "MinimapCluster.MinimapContainer", "MinimapCluster.MinimapContainer" }
SIZE_LIST[#SIZE_LIST + 1] = { "Minimap", "Minimap" }
for _, a in ipairs({ "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }) do
    SIZE_LIST[#SIZE_LIST + 1] = { a .. ".Bar", BAR .. ".PageUnit." .. a .. ".Bar" }
end
SIZE_LIST[#SIZE_LIST + 1] = { "UIParent", "UIParent" }

Add({
    id = "layout.sizes", area = "Values", label = "Read the size and scale of the screen's frames and the bars", kind = "value",
    read = function(c)
        for _, entry in ipairs(SIZE_LIST) do
            local where = entry[2]
            local name, frame = entry[1], (type(where) == "function") and where() or FrameAt(where)
            if not frame then
                c:add(name, nil)
                c:note(name .. " missing")
            else
                local w, h, s = Dim(frame, "GetWidth"), Dim(frame, "GetHeight"), Dim(frame, "GetScale")
                c:add(name .. " w", w); c:add(name .. " h", h); c:add(name .. " scale", s)
                c:note(name .. " w=" .. (w and (math.floor(w * 10 + 0.5) / 10) or "?")
                    .. " h=" .. (h and (math.floor(h * 10 + 0.5) / 10) or "?")
                    .. " scale=" .. (s and (math.floor(s * 100 + 0.5) / 100) or "?"))
            end
        end
    end,
})

Add({
    id = "bars.protected", area = "Values", label = "Ask whether the gamepad bars are protected frames", kind = "value",
    read = function(c)
        local list = { { BAR, BAR }, { "PageUnit", BAR .. ".PageUnit" } }
        for _, a in ipairs(ANCHORS) do list[#list + 1] = { a, BAR .. ".PageUnit." .. a } end
        for _, a in ipairs(ANCHORS) do list[#list + 1] = { a .. ".Bar", BAR .. ".PageUnit." .. a .. ".Bar" } end
        for _, entry in ipairs(list) do
            local name, frame = entry[1], FrameAt(entry[2])
            if not frame or type(frame.IsProtected) ~= "function" then
                c:add(name, nil)
                c:note(name .. " missing")
            else
                local ok, protected, explicit = pcall(frame.IsProtected, frame)
                if not ok then
                    c:add(name, nil)
                    c:note(name .. " error")
                else
                    c:add(name .. " protected", protected)
                    c:add(name .. " explicit", explicit)
                    local function yn(v) if IsSecret(v) then return "secret" end return v and "yes" or "no" end
                    c:note(name .. " protected=" .. yn(protected) .. " explicit=" .. yn(explicit))
                end
            end
        end
    end,
})

Add({
    id = "bars.settings", area = "Values", label = "Read the gamepad bar settings and count the saved layouts", kind = "value",
    needs = { "C_EditMode.GetLayouts" },
    read = function(c)
        local bar = FrameAt(BAR)
        for _, field in ipairs({ "useCompactLayout", "showEmptyBars", "shouldExpand" }) do
            local v = bar and bar[field]
            c:add(field, v)
            if v == nil then c:note(field .. " not set")
            elseif IsSecret(v) then c:note(field .. " secret")
            else c:note(field .. "=" .. (v and "yes" or "no")) end
        end
        local info = Find("C_EditMode.GetLayouts")()
        if c:add("layouts", info) ~= "readable" or type(info) ~= "table" or type(info.layouts) ~= "table" then return end
        local account, character = Find("Enum.EditModeLayoutType.Account"), Find("Enum.EditModeLayoutType.Character")
        local nAccount, nCharacter = 0, 0
        for _, layout in ipairs(info.layouts) do
            local kind = type(layout) == "table" and layout.layoutType
            if not IsSecret(kind) and kind ~= nil then
                if kind == account then nAccount = nAccount + 1 elseif kind == character then nCharacter = nCharacter + 1 end
            end
        end
        c:add("account layouts", nAccount); c:add("character layouts", nCharacter)
        c:note("account layouts=" .. nAccount); c:note("character layouts=" .. nCharacter)
    end,
})

-- ready(): in a fight these are not tried (nothing is saved for them).
local function NotInCombat()
    local fn = Find("InCombatLockdown")
    if type(fn) == "function" then
        local ok, fighting = pcall(fn)
        if ok and not IsSecret(fighting) and fighting then return false, "in combat" end
    end
    return true
end

-- The left bar anchor, or nil and the name that is missing.
local function LeftAnchor()
    return FrameAt(BAR .. ".PageUnit.LeftCenteredAnchor")
end

Add({
    id = "bars.move", area = "Blizzard windows", label = "Set the left bar to the place it already has", kind = "action",
    risky = true,
    ready = NotInCombat,
    run = function()
        local anchor = LeftAnchor()
        if not anchor then return false, "the left bar is not there" end
        if type(anchor.GetPoint) ~= "function" or type(anchor.SetPoint) ~= "function"
            or type(anchor.ClearAllPoints) ~= "function" then return "missing", "frame point methods" end
        -- Edit Mode's Compact setting anchors it with two points; re-setting only the first would change it.
        if type(anchor.GetNumPoints) == "function" and Num(anchor:GetNumPoints()) ~= 1 then
            return false, "more than one anchor point"
        end
        local point, rel, relPoint, x, y = anchor:GetPoint(1)
        if IsSecret(point) or IsSecret(rel) or IsSecret(relPoint) then return false, "bar position unreadable" end
        x, y = Num(x), Num(y)
        if type(point) ~= "string" or not x or not y then return false, "the left bar has no position" end
        anchor:ClearAllPoints()
        anchor:SetPoint(point, rel, relPoint, x, y)
        local point2, rel2, relPoint2, x2, y2 = anchor:GetPoint(1)
        if IsSecret(point2) or IsSecret(rel2) or IsSecret(relPoint2) then return false, "bar position unreadable" end
        return point2 == point and rel2 == rel and relPoint2 == relPoint and Num(x2) == x and Num(y2) == y
    end,
})

Add({
    id = "bars.scale", area = "Blizzard windows", label = "Set the left bar's size to the size it already has", kind = "action",
    risky = true,
    ready = NotInCombat,
    run = function()
        local anchor = LeftAnchor()
        if not anchor then return false, "the left bar is not there" end
        if type(anchor.GetScale) ~= "function" or type(anchor.SetScale) ~= "function" then return "missing", "frame scale methods" end
        local scale = Num(anchor:GetScale())
        if not scale or scale <= 0 then return false, "bar size unreadable" end
        anchor:SetScale(scale)
        return Num(anchor:GetScale()) == scale
    end,
})

Add({
    id = "layout.save", area = "Controller and layout", label = "Save the layouts exactly as they are", kind = "action", clean = true,
    risky = true,
    needs = { "C_EditMode.GetLayouts", "C_EditMode.SaveLayouts" },
    ready = NotInCombat,
    run = function()
        if EditModeOpen() then return false, "Edit Mode open" end
        local info = Find("C_EditMode.GetLayouts")()
        if IsSecret(info) or type(info) ~= "table" or type(info.layouts) ~= "table" then return false, "layouts unreadable" end
        local active, count = Num(info.activeLayout), #info.layouts
        if not active then return false, "active layout unreadable" end
        -- The list the game sends: the three presets first, then the saved layouts.
        local manager = Find("EditModePresetLayoutManager")
        if not Has(manager, "GetCopyOfPresetLayouts") then return false, "no preset list" end
        local ok, presets = pcall(manager.GetCopyOfPresetLayouts, manager)
        if not ok or IsSecret(presets) or type(presets) ~= "table" then return false, "no preset list" end
        local list = {}
        for _, layout in ipairs(presets) do list[#list + 1] = layout end
        for _, layout in ipairs(info.layouts) do list[#list + 1] = layout end
        Find("C_EditMode.SaveLayouts")({ layouts = list, activeLayout = info.activeLayout })
        local after = Find("C_EditMode.GetLayouts")()
        if IsSecret(after) or type(after) ~= "table" or type(after.layouts) ~= "table" then return false, "layouts unreadable afterwards" end
        return Num(after.activeLayout) == active and #after.layouts == count
    end,
})

---------------------------------------------------------------------------
-- Probe 0.4.0, second round: what a flat strip of our own under the map
-- would need (the game plan's "Flat strip for the main bar"). Can the main
-- bar's spells be read in a fight, can a bar be faded in a fight, does a
-- controller press still cast with the main bar off screen, and can a frame
-- of ours show the game's own controller-button pictures.
---------------------------------------------------------------------------

-- Reading the main bar's eight spells: only how many of each value were
-- readable, secret, empty or raised an error is kept, never a value.
local SPELL_FIELDS = { "slot", "has", "icon", "cooldown", "cd start", "cd duration", "count", "usable" }

-- Counting what was read of one field over several buttons. take(field, ok,
-- value) counts one value by class; the first secret one (else the first
-- readable one) is what the field's class is taken from.
local function Tally()
    local tally = {}
    local function take(field, ok, v)
        local t = tally[field]
        if not t then
            t = { readable = 0, secret = 0, ["nil"] = 0, error = 0 }
            tally[field] = t
        end
        if not ok then
            t.error = t.error + 1
            return
        end
        local class = P.Class(v)
        t[class] = t[class] + 1
        -- Flags, not the sample itself, are compared: a secret may not be.
        if class == "secret" and not t.secretSeen then t.sample, t.secretSeen = v, true
        elseif class == "readable" and not t.secretSeen and not t.readableSeen then t.sample, t.readableSeen = v, true end
    end
    return tally, take
end

-- One field's class and its counts ("icon readable 3 secret 1") go to the result.
local function TallyNote(c, tally, field)
    local t = tally[field]
    if not t then return end
    c:add(field, t.sample)
    local parts = {}
    for _, class in ipairs({ "readable", "secret", "nil", "error" }) do
        if t[class] > 0 then parts[#parts + 1] = class .. " " .. t[class] end
    end
    c:note(field .. " " .. tconcat(parts, " "))
end

Add({
    id = "bars.spells", area = "Blizzard windows", label = "Read the main bar's 8 spells (run it in a fight too)",
    kind = "value", fight = true,
    needs = { "C_ActionBar.HasAction", "C_ActionBar.GetActionTexture", "C_ActionBar.GetActionCooldown",
        "C_ActionBar.GetActionDisplayCount", "C_ActionBar.IsUsableAction" },
    read = function(c)
        local tally, take = Tally()
        local has, texture, cooldown = Find("C_ActionBar.HasAction"), Find("C_ActionBar.GetActionTexture"), Find("C_ActionBar.GetActionCooldown")
        local count, usable = Find("C_ActionBar.GetActionDisplayCount"), Find("C_ActionBar.IsUsableAction")
        local buttons, filled = 0, 0
        for i = 1, 8 do
            local b = MainButton(i)
            if b then
                buttons = buttons + 1
                local slot = b.action
                take("slot", true, slot)
                slot = Num(slot)
                if slot and slot >= 1 then
                    local ok, h = pcall(has, slot)
                    take("has", ok, h)
                    if ok and not IsSecret(h) and h then
                        filled = filled + 1
                        take("icon", pcall(texture, slot))
                        local okc, info = pcall(cooldown, slot)
                        take("cooldown", okc, info)
                        if okc and not IsSecret(info) and type(info) == "table" then
                            take("cd start", true, info.startTime)
                            take("cd duration", true, info.duration)
                        end
                        take("count", pcall(count, slot))
                        take("usable", pcall(usable, slot))
                    end
                end
            end
        end
        if buttons == 0 then
            c:add("buttons", nil)
            c:note("the main bar's buttons are not there")
            return
        end
        c:note("buttons " .. buttons .. ", with a spell " .. filled)
        for _, field in ipairs(SPELL_FIELDS) do TallyNote(c, tally, field) end
        c:note("issecretvalue " .. (type(issecretvalue) == "function" and "on this client" or "missing"))
    end,
})

-- Fading a bar: the left bar's see-through set to the value it already has.
-- Tried in a fight too (that is the question); risky like the other bar moves.
Add({
    id = "bars.alpha", area = "Blizzard windows", label = "Set the left bar's see-through to what it has (run it in a fight too)",
    kind = "action", risky = true, fight = true,
    run = function(state)
        local anchor = LeftAnchor()
        if not anchor then return false, "the left bar is not there" end
        if type(anchor.GetAlpha) ~= "function" or type(anchor.SetAlpha) ~= "function" then return "missing", "frame alpha methods" end
        local alpha = anchor:GetAlpha()
        if IsSecret(alpha) then return false, "see-through unreadable (secret)" end
        alpha = Num(alpha)
        if not alpha then return false, "see-through unreadable" end
        state.anchor, state.alpha = anchor, alpha
        anchor:SetAlpha(alpha)
        local now = anchor:GetAlpha()
        if IsSecret(now) then return P.CANT_TELL, "see-through unreadable afterwards" end
        now = Num(now)
        return now ~= nil and math.abs(now - alpha) < 0.001
    end,
    undo = function(state)
        if state.anchor then state.anchor:SetAlpha(state.alpha) end
    end,
})

-- Probe 0.5.0: a real change. The left bar's see-through set to nothing and
-- read back, then the old value written back whatever happened.
Add({
    id = "bars.fade", area = "Blizzard windows", label = "Fade the left bar to nothing and back (run it in a fight)",
    kind = "action", risky = true, fight = true,
    run = function(state)
        local anchor = LeftAnchor()
        if not anchor then return false, "the left bar is not there" end
        if type(anchor.GetAlpha) ~= "function" or type(anchor.SetAlpha) ~= "function" then return "missing", "frame alpha methods" end
        local alpha = anchor:GetAlpha()
        if IsSecret(alpha) then return false, "see-through unreadable (secret)" end
        alpha = Num(alpha)
        if not alpha then return false, "see-through unreadable" end
        state.anchor, state.alpha = anchor, alpha
        anchor:SetAlpha(0)
        local now = anchor:GetAlpha()
        if IsSecret(now) then return P.CANT_TELL, "see-through unreadable afterwards" end
        now = Num(now)
        return now ~= nil and now < 0.001
    end,
    undo = function(state)
        if state.anchor then state.anchor:SetAlpha(state.alpha) end
    end,
})

-- Parking the main bar off screen: a guided trial. Start moves the top bar
-- anchor far above the screen (out of a fight only), the player presses a
-- spell button and answers, and the anchor goes back. The point it had is
-- kept here, never in the saved table (it holds a frame). A reload puts the
-- bar back by itself; a fight that starts while it is parked leaves it parked
-- until the fight ends (no Blizzard frame is moved in a fight).
local PARK_UP = 3000
local parked                     -- { anchor, point, rel, relPoint, x, y, parkedY } while parked

local function TopAnchor()
    return FrameAt(BAR .. ".PageUnit.TopCenteredAnchor")
end

-- true / false whether the main bar's bottom edge is above the screen's top, or nil.
local function BarOffScreen()
    local bar, screen = FrameAt(MAIN_BAR), FrameAt("UIParent")
    if not bar or not screen then return nil end
    local bottom, top = Dim(bar, "GetBottom"), Dim(screen, "GetTop")
    local bs, ss = Dim(bar, "GetEffectiveScale") or 1, Dim(screen, "GetEffectiveScale") or 1
    if not bottom or not top then return nil end
    return bottom * bs > top * ss
end

-- Probe 0.5.0: where the bars are, as our own text: the four bars and the
-- bars that ride on the top anchor. For each: shown or hidden (as the player
-- sees it), its centre in screen units, on or off the screen; then how many
-- are shown and on the screen. Taken just before and just after the park.
local SNAPSHOT_BARS = {
    { "top", MAIN_BAR }, { "left", BAR .. ".PageUnit.LeftCenteredAnchor.Bar" },
    { "right", BAR .. ".PageUnit.RightCenteredAnchor.Bar" }, { "bottom", BAR .. ".PageUnit.BottomCenteredAnchor.Bar" },
    { "possess", BAR .. ".PageUnit.TopCenteredAnchor.PossessBar" }, { "stance", BAR .. ".PageUnit.TopCenteredAnchor.StanceBar" },
    { "friendly", BAR .. ".PageUnit.FriendlyTargetingActionBar" }, { "hostile", BAR .. ".PageUnit.HostileTargetingActionBar" },
    { "shortcuts", BAR .. ".PageUnit.ShortcutsActionBar" },
}

-- true / false as the player sees the frame (its parents count too), or nil.
local function Seen(frame)
    local method = Has(frame, "IsVisible") and "IsVisible" or (Has(frame, "IsShown") and "IsShown")
    if not method then return nil end
    local ok, v = pcall(frame[method], frame)
    if not ok or IsSecret(v) then return nil end
    return v and true or false
end

local function BarsSnapshot()
    local screen = FrameAt("UIParent")
    local sw, sh = screen and Dim(screen, "GetWidth"), screen and Dim(screen, "GetHeight")
    local ss = screen and Dim(screen, "GetEffectiveScale") or 1
    local parts, count = {}, 0
    for _, entry in ipairs(SNAPSHOT_BARS) do
        local name, frame = entry[1], FrameAt(entry[2])
        if not frame then
            parts[#parts + 1] = name .. " missing"
        else
            local seen = Seen(frame)
            local x, y, on
            if Has(frame, "GetCenter") then
                local ok, cx, cy = pcall(frame.GetCenter, frame)
                if ok then x, y = Num(cx), Num(cy) end
            end
            if x and y then
                local scale = (Dim(frame, "GetEffectiveScale") or 1) / ss
                x, y = x * scale, y * scale
                if sw and sh then on = x >= 0 and x <= sw and y >= 0 and y <= sh end
            end
            parts[#parts + 1] = name .. " " .. (seen == nil and "shown ?" or (seen and "shown" or "hidden"))
                .. " " .. ((x and y) and (floor(x + 0.5) .. "," .. floor(y + 0.5)) or "?,?")
                .. " " .. (on == nil and "on screen ?" or (on and "on screen" or "off screen"))
            if seen and on then count = count + 1 end
        end
    end
    parts[#parts + 1] = "bars shown and on screen: " .. count
    return tconcat(parts, "; ")
end

Add({
    id = "bars.park", area = "Blizzard windows", label = "Park the main bar off screen, then press a spell button",
    short = "Park the main bar", kind = "guided", manual = true, risky = true, hold = "the main bar",
    shots = true, big = "Main bar parked. Press a spell, then tap Probe.",
    ready = function()
        local ok, why = NotInCombat()
        if not ok then return false, why end
        if EditModeOpen() then return false, "Edit Mode open" end
        return true
    end,
    start = "Start",
    ask = "The main bar is off screen now and this window has closed. Press a d-pad or face button that holds a "
        .. "spell you can use here (a buff, a heal, or an attack with a target), then tap Probe and answer. "
        .. "Stay out of fights until you answer.",
    closePanel = true,             -- the panel holds the d-pad and A while open: closed on Start
    answers = { "Spell cast", "Nothing happened" },
    apply = function()
        local anchor = TopAnchor()
        if not anchor then return "missing", "the top bar anchor" end
        if type(anchor.GetPoint) ~= "function" or type(anchor.SetPoint) ~= "function"
            or type(anchor.ClearAllPoints) ~= "function" then return "missing", "frame point methods" end
        if type(anchor.GetNumPoints) == "function" and Num(anchor:GetNumPoints()) ~= 1 then
            return false, "more than one anchor point (Edit Mode's Compact setting?)"
        end
        local point, rel, relPoint, x, y = anchor:GetPoint(1)
        if IsSecret(point) or IsSecret(rel) or IsSecret(relPoint) then return false, "bar position unreadable" end
        x, y = Num(x), Num(y)
        if type(point) ~= "string" or not x or not y then return false, "the top bar has no position" end
        local before = BarsSnapshot()
        parked = { anchor = anchor, point = point, rel = rel, relPoint = relPoint, x = x, y = y, parkedX = x, parkedY = y + PARK_UP }
        anchor:ClearAllPoints()
        anchor:SetPoint(point, rel, relPoint, x, y + PARK_UP)
        -- The spot as the game stores it (it may keep offsets less precisely than Lua).
        local _, _, _, px, py = anchor:GetPoint(1)
        px, py = Num(px), Num(py)
        if px and py then parked.parkedX, parked.parkedY = px, py end
        local off = BarOffScreen()
        return true, "top bar anchor moved up " .. PARK_UP .. "; main bar off screen "
            .. (off == nil and "unknown" or (off and "yes" or "no"))
            .. "; before: " .. before .. "; after: " .. BarsSnapshot()
    end,
    -- true when nothing is left to put back; false and why otherwise.
    restore = function()
        local p = parked
        if not p then return true end
        local ok = NotInCombat()
        if not ok then return false, "in a fight: it goes back when the fight ends" end
        local anchor = p.anchor
        local function PutIt()
            anchor:ClearAllPoints()
            anchor:SetPoint(p.point, p.rel, p.relPoint, p.x, p.y)
            parked = nil
            return true
        end
        -- No point at all (a park that stopped half way): put it back.
        if type(anchor.GetNumPoints) == "function" and Num(anchor:GetNumPoints()) == 0 then return PutIt() end
        local point, rel, relPoint, x, y = anchor:GetPoint(1)
        if IsSecret(point) or IsSecret(rel) or IsSecret(relPoint) then
            return false, "its position is unreadable; a reload puts it back"
        end
        x, y = Num(x), Num(y)
        -- Put back only if it is still where we parked it (the game may have placed it since).
        if point == p.point and rel == p.rel and relPoint == p.relPoint and x and y
            and math.abs(x - p.parkedX) < 0.5 and math.abs(y - p.parkedY) < 0.5 then
            return PutIt()
        end
        parked = nil
        return true, "left where the game had put it since"
    end,
})

-- Probe 0.5.0: fading the main bar to nothing: a guided trial. After Start
-- the bar's see-through is set to 0 (in a fight too: that is part of the
-- question), the player presses a spell button and answers, and the old
-- value is written back. The bar and its old value are kept here, never in
-- the saved table. A put-back the game refuses in a fight is tried again
-- when the fight ends; a reload puts the bar back in any case.
local fadeCast = {}              -- .f = { bar, alpha } while faded (bars.fadecast)

local function Hundredths(v) return floor(v * 100 + 0.5) / 100 end

-- The main bar's see-through to 0, read back. `st` keeps the bar and its old
-- value (st.f) until they are put back.
local function FadeMain(st)
    local bar = FrameAt(MAIN_BAR)
    if not bar then return "missing", "the main bar" end
    if type(bar.GetAlpha) ~= "function" or type(bar.SetAlpha) ~= "function" then return "missing", "frame alpha methods" end
    local alpha = bar:GetAlpha()
    if IsSecret(alpha) then return false, "see-through unreadable (secret)" end
    alpha = Num(alpha)
    if not alpha then return false, "see-through unreadable" end
    st.f = { bar = bar, alpha = alpha }
    bar:SetAlpha(0)
    local now = bar:GetAlpha()
    if IsSecret(now) or not Num(now) then return false, "main bar see-through unreadable after setting it to 0" end
    if now >= 0.001 then return false, "main bar see-through still " .. Hundredths(now) .. " after setting it to 0" end
    return true, "main bar see-through " .. Hundredths(alpha) .. " -> 0"
end

-- "<words>: yes" when the main bar is still at 0, "no" when not, or nil.
local function StillFaded(st, words)
    local f = st.f
    if not f then return nil end
    local now = f.bar:GetAlpha()
    if IsSecret(now) or not Num(now) then return words .. ": unknown" end
    return words .. ": " .. (now < 0.001 and "yes" or "no")
end

-- true when nothing is left to put back; false and why otherwise.
local function UnfadeMain(st)
    local f = st.f
    if not f then return true end
    local now = f.bar:GetAlpha()
    if not IsSecret(now) and Num(now) and abs(now - f.alpha) < 0.001 then
        st.f = nil
        return true
    end
    f.bar:SetAlpha(f.alpha)
    now = f.bar:GetAlpha()
    if IsSecret(now) or not Num(now) then return false, "its see-through is unreadable; a reload puts it back" end
    if abs(now - f.alpha) < 0.001 then
        st.f = nil
        return true
    end
    if NotInCombat() then return false, "the game did not take the old value; a reload puts it back" end
    return false, "in a fight: it goes back when the fight ends"
end

Add({
    id = "bars.fadecast", area = "Blizzard windows", label = "Fade the main bar to nothing, then press a spell button",
    short = "Fade the main bar", kind = "guided", manual = true, risky = true, hold = "the main bar's see-through",
    shots = true, big = "Main bar is invisible. Press a spell, then tap Probe.",
    ready = function()
        if EditModeOpen() then return false, "Edit Mode open" end
        return true
    end,
    start = "Start",
    ask = "The main bar is invisible now and this window has closed. Press a d-pad or face button that holds a "
        .. "spell you can use here (a buff, a heal, or an attack with a target), then tap Probe and answer.",
    closePanel = true,
    answers = { "Spell cast", "Nothing happened" },
    apply = function() return FadeMain(fadeCast) end,
    -- Read once more at the answer, before the put-back: the game may have set it itself.
    atAnswer = function() return StillFaded(fadeCast, "still invisible at the answer") end,
    restore = function() return UnfadeMain(fadeCast) end,
})

-- Probe 0.7.0: the main bar invisible for the whole of the next fight, with
-- nothing to do in it (fightNext: Run.lua). Start only says so; the fight's
-- start fades the bar, its end reads it once more, puts it back and asks.
-- Meanwhile the presses on the main bar (the press hooks of Watch.lua) and
-- the player's casts are counted: counts only. Never PageUnit: a wheel puts
-- its alpha back by itself.
local fadeNext = {}              -- .f while faded (bars.fadenext)
local nextCount = { on = false, presses = 0, casts = 0, unreadable = 0, hooks = 0 }
local castsFiltered = false      -- the cast event was registered for the player only
local castFrame = CreateFrame("Frame", nil, UIParent)

castFrame:SetScript("OnEvent", P.Guard(function(_, _, unit)
    if not nextCount.on then return end
    if castsFiltered then
        nextCount.casts = nextCount.casts + 1
    elseif IsSecret(unit) then
        nextCount.unreadable = nextCount.unreadable + 1
    elseif unit == "player" then
        nextCount.casts = nextCount.casts + 1
    end
end))

-- The cast event, only while the fight is watched.
local function CountCasts(on)
    pcall(castFrame.UnregisterAllEvents, castFrame)
    nextCount.on = on
    if not on then return end
    nextCount.presses, nextCount.casts, nextCount.unreadable, nextCount.noCasts = 0, 0, 0, nil
    castsFiltered = false
    if Has(castFrame, "RegisterUnitEvent") and pcall(castFrame.RegisterUnitEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        castsFiltered = true
    elseif not pcall(castFrame.RegisterEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED") then
        nextCount.noCasts = true
    end
end

-- Called by the press hooks (Watch.lua) on every press the game shows.
P.WatchOnPress = function(name, dir)
    if nextCount.on and name == "main" and dir == "down" then nextCount.presses = nextCount.presses + 1 end
end

Add({
    id = "bars.fadenext", area = "Blizzard windows", label = "Fade the main bar for your next fight, with nothing to do in it",
    short = "Fade for next fight", kind = "guided", manual = true, risky = true, hold = "the main bar's see-through",
    fightNext = true, closePanel = true,
    startBig = "Main bar will vanish in your next fight. Just play.",
    big = "Did your spells cast while the bar was invisible?",
    ready = function()
        local ok, why = NotInCombat()
        if not ok then return false, why end
        if EditModeOpen() then return false, "Edit Mode open" end
        return true
    end,
    start = "Start",
    wait = "Your next fight makes the main bar invisible from its start to its end. Just play; the question comes "
        .. "when the fight is over.",
    ask = "The fight is over and the main bar is back. Did your spells cast while it was invisible?",
    answers = { "Yes, they cast", "No" },
    -- At Start: the press hooks, so the fight's presses can be counted.
    prepare = function()
        nextCount.hooks = P.WatchInstallPressHooks and P.WatchInstallPressHooks() or 0
        return nil
    end,
    apply = function() return FadeMain(fadeNext) end,
    onFight = function(on) CountCasts(on) end,
    atFightEnd = function()
        local parts = { StillFaded(fadeNext, "still invisible at the end") or "still invisible at the end: unknown" }
        parts[#parts + 1] = (nextCount.hooks > 0) and ("main bar presses in the fight: " .. nextCount.presses)
            or "main bar presses: not counted (no hook)"
        parts[#parts + 1] = nextCount.noCasts and "casts: not counted (no cast event)" or ("casts in the fight: " .. nextCount.casts)
        if nextCount.unreadable > 0 then parts[#parts + 1] = "casts unreadable: " .. nextCount.unreadable end
        return tconcat(parts, ", ")
    end,
    restore = function() return UnfadeMain(fadeNext) end,
})

-- Probe 0.7.0: are the wheels still seen when the four bars are faded. Start
-- fades the four bars (each read back); the player opens the pet wheel and a
-- spell wheel, then answers. The first two wheels that open are read 0.2
-- seconds later (centre and size in screen units, effective alpha, shown),
-- and one screenshot is taken half a second after the first. A spell wheel on
-- a bar is seen through PageUnit:OnFlyoutOpened; the two sub-menu wheels never
-- reach it (their buttons are on no bar), so their own frames are hooked when
-- they show. The hooks are put on at the first Start and do nothing unless
-- this trial waits. Never PageUnit's alpha: the game sets it for a wheel.
local WHEEL_BARS = { { "TopCenteredAnchor", "main" }, { "LeftCenteredAnchor", "left" },
    { "RightCenteredAnchor", "right" }, { "BottomCenteredAnchor", "both" } }
local WHEEL_FRAMES = { { "GamepadPetActionFlyout", "pet wheel" }, { "GamepadPetSpellFlyout", "pet spell wheel" } }
local WHEEL_READ, WHEEL_SHOT, WHEELS_MAX = 0.2, 0.5, 2
local wheelFaded                 -- { { bar, alpha, name }, ... } while faded
local wheels = { waiting = false, list = {} }
local wheelHooks = {}            -- [what] = true once its hook is on

local function After(seconds, fn)
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then return false end
    after(seconds, P.Guard(fn))
    return true
end

local function WheelClock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and Num(now) or nil
end

-- One wheel as our own text: "wheel 1 (pet wheel): centre 544,189, size 175 x 175, effective alpha 1, shown yes".
local function WheelText(popup, n, source)
    local screen = FrameAt("UIParent")
    local scale = (Dim(popup, "GetEffectiveScale") or 1) / ((screen and Dim(screen, "GetEffectiveScale")) or 1)
    local x, y
    if Has(popup, "GetCenter") then
        local ok, cx, cy = pcall(popup.GetCenter, popup)
        if ok then x, y = Num(cx), Num(cy) end
    end
    local w, h = Dim(popup, "GetWidth"), Dim(popup, "GetHeight")
    local function round(v) return v and tostring(floor(v * scale + 0.5)) or "?" end
    local alpha = "missing"
    if Has(popup, "GetEffectiveAlpha") then
        local a = Dim(popup, "GetEffectiveAlpha")
        alpha = a and tostring(Hundredths(a)) or "unreadable"
    end
    local shown = "?"
    if Has(popup, "IsShown") then
        local ok, v = pcall(popup.IsShown, popup)
        if ok and not IsSecret(v) then shown = v and "yes" or "no" end
    end
    return "wheel " .. n .. " (" .. source .. "): centre " .. ((x and y) and (round(x) .. "," .. round(y)) or "?")
        .. ", size " .. round(w) .. " x " .. round(h) .. ", effective alpha " .. alpha .. ", shown " .. shown
end

local function OnWheel(popup, source)
    if not wheels.waiting or #wheels.list >= WHEELS_MAX then return end
    -- One opening seen by two hooks counts once.
    local now = WheelClock()
    if wheels.lastPopup == popup and now and wheels.lastAt and now - wheels.lastAt < 1 then return end
    wheels.lastPopup, wheels.lastAt = popup, now
    local n = #wheels.list + 1
    local entry = { source = source }
    wheels.list[n] = entry
    After(WHEEL_READ, function() entry.text = WheelText(popup, n, source) end)
    if n == 1 then
        After(WHEEL_SHOT, function()
            if not wheels.waiting then return end
            local shot = Find("Screenshot")
            if type(shot) ~= "function" then
                wheels.shot = "none"
            else
                wheels.shot = pcall(shot) and "taken" or "none (the call failed)"
            end
        end)
    end
end

local function HookWheels()
    if type(hooksecurefunc) == "function" and not wheelHooks.page then
        local pu = FrameAt(BAR .. ".PageUnit")
        if pu and type(pu.OnFlyoutOpened) == "function" then
            local hook = P.Guard(function(_, button)
                if type(button) ~= "table" or IsSecret(button) then return end
                local popup = button.popup
                if type(popup) == "table" and not IsSecret(popup) then OnWheel(popup, "bar wheel") end
            end)
            if pcall(hooksecurefunc, pu, "OnFlyoutOpened", hook) then wheelHooks.page = true end
        end
    end
    for _, w in ipairs(WHEEL_FRAMES) do
        local f = FrameAt(w[1])
        if not wheelHooks[w[1]] and f and Has(f, "HookScript") then
            local source = w[2]
            if pcall(f.HookScript, f, "OnShow", P.Guard(function(self) OnWheel(self, source) end)) then wheelHooks[w[1]] = true end
        end
    end
end

Add({
    id = "bars.wheels", area = "Blizzard windows", label = "Fade the four bars, then open the pet wheel and a spell wheel",
    short = "Wheels on a faded bar", kind = "guided", manual = true, risky = true, hold = "the four bars' see-through",
    closePanel = true,
    big = "Bars faded. Open the pet wheel (LB+LT), then a spell wheel. Then tap Probe.",
    ready = function()
        local ok, why = NotInCombat()
        if not ok then return false, why end
        if EditModeOpen() then return false, "Edit Mode open" end
        return true
    end,
    start = "Start",
    ask = "The four bars are invisible now. Open the pet wheel (LB+LT), then a spell wheel, then tap Probe and answer: "
        .. "was the wheel visible?",
    answers = { "Wheel visible", "Wheel hidden" },
    apply = function()
        local list = {}
        for _, e in ipairs(WHEEL_BARS) do
            local bar = FrameAt(BAR .. ".PageUnit." .. e[1] .. ".Bar")
            if not bar then return "missing", "the " .. e[2] .. " bar" end
            if type(bar.GetAlpha) ~= "function" or type(bar.SetAlpha) ~= "function" then return "missing", "frame alpha methods" end
            local alpha = bar:GetAlpha()
            if IsSecret(alpha) or not Num(alpha) then return false, "the " .. e[2] .. " bar's see-through is unreadable" end
            list[#list + 1] = { bar = bar, alpha = alpha, name = e[2] }
        end
        HookWheels()
        wheelFaded = list
        for _, e in ipairs(list) do e.bar:SetAlpha(0) end
        local stuck, olds = {}, {}
        for _, e in ipairs(list) do
            local now = e.bar:GetAlpha()
            if IsSecret(now) or not Num(now) then
                stuck[#stuck + 1] = e.name .. " bar unreadable"
            elseif now >= 0.001 then
                stuck[#stuck + 1] = e.name .. " bar still " .. Hundredths(now)
            end
            olds[#olds + 1] = tostring(Hundredths(e.alpha))
        end
        if #stuck > 0 then return false, tconcat(stuck, ", ") .. " after setting it to 0" end
        wheels.list, wheels.shot, wheels.lastPopup, wheels.lastAt = {}, nil, nil, nil
        wheels.waiting = true
        return true, "four bars' see-through " .. tconcat(olds, ", ") .. " -> 0"
    end,
    atAnswer = function()
        local parts = { "wheels seen: " .. #wheels.list }
        for i, e in ipairs(wheels.list) do
            parts[#parts + 1] = e.text or ("wheel " .. i .. " (" .. e.source .. "): not read yet")
        end
        if #wheels.list > 0 then parts[#parts + 1] = "screenshot: " .. (wheels.shot or "none") end
        local still, total = 0, 0
        for _, e in ipairs(wheelFaded or {}) do
            total = total + 1
            local now = e.bar:GetAlpha()
            if not IsSecret(now) and Num(now) and now < 0.001 then still = still + 1 end
        end
        parts[#parts + 1] = "bars still invisible at the answer: " .. still .. " of " .. total
        return tconcat(parts, "; ")
    end,
    -- true when nothing is left to put back; false and why otherwise.
    restore = function()
        wheels.waiting = false
        local list = wheelFaded
        if not list then return true end
        local left = {}
        for _, e in ipairs(list) do
            local now = e.bar:GetAlpha()
            if IsSecret(now) or not Num(now) or abs(now - e.alpha) >= 0.001 then
                pcall(e.bar.SetAlpha, e.bar, e.alpha)
                now = e.bar:GetAlpha()
                if IsSecret(now) or not Num(now) or abs(now - e.alpha) >= 0.001 then left[#left + 1] = e end
            end
        end
        if #left == 0 then
            wheelFaded = nil
            return true
        end
        wheelFaded = left
        if NotInCombat() then return false, "the game did not take the old value; a reload puts it back" end
        return false, "in a fight: it goes back when the fight ends"
    end,
})

-- The game's controller-button pictures (the small prompt on each spell
-- button): which atlas each of the eight shows, whether the game's own lookup
-- gives the same one, and whether a texture of ours takes it. The atlas names
-- and the icon set are kept (they name pictures, not anything personal).
local promptFrame = CreateFrame("Frame", nil, holder)
local promptTexture = promptFrame:CreateTexture(nil, "ARTWORK")

local function AtlasOf(texture)
    if type(texture) ~= "table" or type(texture.GetAtlas) ~= "function" then return nil end
    local ok, atlas = pcall(texture.GetAtlas, texture)
    if not ok then return nil end
    atlas = Str(atlas)
    if atlas == "" then return nil end
    return atlas
end

Add({
    id = "bars.prompts", area = "Our own windows", label = "Show the game's controller-button pictures on a frame of ours",
    kind = "info", manual = true,
    run = function()
        if not MainButton(1) then return "missing", MAIN_BAR .. ".actionButtons" end
        local parts = {}
        local manager, set = Find("InputDeviceIconSetManager"), nil
        if Has(manager, "GetActiveInputDeviceIconSet") then
            local ok, v = pcall(manager.GetActiveInputDeviceIconSet, manager)
            set = ok and Str(v) or nil
        end
        parts[1] = "icon set " .. (set and set:sub(1, 30) or "unknown")
        local lookup = Find("InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture")
        local read, copied, same = 0, 0, 0
        for i = 1, 8 do
            local b = MainButton(i)
            local icon = b and b.ButtonIcon
            if IsSecret(icon) or type(icon) ~= "table" then icon = nil end
            local key = icon and Str(icon.mappedButtonKey)
            local atlas = icon and AtlasOf(icon.NormalTexture)
            if atlas then
                read = read + 1
                promptTexture:SetAtlas(atlas)
                if AtlasOf(promptTexture) == atlas then copied = copied + 1 end
                if key and type(lookup) == "function" then
                    local ok, v = pcall(lookup, key)
                    if ok and Str(v) == atlas then same = same + 1 end
                end
            end
            parts[#parts + 1] = i .. " " .. (key and key:sub(1, 30) or "?") .. "=" .. (atlas and atlas:sub(1, 60) or "none")
        end
        parts[#parts + 1] = "the game's own lookup gives the same picture for " .. same .. " of " .. read
        if read == 0 then return "no pictures read", tconcat(parts, "; ") end
        return copied .. " of " .. read .. " copied" .. (set and (" · " .. set:sub(1, 20)) or ""), tconcat(parts, "; ")
    end,
})

---------------------------------------------------------------------------
-- Probe 0.5.0: can a square of ours show the game's cooldown sweep in a
-- fight. Two 48 by 48 squares, made now and hidden, each with the spell's
-- icon and a Cooldown frame (no countdown numbers), "1" and "2" under them.
-- Square 1 is given the game's duration object, square 2 the start and
-- duration numbers. Both calls are documented as protected, so a refusal is
-- an answer too. No cooldown value is read into the saved table.
-- The three trials are marked manual: the squares and the screenshot have no
-- place in an automatic pass. Fight tests, Run all safe and Run still run them.
---------------------------------------------------------------------------

local SWEEP_SIZE, SWEEP_GAP = 48, 8
local SWEEP_SHOW = 8             -- seconds the squares stay on screen after a sweep trial
local SWEEP_SHOT = 1             -- seconds after they show before the one screenshot

-- At the top of the screen, right of the Probe button and its status line.
local sweep = CreateFrame("Frame", "PocketProbeSweep", UIParent)
sweep:SetSize(SWEEP_SIZE * 2 + SWEEP_GAP, SWEEP_SIZE + 20)
sweep:SetFrameStrata("HIGH")
sweep:SetPoint("TOPLEFT", UIParent, "TOP", 230, P.TOP_Y)    -- level with the Probe button (Core.lua)
sweep:Hide()
local sweepIcons, sweepCooldowns = {}, {}
for i = 1, 2 do
    local square = CreateFrame("Frame", nil, sweep)
    square:SetSize(SWEEP_SIZE, SWEEP_SIZE)
    square:SetPoint("TOPLEFT", sweep, "TOPLEFT", (i - 1) * (SWEEP_SIZE + SWEEP_GAP), 0)
    local back = square:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(square)
    back:SetColorTexture(0, 0, 0, 0.8)
    local icon = square:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(square)
    sweepIcons[i] = icon
    -- A client without the frame type or its template: the trials answer "missing".
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, square, "CooldownFrameTemplate")
    if ok and type(cd) == "table" then
        if Has(cd, "SetAllPoints") then pcall(cd.SetAllPoints, cd, square) end
        if Has(cd, "SetHideCountdownNumbers") then pcall(cd.SetHideCountdownNumbers, cd, true) end
        sweepCooldowns[i] = cd
    end
    local number = sweep:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    number:SetPoint("TOP", square, "BOTTOM", 0, -2)
    number:SetText(tostring(i))
end

local sweepToken = 0             -- changes with every show, so only the newest timer hides

-- Shows the squares for SWEEP_SHOW seconds (a second run starts the time
-- again) and takes one screenshot a second after they come up. onShot (if
-- given) is told whether that picture was taken.
local function ShowSweep(onShot)
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then
        if onShot then onShot(false) end
        return
    end
    local fresh = not Shown(sweep)
    sweep:Show()
    sweepToken = sweepToken + 1
    local token = sweepToken
    after(SWEEP_SHOW, P.Guard(function()
        if token == sweepToken then sweep:Hide() end
    end))
    if fresh then
        after(SWEEP_SHOT, P.Guard(function()
            local shot = Find("Screenshot")
            local taken = false
            if type(shot) == "function" and Shown(sweep) then taken = pcall(shot) and true or false end
            if onShot then onShot(taken) end
        end))
    elseif onShot then
        onShot(false)
    end
end

-- The main bar slot to try: one whose cooldown the game says is running,
-- else the first that holds a spell. Returns the slot and "yes" / "no" /
-- "unknown" (is it on cooldown), or nil.
local function SweepSlot()
    local has, cooldown = Find("C_ActionBar.HasAction"), Find("C_ActionBar.GetActionCooldown")
    local first, firstState
    for i = 1, 8 do
        local b = MainButton(i)
        local slot = b and Num(b.action)
        if slot and slot >= 1 then
            local ok, h = pcall(has, slot)
            if ok and not IsSecret(h) and h then
                local state = "unknown"
                local okc, info = pcall(cooldown, slot)
                if okc and not IsSecret(info) and type(info) == "table" then
                    local active, enabled = info.isActive, info.isEnabled
                    if not IsSecret(active) and active ~= nil then
                        state = active and "yes" or "no"
                    elseif not IsSecret(enabled) and enabled == false then
                        state = "no"
                    end
                end
                if state == "yes" then return slot, state end
                if not first then first, firstState = slot, state end
            end
        end
    end
    return first, firstState
end

P.SweepSlot = SweepSlot

-- Square `index` gets the slot's icon and shows (ShowSweep), then `method` is
-- called on its Cooldown frame with args ({ n = count, ... }). The values go
-- straight from the game to the frame. Returns whether the call went through
-- (and its error), whether the frame showed by itself, and the class of
-- GetCooldownDuration afterwards.
local function SweepSquare(index, method, slot, args, onShot)
    local cd = sweepCooldowns[index]
    local texture = Find("C_ActionBar.GetActionTexture")
    if type(texture) == "function" then
        local ok, v = pcall(texture, slot)
        if ok then pcall(sweepIcons[index].SetTexture, sweepIcons[index], v) end
    end
    ShowSweep(onShot)
    cd:Hide()
    local ok, err = pcall(cd[method], cd, unpack(args, 1, args.n))
    -- Whether setting a cooldown shows the frame is one of the things asked.
    local shown = Shown(cd)
    local class = "missing"
    if Has(cd, "GetCooldownDuration") then
        local okd, v = pcall(cd.GetCooldownDuration, cd)
        class = okd and P.Class(v) or "error"
    end
    -- Shown by us if it did not show itself, so a sweep can still be seen.
    if not shown then cd:Show() end
    return ok, err, shown, class
end

-- One sweep trial: square `index`, `method`, with what values(slot) returns
-- ({ n = count, ... }, or nil and why).
local function RunSweep(index, method, values)
    local cd = sweepCooldowns[index]
    if not cd then return "missing", "CooldownFrameTemplate" end
    if not Has(cd, method) then return "missing", "Cooldown:" .. method end
    local slot, running = SweepSlot()
    if not slot then return false, "no main bar button holds a spell" end
    local args, why = values(slot)
    if not args then return false, why end
    local ok, err, shown, class = SweepSquare(index, method, slot, args)
    local note = "slot on cooldown " .. running .. "; sweep frame shown by itself " .. (shown and "yes" or "no")
        .. "; duration afterwards " .. class
    if not ok then error(P.Plain(err, 200) .. " | " .. note, 0) end
    return true, note
end

-- Probe 0.7.0, the sweep watcher (Watch.lua): the steps of cd.sweep.object
-- on square 1 for this slot. Returns "missing" and a name, or a table:
-- { ok = the call went through, shown = the frame showed by itself,
-- durClass = the class of GetCooldownDuration afterwards }. onShot is told
-- whether the screenshot a second later was taken.
function P.SweepOnSlot(slot, onShot)
    local cd = sweepCooldowns[1]
    if not cd then return "missing", "CooldownFrameTemplate" end
    if not Has(cd, "SetCooldownFromDurationObject") then return "missing", "Cooldown:SetCooldownFromDurationObject" end
    local get = Find("C_ActionBar.GetActionCooldownDuration")
    if type(get) ~= "function" then return "missing", "C_ActionBar.GetActionCooldownDuration" end
    local okd, object = pcall(get, slot)
    if not okd then return { ok = false } end
    local ok, _, shown, class = SweepSquare(1, "SetCooldownFromDurationObject", slot, { n = 1, object }, onShot)
    return { ok = ok and true or false, shown = shown and true or false, durClass = class }
end

Add({
    id = "cd.duration", area = "Our own windows", label = "Read the main bar's cooldown duration objects (run it in a fight too)",
    kind = "value", fight = true, manual = true,
    needs = { "C_ActionBar.HasAction", "C_ActionBar.GetActionCooldownDuration" },
    read = function(c)
        local tally, take = Tally()
        local has, duration = Find("C_ActionBar.HasAction"), Find("C_ActionBar.GetActionCooldownDuration")
        local buttons, filled = 0, 0
        for i = 1, 8 do
            local b = MainButton(i)
            if b then
                buttons = buttons + 1
                local slot = Num(b.action)
                if slot and slot >= 1 then
                    local ok, h = pcall(has, slot)
                    if ok and not IsSecret(h) and h then
                        filled = filled + 1
                        take("duration", pcall(duration, slot))
                    end
                end
            end
        end
        if buttons == 0 then
            c:add("buttons", nil)
            c:note("the main bar's buttons are not there")
            return
        end
        c:note("buttons " .. buttons .. ", with a spell " .. filled)
        if tally.duration then TallyNote(c, tally, "duration") else c:add("duration", nil) end
    end,
})

Add({
    id = "cd.sweep.object", area = "Our own windows", label = "Cooldown sweep on a square of ours, from the game's duration object",
    kind = "action", fight = true, manual = true,
    needs = { "C_ActionBar.HasAction", "C_ActionBar.GetActionCooldown", "C_ActionBar.GetActionCooldownDuration" },
    run = function()
        return RunSweep(1, "SetCooldownFromDurationObject", function(slot)
            return { n = 1, (Find("C_ActionBar.GetActionCooldownDuration")(slot)) }
        end)
    end,
})

Add({
    id = "cd.sweep.numbers", area = "Our own windows", label = "Cooldown sweep on a square of ours, from the start and duration numbers",
    kind = "action", fight = true, manual = true,
    needs = { "C_ActionBar.HasAction", "C_ActionBar.GetActionCooldown" },
    run = function()
        return RunSweep(2, "SetCooldown", function(slot)
            local info = Find("C_ActionBar.GetActionCooldown")(slot)
            if IsSecret(info) or type(info) ~= "table" then return nil, "the cooldown table is unreadable" end
            return { n = 2, info.startTime, info.duration }
        end)
    end,
})

---------------------------------------------------------------------------
-- Vendor trials: the only ones that spend anything. Run.lua keeps
-- P.vendorOpen true between MERCHANT_SHOW and MERCHANT_CLOSED.
---------------------------------------------------------------------------

local VENDOR_WAIT = 1   -- seconds before looking whether the sale or repair went through

local function VendorOn()
    return P.vendorOpen == true and type(P.db) == "table" and P.db.options.vendor == true
end

local function Poor()
    local poor = Find("Enum.ItemQuality.Poor")
    return type(poor) == "number" and poor or 0
end

-- The same test as Pocket Essentials' sell-junk feature: grey in both the bag
-- slot and the item data, has a price, not locked. Anything unreadable or
-- not yet loaded means "not junk". Returns the price of the whole stack.
local function JunkValue(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if IsSecret(info) or type(info) ~= "table" then return nil end
    local quality, locked, noValue = info.quality, info.isLocked, info.hasNoValue
    if IsSecret(quality) or IsSecret(locked) or IsSecret(noValue) then return nil end
    if quality ~= Poor() or locked or noValue then return nil end
    local itemID, count = Num(info.itemID), Num(info.stackCount)
    if not itemID or itemID <= 0 or not count or count < 1 then return nil end
    local _, _, infoQuality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(itemID)
    if IsSecret(infoQuality) or infoQuality ~= Poor() then return nil end
    price = Num(price)
    if not price or price <= 0 then return nil end
    return price * count
end

-- The bag menu's own "ignore this bag when selling junk" setting.
local function BagExcluded(bag, backpack)
    local excluded
    if bag == backpack then
        local fn = C_Container.GetBackpackSellJunkDisabled
        excluded = fn and fn()
    else
        local flag = Find("Enum.BagSlotFlags.ExcludeJunkSell")
        local fn = C_Container.GetBagSlotFlag
        excluded = flag and fn and fn(bag, flag)
    end
    if IsSecret(excluded) then return false end
    return excluded and true or false
end

-- The bag and slot of the cheapest grey item that may be sold, or nil.
local function CheapestJunk()
    local first = Num(BACKPACK_CONTAINER) or 0
    local last = Num(NUM_BAG_SLOTS) or 4
    if last < first or last > first + 11 then last = first + 4 end
    local bestBag, bestSlot, bestValue
    for bag = first, last do
        local slots = Num(C_Container.GetContainerNumSlots(bag)) or 0
        if slots > 0 and slots <= 200 and not BagExcluded(bag, first) then
            for slot = 1, slots do
                local value = JunkValue(bag, slot)
                if value and (not bestValue or value < bestValue) then
                    bestBag, bestSlot, bestValue = bag, slot, value
                end
            end
        end
    end
    return bestBag, bestSlot
end

local function JunkLeft()
    return Num(Find("C_MerchantFrame.GetNumJunkItems")())
end

Add({
    id = "vendor.sell1", area = "Bags and vendor", label = "Sell the cheapest grey item (UseContainerItem)", kind = "action",
    clean = true, vendor = true, wait = VENDOR_WAIT,
    needs = { "C_Container.UseContainerItem", "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots",
        "C_Item.GetItemInfo" },
    gate = VendorOn,
    ready = function()
        if not CheapestJunk() then return false, "no grey item to sell" end
        return true
    end,
    run = function(state)
        local bag, slot = CheapestJunk()
        if not bag then return false, "no grey item to sell" end
        state.bag, state.slot = bag, slot
        C_Container.UseContainerItem(bag, slot)
        return "wait"
    end,
    check = function(state)
        local info = C_Container.GetContainerItemInfo(state.bag, state.slot)
        if IsSecret(info) then return false, "bag slot unreadable" end
        return info == nil
    end,
})

Add({
    id = "vendor.sellall", area = "Bags and vendor", label = "The game's sell-all-junk call (SellAllJunkItems)", kind = "action",
    vendor = true, wait = VENDOR_WAIT,
    needs = { "C_MerchantFrame.SellAllJunkItems", "C_MerchantFrame.GetNumJunkItems" },
    gate = VendorOn,
    ready = function()
        -- Blizzard shows its button only when IsSellAllJunkEnabled() and
        -- enables it only when GetNumJunkItems() > 0 (Mainline/MerchantFrame.lua:482, 210).
        local enabled = Find("C_MerchantFrame.IsSellAllJunkEnabled")
        if type(enabled) == "function" then
            local on = enabled()
            if IsSecret(on) or not on then return false, "sell-all-junk is switched off on this client" end
        end
        local left = JunkLeft()
        if not left or left <= 0 then return false, "no junk left to sell" end
        return true
    end,
    run = function()
        Find("C_MerchantFrame.SellAllJunkItems")()
        return "wait"
    end,
    check = function()
        local left = JunkLeft()
        if not left then return false, "junk count unreadable" end
        return left == 0
    end,
})

Add({
    id = "vendor.repair", area = "Bags and vendor", label = "Repair everything (RepairAllItems)", kind = "action",
    vendor = true, wait = VENDOR_WAIT,
    needs = { "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems", "GetMoney" },
    gate = VendorOn,
    ready = function()
        local can = CanMerchantRepair()
        if IsSecret(can) or not can then return false, "this vendor does not repair" end
        local cost, money = Num((GetRepairAllCost())), Num(GetMoney())
        if not cost or not money then return false, "repair cost or money unreadable" end
        if cost <= 0 then return false, "nothing is damaged" end
        if money < cost then return false, "not enough money to repair" end
        return true
    end,
    run = function()
        RepairAllItems(false)
        return "wait"
    end,
    check = function()
        local cost = Num((GetRepairAllCost()))
        if not cost then return false, "repair cost unreadable" end
        return cost == 0
    end,
})

---------------------------------------------------------------------------
-- Values: only the class of each is kept
---------------------------------------------------------------------------

local function Value(id, label, needs, read)
    Add({ id = id, area = "Values", label = label, kind = "value", needs = needs, read = read })
end

Value("val.position", "Player position on the map", { "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition" }, function(c)
    local map = C_Map.GetBestMapForUnit("player")
    if c:add("map", map) ~= "readable" then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if c:add("position", pos) ~= "readable" or type(pos) ~= "table" then return end
    if type(pos.GetXY) == "function" then
        local x, y = pos:GetXY()
        c:add("x", x)
        c:add("y", y)
    else
        c:add("x", pos.x)
        c:add("y", pos.y)
    end
end)

Value("val.facing", "Player facing", { "GetPlayerFacing" }, function(c)
    c:add("facing", (GetPlayerFacing()))
end)

Value("val.map", "Best map for the player", { "C_Map.GetBestMapForUnit" }, function(c)
    c:add("map", (C_Map.GetBestMapForUnit("player")))
end)

Value("val.questlog", "Quest log entries", { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo" }, function(c)
    local entries = C_QuestLog.GetNumQuestLogEntries()
    if c:add("count", entries) ~= "readable" then return end
    if type(entries) ~= "number" or entries < 1 then return end
    local info = C_QuestLog.GetInfo(1)
    if c:add("entry", info) ~= "readable" or type(info) ~= "table" then return end
    c:add("title", info.title)
    c:add("questID", info.questID)
    c:add("isHeader", info.isHeader)
end)

-- The first real quest in the log (not a header), or nil.
local function FirstQuestID()
    local entries = Num((C_QuestLog.GetNumQuestLogEntries())) or 0
    if entries > 50 then entries = 50 end
    for i = 1, entries do
        local info = C_QuestLog.GetInfo(i)
        if not IsSecret(info) and type(info) == "table" then
            local header, id = info.isHeader, Num(info.questID)
            if not IsSecret(header) and not header and id and id > 0 then return id end
        end
    end
    return nil
end

Value("val.objectives", "Quest objectives", { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo",
    "C_QuestLog.GetQuestObjectives" }, function(c)
    local id = FirstQuestID()
    if not id then
        c:add("quest", nil)
        return
    end
    local list = C_QuestLog.GetQuestObjectives(id)
    if c:add("objectives", list) ~= "readable" or type(list) ~= "table" then return end
    local first = list[1]
    if c:add("first", first) ~= "readable" or type(first) ~= "table" then return end
    c:add("text", first.text)
    c:add("numFulfilled", first.numFulfilled)
    c:add("finished", first.finished)
end)

Value("val.bagitem", "Bag item info", { "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo" }, function(c)
    local firstBag = Num(BACKPACK_CONTAINER) or 0
    for bag = firstBag, firstBag + 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        if IsSecret(slots) then
            c:add("slots", slots)
            return
        end
        slots = Num(slots) or 0
        if slots > 200 then slots = 200 end
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info ~= nil then
                if c:add("info", info) ~= "readable" or type(info) ~= "table" then return end
                c:add("itemID", info.itemID)
                c:add("quality", info.quality)
                c:add("hyperlink", info.hyperlink)
                c:add("stackCount", info.stackCount)
                c:add("isLocked", info.isLocked)
                return
            end
        end
    end
    c:add("info", nil)
end)

Value("val.money", "Money", { "GetMoney" }, function(c)
    c:add("money", (GetMoney()))
end)

Value("val.repaircost", "Repair cost", { "GetRepairAllCost" }, function(c)
    local cost, can = GetRepairAllCost()
    c:add("cost", cost)
    c:add("canRepair", can)
end)

Value("val.name.player", "Unit name of the player", { "UnitName" }, function(c)
    c:add("name", (UnitName("player")))
end)

Value("val.name.target", "Unit name of the target", { "UnitName" }, function(c)
    c:add("name", (UnitName("target")))
end)

-- Recorded by Run.lua when a whisper arrives (CHAT_MSG_WHISPER), never in a pass.
Add({ id = "val.whisper", area = "Values", label = "Whisper event payload (when one arrives)", kind = "value", event = true })

---------------------------------------------------------------------------
-- Probe 0.8.0: what a fight leaves readable of the target's and the pet's
-- buffs. Pocket Essentials 0.17.0 wants to slim the target frame; these four
-- read-only trials say whether the buff icons stay readable in a fight and
-- what keeps them visible. Only classes and counts are saved, never an icon,
-- a number of the game's or a name of a spell.
--
-- Game names (Blizzard_APIDocumentationGenerated/, branch forever):
--   C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter)  UnitAuraDocumentation.lua:475
--       (RequiresUnitAuraAccess: a fight may refuse it)
--   C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id) UnitAuraDocumentation.lua:190
--       (SecretWhenUnitAuraRestricted: the answer may be secret)
--   texture :SetTexture(asset) -> success             SimpleTextureBaseAPIDocumentation.lua:604
--   cooldown :SetCooldownFromExpirationTime(expirationTime, duration)
--                                                      FrameAPICooldownDocumentation.lua:320
--       (protected; secret arguments only from untainted code)
--   frame :GetChildren / :GetAlpha / :IsIgnoringParentAlpha
--                                                      SimpleFrameAPIDocumentation.lua:323, 276, 823
--   object :GetParent / :GetName                       SimpleObjectAPIDocumentation.lua:34,
--                                                      SimpleFrameScriptObjectAPIDocumentation.lua:107
-- Not in the documentation folder and so guarded: the field names icon,
-- applications, duration and expirationTime of the aura table (the game
-- hands the table over from its own code), and the TargetFrame's parent keys
-- TargetFrameContent.TargetFrameContentContextual.Auras
-- (Blizzard_UnitFrame/Mainline/TargetFrame.lua:502).
---------------------------------------------------------------------------

local AURA_AREA = "Buffs in a fight"
local AURA_UNITS = { "target", "pet" }
local AURA_FILTERS = { { "HELPFUL", "buffs" }, { "HARMFUL", "debuffs" } }

-- The box the show trial uses: ours, made now, hidden. A picture and a
-- cooldown child, nothing of the game's.
local auraBox = CreateFrame("Frame", nil, UIParent)
auraBox:SetSize(8, 8)
auraBox:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
auraBox:Hide()
auraBox.picture = auraBox:CreateTexture(nil, "ARTWORK")
auraBox.picture:SetAllPoints(auraBox)
local madeCooldown, cooldownFrame = pcall(CreateFrame, "Cooldown", nil, auraBox)
if madeCooldown and type(cooldownFrame) == "table" then
    auraBox.cooldown = cooldownFrame
    cooldownFrame:SetAllPoints(auraBox)
end
P.auraBox = auraBox

-- The aura ids of one unit and filter: the list, or nil and "refused" or "secret".
local function AuraIds(unit, filter)
    local ok, ids = pcall(Find("C_UnitAuras.GetUnitAuraInstanceIDs"), unit, filter)
    if not ok then return nil, "refused" end
    if IsSecret(ids) then return nil, "secret", ids end
    if type(ids) ~= "table" then return nil, "nothing" end
    return ids
end

-- The first buff (else the first debuff) of a unit: its data table, or nil and why.
local function FirstAura(unit)
    local why
    for _, f in ipairs(AURA_FILTERS) do
        local ids, reason = AuraIds(unit, f[1])
        if ids then
            local okId, id = pcall(function() return ids[1] end)
            if okId and id ~= nil and not IsSecret(id) then
                local ok, info = pcall(Find("C_UnitAuras.GetAuraDataByAuraInstanceID"), unit, id)
                if not ok then return nil, "refused" end
                if IsSecret(info) then return nil, "secret" end
                if type(info) == "table" then return info end
            end
        else
            why = why or reason
        end
    end
    return nil, why or "none"
end

local AURA_NEEDS = { "C_UnitAuras.GetUnitAuraInstanceIDs", "C_UnitAuras.GetAuraDataByAuraInstanceID" }

Add({
    id = "aura.count", area = AURA_AREA, label = "Count the target's and the pet's buffs and debuffs (run it in a fight too)",
    kind = "value", fight = true, noRow = true,
    needs = { "C_UnitAuras.GetUnitAuraInstanceIDs" },
    read = function(c)
        for _, unit in ipairs(AURA_UNITS) do
            for _, f in ipairs(AURA_FILTERS) do
                local ids, why, hidden = AuraIds(unit, f[1])
                if ids then
                    local okN, n = pcall(function() return #ids end)
                    n = okN and Num(n)
                    c:add(unit .. " " .. f[2], n or nil)
                    c:note(unit .. " " .. f[2] .. " " .. (n and tostring(n) or "unreadable"))
                else
                    if hidden ~= nil then c:add(unit .. " " .. f[2], hidden) end
                    c:note(unit .. " " .. f[2] .. " " .. why)
                end
            end
        end
    end,
})

local AURA_FIELDS = { "icon", "applications", "duration", "expirationTime" }

Add({
    id = "aura.fields", area = AURA_AREA, label = "Read the first buff's icon, count and time (run it in a fight too)",
    kind = "value", fight = true, noRow = true,
    needs = AURA_NEEDS,
    read = function(c)
        for _, unit in ipairs(AURA_UNITS) do
            local info, why = FirstAura(unit)
            if not info then
                c:add(unit .. " aura", nil)
                c:note(unit .. " has no aura to read (" .. why .. ")")
            else
                for _, field in ipairs(AURA_FIELDS) do
                    local ok, value = pcall(function() return info[field] end)
                    value = ok and value or nil
                    local class = c:add(unit .. " " .. field, value)
                    c:note(unit .. " " .. field .. " " .. (class == "readable" and "plain" or class == "nil" and "missing" or class))
                end
            end
        end
    end,
})

Add({
    id = "aura.show", area = AURA_AREA, label = "Feed a box of ours a buff's icon and time (run it in a fight too)",
    kind = "value", fight = true, noRow = true,
    needs = AURA_NEEDS,
    read = function(c)
        local info, why, from
        for _, unit in ipairs(AURA_UNITS) do
            info, why = FirstAura(unit)
            if info then from = unit break end
        end
        if not info then
            c:add("aura", nil)
            c:note("no aura to show (" .. tostring(why) .. ")")
            return
        end
        auraBox:Show()
        local okAll, err = pcall(function()
            local okT = pcall(auraBox.picture.SetTexture, auraBox.picture, info.icon)
            c:note("SetTexture " .. (okT and "accepted" or "refused"))
            local cd = auraBox.cooldown
            if not cd then
                c:note("SetCooldownFromExpirationTime missing (no cooldown frame)")
            elseif type(cd.SetCooldownFromExpirationTime) ~= "function" then
                c:note("SetCooldownFromExpirationTime missing")
            else
                local okC = pcall(cd.SetCooldownFromExpirationTime, cd, info.expirationTime, info.duration)
                c:note("SetCooldownFromExpirationTime " .. (okC and "accepted" or "refused"))
                pcall(cd.Clear, cd)
            end
        end)
        auraBox:Hide()
        if not okAll then c:note("stopped: " .. P.Plain(err, 80)) end
        c:note("from the " .. from)
        c:add("box", true)
    end,
})

-- One frame's name for the chain: its own name, else its key in its parent.
local function AuraFrameName(frame, parent)
    local name = Has(frame, "GetName") and select(2, pcall(frame.GetName, frame))
    name = Str(name)
    if name and name ~= "" then return name end
    if type(parent) == "table" and not IsSecret(parent) then
        local okK, key = pcall(function()
            for k, v in pairs(parent) do
                if v == frame and type(k) == "string" then return k end
            end
        end)
        if okK and Str(key) then return key end
    end
    return "(unnamed)"
end

-- The aura container of the target frame: the game's key path, else nil.
local function AuraContainer(frame)
    local ok, container = pcall(function()
        return frame.TargetFrameContent.TargetFrameContentContextual.Auras
    end)
    if ok and type(container) == "table" and not IsSecret(container) then return container end
    return nil
end

Add({
    id = "aura.blizzard", area = AURA_AREA, label = "Look at where the target frame's buff icons hang (changes nothing)",
    kind = "value", fight = true, noRow = true,
    read = function(c)
        local frame = Find("TargetFrame")
        if type(frame) ~= "table" or IsSecret(frame) then
            c:add("TargetFrame", nil)
            c:note("TargetFrame is not there")
            return
        end
        local container = AuraContainer(frame)
        if not container then
            c:add("aura container", nil)
            c:note("no aura container under TargetFrame (its key path is not there)")
            return
        end
        -- The icons: the container's children that carry an Icon, else its first child.
        local okC, kids = pcall(function() return { container:GetChildren() } end)
        kids = okC and kids or {}
        local icon
        for _, kid in ipairs(kids) do
            if type(kid) == "table" and kid.Icon ~= nil then icon = kid break end
        end
        icon = icon or kids[1]
        local direct = false
        if icon then
            local okP, parent = pcall(icon.GetParent, icon)
            direct = okP and parent == container
        end
        c:note("children " .. #kids .. ", icons are " .. (icon and (direct and "children of the container" or "children of something else") or "not found"))
        -- The chain from the container up: name, own see-through (alpha under 1), ignores the parent's.
        local chain, own = {}, nil
        local node, depth = container, 0
        while type(node) == "table" and depth < 8 do
            local okP, parent = pcall(node.GetParent, node)
            parent = okP and not IsSecret(parent) and parent or nil
            local alpha = Has(node, "GetAlpha") and select(2, pcall(node.GetAlpha, node))
            alpha = Num(alpha)
            local ignores = Has(node, "IsIgnoringParentAlpha") and select(2, pcall(node.IsIgnoringParentAlpha, node))
            local note = AuraFrameName(node, parent)
            if alpha and alpha < 1 then note = note .. " (own see-through " .. floor(alpha * 100 + 0.5) .. "%)"; own = own or note end
            if ignores == true then note = note .. " (ignores the parent's)" end
            chain[#chain + 1] = note
            node, depth = parent, depth + 1
        end
        c:note("chain " .. tconcat(chain, " < "))
        c:note(own and ("a frame with its own see-through: " .. own) or "no frame in the chain has its own see-through")
        c:add("aura container", container)
        c:note("changed nothing")
    end,
})

---------------------------------------------------------------------------
-- The clean series: each of these alone, first thing after a reload
---------------------------------------------------------------------------

-- The ones suspected of lasting damage come first.
local CLEAN_FIRST = { "chat.type", "chat.open", "chat.openframe", "chat.focus", "chat.close", "bag.toggle" }

P.cleanList = {}
local listed = {}
for _, id in ipairs(CLEAN_FIRST) do
    P.cleanList[#P.cleanList + 1] = P.trialById[id]
    listed[id] = true
end
for _, t in ipairs(P.trials) do
    if t.clean and not listed[t.id] then P.cleanList[#P.cleanList + 1] = t end
end
