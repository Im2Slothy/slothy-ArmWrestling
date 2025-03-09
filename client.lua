local QBCore = exports['qb-core']:GetCoreObject()
local isWrestling = false
local waitingForOpponent = false
local currentOpponent = nil
local wrestlingProps = {}
local mashing = false
local inWrestling = false
local countdownActive = false
local positioningInProgress = false
local playerStrength = 0
local opponentStrength = 0
local centerPosition = 50 -- Center position (neutral)
local currentPosition = 50 -- Current position of the arm wrestling contest
local winThreshold = 100 -- Position needed to win
local loseThreshold = 0 -- Position where you lose
local vsAI = false -- Flag for AI opponent
local aiDifficulty = 1 -- Default AI difficulty (1=easy, 2=medium, 3=hard)

-- Animation Dictionaries and Names
local animDicts = {
    ['enter'] = 'mini@arm_wrestling',
    ['idle'] = 'mini@arm_wrestling',
    ['playing'] = 'mini@arm_wrestling',
    ['win'] = 'mini@arm_wrestling',
    ['lose'] = 'mini@arm_wrestling'
}

local animNames = {
    ['enter'] = 'aw_ig_intro_alt1_a',  -- Player A intro
    ['enterWaiting'] = 'aw_ig_intro_alt1_a',
    ['idle'] = 'nuetral_idle_a',       -- Typo matches qb-armwrestle
    ['idleWaiting'] = 'nuetral_idle_a',
    ['playing'] = 'sweep_a',           -- Player A struggle
    ['win'] = 'win_a_ped_a',           -- Player A wins
    ['lose'] = 'win_a_ped_b'           -- Player A loses (Player B wins)
}

-- AI opponent ped model
local aiPedModel = "a_m_y_musclbeac_01" -- Beach muscle guy - perfect for arm wrestling!
local aiPedHandle = nil

-- Helper function for safe animation playback
function PlaySafeAnim(ped, dict, anim, speedIn, speedOut, duration, flag)
    if not DoesEntityExist(ped) then
        --print("PlaySafeAnim: Entity does not exist")
        return false
    end
    
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000 -- 5 second timeout
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Citizen.Wait(100)
    end
    
    if HasAnimDictLoaded(dict) then
        ClearPedTasks(ped) -- Clear any existing animations
        Citizen.Wait(10) -- Small wait to ensure tasks are cleared
        
        TaskPlayAnim(ped, dict, anim, speedIn, speedOut, duration, flag, 0, false, false, false)
        
        -- Wait for the animation to start, but with a timeout
        local animStartTimeout = GetGameTimer() + 1000 -- 1 second timeout
        while not IsEntityPlayingAnim(ped, dict, anim, 3) and GetGameTimer() < animStartTimeout do
            Citizen.Wait(50)
        end
        
        if IsEntityPlayingAnim(ped, dict, anim, 3) then
            --print("Animation started successfully: " .. dict .. " - " .. anim)
            return true
        else
            --print("Failed to start animation: " .. dict .. " - " .. anim)
        end
    else
        --print("Failed to load animation dictionary: " .. dict)
    end
    
    return false
end

-- Register all arm wrestling props in the world
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        local objects = GetGamePool('CObject')
        for _, object in pairs(objects) do
            if GetEntityModel(object) == GetHashKey('prop_arm_wrestle_01') then
                if not wrestlingProps[object] then
                    wrestlingProps[object] = {
                        waiting = nil,
                        playerA = nil,
                        playerB = nil,
                        inProgress = false
                    }
                end
            end
        end
    end
end)

-- Load animations
Citizen.CreateThread(function()
    for _, dict in pairs(animDicts) do
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
        --print("Loaded animation dictionary: " .. dict)
    end
    RequestAnimDict("amb@world_human_push_ups@male@base")
    while not HasAnimDictLoaded("amb@world_human_push_ups@male@base") do
        Citizen.Wait(10)
    end
    --print("Loaded push-up dictionary")
end)

