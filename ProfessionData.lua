local addonName, addonTable = ...


addonTable.ObjectiveGroups = {
    gathering = { isUnique = false, free = true, name = "Gathering" },
    treasures = { isUnique = false, free = true, name = "Treasures/Dirt" },
    weeklyQuest = { isUnique = true, free = false, name = "Weekly Quest" },
    disenchanting = { isUnique = false, free = false, name = "Disenchanting" }
}

addonTable.Objectives = {
-- [ProfessionID] = { treasures = {QuestID}, weeklyQuest = {QuestID} }
    [171] = { treasures = {93528, 93529}, weeklyQuest = {93690} }, -- Alchemy
    [164] = { treasures = {93530, 93531}, weeklyQuest = {93691} }, -- Blacksmithing
    [202] = { treasures = {93534, 93535}, weeklyQuest = {93692} }, -- Engineering
    [773] = { treasures = {93537, 93536}, weeklyQuest = {93693} }, -- Inscription
    [755] = { treasures = {93538, 93539}, weeklyQuest = {93694} }, -- Jewelcrafting
    [165] = { treasures = {93541, 93540}, weeklyQuest = {93695} }, -- Leatherworking
    [197] = { treasures = {93543, 93542}, weeklyQuest = {93696} }, -- Tailoring
    [333] = { treasures = {93532, 93533}, weeklyQuest = {93699, 93698, 93697}, disenchanting = {95048, 95049, 95050, 95051, 95052, 95053} }, -- Enchanting
    [182] = { gathering = {81425, 81426, 81427, 81428, 81429, 81430}, weeklyQuest = {85393700, 93701, 93702, 93703, 93704} }, -- Herbalism
    [186] = { gathering = {88673, 88674, 88675, 88676, 88677, 88678}, weeklyQuest = {93705, 93706, 93707, 93708, 93709} }, -- Mining
    [393] = { gathering = {88534, 88549, 88536, 88537, 88530, 88529}, weeklyQuest = {93710, 93711, 93712, 93713, 93714} }  -- Skinning
}

addonTable.Currencies = {
    [171] = {ID = 3150}, -- Alchemy
    [164] = {ID = 3151}, -- Blacksmithing
    [202] = {ID = 3259}, -- Engineering
    [773] = {ID = 3155}, -- Inscription
    [755] = {ID = 3156}, -- Jewelcrafting
    [165] = {ID = 3157}, -- Leatherworking
    [197] = {ID = 3160}, -- Tailoring
    [333] = {ID = 3152}, -- Enchanting
    [182] = {ID = 3154}, -- Herbalism
    [186] = {ID = 3158}, -- Mining
    [393] = {ID = 3159}  -- Skinning
}

addonTable.ExpansionPrefix = "Midnight"