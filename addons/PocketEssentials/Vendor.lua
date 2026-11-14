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

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------

local SELL_START_DELAY = 0.3 -- after the window opens, before the first sale
local SELL_STEP = 0.2        -- seconds between sales
local SELL_MAX = 12          -- sales per visit: what the vendor's buyback page holds
local SELL_REPORT_DELAY = 1  -- after the last sale, before the chat line

local POOR = 0
if Enum and Enum.ItemQuality and type(Enum.ItemQuality.Poor) == "number" then
    POOR = Enum.ItemQuality.Poor
end

-- Copper our own repair feature has asked the vendor to take, in total. The
-- sell line is worked out from the change in money, so it adds this back.
local repairSpent = 0

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

-- Prints the visit's one line, once: how many were sold and how much money
-- came in. Nothing if nothing was tried or no money arrived.
local function SellReport(r)
    if r.reported then return end
    r.reported = true
    r.stopped = true
    if r.attempts <= 0 or not r.startMoney then return end
    local money = Num(GetMoney())
    if not money then return end
    local gain = money - r.startMoney + (repairSpent - r.startRepair)
    if gain <= 0 then return end
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
    local text = "Sold " .. r.attempts .. (r.attempts == 1 and " junk item for " or " junk items for ") .. Money(gain) .. "."
    if more then text = text .. " (more left - reopen the vendor)" end
    sellJunk:Print(text)
end

-- No more sales this visit; the line follows once the money has come in.
local function SellStop(r)
    if r.stopped then return end
    r.stopped = true
    sellJunk:After(SELL_REPORT_DELAY, function() SellReport(r) end)
end

-- One step: sell the next grey item, then wait.
local function SellStep(r)
    if run ~= r or r.stopped then return end
    if not VendorWindowShown()
            or (InRepairMode and InRepairMode())
            or (TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown())
            or (SpellIsTargeting and SpellIsTargeting()) then
        -- Window gone, repair cursor up, a trade open or a spell waiting
        -- for a target: a "use" would mean something else now.
        SellStop(r)
        return
    end
    if PE:InCombat() then
        -- Not while fighting: carry on when the fight ends, if still here.
        PE:RunOutOfCombat("sellJunk:resume", function() SellStep(r) end)
        return
    end
    if r.attempts >= SELL_MAX then
        r.capped = true
        SellStop(r)
        return
    end
    local list = r.list
    while r.i <= #list do
        local e = list[r.i]
        r.i = r.i + 1
        -- Looked at again just before it goes: same item, still grey, still
        -- worth something, not locked. Otherwise skipped.
        if JunkAt(e.bag, e.slot) == e.itemID then
            r.attempts = r.attempts + 1
            C_Container.UseContainerItem(e.bag, e.slot)
            sellJunk:After(SELL_STEP, function() SellStep(r) end)
            return
        end
    end
    SellStop(r)
end

local function SellOnShow(mod)
    if run then return end -- this visit is already being handled
    local r = { list = {}, i = 1, attempts = 0, startMoney = Num(GetMoney()), startRepair = repairSpent }
    run = r
    -- A short wait so the window and the bags have settled.
    mod:After(SELL_START_DELAY, function()
        if run ~= r or r.stopped then return end
        r.list = ScanJunk()
        SellStep(r)
    end)
end

local function SellOnClosed()
    local r = run
    run = nil
    if r then SellReport(r) end
end

sellJunk = PE:RegisterModule({
    key = "sellJunk",
    label = "Sell junk automatically",
    desc = "Sells grey items when you open a vendor.",
    order = 40,

    OnEnable = function(mod)
        if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
                and C_Container.UseContainerItem and C_Item and C_Item.GetItemInfo and GetMoney) then
            error("This game version does not have the functions needed to sell items.", 0)
        end
        -- Switched on with a vendor window already open: nothing until the next visit.
        run = nil
        mod:RegisterEvent("MERCHANT_SHOW", SellOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", SellOnClosed)
    end,

    -- Stops at once; says what was sold so far.
    OnDisable = SellOnClosed,
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
    if IsSecret(vendorRepairs) or not vendorRepairs then return end
    local cost, canRepair = GetRepairAllCost()
    cost = Num(cost)
    if not cost or cost <= 0 or IsSecret(canRepair) then return end
    local money = Num(GetMoney())
    if not money then return end
    if money < cost then
        repair:Print("Not enough money to repair (needs " .. Money(cost) .. ").")
        return
    end
    if not canRepair then return end
    repair:Print("Repairing for " .. Money(cost) .. ".")
    repairSpent = repairSpent + cost
    -- false = pay with the character's own money, never the guild bank's.
    RepairAllItems(false)
end

local function RepairOnClosed()
    repairOpen = false
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
        mod:RegisterEvent("MERCHANT_SHOW", RepairOnShow)
        mod:RegisterEvent("MERCHANT_CLOSED", RepairOnClosed)
    end,

    OnDisable = RepairOnClosed,
})
