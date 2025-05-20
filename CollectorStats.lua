-- Create main addon frame and register events
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

-- Cache for inspected players
local currentInspectGUID = nil
local achievementCache = {}

-- Combined tier data for colors and percentiles (sorted descending)
local tierData = {
    {points = 50000, color = "ffd700", percent = "0.01%"},  -- Gold
    {points = 48000, color = "ff8c00", percent = "0.1%"},   -- DarkOrange
    {points = 43000, color = "ff4500", percent = "0.5%"},   -- OrangeRed
    {points = 39600, color = "ff0000", percent = "1%"},     -- Red
    {points = 36000, color = "ff1493", percent = "2%"},     -- DeepPink
    {points = 34000, color = "c71585", percent = "3%"},     -- MediumVioletRed
    {points = 31000, color = "9932cc", percent = "5%"},     -- DarkOrchid
    {points = 27000, color = "483d8b", percent = "10%"},    -- DarkSlateBlue
    {points = 22000, color = "0000cd", percent = "20%"},    -- MediumBlue
    {points = 19000, color = "1e90ff", percent = "30%"},    -- DodgerBlue
    {points = 17500, color = "00bfff", percent = "40%"},    -- DeepSkyBlue
    {points = 15000, color = "20b2aa", percent = "50%"},    -- LightSeaGreen
    {points = 13000, color = "3cb371", percent = "60%"},    -- MediumSeaGreen
    {points = 11000, color = "9acd32", percent = "70%"},    -- YellowGreen
    {points = 8000,  color = "6b8e23", percent = "80%"},    -- OliveDrab
    {points = 5000,  color = "bdb76b", percent = "90%"},    -- DarkKhaki
    {points = 0,     color = "a9a9a9", percent = "99%"}     -- DarkGray
}

-- Get the appropriate tier based on points
local function getAchievementTier(points)
    for _, tier in ipairs(tierData) do
        if points >= tier.points then
            return tier
        end
    end
    return tierData[#tierData]
end

-- Format numbers with commas
local function formatNumber(number)
    return tostring(number):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Create the popup frame
local popupFrame = CreateFrame("Frame", "CollectorStatsPopupFrame", UIParent, "BasicFrameTemplateWithInset")
popupFrame:SetSize(800, 600) -- Increased size for icon grid
popupFrame:SetPoint("CENTER")
popupFrame:SetFrameStrata("DIALOG")
popupFrame:EnableMouse(true)
popupFrame:SetMovable(true)
popupFrame:RegisterForDrag("LeftButton")
popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
popupFrame:Hide()

-- Title
local title = popupFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -12)
title:SetText("Collected Mounts")

-- Create ScrollFrame for Mount List
local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", popupFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, -35)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

-- Scroll Child (content frame)
local scrollChild = CreateFrame("Frame", "$parentScrollChild")
scrollChild:SetSize(750, 1) -- Width matches scrollFrame content area, height dynamic
scrollFrame:SetScrollChild(scrollChild)

-- Close Button (inherits from template)
local closeButton = CreateFrame("Button", "$parentCloseButton", popupFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -2, -2)
closeButton:SetScript("OnClick", function() popupFrame:Hide() end)

-- Constants for icon layout
local ICON_SIZE = 40
local ICON_SPACING = 5
local GROUP_SPACING = 20
local ICONS_PER_ROW = 15

-- Function to create an icon frame
local function CreateMountIcon(parent, index)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 
        ((index - 1) % ICONS_PER_ROW) * (ICON_SIZE + ICON_SPACING),
        -math.floor((index - 1) / ICONS_PER_ROW) * (ICON_SIZE + ICON_SPACING))
    
    -- Create texture for the icon
    local texture = icon:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    icon.texture = texture
    
    -- Add highlight texture
    local highlight = icon:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.3)
    
    return icon
end