-- Target setup for qb-target
exports['qb-target']:AddTargetModel('prop_arm_wrestle_01', {
    options = {
        {
            icon = "fas fa-hand-rock",
            label = "Arm Wrestle",
            action = function(entity)
                StartArmWrestling(entity)
            end,
            canInteract = function(entity)
                return not isWrestling
            end
        }
    },
    distance = 2.0
})

-- Function to start arm wrestling
function StartArmWrestling(entity)
    local propCoords = GetEntityCoords(entity)
    local propHeading = GetEntityHeading(entity)
    local tableInfo = wrestlingProps[entity]
    
    if tableInfo.inProgress then
        QBCore.Functions.Notify("There's already an arm wrestling match in progress!", "error")
        return
    end
    
    local pData = QBCore.Functions.GetPlayerData()
    
    if tableInfo.waiting then
        -- Someone is already waiting, join as player B
        local opponentId = tableInfo.waiting
        local opponentData = QBCore.Functions.GetPlayerData(GetPlayerFromServerId(opponentId))
        local opponentName = opponentData.charinfo.firstname .. " " .. opponentData.charinfo.lastname
        
        -- Ask if player wants to challenge the waiting player
        local elements = {
            {
                header = "Arm Wrestling Challenge",
                isMenuHeader = true
            },
            {
                header = "Challenge " .. opponentName,
                txt = "Start an arm wrestling match",
                params = {
                    event = "qb-armwrestling:challengeAccepted",
                    args = {
                        entityId = entity,
                        opponentId = opponentId
                    }
                }
            },
            {
                header = "Cancel",
                txt = "Maybe another time...",
                params = {
                    event = "qb-armwrestling:cancelWaiting"
                }
            }
        }
        
        exports['qb-menu']:openMenu(elements)
    else
        -- No one is waiting, show options for waiting or AI
        local elements = {
            {
                header = "Arm Wrestling",
                isMenuHeader = true
            },
            {
                header = "Wait for a player",
                txt = "Wait for another player to challenge you",
                params = {
                    event = "qb-armwrestling:waitForPlayer",
                    args = {
                        entityId = entity
                    }
                }
            },
            {
                header = "Challenge AI (Easy)",
                txt = "Play against an AI opponent (Easy difficulty)",
                params = {
                    event = "qb-armwrestling:challengeAI",
                    args = {
                        entityId = entity,
                        difficulty = 1
                    }
                }
            },
            {
                header = "Challenge AI (Medium)",
                txt = "Play against an AI opponent (Medium difficulty)",
                params = {
                    event = "qb-armwrestling:challengeAI",
                    args = {
                        entityId = entity,
                        difficulty = 2
                    }
                }
            },
            {
                header = "Challenge AI (Hard)",
                txt = "Play against an AI opponent (Hard difficulty)",
                params = {
                    event = "qb-armwrestling:challengeAI",
                    args = {
                        entityId = entity,
                        difficulty = 3
                    }
                }
            },
            {
                header = "Cancel",
                txt = "Maybe another time...",
                params = {
                    event = "qb-armwrestling:cancelWaiting"
                }
            }
        }
        
        exports['qb-menu']:openMenu(elements)
    end
end

-- Event to wait for a player opponent
RegisterNetEvent("qb-armwrestling:waitForPlayer")
AddEventHandler("qb-armwrestling:waitForPlayer", function(data)
    local entity = data.entityId
    local propCoords = GetEntityCoords(entity)
    local propHeading = GetEntityHeading(entity)
    
    TriggerServerEvent("qb-armwrestling:registerAsWaiting", entity)
    
    QBCore.Functions.Notify("Waiting for an opponent...", "primary")
    waitingForOpponent = true
    
    local playerPos = vector3(propCoords.x, propCoords.y - 0.7, propCoords.z - 0.5)
    SetEntityCoords(PlayerPedId(), playerPos)
    SetEntityHeading(PlayerPedId(), propHeading)
    --FreezeEntityPosition(PlayerPedId(), true)
    
    TaskPlayAnim(PlayerPedId(), animDicts['enter'], animNames['enterWaiting'], 8.0, -8.0, -1, 1, 0, false, false, false)
    --print("Player waiting animation: " .. animDicts['enter'] .. " - " .. animNames['enterWaiting'])
    
    Citizen.Wait(5000)
    if waitingForOpponent then
        TaskPlayAnim(PlayerPedId(), animDicts['idle'], animNames['idleWaiting'], 8.0, -8.0, -1, 1, 0, false, false, false)
        --print("Player idle waiting animation: " .. animDicts['idle'] .. " - " .. animNames['idleWaiting'])
    end
end)

