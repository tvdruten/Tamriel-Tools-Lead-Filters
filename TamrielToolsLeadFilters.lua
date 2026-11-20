TamrielToolsLeadFilters = {}
local Filters = TamrielToolsLeadFilters
local ADDON_NAME = "TamrielToolsLeadFilters"
local ICON_PATH = ADDON_NAME .. "/Icons/"
local REFRESH_NAME = ADDON_NAME .. "Refresh"
local DIFFICULTIES = {
    ANTIQUITY_DIFFICULTY_ADVANCED,
    ANTIQUITY_DIFFICULTY_MASTER,
    ANTIQUITY_DIFFICULTY_ULTIMATE,
}
local QUALITIES = {
    { value = ANTIQUITY_QUALITY_GREEN, label = "Green" },
    { value = ANTIQUITY_QUALITY_BLUE, label = "Blue" },
    { value = ANTIQUITY_QUALITY_PURPLE, label = "Purple" },
    { value = ANTIQUITY_QUALITY_GOLD, label = "Gold" },
}
local SORT_OPTIONS = {
    { value = "zone", label = "Zone (A-Z)" },
    { value = "expiry", label = "Lead Expiry (soonest first)" },
    { value = "name", label = "Alphabetical" },
}
local STATUS_OPTIONS = {
    { value = "all", label = "All lead statuses" },
    { value = ZO_ANTIQUITY_SECTION_TYPE.IN_PROGRESS, label = GetString(SI_ANTIQUITY_SUBHEADING_IN_PROGRESS) },
    { value = ZO_ANTIQUITY_SECTION_TYPE.AVAILABLE, label = GetString(SI_ANTIQUITY_SUBHEADING_AVAILABLE) },
    { value = ZO_ANTIQUITY_SECTION_TYPE.REQUIRES_LEAD, label = GetString(SI_ANTIQUITY_SUBHEADING_REQUIRES_LEAD) },
    { value = ZO_ANTIQUITY_SECTION_TYPE.ACTIVE_LEAD, label = GetString(SI_ANTIQUITY_SUBHEADING_ACTIVE_LEADS) },
    { value = ZO_ANTIQUITY_SECTION_TYPE.REQUIRES_SKILL, label = "Requires scrying skill" },
}
local defaults = {
    search = "", rewardType = "", status = "all", sortBy = "zone",
    difficulties = {}, qualities = {},
}
for _, difficulty in ipairs(DIFFICULTIES) do
    defaults.difficulties[difficulty] = true
end
for _, quality in ipairs(QUALITIES) do
    defaults.qualities[quality.value] = true
end

function Filters.NormalizeText(text)
    return zo_strlower(text:gsub("|[cC]%x%x%x%x%x%x", ""):gsub("|[rR]", ""))
end

function Filters.Matches(entry, settings, searchWords)
    if not settings.difficulties[entry.difficulty] then
        return false
    end
    if not settings.qualities[entry.quality] then
        return false
    end
    if settings.status ~= "all" and entry.sectionType ~= settings.status then
        return false
    end
    if settings.rewardType ~= "" and entry.rewardType ~= settings.rewardType then
        return false
    end
    for _, word in ipairs(searchWords) do
        if not entry.searchText:find(word, 1, true) then
            return false
        end
    end
    return true
end

function Filters.Compare(left, right, sortBy)
    if sortBy == "expiry" then
        local leftTime, rightTime = left.remaining or math.huge, right.remaining or math.huge
        if leftTime ~= rightTime then return leftTime < rightTime end
    end
    if sortBy ~= "name" then
        if left.zoneId == 0 and right.zoneId ~= 0 then return false end
        if right.zoneId == 0 and left.zoneId ~= 0 then return true end
        if left.zoneSort ~= right.zoneSort then return left.zoneSort < right.zoneSort end
    end
    if left.nameSort ~= right.nameSort then return left.nameSort < right.nameSort end
    return left.id < right.id
end

