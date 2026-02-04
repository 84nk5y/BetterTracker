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
local WORLD_QUESTS_TO_SCAN = {}
local FOUND_WORLD_QUESTS = {}
local UDATING_UI = false


local function CreateBadge(point)
    local badge = CreateFrame("Frame", "MyWorldQuestBadge", QuestLogMicroButton)
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

local f = CreateFrame("Frame")

f.worldQuestBadge = CreateBadge("TOP")

-- local function FormatDebugTime(ms)
--     local totalSeconds = math.floor(ms / 1000)
--     local milliseconds = math.floor(ms % 1000)
--     local seconds = totalSeconds % 60
--     local minutes = math.floor(totalSeconds / 60) % 60
--     local hours = math.floor(totalSeconds / 3600)
--     return string.format("%02d:%02d:%02d:%03d", hours, minutes, seconds, milliseconds)
-- end

local function UpdateUI()
    -- print("UpdateUI at "..FormatDebugTime(debugprofilestop()))
    -- for questID, quest in pairs(FOUND_WORLD_QUESTS) do
    --     if not WORLD_QUESTS_TO_SCAN[questID] then
    --         local questName = quest.name
    --         local mapName = quest.zone

    --         print("    Quest not found in WORLD_QUESTS_TO_SCAN: "..questID.." '"..questName.."' on '"..mapName.."'")
    --     end
    -- end
    -- for questID, mapID in pairs(WORLD_QUESTS_TO_SCAN) do
    --     if not FOUND_WORLD_QUESTS[questID] then
    --         local questName = C_QuestLog.GetTitleForQuestID(questID)
    --         local mapName = C_Map.GetMapInfo(mapID).name or "Unknown Zone"

    --         print("    Quest not found in FOUND_WORLD_QUESTS: "..questID.." '"..questName.."' on '"..mapName.."'")
    --     end
    -- end

    local count = 0
    for _ in pairs(FOUND_WORLD_QUESTS) do count = count + 1 end

    if count > 0 then
        f.worldQuestBadge.text:SetText(tostring(count))
        f.worldQuestBadge:Show()
    else
        f.worldQuestBadge:Hide()
    end

    if QuestMapFrame.WorldQuestsPanel and QuestMapFrame.WorldQuestsPanel:IsShown() then
        QuestMapFrame.WorldQuestsPanel:RefreshList()
    end

    UDATING_UI = false
end

local function GetTotalGoldFromQuest(questID)
    local totalMoney = 0

    C_TaskQuest.RequestPreloadRewardData(questID)

    local moneyReward = GetQuestLogRewardMoney(questID)
    if moneyReward and moneyReward > 0 then
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

    return math.floor((tonumber(totalMoney) / 10000)) * 10000
end

local function ProcessQuest(questID)
    if not questID then return end

    if C_QuestLog.IsComplete(questID) or not C_TaskQuest.IsActive(questID) then
        FOUND_WORLD_QUESTS[questID] = nil
        return
    end

    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

    if isWorldQuest then
        local questName = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
        local questTagInfo = C_QuestLog.GetQuestTagInfo(questID)
        local mapID = C_TaskQuest.GetQuestZoneID(questID)
        local mapName = mapID and C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name or "Unknown Zone"
        local goldAmount = GetTotalGoldFromQuest(questID) or 0
        local minutesLeft= C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0

        if goldAmount > (500 * 10000) then
            local quest = {
                ID = questID,
                name = questName,
                amount = goldAmount,
                tagInfo = questTagInfo,
                minutesLeft = minutesLeft,
                zone = mapName
            }
            FOUND_WORLD_QUESTS[questID] = quest
        end


    end

    if not UDATING_UI then
        UDATING_UI = true
        C_Timer.After(1, UpdateUI)
    end
end

local RefreshQuestRewards

local function RefreshQuests()
    for questID, _ in pairs(WORLD_QUESTS_TO_SCAN) do
        if not FOUND_WORLD_QUESTS[questID] then
            ProcessQuest(questID)
        end
    end

    -- queue the next quest refresh cycle
    C_Timer.After(SCAN_RATE, RefreshQuestRewards)
end

