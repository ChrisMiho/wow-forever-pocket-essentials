-- Rules for "Sell junk automatically" and "Repair automatically" (Vendor.lua).
-- Sources: Vendor.lua's header and comments; docs/DECISIONS.md, section
-- "Decisions made without the maintainer", part "Vendor"; PRD.md goals 3 and 4.
-- Each test names its source in a comment. Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

-- One bag item. id must be unique in a test: the item database is looked up by id.
local function item(id, quality, price, extra)
    local it = { itemID = id, name = "Item " .. id, quality = quality, price = price, count = 1 }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end

local function put(c, bag, slot, it)
    local w = c.world
    if (w.bagSizes[bag] or 0) < slot then w.bagSizes[bag] = slot end
    w.bags[bag][slot] = it
end

-- A backpack of 16 slots; fill(c) puts things in it.
local function visit(opts, fill)
    return T.new({ on = opts.on, setup = function(c)
        c.world.bagSizes[0] = 16
        c.world.money = opts.money or 100000
        if opts.merchant then for k, v in pairs(opts.merchant) do c.world.merchant[k] = v end end
        if fill then fill(c) end
    end })
end

local function coin(c, copper) return c.env.C_CurrencyInfo.GetCoinTextureString(copper) end

local function lineStartingWith(c, prefix)
    local found = {}
    for _, line in ipairs(T.chatLines(c)) do
        if line:sub(1, #prefix) == prefix then found[#found + 1] = line end
    end
    return found
end

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------

-- Vendor.lua header; DECISIONS "Vendor": "An item must be grey ..., have a price".
test("sell junk: sells every grey item with a price, in bag order (exact list)", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(101, 1, 50))         -- white: kept
        put(c, 0, 2, item(102, 0, 5))          -- grey: sold
        put(c, 0, 3, item(103, 0, 6, { count = 4 })) -- grey stack: sold
        put(c, 0, 5, item(104, 2, 90))         -- green: kept
        c.world.bagSizes[1] = 4
        put(c, 1, 2, item(105, 0, 7))          -- grey in the first bag: sold
        c.world.bagSizes[2] = 2
        put(c, 2, 1, item(106, 3, 70))         -- blue: kept
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 }, { 0, 3 }, { 1, 2 } })
    c:assertClean("sell junk")
end)

-- DECISIONS "Vendor": "grey according to both the bag slot and the item database".
test("sell junk: skips an item that is grey in the bag slot but not in the item database", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(201, 0, 5, { dbQuality = 1 }))   -- bag says grey, database says white
        put(c, 0, 2, item(202, 0, 5))                       -- grey in both: sold
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 } })
end)

test("sell junk: skips an item that is grey in the item database but not in the bag slot", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(211, 1, 5, { dbQuality = 0 }))   -- database says grey, bag says white
        put(c, 0, 2, item(212, 0, 5))
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 } })
end)

-- DECISIONS "Vendor": "not be locked"; Vendor.lua JunkAt.
test("sell junk: skips locked items", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(301, 0, 5, { locked = true }))
        put(c, 0, 2, item(302, 0, 5))
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 } })
end)

-- DECISIONS "Vendor": "have a price"; Vendor.lua JunkAt (noValue, price <= 0).
test("sell junk: skips grey items with no price", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(401, 0, 0))     -- price 0
        put(c, 0, 2, item(402, 0, nil))   -- no price at all
        put(c, 0, 3, item(403, 0, 3))
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 3 } })
end)

-- DECISIONS "Vendor": 'Bags the player marked "ignore for junk" ... are skipped.'
test("sell junk: skips a bag marked ignore-for-junk, and the backpack when it is marked", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(501, 0, 5))
        c.world.bagSizes[1] = 2
        put(c, 1, 1, item(502, 0, 5))     -- bag 1: ignored
        c.world.bagSizes[2] = 2
        put(c, 2, 1, item(503, 0, 5))
        c.world.ignoreJunk[1] = true
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 1 }, { 2, 1 } })

    local c2 = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(511, 0, 5))     -- backpack: ignored
        c.world.bagSizes[1] = 2
        put(c, 1, 1, item(512, 0, 5))
        c.world.ignoreJunk[0] = true
    end)
    c2:openMerchant()
    c2:advance(5)
    eq(T.sold(c2), { { 1, 1 } })