function Filters:GetMetadata(data)
    local setData = data:GetAntiquitySetData()
    local rewardData = setData and setData:HasReward() and setData or data
    local rewardType = rewardData:HasReward()
        and REWARDS_MANAGER:GetRewardContextualTypeString(rewardData:GetRewardId())
        or nil
    rewardType = rewardType or GetString(SI_ANTIQUITY_TYPE_FALLBACK)
    local name = data:GetFormattedName()
    local zoneId = data:GetZoneId()
    local zone = zoneId == 0 and "Any zone" or zo_strformat(SI_ZONE_NAME, GetZoneNameById(zoneId))
    local remaining = data:HasLead() and data:GetLeadTimeRemainingS() or 0
    local setName = setData and setData:GetFormattedName() or ""
    return {
        id = data:GetId(),
        name = name,
        nameSort = self.NormalizeText(name),
        zoneId = zoneId,
        zoneSort = self.NormalizeText(zone),
        searchText = self.NormalizeText(name .. " " .. zone .. " " .. setName),
        rewardType = rewardType,
        difficulty = data:GetDifficulty(),
        quality = data:GetQuality(),
        remaining = remaining > 0 and remaining or nil,
        data = data,
    }
end

function Filters:CollectEntries(category)
    local sections = ANTIQUITY_MANAGER:GetOrCreateAntiquitySectionList()
    local visibleSections = {}
    for sectionIndex, section in ipairs(sections) do
        if ANTIQUITY_MANAGER:ShouldScryableSubcategoryShowSection(category, section) then
            visibleSections[#visibleSections + 1] = sectionIndex
        end
    end
    local entries = {}
    for _, data in category:AntiquityIterator({ ZO_Antiquity.IsVisible }) do
        for _, sectionIndex in ipairs(visibleSections) do
            local section = sections[sectionIndex]
            local matches = true
            for _, predicate in ipairs(section.filterFunctions) do
                if not predicate(data) then
                    matches = false
                    break
                end
            end
            if matches then
                local entry = self:GetMetadata(data)
                entry.sectionIndex, entry.sectionType = sectionIndex, section.sectionType
                entries[#entries + 1] = entry
                break
            end
        end
    end
    return entries, sections
end

function Filters:IsActive(owner, category)
    return self.panel ~= nil and owner == ANTIQUITY_JOURNAL_KEYBOARD
        and owner.scene:IsShowing() and not IsInGamepadPreferredMode()
        and category ~= nil and ZO_IsAntiquityScryableSubcategory(category)
        and ZO_IsScryingUnlocked()
end

function Filters:BuildList(owner, category)
    EVENT_MANAGER:UnregisterForUpdate(REFRESH_NAME)
    local entries, sections = self:CollectEntries(category)
    local groups, metadata = {}, {}
    local searchWords = {}
    for word in self.NormalizeText(self.saved.search):gmatch("%S+") do
        searchWords[#searchWords + 1] = word
    end
    local matchCount = 0
    for _, entry in ipairs(entries) do
        if self.Matches(entry, self.saved, searchWords) then
            local group = groups[entry.sectionIndex]
            if not group then
                group = {}
                groups[entry.sectionIndex] = group
            end
            group[#group + 1] = entry.data
            metadata[entry.id] = entry
            matchCount = matchCount + 1
        end
    end

    local offset
    if owner.isRefreshingAll then
        local _, verticalOffset = owner.contentList.scroll:GetScrollOffsets()
        offset = verticalOffset
    end
    local oldMouseOverTile = owner.mouseOverTile
    owner:ResetCategoryTiles(true)
    local function Compare(left, right)
        return self.Compare(metadata[left:GetId()], metadata[right:GetId()], self.saved.sortBy)
    end
    local previousTileOrHeading
    for sectionIndex, section in ipairs(sections) do
        local group = groups[sectionIndex]
        if group then
            previousTileOrHeading = owner:AddScryableAntiquityTiles(
                previousTileOrHeading, section.sectionHeading, group, Compare)
            for _, data in ipairs(group) do
                local tile = owner.antiquityTilesByAntiquityId[data:GetId()]
                if not tile.tamrielToolsCodexProgress then self:UpdateCodexProgress(tile) end
            end
        end
    end
    owner.contentList:SetHidden(matchCount == 0)
    owner.contentEmptyLabel:SetHidden(matchCount > 0)
    if offset then
        ZO_Scroll_ScrollAbsoluteInstantly(owner.contentList, offset)
    end
    self.countLabel:SetText(string.format("%d / %d leads", matchCount, #entries))
    self:UpdateTypeChoices(entries)
    if oldMouseOverTile and not oldMouseOverTile:IsControlHidden() then
        owner:SetMouseOverTile(oldMouseOverTile)
    end
end

function Filters:UpdateCodexProgress(tile)
    local owner = ANTIQUITY_JOURNAL_KEYBOARD
    local category = owner.categoryTree and owner.categoryTree:GetSelectedData()
    local progress = tile.tamrielToolsCodexProgress
    local data = tile.tileData
    if not self:IsActive(owner, category) or not data or not data:HasDiscovered() or data:GetNumLoreEntries() == 0 then
        if progress then progress:SetHidden(true) end
        return
    end
    if not progress then
        progress = WINDOW_MANAGER:CreateControlFromVirtual(
            ADDON_NAME .. tile.control:GetName() .. "Codex", tile.header, "ZO_AntiquityLogBookProgress")
        progress:SetAnchor(TOPRIGHT, tile.header, TOPRIGHT, -15, 0)
        tile.tamrielToolsCodexProgress = progress
    end
    progress:GetNamedChild("Progress"):SetText(string.format(
        "%d / %d", data:GetNumUnlockedLoreEntries(), data:GetNumLoreEntries()))
    progress:SetHidden(false)
end

function Filters:Refresh()
    local owner = ANTIQUITY_JOURNAL_KEYBOARD
    local category = owner.categoryTree and owner.categoryTree:GetSelectedData()
    if self:IsActive(owner, category) then
        owner:BuildCategoryAntiquityTiles(category)
    end
end

function Filters:QueueRefresh()
    local owner = ANTIQUITY_JOURNAL_KEYBOARD
    local category = owner.categoryTree and owner.categoryTree:GetSelectedData()
    if not self:IsActive(owner, category) then return end
    EVENT_MANAGER:RegisterForUpdate(REFRESH_NAME, 100, function()
        EVENT_MANAGER:UnregisterForUpdate(REFRESH_NAME)
        self:Refresh()
    end)
end

local function AddTooltip(control, text)
    control:SetMouseEnabled(true)
    ZO_PostHookHandler(control, "OnMouseEnter", function()
        InitializeTooltip(InformationTooltip, control, BOTTOM, 0, -6)
        SetTooltipText(InformationTooltip, type(text) == "function" and text() or text)
    end)
    local function HideTooltip()
        if InformationTooltip:GetOwner() == control then ClearTooltip(InformationTooltip) end
    end
    ZO_PostHookHandler(control, "OnMouseExit", HideTooltip)
    ZO_PostHookHandler(control, "OnEffectivelyHidden", HideTooltip)
end

local function Label(name, parent, text, y, font)
    local control = WINDOW_MANAGER:CreateControl(ADDON_NAME .. name, parent, CT_LABEL)
    control:SetFont(font or "ZoFontWinH4")
    control:SetDimensions(228, 24)
    control:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
    control:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    control:SetText(text)
    return control
end

local function Dropdown(name, parent, y)
    local control = WINDOW_MANAGER:CreateControlFromVirtual(ADDON_NAME .. name, parent, "ZO_ComboBox")
    control:SetDimensions(228, 28)
    control:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
    local combo = ZO_ComboBox_ObjectFromContainer(control)
    combo:SetSortsItems(false)
    combo:SetFont("ZoFontWinT1")
    return combo, control
end

function Filters:FillDropdown(combo, options, setting)
    combo:ClearItems()
    local selected = 1
    for index, option in ipairs(options) do
        local value = option.value
        combo:AddItem(combo:CreateItemEntry(option.label, function()
            if not self.updatingControls then
                self.saved[setting] = value
                self:Refresh()
            end
        end))
        if self.saved[setting] == value then selected = index end
    end
    combo:SelectItemByIndex(selected, true)
end

function Filters:UpdateTypeChoices(entries)
    local types = {}
    for _, entry in ipairs(entries) do types[entry.rewardType] = true end
    if self.saved.rewardType ~= "" then types[self.saved.rewardType] = true end
    local labels = {}
    for name in pairs(types) do labels[#labels + 1] = name end
    table.sort(labels)
    local signature = table.concat(labels, "\n") .. "\n" .. self.saved.rewardType
    if self.typeSignature == signature then return end
    self.typeSignature = signature
    local options = { { value = "", label = "All types" } }
    for _, name in ipairs(labels) do options[#options + 1] = { value = name, label = name } end
    self:FillDropdown(self.typeCombo, options, "rewardType")
end

function Filters:UpdateDifficulties()
    local minimum, maximum
    for index, difficulty in ipairs(DIFFICULTIES) do
        local selected = self.saved.difficulties[difficulty]
        self.difficultyButtons[index]:SetAlpha(selected and 1 or 0.45)
        if selected then
            minimum = minimum or index
            maximum = index
        end
    end
    self.range:SetValues(minimum or 1, maximum or #DIFFICULTIES)
    self.range.selection:SetAlpha(minimum and 1 or 0)
end

function Filters:UpdateQualities()
    local minimum, maximum
    for index, quality in ipairs(QUALITIES) do
        local selected = self.saved.qualities[quality.value]
        self.qualityButtons[index].swatch:SetAlpha(selected and 1 or 0.25)
        if selected then
            minimum = minimum or index
            maximum = index
        end
    end
    self.qualityRange:SetValues(minimum or 1, maximum or #QUALITIES)
    self.qualityRange.selection:SetAlpha(minimum and 1 or 0)
end

function Filters:Reset()
    self.saved.search, self.saved.rewardType = "", ""
    self.saved.status, self.saved.sortBy = "all", "zone"
    for _, difficulty in ipairs(DIFFICULTIES) do self.saved.difficulties[difficulty] = true end
    for _, quality in ipairs(QUALITIES) do self.saved.qualities[quality.value] = true end
    self.updatingControls = true
    self.searchEdit:SetText("")
    self:FillDropdown(self.sortCombo, SORT_OPTIONS, "sortBy")
    self:FillDropdown(self.statusCombo, STATUS_OPTIONS, "status")
    self:UpdateDifficulties()
    self:UpdateQualities()
    self.updatingControls = false
    self:Refresh()
end

local function CreateTierRange(parent, name, y, count, label, onChanged)
    local control = WINDOW_MANAGER:CreateControl(ADDON_NAME .. name .. "Range", parent, CT_CONTROL)
    control:SetDimensions(228, 18)
    control:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
    control:SetMouseEnabled(true)
    local range = { minimum = 1, maximum = count }
    local track = WINDOW_MANAGER:CreateControl(ADDON_NAME .. name .. "Track", control, CT_TEXTURE)
    track:SetDimensions(220, 4)
    track:SetAnchor(TOPLEFT, control, TOPLEFT, 4, 7)
    track:SetColor(0.45, 0.44, 0.31, 0.8)
    local selection = WINDOW_MANAGER:CreateControl(ADDON_NAME .. name .. "RangeSelection", control, CT_TEXTURE)
    selection:SetColor(0.2, 0.48, 0.47, 0.95)
    range.selection = selection
    local handles = {}
    for _, boundary in ipairs({ "minimum", "maximum" }) do
        local handle = WINDOW_MANAGER:CreateControl(ADDON_NAME .. name .. boundary, control, CT_BUTTON)
        handle:SetDimensions(8, 16)
        handle:SetNormalTexture("EsoUI/Art/Miscellaneous/scrollbox_elevator.dds")
        handle:SetPressedTexture("EsoUI/Art/Miscellaneous/scrollbox_elevator.dds")
        handle:SetMouseOverTexture("EsoUI/Art/Miscellaneous/scrollbox_elevator.dds")
        handle:SetHandler("OnMouseDown", function(_, button)
            if button == MOUSE_BUTTON_INDEX_LEFT then range.dragging = boundary end
        end)
        handle:SetHandler("OnMouseUp", function() range.dragging = nil end)
        AddTooltip(handle, (boundary == "minimum" and "Minimum " or "Maximum ") .. label)
        handles[boundary] = handle
    end
    function range:SetValues(minimum, maximum)
        self.minimum, self.maximum = minimum, maximum
        local left = (minimum - 1) / (count - 1) * 220
        local right = (maximum - 1) / (count - 1) * 220
        selection:ClearAnchors()
        selection:SetAnchor(TOPLEFT, control, TOPLEFT, left + 4, 7)
        selection:SetDimensions(math.max(1, right - left), 4)
        for boundary, handle in pairs(handles) do
            handle:ClearAnchors()
            handle:SetAnchor(TOPLEFT, control, TOPLEFT, boundary == "minimum" and left or right, 1)
        end
    end
    local function MouseStep()
        local x = GetUIMousePosition()
        return 1 + (x - control:GetLeft() - 4) / 220 * (count - 1)
    end
    local function Move()
        local value = math.max(1, math.min(count, math.floor(MouseStep() + 0.5)))
        local minimum, maximum = range.minimum, range.maximum
        if range.dragging == "minimum" then minimum = math.min(value, maximum)
        else maximum = math.max(value, minimum) end
        if minimum ~= range.minimum or maximum ~= range.maximum then
            range:SetValues(minimum, maximum)
            onChanged(minimum, maximum)
        end
    end
    control:SetHandler("OnMouseDown", function(_, button)
        if button == MOUSE_BUTTON_INDEX_LEFT then
            local step = MouseStep()
            range.dragging = math.abs(step - range.minimum) <= math.abs(step - range.maximum) and "minimum" or "maximum"
            Move()
        end
    end)
    control:SetHandler("OnUpdate", function()
        if range.dragging then Move() end
    end)
    control:SetHandler("OnMouseUp", function() range.dragging = nil end)
    control:SetHandler("OnEffectivelyHidden", function() range.dragging = nil end)
    range:SetValues(1, count)
    return range
end

local function CreateTierSwatch(button, suffix, red, green, blue)
    local frame = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Frame" .. suffix, button, CT_TEXTURE)
    frame:SetAnchorFill(button)
    frame:SetTexture(ICON_PATH .. "QualityFrame.dds")
    frame:SetColor(0.85, 0.85, 0.65, 1)
    local swatch = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Swatch" .. suffix, button, CT_TEXTURE)
    swatch:SetAnchorFill(button)
    swatch:SetTexture(ICON_PATH .. "QualityFill.dds")
    swatch:SetColor(red, green, blue)
    button.swatch = swatch
end

function Filters:CreatePanel(owner)
    if self.panel then return end
    local panel = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Panel", owner.control, CT_CONTROL)
    panel:SetDimensions(260, 0)
    panel:SetHidden(true)
    self.panel = panel
    self.backgroundTextures = {}
    for _, name in ipairs({ "Left", "Right" }) do
        local source = ZO_SharedRightBackground:GetNamedChild(name)
        local texture = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Background" .. name, owner.control, CT_TEXTURE)
        texture:SetDrawLayer(DL_BACKGROUND)
        texture:SetMouseEnabled(true)
        texture:SetHidden(true)
        self.backgroundTextures[#self.backgroundTextures + 1] = { source = source, control = texture }
    end
    self.backgroundTextures[1].control:SetAnchor(TOPLEFT, panel, TOPLEFT, -65, 0, ANCHOR_CONSTRAINS_X)
    self.backgroundTextures[1].control:SetAnchor(BOTTOMRIGHT, self.backgroundTextures[1].source, BOTTOMRIGHT, 0, 0)
    self.backgroundTextures[2].control:SetAnchorFill(self.backgroundTextures[2].source)
    self:UpdatePanelPlacement(owner)
    local header = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Header", panel, CT_CONTROL)
    header:SetDimensions(228, 30)
    header:SetAnchor(TOPLEFT, panel, TOPLEFT, 16, 0)
    Label("Title", header, "Lead Filters", 0, "ZoFontHeader3")
    local reset = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Reset", panel, CT_BUTTON)
    reset:SetDimensions(28, 28)
    reset:SetAnchor(TOPRIGHT, panel, TOPRIGHT, -16, 0)
    reset:SetNormalTexture(ICON_PATH .. "Reset.dds")
    reset:SetPressedTexture(ICON_PATH .. "Reset.dds")
    reset:SetMouseOverTexture(ICON_PATH .. "Reset.dds")
    reset:SetHandler("OnClicked", function() self:Reset() end)
    AddTooltip(reset, "Reset lead filters and sorting. Does not change the journal's search or selected category.")
    for _, y in ipairs({ 28, -28 }) do
        local line = WINDOW_MANAGER:CreateControl(nil, panel, CT_TEXTURE)
        line:SetDimensions(228, 1)
        local anchor = y > 0 and TOPLEFT or BOTTOMLEFT
        line:SetAnchor(anchor, panel, anchor, 16, y)
        line:SetColor(0.55, 0.53, 0.39, 0.5)
    end
    local separator = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Separator", panel, CT_TEXTURE)
    separator:SetDrawLayer(DL_BACKGROUND)
    separator:SetDimensions(1, 0)
    separator:SetAnchor(TOPRIGHT, panel, TOPRIGHT, 0, 28)
    separator:SetAnchor(BOTTOMRIGHT, panel, BOTTOMRIGHT, 0, -30)
    separator:SetColor(0.55, 0.53, 0.39, 0.3)
    local scroll = WINDOW_MANAGER:CreateControlFromVirtual(ADDON_NAME .. "Body", panel, "ZO_ScrollContainer")
    scroll:ClearAnchors()
    scroll:SetAnchor(TOPLEFT, panel, TOPLEFT, 16, 42)
    scroll:SetAnchor(BOTTOMRIGHT, panel, BOTTOMRIGHT, 0, -38)
    local content = scroll:GetNamedChild("ScrollChild")
    content:SetDimensions(228, 480)

    Label("SearchLabel", content, "Text Search:", 0)
    local editBackdrop = WINDOW_MANAGER:CreateControlFromVirtual(ADDON_NAME .. "Search", content, "ZO_SingleLineEditBackdrop_Keyboard")
    editBackdrop:SetDimensions(228, 28)
    editBackdrop:SetAnchor(TOPLEFT, content, TOPLEFT, 0, 28)
    local edit = WINDOW_MANAGER:CreateControlFromVirtual(ADDON_NAME .. "SearchEdit", editBackdrop, "ZO_DefaultEditForBackdrop")
    edit:SetFont("ZoFontWinT1")
    edit:SetMaxInputChars(160)
    edit:SetDefaultText("")
    edit:SetText(self.saved.search)
    edit:SetHandler("OnTextChanged", function()
        if not self.updatingControls then
            self.saved.search = edit:GetText()
            self:QueueRefresh()
        end
    end)
    self.searchEdit = edit
    AddTooltip(edit, "Search lead, completed set, and zone names. Every word must match; word order does not matter.")

    Label("SortLabel", content, "Sort By:", 76)
    local sortControl
    self.sortCombo, sortControl = Dropdown("SortBy", content, 104)
    self:FillDropdown(self.sortCombo, SORT_OPTIONS, "sortBy")
    AddTooltip(sortControl, "Sort within each native status group. Expiry puts timed leads first, soonest first; entries without an expiry come last within that group.")
    Label("TypeLabel", content, "Type:", 152)
    local typeControl
    self.typeCombo, typeControl = Dropdown("Type", content, 180)
    self:UpdateTypeChoices({})
    AddTooltip(typeControl, "Filter by reward type. Set fragments use the completed set's reward type when available.")

    Label("StatusLabel", content, "Lead Status:", 228)
    local statusControl
    self.statusCombo, statusControl = Dropdown("Status", content, 256)
    self:FillDropdown(self.statusCombo, STATUS_OPTIONS, "status")
    AddTooltip(statusControl, "Filter by ESO's native journal groups, including Available and Requires Lead. Only groups supported by the selected Scryable category are shown.")

    local difficultyLabel = Label("DifficultyLabel", content, "Difficulty:", 304)
    AddTooltip(difficultyLabel, "Filters ESO's reported scrying difficulty, as shown in the journal. This is separate from the lead name's colour.")
    self.range = CreateTierRange(content, "", 332, #DIFFICULTIES, "difficulty", function(minimum, maximum)
        for index, difficulty in ipairs(DIFFICULTIES) do
            self.saved.difficulties[difficulty] = index >= minimum and index <= maximum
        end
        self:UpdateDifficulties()
        self:Refresh()
    end)
    self.difficultyButtons = {}
    for index, difficulty in ipairs(DIFFICULTIES) do
        local selectedDifficulty = difficulty
        local button = WINDOW_MANAGER:CreateControlFromVirtual(
            ADDON_NAME .. "Difficulty" .. index, content, "ZO_DefaultButton")
        button:SetDimensions(76, 28)
        button:SetAnchor(TOPLEFT, content, TOPLEFT, (index - 1) * 76, 354)
        button:SetFont("ZoFontGameSmall")
        local name = GetString("SI_ANTIQUITYDIFFICULTY", selectedDifficulty)
        button:SetText(name)
        button:SetHandler("OnClicked", function()
            self.saved.difficulties[selectedDifficulty] = not self.saved.difficulties[selectedDifficulty]
            self:UpdateDifficulties()
            self:Refresh()
        end)
        AddTooltip(button, function()
            return name
                .. (self.saved.difficulties[selectedDifficulty] and " (shown)" or " (hidden)")
        end)
        self.difficultyButtons[index] = button
    end
    self:UpdateDifficulties()
    local qualityLabel = Label("QualityLabel", content, "Lead Quality:", 392)
    AddTooltip(qualityLabel, "Filters the lead name's colour, independently of difficulty. Set fragments use their own quality, not the completed set's quality.")
    self.qualityRange = CreateTierRange(content, "Quality", 420, #QUALITIES, "lead quality", function(minimum, maximum)
        for index, quality in ipairs(QUALITIES) do
            self.saved.qualities[quality.value] = index >= minimum and index <= maximum
        end
        self:UpdateQualities()
        self:Refresh()
    end)
    self.qualityButtons = {}
    for index, quality in ipairs(QUALITIES) do
        local selectedQuality, qualityLabelText = quality.value, quality.label
        local button = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "Quality" .. index, content, CT_BUTTON)
        button:SetDimensions(36, 36)
        button:SetAnchor(TOPLEFT, content, TOPLEFT, (index - 1) * 64, 442)
        CreateTierSwatch(button, "Quality" .. index, GetAntiquityQualityColor(selectedQuality):UnpackRGB())
        button:SetHandler("OnClicked", function()
            self.saved.qualities[selectedQuality] = not self.saved.qualities[selectedQuality]
            self:UpdateQualities()
            self:Refresh()
        end)
        AddTooltip(button, function()
            return qualityLabelText .. " lead quality"
                .. (self.saved.qualities[selectedQuality] and " (shown)" or " (hidden)")
        end)
        self.qualityButtons[index] = button
    end
    self:UpdateQualities()
    self.countLabel = Label("Count", panel, "", 0, "ZoFontGameSmall")
    self.countLabel:ClearAnchors()
    self.countLabel:SetAnchor(BOTTOMLEFT, panel, BOTTOMLEFT, 16, -2)
    self.countLabel:SetColor(0.72, 0.71, 0.6, 1)
    ZO_PostHookHandler(panel, "OnEffectivelyHidden", function() self:CloseControls() end)
    ZO_PostHookHandler(panel, "OnEffectivelyShown", function()
        self:UpdatePanelPlacement(owner)
        self:ShowConnectedBackground(owner)
    end)
    for _, control in ipairs({
        ZO_SharedTitle:GetNamedChild("Label"), owner.control,
        ZO_SharedRightBackground, self.backgroundTextures[1].source,
    }) do
        ZO_PostHookHandler(control, "OnRectChanged", function() self:UpdatePanelPlacement(owner) end)
    end
end

function Filters:UpdatePanelPlacement(owner)
    local journalTitle = ZO_SharedTitle:GetNamedChild("Label")
    local offsetX = ZO_SharedRightBackground:GetLeft() - journalTitle:GetLeft()
    self.panel:ClearAnchors()
    self.panel:SetAnchor(TOPRIGHT, journalTitle, TOPLEFT, offsetX, 0)
    self.panel:SetAnchor(BOTTOMRIGHT, owner.control, BOTTOMLEFT, 0, 0, ANCHOR_CONSTRAINS_Y)
    local background = self.backgroundTextures[1]
    local _, height = background.source:GetDimensions()
    background.control:SetDimensions(0, height)
end

function Filters:ShowConnectedBackground(owner)
    local category = owner.categoryTree and owner.categoryTree:GetSelectedData()
    if not self:IsActive(owner, category) or self.panel:IsControlHidden() then
        self:RestoreNativeBackground()
        return
    end
    if self.backgroundState then return end
    self.backgroundState = { scene = owner.scene, hadFragment = owner.scene:HasFragment(RIGHT_BG_FRAGMENT) }
    for _, background in ipairs(self.backgroundTextures) do
        local source, texture = background.source, background.control
        texture:SetTexture(source:GetTextureFileName())
        texture:SetTextureCoords(source:GetTextureCoords())
        texture:SetColor(source:GetColor())
        texture:SetAlpha(source:GetAlpha())
        texture:SetHidden(false)
    end
    if self.backgroundState.hadFragment then
        owner.scene:RemoveFragment(RIGHT_BG_FRAGMENT)
    end
end

function Filters:RestoreNativeBackground()
    local state = self.backgroundState
    if not state then return end
    self.backgroundState = nil
    for _, background in ipairs(self.backgroundTextures) do background.control:SetHidden(true) end
    if state.hadFragment then state.scene:AddFragment(RIGHT_BG_FRAGMENT) end
end

function Filters:CloseControls()
    self:RestoreNativeBackground()
    EVENT_MANAGER:UnregisterForUpdate(REFRESH_NAME)
    self.sortCombo:HideDropdown()
    self.typeCombo:HideDropdown()
    self.statusCombo:HideDropdown()
    self.searchEdit:LoseFocus()
    self.range.dragging = nil
    self.qualityRange.dragging = nil
end

function Filters:UpdateVisibility(owner, category)
    if self.panel then
        self:UpdatePanelPlacement(owner)
        self.panel:SetHidden(not self:IsActive(owner, category))
        self:ShowConnectedBackground(owner)
    end
end

function Filters:Initialize()
    self.saved = ZO_SavedVars:New(ADDON_NAME .. "_SV", 1, nil, defaults)
    self.saved.recovery = nil
    self.saved.qualities[ANTIQUITY_QUALITY_WHITE] = nil
    self.saved.qualities[ANTIQUITY_QUALITY_ORANGE] = nil
    self.saved.difficulties[ANTIQUITY_DIFFICULTY_TRIVIAL] = nil
    self.saved.difficulties[ANTIQUITY_DIFFICULTY_SIMPLE] = nil
    self.saved.difficulties[ANTIQUITY_DIFFICULTY_INTERMEDIATE] = nil
    local class = ZO_AntiquityJournal_Keyboard
    SecurePostHook(class, "OnDeferredInitialize", function(owner)
        if owner == ANTIQUITY_JOURNAL_KEYBOARD then self:CreatePanel(owner) end
    end)
    ZO_PreHook(class, "BuildCategoryAntiquityTiles", function(owner, category)
        if self:IsActive(owner, category) then
            self:BuildList(owner, category)
            return true
        end
    end)
    SecurePostHook(class, "OnCategorySelected", function(owner, category)
        if owner == ANTIQUITY_JOURNAL_KEYBOARD then self:UpdateVisibility(owner, category) end
    end)
    ANTIQUITY_DATA_MANAGER:RegisterCallback("SingleAntiquityLeadAcquired", function()
        self:QueueRefresh()
    end)
    SecurePostHook(ZO_ScryableAntiquityTile_Keyboard, "Refresh", function(tile)
        if tile.tamrielToolsCodexProgress then self:UpdateCodexProgress(tile) end
    end)
    SecurePostHook(ZO_ScryableAntiquityTile_Keyboard, "Reset", function(tile)
        if tile.tamrielToolsCodexProgress then tile.tamrielToolsCodexProgress:SetHidden(true) end
    end)
    local owner = ANTIQUITY_JOURNAL_KEYBOARD
    if owner.contentList then self:CreatePanel(owner) end
    owner.scene:RegisterCallback("StateChange", function(_, state)
        if state == SCENE_SHOWING or state == SCENE_SHOWN then
            local category = owner.categoryTree and owner.categoryTree:GetSelectedData()
            self:UpdateVisibility(owner, category)
        elseif self.panel then
            self.panel:SetHidden(true)
            self:CloseControls()
        end
    end)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, function(_, name)
    if name == ADDON_NAME then
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
        Filters:Initialize()
    end
end)
