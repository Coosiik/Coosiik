local isNearStation = false
local currentStation = nil
local cachedData = nil
local nuiOpen = false
local isCrafting = false
local resourceName = GetCurrentResourceName()

local function notify(message)
    TriggerEvent('vorp:TipBottom', message, 4000)
end

local function requestData(cb)
    TriggerServerEvent('coosiik_crafting:server:requestData')
    if cb then cb() end
end

local function setNuiState(visible, payload)
    nuiOpen = visible
    SetNuiFocus(visible, visible)
    SetNuiFocusKeepInput(visible)
    SendNUIMessage({
        action = visible and 'open' or 'close',
        payload = payload,
    })
end

local function openCraftingMenu(stationKey)
    if not cachedData then
        requestData(function()
            notify('Pobieram dane craftingu, sprobuj ponownie.')
        end)
        return
    end

    local station = cachedData.stations[stationKey]
    if not station then return end

    setNuiState(true, {
        mode = 'crafting',
        stationKey = stationKey,
        station = station,
        data = cachedData,
    })
end

local function openBlueprintMenu()
    if not cachedData then
        requestData(function()
            notify('Pobieram drzewko blueprintow, sprobuj ponownie.')
        end)
        return
    end

    setNuiState(true, {
        mode = 'blueprints',
        data = cachedData,
    })
end

RegisterNetEvent('coosiik_crafting:client:receiveData', function(payload)
    cachedData = payload
    if nuiOpen then
        SendNUIMessage({
            action = 'refresh',
            payload = payload,
            stationKey = currentStation,
        })
    end
end)

RegisterNetEvent('coosiik_crafting:client:xpUpdated', function(payload, grantedXp, awardedSkillPoints, awardedBlueprintPoints)
    cachedData = payload
    notify(('Otrzymano %s XP za crafting.'):format(grantedXp))

    for _, pointAward in ipairs(awardedSkillPoints or {}) do
        local label = cachedData.skillTree[pointAward.skill] and cachedData.skillTree[pointAward.skill].label or pointAward.skill
        notify(('Otrzymano %s pkt skilla do galezi %s'):format(pointAward.points, label))
    end

    for _, pointAward in ipairs(awardedBlueprintPoints or {}) do
        local label = cachedData.skillTree[pointAward.skill] and cachedData.skillTree[pointAward.skill].label or pointAward.skill
        notify(('Otrzymano %s pkt blueprint do galezi %s'):format(pointAward.points, label))
    end

    if nuiOpen then
        SendNUIMessage({
            action = 'refresh',
            payload = payload,
            stationKey = currentStation,
        })
    end
end)

CreateThread(function()
    Wait(2000)
    requestData()

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        isNearStation = false
        currentStation = nil

        for stationKey, station in pairs(Config.CraftingStations) do
            local distance = #(coords - station.coords)
            if distance <= station.radius then
                sleep = 0
                isNearStation = true
                currentStation = stationKey

                if not nuiOpen then
                    local prompt = CreateVarString(10, 'LITERAL_STRING', ('[J] %s | [B] Blueprinty'):format(station.label))
                    SetTextScale(0.35, 0.35)
                    SetTextColour(255, 255, 255, 215)
                    SetTextCentre(true)
                    DisplayText(prompt, 0.5, 0.92)
                end

                if IsControlJustReleased(0, 0xF3830D8E) and not isCrafting and not nuiOpen then
                    openCraftingMenu(stationKey)
                elseif IsControlJustReleased(0, 0x4CC0E2FE) and not nuiOpen then -- B
                    openBlueprintMenu()
                end
                break
            end
        end

        Wait(sleep)
    end
end)

RegisterNUICallback('close', function(_, cb)
    setNuiState(false)
    cb({ ok = true })
end)

RegisterNUICallback('requestData', function(_, cb)
    requestData()
    cb({ ok = true })
end)

RegisterNUICallback('craft', function(data, cb)
    if isCrafting then
        cb({ ok = false, error = 'Crafting trwa.' })
        return
    end

    if not currentStation then
        cb({ ok = false, error = 'Nie stoisz przy stanowisku.' })
        return
    end

    local recipeKey = data.recipeKey
    local amount = tonumber(data.amount) or 1
    local recipe = Config.Recipes[recipeKey]
    if not recipe then
        cb({ ok = false, error = 'Nie ma takiej receptury.' })
        return
    end

    if currentStation ~= recipe.station then
        cb({ ok = false, error = 'To recipe nalezy do innego stanowiska.' })
        return
    end

    isCrafting = true
    local duration = (recipe.craftTimeMs or Config.CraftingDurationMs) * amount
    SendNUIMessage({ action = 'craftingState', active = true, duration = duration })
    Wait(duration)
    TriggerServerEvent('coosiik_crafting:server:craftItem', recipeKey, amount)
    SendNUIMessage({ action = 'craftingState', active = false })
    isCrafting = false
    cb({ ok = true })
end)

RegisterNUICallback('unlockBlueprint', function(data, cb)
    TriggerServerEvent('coosiik_crafting:server:unlockBlueprintNode', data.nodeKey)
    cb({ ok = true })
end)

RegisterNUICallback('upgradeSkill', function(data, cb)
    TriggerServerEvent('coosiik_crafting:server:spendPoint', data.skill)
    cb({ ok = true })
end)

RegisterCommand(Config.BlueprintOpenCommand, function()
    openBlueprintMenu()
end, false)

RegisterCommand('craftingui', function()
    if currentStation then
        openCraftingMenu(currentStation)
    else
        notify('Podejdz do stanowiska craftingu.')
    end
end, false)
