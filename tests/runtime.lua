local ADDON_NAME = "TamrielToolsLeadFilters"
ANTIQUITY_DIFFICULTY_TRIVIAL, ANTIQUITY_DIFFICULTY_SIMPLE = 0, 1
ANTIQUITY_DIFFICULTY_INTERMEDIATE, ANTIQUITY_DIFFICULTY_ADVANCED = 2, 3
ANTIQUITY_DIFFICULTY_MASTER, ANTIQUITY_DIFFICULTY_ULTIMATE = 4, 5
ANTIQUITY_QUALITY_WHITE, ANTIQUITY_QUALITY_GREEN, ANTIQUITY_QUALITY_BLUE = 1, 2, 3
ANTIQUITY_QUALITY_PURPLE, ANTIQUITY_QUALITY_GOLD, ANTIQUITY_QUALITY_ORANGE = 4, 5, 6
EVENT_ADD_ON_LOADED = 1
SCENE_SHOWING, SCENE_SHOWN, SCENE_HIDING, SCENE_HIDDEN = 1, 2, 3, 4
TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, TOP, BOTTOM = 1, 2, 3, 4, 5, 6
CT_CONTROL, CT_LABEL, CT_TEXTURE, CT_BUTTON, CT_BACKDROP = 1, 2, 3, 4, 5
TEXT_ALIGN_CENTER, DL_BACKGROUND, ANCHOR_CONSTRAINS_Y, MOUSE_BUTTON_INDEX_LEFT = 1, 1, 1, 1
ANCHOR_CONSTRAINS_X = 2
SI_ANTIQUITY_TYPE_FALLBACK, SI_ZONE_NAME = "Antiquity", "Zone"
SI_ANTIQUITY_SUBHEADING_IN_PROGRESS, SI_ANTIQUITY_SUBHEADING_AVAILABLE = "In Progress", "Available"
SI_ANTIQUITY_SUBHEADING_REQUIRES_LEAD, SI_ANTIQUITY_SUBHEADING_ACTIVE_LEADS = "Requires Lead", "Active Leads"
ZO_ANTIQUITY_SECTION_TYPE = { IN_PROGRESS = 1, AVAILABLE = 2, REQUIRES_LEAD = 3, ACTIVE_LEAD = 4, REQUIRES_SKILL = 5 }

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local Data = {}
Data.__index = Data
function Data:GetId() return self.id end
function Data:GetFormattedName() return self.name end
function Data:GetAntiquitySetData() return self.set end
function Data:HasReward() return self.reward ~= nil end
function Data:GetRewardId() return self.reward end
function Data:GetZoneId() return self.zone end
function Data:GetDifficulty() return self.difficulty end
function Data:GetQuality() return self.quality end
function Data:HasLead() return self.hasLead end
function Data:GetLeadTimeRemainingS() return self.remaining or 0 end
function Data:HasRecovered() return self.recovered or false end
function Data:HasDiscovered() return self.discovered ~= false end
function Data:GetNumLoreEntries() return self.loreTotal end
function Data:GetNumUnlockedLoreEntries() return self.loreUnlocked end
function Data:IsVisible() return self.visible ~= false end
ZO_Antiquity = Data
local function Antiquity(id, name, properties)
    local result = setmetatable({
        id = id, name = name, zone = 1, difficulty = 3, quality = ANTIQUITY_QUALITY_GREEN,
        hasLead = true, reward = "Treasure",
        loreTotal = 3, loreUnlocked = 0,
    }, Data)
    for key, value in pairs(properties or {}) do result[key] = value end
    return result
end

