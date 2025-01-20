-- Create main addon frame and register events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

-- Cache for inspected players
local currentInspectGUID = nil
local achievementCache = {}

-- Combined tier data for colors and percentiles
local tierData = {
    {points = 50000, color = "ffd700", percent = "0.01%"},  -- Gold
    {points = 48000, color = "ff3030", percent = "0.1%"},   -- Bright Red
    {points = 43000, color = "ff0000", percent = "0.5%"},   -- Pure Red
    {points = 39600, color = "ffa500", percent = "1%"},     -- Bright Orange
    {points = 36000, color = "ff8c00", percent = "2%"},     -- Dark Orange
    {points = 34000, color = "ff69b4", percent = "3%"},     -- Hot Pink
    {points = 31000, color = "ff1493", percent = "5%"},     -- Deep Pink
    {points = 27000, color = "da70d6", percent = "10%"},    -- Orchid
    {points = 22000, color = "9932cc", percent = "20%"},    -- Dark Orchid
    {points = 19000, color = "00bfff", percent = "30%"},    -- Deep Sky Blue
    {points = 17500, color = "1e90ff", percent = "40%"},    -- Dodger Blue
    {points = 15000, color = "0080ff", percent = "50%"},    -- Royal Blue
    {points = 13000, color = "98fb98", percent = "60%"},    -- Pale Green
    {points = 11000, color = "32cd32", percent = "70%"},    -- Lime Green
    {points = 8000, color = "228b22", percent = "80%"},     -- Forest Green
    {points = 5000, color = "207520", percent = "90%"},     -- Medium Green
    {points = 0, color = "bebebe", percent = "99%"}         -- Gray
}

-- Get color and percentile for achievement points
local function GetAchievementInfo(points)
    for _, tier in ipairs(tierData) do
        if points >= tier.points then
            return tier.color, tier.percent
        end
    end
    return tierData[#tierData].color, tierData[#tierData].percent
end

-- Format numbers with commas
local function FormatNumber(number)
    return tostring(number):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Add achievement points to tooltip
local function UpdateTooltip(tooltip, points)
    if not tooltip or not points then return end
    
    local color, percentile = GetAchievementInfo(points)
    tooltip:AddDoubleLine(
        "|cffffd700Achievement Points|r",
        string.format("|c%s%s (top %s)|r", "ff" .. color, FormatNumber(points), percentile)
    )
    tooltip:Show()
end

-- Event handler
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "CollectorStats" then
        -- Hook tooltip
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local _, unit = tooltip:GetUnit()
            if not unit or not UnitIsPlayer(unit) then return end
            
            if UnitIsUnit(unit, "player") then
                UpdateTooltip(tooltip, GetTotalAchievementPoints())
            else
                local guid = UnitGUID(unit)
                if achievementCache[guid] then
                    UpdateTooltip(tooltip, achievementCache[guid])
                elseif CanInspect(unit) and currentInspectGUID ~= guid then
                    currentInspectGUID = guid
                    ClearAchievementComparisonUnit()
                    SetAchievementComparisonUnit(unit)
                end
            end
        end)
        
        f:UnregisterEvent("ADDON_LOADED")
    elseif event == "INSPECT_ACHIEVEMENT_READY" then
        local points = GetComparisonAchievementPoints()
        if points and points > 0 and currentInspectGUID then
            achievementCache[currentInspectGUID] = points
            if GameTooltip:IsVisible() then
                local _, unit = GameTooltip:GetUnit()
                if unit and UnitGUID(unit) == currentInspectGUID then
                    UpdateTooltip(GameTooltip, points)
                end
            end
            currentInspectGUID = nil
        end
    end
end) 