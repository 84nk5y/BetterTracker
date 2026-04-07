local _, _A = ...


ParagonTrackerMixin = {}

function ParagonTrackerMixin:Setup()
    self.availableParagonCaches = {}
    self.scanPending = false
    self.updatePending = false

    self.badgeParagon = self:CreateBadge("TOP")

    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("UPDATE_FACTION")
    self:RegisterEvent("FACTION_STANDING_CHANGED")

    self:SetScript("OnEvent", self.OnEvent)
end

function ParagonTrackerMixin:CreateBadge(point)
    local badge = CreateFrame("Frame", nil, AchievementMicroButton)
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

    badge:Hide()

    return badge
end

function ParagonTrackerMixin:UpdateParagonBadge()
    local count = 0
    for _ in pairs(self.availableParagonCaches) do
        count = count + 1
    end

    if count > 0 then
        self.badgeParagon.text:SetText(count)
        self.badgeParagon:Show()
    else
        self.badgeParagon:Hide()
    end
end

function ParagonTrackerMixin:OnEvent(event, ...)
    if event == "UPDATE_FACTION" or event == "FACTION_STANDING_CHANGED" then
        if not self.scanPending then
            self.scanPending = true

            C_Timer.After(0.1, function() self:GetAvailableParagonCaches() end)
        end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        for factionID, cache in pairs(self.availableParagonCaches) do
            if questID == cache.questID then
                self.availableParagonCaches[factionID] = nil

                if not self.updatePending then
                    self.updatePending = true
                    C_Timer.After(0.5, function()
                        self.updatePending = false
                        self:UpdateParagonBadge()
                    end)
                end
                return
            end
        end
    end
end

function ParagonTrackerMixin:GetAvailableParagonCaches()
    self.availableParagonCaches = {}

    local factionList = {}
    for factionID in pairs(_A.ParagonFactions) do
        table.insert(factionList, factionID)
    end

    local function ScanParagonBatch(startIndex)
        local batchSize = 6 -- Number of factions per frame
        local endIndex = math.min(startIndex + batchSize - 1, #factionList)

        for i = startIndex, endIndex do
            local factionID = factionList[i]
            local factionName = _A.ParagonFactions[factionID]

            if C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
                local _, _, rewardQuestID, hasRewardPending = C_Reputation.GetFactionParagonInfo(factionID)

                if hasRewardPending then
                    self.availableParagonCaches[factionID] = {
                        name = factionName,
                        questID = rewardQuestID
                    }
                end
            end
        end

        if endIndex < #factionList then
            C_Timer.After(0.1, function() ScanParagonBatch(endIndex + 1) end)
        else
            self:UpdateParagonBadge()

            self.scanPending = false
        end
    end

    if #factionList > 0 then
        ScanParagonBatch(1)
    else
        self.scanPending = false
    end
end

function ParagonTrackerMixin:CreateTooltipText()
    local lines = {}
    for _, cache in pairs(self.availableParagonCaches) do
        table.insert(lines, "  "..cache.name)
    end

    local detailsText = #lines > 0 and table.concat(lines, "\n") or "  None!"
    local headerText = "|cFFFFD100Paragon caches:|r"

    return "\n"..headerText.."\n"..detailsText
end

local ParagonTracker = CreateFrame("Frame")
Mixin(ParagonTracker, ParagonTrackerMixin)
ParagonTracker:Setup()


AchievementMicroButton:HookScript("OnEnter", function(self)
    if GameTooltip:IsOwned(self) then
        if next(ParagonTracker.availableParagonCaches) then
            GameTooltip:AddLine(ParagonTracker:CreateTooltipText(), 1, 1, 1, true)
            GameTooltip:Show()
        end
    end
end)