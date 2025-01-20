-- Create main addon frame and register events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

-- Cache for achievement points
local achievementCache = {}
local currentInspectGUID = nil
local pendingTooltips = {}
local tooltipUpdateQueued = false

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
    if points >= 50000 then return "ffd700"      -- golden
    elseif points >= 45000 then return "ffc0cb"  -- light pink
    elseif points >= 40000 then return "ff69b4"  -- hot pink
    elseif points >= 35000 then return "da70d6"  -- orchid (lighter purple)
    elseif points >= 30000 then return "9370db"  -- medium purple
    elseif points >= 25000 then return "1e90ff"  -- dodger blue
    elseif points >= 20000 then return "4169e1"  -- royal blue
    elseif points >= 15000 then return "98fb98"  -- pale green
    elseif points >= 10000 then return "32cd32"  -- lime green
    elseif points >= 5000 then return "228b22"   -- forest green
    else return "a9a9a9" end                     -- dark gray
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

-- Function to safely add achievement points to tooltip
local function AddAchievementToTooltip(tooltip, points, isSelf)
    if not tooltip or not points or tooltipUpdateQueued then return end
    
    tooltipUpdateQueued = true
    
    local function updateTooltip()
        if tooltip:IsVisible() then
            local color = GetAchievementColor(points)
            
            -- Add our lines with increased font size
            local line = tooltip:AddDoubleLine(
                "|cffffd700Achievement Points|r",
                string.format("|c%s%s|r", "ff" .. color, FormatNumber(points))
            )
            
            -- Get the last line (the one we just added) and increase its font size
            local numLines = tooltip:NumLines()
            local leftText = _G[tooltip:GetName().."TextLeft"..numLines]
            local rightText = _G[tooltip:GetName().."TextRight"..numLines]
            if leftText and rightText then
                leftText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
                rightText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
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