-- /dump C_Map.GetBestMapForUnit("player")
local WORLD_QUEST_ZONES = {
    [2214] = "The Ringing Deeps",
    [2215] = "Hallowfall",
    [2248] = "Isle of Dorn",
    [2339] = "Dornogal",
    [2255] = "Azj-Kahet",
    [2346] = "Undermine",
    [2369] = "Siren Isle",
    [2371] = "K'aresh",
    [2472] = "Tazavesh"
}

local SCAN_RATE = 5 * 60


BT_SavedVars = BT_SavedVars or { WorldQuestTracker= { MinGoldReward = 500 * 10000 } }
local SavedVars = nil


local WorldQuestTrackerMixin = {}

function WorldQuestTrackerMixin:Setup()
    self.worldQuestsToScan = {}
    self.foundWorldQuests = {}
    self.updatingUI = false
    self.foundWorldQuestsCount = 0

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
    if self.foundWorldQuestsCount > 0 then
        self.worldQuestBadge.text:SetText(self.foundWorldQuestsCount)
        self.worldQuestBadge:Show()
    else
        self.worldQuestBadge:Hide()
    end

    if QuestMapFrame and QuestMapFrame.WorldQuestsPanel and QuestMapFrame.WorldQuestsPanel:IsShown() then
        QuestMapFrame.WorldQuestsPanel:RefreshList()
    end

    self.updatingUI = false
end

function WorldQuestTrackerMixin:GetTotalGoldFromQuest(questID)
    local totalMoney = 0

    C_TaskQuest.RequestPreloadRewardData(questID)

    local moneyReward = GetQuestLogRewardMoney(questID) or 0
    if moneyReward > 0 then
        totalMoney = totalMoney + moneyReward
    end

    local currencies = C_QuestLog.GetQuestRewardCurrencies(questID)
    if currencies then
        for _, currency in ipairs(currencies) do
            if currency.currencyID == 0 or currency.name == "Gold" then
                totalMoney = totalMoney + (currency.totalRewardAmount or 0)
            end
        end
    end

    return math.floor(totalMoney / 10000) * 10000
end

function WorldQuestTrackerMixin:ProcessQuest(questID)
    if not questID then return end

    if C_QuestLog.IsComplete(questID) or not C_TaskQuest.IsActive(questID) then
        if self.foundWorldQuests[questID] then
            self.foundWorldQuests[questID] = nil
            self.foundWorldQuestsCount = self.foundWorldQuestsCount - 1
        end

        self.worldQuestsToScan[questID] = nil

        return
    end

    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

    if isWorldQuest then
        local questName = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
        local questTagInfo = C_QuestLog.GetQuestTagInfo(questID)
        local mapID = C_TaskQuest.GetQuestZoneID(questID)
        local mapName = mapID and C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name or "Unknown Zone"
        local goldAmount = self:GetTotalGoldFromQuest(questID) or 0
        local minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0

        if goldAmount > SavedVars.MinGoldReward then
            if not self.foundWorldQuests[questID] then
                self.foundWorldQuestsCount = self.foundWorldQuestsCount + 1
            end

            local quest = {
                ID = questID,
                name = questName,
                amount = goldAmount,
                tagInfo = questTagInfo,
                minutesLeft = minutesLeft,
                zone = mapName
            }
            self.foundWorldQuests[questID] = quest
        end
    end

    if not self.updatingUI then
        self.updatingUI = true
        C_Timer.After(1, function() self:UpdateUI() end)
    end
end

function WorldQuestTrackerMixin:RefreshQuestRewards()
    local mapList = {}
    for mapID in pairs(WORLD_QUEST_ZONES) do
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
        if not self.foundWorldQuests[questID] then
            self:ProcessQuest(questID)
        end
    end

    -- queue the next quest refresh cycle
    C_Timer.After(SCAN_RATE, function() self:RefreshQuestRewards() end)
end

function WorldQuestTrackerMixin:ResetQuests()
    self.worldQuestsToScan = {}
    self.foundWorldQuests = {}
    self.foundWorldQuestsCount = 0

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

        if self.foundWorldQuests and self.foundWorldQuests[questID] then
            self.foundWorldQuests[questID] = nil
            self.foundWorldQuestsCount = self.foundWorldQuestsCount - 1
            self.worldQuestsToScan[questID] = nil

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
        for qID, data in pairs(WorldQuestTracker.foundWorldQuests) do
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
    if not WorldQuestTracker.foundWorldQuests then return end

    local sortedQuests = {}
    for _, quest in pairs(WorldQuestTracker.foundWorldQuests) do
        quest.minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(quest.ID) or quest.minutesLeft or 0
        table.insert(sortedQuests, quest)
    end
    table.sort(sortedQuests, function(a, b)
        if a.minutesLeft ~= b.minutesLeft then
            return a.minutesLeft < b.minutesLeft
        end
        return a.zone < b.zone
    end)

    local container = self.ScrollFrame.Content

    if not self.pool then
        self.pool = CreateFramePool("Button", container, "WorldQuestEntryTemplate")
    end
    self.pool:ReleaseAll()

    -- Store reference to panel for use in button callbacks
    local panel = self

    for i, quest in ipairs(sortedQuests) do
        local entry = self.pool:Acquire()

        entry.layoutIndex = i
        entry.questID = quest.ID
        entry.questName = quest.name
        entry.minutesLeft = quest.minutesLeft
        entry.zone = quest.zone
        entry.amount = quest.amount

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
        if entry.minutesLeft < (8 * 60) then
            entry.Title:SetTextColor(RED_FONT_COLOR:GetRGB())
        elseif entry.minutesLeft < (24 * 60) then
            entry.Title:SetTextColor(0.8, 0.4, 0)
        else
            entry.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        end

        entry.Reward:SetText(GetMoneyString(entry.amount, true))

        entry:SetScript("OnClick", function(self)
            C_QuestLog.AddWorldQuestWatch(self.questID, Enum.QuestWatchType.Manual)
        end)

        entry:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            if GameTooltip:IsOwned(self) then
                GameTooltip:SetText("Time left: "..panel:FormatQuestTime(self.minutesLeft), NORMAL_FONT_COLOR:GetRGB())
                GameTooltip:AddLine("|cFFFFD100Zone:|r "..self.zone, 1, 1, 1, true)
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
        return string.format("|cFFFFD100%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("|cffff0000%dh %dm", hours, minutes)
    else
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