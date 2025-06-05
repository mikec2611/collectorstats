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

-- Create the popup frame (much larger to fit all mounts)
local popupFrame = CreateFrame("Frame", "CollectorStatsPopupFrame", UIParent, "BasicFrameTemplateWithInset")
popupFrame:SetSize(1500, 1000) -- Even larger to accommodate all mounts per expansion
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
title:SetText("Mount Collection")

-- Create ScrollFrame for Mount List
local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", popupFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, -35)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

-- Scroll Child (content frame)
local contentFrame = CreateFrame("Frame", "$parentScrollChild")
contentFrame:SetSize(1450, 1) -- Width matches scrollFrame content area, height dynamic
scrollFrame:SetScrollChild(contentFrame)

-- Close Button (inherits from template)
local closeButton = CreateFrame("Button", "$parentCloseButton", popupFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -2, -2)
closeButton:SetScript("OnClick", function() popupFrame:Hide() end)

-- Constants for icon layout
local ICON_SIZE = 28
local ICON_SPACING = 3
local GROUP_SPACING = 20  -- Reduced vertical spacing to fit all expansions
local ICONS_PER_ROW = 25  -- More icons per row for full-width layout
local HEADER_HEIGHT = 25
local HEADER_SPACING = 5

-- Function to create a category header
local function CreateCategoryHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    header:SetText(text)
    return header
end

-- Function to create an icon frame
local function CreateMountIcon(parent, index, isCollected)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 
        ((index - 1) % ICONS_PER_ROW) * (ICON_SIZE + ICON_SPACING) + 5,
        -math.floor((index - 1) / ICONS_PER_ROW) * (ICON_SIZE + ICON_SPACING) - HEADER_HEIGHT - 5)
    
    -- Create texture for the icon
    local texture = icon:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    icon.texture = texture
    
    -- Style for uncollected mounts
    if not isCollected then
        -- Desaturate uncollected mounts
        texture:SetDesaturated(true)
        texture:SetAlpha(0.4)
        
        -- Add dark overlay for uncollected
        local overlay = icon:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints()
        overlay:SetColorTexture(0, 0, 0, 0.6)
        icon.overlay = overlay
    end
    
    -- Add highlight texture
    local highlight = icon:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.3)
    
    return icon
end

-- Source type mapping for mount categorization
local sourceTypeData = {
    [0] = {name = "Unknown Source", order = 99},
    [1] = {name = "Achievement Mounts", order = 1},
    [2] = {name = "Quest Mounts", order = 2},
    [3] = {name = "Vendor Mounts", order = 3},
    [4] = {name = "Drop/Loot Mounts", order = 4},
    [5] = {name = "Store Mounts", order = 5},
    [6] = {name = "World Event Mounts", order = 6},
    [7] = {name = "Trading Post Mounts", order = 7},
    [8] = {name = "Profession Mounts", order = 8},
    [9] = {name = "PvP Mounts", order = 9},
    [10] = {name = "Discovery Mounts", order = 10}
}

