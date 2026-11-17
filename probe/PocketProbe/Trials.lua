local ADDON_NAME, P = ...

-- The trials. Each one is a small table:
--
--   id, area, label, kind   what the saved file lists ("action" or "value")
--   clean = true            also run alone, first thing after a reload
--   vendor = true           costs something; only with a vendor window open
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
-- Run.lua calls these inside its error catcher and watches for the game's
-- "blocked" signals while one runs. Nothing here stores a value read from
-- the game: only classes ("readable", "secret", "nil") and our own text.

local type, pairs, ipairs = type, pairs, ipairs
local Find, IsSecret, Num, Str = P.Find, P.IsSecret, P.Num, P.Str

P.trials = {}
P.trialById = {}

local function Add(t)
    P.trials[#P.trials + 1] = t
    P.trialById[t.id] = t
end

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
    id = "chat.open", area = "Chat box", label = "Open the chat box", kind = "action", clean = true,
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
    id = "chat.focus", area = "Chat box", label = "Give the chat edit box focus", kind = "action", clean = true,
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
    id = "chat.close", area = "Chat box", label = "Close the chat box again", kind = "action", clean = true,
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
    { key = "chat", what = "the chat frame", find = function() return Find("ChatFrame1"), "ChatFrame1" end },
}

local function BagFrame()
    local frame = WINDOWS[2].find()
    return type(frame) == "table" and frame or nil
end

for _, w in ipairs(WINDOWS) do
    local key, find = w.key, w.find

    Add({
        id = "win." .. key .. ".create", area = "Blizzard windows", label = "Create a button under " .. w.what,
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
        id = "win." .. key .. ".attach", area = "Blizzard windows", label = "Put our existing button back under " .. w.what,
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
    id = "bag.toggle", area = "Blizzard windows", label = "Open and close the bags", kind = "action",
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
    id = "bag.move", area = "Blizzard windows", label = "Move the bag", kind = "action",
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
    id = "bag.scale", area = "Blizzard windows", label = "Resize the bag", kind = "action",
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
    id = "pad.bind", area = "Controller", label = "Take a controller button for ourselves and give it back",
    kind = "action", clean = true,
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
    id = "pad.mark", area = "Controller", label = "Mark one of our buttons for the controller's navigation",
    kind = "action", clean = true,
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
    id = "bags.sort", area = "Bags", label = "Sort the bags", kind = "action",
    needs = { "C_Container.SortBags" },
    run = function()
        Find("C_Container.SortBags")()
        return nil
    end,
})

local BAG_SETTING = "combinedBags"

Add({
    id = "cvar.write", area = "Settings", label = "Read the combined-bags setting and write it back unchanged", kind = "action",
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
    id = "layout.read", area = "Layout", label = "Read the Edit Mode layouts", kind = "value",
    needs = { "C_EditMode.GetLayouts" },
    read = function(c)
        local info = Find("C_EditMode.GetLayouts")()
        if c:add("layouts", info) ~= "readable" or type(info) ~= "table" then return end
        c:add("activeLayout", info.activeLayout)
        c:add("list", info.layouts)
    end,
})

Add({
    id = "layout.set", area = "Layout", label = "Set the active layout to the one already active", kind = "action", clean = true,
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
    id = "vendor.sell1", area = "Vendor", label = "Sell the cheapest grey item (UseContainerItem)", kind = "action",
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
    id = "vendor.sellall", area = "Vendor", label = "The game's sell-all-junk call (SellAllJunkItems)", kind = "action",
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
    id = "vendor.repair", area = "Vendor", label = "Repair everything (RepairAllItems)", kind = "action",
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
-- The clean series: each of these alone, first thing after a reload
---------------------------------------------------------------------------

P.cleanList = {}
for _, t in ipairs(P.trials) do
    if t.clean then P.cleanList[#P.cleanList + 1] = t end
end
