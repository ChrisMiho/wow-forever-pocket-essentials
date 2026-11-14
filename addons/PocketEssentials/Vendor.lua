local ADDON_NAME, PE = ...

-- Vendor helpers: two separate features, each with its own switch.
--
--   "sellJunk"  sells grey items when a vendor window opens: one item about
--               every 0.2 seconds, at most 12 per visit so all of it can
--               still be bought back.
--   "repair"    repairs all gear at vendors that can, with the character's
--               own money (never the guild's).
--
-- The two do not know about each other; they only share the small helpers
-- at the top of this file. No frames, no OnUpdate: events and short timers.

local type, pcall, error = type, pcall, error
local floor = math.floor
local tconcat = table.concat

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

-- The client can hand addons "secret" values that raise an error when they
-- are compared or used in maths. Anything secret is treated as unreadable.
local function IsSecret(value)
    return (issecretvalue and issecretvalue(value)) and true or false
end

-- The value if it is an ordinary, readable number; otherwise nil.
local function Num(value)
    if IsSecret(value) or type(value) ~= "number" or value ~= value then return nil end
    return value
end

local function PlainMoney(copper)
    local gold = floor(copper / 10000)
    local silver = floor(copper / 100) % 100
    local coins = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if coins > 0 or #parts == 0 then parts[#parts + 1] = coins .. "c" end
    return tconcat(parts, " ")
end

-- Money as text: the game's own coin text when it has it, else "1g 20s 5c".
local function Money(copper)
    copper = floor((Num(copper) or 0) + 0.5)
    if copper < 0 then copper = 0 end
    local coinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if coinText then
        local ok, text = pcall(coinText, copper)
        if ok and not IsSecret(text) and type(text) == "string" and text ~= "" then return text end
    end
    return PlainMoney(copper)
end

-- True while the game's vendor window is on screen. (If this client had no
-- such frame, the MERCHANT_SHOW / MERCHANT_CLOSED events alone decide.)
local function VendorWindowShown()
    local frame = MerchantFrame
    if frame and frame.IsShown then return frame:IsShown() and true or false end
    return true
end

