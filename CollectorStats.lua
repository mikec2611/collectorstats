-- Create main addon frame and register events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

-- Cache for achievement points
local achievementCache = {}

-- Function to get color based on achievement points
local function GetAchievementColor(points)
    if points >= 50000 then return "ffd700"      -- golden
    elseif points >= 45000 then return "ffb6c1"  -- light pink
    elseif points >= 40000 then return "ff69b4"  -- dark pink
    elseif points >= 35000 then return "a020f0"  -- purple
    elseif points >= 30000 then return "800080"  -- dark purple
    elseif points >= 25000 then return "0000ff"  -- blue
    elseif points >= 20000 then return "00008b"  -- dark blue
    elseif points >= 15000 then return "90ee90"  -- light green
    elseif points >= 10000 then return "008000"  -- green
    elseif points >= 5000 then return "006400"   -- dark green
    else return "808080" end                     -- gray
end

-- Function to safely add achievement points to tooltip
local function AddAchievementToTooltip(tooltip, points)
    if not tooltip or not points then return end
    
    local color = GetAchievementColor(points)
    tooltip:AddDoubleLine(
        "|cffffd700Achievement Points|r",
        string.format("|c%s%d|r", "ff" .. color, points),
        1, 1, 1,  -- Left text RGB (not used due to color codes)
        1, 1, 1   -- Right text RGB (not used due to color codes)
    )
    tooltip:Show()  -- Refresh the tooltip
end

-- Initialize addon
local function OnEvent(self, event, addon)
    if event == "ADDON_LOADED" and addon == "CollectorStats" then
        -- Initialize saved variables if needed
        CollectorStatsDB = CollectorStatsDB or {}
        
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
                        AddAchievementToTooltip(tooltip, achievementPoints)
                    end
                else
                    -- For other players, check cache first
                    if achievementCache[guid] then
                        achievementPoints = achievementCache[guid]
                        AddAchievementToTooltip(tooltip, achievementPoints)
                    else
                        -- Request inspection if not in cache
                        if CanInspect(unit) then
                            tooltip:AddDoubleLine(
                                "|cffffd700Achievement Points|r",
                                "|cffffd700...Loading...|r",
                                1, 1, 1,
                                1, 1, 1
                            )
                            tooltip:Show()
                            
                            ClearAchievementComparisonUnit()
                            SetAchievementComparisonUnit(unit)
                            -- Cache the result when it's ready
                            C_Timer.After(0.5, function()
                                local points = GetComparisonAchievementPoints()
                                if points and points > 0 then
                                    achievementCache[guid] = points
                                end
                            end)
                        end
                    end
                end
            end
        end)
        
        -- Clear cache periodically (every 5 minutes)
        C_Timer.NewTicker(300, function() achievementCache = {} end)
        
        -- Unregister the ADDON_LOADED event as we don't need it anymore
        f:UnregisterEvent("ADDON_LOADED")
    end
end

f:SetScript("OnEvent", OnEvent) 