-- Function to categorize mounts based on multiple data points
local function GetMountCategory(mountID, sourceType, mountType, mountSubType, mountName, isFactionSpecific)
    local name = mountName or ""
    
    -- Handle special cases and subcategorizations
    if sourceType == 4 then -- Drop/Loot mounts - try to subcategorize
        if name:find("Ashes of Al'ar") or name:find("Invincible") or name:find("Mimiron") or 
           name:find("Experiment 12-B") or name:find("Fiery Warhorse") or name:find("Midnight") or
           name:find("Smoldering Ember Wyrm") or name:find("Life-Binder's Handmaiden") or
           name:find("Blazing Drake") or name:find("Twilight Drake") then
            return {category = 41, name = "Raid Drop Mounts", order = 41}
        elseif name:find("Raven Lord") or name:find("White Hawkstrider") or name:find("Swift White Hawkstrider") or
               name:find("Blue Proto-Drake") or name:find("Bronze Drake") then
            return {category = 42, name = "Dungeon Drop Mounts", order = 42}
        else
            return {category = 4, name = "Other Drop Mounts", order = 4}
        end
    end
    
    -- PvP mounts with special handling
    if sourceType == 9 then
        if name:find("Vicious") then
            return {category = 91, name = "Vicious PvP Mounts", order = 91}
        elseif name:find("Gladiator") then
            return {category = 92, name = "Gladiator Mounts", order = 92}
        else
            return {category = 9, name = "Other PvP Mounts", order = 9}
        end
    end
    
    -- Faction-specific mounts
    if isFactionSpecific then
        if sourceType == 3 then -- Vendor
            return {category = 31, name = "Faction Vendor Mounts", order = 31}
        end
    end
    
    -- Special mount families based on names
    if name:find("Darkmoon") then
        return {category = 61, name = "Darkmoon Faire Mounts", order = 61}
    elseif name:find("Love is in the Air") or name:find("Brewfest") or name:find("Hallow") then
        return {category = 62, name = "Holiday Event Mounts", order = 62}
    elseif name:find("Trading Post") then
        return {category = 7, name = "Trading Post Mounts", order = 7}
    end
    
    -- Default to source type
    local sourceInfo = sourceTypeData[sourceType] or sourceTypeData[0]
    return {category = sourceType, name = sourceInfo.name, order = sourceInfo.order}
end