-- Function to show/update the popup
local function ShowCollectorStatsPopup()
    -- Get mount data
    local mountIDs = C_MountJournal.GetMountIDs() or {}
    local mountsByType = {}
    local totalMounts = #mountIDs

    -- Initialize mount type categories with more detailed types
    local mountTypes = {
        [1] = "Ground Mounts",
        [2] = "Flying Mounts",
        [3] = "Aquatic Mounts",
        [4] = "Dragonriding Mounts",
        [5] = "Reputation Mounts",
        [6] = "Raid Mounts",
        [7] = "Dungeon Mounts",
        [8] = "PvP Mounts",
        [9] = "World Event Mounts",
        [10] = "Trading Post Mounts",
        [11] = "Store Mounts",
        [12] = "Achievement Mounts",
        [13] = "Profession Mounts",
        [14] = "Quest Mounts",
        [15] = "Other Mounts"
    }

    -- Sort mounts by type and name
    for i, mountID in ipairs(mountIDs) do
        local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mountIDAgain, mountType, mountSubType = C_MountJournal.GetMountInfoByID(mountID)
        if name and isCollected then
            -- Determine the specific category based on sourceType
            local category = mountType
            if sourceType == 1 then -- Achievement
                category = 12
            elseif sourceType == 2 then -- Quest
                category = 14
            elseif sourceType == 3 then -- Vendor
                category = 5
            elseif sourceType == 4 then -- Loot
                if mountSubType == 1 then -- Raid
                    category = 6
                elseif mountSubType == 2 then -- Dungeon
                    category = 7
                else
                    category = 15
                end
            elseif sourceType == 5 then -- Store
                category = 11
            elseif sourceType == 6 then -- World Event
                category = 9
            elseif sourceType == 7 then -- Trading Post
                category = 10
            elseif sourceType == 8 then -- Profession
                category = 13
            elseif sourceType == 9 then -- PvP
                category = 8
            end

            if not mountsByType[category] then
                mountsByType[category] = {}
            end
            table.insert(mountsByType[category], {name = name, icon = icon})
        end
    end

    -- Clear existing icons
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
    end

    -- Sort categories alphabetically
    local sortedCategories = {}
    for category, _ in pairs(mountTypes) do
        if mountsByType[category] and #mountsByType[category] > 0 then
            table.insert(sortedCategories, category)
        end
    end
    table.sort(sortedCategories, function(a, b) return mountTypes[a] < mountTypes[b] end)

    -- Create icon groups
    local currentY = 0
    local totalCollected = 0

    for _, category in ipairs(sortedCategories) do
        -- Sort mounts alphabetically within category
        table.sort(mountsByType[category], function(a, b) return a.name < b.name end)

        -- Create group frame
        local groupFrame = CreateFrame("Frame", nil, scrollChild)
        groupFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -currentY)
        groupFrame:SetSize(750, math.ceil(#mountsByType[category] / ICONS_PER_ROW) * (ICON_SIZE + ICON_SPACING))

        -- Create icons for this group
        for i, mountData in ipairs(mountsByType[category]) do
            local icon = CreateMountIcon(groupFrame, i)
            icon.texture:SetTexture(mountData.icon)
            icon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(mountData.name)
                GameTooltip:Show()
            end)
            icon:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
        end

        currentY = currentY + groupFrame:GetHeight() + GROUP_SPACING
        totalCollected = totalCollected + #mountsByType[category]
    end

    -- Update scroll frame content height
    scrollChild:SetHeight(currentY)

    -- Update Title with counts
    title:SetText(string.format("Collected Mounts (%d/%d)", totalCollected, totalMounts))

    popupFrame:Show()
end

-- Chat command handler
local function ChatCommandHandler(msg, editbox)
    ShowCollectorStatsPopup()
end

-- Register the slash command
SLASH_COLLECTORSTATS1 = "/collectorstats"
SLASH_COLLECTORSTATS2 = "/cstats"
SlashCmdList["COLLECTORSTATS"] = ChatCommandHandler

-- Add achievement points to the tooltip
local function updateTooltip(tooltip, points)
    if not tooltip or not points then return end
    local tier = getAchievementTier(points)
    tooltip:AddDoubleLine(
        "|cffffd700Achievement Points:|r",
        string.format("|c%s%s (top %s)|r", "ff" .. tier.color, formatNumber(points), tier.percent)
    )
end

-- Callback for processing unit tooltips
local function onTooltipShow(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    if UnitIsUnit(unit, "player") then
        updateTooltip(tooltip, GetTotalAchievementPoints())
    else
        local guid = UnitGUID(unit)
        if achievementCache[guid] then
            updateTooltip(tooltip, achievementCache[guid])
        elseif CanInspect(unit) and currentInspectGUID ~= guid then
            currentInspectGUID = guid
            ClearAchievementComparisonUnit()
            SetAchievementComparisonUnit(unit)
        end
    end
end

-- Handler for the ADDON_LOADED event
local function onAddonLoaded(arg1)
    if arg1 == "CollectorStats" then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltipShow)
        addonFrame:UnregisterEvent("ADDON_LOADED")
    end
end

-- Handler for the INSPECT_ACHIEVEMENT_READY event
local function onInspectAchievementReady()
    local points = GetComparisonAchievementPoints()
    if points and points > 0 and currentInspectGUID then
        achievementCache[currentInspectGUID] = points
        if GameTooltip:IsVisible() then
            local _, unit = GameTooltip:GetUnit()
            if unit and UnitGUID(unit) == currentInspectGUID then
                updateTooltip(GameTooltip, points)
            end
        end
        currentInspectGUID = nil
    end
end

-- Universal event handler
addonFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        onAddonLoaded(arg1)
    elseif event == "INSPECT_ACHIEVEMENT_READY" then
        onInspectAchievementReady()
    end
end) 