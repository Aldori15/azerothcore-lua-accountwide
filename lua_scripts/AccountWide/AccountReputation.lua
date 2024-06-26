-- ------------------------------------------------------------------------------------------------
-- ACCOUNTWIDE REPUTATION CONFIG 
--
-- Hosted by Aldori15 on Github: https://github.com/Aldori15/azerothcore-lua-accountwide
-- ------------------------------------------------------------------------------------------------

local ENABLE_ACCOUNTWIDE_REPUTATION = false

local ANNOUNCE_ON_LOGIN = true
local ANNOUNCEMENT = "This server is running the |cFF00B0E8AccountWide Reputation |rlua script."

-- -- ------------------------------------------------------------------------------------------------
-- -- END CONFIG
-- -- ------------------------------------------------------------------------------------------------

if not ENABLE_ACCOUNTWIDE_REPUTATION then return end

-- Alliance Factions
local allianceFactions = {
    [47] = true, [54] = true, [69] = true, [72] = true, [469] = true, [509] = true, [589] = true, 
    [730] = true, [890] = true, [891] = true, [930] = true, [946] = true, [978] = true, [1037] = true, 
    [1050] = true, [1068] = true, [1094] = true, [1126] = true
}

-- Horde Factions
local hordeFactions = {
    [67] = true, [68] = true, [76] = true, [81] = true, [510] = true, [530] = true, [729] = true, 
    [889] = true, [892] = true, [911] = true, [922] = true, [941] = true, [947] = true, [1052] = true, 
    [1064] = true, [1067] = true, [1085] = true, [1124] = true
}

-- List of invalid faction IDs to exclude
local invalidFactions = { [21426] = true }

local initializingAccounts = {}

local function InitializeAccountReputation(accountId, callback)
    local query = CharDBQuery("SELECT faction, MAX(standing) FROM character_reputation WHERE guid IN (SELECT guid FROM characters WHERE account = " .. accountId .. ") GROUP BY faction")
    if query then
        repeat
            local factionId = query:GetUInt32(0)
            local maxStanding = query:GetUInt32(1)
            if not invalidFactions[factionId] then
                CharDBExecute("INSERT INTO accountwide_reputation (accountId, factionId, standing) VALUES (" .. accountId .. ", " .. factionId .. ", " .. maxStanding .. ") ON DUPLICATE KEY UPDATE standing = " .. maxStanding)
            end
        until not query:NextRow()
    end
    initializingAccounts[accountId] = false
    if callback then callback() end
end

local function GetAccountReputation(accountId, player, callback)
    local reputationData = {}
    local query = CharDBQuery("SELECT factionId, standing FROM accountwide_reputation WHERE accountId = " .. accountId)
    if query then
        repeat
            local factionId = query:GetUInt32(0)
            local standing = query:GetUInt32(1)
            if not invalidFactions[factionId] then
                reputationData[factionId] = standing
            end
        until not query:NextRow()
        callback(player, reputationData)
    else
        -- If the table is empty and not already initializing, initialize it once
        if not initializingAccounts[accountId] then
            initializingAccounts[accountId] = true
            InitializeAccountReputation(accountId, function()
                CreateLuaEvent(function()
                    GetAccountReputation(accountId, player, callback)
                end, 500, 1) -- Delay of 500 milliseconds
            end)
        end
    end
end

local function ApplyReputationToPlayer(player, reputationData)
    local playerTeam = player:GetTeam()
    for factionId, accountStanding in pairs(reputationData) do
        if not invalidFactions[factionId] then
            local applyReputation = false
            if playerTeam == 0 then -- Alliance
                if allianceFactions[factionId] or (not allianceFactions[factionId] and not hordeFactions[factionId]) then
                    applyReputation = true
                end
            elseif playerTeam == 1 then -- Horde
                if hordeFactions[factionId] or (not allianceFactions[factionId] and not hordeFactions[factionId]) then
                    applyReputation = true
                end
            end
            if applyReputation then
                local playerStanding = player:GetReputation(factionId)
                if playerStanding and playerStanding ~= accountStanding then
                    player:SetReputation(factionId, accountStanding)
                end
            end
        end
    end
end

local function UpdateAccountReputationOnReputationChange(event, player, factionId, standing)
    if factionId and standing and not invalidFactions[factionId] then
        local accountId = player:GetAccountId()
        CharDBExecute("INSERT INTO accountwide_reputation (accountId, factionId, standing) VALUES (" .. accountId .. ", " .. factionId .. ", " .. standing .. ") ON DUPLICATE KEY UPDATE standing = IF(standing <> VALUES(standing), VALUES(standing), standing)")
    end
end

local function SyncReputationOnLogin(event, player)
    local accountId = player:GetAccountId()
    local guid = player:GetGUIDLow()
    GetAccountReputation(accountId, player, function(player, reputationData)
        CreateLuaEvent(function()
            local targetPlayer = GetPlayerByGUID(guid)
            if targetPlayer then
                ApplyReputationToPlayer(targetPlayer, reputationData)
            end
        end, 500, 1) -- Delay of 500 milliseconds (0.5 seconds) to ensure that the InitializeAccountReputation() function finishes populating the empty table
    end)
    
    if ANNOUNCE_ON_LOGIN then
        player:SendBroadcastMessage(ANNOUNCEMENT)
    end
end

RegisterPlayerEvent(3, SyncReputationOnLogin) -- EVENT_ON_LOGIN
RegisterPlayerEvent(15, UpdateAccountReputationOnReputationChange) -- EVENT_ON_REPUTATION_CHANGE