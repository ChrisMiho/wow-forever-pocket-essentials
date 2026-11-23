local ADDON_NAME, P = ...

-- Pocket Probe: a test tool. It tries a list of addon actions in each
-- situation the player gets into and saves what the game answered. It only
-- reports; it never tries to get round a block.
--
--   Core.lua    saved table, the situation, reading values safely, recording
--   Trials.lua  the list of trials (one small function each, plus an undo)
--   Errors.lua  the Errors and Graphics trials, and the error box listener
--   Run.lua     noticing blocks, passes, the clean series, guided trials
--   Watch.lua   the watchers armed for the next fights, and Clear saved
--               results (probe 0.7.0; its game names are listed at its top)
--   Panel.lua   the window that drives it all (touch and d-pad)
--   Perf.lua    the performance recorder (probe 0.6.0; its game names and
--               their proof are listed at its top)
--
-- Nothing runs by itself: the automatic passes of 0.2.0 only run with the
-- "Auto" switch on (off by default). The listeners that only record stay.
-- The one exception is the performance recorder, which starts at login when
-- Pocket Essentials is loaded too (Perf.lua).
--
-- Every game name used, and where Blizzard's source for build 1.60.1 (70938)
-- proves it (paths under Interface/AddOns; "Doc/" is
-- Blizzard_APIDocumentationGenerated/). Each one is looked up before use, so
-- a name this client lacks gives the result "missing" and no Lua error.
--
--   Name                                         Proof
--   CreateFrame                                  Blizzard_GamepadSmartNavigation/SecureHelper.lua:1
--   hooksecurefunc                               Blizzard_GamepadSmartNavigation/SmartNavigation.lua:260
--   DisplayInterfaceActionBlockedMessage         Blizzard_ChatFrameBase/Mainline/ChatFrameUtilOverrides.lua:3
--   GameEvent.HandleActionBlocked (stack text)   Blizzard_Game/Mainline/EventImplementation.lua:375
--   ADDON_ACTION_BLOCKED / _FORBIDDEN            Doc/RestrictedActionsDocumentation.lua:77, 88
--   ADDON_RESTRICTION_STATE_CHANGED              Doc/RestrictedActionsDocumentation.lua:99
--   C_RestrictedActions.IsAddOnRestrictionActive Doc/RestrictedActionsDocumentation.lua:55
--   Enum.AddOnRestrictionType (six values)       Doc/RestrictedActionsConstantsDocumentation.lua:19
--   InCombatLockdown                             Doc/RestrictedActionsDocumentation.lua:45
--   C_InputInterfaceStyle.GetCurrentStyle        Doc/InputInterfaceStyleDocumentation.lua:11
--   Enum.InputDeviceInterfaceType.Gamepad        Doc/InputConstantsDocumentation.lua:28
--   IsInInstance                                 Doc/InstanceDocumentation.lua:170
--   GetBuildInfo                                 Doc/BuildDocumentation.lua:10
--   C_AddOns.GetAddOnMetadata                    Doc/AddOnsDocumentation.lua:165
--   C_Timer.After                                Doc/UITimerDocumentation.lua:11
--   C_UI.Reload                                  Doc/UIManagerDocumentation.lua:65
--   ReloadUI                                     Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1297
--   issecretvalue, canaccessvalue                Doc/FrameScriptDocumentation.lua:287, 65
--   debugstack                                   Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:59
--   date                                         Blizzard_FrameXMLUtil/GameTimeUtil.lua:78
--   GetTime                                      Doc/SystemTimeDocumentation.lua:57
--   SlashCmdList, SLASH_<KEY>1                   Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua:16
--   UISpecialFrames                              Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:21
--   GamepadMode.FrameControlsManager             Blizzard_GamepadSharedUtility/FrameControlsManager.lua:1012
--     :GetActiveFrame                            Blizzard_GamepadSharedUtility/FrameControlsManager.lua:834
--   PLAYER_ENTERING_WORLD, PLAYER_LOGIN          Doc/SystemDocumentation.lua:136, 153
--   ADDON_LOADED                                 Doc/AddOnsDocumentation.lua:391
--   PLAYER_REGEN_DISABLED / _ENABLED             Doc/UnitDocumentation.lua:3887, 3893
--   MERCHANT_SHOW / MERCHANT_CLOSED              Doc/MerchantFrameDocumentation.lua:112, 96
--   CHAT_MSG_WHISPER                             Doc/ChatInfoDocumentation.lua:2594
--   ChatFrameUtil.OpenChat                       Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:448
--   ChatFrameUtil.GetActiveWindow                Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:511
--   ChatFrameUtil.DeactivateChat                 Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:564
--   ChatFrameUtil.ChooseBoxForSend               Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:572
--   edit box :GetChatType / :SetChatType         Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:14, 18
--   edit box :SetFocus / :ClearFocus / :HasFocus Doc/SimpleEditBoxAPIDocumentation.lua:668, 20, 408
--   ChatFrame1                                   Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.xml:709
--   WorldMapFrame                                Blizzard_WorldMap/Blizzard_WorldMap.xml:67
--   ContainerFrameCombinedBags, ContainerFrame1  Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:313, 298
--   OpenAllBags / IsAnyBagOpen / CloseAllBags    Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:2153, 2235, 2282
--   region :SetParent (a frame or nil)           Doc/SimpleScriptRegionAPIDocumentation.lua:653
--   region :GetPoint / :SetPoint                 Doc/SimpleScriptRegionResizingAPIDocumentation.lua:65, 135
--   frame :GetScale / :SetScale                  Doc/SimpleFrameAPIDocumentation.lua:621, 1472
--   :GetName, :GetParent                         Doc/SimpleFrameScriptObjectAPIDocumentation.lua:107, Doc/SimpleObjectAPIDocumentation.lua:34
--   SetOverrideBindingClick                      Blizzard_GamepadSharedUtility/InputBindingStack/InputFunctionBinding.lua:49
--   ClearOverrideBindings                        Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:538
--   GetBindingAction(key, checkOverride)         Blizzard_Kiosk/BlizzCon2026/ColdSwap.lua:153
--   "PADRSTICK" (right stick click)              Blizzard_SharedXML/SharedConstants.lua:72
--   SmartNavigation_MarkFrameIgnored             Blizzard_GamepadSmartNavigation/Utility.lua:46
--   SmartNavigation_ClearIgnoreStatus            Blizzard_GamepadSmartNavigation/Utility.lua:54
--   C_Container.SortBags                         Doc/ContainerDocumentation.lua:554
--   C_Container.UseContainerItem                 Doc/ContainerDocumentation.lua:584
--   C_Container.GetContainerItemInfo             Doc/ContainerDocumentation.lua:192 (fields: 766)
--   C_Container.GetContainerNumSlots             Doc/ContainerDocumentation.lua:313
--   C_Container.GetBackpackSellJunkDisabled      Doc/ContainerDocumentation.lua:57
--   C_Container.GetBagSlotFlag                   Doc/ContainerDocumentation.lua:81
--   Enum.BagSlotFlags.ExcludeJunkSell            Doc/BagConstantsDocumentation.lua:56
--   Enum.ItemQuality.Poor                        Doc/ItemQualitiesDocumentation.lua:13
--   BACKPACK_CONTAINER, NUM_BAG_SLOTS            Blizzard_FrameXMLBase/Constants.lua:165, 168
--   C_Item.GetItemInfo                           Doc/ItemDocumentation.lua:626
--   C_MerchantFrame.GetNumJunkItems              Doc/MerchantFrameDocumentation.lua:53 (used: Mainline/MerchantFrame.lua:210)
--   C_MerchantFrame.IsSellAllJunkEnabled         Doc/MerchantFrameDocumentation.lua:77 (used: Mainline/MerchantFrame.lua:482)
--   C_MerchantFrame.SellAllJunkItems             Doc/MerchantFrameDocumentation.lua:86 (used: Mainline/MerchantFrame.lua:1125)
--   CanMerchantRepair                            Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua:988
--   GetRepairAllCost, RepairAllItems             Blizzard_UIPanels_Game/Mainline/MerchantFrame.xml:255, 268
--   GetMoney                                     Doc/PlayerScriptDocumentation.lua:642
--   C_CVar.GetCVar / SetCVar (no secret values)  Doc/CVarDocumentation.lua:20, 131
--   "combinedBags" setting                       Blizzard_SettingsDefinitions_Shared/Preset.lua:94
--   C_EditMode.GetLayouts / SetActiveLayout      Doc/EditModeManagerDocumentation.lua:60, 131
--   EditModeManagerFrame:IsEditModeActive        Blizzard_EditMode/Shared/EditModeManager.lua:149
--   C_EditMode.SaveLayouts                       Doc/EditModeManagerDocumentation.lua:110 (called: Blizzard_EditMode/Shared/EditModeManager.lua:909)
--   Enum.EditModeLayoutType (Account, Character) Doc/EditModeManagerConstantsDocumentation.lua:511
--   EditModePresetLayoutManager:GetCopyOfPresetLayouts  Blizzard_EditMode/Shared/EditModePresetLayoutsManager.lua:46
--   MinimapCluster                               Blizzard_Minimap/Mainline/Minimap.xml:3
--   PlayerFrame, PetFrame                        Blizzard_UnitFrame/Mainline/PlayerFrame.xml:13, PetFrame.xml:11
--   TargetFrame                                  Blizzard_UnitFrame/Mainline/TargetFrame.xml:549
--   SwingTimerMainHandFrame                      Blizzard_SwingTimer/Blizzard_SwingTimer.xml:56
--   GamepadMainActionBarFrame                    Blizzard_GamepadActionBars/MainActionBarFrame.xml:3
--     .PageUnit                                  Blizzard_GamepadActionBars/ActionBarEditFrame.xml:125
--     .useCompactLayout / .showEmptyBars / .shouldExpand   Blizzard_GamepadActionBars/MainActionBarFrame.lua:113, 119, 136
--   PageUnit's four anchors and their .Bar       Blizzard_GamepadActionBars/ActionBarTemplates.xml:600, 606
--   UIParent (:GetWidth / :GetHeight)            Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:827 (the size read: Blizzard_NewPlayerExperience/Blizzard_TutorialKeyboardMouseFrame.lua:26)
--   region :GetWidth / :GetHeight / :IsProtected Doc/SimpleScriptRegionAPIDocumentation.lua:323, 161, 540
--   region :ClearAllPoints                       Doc/SimpleScriptRegionResizingAPIDocumentation.lua:22
--   BuffFrame, DebuffFrame                       Blizzard_BuffFrame/BuffFrame.xml:6, 87
--   ObjectiveTrackerFrame                        Blizzard_ObjectiveTracker/Blizzard_ObjectiveTracker.xml:3
--   MainStatusTrackingBarContainer               Blizzard_StatusTrackingBar/Mainline/StatusTrackingBar.xml:41
--   GamepadPetActionFlyout                       Blizzard_GamepadActionBars/Camelot/PetClassFlyouts.xml:18
--   PageUnit.LeftClassAction / .RightClassAction Blizzard_GamepadActionBars/MainActionBarFrame.xml:94, 104
--   a bar's .actionButtons[1..8]                 Blizzard_GamepadActionBars/ActionBar.lua:8-17
--   a spell button's .action (its action slot)   Blizzard_ActionBar/Shared/ActionButton.lua:545
--   C_ActionBar.HasAction / GetActionTexture     Doc/ActionBarFrameDocumentation.lua:467, 270
--   C_ActionBar.GetActionCooldown (startTime, duration)   Doc/ActionBarFrameDocumentation.lua:164, Doc/SpellSharedDocumentation.lua:19
--   C_ActionBar.GetActionDisplayCount / IsUsableAction    Doc/ActionBarFrameDocumentation.lua:199, 919
--     (cooldown and count are documented "SecretWhenCooldownsRestricted")
--   region :SetAlpha / :GetAlpha                 Doc/SimpleFrameAPIDocumentation.lua:1134, 276 (not a protected function)
--   region :GetBottom / :GetTop                  Doc/SimpleScriptRegionAPIDocumentation.lua:130, 308
--   frame :GetEffectiveScale                     Doc/SimpleFrameAPIDocumentation.lua:381
--   a spell button's .ButtonIcon (InputIconTextureFrameTemplate)   Blizzard_GamepadActionBars/ActionBarTemplates.xml:163
--     .mappedButtonKey, .NormalTexture           Blizzard_GamepadActionBars/ActionBarTemplates.xml:165,
--                                                Blizzard_SharedXML/Shared/InputIcons/InputIconTexture.xml:10
--   texture :GetAtlas / :SetAtlas                Doc/SimpleTextureBaseAPIDocumentation.lua:45, 368
--   InputDeviceIconSetManager:GetActiveInputDeviceIconSet   Blizzard_SharedXML/Shared/InputIcons/InputDeviceIconSetManager.lua:9, 57
--   InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture   Blizzard_SharedXML/Shared/InputIcons/InputIconTexture.lua:556, 565
--   C_Map.GetBestMapForUnit                      Doc/MapDocumentation.lua:49
--   C_Map.GetPlayerMapPosition (:GetXY)          Doc/MapDocumentation.lua:437, Blizzard_SharedXML/Vector2D.lua:77
--   GetPlayerFacing                              Doc/PlayerScriptDocumentation.lua:828
--   C_QuestLog.GetNumQuestLogEntries / GetInfo   Doc/QuestLogDocumentation.lua:303, 191
--   C_QuestLog.GetQuestObjectives                Doc/QuestLogDocumentation.lua:477
--   UnitName                                     Doc/UnitDocumentation.lua:2489
--
-- Added in 0.5.0 (the fight button, the park and fade tests, the sweep tests):
--   Screenshot                                   Doc/ClientDocumentation.lua:95 (a plain function; Blizzard calls it from Lua
--                                                at Blizzard_CharacterCreate/Camelot/Blizzard_CharacterCreate.lua:457)
--   C_ActionBar.GetActionCooldownDuration        Doc/ActionBarFrameDocumentation.lua:181 (returns a LuaDurationObject)
--   cooldown info .isActive / .isEnabled         Doc/SpellSharedDocumentation.lua:26, 25 (both "NeverSecret")
--   Cooldown:SetCooldownFromDurationObject       Doc/FrameAPICooldownDocumentation.lua:308 (marked protected)
--   Cooldown:SetCooldown(start, duration)        Doc/FrameAPICooldownDocumentation.lua:281 (marked protected)
--   Cooldown:GetCooldownDuration                 Doc/FrameAPICooldownDocumentation.lua:34
--   Cooldown:SetHideCountdownNumbers             Doc/FrameAPICooldownDocumentation.lua:461
--   CooldownFrameTemplate                        Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3 (hidden until a cooldown is set;
--                                                used at Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.xml:35)
--   TopCenteredAnchor.PossessBar / .StanceBar    Blizzard_GamepadActionBars/PageUnit.lua:115, 116
--   PageUnit.FriendlyTargetingActionBar, .HostileTargetingActionBar, .ShortcutsActionBar
--                                                Blizzard_GamepadActionBars/PageUnit.lua:119-121 (moved under the top anchor: 136-147)
--   MinimapCluster.MinimapContainer, Minimap     Blizzard_Minimap/Mainline/Minimap.xml:47, 56 (the container takes the
--                                                Edit Mode size: Blizzard_Minimap/Mainline/Minimap.lua:418-419)
--   region :GetCenter / :IsShown / :IsVisible    Doc/SimpleScriptRegionAPIDocumentation.lua:145, 568, 582
--   region :SetAllPoints                         Doc/SimpleScriptRegionResizingAPIDocumentation.lua:111
--   texture :SetTexture                          Doc/SimpleTextureBaseAPIDocumentation.lua:604
--
-- Added in 0.7.0 for the two guided bar trials (Trials.lua; the watchers'
-- names are at the top of Watch.lua, the Fight button's at the top of Perf.lua):
--   UNIT_SPELLCAST_SUCCEEDED                     Doc/UnitDocumentation.lua:4847 (its unit may be secret
--                                                in a fight: "SecretWhenUnitSpellCastRestricted")
--   frame :RegisterUnitEvent(event, unit)        Doc/SimpleFrameAPIDocumentation.lua:1064
--   frame :UnregisterAllEvents                   Doc/SimpleFrameAPIDocumentation.lua:1588
--   PageUnit:OnFlyoutOpened(button)              Blizzard_GamepadActionBars/PageUnit.lua:719 (called for a
--                                                spell wheel on a bar button: ActionBarButton.lua:737-742)
--   the wheel button's .popup                    Blizzard_GamepadActionBars/PageUnit.lua:726
--   GamepadPetSpellFlyout                        Blizzard_GamepadActionBars/Camelot/PetClassFlyouts.xml:72
--   GamepadPetActionFlyout (above) and it: the two sub-menu wheels. Their
--     buttons (LeftClassAction, RightClassAction) are on no bar, so they never
--     reach PageUnit:OnFlyoutOpened (ActionBarButton.lua:738-742; a button's bar
--     is set only at ActionBar.lua:34-35): their own OnShow is hooked instead.
--   region :HookScript                           Doc/SimpleScriptRegionAPIDocumentation.lua:365
--   frame :GetEffectiveAlpha                     Doc/SimpleFrameAPIDocumentation.lua:366
--   a wheel re-parents itself to UIParent and is centred on its button
--                                                Blizzard_GamepadActionBars/FlyoutRadial.lua:200-224
--
-- Not proven by the source, and guarded:
--   debugstack(start, count1, count2)  only debugstack() and debugstack(level)
--     appear in the source; if the long form fails the short one is used.
--   GetBindingAction returning "CLICK <button>:<mouse button>" for an override
--     binding: if the text is anything else the trial says "no effect".
--   CanMerchantRepair, GetRepairAllCost, RepairAllItems, SetOverrideBindingClick,
--     ClearOverrideBindings, OpenAllBags, CloseAllBags: used by Blizzard's own
--     code but not in the generated documentation, so their restrictions are
--     unknown. Finding those out is what the probe is for.
--   Cooldown:SetCooldown and :SetCooldownFromDurationObject are documented as
--     protected: a refusal is a possible answer, and it is recorded as one.
--   CreateFrame("Cooldown", ..., "CooldownFrameTemplate") is inside a pcall;
--     without it the sweep trials answer "missing".
--   Whether a Cooldown frame shows itself when a cooldown is set is not in
--     the source (the template starts hidden): the sweep trials note it.

local type, tostring, pairs, ipairs, pcall, select = type, tostring, pairs, ipairs, pcall, select
local tconcat, tremove = table.concat, table.remove

P.name = ADDON_NAME or "PocketProbe"
P.VERSION = "0.7.0"          -- used when the game cannot read the TOC's version line
-- An action trial returns this when nothing refused it but it could not see
-- whether it worked; it is stored as it is (never as "allowed").
P.CANT_TELL = "can't tell"

local LOG_MAX, LOG_DROP = 2000, 200   -- the activity log drops its oldest lines in blocks
local DETAILS_MAX = 400
P.PERF_RUNS = 3                        -- performance recordings kept (Perf.lua)
P.WATCH_KEEP = 3                       -- armings of the watchers kept (Watch.lua)
local MESSAGE_MAX = 1500               -- a detail's message, at most
P.MESSAGE_MAX = MESSAGE_MAX

---------------------------------------------------------------------------
-- Looking names up, and values the game may hide
---------------------------------------------------------------------------

-- The value behind a dotted global name ("C_Container.SortBags"), or nil.
function P.Find(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
        if v == nil then return nil end
    end
    return v
end

-- The game can hand addons "secret" values that raise an error when they
-- are compared or used. Anything secret is never looked at.
function P.IsSecret(v)
    local fn = issecretvalue
    if type(fn) ~= "function" then return false end
    local ok, secret = pcall(fn, v)
    if not ok then return true end
    return secret and true or false
end
local IsSecret = P.IsSecret

-- The value if it is an ordinary number; otherwise nil.
function P.Num(v)
    if IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

-- The value if it is ordinary text; otherwise nil.
function P.Str(v)
    if IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- Text that is safe to store: a secret becomes "<secret>", long text is cut.
function P.Plain(v, limit)
    if IsSecret(v) then return "<secret>" end
    local text = tostring(v)
    limit = limit or 300
    if #text > limit then text = text:sub(1, limit) .. "..." end
    return text
end

-- "readable", "secret" or "nil": the class of a value, never the value.
function P.Class(v)
    if IsSecret(v) then return "secret" end
    if v == nil then return "nil" end
    local can = canaccessvalue
    if type(can) == "function" then
        local ok, allowed = pcall(can, v)
        if ok and not IsSecret(allowed) and allowed == false then return "secret" end
    end
    return "readable"
end

---------------------------------------------------------------------------
-- The saved table (format: see docs/superpowers/specs/2026-11-17-restriction-probe.md)
---------------------------------------------------------------------------

local db                    -- PocketProbeDB once the saved file is loaded
local earlyLog = {}         -- lines written before that

local function Stamp(fmt)
    if type(date) ~= "function" then return "" end
    local ok, text = pcall(date, fmt)
    if ok and type(text) == "string" and not IsSecret(text) then return text end
    return ""
end
P.Stamp = Stamp

-- limit: how long the line may be (400 unless given).
function P.Log(text, limit)
    local line = Stamp("%H:%M:%S") .. " " .. P.Plain(text, limit or 400)
    local log = db and db.log or earlyLog
    log[#log + 1] = line
    if #log > LOG_MAX then
        local kept = {}
        for i = LOG_DROP + 1, #log do kept[#kept + 1] = log[i] end
        if db then db.log = kept else earlyLog = kept end
    end
end
local Log = P.Log

-- A script handler that cannot raise: an error goes to the activity log.
function P.Guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then pcall(Log, "error in the probe: " .. P.Plain(err)) end
    end
end

local function GameVersion()
    if type(GetBuildInfo) ~= "function" then return "unknown" end
    local ok, version, build = pcall(GetBuildInfo)
    if not ok then return "unknown" end
    version, build = P.Str(version) or "?", P.Str(build) or "?"
    return version .. " (" .. build .. ")"
end

local function ProbeVersion()
    local fn = P.Find("C_AddOns.GetAddOnMetadata")
    if type(fn) == "function" then
        local ok, v = pcall(fn, P.name, "Version")
        v = ok and P.Str(v)
        if v and v ~= "" then return v end
    end
    return P.VERSION
end

-- Writes back the settings a guided trial saved ({ [name] = value, or false
-- for a setting this client lacks }). Returns the names that could not be
-- written back, sorted (empty when all went back).
function P.PutBackSettings(old)
    local failed = {}
    local set = P.Find("C_CVar.SetCVar")
    for name, value in pairs(type(old) == "table" and old or {}) do
        if type(value) == "string" then
            local ok, done = false, nil
            if type(set) == "function" then ok, done = pcall(set, name, value) end
            if not (ok and not IsSecret(done) and done) then failed[#failed + 1] = tostring(name) end
        end
    end
    table.sort(failed)
    return failed
end

-- Called once, when the saved file has been loaded. Keeps everything earlier
-- sessions stored and refreshes the parts that describe this build.
function P.InitDB()
    local saved = _G.PocketProbeDB
    if type(saved) ~= "table" then saved = {} end
    _G.PocketProbeDB = saved
    -- Results from another probe version were made with another run order:
    -- they are dropped, so one table never mixes the two.
    local version, cleared = ProbeVersion(), nil
    if saved.probe ~= nil and saved.probe ~= version then
        cleared = P.Plain(saved.probe, 40)
        -- "guided" is kept: it holds settings a guided trial still has to put back.
        for _, key in ipairs({ "results", "details", "situations", "spoiled", "log", "last" }) do saved[key] = {} end
        saved.clean, saved.pressIndex = nil, nil
        saved.perf = nil               -- recordings too: their sample lines may differ
    end
    saved.version = 1
    saved.game = GameVersion()
    saved.probe = version
    if type(saved.options) ~= "table" then saved.options = {} end
    if type(saved.options.vendor) ~= "boolean" then saved.options.vendor = true end
    if type(saved.options.risky) ~= "boolean" then saved.options.risky = false end
    if type(saved.options.auto) ~= "boolean" then saved.options.auto = false end
    if type(saved.clean) ~= "table" then saved.clean = {} end
    if type(saved.clean.index) ~= "number" then saved.clean.index = 0 end
    saved.clean.running = saved.clean.running == true
    if type(saved.pressIndex) ~= "number" then saved.pressIndex = 0 end
    for _, key in ipairs({ "situations", "results", "details", "log", "spoiled", "last", "guided" }) do
        if type(saved[key]) ~= "table" then saved[key] = {} end
    end
    -- Performance recordings (Perf.lua): the last few runs are kept.
    if type(saved.perf) ~= "table" then saved.perf = {} end
    if type(saved.perf.runs) ~= "table" then saved.perf.runs = {} end
    while #saved.perf.runs > P.PERF_RUNS do tremove(saved.perf.runs, 1) end
    saved.perf.on, saved.perf.stopped = saved.perf.on == true, saved.perf.stopped == true
    -- The watchers' armings (Watch.lua): the last few are kept. A reload ends
    -- an arming; one the logout did not close (the game stopped) is closed now.
    if type(saved.watch) ~= "table" then saved.watch = {} end
    for i = #saved.watch, 1, -1 do
        if type(saved.watch[i]) ~= "table" then tremove(saved.watch, i) end
    end
    while #saved.watch > P.WATCH_KEEP do tremove(saved.watch, 1) end
    for _, w in ipairs(saved.watch) do
        if w.ended == nil and w.why == nil then w.why = "reload" end
    end
    -- The trial list is written fresh; the "afterwards" entries earlier
    -- sessions added (see P.AddTrial) are kept at its end.
    local old = type(saved.trials) == "table" and saved.trials or {}
    saved.trials = {}
    for i, t in ipairs(P.trials) do
        saved.trials[i] = { id = t.id, area = t.area, label = t.label, kind = t.kind, risky = t.risky or nil }
    end
    db = saved
    P.db = saved
    -- A guided trial this version no longer has: its settings go back now.
    -- One that moved a frame (apply / restore) is called off: a reload puts
    -- the game's frames back by itself, and the spot it kept is gone.
    for id, g in pairs(saved.guided) do
        local t = type(id) == "string" and P.trialById[id] or nil
        if not t or t.apply then
            local failed = P.PutBackSettings(type(g) == "table" and g.old or nil)
            saved.guided[id] = nil
            -- One still waiting for its fight (probe 0.7.0) had changed nothing yet.
            local waited = type(g) == "table" and g.stage == "waitfight"
            earlyLog[#earlyLog + 1] = Stamp("%H:%M:%S") .. " " .. P.Plain(id, 40)
                .. (t and (waited and ": called off by the reload"
                    or (": called off; the reload put " .. tostring(t.hold or "the frame") .. " back"))
                    or ": no such trial any more; settings put back")
                .. (#failed > 0 and (", except " .. tconcat(failed, ", ")) or "")
        end
    end
    for _, t in ipairs(old) do
        if type(t) == "table" and type(t.id) == "string" and t.id:find("^after%.") and not cleared then
            P.AddTrial(t.id, t.area, t.label)
        end
    end
    local early = earlyLog
    earlyLog = {}
    for i = 1, #early do saved.log[#saved.log + 1] = early[i] end
    Log("loaded: probe " .. saved.probe .. ", game " .. saved.game)
    if cleared then Log("results from probe " .. cleared .. " cleared") end
    return saved
end

---------------------------------------------------------------------------
-- The situation
---------------------------------------------------------------------------

-- The six addon restrictions, in the order of the key's "rest=" letters.
local RESTRICTIONS = {
    { field = "combat",    enum = "Combat",        letter = "c" },
    { field = "encounter", enum = "Encounter",     letter = "e" },
    { field = "challenge", enum = "ChallengeMode", letter = "h" },
    { field = "pvp",       enum = "PvPMatch",      letter = "p" },
    { field = "map",       enum = "Map",           letter = "m" },
    { field = "chat",      enum = "Chat",          letter = "t" },
}

local function GamepadOn()
    local fn = P.Find("C_InputInterfaceStyle.GetCurrentStyle")
    local gamepad = P.Find("Enum.InputDeviceInterfaceType.Gamepad")
    if type(fn) ~= "function" or gamepad == nil then return false end
    local ok, style = pcall(fn)
    if not ok or IsSecret(style) then return false end
    return style == gamepad
end

local function Lockdown()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    if not ok or IsSecret(locked) then return false end
    return locked and true or false
end

local function RestrictionOn(enumName)
    local fn = P.Find("C_RestrictedActions.IsAddOnRestrictionActive")
    local kind = P.Find("Enum.AddOnRestrictionType." .. enumName)
    if type(fn) ~= "function" or kind == nil then return false end
    local ok, active = pcall(fn, kind)
    if not ok or IsSecret(active) then return false end
    return active and true or false
end

local WHERE = { none = "world", party = "party", raid = "raid", pvp = "pvp", arena = "arena", scenario = "scenario" }

local function Where()
    if type(IsInInstance) ~= "function" then return "world" end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or IsSecret(inside) or IsSecret(kind) then return "unknown" end
    if not inside then return "world" end
    if type(kind) ~= "string" or kind == "" then return "unknown" end
    return WHERE[kind] or (kind:gsub("[^%w]", "_"))
end

-- The situation right now: its key and the facts stored with it.
-- trigger: "auto" | "press" | "clean".
function P.Situation(trigger)
    local facts = {
        gamepad = GamepadOn(), lockdown = Lockdown(), restrictions = {},
        where = Where(), trigger = trigger,
    }
    local letters = {}
    for i, r in ipairs(RESTRICTIONS) do
        local on = RestrictionOn(r.enum)
        facts.restrictions[r.field] = on
        letters[i] = on and r.letter or "-"
    end
    local key = "gp=" .. (facts.gamepad and "on" or "off")
        .. " fight=" .. (facts.lockdown and "yes" or "no")
        .. " rest=" .. tconcat(letters)
        .. " where=" .. facts.where
        .. " trig=" .. trigger
    return key, facts
end

-- Makes sure the saved table knows this situation. Returns its entry.
function P.EnsureSituation(key, facts)
    local s = db.situations[key]
    if type(s) ~= "table" then
        s = facts
        s.first = Stamp("%Y-%m-%d %H:%M:%S")
        s.passes = 0
        db.situations[key] = s
    end
    if type(s.passes) ~= "number" then s.passes = 0 end
    return s
end

function P.SituationCount()
    local n = 0
    if db then for _ in pairs(db.situations) do n = n + 1 end end
    return n
end

-- The name of the window that has the controller's focus, or nil.
function P.FocusName()
    local manager = P.Find("GamepadMode.FrameControlsManager")
    if type(manager) ~= "table" or type(manager.GetActiveFrame) ~= "function" then return nil end
    local ok, frame = pcall(manager.GetActiveFrame, manager)
    if not ok or IsSecret(frame) or type(frame) ~= "table" then return nil end
    if type(frame.GetName) ~= "function" then return "(unnamed)" end
    local ok2, name = pcall(frame.GetName, frame)
    name = ok2 and P.Str(name)
    if name and name ~= "" then return name:sub(1, 80) end
    return "(unnamed)"
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local QUIET = { allowed = true, readable = true }   -- results that need no detail entry

-- Adds an entry to the saved trial list unless its id is already there.
-- Used for the "afterwards" entries, which are only known once seen.
function P.AddTrial(id, area, label)
    for _, t in ipairs(db.trials) do
        if t.id == id then return end
    end
    db.trials[#db.trials + 1] = { id = id, area = area, label = label, kind = "action" }
end

-- Two different answers for one cell are both kept: "allowed / blocked".
local function Merge(old, new)
    if type(old) ~= "string" or old == "" then return new end
    for part in (old .. " / "):gmatch("(.-) / ") do
        if part == new then return old end
    end
    return old .. " / " .. new
end

P.Merge = Merge

-- Called after every result is stored (the panel redraws itself).
P.OnRecord = nil

-- Stores one result. info (all optional): func, message, stack, inPress,
-- replace (for "info" and "guided" trials: the cell keeps only the newest
-- answer, since a count or a setting read twice is not two answers).
-- Returns the detail entry when one was made.
function P.Record(trialId, key, result, info)
    info = info or {}
    if info.message then info.message = P.Plain(info.message, MESSAGE_MAX) end
    local cell = db.results[trialId]
    if type(cell) ~= "table" then
        cell = {}
        db.results[trialId] = cell
    end
    cell[key] = info.replace and result or Merge(cell[key], result)
    -- The newest answer of each trial, whatever the situation: what the panel shows.
    db.last[trialId] = {
        result = result, func = info.func, message = info.message, stack = info.stack,
        situation = key, at = Stamp("%H:%M:%S"),
    }
    if P.OnRecord then pcall(P.OnRecord, trialId) end
    Log(trialId .. ": " .. result
        .. (info.inPress == true and " (straight from the press)" or "")
        .. (info.func and (" [" .. info.func .. "]") or "")
        .. (info.message and (" - " .. info.message) or ""))
    if QUIET[result] and not info.keep then return end
    local details = db.details
    local entry = {
        trial = trialId, situation = key, result = result, func = info.func, message = info.message,
        stack = info.stack, focus = P.FocusName(), at = Stamp("%Y-%m-%d %H:%M:%S"), inPress = info.inPress,
    }
    details[#details + 1] = entry
    while #details > DETAILS_MAX do tremove(details, 1) end
    return entry
end

---------------------------------------------------------------------------
-- The call stack as text: at most 14 lines, our own trial line among them
---------------------------------------------------------------------------

local STACK_LINES = 14

function P.RawStack()
    if type(debugstack) ~= "function" then return "" end
    local ok, text = pcall(debugstack, 3, 40, 0)
    if not ok or type(text) ~= "string" then
        ok, text = pcall(debugstack)
    end
    if not ok or type(text) ~= "string" or IsSecret(text) then return "" end
    return text
end

function P.TrimStack(text)
    if type(text) ~= "string" or text == "" then return nil end
    local lines, ours = {}, nil
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("Interface[/\\]AddOns[/\\]", ""):sub(1, 160)
        -- The first lines are our own listening code (Run.lua): left out.
        if #lines == 0 and (line:find("Run.lua", 1, true) or line:find("^%[C%]: %?")) then line = "" end
        if line ~= "" then
            if #lines < STACK_LINES then
                lines[#lines + 1] = line
                if line:find("Trials.lua", 1, true) then ours = true end
            elseif not ours and line:find(P.name, 1, true) and line:find("Trials.lua", 1, true) then
                lines[STACK_LINES] = line
                ours = true
            end
        end
    end
    if #lines == 0 then return nil end
    return tconcat(lines, "\n")
end

---------------------------------------------------------------------------
-- Classes of several values read together (value trials)
---------------------------------------------------------------------------

-- local c = P.Classes(); c:add("x", value) ...; c:result() -> class, message
local ClassesMeta = {}
ClassesMeta.__index = ClassesMeta

function ClassesMeta:add(name, value)
    local class = P.Class(value)
    self.n = self.n + 1
    self.names[self.n], self.classes[self.n] = name, class
    return class
end

-- Our own text about a value (a number we read, built into words): kept
-- with the result. Never pass text that came from the game.
function ClassesMeta:note(text)
    self.notes[#self.notes + 1] = text
end

function ClassesMeta:result()
    local secret, readable = false, false
    local parts = {}
    for i = 1, self.n do
        local class = self.classes[i]
        if class == "secret" then secret = true elseif class == "readable" then readable = true end
        parts[i] = self.names[i] .. "=" .. class
    end
    local result = secret and "secret" or (readable and "readable" or "nil")
    local message = (result ~= "readable" and self.n > 0) and tconcat(parts, " ") or nil
    if #self.notes > 0 then
        message = (message and (message .. " | ") or "") .. tconcat(self.notes, "; ")
    end
    return result, message
end

function P.Classes()
    return setmetatable({ n = 0, names = {}, classes = {}, notes = {} }, ClassesMeta)
end

-- The classes of a list of values given as arguments (an event's payload),
-- named by position: "1=secret 2=secret 3=readable".
function P.ClassesOf(...)
    local c = P.Classes()
    for i = 1, select("#", ...) do c:add(tostring(i), (select(i, ...))) end
    return c:result()
end