end)

-- DECISIONS "Vendor": "No cap on how many greys sell per visit".
test("sell junk: sells more than 12 in one visit (no cap)", function()
    local expected = {}
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 16 do put(c, 0, slot, item(600 + slot, 0, 3)) end
        c.world.bagSizes[1] = 8
        for slot = 1, 8 do put(c, 1, slot, item(630 + slot, 0, 3)) end
    end)
    for slot = 1, 16 do expected[#expected + 1] = { 0, slot } end
    for slot = 1, 8 do expected[#expected + 1] = { 1, slot } end
    c:openMerchant()
    c:advance(10)
    eq(T.sold(c), expected)
end)

-- Vendor.lua SellStep and SELL_STEP: one item about every 0.2 seconds.
test("sell junk: sells one item about every 0.2 seconds, not all at once", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(700 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.2)
    eq(#T.sold(c), 0, "before the start delay of 0.3 s")
    c:advance(0.2) -- 0.4 s: the first sale at 0.3 s
    eq(#T.sold(c), 1, "after 0.4 s")
    c:advance(0.4) -- 0.8 s: second at 0.5 s, third at 0.7 s
    eq(#T.sold(c), 3, "after 0.8 s")
end)

-- DECISIONS "Vendor": "Selling pauses in combat"; Vendor.lua SellStep (RunOutOfCombat).
test("sell junk: pauses while in combat and resumes after the fight", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(800 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(#T.sold(c), 1, "one sold before the fight")
    c:enterCombat()
    c:advance(3)
    eq(#T.sold(c), 1, "nothing sold during combat")
    c:leaveCombat()
    c:advance(3)
    eq(T.sold(c), { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 } })
    c:assertClean("combat pause")
end)

-- DECISIONS "Vendor": "stops if a trade window ... is up"; Vendor.lua SellStep.
test("sell junk: stops when a trade window opens, and does not resume", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(900 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(#T.sold(c), 1)
    c.env.TradeFrame:Show()
    c:advance(3)
    eq(T.sold(c), { { 0, 1 } })
    c.env.TradeFrame:Hide()
    c:advance(3)
    eq(T.sold(c), { { 0, 1 } }, "the trade closing does not restart the sale")
end)

-- DECISIONS "Vendor": "stops if a ... spell-target cursor is up".
test("sell junk: stops when a spell is waiting for a target", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(1000 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(#T.sold(c), 1)
    c.world.spellTargeting = true
    c:advance(3)
    eq(T.sold(c), { { 0, 1 } })
end)

-- Vendor.lua SellStep: "repair cursor up ... a 'use' would mean something else now".
test("sell junk: stops when the vendor's repair cursor is up", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(1100 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    c.world.repairMode = true
    c:advance(3)
    eq(T.sold(c), { { 0, 1 } })
end)

-- Vendor.lua SellOnClosed / SellStep (window gone).
test("sell junk: stops when the vendor window closes, and reports what was sold so far", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(1200 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    c:closeMerchant()
    local lines = lineStartingWith(c, "Sold ")
    eq(lines, { "Sold 1 junk item for " .. coin(c, 3) .. "." })
    c:advance(5)
    eq(T.sold(c), { { 0, 1 } })
    eq(#lineStartingWith(c, "Sold "), 1, "the line is printed once")
end)

-- Vendor.lua SellStep line 165 (VendorWindowShown): if the window is gone without a closed event, the next step stops.
test("sell junk: sells nothing more once the vendor window is gone, even without a closed event", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(1400 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(T.sold(c), { { 0, 1 } })
    c.env.MerchantFrame:Hide()    -- the window goes, no MERCHANT_CLOSED
    c:advance(5)
    eq(T.sold(c), { { 0, 1 } }, "kept selling with the window gone")
    c:assertClean("window gone")
end)

-- DECISIONS "Vendor": "Nothing is ever auto-confirmed"; Vendor.lua header.
test("sell junk: never calls a confirm function (only UseContainerItem and RepairAllItems are called)", function()
    local c = visit({ on = { "sellJunk", "repair" }, merchant = { canRepair = true, repairCost = 500 } }, function(c)
        put(c, 0, 1, item(1301, 0, 5))
        put(c, 0, 2, item(1302, 5, 5))   -- a legendary with a price: stays, so no "are you sure" can arise
    end)
    c:openMerchant()
    c:advance(5)
    local names = {}
    for _, call in ipairs(c.calls) do names[call.name] = true end
    eq(names, { ["C_Container.UseContainerItem"] = true, RepairAllItems = true })
    for key in pairs(c.missing) do
        check(not key:lower():find("confirm") and not key:lower():find("popup") and not key:lower():find("accept"),
            "the addon looked up a confirm-like name: " .. key)
    end
    eq(c.blocked, {})
end)

-- DECISIONS "Vendor": 'e.g. "Sold 7 junk items for 1g 20s 5c."'. Vendor.lua SellReport.
test("sell junk: the chat line reports the money gained (game coin text)", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(1401, 0, 12345))
        put(c, 0, 2, item(1402, 0, 250, { count = 3 }))   -- 750 for the stack
    end)
    c:openMerchant()
    c:advance(5)
    eq(c.world.money, 100000 + 12345 + 750)
    eq(T.chatLines(c), { "Sold 2 junk items for " .. coin(c, 13095) .. "." })
end)

test("sell junk: the chat line uses the plain 'Xg Ys Zc' form when the game has no coin text", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(1411, 0, 12345))
        put(c, 0, 2, item(1412, 0, 250, { count = 3 }))
    end)
    rawset(c.env, "C_CurrencyInfo", nil)
    c:openMerchant()
    c:advance(5)
    eq(T.chatLines(c), { "Sold 2 junk items for 1g 30s 95c." })
end)

test("sell junk: the chat line says 'item' for one and nothing is said when nothing sold", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(1421, 0, 7))
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.chatLines(c), { "Sold 1 junk item for 7|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t." })

    local c2 = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(1422, 1, 7))
    end)
    c2:openMerchant()
    c2:advance(5)
    eq(T.chatLines(c2), {})
    eq(T.sold(c2), {})
end)

-- Vendor.lua line 78-80: the repair cost is added back, so the line is junk money only.
test("sell junk: the money line does not count the repair bill", function()
    local c = visit({ on = { "sellJunk", "repair" }, money = 10000, merchant = { canRepair = true, repairCost = 2000 } },
        function(c) put(c, 0, 1, item(1431, 0, 40)) end)
    c:openMerchant()
    c:advance(5)
    eq(c.world.money, 10000 - 2000 + 40)
    eq(lineStartingWith(c, "Sold "), { "Sold 1 junk item for " .. coin(c, 40) .. "." })
end)

-- PRD.md rule: features default off; Core.lua. With the switch off nothing registers.
test("sell junk: nothing happens with the feature off", function()
    local c = visit({}, function(c)
        for slot = 1, 3 do put(c, 0, slot, item(1500 + slot, 0, 5)) end
    end)
    c:openMerchant()
    c:advance(5)
    c:closeMerchant()
    c:advance(2)
    eq(T.sold(c), {})
    eq(c.calls, {})
    eq(T.chatLines(c), {})
end)

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

-- DECISIONS "Vendor": 'e.g. ... "Repairing for 12s 40c."'. Vendor.lua RepairOnShow.
test("repair: repairs once when the vendor can repair and the money is enough, and says so", function()
    local c = visit({ on = { "repair" }, money = 5000, merchant = { canRepair = true, repairCost = 1240 } })
    c:openMerchant()
    c:advance(1)
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(c.world.money, 5000 - 1240)
    eq(T.chatLines(c), { "Repairing for " .. coin(c, 1240) .. "." })
    -- one try per visit: the vendor window event again does nothing more
    c:fire("MERCHANT_SHOW")
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(#T.chatLines(c), 1)
end)

test("repair: repairs when the money is exactly the cost", function()
    local c = visit({ on = { "repair" }, money = 1240, merchant = { canRepair = true, repairCost = 1240 } })
    c:openMerchant()
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(c.world.money, 0)
end)

-- Vendor.lua line 9-10 and 258-259: "never the guild's"; "false = pay with the character's own money".
test("repair: never uses guild funds (RepairAllItems is called with false)", function()
    local c = visit({ on = { "repair" }, merchant = { canRepair = true, repairCost = 300 } })
    c.world.guild = "Pocket Guild"
    c:openMerchant()
    local calls = c:callsTo("RepairAllItems")
    eq(#calls, 1)
    eq(calls[1].args.n, 1)
    eq(calls[1].args[1], false)
end)

-- DECISIONS "Vendor": "If the character cannot afford the repair it says so once and does not retry that visit."
test("repair: with too little money it says so once and does not retry that visit", function()
    local c = visit({ on = { "repair" }, money = 500, merchant = { canRepair = true, repairCost = 1240 } })
    c:openMerchant()
    c:advance(2)
    eq(#c:callsTo("RepairAllItems"), 0)
    eq(T.chatLines(c), { "Not enough money to repair (needs " .. coin(c, 1240) .. ")." })
    -- money arrives mid-visit and the window event comes again: still no retry, still one line
    c.world.money = 5000
    c:fire("MERCHANT_SHOW")
    c:advance(2)
    eq(#c:callsTo("RepairAllItems"), 0)
    eq(#T.chatLines(c), 1)
    -- a new visit tries again
    c:closeMerchant()
    c:openMerchant()
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(c.world.money, 5000 - 1240)
end)

-- Vendor.lua RepairOnShow: CanMerchantRepair false returns before anything is said.
test("repair: does nothing at a vendor that cannot repair", function()
    local c = visit({ on = { "repair" }, merchant = { canRepair = false, repairCost = 1240 } })
    c:openMerchant()
    c:advance(2)
    eq(c:callsTo("RepairAllItems"), {})
    eq(T.chatLines(c), {})
end)

-- Vendor.lua RepairOnShow: cost <= 0 means nothing is damaged.
test("repair: does nothing when nothing is damaged", function()
    local c = visit({ on = { "repair" }, merchant = { canRepair = true, repairCost = 0 } })
    c:openMerchant()
    c:advance(2)
    eq(c:callsTo("RepairAllItems"), {})
    eq(T.chatLines(c), {})
end)

test("repair: nothing happens with the feature off", function()
    local c = visit({}, nil)
    c.world.merchant.canRepair, c.world.merchant.repairCost = true, 800
    c:openMerchant()
    c:advance(2)
    eq(c.calls, {})
    eq(T.chatLines(c), {})
    eq(c.world.money, 100000)
end)

-- Vendor.lua header: "The two do not know about each other"; DECISIONS "Vendor"; PRD goal 3 (separate switches).
test("repair and sell junk: each switch works without the other", function()
    local function setup(c)
        put(c, 0, 1, item(1601, 0, 5))
        c.world.merchant.canRepair, c.world.merchant.repairCost = true, 300
    end
    local c = visit({ on = { "repair" } }, setup)
    c:openMerchant()
    c:advance(5)
    eq(#c:callsTo("RepairAllItems"), 1, "repair alone repairs")
    eq(T.sold(c), {}, "repair alone sells nothing")

    local c2 = visit({ on = { "sellJunk" } }, setup)
    c2:openMerchant()
    c2:advance(5)
    eq(T.sold(c2), { { 0, 1 } }, "sell junk alone sells")
    eq(#c2:callsTo("RepairAllItems"), 0, "sell junk alone does not repair")
end)

test("repair and sell junk: switching one off leaves the other working", function()
    local function setup(c)
        put(c, 0, 1, item(1611, 0, 5))
        c.world.merchant.canRepair, c.world.merchant.repairCost = true, 300
    end
    local c, PE = visit({ on = { "sellJunk", "repair" } }, setup)
    PE:SetModuleEnabled("sellJunk", false)
    c:openMerchant()
    c:advance(5)
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(T.sold(c), {})

    local c2, PE2 = visit({ on = { "sellJunk", "repair" } }, setup)
    PE2:SetModuleEnabled("repair", false)
    c2:openMerchant()
    c2:advance(5)
    eq(#c2:callsTo("RepairAllItems"), 0)
    eq(T.sold(c2), { { 0, 1 } })
end)


---------------------------------------------------------------------------
-- Rechecks just before each sale, and switching off mid-visit
---------------------------------------------------------------------------

-- Vendor.lua SellStep (the look "again just before it goes: same item, still grey, ... not locked").
test("sell junk: an item locked after the scan, while it waits its turn, is not sold", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 4 do put(c, 0, slot, item(1700 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(T.sold(c), { { 0, 1 } })
    c.world.bags[0][2].locked = true
    c:advance(5)
    eq(T.sold(c), { { 0, 1 }, { 0, 3 }, { 0, 4 } })
end)

test("sell junk: a slot whose item was replaced after the scan is not sold (not grey, or another item)", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 4 do put(c, 0, slot, item(1710 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    c.world.bags[0][2] = item(1799, 1, 50)   -- a white item moved into the waiting slot
    c.world.bags[0][3] = item(1798, 0, 3)    -- a different grey item in the waiting slot
    c:advance(5)
    eq(T.sold(c), { { 0, 1 }, { 0, 4 } })
end)

-- Vendor.lua JunkAt lines 96-99: "Returns nothing while the item's data has not arrived ... left alone for this visit."
test("sell junk: an item whose data has not loaded is left alone for that visit, and sold on the next", function()
    local c = visit({ on = { "sellJunk" } }, function(c)
        put(c, 0, 1, item(1721, 0, 3, { noData = true }))
        put(c, 0, 2, item(1722, 0, 3))
    end)
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 } })
    c.world.bags[0][1].noData = nil
    c:closeMerchant()
    c:openMerchant()
    c:advance(5)
    eq(T.sold(c), { { 0, 2 }, { 0, 1 } })
end)

-- Vendor.lua line 230-231: OnDisable = SellOnClosed ("Stops at once; says what was sold so far").
test("sell junk: switching it off during a visit stops selling at once and reports what was sold", function()
    local c, PE = visit({ on = { "sellJunk" } }, function(c)
        for slot = 1, 5 do put(c, 0, slot, item(1730 + slot, 0, 3)) end
    end)
    c:openMerchant()
    c:advance(0.4)
    eq(T.sold(c), { { 0, 1 } })
    PE:SetModuleEnabled("sellJunk", false)
    eq(T.chatLines(c), { "Sold 1 junk item for " .. coin(c, 3) .. "." }, "the line comes at once")
    c:advance(5)
    eq(T.sold(c), { { 0, 1 } })
    eq(#T.chatLines(c), 1)
end)

-- Vendor.lua RepairOnShow line 255: "if not canRepair then return end" (GetRepairAllCost's second value
-- means something is repairable; see fakeclient.lua).
test("repair: does nothing when the game says nothing can be repaired, even with a cost and the money", function()
    local c = visit({ on = { "repair" }, merchant = { canRepair = true, repairCost = 500, canRepairAll = false } })
    c:openMerchant()
    c:advance(2)
    eq(c:callsTo("RepairAllItems"), {})
    eq(T.chatLines(c), {})
    eq(c.world.money, 100000)
end)

return { known = KNOWN_FAILURES }