local function Setup(items, options)
    options = options or {}
    local s = {
        items = items or {}, controls = {}, events = {}, updates = {}, sceneCallbacks = {},
        nativeBuilds = 0, nativeLeadUpdates = 0, initialized = 0,
        showing = false, gamepad = false, unlocked = true, mouseX = 0,
        tilePool = {}, dataCallbacks = {}, listBuilds = 0, sectionChecks = 0, codexCreates = 0,
    }
    local Control = {}
    Control.__index = Control
    function Control:IsControlHidden()
        return self.hidden or (self.parent and self.parent:IsControlHidden()) or false
    end
    function Control:RefreshEffectiveVisibility()
        local hidden = self:IsControlHidden()
        if self.effectiveHidden ~= hidden then
            self.effectiveHidden = hidden
            local handler = self.handlers[hidden and "OnEffectivelyHidden" or "OnEffectivelyShown"]
            if handler then handler(self) end
        end
        for _, child in ipairs(self.childControls) do child:RefreshEffectiveVisibility() end
    end
    function Control:SetHidden(hidden)
        self.hidden = hidden
        self:RefreshEffectiveVisibility()
    end
    function Control:SetText(text)
        self.textWrites = (self.textWrites or 0) + 1
        self.text = text
        if self.handlers.OnTextChanged then self.handlers.OnTextChanged(self) end
    end
    function Control:GetText() return self.text or "" end
    function Control:GetName() return self.name end
    function Control:SetHandler(event, callback) self.handlers[event] = callback end
    function Control:GetLeft() return self.left or 0 end
    function Control:SetDimensions(width, height)
        self.width, self.height = width, height
        self.geometryWrites = (self.geometryWrites or 0) + 1
    end
    function Control:GetDimensions() return self.width or 0, self.height or 0 end
    function Control:SetAnchor(...)
        self.anchors[#self.anchors + 1] = { ... }
        self.geometryWrites = (self.geometryWrites or 0) + 1
    end
    function Control:ClearAnchors() self.anchors = {} end
    function Control:SetAnchorFill(control) self.anchorFill = control end
    function Control:SetTexture(file) self.texture = file end
    function Control:GetTextureFileName() return self.texture end
    function Control:SetTextureCoords(...) self.textureCoords = { ... } end
    function Control:GetTextureCoords() return unpack(self.textureCoords) end
    function Control:SetColor(...) self.color = { ... } end
    function Control:GetColor() return unpack(self.color) end
    function Control:SetAlpha(alpha) self.alpha = alpha end
    function Control:GetAlpha() return self.alpha end
    function Control:GetNamedChild(name)
        assert(self.children[name], "Unknown child: " .. name)
        return self.children[name]
    end
    function Control:LoseFocus() self.focused = false end
    for _, method in ipairs({
        "SetFont",
        "SetVerticalAlignment", "SetMouseEnabled", "SetNormalTexture", "SetPressedTexture",
        "SetMouseOverTexture", "SetCenterColor",
        "SetEdgeColor", "SetDrawLayer", "SetMaxInputChars", "SetDefaultText",
    }) do
        Control[method] = function() end
    end
    local function NewControl(name, parent)
        local control = setmetatable({
            handlers = {}, children = {}, childControls = {}, anchors = {}, text = "",
            parent = parent, color = { 1, 1, 1, 1 }, textureCoords = { 0, 1, 0, 1 }, alpha = 1,
            name = name,
        }, Control)
        control.effectiveHidden = control:IsControlHidden()
        if parent then parent.childControls[#parent.childControls + 1] = control end
        if name then s.controls[name] = control end
        return control
    end
    local Combo = {}
    Combo.__index = Combo
    function Combo:ClearItems() self.entries = {} end
    function Combo:CreateItemEntry(label, callback) return { label = label, callback = callback } end
    function Combo:AddItem(entry) self.entries[#self.entries + 1] = entry end
    function Combo:SelectItemByIndex(index, suppress)
        assert(self.entries[index], "Invalid dropdown index")
        self.selected = index
        if not suppress then self.entries[index].callback(self, self.entries[index].label, self.entries[index]) end
    end
    function Combo:HideDropdown() self.open = false end
    function Combo:SetSortsItems() end
    function Combo:SetFont() end
    WINDOW_MANAGER = {
        CreateControl = function(_, name, parent) return NewControl(name, parent) end,
        CreateControlFromVirtual = function(_, name, parent, template)
            local control = NewControl(name, parent)
            if template == "ZO_ScrollContainer" then control.children.ScrollChild = NewControl(nil, control) end
            if template == "ZO_AntiquityLogBookProgress" then
                s.codexCreates = s.codexCreates + 1
                control.children.Progress = NewControl(nil, control)
                control.children.LogBook = NewControl(nil, control)
                control.children.LogBook:SetText("Codex")
            end
            if template == "ZO_ComboBox" then
                control.combo = setmetatable({ entries = {} }, Combo)
            end
            return control
        end,
    }
    ZO_ComboBox_ObjectFromContainer = function(control) return assert(control.combo) end
    ZO_PostHookHandler = function(control, event, hook)
        local original = control.handlers[event]
        control.handlers[event] = function(...)
            if original then original(...) end
            hook(...)
        end
    end
    SecurePostHook = function(object, method, hook)
        local original = assert(object[method], method)
        object[method] = function(...)
            local result = original(...)
            hook(...)
            return result
        end
    end
    ZO_PreHook = function(object, method, hook)
        local original = assert(object[method], method)
        object[method] = function(...)
            if hook(...) then return end
            return original(...)
        end
    end
    zo_strlower = string.lower
    zo_strformat = function(_, text) return text end
    GetString = function(id, value)
        if id == "SI_ANTIQUITYDIFFICULTY" then
            return ({ [0] = "Trivial", "Simple", "Intermediate", "Advanced", "Master", "Ultimate" })[value]
        end
        if value then return "Difficulty " .. value end
        return id
    end
    GetZoneNameById = function(zone) return ({ [1] = "Auridon", [2] = "Glenumbra" })[zone] end
    GetAntiquityQualityColor = function(quality)
        local colors = {
            [ANTIQUITY_QUALITY_WHITE] = { 1, 1, 1 },
            [ANTIQUITY_QUALITY_GREEN] = { 0.2, 0.75, 0.2 },
            [ANTIQUITY_QUALITY_BLUE] = { 0.2, 0.6, 1 },
            [ANTIQUITY_QUALITY_PURPLE] = { 0.65, 0.35, 0.9 },
            [ANTIQUITY_QUALITY_GOLD] = { 0.9, 0.75, 0.25 },
            [ANTIQUITY_QUALITY_ORANGE] = { 1, 0.45, 0.15 },
        }
        return { UnpackRGB = function() return unpack(assert(colors[quality])) end }
    end
    GetUIMousePosition = function() return s.mouseX, 0 end
    IsInGamepadPreferredMode = function() return s.gamepad end
    ZO_IsScryingUnlocked = function() return s.unlocked end
    ZO_IsAntiquityScryableSubcategory = function(category) return category.scryable end
    REWARDS_MANAGER = { GetRewardContextualTypeString = function(_, reward) return reward end }
    InformationTooltip = { GetOwner = function(self) return self.owner end }
    InitializeTooltip = function(tooltip, owner) tooltip.owner = owner end
    SetTooltipText = function(tooltip, text) tooltip.text = text end
    ClearTooltip = function(tooltip) tooltip.owner, tooltip.text = nil, nil end
    ZO_Scroll_ScrollAbsoluteInstantly = function(_, offset) s.restoredOffset = offset end
    ZO_SavedVars = {
        New = function(_, name, version, namespace, defaults)
            assert(name == ADDON_NAME .. "_SV" and version == 1 and namespace == nil)
            s.saved = Copy(defaults)
            for key, value in pairs(options.saved or {}) do s.saved[key] = Copy(value) end
            return s.saved
        end,
    }
    EVENT_MANAGER = {
        RegisterForEvent = function(_, _, event, callback) s.events[event] = callback end,
        UnregisterForEvent = function(_, _, event) s.events[event] = nil end,
        RegisterForUpdate = function(_, name, _, callback) s.updates[name] = callback end,
        UnregisterForUpdate = function(_, name) s.updates[name] = nil end,
    }
    s.sections = {
        {
            sectionType = ZO_ANTIQUITY_SECTION_TYPE.IN_PROGRESS, sectionHeading = "In Progress",
            filterFunctions = { function(data) return data.progress end }, list = {},
        },
        {
            sectionType = ZO_ANTIQUITY_SECTION_TYPE.AVAILABLE, sectionHeading = "Available",
            filterFunctions = { function(data) return data.available end }, list = {},
        },
        {
            sectionType = ZO_ANTIQUITY_SECTION_TYPE.REQUIRES_LEAD, sectionHeading = "Requires Lead",
            filterFunctions = { function(data) return data.zone == 1 and data.requiresLead and not data.hasLead end },
            list = {},
        },
        {
            sectionType = ZO_ANTIQUITY_SECTION_TYPE.ACTIVE_LEAD, sectionHeading = "Active Leads",
            filterFunctions = { function(data) return data.hasLead end }, list = {},
        },
    }
    for _, difficulty in ipairs({ 3, 4 }) do
        s.sections[#s.sections + 1] = {
            sectionType = ZO_ANTIQUITY_SECTION_TYPE.REQUIRES_SKILL,
            sectionHeading = "Requires skill " .. difficulty,
            filterFunctions = { function(data)
                return data.zone == 1 and data.requiresSkill and data.difficulty == difficulty
            end },
            list = {},
        }
    end
    ANTIQUITY_MANAGER = {
        GetOrCreateAntiquitySectionList = function()
            for _, section in ipairs(s.sections) do
                for index = #section.list, 1, -1 do section.list[index] = nil end
            end
            return s.sections
        end,
        ShouldScryableSubcategoryShowSection = function(_, category, section)
            s.sectionChecks = s.sectionChecks + 1
            return not (category.current and section.sectionType == ZO_ANTIQUITY_SECTION_TYPE.ACTIVE_LEAD)
        end,
    }
    function s:Category(scryable, current)
        return {
            scryable = scryable, current = current,
            AntiquityIterator = function(_, predicates)
                local index = 0
                return function()
                    while index < #s.items do
                        index = index + 1
                        local data = s.items[index]
                        local include = not current or data.zone == 1 or data.zone == 0
                        for _, predicate in ipairs(predicates) do include = include and predicate(data) end
                        if include then return index, data end
                    end
                end
            end,
        }
    end
    ANTIQUITY_DATA_MANAGER = {
        RegisterCallback = function(_, name, callback) s.dataCallbacks[name] = callback end,
    }
    s.category = s:Category(true, false)
    local class = {}
    function class:OnDeferredInitialize()
        s.initialized = s.initialized + 1
        self.categoryLabel = NewControl(nil, self.control)
        self.categoryLabel.left = 800
        self.contentList = NewControl(nil, self.control)
        self.contentList.scroll = { GetScrollOffsets = function() return 0, 123 end }
        self.contentEmptyLabel = NewControl()
        self.contentSearchEditBox = NewControl()
        self.contentSearchEditBox:SetText("native search")
        self.categoryTree = { GetSelectedData = function() return s.category end }
        self.antiquityTilesByAntiquityId = {}
    end
    function class:BuildCategoryAntiquityTiles() s.nativeBuilds = s.nativeBuilds + 1 end
    function class:OnCategorySelected(category)
        if s.unlocked then self:BuildCategoryAntiquityTiles(category) end
    end
    function class:OnSingleAntiquityLeadUpdated() s.nativeLeadUpdates = s.nativeLeadUpdates + 1 end
    function class:OnShowing() s.nativeRefreshPending = true end
    function class:OnAntiquitiesUpdated()
        self.isRefreshingAll = true
        self:OnCategorySelected(s.category)
        self.isRefreshingAll = false
    end
    function class:SetMouseOverTile(tile)
        self.mouseOverTile = tile
        s.hoverRestores = (s.hoverRestores or 0) + 1
    end
    local tileClass = {}
    function tileClass:IsControlHidden() return self.control:IsControlHidden() end
    function tileClass:Refresh()
        self.nativeRefreshes = (self.nativeRefreshes or 0) + 1
    end
    function tileClass:Reset() self.tileData = nil end
    ZO_ScryableAntiquityTile_Keyboard = tileClass
    function class:ResetCategoryTiles(hideProgress)
        assert(hideProgress)
        s.listBuilds = s.listBuilds + 1
        for _, tile in ipairs(s.tilePool) do
            tile:Reset()
            tile.control:SetHidden(true)
        end
        s.rendered = {}
        s.groups, s.lastTile = {}, nil
        self.mouseOverTile = nil
        self.antiquityTilesByAntiquityId = {}
    end
    function class:AddScryableAntiquityTiles(previous, heading, data, compare)
        assert(previous == s.lastTile, "Each group must be anchored after the preceding group's last tile")
        assert(#data > 0, "Empty headings must not be rendered")
        local group = { heading = heading, ids = {} }
        s.groups[#s.groups + 1] = group
        table.sort(data, compare)
        for _, entry in ipairs(data) do
            local index = #s.rendered + 1
            local tile = s.tilePool[index]
            if not tile then
                local control = NewControl("MockScryableTile" .. index, self.contentList)
                tile = setmetatable({ control = control, header = NewControl(nil, control) }, { __index = tileClass })
                s.tilePool[index] = tile
            end
            tile.tileData = entry
            tile.control:SetHidden(false)
            tile:Refresh()
            s.rendered[#s.rendered + 1] = entry:GetId()
            group.ids[#group.ids + 1] = entry:GetId()
            self.antiquityTilesByAntiquityId[entry:GetId()] = tile
        end
        s.lastTile = { control = {} }
        return s.lastTile
    end
    ZO_AntiquityJournal_Keyboard = class
    RIGHT_BG_FRAGMENT = {}
    ZO_SharedTitle = NewControl()
    ZO_SharedTitle.children.Label = NewControl(nil, ZO_SharedTitle)
    ZO_SharedTitle.children.Label.left = 600
    ZO_SharedRightBackground = NewControl()
    ZO_SharedRightBackground.left = 450
    for _, name in ipairs({ "Left", "Right" }) do
        local texture = NewControl(nil, ZO_SharedRightBackground)
        texture.width, texture.height = name == "Left" and 1024 or 64, 1024
        texture.texture = "EsoUI/Art/Miscellaneous/centerscreen_" .. string.lower(name) .. ".dds"
        ZO_SharedRightBackground.children[name] = texture
    end
    s.fragments = { [RIGHT_BG_FRAGMENT] = options.backgroundFragment ~= false }
    s.otherSceneFragments = { [RIGHT_BG_FRAGMENT] = true }
    s.fragmentAdds, s.fragmentRemoves = 0, 0
    local function RefreshNativeBackground()
        ZO_SharedRightBackground:SetHidden(not (s.fragments[RIGHT_BG_FRAGMENT] and s.showing))
    end
    RefreshNativeBackground()
    s.owner = setmetatable({
        control = NewControl(),
        scene = {
            IsShowing = function() return s.showing end,
            RegisterCallback = function(_, name, callback)
                assert(name == "StateChange")
                s.sceneCallbacks[#s.sceneCallbacks + 1] = callback
            end,
            HasFragment = function(_, fragment) return s.fragments[fragment] == true end,
            AddFragment = function(_, fragment)
                assert(fragment == RIGHT_BG_FRAGMENT)
                s.fragments[fragment] = true
                s.fragmentAdds = s.fragmentAdds + 1
                RefreshNativeBackground()
            end,
            RemoveFragment = function(_, fragment)
                assert(fragment == RIGHT_BG_FRAGMENT)
                s.fragments[fragment] = nil
                s.fragmentRemoves = s.fragmentRemoves + 1
                RefreshNativeBackground()
            end,
        },
    }, { __index = class })
    s.owner.control:SetHidden(true)
    ANTIQUITY_JOURNAL_KEYBOARD = s.owner
    if options.initialized then s.owner:OnDeferredInitialize() end
    assert(loadfile("TamrielToolsLeadFilters.lua"))()
    s.events[EVENT_ADD_ON_LOADED](EVENT_ADD_ON_LOADED, "OtherAddon")
    assert(not TamrielToolsLeadFilters.saved)
    s.events[EVENT_ADD_ON_LOADED](EVENT_ADD_ON_LOADED, ADDON_NAME)
    s.filters = TamrielToolsLeadFilters
    function s:Show()
        if self.initialized == 0 then self.owner:OnDeferredInitialize() end
        self.showing = true
        RefreshNativeBackground()
        self.owner.control:SetHidden(false)
        self.owner:OnShowing()
        for _, callback in ipairs(self.sceneCallbacks) do callback(SCENE_HIDDEN, SCENE_SHOWING) end
        if self.nativeRefreshPending then
            self.nativeRefreshPending = false
            self.owner:OnAntiquitiesUpdated()
        end
    end
    function s:Hide()
        self.showing = false
        for _, callback in ipairs(self.sceneCallbacks) do callback(SCENE_SHOWN, SCENE_HIDING) end
        self.owner.control:SetHidden(true)
        RefreshNativeBackground()
    end
    function s:Select(category)
        self.category = category
        self.owner:OnCategorySelected(category)
    end
    function s:Flush()
        local callback = assert(self.updates[ADDON_NAME .. "Refresh"], "No scheduled refresh")
        callback()
    end
    function s:AcquireLead(data)
        self.owner:OnSingleAntiquityLeadUpdated(data)
        self.dataCallbacks.SingleAntiquityLeadAcquired(data)
    end
    function s:ExpectRows(expected)
        assert(table.concat(self.rendered, ",") == expected, table.concat(self.rendered, ",") .. " ~= " .. expected)
    end
    return s
end

local tests = {}

function tests.large_list_opening_builds_once_and_reuses_codex_controls()
    local items = {}
    for index = 1, 600 do
        items[index] = Antiquity(index, string.format("Needle %04d", index))
    end
    local s = Setup(items, { saved = { search = "needle" } })
    local normalize = s.filters.NormalizeText
    local searchNormalizations = 0
    s.filters.NormalizeText = function(text)
        if text == "needle" then searchNormalizations = searchNormalizations + 1 end
        return normalize(text)
    end
    s:Show()
    assert(s.listBuilds == 1 and #s.rendered == 600, "Scene opening must not build the list twice")
    assert(s.codexCreates == 600 and searchNormalizations == 1)
    assert(s.sectionChecks == #s.sections, "Section visibility must be checked once per section, not per lead")
    for _, tile in ipairs(s.tilePool) do
        assert(tile.tamrielToolsCodexProgress:GetNamedChild("Progress").textWrites == 1)
    end
    s:Hide()
    s.items[1].loreUnlocked = 2
    s.items[2].remaining = 30
    s:Show()
    assert(s.listBuilds == 2 and searchNormalizations == 2)
    assert(s.codexCreates == 600, "Reopening must reuse the existing Codex controls")
    for _, tile in ipairs(s.tilePool) do
        assert(tile.tamrielToolsCodexProgress:GetNamedChild("Progress").textWrites == 2,
            "Reused rows must update Codex exactly once per layout")
    end
    assert(s.owner.antiquityTilesByAntiquityId[1].tamrielToolsCodexProgress:GetNamedChild("Progress"):GetText() == "2 / 3")
    assert(s.restoredOffset == 123)
end

function tests.clearing_new_markers_does_not_queue_list_rebuilds_but_acquiring_leads_does()
    local s = Setup({
        Antiquity(1, "Existing"),
        Antiquity(2, "New", { hasLead = false }),
    })
    s:Show()
    s:ExpectRows("1")
    for _ = 1, 10 do s.owner:OnSingleAntiquityLeadUpdated(s.items[1]) end
    assert(s.nativeLeadUpdates == 10 and next(s.updates) == nil and s.listBuilds == 1)
    s.items[2].hasLead = true
    s:AcquireLead(s.items[2])
    assert(s.updates[ADDON_NAME .. "Refresh"])
    s:Flush()
    s:ExpectRows("1,2")
    assert(s.listBuilds == 2)
    s:Hide()
    s.items[3] = Antiquity(3, "While hidden")
    s:AcquireLead(s.items[3])
    assert(next(s.updates) == nil)
    s:Show()
    s:ExpectRows("1,2,3")
    assert(s.listBuilds == 3)
end

function tests.native_data_refresh_consumes_pending_addon_rebuild_and_rechecks_live_data()
    local s = Setup({ Antiquity(1, "Lead"), Antiquity(2, "No lead", { hasLead = false }) })
    s:Show()
    s.items[2].hasLead = true
    s:AcquireLead(s.items[2])
    assert(next(s.updates))
    s.items[1].hasLead = false
    s.owner:OnAntiquitiesUpdated()
    s:ExpectRows("2")
    assert(s.listBuilds == 2 and next(s.updates) == nil,
        "A native rebuild already handles pending lead changes; don't repeat it on the next timer tick")
end

function tests.filters_intersect_and_match_set_reward_and_zone_search()
    local set = Antiquity(100, "Ancient Seat", { reward = "Furnishing" })
    local s = Setup({
        Antiquity(1, "Left Leg", { set = set, difficulty = 4 }),
        Antiquity(2, "Right Leg", { set = set, difficulty = 4, recovered = true }),
        Antiquity(3, "Left Leg", { difficulty = 4 }),
        Antiquity(4, "Left Leg", { set = set, difficulty = 5 }),
    })
    s.saved.rewardType = "Furnishing"
    s.saved.search = "aurIDon ANCIENT left"
    s.saved.difficulties[5] = false
    s:Show()
    s:ExpectRows("1")
    assert(s.filters.countLabel:GetText() == "1 / 4 leads")
end

function tests.zone_and_name_sorts_are_deterministic_within_native_groups()
    local s = Setup({
        Antiquity(7, "Zebra", { zone = 2, progress = true }),
        Antiquity(5, "beta", { zone = 1 }),
        Antiquity(3, "Alpha", { zone = 2 }),
        Antiquity(2, "Alpha", { zone = 1 }),
        Antiquity(1, "Alpha", { zone = 1 }),
        Antiquity(8, "Anywhere", { zone = 0 }),
    })
    s:Show()
    s:ExpectRows("7,1,2,5,3,8")
    s.saved.sortBy = "name"
    s.filters:Refresh()
    s:ExpectRows("7,1,2,3,8,5")
    assert(s.items[1].id == 7, "Shared candidate order must not be changed")
end

function tests.expiry_sort_preserves_groups_and_puts_untimed_last_within_each_group()
    local s = Setup({
        Antiquity(1, "In progress", { progress = true, remaining = 500 }),
        Antiquity(2, "Urgent", { zone = 2, remaining = 10 }),
        Antiquity(3, "Repeatable", { hasLead = false, available = true, remaining = 1 }),
        Antiquity(4, "Untimed", { remaining = 0 }),
        Antiquity(5, "Later progress", { progress = true, remaining = 1000 }),
        Antiquity(6, "Later active", { remaining = 20 }),
    })
    s.saved.sortBy = "expiry"
    s:Show()
    s:ExpectRows("1,5,3,2,6,4")
    s.items[1].remaining = 2000
    s.filters:Refresh()
    s:ExpectRows("5,1,3,2,6,4")
end

function tests.native_visibility_and_current_zone_section_rules_are_preserved()
    local s = Setup({
        Antiquity(1, "Hidden", { visible = false, available = true }),
        Antiquity(2, "Other zone", { zone = 2, available = true }),
        Antiquity(3, "Here", { available = true }),
        Antiquity(4, "Native section excluded"),
        Antiquity(5, "No native section", { hasLead = false }),
    })
    s:Show()
    s:ExpectRows("3,2,4")
    s:Select(s:Category(true, true))
    s:ExpectRows("3")
end

function tests.native_headings_priority_and_skill_subgroups_are_preserved()
    local s = Setup({
        Antiquity(1, "Progress", { progress = true, available = true }),
        Antiquity(2, "Permanent", { available = true, hasLead = false }),
        Antiquity(3, "Missing", { requiresLead = true, hasLead = false }),
        Antiquity(4, "Active"),
        Antiquity(5, "Z skill", { requiresSkill = true, hasLead = false, difficulty = 3 }),
        Antiquity(6, "A skill", { requiresSkill = true, hasLead = false, difficulty = 4 }),
    })
    s:Show()
    s:ExpectRows("1,2,3,4,5,6")
    assert(#s.groups == 6 and s.filters.countLabel:GetText() == "6 / 6 leads")
    for index, section in ipairs(s.sections) do
        assert(s.groups[index].heading == section.sectionHeading)
        assert(next(section.list) == nil, "The addon must not populate or sort shared section lists")
    end
    s:Select(s:Category(true, true))
    s:ExpectRows("1,2,3,5,6")
    s.filters.statusCombo:SelectItemByIndex(3)
    s:ExpectRows("2")
    assert(#s.groups == 1 and s.groups[1].heading == "Available")
    s.filters.statusCombo:SelectItemByIndex(4)
    s:ExpectRows("3")
    assert(#s.groups == 1 and s.groups[1].heading == "Requires Lead")
    s.filters.statusCombo:SelectItemByIndex(6)
    s:ExpectRows("5,6")
    assert(#s.groups == 2 and s.groups[1].heading ~= s.groups[2].heading)
    s.filters.statusCombo:SelectItemByIndex(5)
    s:ExpectRows("")
    assert(#s.groups == 0, "A status filter must not bypass Current Zone section eligibility")
end

function tests.status_intersects_with_quality_and_search_and_reset_restores_all_groups()
    local s = Setup({
        Antiquity(1, "Missing Green", { requiresLead = true, hasLead = false, recovered = true }),
        Antiquity(2, "Missing Blue", { requiresLead = true, hasLead = false, quality = ANTIQUITY_QUALITY_BLUE }),
        Antiquity(3, "Available Green", { available = true, hasLead = false }),
        Antiquity(4, "Missing New Green", { requiresLead = true, hasLead = false }),
    })
    s:Show()
    s:ExpectRows("3,2,1,4")
    s.filters.statusCombo:SelectItemByIndex(4)
    s:ExpectRows("2,1,4")
    local blue = s.filters.qualityButtons[2]
    blue.handlers.OnClicked(blue)
    s:ExpectRows("1,4")
    s.filters.searchEdit:SetText("new")
    s:Flush()
    s:ExpectRows("4")
    assert(#s.groups == 1 and s.filters.countLabel:GetText() == "1 / 4 leads")
    s.filters:Reset()
    s:ExpectRows("3,2,1,4")
    assert(#s.groups == 2 and s.saved.status == "all" and s.filters.statusCombo.selected == 1)
end

function tests.saved_status_is_restored_and_lead_updates_reclassify_entries()
    local s = Setup({
        Antiquity(1, "Missing", { requiresLead = true, hasLead = false }),
        Antiquity(2, "Permanent", { available = true, hasLead = false }),
    }, { saved = { status = ZO_ANTIQUITY_SECTION_TYPE.REQUIRES_LEAD } })
    s:Show()
    s:ExpectRows("1")
    assert(s.filters.statusCombo.selected == 4)
    s.items[1].hasLead = true
    s:AcquireLead(s.items[1])
    s:Flush()
    s:ExpectRows("")
    assert(#s.groups == 0 and s.filters.countLabel:GetText() == "0 / 2 leads")
    s.filters:Reset()
    s:ExpectRows("2,1")
    assert(s.groups[1].heading == "Available" and s.groups[2].heading == "Active Leads")
    s.filters.statusCombo:SelectItemByIndex(3)
    s:Hide()
    s:Show()
    s:ExpectRows("2")
    assert(s.saved.status == ZO_ANTIQUITY_SECTION_TYPE.AVAILABLE)
end

function tests.scryable_rows_show_actual_codex_progress_in_every_status_group()
    local set = Antiquity(100, "Completed Set", { loreUnlocked = 3 })
    local s = Setup({
        Antiquity(1, "Pipe", { available = true, recovered = true, loreUnlocked = 3 }),
        Antiquity(2, "Scrollcase", { requiresLead = true, hasLead = false, recovered = true, loreUnlocked = 1 }),
        Antiquity(3, "Fragment", { set = set, loreTotal = 1, loreUnlocked = 1 }),
        Antiquity(4, "Undiscovered", { discovered = false }),
    })
    s:Show()
    local lookup = s.owner.antiquityTilesByAntiquityId
    local function ExpectProgress(id, text)
        local progress = lookup[id].tamrielToolsCodexProgress
        assert(progress and not progress:IsControlHidden())
        assert(progress:GetNamedChild("Progress"):GetText() == text)
        assert(progress:GetNamedChild("LogBook"):GetText() == "Codex")
    end
    ExpectProgress(1, "3 / 3")
    ExpectProgress(2, "1 / 3")
    ExpectProgress(3, "1 / 1")
    assert(not lookup[4].tamrielToolsCodexProgress)
end

function tests.codex_progress_refreshes_and_pooled_tiles_do_not_keep_old_counts()
    local s = Setup({
        Antiquity(1, "Alpha", { loreUnlocked = 1 }),
        Antiquity(2, "Beta", { loreTotal = 1, loreUnlocked = 1 }),
        Antiquity(3, "Gamma", { loreTotal = 0 }),
    })
    s:Show()
    local tile = s.owner.antiquityTilesByAntiquityId[1]
    local progress = tile.tamrielToolsCodexProgress
    local nativeRefreshes = tile.nativeRefreshes
    s.items[1].loreUnlocked = 2
    tile:Refresh()
    assert(tile.nativeRefreshes == nativeRefreshes + 1)
    assert(progress:GetNamedChild("Progress"):GetText() == "2 / 3")
    s.filters.searchEdit:SetText("beta")
    s:Flush()
    assert(s.owner.antiquityTilesByAntiquityId[2] == tile)
    assert(tile.tamrielToolsCodexProgress == progress)
    assert(progress:GetNamedChild("Progress"):GetText() == "1 / 1")
    assert(s.tilePool[2].tamrielToolsCodexProgress.hidden, "Released tiles must hide their old Codex counters")
    s.filters.searchEdit:SetText("gamma")
    s:Flush()
    assert(progress.hidden, "A lead without lore entries must not inherit another lead's count")
    s.filters.searchEdit:SetText("alpha")
    s:Flush()
    assert(not progress.hidden and progress:GetNamedChild("Progress"):GetText() == "2 / 3")
    tile:Reset()
    tile:Refresh()
    assert(progress.hidden and tile.tileData == nil)
end

function tests.codex_counters_are_scoped_to_our_keyboard_scryable_tiles()
    local s = Setup({ Antiquity(1, "Pipe", { loreUnlocked = 1 }) })
    s:Show()
    local tile = s.owner.antiquityTilesByAntiquityId[1]
    local otherTile = setmetatable({ tileData = s.items[1] }, { __index = ZO_ScryableAntiquityTile_Keyboard })
    otherTile:Refresh()
    assert(otherTile.nativeRefreshes == 1 and not otherTile.tamrielToolsCodexProgress)
    s:Select(s:Category(false))
    tile:Refresh()
    assert(tile.tamrielToolsCodexProgress.hidden)
    s:Select(s:Category(true))
    tile = s.owner.antiquityTilesByAntiquityId[1]
    assert(not tile.tamrielToolsCodexProgress.hidden)
    s.gamepad = true
    tile:Refresh()
    assert(tile.tamrielToolsCodexProgress.hidden)
    s:Hide()
    assert(tile.tamrielToolsCodexProgress:IsControlHidden())
end

function tests.no_matches_clear_tiles_and_have_an_explicit_count()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    s.owner.mouseOverTile = s.owner.antiquityTilesByAntiquityId[1]
    s.saved.search = "nothing"
    s.filters:Refresh()
    s:ExpectRows("")
    assert(next(s.owner.antiquityTilesByAntiquityId) == nil)
    assert(s.owner.mouseOverTile == nil)
    assert(s.owner.contentEmptyLabel.hidden == false)
    assert(s.filters.countLabel:GetText() == "0 / 1 leads")
end

function tests.sidebar_search_is_literal_debounced_and_does_not_change_native_search()
    local s = Setup({ Antiquity(1, "|cFF0000Ore [Fine]|r"), Antiquity(2, "Ore raw") })
    s:Show()
    local search = s.controls[ADDON_NAME .. "Search"]
    local searchBottom = search.anchors[1][5] + search.height
    for _, name in ipairs({ "SortLabel", "TypeLabel", "StatusLabel", "DifficultyLabel", "QualityLabel" }) do
        assert(searchBottom < s.controls[ADDON_NAME .. name].anchors[1][5], "Text Search must precede all other filters")
    end
    assert(not s.controls[ADDON_NAME .. "DifficultyHint"] and not s.controls[ADDON_NAME .. "QualityHint"])
    s.filters.searchEdit:SetText("[fine] AURIDON")
    s:ExpectRows("1,2")
    s:Flush()
    s:ExpectRows("1")
    assert(s.owner.contentSearchEditBox:GetText() == "native search")
end

function tests.obsolete_recovery_is_ignored_and_reset_preserves_native_category_and_search()
    local s = Setup({ Antiquity(1, "New"), Antiquity(2, "Recovered", { recovered = true }) },
        { saved = { recovery = "new" } })
    s:Show()
    s:ExpectRows("1,2")
    assert(s.saved.recovery == nil and s.filters.recoveryCombo == nil)
    assert(s.controls[ADDON_NAME .. "Recovery"] == nil and s.controls[ADDON_NAME .. "RecoveryLabel"] == nil)
    s.saved.search, s.saved.rewardType, s.saved.sortBy = "other", "Furnishing", "expiry"
    s.saved.difficulties[3] = false
    local category = s.category
    s.filters:Reset()
    s:ExpectRows("1,2")
    assert(s.saved.search == "" and s.saved.rewardType == "" and s.saved.sortBy == "zone")
    assert(s.saved.recovery == nil and s.saved.difficulties[3])
    assert(s.category == category and s.owner.contentSearchEditBox:GetText() == "native search")
end

function tests.deferred_initialization_is_not_forced_and_existing_initialization_is_supported()
    local s = Setup()
    assert(s.initialized == 0 and not s.filters.panel)
    s:Show()
    assert(s.initialized == 1 and s.filters.panel)
    local initialized = Setup(nil, { initialized = true })
    assert(initialized.initialized == 1 and initialized.filters.panel)
end

function tests.codex_gamepad_other_instances_and_locked_content_use_native_builds()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    assert(not s.filters.panel.hidden)
    s:Select(s:Category(false))
    assert(s.nativeBuilds == 1 and s.filters.panel.hidden)
    s.gamepad = true
    s:Select(s:Category(true))
    assert(s.nativeBuilds == 2 and s.filters.panel.hidden)
    local otherOwner = setmetatable({}, { __index = ZO_AntiquityJournal_Keyboard })
    otherOwner:BuildCategoryAntiquityTiles(s.category)
    assert(s.nativeBuilds == 3)
    s.gamepad, s.unlocked = false, false
    s:Select(s:Category(true))
    assert(s.nativeBuilds == 3 and s.filters.panel.hidden)
end

function tests.closing_hides_dropdowns_releases_focus_and_cancels_pending_refresh()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    s.filters.sortCombo.open, s.filters.typeCombo.open = true, true
    s.filters.statusCombo.open = true
    s.filters.searchEdit.focused = true
    s.filters.range.dragging = "minimum"
    s.filters.qualityRange.dragging = "maximum"
    s.filters.searchEdit:SetText("ore")
    s:Hide()
    assert(s.filters.panel.hidden and next(s.updates) == nil)
    assert(not s.filters.sortCombo.open and not s.filters.typeCombo.open)
    assert(not s.filters.statusCombo.open)
    assert(not s.filters.searchEdit.focused and not s.filters.range.dragging)
    assert(not s.filters.qualityRange.dragging)
end

function tests.lead_events_refresh_membership_and_preserve_full_refresh_scroll()
    local s = Setup({ Antiquity(1, "Ore"), Antiquity(2, "Vase") })
    s:Show()
    s.items[1].hasLead = false
    s:AcquireLead(s.items[1])
    assert(s.nativeLeadUpdates == 1)
    s:Flush()
    s:ExpectRows("2")
    s.owner.isRefreshingAll = true
    s.filters:Refresh()
    assert(s.restoredOffset == 123)
end

function tests.saved_filters_are_restored_and_missing_type_stays_visible()
    local s = Setup({ Antiquity(1, "Ore") }, {
        saved = { rewardType = "Furnishing", sortBy = "expiry", search = "auridon" },
    })
    s:Show()
    s:ExpectRows("")
    assert(s.filters.searchEdit:GetText() == "auridon")
    local combo = s.filters.typeCombo
    assert(combo.entries[combo.selected].label == "Furnishing")
    combo:SelectItemByIndex(1)
    s:ExpectRows("1")
end

function tests.compact_difficulties_preserve_choices_and_remove_obsolete_tiers()
    local s = Setup({
        Antiquity(1, "Master", { difficulty = 4 }),
        Antiquity(2, "Advanced", { difficulty = 3 }),
        Antiquity(3, "Trivial", { difficulty = 0 }),
        Antiquity(4, "Simple", { difficulty = 1 }),
        Antiquity(5, "Intermediate", { difficulty = 2 }),
    }, { saved = { difficulties = { [0] = true, true, true, false, true, false } } })
    s:Show()
    s:ExpectRows("1")
    local buttons = s.filters.difficultyButtons
    assert(#buttons == 3)
    assert(s.saved.difficulties[0] == nil and s.saved.difficulties[1] == nil and s.saved.difficulties[2] == nil)
    local previousRight = 0
    for index, name in ipairs({ "Advanced", "Master", "Ultimate" }) do
        local button = buttons[index]
        local x, y = button.anchors[1][4], button.anchors[1][5]
        assert(button:GetText() == name and not button.swatch)
        assert(y == buttons[1].anchors[1][5] and button.height <= 28, "Difficulty must fit in one compact row")
        assert(x >= previousRight and x + button.width <= 228, "Buttons must fit without overlapping")
        previousRight = x + button.width
    end
    assert(buttons[2].alpha == 1 and buttons[1].alpha < 1)
    buttons[1].handlers.OnMouseEnter(buttons[1])
    assert(InformationTooltip.text == "Advanced (hidden)" and InformationTooltip.owner == buttons[1])
    buttons[1].handlers.OnClicked(buttons[1])
    s:ExpectRows("2,1")
    assert(buttons[1].alpha == 1)
    buttons[1].handlers.OnMouseEnter(buttons[1])
    assert(InformationTooltip.text == "Advanced (shown)")
    buttons[1].handlers.OnMouseExit(buttons[1])
    assert(InformationTooltip.owner == nil and InformationTooltip.text == nil)
    s.filters:Reset()
    for _, button in ipairs(buttons) do assert(button.alpha == 1) end
    s:ExpectRows("2,1")
    assert(s.saved.difficulties[0] == nil and s.saved.difficulties[1] == nil and s.saved.difficulties[2] == nil)
end

function tests.difficulty_toggles_and_range_cover_advanced_through_ultimate()
    local s = Setup({
        Antiquity(1, "A Advanced", { difficulty = 3 }),
        Antiquity(2, "B Master", { difficulty = 4 }),
        Antiquity(3, "C Ultimate", { difficulty = 5 }),
    })
    s:Show()
    s:ExpectRows("1,2,3")
    local advanced = s.filters.difficultyButtons[1]
    advanced.handlers.OnClicked(advanced)
    s:ExpectRows("2,3")
    s.filters:Reset()
    local rangeControl = s.controls[ADDON_NAME .. "Range"]
    s.mouseX = 4 + 220 / 2
    rangeControl.handlers.OnMouseDown(rangeControl, MOUSE_BUTTON_INDEX_LEFT)
    assert(s.saved.difficulties[3] == false and s.saved.difficulties[4] == true)
    s:ExpectRows("2,3")
    s.mouseX = -100
    rangeControl.handlers.OnUpdate(rangeControl)
    assert(s.saved.difficulties[3] == true)
    s:ExpectRows("1,2,3")
    rangeControl.handlers.OnMouseUp(rangeControl)
    assert(not s.filters.range.dragging)
    for _, button in ipairs(s.filters.difficultyButtons) do button.handlers.OnClicked(button) end
    s:ExpectRows("")
end

function tests.quality_filters_name_colour_independently_of_reported_difficulty()
    local s = Setup({
        Antiquity(1, "Green Pipe", { difficulty = 3, quality = ANTIQUITY_QUALITY_GREEN }),
        Antiquity(2, "Blue Fossil", { difficulty = 3, quality = ANTIQUITY_QUALITY_BLUE }),
        Antiquity(3, "Purple Relief", { difficulty = 3, quality = ANTIQUITY_QUALITY_PURPLE }),
        Antiquity(4, "Gold Furnishing", { difficulty = 4, quality = ANTIQUITY_QUALITY_GOLD }),
    })
    s:Show()
    s:ExpectRows("2,4,1,3")
    for index = 1, 2 do
        local button = s.filters.qualityButtons[index]
        button.handlers.OnClicked(button)
    end
    s:ExpectRows("4,3")
    local green = s.filters.qualityButtons[1]
    green.handlers.OnMouseEnter(green)
    assert(InformationTooltip.text == "Green lead quality (hidden)" and green.swatch.alpha == 0.25)
    local master = s.filters.difficultyButtons[2]
    master.handlers.OnClicked(master)
    s:ExpectRows("3")
    local advanced = s.filters.difficultyButtons[1]
    advanced.handlers.OnClicked(advanced)
    s:ExpectRows("")
    green.handlers.OnClicked(green)
    s:ExpectRows("")
    advanced.handlers.OnClicked(advanced)
    s:ExpectRows("1,3")
end

function tests.quality_range_drags_both_bounds_and_stays_independent_of_difficulty()
    local items = {}
    for index, quality in ipairs({
        ANTIQUITY_QUALITY_GREEN, ANTIQUITY_QUALITY_BLUE,
        ANTIQUITY_QUALITY_PURPLE, ANTIQUITY_QUALITY_GOLD,
    }) do
        items[index] = Antiquity(index, "Lead " .. index, { quality = quality })
    end
    local s = Setup(items)
    s:Show()
    local control = s.controls[ADDON_NAME .. "QualityRange"]
    s.mouseX = 4 + 220 / 3
    control.handlers.OnMouseDown(control, MOUSE_BUTTON_INDEX_LEFT)
    s:ExpectRows("2,3,4")
    assert(s.filters.qualityRange.minimum == 2 and s.filters.qualityRange.maximum == 4)
    control.handlers.OnMouseUp(control)
    local maximum = s.controls[ADDON_NAME .. "Qualitymaximum"]
    maximum.handlers.OnMouseEnter(maximum)
    assert(InformationTooltip.text == "Maximum lead quality")
    maximum.handlers.OnMouseDown(maximum, MOUSE_BUTTON_INDEX_LEFT)
    s.mouseX = 4 + 220 * 2 / 3
    control.handlers.OnUpdate(control)
    s:ExpectRows("2,3")
    s.mouseX = -100
    control.handlers.OnUpdate(control)
    s:ExpectRows("2")
    assert(s.filters.qualityRange.maximum == 2, "The upper handle must not cross the lower handle")
    maximum.handlers.OnMouseUp(maximum)
    assert(not s.filters.qualityRange.dragging)
    local blue = s.filters.qualityButtons[2]
    blue.handlers.OnClicked(blue)
    s:ExpectRows("")
    assert(s.filters.qualityRange.selection.alpha == 0)
    s.filters:Reset()
    s:ExpectRows("1,2,3,4")
    assert(s.filters.qualityRange.minimum == 1 and s.filters.qualityRange.maximum == 4)
    assert(s.filters.qualityRange.selection.alpha == 1)
    assert(s.filters.range.minimum == 1 and s.filters.range.maximum == 3)
end

function tests.quality_uses_fragment_colour_and_all_colours_can_be_disabled()
    local set = Antiquity(100, "Gold Set", { quality = ANTIQUITY_QUALITY_GOLD })
    local s = Setup({
        Antiquity(1, "Fragment", { set = set, quality = ANTIQUITY_QUALITY_GREEN }),
        Antiquity(2, "Purple", { quality = ANTIQUITY_QUALITY_PURPLE }),
        Antiquity(3, "Blue", { quality = ANTIQUITY_QUALITY_BLUE }),
    })
    s:Show()
    s:ExpectRows("3,1,2")
    for _, button in ipairs(s.filters.qualityButtons) do button.handlers.OnClicked(button) end
    s:ExpectRows("")
    local gold = s.filters.qualityButtons[4]
    gold.handlers.OnClicked(gold)
    s:ExpectRows("")
    local green = s.filters.qualityButtons[1]
    green.handlers.OnClicked(green)
    s:ExpectRows("1")
    s.filters:Reset()
    s:ExpectRows("3,1,2")
    for _, button in ipairs(s.filters.qualityButtons) do assert(button.swatch.alpha == 1) end
end

function tests.saved_quality_choices_are_restored_without_changing_difficulty()
    local qualities = { true, true, false, false, false, true }
    local s = Setup({
        Antiquity(1, "Green", { quality = ANTIQUITY_QUALITY_GREEN }),
        Antiquity(2, "Blue", { quality = ANTIQUITY_QUALITY_BLUE }),
        Antiquity(3, "White", { quality = ANTIQUITY_QUALITY_WHITE }),
        Antiquity(4, "Orange", { quality = ANTIQUITY_QUALITY_ORANGE }),
    }, { saved = { qualities = qualities } })
    s:Show()
    s:ExpectRows("1")
    assert(#s.filters.qualityButtons == 4 and s.saved.qualities[ANTIQUITY_QUALITY_WHITE] == nil)
    assert(s.saved.qualities[ANTIQUITY_QUALITY_ORANGE] == nil)
    assert(s.filters.qualityButtons[1].swatch.alpha == 1 and s.filters.qualityButtons[2].swatch.alpha == 0.25)
    assert(s.filters.qualityRange.minimum == 1 and s.filters.qualityRange.maximum == 1)
    s:Hide()
    s:Show()
    s:ExpectRows("1")
    assert(s.saved.difficulties[ANTIQUITY_DIFFICULTY_ADVANCED])
    s.filters:Reset()
    s:ExpectRows("2,1")
end

function tests.sidebar_aligns_with_native_header_edge_and_footer_after_resizing()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    local function CheckPlacement()
        local anchors = s.filters.panel.anchors
        assert(#anchors == 2)
        local top, bottom = anchors[1], anchors[2]
        assert(top[1] == TOPRIGHT and top[2] == ZO_SharedTitle:GetNamedChild("Label") and top[3] == TOPLEFT)
        assert(top[2]:GetLeft() + top[4] == ZO_SharedRightBackground:GetLeft(),
            "The sidebar must join the native background edge without a gap or overlap")
        assert(top[5] == 0, "The filter title must align with Quest Journal, not the lower category title")
        assert(bottom[1] == BOTTOMRIGHT and bottom[2] == s.owner.control and bottom[3] == BOTTOMLEFT)
        assert(bottom[5] == 0 and bottom[6] == ANCHOR_CONSTRAINS_Y,
            "The footer must extend to the journal bottom without moving the sidebar horizontally")
    end
    CheckPlacement()
    ZO_SharedRightBackground.left = 510
    s.owner.categoryLabel.left = 900
    ZO_SharedRightBackground.handlers.OnRectChanged(ZO_SharedRightBackground)
    CheckPlacement()
    local journalTitle = ZO_SharedTitle:GetNamedChild("Label")
    journalTitle.left = 650
    journalTitle.handlers.OnRectChanged(journalTitle)
    CheckPlacement()
    local source = s.filters.backgroundTextures[1].source
    source.height = 1200
    source.handlers.OnRectChanged(source)
    assert(s.filters.backgroundTextures[1].control.height == 1200)
    assert(s.controls[ADDON_NAME .. "Separator"])
end

function tests.connected_background_copies_both_native_textures_without_mutating_them()
    local s = Setup({ Antiquity(1, "Ore") })
    local left = ZO_SharedRightBackground:GetNamedChild("Left")
    local right = ZO_SharedRightBackground:GetNamedChild("Right")
    left.color, left.alpha, left.textureCoords = { 0.7, 0.6, 0.5, 0.8 }, 0.9, { 0.1, 0.9, 0.2, 0.8 }
    right.color, right.alpha = { 0.6, 0.5, 0.4, 0.7 }, 0.8
    s:Show()
    assert(s.fragments[RIGHT_BG_FRAGMENT] == nil and s.fragmentRemoves == 1)
    assert(ZO_SharedRightBackground:IsControlHidden(), "Scene removal must refresh the native background")
    for _, background in ipairs(s.filters.backgroundTextures) do
        local source, texture = background.source, background.control
        assert(texture.texture == source.texture and texture.alpha == source.alpha)
        assert(table.concat(texture.color, ",") == table.concat(source.color, ","))
        assert(table.concat(texture.textureCoords, ",") == table.concat(source.textureCoords, ","))
        assert(not texture:IsControlHidden())
        assert(not source.geometryWrites and not source.hidden,
            "Only scene membership, not shared texture geometry or visibility, may be changed")
    end
    local first, second = s.filters.backgroundTextures[1], s.filters.backgroundTextures[2]
    assert(first.control.height == first.source.height)
    assert(first.control.anchors[2][2] == first.source)
    assert(second.control.anchorFill == second.source)
    s.filters:UpdateVisibility(s.owner, s.category)
    assert(s.fragmentRemoves == 1, "Repeated refreshes must not acquire the background twice")
    s:Hide()
    assert(s.fragments[RIGHT_BG_FRAGMENT] and s.fragmentAdds == 1)
    assert(s.otherSceneFragments[RIGHT_BG_FRAGMENT])
end

function tests.category_changes_restore_and_reacquire_only_the_journal_background()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    s:Select(s:Category(false))
    assert(s.fragments[RIGHT_BG_FRAGMENT] and not s.filters.backgroundState)
    for _, background in ipairs(s.filters.backgroundTextures) do assert(background.control.hidden) end
    assert(s.fragmentAdds == 1)
    s:Select(s:Category(true))
    assert(s.fragments[RIGHT_BG_FRAGMENT] == nil and s.filters.backgroundState)
    assert(s.fragmentRemoves == 2)
    s.gamepad = true
    s.filters:UpdateVisibility(s.owner, s.category)
    assert(s.fragments[RIGHT_BG_FRAGMENT] and not s.filters.backgroundState)
    assert(s.fragmentAdds == 2)
end

function tests.absent_native_fragment_is_not_added_during_restoration()
    local s = Setup({ Antiquity(1, "Ore") }, { backgroundFragment = false })
    s:Show()
    assert(s.filters.backgroundState and not s.filters.backgroundState.hadFragment)
    s:Hide()
    assert(not s.fragments[RIGHT_BG_FRAGMENT])
    assert(s.fragmentAdds == 0 and s.fragmentRemoves == 0)
    assert(s.otherSceneFragments[RIGHT_BG_FRAGMENT])
end

function tests.parent_hiding_restores_background_and_cleans_controls_without_scene_callback()
    local s = Setup({ Antiquity(1, "Ore") })
    s:Show()
    s.filters.typeCombo.open = true
    s.filters.searchEdit.focused = true
    s.filters.searchEdit:SetText("ore")
    s.filters.range.dragging = "minimum"
    s.owner.control:SetHidden(true)
    assert(s.filters.panel:IsControlHidden() and s.filters.panel.hidden == false)
    assert(not s.filters.backgroundState and s.fragments[RIGHT_BG_FRAGMENT])
    assert(not s.filters.typeCombo.open and not s.filters.searchEdit.focused)
    assert(not s.filters.range.dragging and next(s.updates) == nil)
    for _, background in ipairs(s.filters.backgroundTextures) do assert(background.control.hidden) end
    s.owner.control:SetHidden(false)
    assert(s.filters.backgroundState and s.fragments[RIGHT_BG_FRAGMENT] == nil)
    s:Hide()
    assert(s.fragments[RIGHT_BG_FRAGMENT] and s.fragmentAdds == 2 and s.fragmentRemoves == 2)
end

function tests.full_refresh_restores_hover_on_a_reused_visible_tile()
    local s = Setup({ Antiquity(1, "Lead") })
    s:Show()
    local tile = s.owner.antiquityTilesByAntiquityId[1]
    s.owner.mouseOverTile = tile
    s.owner:OnAntiquitiesUpdated()
    assert(s.owner.antiquityTilesByAntiquityId[1] == tile)
    assert(s.owner.mouseOverTile == tile, "A visible reused tile must retain its native tooltip/action state")
    assert(s.hoverRestores == 1, "Restore hover through the native method")
end

function tests.filtered_out_hovered_tiles_are_not_restored()
    local s = Setup({ Antiquity(1, "Keep"), Antiquity(2, "Remove") })
    s:Show()
    local tile = s.owner.antiquityTilesByAntiquityId[2]
    s.owner.mouseOverTile = tile
    s.filters.saved.search = "Keep"
    s.filters:Refresh()
    assert(tile:IsControlHidden())
    assert(not s.owner.mouseOverTile and not s.hoverRestores)
    s.owner.mouseOverTile = s.owner.antiquityTilesByAntiquityId[1]
    s.filters.saved.search = "No matches"
    s.filters:Refresh()
    assert(not s.owner.mouseOverTile and not s.hoverRestores)
end

local passed = 0
for name, test in pairs(tests) do
    test()
    passed = passed + 1
    print("PASS " .. name)
end
print(string.format("%d tests passed", passed))
