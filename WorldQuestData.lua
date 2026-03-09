local addonName, addonTable = ...

-- /dump C_Map.GetBestMapForUnit("player")
addonTable.WorldQuestsZones = {
    [2424] = "Silvermoon -Isle of Quel'Danas",
    [2393] = "Silvermoon City",
    [2395] = "Eversong Woods",
    [2437] = "Zul'Aman",
    [2576] = "Harandar",
    [2405] = "Voidstorm",
    [2444] = "Voidstorm - Bloodplains"
}


addonTable.FoundWorldQuests = { quests = {}, count = 0 }
local FoundWorldQuests = addonTable.FoundWorldQuests

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