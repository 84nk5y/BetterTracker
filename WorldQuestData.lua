local _, _A = ...


-- Use /dump C_Map.GetBestMapForUnit("player") in-game to find map IDs
_A.WorldQuestsZones = {
    [2424] = "Silvermoon - Isle of Quel'Danas",
    [2393] = "Silvermoon City",
    [2395] = "Eversong Woods",
    [2437] = "Zul'Aman",
    [2576] = "Harandar",
    [2405] = "Voidstorm",
    [2444] = "Voidstorm - Bloodplains",
}
local WorldQuestsZones = _A.WorldQuestsZones


_A.FoundWorldQuests = { quests = {}, count = 0 }
local FoundWorldQuests = _A.FoundWorldQuests

function FoundWorldQuests:GetQuests()
    return self.quests
end

function FoundWorldQuests:GetQuest(questID)
    return self.quests[questID]
end

function FoundWorldQuests:GetCount()
    return self.count
end

function FoundWorldQuests:AddQuest(questID, data)
    local quests = self.quests
    if not quests[questID] then
        self.count = self.count + 1
    end
    quests[questID] = data
end

function FoundWorldQuests:RemoveQuest(questID)
    local quests = self.quests
    if quests[questID] then
        quests[questID] = nil
        self.count = self.count - 1
    end
end

function FoundWorldQuests:Clear()
    self.quests = {}
    self.count = 0
end


function _A.ProcessWorldQuest(questID, savedVars)
    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    local existingQuest = FoundWorldQuests:GetQuests(questID)

    if existingQuest and (C_QuestLog.IsComplete(questID) or not C_TaskQuest.IsActive(questID)) then
        FoundWorldQuests:RemoveQuest(questID)
        return true
    end

    if not WorldQuestsZones[mapID] then return false end

    if not C_QuestLog.IsWorldQuest(questID) then return false end

    local mapInfo = C_Map.GetMapInfo(mapID)
    local rewards = _A:GetRewardsForQuest(questID)

    if rewards.gold > savedVars.MinGoldReward or rewards.reputation then
        local quest = {
            ID = questID,
            name = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest",
            amount = rewards.gold,
            repReward = rewards.reputation,
            tagInfo = C_QuestLog.GetQuestTagInfo(questID),
            minutesLeft = C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0,
            zone = mapInfo and mapInfo.name or "Unknown Zone",
        }
        FoundWorldQuests:AddQuest(questID, quest)

        return true
    end

    return false
end

function _A:GetRewardsForQuest(questID)
    local rewards = { gold = 0, reputation = false }

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