RefreshQuestRewards = function()
    local mapList = {}
    for mapID, _ in pairs(WORLD_QUEST_ZONES) do
        table.insert(mapList, mapID)
    end

    WORLD_QUESTS_TO_SCAN = {}

    -- Staggered scanning to reduce FPS impact
    local function ScanMapBatch(index)
        local mapID = mapList[index]
        local quests = C_TaskQuest.GetQuestsOnMap(mapID)

        if quests then
            for _, qInfo in ipairs(quests) do
                local questID = qInfo.questId or qInfo.questID

                if questID then
                    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

                    if isWorldQuest and not WORLD_QUESTS_TO_SCAN[questID] then
                        -- try to force server to provide quest data
                        C_TaskQuest.GetQuestZoneID(questID)
                        C_TaskQuest.RequestPreloadRewardData(questID)
                        C_QuestLog.RequestLoadQuestByID(questID)

                        WORLD_QUESTS_TO_SCAN[questID] = mapID
                    end
                end
            end
        end

        if index < #mapList then
            C_Timer.After(0.1, function() ScanMapBatch(index + 1) end)
        else
            -- to ensure no detected quest is lost (in case quest data event is not triggered)
            C_Timer.After(2, RefreshQuests)
        end
    end

    if #mapList > 0 then
        ScanMapBatch(1)
    end
end


f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_DATA_LOAD_RESULT")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, RefreshQuestRewards)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local questID, success = ...
        if success and questID then
            ProcessQuest(questID)
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        local questID = ...

        if FOUND_WORLD_QUESTS and FOUND_WORLD_QUESTS[questID] then
            FOUND_WORLD_QUESTS[questID] = nil

            if not UDATING_UI then
                UDATING_UI = true
                C_Timer.After(0.1, UpdateUI)
            end
        end
    end
end)

QuestLogMicroButton:HookScript("OnEnter", function(self)
    if GameTooltip:IsOwned(self) then
        local totalGold = 0
        for qID, data in pairs(FOUND_WORLD_QUESTS) do
            totalGold = totalGold + data.amount
        end
        GameTooltip:AddLine("\nTotal Gold available: " .. GetMoneyString(totalGold, true), 1, 1, 1, true)

        GameTooltip:Show()
    end
end)



WorldQuestTabMixin = {}

function WorldQuestTabMixin:OnLoad()
    self.SelectedTexture:Hide()
    self.Icon:SetAtlas(self.activeAtlas)
    self.Icon:SetSize(21, 21)
    self.Icon:Show()
    self.tooltipText = "Gold Quests"
end

function WorldQuestTabMixin:OnClick()
    if IsShiftKeyDown() then
        RefreshQuestRewards()
    else
        QuestMapFrame.WorldQuestsPanel:RefreshList()

        QuestMapFrame:SetDisplayMode(self.displayMode)
    end
end



local function FormatQuestTime(totalMinutes)
    if not totalMinutes or totalMinutes <= 0 then
        return "|cffff0000Expired|r"
    end

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

WorldQuestsPanelMixin = {}

function WorldQuestsPanelMixin:RefreshList()
    if not FOUND_WORLD_QUESTS then
        return
    end

    local sortedQuests = {}
    for _, quest in pairs(FOUND_WORLD_QUESTS) do
        quest.minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(quest.ID) or quest.minutesLeft or 0
        table.insert(sortedQuests, quest)
    end
    table.sort(sortedQuests, function(a, b)
        if a.minutesLeft ~= b.minutesLeft then
            return a.minutesLeft < b.minutesLeft
        end

        return a.zone < b.zone
    end)

    local container = self.ScrollFrame.ScrollChild

    if not self.pool then
        self.pool = CreateFramePool("Button", container, "WorldQuestEntryTemplate")
    end
    self.pool:ReleaseAll()

    for i, quest in ipairs(sortedQuests) do
        local entry = self.pool:Acquire()

        entry.layoutIndex = i
        entry.questID = quest.ID
        entry.questName = quest.name
        entry.minutesLeft = quest.minutesLeft
        entry.zone = quest.zone
        entry.amount = quest.amount

        local atlas, width, height = QuestUtil.GetWorldQuestAtlasInfo(quest.ID, quest.tagInfo, false);
        if atlas then
            entry.Icon:SetAtlas(atlas, true)
            local scale = 18 / math.max(width, height)
            entry.Icon:SetSize(width * scale, height * scale)
        else
            entry.Icon:SetAtlas("worldquest-icon-adventure")
            entry.Icon:SetSize(18, 18)
        end

        entry.Title:SetText(quest.name)
        if quest.minutesLeft < (24 * 60) then
            entry.Title:SetTextColor(RED_FONT_COLOR:GetRGB())
        else
            entry.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        end

        entry.Reward:SetText(GetMoneyString(quest.amount, true))

        entry:SetScript("OnClick", function()
            C_QuestLog.AddWorldQuestWatch(quest.ID, Enum.QuestWatchType.Manual)
        end)

        entry:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            if GameTooltip:IsOwned(self) then
                GameTooltip:SetText("Time left: " .. FormatQuestTime(self.minutesLeft), NORMAL_FONT_COLOR:GetRGB());
                GameTooltip:AddLine("|cFFFFD100Zone:|r " .. self.zone, 1, 1, 1, true)
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
    self.ScrollFrame:UpdateScrollChildRect();
end
