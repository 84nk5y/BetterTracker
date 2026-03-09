local addonName, addonTable = ...


local SCAN_RATE = 5 * 60


BT_SavedVars = BT_SavedVars or { WorldQuestTracker= { MinGoldReward = 500 * 10000 } }
local SavedVars = nil


local WorldQuestTrackerMixin = {}

function WorldQuestTrackerMixin:Setup()
    self.worldQuestsToScan = {}
    self.updatingUI = false

    self.worldQuestBadge = self:CreateBadge("TOP")

    self:RegisterEvent("VARIABLES_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("QUEST_REMOVED")

    self:SetScript("OnEvent", self.OnEvent)
end

function WorldQuestTrackerMixin:CreateBadge(point)
    local badge = CreateFrame("Frame", nil, QuestLogMicroButton)
    badge:SetSize(20, 20)
    badge:SetFrameStrata("MEDIUM")
    badge:SetFrameLevel(QuestLogMicroButton:GetFrameLevel() + 10)
    badge:SetPoint(point, QuestLogMicroButton, "TOP", 0, 6)

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
    badge.text:SetText("-")

    return badge
end

function WorldQuestTrackerMixin:UpdateUI()
    local count = addonTable.FoundWorldQuests:GetCount()
    if count > 0 then
        self.worldQuestBadge.text:SetText(count)
        self.worldQuestBadge:Show()
    else
        self.worldQuestBadge:Hide()
    end

    if QuestMapFrame and QuestMapFrame.WorldQuestsPanel and QuestMapFrame.WorldQuestsPanel:IsShown() then
        QuestMapFrame.WorldQuestsPanel:RefreshList()
    end

    self.updatingUI = false
end

function WorldQuestTrackerMixin:GetRewardsForQuest(questID)
    local rewards = { gold = 0, reputation = false}

    local goldReward = GetQuestLogRewardMoney(questID) or 0
    if goldReward > 0 then
        rewards.gold = rewards.gold + goldReward
    end

    local currencies = C_QuestLog.GetQuestRewardCurrencies(questID) or {}
    for _, currency in ipairs(currencies) do
        if currency.currencyID == 0 or currency.name == "Gold" then
            rewards.gold = rewards.gold + (currency.totalRewardAmount or 0)
        end

        -- Blizzard's internal check: Does this currency ID grant a faction?
        if C_CurrencyInfo.GetFactionGrantedByCurrency(currency.currencyID) then
            rewards.reputation = true
        end
    end

    rewards.gold = math.floor(rewards.gold / 10000) * 10000

    -- 1. Check for the First-Time Completion Bonus (Warband Rep)
    -- This is the API you found in the Blizzard source. It checks if the
    -- player gets that large chunk of 'blue' account-wide reputation.
    if C_QuestLog.QuestContainsFirstTimeRepBonusForPlayer(questID) then
        rewards.reputation = true
    end

    -- 3. Check Standard Rewards (Fallback)
    -- This handles the basic +75 or +125 rep lines.
    local numFactions = GetNumQuestLogRewardFactions(questID) or 0
    if numFactions > 0 then
        print("GetNumQuestLogRewardFactions > 0")
        rewards.reputation = true
    end

    return rewards
end

function WorldQuestTrackerMixin:ProcessQuest(questID)
    if not questID then return end

    local mapID = C_TaskQuest.GetQuestZoneID(questID)

    if not addonTable.WorldQuestsZones[mapID] then return end

    if C_QuestLog.IsComplete(questID) or not C_TaskQuest.IsActive(questID)  then
        addonTable.FoundWorldQuests:RemoveQuest(questID)
        return
    end

    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

    if isWorldQuest then
        local questName = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
        local questTagInfo = C_QuestLog.GetQuestTagInfo(questID)
        local mapName = mapID and C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name or "Unknown Zone"
        local rewards = self:GetRewardsForQuest(questID)
        local minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0

        if rewards.gold > SavedVars.MinGoldReward or rewards.reputation then
            local quest = {
                ID = questID,
                name = questName,
                amount = rewards.gold,
                repReward = rewards.reputation,
                tagInfo = questTagInfo,
                minutesLeft = minutesLeft,
                zone = mapName
            }
            addonTable.FoundWorldQuests:AddQuest(questID, quest)
        end
    end

    if not self.updatingUI then
        self.updatingUI = true
        C_Timer.After(1, function() self:UpdateUI() end)
    end
end

function WorldQuestTrackerMixin:RefreshQuestRewards()
    local mapList = {}
    for mapID in pairs(addonTable.WorldQuestsZones) do
        table.insert(mapList, mapID)
    end

    self.worldQuestsToScan = {}

    -- Staggered scanning to reduce FPS impact
    local function ScanMapBatch(index)
        local mapID = mapList[index]
        local quests = C_TaskQuest.GetQuestsOnMap(mapID)

        if quests then
            for _, qInfo in ipairs(quests) do
                local questID = qInfo.questId or qInfo.questID

                if questID then
                    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

                    if isWorldQuest and not self.worldQuestsToScan[questID] then
                        -- try to force server to provide quest data
                        C_TaskQuest.GetQuestZoneID(questID)
                        C_TaskQuest.RequestPreloadRewardData(questID)
                        C_QuestLog.RequestLoadQuestByID(questID)

                        self.worldQuestsToScan[questID] = mapID
                    end
                end
            end
        end

        if index < #mapList then
            C_Timer.After(0.1, function() ScanMapBatch(index + 1) end)
        else
            C_Timer.After(2, function() self:RefreshQuests() end)
        end
    end

    if #mapList > 0 then
        ScanMapBatch(1)
    end
end

function WorldQuestTrackerMixin:RefreshQuests()
    for questID in pairs(self.worldQuestsToScan) do
        if not addonTable.FoundWorldQuests:GetQuest(questID) then
            self:ProcessQuest(questID)
        end
    end

    -- queue the next quest refresh cycle
    C_Timer.After(SCAN_RATE, function() self:RefreshQuestRewards() end)
end

function WorldQuestTrackerMixin:ResetQuests()
    self.worldQuestsToScan = {}

    addonTable.FoundWorldQuests:Clear()

    self:RefreshQuestRewards()
end

function WorldQuestTrackerMixin:OnEvent(event, ...)
    if event == "VARIABLES_LOADED" then
        SavedVars = BT_SavedVars["WorldQuestTracker"]
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function() self:RefreshQuestRewards() end)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local questID, success = ...
        if success and questID then
            self:ProcessQuest(questID)
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        local questID = ...

        if addonTable.FoundWorldQuests:GetQuest(questID) then
            addonTable.FoundWorldQuests:RemoveQuest(questID)

            if not self.updatingUI then
                self.updatingUI = true
                C_Timer.After(0.1, function() self:UpdateUI() end)
            end
        end
    end
