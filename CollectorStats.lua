-- Create main addon frame and register events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

-- Cache for achievement points
local achievementCache = {}
local currentInspectGUID = nil
local pendingTooltips = {}
local tooltipUpdateQueued = false
local percentileData = {}

-- Create custom font objects
local function CreateFontObjects()
    local labelFont = CreateFont("CollectorStatsLabelFont")
    labelFont:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    labelFont:SetTextColor(1, 0.84, 0) -- Gold color

    local valueFont = CreateFont("CollectorStatsValueFont")
    valueFont:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
end

-- Function to get color based on achievement points
local function GetAchievementColor(points)
    -- Tier 7 (Gold) - Top 0.01%
    if points >= 50000 then return "ffd700"      -- bright gold

    -- Tier 6 (Red) - Top 0.1-0.5%
    elseif points >= 48000 then return "ff3030"  -- bright red
    elseif points >= 43000 then return "ff0000"  -- pure red

    -- Tier 5 (Orange) - Top 1-2%
    elseif points >= 39600 then return "ffa500"  -- bright orange
    elseif points >= 36000 then return "ff8c00"  -- dark orange

    -- Tier 4 (Pink) - Top 3-5%
    elseif points >= 34000 then return "ff69b4"  -- hot pink
    elseif points >= 31000 then return "ff1493"  -- deep pink

    -- Tier 3 (Purple) - Top 10-20%
    elseif points >= 27000 then return "da70d6"  -- orchid
    elseif points >= 22000 then return "9932cc"  -- dark orchid

    -- Tier 2 (Blue) - Top 30-50%
    elseif points >= 19000 then return "00bfff"  -- deep sky blue
    elseif points >= 17500 then return "1e90ff"  -- dodger blue
    elseif points >= 15000 then return "4169e1"  -- royal blue

    -- Tier 1 (Green) - Top 60-90%
    elseif points >= 13000 then return "98fb98"  -- pale green
    elseif points >= 11000 then return "32cd32"  -- lime green
    elseif points >= 8000 then return "228b22"   -- forest green
    elseif points >= 5000 then return "006400"   -- dark green

    -- Tier 0 (Gray) - Bottom 10%
    else return "bebebe" end                     -- bright gray
end

-- Function to format numbers with thousand separators
local function FormatNumber(number)
    local formatted = tostring(number)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Function to load percentile data
local function LoadPercentileData()
    local data = {
        {low = 0, high = 4999, percent = "100%"},
        {low = 5000, high = 7999, percent = "90%"},
        {low = 8000, high = 10999, percent = "80%"},
        {low = 11000, high = 12999, percent = "70%"},
        {low = 13000, high = 14999, percent = "60%"},
        {low = 15000, high = 17499, percent = "50%"},
        {low = 17500, high = 18999, percent = "40%"},
        {low = 19000, high = 21999, percent = "30%"},
        {low = 22000, high = 26999, percent = "20%"},
        {low = 27000, high = 30999, percent = "10%"},
        {low = 31000, high = 33999, percent = "5%"},
        {low = 34000, high = 35999, percent = "3%"},
        {low = 36000, high = 39599, percent = "2%"},
        {low = 39600, high = 43000, percent = "1%"},
        {low = 43000, high = 47999, percent = "0.5%"},
        {low = 48000, high = 49999, percent = "0.1%"},
        {low = 50000, high = 100000, percent = "0.01%"}
    }
    return data
end

-- Function to get percentile for points
local function GetPercentile(points)
    if not percentileData or #percentileData == 0 then
        percentileData = LoadPercentileData()
    end
    
    for _, bracket in ipairs(percentileData) do
        if points >= bracket.low and points <= bracket.high then
            return bracket.percent
        end
    end
    return "100%"  -- Default fallback
end

-- Function to safely add achievement points to tooltip
local function AddAchievementToTooltip(tooltip, points, isSelf)
    if not tooltip or not points or tooltipUpdateQueued then return end
    
    tooltipUpdateQueued = true
    
    local function updateTooltip()
        if tooltip:IsVisible() then
            local color = GetAchievementColor(points)
            local percentile = GetPercentile(points)
            
            -- Add our lines with increased font size
            local line = tooltip:AddDoubleLine(
                "|cffffd700Achievement Points|r",
                string.format("|c%s%s (top %s of players)|r", "ff" .. color, FormatNumber(points), percentile)
            )
            
            -- Get the last line (the one we just added) and increase its font size
            local numLines = tooltip:NumLines()
            local leftText = _G[tooltip:GetName().."TextLeft"..numLines]
            local rightText = _G[tooltip:GetName().."TextRight"..numLines]
            if leftText and rightText then
                leftText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
                rightText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            end
            
            tooltip:Show()  -- Refresh the tooltip
        end
        tooltipUpdateQueued = false
    end

    if isSelf then
        updateTooltip()
    else
        C_Timer.After(0.25, updateTooltip)
    end
end

-- Initialize addon
local function OnEvent(self, event, addon)
    if event == "ADDON_LOADED" and addon == "CollectorStats" then
        -- Initialize saved variables if needed
        CollectorStatsDB = CollectorStatsDB or {}
        CreateFontObjects()
        
        -- Hook the tooltip using TooltipDataProcessor
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local _, unit = tooltip:GetUnit()
            if not unit then return end
            
            -- Check if it's a player
            if UnitIsPlayer(unit) then
                local achievementPoints
                local guid = UnitGUID(unit)
                
                -- If it's the player, use direct method
                if UnitIsUnit(unit, "player") then
                    achievementPoints = GetTotalAchievementPoints()
                    if achievementPoints and achievementPoints > 0 then
                        AddAchievementToTooltip(tooltip, achievementPoints, true)
                    end
                else
                    -- For other players, check cache first
                    if achievementCache[guid] then
                        achievementPoints = achievementCache[guid]
                        AddAchievementToTooltip(tooltip, achievementPoints, false)
                    else
                        -- Request inspection if not in cache
                        if CanInspect(unit) and currentInspectGUID ~= guid then
                            currentInspectGUID = guid
                            pendingTooltips[guid] = tooltip
                            ClearAchievementComparisonUnit()
                            SetAchievementComparisonUnit(unit)
                        end
                    end
                end
            end
        end)
        
        -- Clear cache periodically (every 5 minutes)
        C_Timer.NewTicker(300, function() achievementCache = {} end)
        
        -- Unregister the ADDON_LOADED event as we don't need it anymore
        f:UnregisterEvent("ADDON_LOADED")
    elseif event == "INSPECT_ACHIEVEMENT_READY" then
        local points = GetComparisonAchievementPoints()
        if points and points > 0 and currentInspectGUID then
            achievementCache[currentInspectGUID] = points
            -- Update tooltip if it's still visible
            if GameTooltip:IsVisible() then
                local _, unit = GameTooltip:GetUnit()
                if unit and UnitGUID(unit) == currentInspectGUID then
                    AddAchievementToTooltip(GameTooltip, points, false)
                end
            end
            pendingTooltips[currentInspectGUID] = nil
            currentInspectGUID = nil
        end
    end
end

f:SetScript("OnEvent", OnEvent) 