-- Create main addon frame and register events
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

-- Cache for inspected players
local currentGUID = nil
local cache = {}

-- Combined tier data for colors and percentiles (sorted descending)
local tiers = {
    {50000, "ffd700", "0.01%"}, {48000, "ff8c00", "0.1%"}, {43000, "ff4500", "0.5%"},
    {39600, "ff0000", "1%"}, {36000, "ff1493", "2%"}, {34000, "c71585", "3%"},
    {31000, "9932cc", "5%"}, {27000, "6495ed", "10%"}, {22000, "4169e1", "20%"},
    {19000, "1e90ff", "30%"}, {17500, "00bfff", "40%"}, {15000, "20b2aa", "50%"},
    {13000, "3cb371", "60%"}, {11000, "9acd32", "70%"}, {8000, "6b8e23", "80%"},
    {5000, "bdb76b", "90%"}, {0, "a9a9a9", "99%"}
}

-- Get the appropriate tier based on points
local function getTier(points)
    for _, tier in ipairs(tiers) do
        if points >= tier[1] then return tier end
    end
    return tiers[#tiers]
end

-- Format numbers with commas
local function formatNumber(number)
    return tostring(number):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Add achievement points to the tooltip
local function addTooltip(tooltip, points)
    if not tooltip or not points then return end
    local tier = getTier(points)
    local formatted = tostring(points):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    tooltip:AddDoubleLine(
        "|cffffd700Achievement Points:|r",
        string.format("|cff%s%s (top %s)|r", tier[2], formatted, tier[3])
    )
end

-- Callback for processing unit tooltips
local function onTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    
    if UnitIsUnit(unit, "player") then
        addTooltip(tooltip, GetTotalAchievementPoints())
    else
        local guid = UnitGUID(unit)
        if cache[guid] then
            addTooltip(tooltip, cache[guid])
        elseif CanInspect(unit) and currentGUID ~= guid then
            currentGUID = guid
            ClearAchievementComparisonUnit()
            SetAchievementComparisonUnit(unit)
        end
    end
end

-- Handler for the ADDON_LOADED event
local function onAddonLoaded(arg1)
    if arg1 == "CollectorStats" then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltip)
        frame:UnregisterEvent("ADDON_LOADED")
    end
end

-- Handler for the INSPECT_ACHIEVEMENT_READY event
local function onInspectAchievementReady()
    local points = GetComparisonAchievementPoints()
    if points and points > 0 and currentGUID then
        cache[currentGUID] = points
        if GameTooltip:IsVisible() then
            local _, unit = GameTooltip:GetUnit()
            if unit and UnitGUID(unit) == currentGUID then
                addTooltip(GameTooltip, points)
                GameTooltip:Show() -- Force tooltip refresh
            end
        end
        currentGUID = nil
    end
end

-- Universal event handler
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        onAddonLoaded(arg1)
    elseif event == "INSPECT_ACHIEVEMENT_READY" then
        onInspectAchievementReady()
    end
end) 