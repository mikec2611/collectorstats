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