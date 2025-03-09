if IsDuplicityVersion() then
    local wrestlingTables = {}
    
    -- Register a player as waiting at a table
    RegisterNetEvent("qb-armwrestling:registerAsWaiting")
    AddEventHandler("qb-armwrestling:registerAsWaiting", function(entityId)
        local src = source
        
        if not wrestlingTables[entityId] then
            wrestlingTables[entityId] = {
                waiting = src,
                inProgress = false,
                playerA = nil,
                playerB = nil
            }
        else
            wrestlingTables[entityId].waiting = src
        end
    end)
    
    -- Start a match between two players
    RegisterNetEvent("qb-armwrestling:startMatch")
    AddEventHandler("qb-armwrestling:startMatch", function(entityId, playerA, playerB)
        local tableInfo = wrestlingTables[entityId]
        
        if tableInfo and tableInfo.waiting == playerA and not tableInfo.inProgress then
            tableInfo.inProgress = true
            tableInfo.waiting = nil
            tableInfo.playerA = playerA
            tableInfo.playerB = playerB
            
            -- Get entity coordinates to sync between players
            local ent = NetworkGetEntityFromNetworkId(entityId)
            local coords = GetEntityCoords(ent)
            local heading = GetEntityHeading(ent)
            
            -- Position both players
            TriggerClientEvent("qb-armwrestling:positionPlayers", -1, entityId, playerA, playerB, coords, heading)
            
            -- Initialize arm wrestling values
            tableInfo.position = 50 -- neutral position
        end
    end)
    
    -- Update player strength during match
    RegisterNetEvent("qb-armwrestling:updateStrength")
    AddEventHandler("qb-armwrestling:updateStrength", function(playerSrc, opponentSrc, strength)
        for entityId, tableInfo in pairs(wrestlingTables) do
            if tableInfo.inProgress and 
              ((tableInfo.playerA == playerSrc and tableInfo.playerB == opponentSrc) or
               (tableInfo.playerA == opponentSrc and tableInfo.playerB == playerSrc)) then
                
                -- Update position based on which player is pushing
                if tableInfo.playerA == playerSrc then
                    tableInfo.position = tableInfo.position + (strength * 0.5)
                else
                    tableInfo.position = tableInfo.position - (strength * 0.5)
                end
                
                -- Ensure position stays within bounds
                tableInfo.position = math.max(0, math.min(100, tableInfo.position))
                
                -- Broadcast updated position to both players
                TriggerClientEvent("qb-armwrestling:updatePosition", tableInfo.playerA, tableInfo.position)
                TriggerClientEvent("qb-armwrestling:updatePosition", tableInfo.playerB, 100 - tableInfo.position)
                
                -- Check for win conditions
                if tableInfo.position >= 100 then
                    -- Player A wins
                    EndMatch(entityId, tableInfo.playerA, tableInfo.playerB)
                elseif tableInfo.position <= 0 then
                    -- Player B wins
                    EndMatch(entityId, tableInfo.playerB, tableInfo.playerA)
                end
                
                break
            end
        end
    end)
    
    -- End a match and reset the table
    function EndMatch(entityId, winner, loser)
        if wrestlingTables[entityId] then
            wrestlingTables[entityId].inProgress = false
            wrestlingTables[entityId].playerA = nil
            wrestlingTables[entityId].playerB = nil
            wrestlingTables[entityId].waiting = nil
        end
    end
    
    -- Reset table state when a match ends
    RegisterNetEvent("qb-armwrestling:resetTable")
    AddEventHandler("qb-armwrestling:resetTable", function()
        local src = source
        
        for entityId, tableInfo in pairs(wrestlingTables) do
            if tableInfo.playerA == src or tableInfo.playerB == src or tableInfo.waiting == src then
                if tableInfo.playerA and tableInfo.playerA ~= src then
                    TriggerClientEvent("qb-armwrestling:forceEnd", tableInfo.playerA)
                end
                
                if tableInfo.playerB and tableInfo.playerB ~= src then
                    TriggerClientEvent("qb-armwrestling:forceEnd", tableInfo.playerB)
                end
                
                wrestlingTables[entityId] = {
                    waiting = nil,
                    inProgress = false,
                    playerA = nil,
                    playerB = nil
                }
            end
        end
    end)
    
    -- Clean up when a player disconnects
    AddEventHandler('playerDropped', function()
        local src = source
        
        for entityId, tableInfo in pairs(wrestlingTables) do
            if tableInfo.playerA == src or tableInfo.playerB == src or tableInfo.waiting == src then
                if tableInfo.playerA and tableInfo.playerA ~= src then
                    TriggerClientEvent("qb-armwrestling:forceEnd", tableInfo.playerA)
                end
                
                if tableInfo.playerB and tableInfo.playerB ~= src then
                    TriggerClientEvent("qb-armwrestling:forceEnd", tableInfo.playerB)
                end
                
                wrestlingTables[entityId] = {
                    waiting = nil,
                    inProgress = false,
                    playerA = nil,
                    playerB = nil
                }
            end
        end
    end)
end