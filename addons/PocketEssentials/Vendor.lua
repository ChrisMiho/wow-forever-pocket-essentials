local ADDON_NAME, PE = ...

-- Vendor helpers: two separate features, each with its own switch.
--
--   "sellJunk"  sells grey items when a vendor window opens: one item about
--               every 0.2 seconds, until none are left. (Only the last 12
--               sold can be bought back; no cap, by design.)
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

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------

local SELL_START_DELAY = 0.3 -- after the window opens, before the first sale
local SELL_STEP = 0.2        -- seconds between sales
local SELL_REPORT_DELAY = 1  -- after the last sale, before the chat line
local SELL_CHECK_DELAY = 1   -- after the first sale, before checking that it went

local POOR = 0
if Enum and Enum.ItemQuality and type(Enum.ItemQuality.Poor) == "number" then
    POOR = Enum.ItemQuality.Poor
end

local sellJunk          -- the module
local run               -- this vendor visit (MERCHANT_SHOW to MERCHANT_CLOSED), or nil

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

-- Prints the visit's one line, once: how many items were sold (a stack of
-- three counts three) and their price, as read from each item just before it
-- went. Not the change in money: buying, buybacks and the time the money takes
-- to arrive would skew that. Nothing if no sale was tried.
local function SellReport(r)
    if r.reported then return end
    r.reported = true
    r.stopped = true
    if r.attempts <= 0 or r.items <= 0 then
        if PE.debugOn then PE:Debug("sellJunk", "money line: nothing said, no sale tried") end
        return
    end
    if PE.debugOn then
        PE:Debug("sellJunk", "money line: " .. r.items .. " items, " .. r.value .. " copper")
    end
    local text = "Sold " .. r.items .. (r.items == 1 and " junk item for " or " junk items for ") .. Money(r.value) .. "."
    sellJunk:Print(text)
end

-- Counts one sale in the line, or (sign -1) takes it off again.
local function CountSale(r, e, sign)
    r.attempts = r.attempts + sign
    r.items = r.items + sign * e.count
    r.value = r.value + sign * e.count * e.price
end

-- No more sales this visit; the line follows a moment later.
local function SellStop(r)
    if r.stopped then return end
    r.stopped = true
    sellJunk:After(SELL_REPORT_DELAY, function() SellReport(r) end)
end

-- Only for the debug log: which of the checks in SellStep ended the selling.
local function StopReason()
    if not VendorWindowShown() then return "vendor window closed" end
    if MerchantFrame and MerchantFrame.selectedTab == 2 then return "Buyback tab showing" end
    if InRepairMode and InRepairMode() then return "repair cursor up" end
    if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then return "trade open" end
    return "spell waiting for a target"
end

-- One step: sell the next grey item, then wait.
local function SellStep(r)
    if run ~= r or r.stopped then return end
    if not VendorWindowShown()
            or (MerchantFrame and MerchantFrame.selectedTab == 2)
            or (InRepairMode and InRepairMode())
            or (TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown())
            or (SpellIsTargeting and SpellIsTargeting()) then
        -- Window gone, the Buyback tab showing (the game's own click sells
        -- nothing there), repair cursor up, a trade open or a spell waiting
        -- for a target: a "use" would mean something else now.
        if PE.debugOn then PE:Debug("sellJunk", "stopped: " .. StopReason()) end
        SellStop(r)
        return
    end
    if PE:InCombat() then
        -- Not while fighting: carry on when the fight ends, if still here.
        if PE.debugOn then PE:Debug("sellJunk", "selling held: in a fight") end
        PE:RunOutOfCombat("sellJunk:resume", function() SellStep(r) end)
        return
    end
    local list = r.list
    while r.i <= #list do
        local e = list[r.i]
        r.i = r.i + 1
        -- Looked at again just before it goes: same item, still grey, still
        -- worth something, not locked. Otherwise skipped.
        local itemID, count, price = JunkAt(e.bag, e.slot)
        if itemID == e.itemID then
            e.count, e.price = count, price
            CountSale(r, e, 1)
            if PE.debugOn then
                PE:Debug("sellJunk", "selling bag " .. e.bag .. " slot " .. e.slot .. " item " .. e.itemID)
            end
            local blockedBefore = PE.blockedSerial
            C_Container.UseContainerItem(e.bag, e.slot)
            if PE.blockedSerial ~= blockedBefore then
                -- The game refused the sale (it reports that synchronously,
                -- inside the call). Trying the next item would only bring its
                -- warning back every step: stop for this visit.
                CountSale(r, e, -1)
                if PE.debugOn then PE:Debug("sellJunk", "stopped: the game refused the sale") end
                sellJunk:Print("The game would not let Pocket Essentials sell items here; stopped selling.")
                SellStop(r)
                return
            end
            if r.checked then
                sellJunk:After(SELL_STEP, function() SellStep(r) end)
                return
            end
            -- The first sale of a visit is looked at again after a longer
            -- wait. An item still in its slot means the game is not selling
            -- for us, and it may not have told us so: stop, so its warning
            -- cannot come back once for every grey item.
            r.checked = true
            sellJunk:After(SELL_CHECK_DELAY, function()
                if run ~= r or r.stopped then return end
                if JunkAt(e.bag, e.slot) == e.itemID then
                    CountSale(r, e, -1)
                    if PE.debugOn then
                        PE:Debug("sellJunk", "first sale check: still there")
                        PE:Debug("sellJunk", "stopped: the first item did not sell")
                    end
                    sellJunk:Print("The first junk item did not sell; stopped selling for this visit.")
                    SellStop(r)
                    return
                end
                if PE.debugOn then PE:Debug("sellJunk", "first sale check: went") end
                SellStep(r)
            end)
            return
        elseif PE.debugOn then
            PE:Debug("sellJunk", "skipped bag " .. e.bag .. " slot " .. e.slot .. ": changed since the scan")
        end
    end
    if PE.debugOn then PE:Debug("sellJunk", "stopped: list finished") end
    SellStop(r)