end

local WorldQuestTracker = CreateFrame("Frame")
Mixin(WorldQuestTracker, WorldQuestTrackerMixin)
WorldQuestTracker:Setup()


QuestLogMicroButton:HookScript("OnEnter", function(self)
    if GameTooltip:IsOwned(self) then
        local totalGold = 0
        for qID, data in pairs(addonTable.FoundWorldQuests:GetQuests()) do
            totalGold = totalGold + data.amount
        end
        GameTooltip:AddLine("\nTotal Gold available: "..GetMoneyString(totalGold, true), 1, 1, 1, true)
        GameTooltip:Show()
    end
end)


WorldQuestTabMixin = {}

function WorldQuestTabMixin:OnLoad()
    self.SelectedTexture:Hide()
    self.Icon:SetAtlas(self.activeAtlas)
    self.Icon:SetDesaturated(true)
    self.Icon:SetVertexColor(0.70, 0.60, 0.20)
    self.Icon:SetSize(20, 20)
    self.Icon:Show()
end

function WorldQuestTabMixin:OnClick()
    if IsShiftKeyDown() then
        WorldQuestTracker:ResetQuests()
    else
        QuestMapFrame.WorldQuestsPanel:RefreshList()

        QuestMapFrame:SetDisplayMode(self.displayMode)
    end
end


WorldQuestsPanelMixin = {}