-- The game reports a call it refused with ADDON_ACTION_BLOCKED or
-- ADDON_ACTION_FORBIDDEN (addon name, function name).
local function RefusedCallIsOurs(addon, func, name)
    if IsSecret(addon) or IsSecret(func) then return false end
    return addon == ADDON_NAME and type(func) == "string" and func:find(name, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------

local SELL_START_DELAY = 0.3 -- after the window opens, before the first sale
local SELL_STEP = 0.2        -- seconds between sales
local SELL_MAX = 12          -- tries per visit: what the vendor's buyback page holds
local SELL_LAST_LOOK = 0.6   -- a sale still on its way when selling stops is checked once more
local WAIT_UNLOCKED = 5      -- steps (1 s) an item may sit untouched before it counts as not sold
local WAIT_LOCKED = 15       -- steps (3 s) for an item the game still shows as busy
local REFUSALS_TO_STOP = 2   -- this many in a row: the vendor is not buying, stop

local POOR = 0
if Enum and Enum.ItemQuality and type(Enum.ItemQuality.Poor) == "number" then
    POOR = Enum.ItemQuality.Poor
end

local sellJunk             -- the module
local run                  -- the selling under way, or nil
local sellOpen = false     -- between MERCHANT_SHOW and MERCHANT_CLOSED
local sellBlocked = false  -- the game refused our sell call: no more tries this session
local inSellCall = false

-- If that bag slot holds a grey item that may be sold right now, returns its
-- itemID, stack count and price for one. Otherwise nil. Anything missing,
-- unreadable or not yet loaded means "do not sell".
local function JunkAt(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if IsSecret(info) or type(info) ~= "table" then return nil end
    local quality, locked, noValue = info.quality, info.isLocked, info.hasNoValue
    if IsSecret(quality) or IsSecret(locked) or IsSecret(noValue) then return nil end
    if quality ~= POOR or locked or noValue then return nil end
    local itemID, count = Num(info.itemID), Num(info.stackCount)
    if not itemID or itemID <= 0 or not count or count < 1 then return nil end
    -- Returns nothing while the item's data has not arrived from the server:
    -- that item is then left alone for this visit.
    local _, _, infoQuality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(itemID)
    if IsSecret(infoQuality) or infoQuality ~= POOR then return nil end
    price = Num(price)
    if not price or price <= 0 then return nil end
    return itemID, count, price
end

-- The bag menu's own "ignore this bag when selling junk" setting.
local function BagExcludedBody(bag, backpack)
    if bag == backpack then
        local fn = C_Container.GetBackpackSellJunkDisabled
        return fn and fn()
    end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell
    local fn = C_Container.GetBagSlotFlag
    return flag and fn and fn(bag, flag)
end

local function BagExcluded(bag, backpack)
    local ok, excluded = pcall(BagExcludedBody, bag, backpack)
    if not ok or IsSecret(excluded) then return false end
    return excluded and true or false
end

-- Every grey item worth selling in the backpack and the four bags.
local function ScanJunk()
    local list = {}
    local first = Num(BACKPACK_CONTAINER) or 0
    local last = Num(NUM_BAG_SLOTS) or 4
    if last < first or last > first + 11 then last = first + 4 end
    for bag = first, last do
        local slots = Num(C_Container.GetContainerNumSlots(bag)) or 0
        if slots > 0 and slots <= 200 and not BagExcluded(bag, first) then
            for slot = 1, slots do
                local itemID = JunkAt(bag, slot)
                if itemID then list[#list + 1] = { bag = bag, slot = slot, itemID = itemID } end
            end
        end
    end
    return list
end

-- What became of the item we asked the vendor to take:
-- "sold" (gone from its slot), "busy" (still there, the game is working on
-- it) or "kept" (still there).
local function PendingState(p)
    local info = C_Container.GetContainerItemInfo(p.bag, p.slot)
    if IsSecret(info) then return "kept" end
    if info == nil then return "sold" end
    if type(info) ~= "table" then return "kept" end
    local itemID, locked = info.itemID, info.isLocked
    if IsSecret(itemID) or IsSecret(locked) then return "kept" end
    if itemID ~= p.itemID then return "sold" end
    return locked and "busy" or "kept"
end

-- Counts the pending sale once its slot has emptied. Returns its state, or
-- nil when nothing is pending.
local function SellSettle(r)
    local p = r.pending
    if not p then return nil end
    local state = PendingState(p)
    if state == "sold" then
        r.pending = nil
        r.sold = r.sold + 1
        r.total = r.total + p.price * p.count
    end
    return state
end

-- Ends a run and prints its one line (nothing when nothing was sold).
local function SellFinish(r, lastLook)
    if run == r then run = nil end
    if r.reported then return end
    local state = SellSettle(r)
    if state and state ~= "sold" and not lastLook and sellJunk:IsEnabled() then
        -- The last sale may still be on its way: look once more, then report.
        sellJunk:After(SELL_LAST_LOOK, function() SellFinish(r, true) end)
        return
    end
    r.reported = true
    if r.sold <= 0 then return end
    local more = false
    if r.capped then
        for i = r.i, #r.list do
            local e = r.list[i]
            if JunkAt(e.bag, e.slot) == e.itemID then
                more = true
                break
            end
        end
    end
    local text = "Sold " .. r.sold .. (r.sold == 1 and " junk item for " or " junk items for ") .. Money(r.total) .. "."
    if more then text = text .. " (more left - reopen the vendor)" end
    sellJunk:Print(text)
end

local SellStep

local function SellLater(r)
    sellJunk:After(SELL_STEP, function()
        if run == r then SellStep(r) end
    end)
end

-- One step: check on the item sold last, then sell the next one.
SellStep = function(r)
    if sellBlocked or not sellOpen or not VendorWindowShown() then
        SellFinish(r)
        return
    end
    if PE:InCombat() then
        -- Not while fighting: carry on when the fight ends, if still here.
        PE:RunOutOfCombat("sellJunk:resume", function()
            if run == r then SellStep(r) end
        end)
        return
    end
    if InRepairMode and InRepairMode() then
        -- The repair cursor is up: a "use" would mean something else now.
        SellFinish(r)
        return
    end

    local p = r.pending
    if p then
        local state = SellSettle(r)
        if state == "sold" then
            r.refused = 0
        else
            p.waits = p.waits + 1
            if p.waits < (state == "busy" and WAIT_LOCKED or WAIT_UNLOCKED) then
                SellLater(r)
                return
            end
            -- Still in the bag: the vendor did not take it. It is not tried again.
            r.pending = nil
            r.refused = r.refused + 1
            if r.refused >= REFUSALS_TO_STOP then
                SellFinish(r)
                return
            end
        end
    end

    if r.attempts >= SELL_MAX then
        r.capped = true
        SellFinish(r)
        return
    end

    local list = r.list
    while r.i <= #list do
        local e = list[r.i]
        r.i = r.i + 1
        -- Looked at again just before it goes: same item, still grey, still
        -- worth something, not locked.
        local itemID, count, price = JunkAt(e.bag, e.slot)
        if itemID and itemID == e.itemID then
            r.attempts = r.attempts + 1
            r.pending = { bag = e.bag, slot = e.slot, itemID = itemID, count = count, price = price, waits = 0 }
            inSellCall = true
            local ok, err = pcall(C_Container.UseContainerItem, e.bag, e.slot)
            inSellCall = false
            if not ok then
                SellFinish(r)
                error(err, 0)
            end
            if sellBlocked then
                SellFinish(r)
            else
                SellLater(r)
            end
            return
        end
    end
    SellFinish(r)
end

local function SellOnShow(mod)
    sellOpen = true
    if run or sellBlocked then return end
    local r = { list = {}, i = 1, attempts = 0, sold = 0, total = 0, refused = 0 }
    run = r
    -- A short wait so the window and the bags have settled.
    mod:After(SELL_START_DELAY, function()
        if run ~= r then return end
        r.list = ScanJunk()
        SellStep(r)
    end)
end

local function SellOnClosed()
    sellOpen = false
    if run then SellFinish(run) end
end

-- Selling something with a trade timer raises the game's own question. We
-- never answer it; we just stop.
local function SellOnConfirmNeeded()
    if run then SellFinish(run) end
end

local function SellOnRefusedCall(mod, _, addon, func)
    if sellBlocked then return end
    if not (inSellCall or RefusedCallIsOurs(addon, func, "UseContainerItem")) then return end
    sellBlocked = true
    mod:Print("The game blocked automatic selling. Please sell junk by hand.")
    if run and not inSellCall then SellFinish(run) end
end

sellJunk = PE:RegisterModule({
    key = "sellJunk",
    label = "Sell junk automatically",
    desc = "Sells grey items when you open a vendor.",
    order = 40,

    OnEnable = function(mod)
        if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
                and C_Container.UseContainerItem and C_Item and C_Item.GetItemInfo) then
            error("This game version does not have the bag functions needed to sell items.", 0)
        end
        -- Switched on with a vendor window already open: nothing until the next visit.
        sellOpen = false
        run = nil
        mod:RegisterEvent("MERCHANT_SHOW", SellOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", SellOnClosed)
        mod:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", SellOnConfirmNeeded)
        mod:RegisterEvent("ADDON_ACTION_BLOCKED", SellOnRefusedCall)
        mod:RegisterEvent("ADDON_ACTION_FORBIDDEN", SellOnRefusedCall)
    end,

    OnDisable = function()
        sellOpen = false
        -- Stops at once; says what was sold so far.
        if run then SellFinish(run, true) end
    end,
})

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

local REPAIR_CHECK_FIRST = 0.4  -- seconds after asking, look whether it worked
local REPAIR_CHECK_AGAIN = 1.2  -- and once more if it had not yet

local repair                 -- the module
local repairOpen = false     -- between MERCHANT_SHOW and MERCHANT_CLOSED
local repairWaiting = false  -- too poor when the window opened: tried again when money changes
local repairBlocked = false  -- the game refused our repair call: no more tries this session
local inRepairCall = false
local repairCheck            -- marks the newest "did it work" look; older ones give up

local function RepairConfirm(cost, token, try)
    repair:After(try == 1 and REPAIR_CHECK_FIRST or REPAIR_CHECK_AGAIN, function()
        if repairCheck ~= token then return end
        if not repairOpen then
            -- The window closed before we could look. The request had been sent.
            repairCheck = nil
            repair:Print("Repaired for " .. Money(cost) .. ".")
            return
        end
        local left = Num((GetRepairAllCost()))
        if left and left < cost then
            repairCheck = nil
            repair:Print("Repaired for " .. Money(cost - left) .. ".")
        elseif try < 2 then
            RepairConfirm(cost, token, try + 1)
        else
            repairCheck = nil
            repair:Print("Could not repair automatically. Use the vendor's repair button.")
        end
    end)
end

local function TryRepair(announce)
    if repairBlocked then return end
    local vendorRepairs = CanMerchantRepair()
    if IsSecret(vendorRepairs) or not vendorRepairs then return end
    local cost, canRepair = GetRepairAllCost()
    cost = Num(cost)
    if not cost or cost <= 0 or IsSecret(canRepair) then return end
    local money = Num(GetMoney())
    if not money then return end
    if money < cost then
        repairWaiting = true
        if announce then repair:Print("Not enough money to repair (needs " .. Money(cost) .. ").") end
        return
    end
    repairWaiting = false
    if not canRepair then return end

    -- false = pay with the character's own money, never the guild bank's.
    inRepairCall = true
    local ok, err = pcall(RepairAllItems, false)
    inRepairCall = false
    if not ok then error(err, 0) end
    if repairBlocked then return end
    local token = {}
    repairCheck = token
    RepairConfirm(cost, token, 1)
end

local function RepairOnShow()
    -- The same visit announced twice: already dealt with.
    if repairOpen and (repairWaiting or repairCheck) then return end
    repairOpen = true
    repairWaiting = false
    TryRepair(true)
end

local function RepairOnClosed()
    repairOpen = false
    repairWaiting = false
end

-- Money came in while the window is open (junk sold, say): try again.
local function RepairOnMoney()
    if repairOpen and repairWaiting then TryRepair(false) end
end

local function RepairOnRefusedCall(mod, _, addon, func)
    if repairBlocked then return end
    if not (inRepairCall or RefusedCallIsOurs(addon, func, "RepairAllItems")) then return end
    repairBlocked = true
    repairCheck = nil
    mod:Print("The game blocked automatic repair. Please use the vendor's repair button.")
end

repair = PE:RegisterModule({
    key = "repair",
    label = "Repair automatically",
    desc = "Repairs your gear at vendors that can, using your own money.",
    order = 50,

    OnEnable = function(mod)
        if not (CanMerchantRepair and GetRepairAllCost and RepairAllItems and GetMoney) then
            error("This game version does not have the functions needed to repair.", 0)
        end
        -- Switched on with a vendor window already open: nothing until the next visit.
        repairOpen = false
        repairWaiting = false
        repairCheck = nil
        mod:RegisterEvent("MERCHANT_SHOW", RepairOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", RepairOnClosed)
        mod:RegisterEvent("PLAYER_MONEY", RepairOnMoney)
        mod:RegisterEvent("ADDON_ACTION_BLOCKED", RepairOnRefusedCall)
        mod:RegisterEvent("ADDON_ACTION_FORBIDDEN", RepairOnRefusedCall)
    end,

    OnDisable = function()
        repairOpen = false
        repairWaiting = false
        repairCheck = nil
    end,
})