-- Event to challenge an AI opponent
RegisterNetEvent("qb-armwrestling:challengeAI")
AddEventHandler("qb-armwrestling:challengeAI", function(data)
    local entity = data.entityId
    local difficulty = data.difficulty
    
    aiDifficulty = difficulty
    vsAI = true
    isWrestling = true
    
    local propCoords = GetEntityCoords(entity)
    local propHeading = GetEntityHeading(entity)
    
    local playerPos = vector3(propCoords.x, propCoords.y - 0.7, propCoords.z - 0.5)
    SetEntityCoords(PlayerPedId(), playerPos)
    SetEntityHeading(PlayerPedId(), propHeading)
    --FreezeEntityPosition(PlayerPedId(), true) -- Removed to allow proper positioning later
    
    SpawnAIOpponent(entity, propCoords, propHeading)
    
    -- Removed early TaskPlayAnim and countdown
    --print("Player enter animation and countdown deferred to StartArmWrestlingGameVsAI")
    
    -- Removed countdown notifications and wait
    StartArmWrestlingGameVsAI()
end)

-- Function to spawn AI opponent
function SpawnAIOpponent(entity, propCoords, propHeading)
    RequestModel(GetHashKey(aiPedModel))
    while not HasModelLoaded(GetHashKey(aiPedModel)) do
        Citizen.Wait(1)
    end

    aiPedHandle = CreatePed(4, GetHashKey(aiPedModel), propCoords.x, propCoords.y + 0.6, propCoords.z - 0.5, propHeading + 180.0, false, true)
    if DoesEntityExist(aiPedHandle) then
        SetPedCanRagdoll(aiPedHandle, false)
        SetPedCanBeTargetted(aiPedHandle, false)
        SetBlockingOfNonTemporaryEvents(aiPedHandle, true)
        FreezeEntityPosition(aiPedHandle, true)

        --print("AI opponent spawned at: " .. propCoords.x .. ", " .. propCoords.y + 0.6 .. ", " .. propCoords.z - 0.5)
    else
        --print("Failed to create AI opponent.")
    end
end

-- Event when a player accepts a challenge
RegisterNetEvent("qb-armwrestling:challengeAccepted")
AddEventHandler("qb-armwrestling:challengeAccepted", function(data)
    TriggerServerEvent("qb-armwrestling:startMatch", data.entityId, data.opponentId, GetPlayerServerId(PlayerId()))
end)

