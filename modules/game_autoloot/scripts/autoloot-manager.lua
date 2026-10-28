AutoLootManager = {}

-- The looting itself runs on the server (data/lib/autoloot_manager.lua there): the client only keeps the
-- rules and sends them to the server at login and after every change.
local SYNC_CONFIG_OPCODE = 90
-- The backpacks the player carries are not read from open containers: the client asks the server (empty
-- buffer) and gets "<backpack id>,<amount>;<backpack id>,<amount>..." back.
local BACKPACKS_OPCODE = 91

local settings = { enabled = true, rules = {} }
local settingsFile = nil
local ownedBackpacks = {}

local function getSettingsFile()
    return '/settings/autoloot_' .. g_game.getCharacterName() .. '.json'
end

local function onBackpacks(protocol, opcode, buffer)
    local counts = {}
    for entry in (buffer or ''):gmatch('[^;]+') do
        local id, amount = entry:match('^(%d+),(%d+)$')
        if id then
            counts[tonumber(id)] = tonumber(amount)
        end
    end
    ownedBackpacks = counts

    if AutoLootUI and AutoLootUI.onBackpacksChanged then
        AutoLootUI.onBackpacksChanged()
    end
end

function AutoLootManager.init()
    ProtocolGame.registerExtendedOpcode(BACKPACKS_OPCODE, onBackpacks)
    connect(g_game, {
        onGameStart = AutoLootManager.onGameStart,
        onGameEnd = AutoLootManager.onGameEnd
    })

    if g_game.isOnline() then
        AutoLootManager.onGameStart()
    end
end

function AutoLootManager.terminate()
    ProtocolGame.unregisterExtendedOpcode(BACKPACKS_OPCODE)
    disconnect(g_game, {
        onGameStart = AutoLootManager.onGameStart,
        onGameEnd = AutoLootManager.onGameEnd
    })
end

function AutoLootManager.onGameStart()
    AutoLootManager.load()
    AutoLootManager.sync()
end

function AutoLootManager.onGameEnd()
    settings = { enabled = true, rules = {} }
    ownedBackpacks = {}
    settingsFile = nil
end

function AutoLootManager.load()
    settingsFile = getSettingsFile()
    settings = { enabled = true, rules = {} }

    if not g_resources.fileExists(settingsFile) then
        return
    end

    local status, result = pcall(function()
        return json.decode(g_resources.readFileContents(settingsFile))
    end)
    if not status or type(result) ~= 'table' then
        return g_logger.error('Error while reading auto loot settings. Details: ' .. tostring(result))
    end

    settings.enabled = result.enabled ~= false
    settings.rules = result.rules or {}
end

-- Sends the rules to the server as "<backpack>,<number>,<item>,<item>...;<next rule>". Nothing is sent
-- for a disabled Auto Loot, so the server drops its copy and stops looting.
function AutoLootManager.sync()
    local protocol = g_game.getProtocolGame()
    if not protocol then
        return
    end

    local rules = {}
    if settings.enabled then
        for _, rule in ipairs(settings.rules) do
            local values = { rule.backpack, rule.number or 1 }
            for _, itemId in ipairs(rule.items) do
                table.insert(values, itemId)
            end
            table.insert(rules, table.concat(values, ','))
        end
    end

    protocol:sendExtendedOpcode(SYNC_CONFIG_OPCODE, table.concat(rules, ';'))
end

function AutoLootManager.save()
    if not settingsFile then
        return
    end

    local status, result = pcall(function() return json.encode(settings, 2) end)
    if not status then
        return g_logger.error('Error while saving auto loot settings. Details: ' .. result)
    end
    g_resources.writeFileContents(settingsFile, result)

    AutoLootManager.sync()
end

function AutoLootManager.getSettings()
    return settings
end

function AutoLootManager.isEnabled()
    return settings.enabled
end

-- Auto Loot is a premium feature (the server checks it as well). On protocol 8.60 the game connection does
-- not tell the client about premium (LocalPlayer:isPremium() stays false), the days only come with the
-- character list at login (65535 = free premium on the server).
function AutoLootManager.isPremium()
    local player = g_game.getLocalPlayer()
    if player and player:isPremium() then
        return true
    end

    local account = G and G.characterAccount
    return account ~= nil and (account.premDays or 0) > 0
end

function AutoLootManager.setEnabled(enabled)
    settings.enabled = enabled
    AutoLootManager.save()
end

-- A rule is { backpack = <client id of the target backpack>, number = n, items = { <client id>, ... } }
-- Two backpacks of the same type cannot be told apart, so a rule targets the n-th backpack of its type.
-- The server counts them: the equipped backpack first, then the ones inside it in slot order. The number
-- is never reused or renumbered when another rule is removed.
function AutoLootManager.addRule(backpackId)
    local number = 1
    for _, rule in ipairs(settings.rules) do
        if rule.backpack == backpackId then
            number = math.max(number, (rule.number or 1) + 1)
        end
    end
    table.insert(settings.rules, { backpack = backpackId, number = number, items = {} })
    AutoLootManager.save()
    return true
end

function AutoLootManager.hasMultipleRules(backpackId)
    return AutoLootManager.getRuleCount(backpackId) > 1
end

function AutoLootManager.removeRule(index)
    table.remove(settings.rules, index)
    AutoLootManager.save()
end

function AutoLootManager.addRuleItem(index, itemId)
    local rule = settings.rules[index]
    if not rule then
        return false
    end
    -- an item can only belong to one backpack
    if AutoLootManager.isItemAssigned(itemId) then
        return false
    end
    table.insert(rule.items, itemId)
    AutoLootManager.save()
    return true
end

function AutoLootManager.isItemAssigned(itemId)
    for _, rule in ipairs(settings.rules) do
        for _, id in ipairs(rule.items) do
            if id == itemId then
                return true
            end
        end
    end
    return false
end

function AutoLootManager.removeRuleItem(index, itemId)
    local rule = settings.rules[index]
    if not rule then
        return
    end
    for i, id in ipairs(rule.items) do
        if id == itemId then
            table.remove(rule.items, i)
            break
        end
    end
    AutoLootManager.save()
end

-- Asks the server which backpacks the player carries, the answer arrives in onBackpacks.
function AutoLootManager.requestBackpacks()
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(BACKPACKS_OPCODE, '')
    end
end

-- Backpacks the player carries as { [item id] = amount }, as last reported by the server: the equipped
-- one plus every container inside it.
function AutoLootManager.getOwnedBackpackCounts()
    return ownedBackpacks
end

function AutoLootManager.getRuleCount(backpackId)
    local count = 0
    for _, rule in ipairs(settings.rules) do
        if rule.backpack == backpackId then
            count = count + 1
        end
    end
    return count
end