end

local function SellOnShow(mod)
    if run then return end -- this visit is already being handled
    local r = { list = {}, i = 1, attempts = 0, items = 0, value = 0 }
    run = r
    if PE.debugOn then PE:Debug("sellJunk", "vendor opened") end
    -- A short wait so the window and the bags have settled.
    mod:After(SELL_START_DELAY, function()
        if run ~= r or r.stopped then return end
        r.list = ScanJunk()
        if PE.debugOn then PE:Debug("sellJunk", "found " .. #r.list .. " grey items to sell") end
        SellStep(r)
    end)
end

-- `why` is only for the debug log.
local function SellEnd(why)
    local r = run
    run = nil
    if r then
        if PE.debugOn and not r.stopped then PE:Debug("sellJunk", "stopped: " .. why) end
        SellReport(r)
    end
end

local function SellOnClosed()
    SellEnd("vendor window closed")
end

sellJunk = PE:RegisterModule({
    key = "sellJunk",
    label = "Auto sell junk",
    desc = "Sells grey items when you open a vendor.",
    order = 40,

    OnEnable = function(mod)
        if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
                and C_Container.UseContainerItem and C_Item and C_Item.GetItemInfo) then
            error("This game version does not have the functions needed to sell items.", 0)
        end
        -- Switched on with a vendor window already open: nothing until the next visit.
        run = nil
        mod:RegisterEvent("MERCHANT_SHOW", SellOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", SellOnClosed)
    end,

    -- Stops at once; says what was sold so far.
    OnDisable = function()
        SellEnd("switched off")
    end,
})

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

local repair              -- the module
local repairOpen = false  -- between MERCHANT_SHOW and MERCHANT_CLOSED: one try per visit

local function RepairOnShow()
    if repairOpen then return end
    repairOpen = true
    local vendorRepairs = CanMerchantRepair()
    if PE.debugOn then PE:Debug("repair", "vendor opened, can repair: " .. PE.Plain(vendorRepairs)) end
    if IsSecret(vendorRepairs) or not vendorRepairs then return end
    local cost, canRepair = GetRepairAllCost()
    if PE.debugOn then
        PE:Debug("repair", "cost " .. PE.Plain(cost) .. " copper, repair possible: " .. PE.Plain(canRepair))
    end
    cost = Num(cost)
    if not cost or cost <= 0 or IsSecret(canRepair) then
        if PE.debugOn then PE:Debug("repair", "nothing to repair, or the cost is unreadable") end
        return
    end
    local money = Num(GetMoney())
    if PE.debugOn then PE:Debug("repair", "money " .. (money or "unreadable") .. " copper") end
    if not money then return end
    if money < cost then
        if PE.debugOn then PE:Debug("repair", "not enough money") end
        repair:Print("Not enough money to repair (needs " .. Money(cost) .. ").")
        return
    end
    if not canRepair then
        if PE.debugOn then PE:Debug("repair", "not repaired: the game says it cannot repair now") end
        return
    end
    local blockedBefore = PE.blockedSerial
    -- false = pay with the character's own money, never the guild bank's.
    RepairAllItems(false)
    if PE.blockedSerial ~= blockedBefore then
        -- The game refused (it reports that inside the call): nothing was spent.
        if PE.debugOn then PE:Debug("repair", "refused by the game") end
        repair:Print("The game would not let Pocket Essentials repair here.")
        return
    end
    if PE.debugOn then PE:Debug("repair", "repaired for " .. cost .. " copper") end
    repair:Print("Repairing for " .. Money(cost) .. ".")
end

local function RepairOnClosed()
    repairOpen = false
end

repair = PE:RegisterModule({
    key = "repair",
    label = "Auto repair",
    desc = "Repairs your gear at vendors, with your own gold.",
    order = 50,

    OnEnable = function(mod)
        if not (CanMerchantRepair and GetRepairAllCost and RepairAllItems and GetMoney) then
            error("This game version does not have the functions needed to repair.", 0)
        end
        -- Switched on with a vendor window already open: nothing until the next visit.
        repairOpen = false
        mod:RegisterEvent("MERCHANT_SHOW", RepairOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", RepairOnClosed)
    end,

    OnDisable = RepairOnClosed,
})