function WorldQuestsPanelMixin:RefreshList()
    local sortedQuests = {}
    for _, quest in pairs(addonTable.FoundWorldQuests:GetQuests()) do
        quest.minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(quest.ID) or quest.minutesLeft or 0
        table.insert(sortedQuests, quest)
    end
    table.sort(sortedQuests, function(a, b)
        local function sortKey(minutes)
            if minutes > 60 then
                return math.floor(minutes / 60) * 60
            end
            return minutes
        end
        local aKey = sortKey(a.minutesLeft)
        local bKey = sortKey(b.minutesLeft)
        if aKey ~= bKey then
            return aKey < bKey
        end
        return a.zone < b.zone
    end)

    local container = self.ScrollFrame.Content

    if not self.pool then
        self.pool = CreateFramePool("Button", container, "WorldQuestEntryTemplate")
    end
    self.pool:ReleaseAll()

    local panel = self

    for i, quest in ipairs(sortedQuests) do
        local entry = self.pool:Acquire()

        entry.layoutIndex = i
        entry.questID = quest.ID
        entry.questName = quest.name
        entry.minutesLeft = quest.minutesLeft
        entry.zone = quest.zone
        entry.amount = quest.amount
        entry.repReward = quest.repReward

        local atlas, width, height = QuestUtil.GetWorldQuestAtlasInfo(quest.ID, quest.tagInfo, false)
        if atlas then
            entry.Icon:SetAtlas(atlas, true)
            local scale = 18 / math.max(width, height)
            entry.Icon:SetSize(width * scale, height * scale)
        else
            entry.Icon:SetAtlas("worldquest-icon-adventure")
            entry.Icon:SetSize(18, 18)
        end

        entry.Title:SetText(entry.questName)
        if entry.minutesLeft <= 0 then
            entry.Title:SetTextColor(DISABLED_FONT_COLOR:GetRGB())
        elseif entry.minutesLeft < (8 * 60) then
            entry.Title:SetTextColor(RED_FONT_COLOR:GetRGB())
        elseif entry.minutesLeft < (24 * 60) then
            entry.Title:SetTextColor(0.8, 0.4, 0)
        else
            entry.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        end

        if entry.amount > 0 then
            entry.Reward:SetText(GetMoneyString(entry.amount, true))
        elseif entry.repReward then
            entry.Reward:SetText("Reputation")
        else
            entry.Reward:SetText("n/a")
        end

        entry:SetScript("OnClick", function(self)
            C_QuestLog.AddWorldQuestWatch(self.questID, Enum.QuestWatchType.Manual)
        end)

        entry:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            if GameTooltip:IsOwned(self) then
                GameTooltip:SetText("Time left: "..panel:FormatQuestTime(self.minutesLeft), NORMAL_FONT_COLOR:GetRGB())
                GameTooltip:AddLine("|cFFFFD100Zone:|r "..self.zone, 1, 1, 1, true)
                if self.amount > 0 then
                    GameTooltip:AddLine("|cFFFFD100Gold:|r "..GetMoneyString(self.amount, true), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end
        end)

        entry:SetScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
                GameTooltip.questID = nil
            end
        end)

        entry:Show()
    end

    container:Layout()
    container:Show()

    self.ScrollFrame:UpdateScrollChildRect()
end

function WorldQuestsPanelMixin:FormatQuestTime(totalMinutes)
    if not totalMinutes or totalMinutes <= 0 then return "|cffff0000Expired|r" end

    local days = math.floor(totalMinutes / 1440)
    local remainingMinutes = totalMinutes % 1440
    local hours = math.floor(remainingMinutes / 60)
    local minutes = remainingMinutes % 60

    if days > 0 then
        -- More than 1 day: show days and hours only
        return string.format("|cFFFFD100%dd %dh", days, hours)
    elseif hours > 0 then
        -- More than 1 hour: show hours only, no minutes
        return string.format("|cFFFFD100%dh", hours)
    else
        -- Under 1 hour: show minutes only
        return string.format("|cffff0000%dm", minutes)
    end
end



SLASH_WorldQuestTracker1 = "/bwq"

SlashCmdList["WorldQuestTracker"] = function(arg)
    local msg = string.lower(arg or "")

    if msg:match("^set%s+%d+$") then
        local value = tonumber(msg:match("^set%s+(%d+)$"))
        if value and value >= 1 then
            SavedVars.MinGoldReward = value * 10000
            print("|cffB0C4DE[WorldQuestTracker]|r Minimum gold reward set to "..GetMoneyString(SavedVars.MinGoldReward, true))

            WorldQuestTracker:ResetQuests()
        end
    elseif msg == "show" then
        print("|cffB0C4DE[WorldQuestTracker]|r Minimum gold reward is "..GetMoneyString(SavedVars.MinGoldReward, true))
    else
        print("|cffB0C4DE[WorldQuestTracker]|r Commands:")
        print("  /bwq set <value> - Set the minimum gold reward amount")
        print("  /bwq show - Prints the minimum gold reward amount")
    end
end