-- Function to show/update the popup
local function ShowCollectorStatsPopup()
    -- Try to get all mounts by using multiple filter combinations
    local hasFilterAPI = C_MountJournal.SetCollectedFilterSetting and C_MountJournal.GetCollectedFilterSetting
    local allMountData = {}
    local mountsByExpansion = {}
    local totalCollected = 0
    
    if hasFilterAPI then
        -- Save current filter settings
        local savedCollectedFilter = C_MountJournal.GetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED)
        local savedNotCollectedFilter = C_MountJournal.GetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED)
        
        -- Method 1: Get collected mounts
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED, true)
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED, false)
        local collectedIDs = C_MountJournal.GetMountIDs() or {}
        
        -- Method 2: Get uncollected mounts
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED, false)
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED, true)
        local uncollectedIDs = C_MountJournal.GetMountIDs() or {}
        
        -- Method 3: Try to get all mounts
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED, true)
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED, true)
        local allIDs = C_MountJournal.GetMountIDs() or {}
        
        -- Combine all mount IDs
        local seenIDs = {}
        local combinedIDs = {}
        
        for _, idList in ipairs({collectedIDs, uncollectedIDs, allIDs}) do
            for _, mountID in ipairs(idList) do
                if not seenIDs[mountID] then
                    seenIDs[mountID] = true
                    table.insert(combinedIDs, mountID)
                end
            end
        end
        
        -- Process all unique mount IDs
        for _, mountID in ipairs(combinedIDs) do
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mountIDAgain, mountType, mountSubType = C_MountJournal.GetMountInfoByID(mountID)
            if name then
                allMountData[mountID] = {
                    name = name, 
                    spellID = spellID,
                    icon = icon, 
                    mountID = mountID, 
                    sourceType = sourceType,
                    mountType = mountType,
                    mountSubType = mountSubType,
                    isFactionSpecific = isFactionSpecific,
                    isCollected = isCollected
                }
                if isCollected then
                    totalCollected = totalCollected + 1
                end
            end
        end
        
        -- Restore original filter settings
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED, savedCollectedFilter)
        C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED, savedNotCollectedFilter)
    else
        -- Fallback for older API
        local mountIDs = C_MountJournal.GetMountIDs() or {}
        for _, mountID in ipairs(mountIDs) do
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mountIDAgain, mountType, mountSubType = C_MountJournal.GetMountInfoByID(mountID)
            if name then
                allMountData[mountID] = {
                    name = name, 
                    spellID = spellID,
                    icon = icon, 
                    mountID = mountID, 
                    sourceType = sourceType,
                    mountType = mountType,
                    mountSubType = mountSubType,
                    isFactionSpecific = isFactionSpecific,
                    isCollected = isCollected
                }
                if isCollected then
                    totalCollected = totalCollected + 1
                end
            end
        end
    end
    
    -- Group mounts by category using game data
    local mountsByCategory = {}
    for mountID, mountData in pairs(allMountData) do
        local categoryInfo = GetMountCategory(mountID, mountData.sourceType, mountData.mountType, 
                                           mountData.mountSubType, mountData.name, mountData.isFactionSpecific)
        
        if not mountsByCategory[categoryInfo.category] then
            mountsByCategory[categoryInfo.category] = {
                collected = {}, 
                uncollected = {}, 
                name = categoryInfo.name,
                order = categoryInfo.order
            }
        end
        
        if mountData.isCollected then
            table.insert(mountsByCategory[categoryInfo.category].collected, mountData)
        else
            table.insert(mountsByCategory[categoryInfo.category].uncollected, mountData)
        end
    end
    
    local totalMounts = 0
    for _, data in pairs(allMountData) do
        totalMounts = totalMounts + 1
    end

    -- Clear existing children
    for _, child in ipairs({contentFrame:GetChildren()}) do
        child:Hide()
    end

    -- Sort categories by order
    local sortedCategories = {}
    for category, _ in pairs(mountsByCategory) do
        table.insert(sortedCategories, category)
    end
    table.sort(sortedCategories, function(a, b) return mountsByCategory[a].order < mountsByCategory[b].order end)

    -- Calculate layout - vertical scrolling layout
    local currentY = 0

    for _, category in ipairs(sortedCategories) do
        local categoryMounts = mountsByCategory[category]
        local collectedCount = #categoryMounts.collected
        local uncollectedCount = #categoryMounts.uncollected
        local totalInCategory = collectedCount + uncollectedCount
        
        if totalInCategory > 0 then
            -- Create group frame
            local groupFrame = CreateFrame("Frame", nil, contentFrame)
            -- Show ALL mounts for each category (no artificial limit)
            local iconsToShow = totalInCategory
            local rows = math.ceil(iconsToShow / ICONS_PER_ROW)
            local groupHeight = rows * (ICON_SIZE + ICON_SPACING) + HEADER_HEIGHT + 10
            
            groupFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -currentY)
            groupFrame:SetSize(contentFrame:GetWidth() - 20, groupHeight)
            
            -- Add a subtle background for visual separation
            local bg = groupFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", -3, 3)
            bg:SetPoint("BOTTOMRIGHT", 3, -3)
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)

            -- Create category header
            local header = CreateCategoryHeader(groupFrame, categoryMounts.name, -3)
            header:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            header:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 5, -3)
            
            -- Create count text
            local countText = groupFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            countText:SetPoint("TOPRIGHT", groupFrame, "TOPRIGHT", -8, -3)
            countText:SetText(string.format("(%d/%d)", collectedCount, totalInCategory))
            
            -- Color code the count based on completion percentage
            local completionPercent = collectedCount / totalInCategory
            if completionPercent == 1.0 then
                countText:SetTextColor(0.0, 1.0, 0.0) -- Green for 100%
            elseif completionPercent >= 0.8 then
                countText:SetTextColor(1.0, 1.0, 0.0) -- Yellow for 80%+
            else
                countText:SetTextColor(1.0, 0.4, 0.4) -- Red for less than 80%
            end

            -- Combine and sort mounts (collected first, then uncollected)
            local allMounts = {}
            for _, mount in ipairs(categoryMounts.collected) do
                mount.isCollected = true
                table.insert(allMounts, mount)
            end
            for _, mount in ipairs(categoryMounts.uncollected) do
                mount.isCollected = false
                table.insert(allMounts, mount)
            end
            
            -- Sort by name within each category
            table.sort(allMounts, function(a, b) 
                if a.isCollected == b.isCollected then
                    return a.name < b.name
                else
                    return a.isCollected and not b.isCollected
                end
            end)

            -- Create icons for this group (show all mounts)
            for i = 1, #allMounts do
                local mountData = allMounts[i]
                local icon = CreateMountIcon(groupFrame, i, mountData.isCollected)
                icon.texture:SetTexture(mountData.icon)
                
                -- Add click handler to open WoWHead page
                icon:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" and mountData.spellID then
                        -- Create WoWhead URL using spell ID (most reliable for mounts)
                        local wowheadURL = "https://www.wowhead.com/spell=" .. mountData.spellID
                        
                        -- Try to open URL in browser using WoW's built-in methods
                        local opened = false
                        
                        -- Method 1: Try the secure browser frame
                        if C_Web and C_Web.LaunchURL then
                            C_Web.LaunchURL(wowheadURL)
                            opened = true
                            print("|cff00ff00CollectorStats:|r Opening WoWHead page for " .. mountData.name)
                        -- Method 2: Try BrowserFrame if available
                        elseif BrowserFrame then
                            if BrowserFrame.LoadURL then
                                BrowserFrame:LoadURL(wowheadURL)
                                opened = true
                                print("|cff00ff00CollectorStats:|r Opening WoWHead page for " .. mountData.name)
                            elseif BrowserFrame.OpenURL then
                                BrowserFrame:OpenURL(wowheadURL)
                                opened = true
                                print("|cff00ff00CollectorStats:|r Opening WoWHead page for " .. mountData.name)
                            end
                        end
                        
                        -- Fallback: copy to clipboard
                        if not opened then
                            if C_System and C_System.SetClipboard then
                                C_System.SetClipboard(wowheadURL)
                                print("|cff00ff00CollectorStats:|r Browser not available. WoWHead URL copied to clipboard: " .. wowheadURL)
                            else
                                print("|cff00ff00CollectorStats:|r WoWHead URL: " .. wowheadURL)
                            end
                        end
                    end
                end)
                
                icon:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(mountData.name)
                    if not mountData.isCollected then
                        GameTooltip:AddLine("|cffff6666Not Collected|r")
                        -- Add source information for uncollected mounts
                        local sourceText = ""
                        if mountData.sourceType == 1 then
                            sourceText = "|cffffff00Source: Achievement|r"
                        elseif mountData.sourceType == 2 then
                            sourceText = "|cffffff00Source: Quest|r"
                        elseif mountData.sourceType == 3 then
                            sourceText = "|cffffff00Source: Vendor|r"
                        elseif mountData.sourceType == 4 then
                            sourceText = "|cffffff00Source: Drop|r"
                        elseif mountData.sourceType == 5 then
                            sourceText = "|cffffff00Source: Store|r"
                        elseif mountData.sourceType == 6 then
                            sourceText = "|cffffff00Source: World Event|r"
                        elseif mountData.sourceType == 7 then
                            sourceText = "|cffffff00Source: Trading Post|r"
                        elseif mountData.sourceType == 8 then
                            sourceText = "|cffffff00Source: Profession|r"
                        elseif mountData.sourceType == 9 then
                            sourceText = "|cffffff00Source: PvP|r"
                        end
                        if sourceText ~= "" then
                            GameTooltip:AddLine(sourceText)
                        end
                    end
                    -- Add click instruction to tooltip
                    GameTooltip:AddLine("|cff888888Left-click: Open WoWHead page|r")
                    GameTooltip:Show()
                end)
                icon:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
            end

            -- Move to next category (vertical layout)
            currentY = currentY + groupFrame:GetHeight() + GROUP_SPACING
        end
    end
    
    -- Update scroll frame content height
    contentFrame:SetHeight(currentY)

    -- Update Title with counts
    title:SetText(string.format("Mount Collection (%d/%d)", totalCollected, totalMounts))

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