local AVAILABLE_PARAGON_CACHES = {}


local function CreateBadge(point)
    local badge = CreateFrame("Frame", "MyParagonsBadge", AchievementMicroButton)
    badge:SetSize(20, 20)
    badge:SetFrameStrata("MEDIUM")
    badge:SetFrameLevel(AchievementMicroButton:GetFrameLevel() + 10)
    badge:SetPoint(point, AchievementMicroButton, "TOP", 0, 6)

    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") 
    badge.bg:SetAllPoints(badge)
    badge.bg:SetVertexColor(0, 0, 0)

    badge.border = badge:CreateTexture(nil, "OVERLAY")
    badge.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    badge.border:SetSize(42, 42)
    badge.border:SetPoint("CENTER", badge, "CENTER", 8, -8)
    badge.border:SetVertexColor(1, 0.8, 0, 0.6)

    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.text:SetText("*")

    return badge
end

local f = CreateFrame("Frame")

f.badgeParagon = CreateBadge("TOP")

local function UpdateParagonBadge()
    local count =  #AVAILABLE_PARAGON_CACHES

    if count and count > 0 then
        f.badgeParagon.text:SetText(tostring(count))
        f.badgeParagon:Show()
    else
        f.badgeParagon:Hide()
    end
end



local function GetAvailableParagonCaches()
    AVAILABLE_PARAGON_CACHES = {}

    local factionQueue = {}
    for i = 1, C_Reputation.GetNumFactions() do
        local _, _, _, _, _, _, _, _, isHeader, _, hasRep, factionID = C_CreatureInfo.GetFactionInfo(i)
        if factionID and (not isHeader or hasRep) then
            table.insert(factionQueue, { id = factionID, isMajor = false })
        end
    end

    local majorFactionIDs = C_MajorFactions.GetMajorFactionIDs()
    for _, factionID in ipairs(majorFactionIDs) do
        table.insert(factionQueue, { id = factionID, isMajor = true })
    end

    local function ScanParagonBatch(startIndex)
        local batchSize = 2 -- Number of factions per frame
        local endIndex = math.min(startIndex + batchSize - 1, #factionQueue)

        for i = startIndex, endIndex do
            local item = factionQueue[i]
            local factionID = item.id

            if C_Reputation.IsFactionParagon(factionID) then
                local _, _, rewardQuestID, hasRewardPending = C_Reputation.GetFactionParagonInfo(factionID)
                
                if hasRewardPending then
                    local name = ""
                    if item.isMajor then
                        local data = C_MajorFactions.GetMajorFactionData(factionID)
                        name = data and data.name or "Unknown Major Faction"
                    else
                        name = GetFactionInfoByID(factionID) or "Unknown Faction"
                    end

                    table.insert(AVAILABLE_PARAGON_CACHES, {
                        id = factionID,
                        name = name,
                        questID = rewardQuestID
                    })
                end
            end
        end

        if endIndex < #factionQueue then
            C_Timer.After(0.01, function() ScanParagonBatch(endIndex + 1) end)
        else
            UpdateParagonBadge()
        end
    end

    if #factionQueue > 0 then
        ScanParagonBatch(1)
    end
end

local function CreateTooltipText()
    local detailsText = ""

    for _, cache in ipairs(AVAILABLE_PARAGON_CACHES) do
        detailsText = detailsText .. "  " .. cache.name .. "\n"
    end

    if #detailsText <= 0 then
         detailsText = "  None!"
    end

    local headerText = "|cFFFFD100Paragon caches:|r"
    return  "\n" .. headerText .. "\n" .. detailsText
end


f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_TURNED_IN")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        GetAvailableParagonCaches()
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        local questID = ...

        for i = #AVAILABLE_PARAGON_CACHES, 1, -1 do
            if AVAILABLE_PARAGON_CACHES[i].guestID == questID then
                table.remove(AVAILABLE_PARAGON_CACHES, i)
            end
        end

        UpdateParagonBadge()
    end
end)

AchievementMicroButton:HookScript("OnEnter", function(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:AddLine(CreateTooltipText(), 1, 1, 1, true)
        GameTooltip:Show()
    end
end)
