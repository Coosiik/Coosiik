local Core = exports.vorp_core:GetCore()

local RESOURCE_NAME = GetCurrentResourceName()
local PLAYER_DATA = {}
local INVENTORY_RESOURCE = nil

local function resolveInventoryResource()
    local candidates = {}
    if Config and Config.InventoryApiResource then
        candidates[#candidates + 1] = Config.InventoryApiResource
    end

    for _, resourceName in ipairs((Config and Config.InventoryFallbackResources) or {}) do
        local alreadyAdded = false
        for _, existing in ipairs(candidates) do
            if existing == resourceName then
                alreadyAdded = true
                break
            end
        end

        if not alreadyAdded then
            candidates[#candidates + 1] = resourceName
        end
    end

    for _, resourceName in ipairs(candidates) do
        if GetResourceState(resourceName) == 'started' then
            return resourceName
        end
    end

    return nil
end

local function inventoryCall(methodName, ...)
    if not INVENTORY_RESOURCE then
        local tried = {}
        if Config and Config.InventoryApiResource then
            tried[#tried + 1] = Config.InventoryApiResource
        end
        for _, resourceName in ipairs((Config and Config.InventoryFallbackResources) or {}) do
            tried[#tried + 1] = resourceName
        end

        error(('Inventory resource not found. Ustaw Config.InventoryApiResource. Tried: %s'):format(table.concat(tried, ', ')))
    end

    return exports[INVENTORY_RESOURCE][methodName](...)
end


local function normalizeSource(playerSource)
    local normalized = tonumber(playerSource)
    if not normalized or normalized <= 0 then
        return nil
    end

    return normalized
end

local function debugPrint(...)
    if Config.Debug then
        print(('^3[%s]^7'):format(RESOURCE_NAME), ...)
    end
end

local function getIdentifier(source)
    local user = Core.getUser(source)
    if not user then return nil end

    local character = user.getUsedCharacter
    if type(character) == 'function' then
        character = character(user)
    end

    if character and character.charIdentifier then
        return tostring(character.charIdentifier)
    end

    if user.identifier then
        return tostring(user.identifier)
    end

    return nil
end

local function getPlayerState(source)
    local identifier = getIdentifier(source)
    if not identifier then return nil end

    if not PLAYER_DATA[identifier] then
        PLAYER_DATA[identifier] = {
            blueprints = {},
            skills = {},
            xp = {},
            unspentPoints = 0,
            pointMilestones = {},
            blueprintPoints = 0,
        }
    end

    for skillName in pairs(Config.SkillTree) do
        PLAYER_DATA[identifier].skills[skillName] = PLAYER_DATA[identifier].skills[skillName] or 0
        PLAYER_DATA[identifier].xp[skillName] = PLAYER_DATA[identifier].xp[skillName] or 0
        PLAYER_DATA[identifier].pointMilestones[skillName] = PLAYER_DATA[identifier].pointMilestones[skillName] or 0
    end

    return PLAYER_DATA[identifier], identifier
end

local function inventoryHasItem(source, itemName, amount)
    local playerSource = normalizeSource(source)
    if not playerSource then return false end

    amount = amount or 1
    local count = inventoryCall('getItemCount', playerSource, nil, itemName)
    return (count or 0) >= amount
end

local function inventoryCount(source, itemName)
    local playerSource = normalizeSource(source)
    if not playerSource then return 0 end

    return inventoryCall('getItemCount', playerSource, nil, itemName) or 0
end

local function removeIngredients(source, ingredients)
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    for _, ingredient in ipairs(ingredients) do
        inventoryCall('subItem', playerSource, ingredient.item, ingredient.count)
    end
end

local function giveRewards(source, rewards)
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    for _, reward in ipairs(rewards) do
        inventoryCall('addItem', playerSource, reward.item, reward.count)
    end
end

local function getBlueprintNode(nodeKey)
    for _, node in ipairs(Config.BlueprintTree or {}) do
        if node.key == nodeKey then
            return node
        end
    end
end

local function addBlueprintsForNode(playerState, node)
    for _, recipeKey in ipairs(node.recipeKeys or {}) do
        local recipe = Config.Recipes[recipeKey]
        if recipe and recipe.blueprint then
            playerState.blueprints[recipe.blueprint] = true
        end
    end
end

local function requirementsMet(playerState, recipe)
    for skillName, requiredLevel in pairs(recipe.skillRequirements or {}) do
        local currentLevel = playerState.skills[skillName] or 0
        if currentLevel < requiredLevel then
            return false, skillName, requiredLevel, currentLevel
        end
    end

    return true
end

local function ingredientsMet(source, recipe)
    local ingredientState = {}

    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local have = inventoryCount(source, ingredient.item)
        ingredientState[#ingredientState + 1] = {
            item = ingredient.item,
            label = ingredient.label or ingredient.item,
            count = ingredient.count,
            have = have,
            met = have >= ingredient.count,
        }

        if have < ingredient.count then
            return false, ingredient.item, ingredient.count, ingredientState
        end
    end

    return true, nil, nil, ingredientState
end

local function categoryXp(category)
    return Config.XpByCategory[category] or Config.XpByCategory[Config.DefaultCategory] or 10
end

local function addXpAndPoints(source, playerState, recipe)
    local grantedXp = recipe.xp or categoryXp(recipe.category)
    local awardedSkillPoints = {}
    local awardedBlueprintPoints = {}

    for skillName in pairs(recipe.skillRequirements or {}) do
        playerState.xp[skillName] = (playerState.xp[skillName] or 0) + grantedXp

        local reachedMilestones = math.floor(playerState.xp[skillName] / 100)
        local alreadyAwarded = playerState.pointMilestones[skillName] or 0

        if reachedMilestones > alreadyAwarded then
            local newPoints = reachedMilestones - alreadyAwarded
            local scaledPoints = newPoints * (Config.DefaultSkillPointsPerLevel or 1)
            playerState.unspentPoints = playerState.unspentPoints + scaledPoints
            playerState.blueprintPoints = (playerState.blueprintPoints or 0) + newPoints
            playerState.pointMilestones[skillName] = reachedMilestones

            awardedSkillPoints[#awardedSkillPoints + 1] = {
                skill = skillName,
                points = scaledPoints,
            }
            awardedBlueprintPoints[#awardedBlueprintPoints + 1] = {
                skill = skillName,
                points = newPoints,
            }
        end
    end

    TriggerClientEvent('coosiik_crafting:client:xpUpdated', source, playerState, grantedXp, awardedSkillPoints, awardedBlueprintPoints)
end

local function buildRecipePayload(source, playerState, recipeKey, recipe)
    local ingredientDetails = {}
    local ingredientsOk = true

    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local have = inventoryCount(source, ingredient.item)
        local met = have >= ingredient.count
        if not met then ingredientsOk = false end

        ingredientDetails[#ingredientDetails + 1] = {
            item = ingredient.item,
            label = ingredient.label or ingredient.item,
            count = ingredient.count,
            have = have,
            met = met,
        }
    end

    local skillOk = true
    local skillMissing = nil
    for skillName, requiredLevel in pairs(recipe.skillRequirements or {}) do
        local currentLevel = playerState.skills[skillName] or 0
        if currentLevel < requiredLevel then
            skillOk = false
            skillMissing = {
                skill = skillName,
                required = requiredLevel,
                current = currentLevel,
            }
            break
        end
    end

    local blueprintKnown = not recipe.blueprint or playerState.blueprints[recipe.blueprint] == true
    local unlocked = blueprintKnown and skillOk

    return {
        key = recipeKey,
        label = recipe.label,
        description = recipe.description,
        station = recipe.station,
        category = recipe.category,
        theme = recipe.theme,
        craftTimeMs = recipe.craftTimeMs or Config.CraftingDurationMs,
        durationLabel = recipe.durationLabel or '00:30',
        icon = recipe.icon or '•',
        previewModel = recipe.previewModel,
        blueprint = recipe.blueprint,
        blueprintNode = recipe.blueprintNode,
        skillRequirements = recipe.skillRequirements or {},
        rewards = recipe.rewards or {},
        ingredients = ingredientDetails,
        unlocked = unlocked,
        blueprintKnown = blueprintKnown,
        skillOk = skillOk,
        ingredientsOk = ingredientsOk,
        skillMissing = skillMissing,
    }
end

local function buildBlueprintPayload(playerState)
    local result = {}

    for _, node in ipairs(Config.BlueprintTree or {}) do
        local known = false
        for _, recipeKey in ipairs(node.recipeKeys or {}) do
            local recipe = Config.Recipes[recipeKey]
            if recipe and recipe.blueprint and playerState.blueprints[recipe.blueprint] then
                known = true
                break
            end
        end

        local requirementsMetLocal = true
        for _, requiredNode in ipairs(node.requires or {}) do
            local reqNode = getBlueprintNode(requiredNode)
            if reqNode then
                local reqKnown = false
                for _, recipeKey in ipairs(reqNode.recipeKeys or {}) do
                    local recipe = Config.Recipes[recipeKey]
                    if recipe and recipe.blueprint and playerState.blueprints[recipe.blueprint] then
                        reqKnown = true
                        break
                    end
                end
                if not reqKnown then
                    requirementsMetLocal = false
                    break
                end
            end
        end

        result[#result + 1] = {
            key = node.key,
            label = node.label,
            description = node.description,
            group = node.group,
            tier = node.tier,
            position = node.position,
            skill = node.skill,
            cost = node.cost or Config.BlueprintPointCost,
            requires = node.requires or {},
            recipeKeys = node.recipeKeys or {},
            unlocked = known,
            available = (not known) and requirementsMetLocal,
        }
    end

    return result
end

local function playerPayload(source, state)
    local playerSource = normalizeSource(source)
    local playerState = state or getPlayerState(playerSource)
    if type(playerState) ~= 'table' then return nil end

    local recipes = {}
    for recipeKey, recipe in pairs(Config.Recipes) do
        recipes[recipeKey] = buildRecipePayload(playerSource, playerState, recipeKey, recipe)
    end

    return {
        player = {
            blueprints = playerState.blueprints,
            skills = playerState.skills,
            xp = playerState.xp,
            unspentPoints = playerState.unspentPoints,
            pointMilestones = playerState.pointMilestones,
            blueprintPoints = playerState.blueprintPoints or 0,
        },
        recipes = recipes,
        skillTree = Config.SkillTree,
        stations = Config.CraftingStations,
        blueprintTree = buildBlueprintPayload(playerState),
        config = {
            blueprintOpenCommand = Config.BlueprintOpenCommand,
        }
    }
end

RegisterNetEvent('coosiik_crafting:server:requestData', function()
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    local state = getPlayerState(playerSource)
    if not state then return end

    TriggerClientEvent('coosiik_crafting:client:receiveData', playerSource, playerPayload(playerSource, state))
end)

RegisterNetEvent('coosiik_crafting:server:spendPoint', function(skillName)
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    local state = getPlayerState(playerSource)
    local skillConfig = Config.SkillTree[skillName]

    if not state or not skillConfig then return end
    if state.unspentPoints <= 0 then
        TriggerClientEvent('vorp:TipBottom', playerSource, 'Brak wolnych punktow umiejetnosci.', 4000)
        return
    end

    local current = state.skills[skillName] or 0
    if current >= (skillConfig.maxLevel or 5) then
        TriggerClientEvent('vorp:TipBottom', playerSource, 'Ta umiejetnosc ma juz maksymalny poziom.', 4000)
        return
    end

    state.skills[skillName] = current + 1
    state.unspentPoints = state.unspentPoints - 1
    TriggerClientEvent('vorp:TipBottom', playerSource, ('Zwiekszono poziom %s do %s'):format(skillConfig.label, state.skills[skillName]), 4000)
    TriggerClientEvent('coosiik_crafting:client:receiveData', playerSource, playerPayload(playerSource, state))
end)

RegisterNetEvent('coosiik_crafting:server:unlockBlueprintNode', function(nodeKey)
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    local state = getPlayerState(playerSource)
    local node = getBlueprintNode(nodeKey)
    if not state or not node then return end

    if (state.blueprintPoints or 0) < (node.cost or Config.BlueprintPointCost) then
        TriggerClientEvent('vorp:TipBottom', playerSource, 'Brak punktow blueprintow.', 4000)
        return
    end

    for _, requiredNode in ipairs(node.requires or {}) do
        local reqNode = getBlueprintNode(requiredNode)
        if reqNode then
            local unlocked = false
            for _, recipeKey in ipairs(reqNode.recipeKeys or {}) do
                local recipe = Config.Recipes[recipeKey]
                if recipe and recipe.blueprint and state.blueprints[recipe.blueprint] then
                    unlocked = true
                    break
                end
            end
            if not unlocked then
                TriggerClientEvent('vorp:TipBottom', playerSource, 'Musisz odblokowac poprzedni blueprint.', 4000)
                return
            end
        end
    end

    addBlueprintsForNode(state, node)
    state.blueprintPoints = state.blueprintPoints - (node.cost or Config.BlueprintPointCost)
    TriggerClientEvent('vorp:TipBottom', playerSource, ('Odblokowano research: %s'):format(node.label), 4000)
    TriggerClientEvent('coosiik_crafting:client:receiveData', playerSource, playerPayload(playerSource, state))
end)

RegisterNetEvent('coosiik_crafting:server:craftItem', function(recipeKey, amount)
    local playerSource = normalizeSource(source)
    if not playerSource then return end

    local recipe = Config.Recipes[recipeKey]
    local craftAmount = math.max(1, math.min(tonumber(amount) or 1, 10))
    if not recipe then return end

    local state = getPlayerState(playerSource)
    if not state then return end

    if recipe.blueprint and not state.blueprints[recipe.blueprint] then
        TriggerClientEvent('vorp:TipBottom', playerSource, 'Research required. Otworz drzewko blueprintow.', 4000)
        return
    end

    local skillsOk, skillName, requiredLevel, currentLevel = requirementsMet(state, recipe)
    if not skillsOk then
        local skillLabel = Config.SkillTree[skillName] and Config.SkillTree[skillName].label or skillName
        TriggerClientEvent('vorp:TipBottom', playerSource, ('Potrzebujesz %s %s (masz %s).'):format(skillLabel, requiredLevel, currentLevel), 4000)
        return
    end

    local scaledIngredients = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        scaledIngredients[#scaledIngredients + 1] = {
            item = ingredient.item,
            label = ingredient.label,
            count = ingredient.count * craftAmount,
        }
    end

    local scaledRewards = {}
    for _, reward in ipairs(recipe.rewards or {}) do
        scaledRewards[#scaledRewards + 1] = {
            item = reward.item,
            count = reward.count * craftAmount,
        }
    end

    local scaledRecipe = {
        ingredients = scaledIngredients,
        rewards = scaledRewards,
        category = recipe.category,
        xp = (recipe.xp or categoryXp(recipe.category)) * craftAmount,
        skillRequirements = recipe.skillRequirements,
    }

    local ingredientsOk, ingredientName, ingredientCount = ingredientsMet(playerSource, scaledRecipe)
    if not ingredientsOk then
        TriggerClientEvent('vorp:TipBottom', playerSource, ('Brakuje skladnika: %s x%s'):format(ingredientName, ingredientCount), 4000)
        return
    end

    removeIngredients(playerSource, scaledIngredients)
    giveRewards(playerSource, scaledRewards)
    addXpAndPoints(playerSource, state, scaledRecipe)

    TriggerClientEvent('vorp:TipBottom', playerSource, ('Stworzono: %s x%s'):format(recipe.label, craftAmount), 4000)
    TriggerClientEvent('coosiik_crafting:client:receiveData', playerSource, playerPayload(playerSource, state))
    debugPrint(('Crafted recipe %s x%s for %s'):format(recipeKey, craftAmount, playerSource))
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE_NAME then
        INVENTORY_RESOURCE = resolveInventoryResource()
        if not INVENTORY_RESOURCE then
            print(('^1[%s]^7 Nie znaleziono inventory resource. Ustaw Config.InventoryApiResource lub uruchom jeden z: %s'):format(RESOURCE_NAME, table.concat(Config.InventoryFallbackResources or {}, ', ')))
            return
        end

        print(('^2[%s]^7 Inventory hooked into: %s'):format(RESOURCE_NAME, INVENTORY_RESOURCE))
        debugPrint('Crafting resource started.')
        return
    end

    if resourceName == Config.InventoryApiResource or resourceName == 'vorp_inventory' or resourceName == 'vorp_inventoryApi' then
        INVENTORY_RESOURCE = resolveInventoryResource()
        if INVENTORY_RESOURCE then
            print(('^2[%s]^7 Inventory detected after start: %s'):format(RESOURCE_NAME, INVENTORY_RESOURCE))
        end
    end
end)