-- Event to position players and start the match
RegisterNetEvent("qb-armwrestling:positionPlayers")
AddEventHandler("qb-armwrestling:positionPlayers", function(entityId, playerA, playerB, entityCoords, entityHeading)
    local playerAId = GetPlayerFromServerId(playerA)
    local playerBId = GetPlayerFromServerId(playerB)
    
    if playerA == GetPlayerServerId(PlayerId()) then
        -- I'm player A (already positioned)
        currentOpponent = playerB
        isWrestling = true
        
        -- Stop waiting
        waitingForOpponent = false
        
        -- Update animation from waiting to ready
        TaskPlayAnim(PlayerPedId(), animDicts['idle'], animNames['idle'], 8.0, -8.0, -1, 1, 0, false, false, false)
    elseif playerB == GetPlayerServerId(PlayerId()) then
        -- I'm player B (need to move to position)
        currentOpponent = playerA
        isWrestling = true
        
        -- Position at the table
        local playerPos = vector3(entityCoords.x, entityCoords.y + 0.7, entityCoords.z - 1) -- Adjust +0.7 based on prop size
        SetEntityCoords(PlayerPedId(), playerPos)
        SetEntityHeading(PlayerPedId(), entityHeading) -- Match prop heading or adjust as needed
        --FreezeEntityPosition(PlayerPedId(), true) -- Lock player in place
        
        -- Play entry animation
        TaskPlayAnim(PlayerPedId(), animDicts['enter'], animNames['enter'], 8.0, -8.0, -1, 1, 0, false, false, false)
        
        -- Wait for a bit then transition to idle animation
        Citizen.Wait(5000)
        TaskPlayAnim(PlayerPedId(), animDicts['idle'], animNames['idle'], 8.0, -8.0, -1, 1, 0, false, false, false)
    end
    
    -- Wait for both players to be ready
    Citizen.Wait(2000)
    
    if isWrestling then
        QBCore.Functions.Notify("How to play? Rapidly press A and D to win!", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("3...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("2...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("1...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("GO!", "success")
        
        -- Start the game
        StartArmWrestlingGame()
    end
end)

-- Function to handle the actual arm wrestling game against real player
function StartArmWrestlingGame()
    -- Start playing animation
    TaskPlayAnim(PlayerPedId(), animDicts['playing'], animNames['playing'], 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Reset values
    playerStrength = 0
    currentPosition = 50
    mashing = true
    
    -- Create a thread to handle key presses
    Citizen.CreateThread(function()
        while mashing and isWrestling do
            Citizen.Wait(0)
            
            -- A and D key presses (alternating)
            if IsControlJustPressed(0, 34) then -- A key
                playerStrength = playerStrength + 1
            elseif IsControlJustPressed(0, 35) then -- D key
                playerStrength = playerStrength + 1
            end
            
            -- Send strength updates to server every 100ms
            if playerStrength > 0 then
                TriggerServerEvent("qb-armwrestling:updateStrength", GetPlayerServerId(PlayerId()), currentOpponent, playerStrength)
                playerStrength = 0
            end
        end
    end)
    
    -- Create a thread to render UI
    Citizen.CreateThread(function()
        while mashing and isWrestling do
            Citizen.Wait(0)
            
            -- Draw progress bar
            DrawRect(0.5, 0.95, 0.2, 0.03, 0, 0, 0, 200)
            
            -- Draw current position indicator
            local barWidth = 0.2 * (currentPosition / 100)
            DrawRect(0.4 + barWidth/2, 0.95, barWidth, 0.03, 255, 255, 255, 200)
            
            -- Draw center marker
            DrawRect(0.5, 0.95, 0.002, 0.03, 255, 0, 0, 200)
            
            -- Draw winning sides markers
            DrawRect(0.4, 0.95, 0.002, 0.03, 255, 0, 0, 200) -- left/lose
            DrawRect(0.6, 0.95, 0.002, 0.03, 0, 255, 0, 200) -- right/win
        end
    end)
end

RegisterNetEvent("qb-armwrestling:cancelWaiting")
AddEventHandler("qb-armwrestling:cancelWaiting", function()
    if waitingForOpponent then
        -- End the arm wrestling session with a "cancel" result
        EndArmWrestling("cancel")
        -- Close the menu explicitly
        exports['qb-menu']:closeMenu()
    end
end)

-- Function to handle arm wrestling game against AI
function StartArmWrestlingGameVsAI()
    if isWrestling and not positioningInProgress then
        positioningInProgress = true
        --print("Starting arm wrestling game vs AI")

        -- Ensure the player and AI are in position
        local prop = GetClosestObjectOfType(GetEntityCoords(PlayerPedId()), 1.5, GetHashKey('prop_arm_wrestle_01'), 0, 0, 0)
        local propCoords = GetEntityCoords(prop)
        local playerPed = PlayerPedId()

        -- Set initial positions
        SetEntityCoords(playerPed, propCoords.x - 0.1, propCoords.y - 0.6, propCoords.z - 0.45)
        SetEntityHeading(playerPed, GetEntityHeading(prop))
        if aiPedHandle then
            SetEntityCoords(aiPedHandle, propCoords.x + 0.1, propCoords.y + 0.6, propCoords.z - 0.45)
            SetEntityHeading(aiPedHandle, GetEntityHeading(prop) + 180.0)
        end

        local maxSpawnWait = 2000
        local spawnWaitStart = GetGameTimer()
        while aiPedHandle and not DoesEntityExist(aiPedHandle) and (GetGameTimer() - spawnWaitStart) < maxSpawnWait do
            Citizen.Wait(100)
        end
        if not DoesEntityExist(aiPedHandle) then
            --print("AI failed to spawn properly. Aborting match.")
            EndArmWrestling("cancel")
            positioningInProgress = false
            return
        end
        --print("AI spawn confirmed.")

        -- Freeze positions immediately to prevent drift
        FreezeEntityPosition(playerPed, true)
        if aiPedHandle then
            FreezeEntityPosition(aiPedHandle, true)
        end

        -- Start with intro animations and keep them throughout the countdown
        --print("Starting intro animations")
        PlaySafeAnim(playerPed, animDicts['enter'], animNames['enter'], 8.0, -8.0, -1, 2, 0)
        if aiPedHandle then
            PlaySafeAnim(aiPedHandle, animDicts['enter'], 'aw_ig_intro_alt1_b', 8.0, -8.0, -1, 2, 0)
        end
        --print("Intro animations started")

        -- Allow time for intro animations to sync but don't end them
        Citizen.Wait(3000)

        -- Start countdown while still in intro animation
        --print("Starting countdown")
        QBCore.Functions.Notify("Get ready...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("3...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("2...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("1...", "warning")
        Citizen.Wait(1000)
        QBCore.Functions.Notify("GO! Rapidly press A and D to win!", "success")

        -- Now transition directly to struggle animations
        --print("Starting struggle phase")
        PlaySafeAnim(playerPed, animDicts['playing'], animNames['playing'], 8.0, -8.0, -1, 2, 0)
        if aiPedHandle then
            PlaySafeAnim(aiPedHandle, animDicts['playing'], 'sweep_b', 8.0, -8.0, -1, 2, 0)
        end
        --print("Struggle animations started")

        playerStrength = 0
        currentPosition = 50
        mashing = true

        local aiPushStrength = 0
        local aiPushFrequency = 0
        local aiRandomVariance = 0
        if aiDifficulty == 1 then
            aiPushStrength = 0.45 -- This determines how much the AI pushes on the bar
            aiPushFrequency = 400 -- This determines how often the AI pushes in ms
            aiRandomVariance = 0.02 -- This determines how much the AI's push strength can vary
        elseif aiDifficulty == 2 then
            aiPushStrength = 0.6
            aiPushFrequency = 350
            aiRandomVariance = 0.03
        else
            aiPushStrength = 0.7
            aiPushFrequency = 275
            aiRandomVariance = 0.04
        end

        Citizen.CreateThread(function()
            local lastAiPush = GetGameTimer()
            local lastInputTime = GetGameTimer()
            local inputCooldown = 30
            while mashing and isWrestling and vsAI and currentPosition > loseThreshold and currentPosition < winThreshold do
                Citizen.Wait(0)
                if GetGameTimer() - lastAiPush >= aiPushFrequency then
                    local variance = math.random() * aiRandomVariance
                    local aiPush = aiPushStrength + variance
                    currentPosition = currentPosition - aiPush
                    lastAiPush = GetGameTimer()
                    --print("AI Push: " .. aiPush .. " | New Position: " .. currentPosition)
                end
                if IsControlPressed(0, 34) or IsControlPressed(0, 35) then
                    if GetGameTimer() - lastInputTime >= inputCooldown then
                        currentPosition = currentPosition + 0.15
                        lastInputTime = GetGameTimer()
                        --print("Player Push: 0.15 | New Position: " .. currentPosition)
                    end
                end
                currentPosition = math.max(0, math.min(100, currentPosition))
                local animGrade = currentPosition / 100
                if IsEntityPlayingAnim(playerPed, animDicts['playing'], animNames['playing'], 3) then
                    SetEntityAnimCurrentTime(playerPed, animDicts['playing'], animNames['playing'], animGrade)
                end
                if aiPedHandle and IsEntityPlayingAnim(aiPedHandle, animDicts['playing'], 'sweep_b', 3) then
                    SetEntityAnimCurrentTime(aiPedHandle, animDicts['playing'], 'sweep_b', animGrade)
                end
                --print("Anim Sync | Position: " .. currentPosition .. " | Anim Grade: " .. animGrade)
            end
            if currentPosition <= loseThreshold then
                EndArmWrestling("lose")
            elseif currentPosition >= winThreshold then
                EndArmWrestling("win")
            end
        end)

        Citizen.CreateThread(function()
            while mashing and isWrestling do
                Citizen.Wait(0)
                DrawRect(0.5, 0.95, 0.2, 0.03, 0, 0, 0, 200)
                local barWidth = 0.2 * (currentPosition / 100)
                DrawRect(0.4 + barWidth/2, 0.95, barWidth, 0.03, 255, 255, 255, 200)
                DrawRect(0.5, 0.95, 0.002, 0.03, 255, 0, 0, 200)
                DrawRect(0.4, 0.95, 0.002, 0.03, 255, 0, 0, 200)
                DrawRect(0.6, 0.95, 0.002, 0.03, 0, 255, 0, 200)
            end
        end)

        positioningInProgress = false
    end
end


-- Update the current position of the arm wrestling match
RegisterNetEvent("qb-armwrestling:updatePosition")
AddEventHandler("qb-armwrestling:updatePosition", function(newPosition)
    currentPosition = newPosition
    
    -- Check if match is over
    if currentPosition >= winThreshold then
        EndArmWrestling("win")
    elseif currentPosition <= loseThreshold then
        EndArmWrestling("lose")
    end
end)

-- End the arm wrestling match
function EndArmWrestling(result)
    mashing = false
    
    if result == "win" then
        TaskPlayAnim(PlayerPedId(), animDicts['win'], animNames['win'], 1.5, 1.5, -1, 2, 0, false, false, false)
        if vsAI and aiPedHandle then
            TaskPlayAnim(aiPedHandle, animDicts['lose'], 'win_a_ped_b', 1.5, 1.5, -1, 2, 0, false, false, false)
        end
    elseif result == "lose" then
        TaskPlayAnim(PlayerPedId(), animDicts['lose'], animNames['lose'], 1.5, 1.5, -1, 2, 0, false, false, false)
        if vsAI and aiPedHandle then
            TaskPlayAnim(aiPedHandle, animDicts['win'], 'win_a_ped_a', 1.5, 1.5, -1, 2, 0, false, false, false)
        end
    elseif result == "cancel" then
        QBCore.Functions.Notify("You canceled the arm wrestling session.", "primary")
    end
    
    if result == "win" or result == "lose" then
        Citizen.Wait(5000)
    end
    
    ClearPedTasks(PlayerPedId())
    FreezeEntityPosition(PlayerPedId(), false)
    
    if vsAI and aiPedHandle then
        Citizen.Wait(1000)
        DeleteEntity(aiPedHandle)
        aiPedHandle = nil
    end
    
    isWrestling = false
    waitingForOpponent = false
    currentOpponent = nil
    vsAI = false
    
    if not vsAI then
        TriggerServerEvent("qb-armwrestling:resetTable")
    end
end

-- Forced end of match (e.g., when opponent disconnects)
RegisterNetEvent("qb-armwrestling:forceEnd")
AddEventHandler("qb-armwrestling:forceEnd", function()
    if isWrestling or waitingForOpponent then
        mashing = false
        ClearPedTasks(PlayerPedId())
        
        -- Clean up AI opponent if present
        if vsAI and aiPedHandle then
            DeleteEntity(aiPedHandle)
            aiPedHandle = nil
        end
        
        -- Reset all states
        isWrestling = false
        waitingForOpponent = false
        currentOpponent = nil
        vsAI = false
        
        QBCore.Functions.Notify("Arm wrestling match ended unexpectedly.", "error")
    end
end)
