AutoLootUI = {}

local MAX_RESULTS = 50

local mainWindow = nil
local building = false
local selectedIndex = nil
local backpackQuery = ''
local browsingBackpacks = false
local itemQuery = ''

local namesById = nil

function AutoLootUI.init()
    g_ui.importStyle('/modules/game_autoloot/ui/autoloot-main')
    g_ui.importStyle('/modules/game_autoloot/ui/autoloot-rows')

    connect(g_game, { onGameEnd = AutoLootUI.closeDialog })
end

function AutoLootUI.terminate()
    disconnect(g_game, { onGameEnd = AutoLootUI.closeDialog })
    AutoLootUI.closeDialog()
end

function AutoLootUI.closeDialog()
    if mainWindow then
        mainWindow:destroy()
        mainWindow = nil
    end
    selectedIndex = nil
    backpackQuery = ''
    browsingBackpacks = false
    itemQuery = ''
end

function AutoLootUI.toggle()
    if mainWindow then
        AutoLootUI.closeDialog()
        return
    end

    if not AutoLootManager.isPremium() then
        displayInfoBox(tr('Auto Loot'), tr('Auto Loot is only available for premium accounts.'))
        return
    end

    AutoLootUI.openDialog()
end

function AutoLootUI.openDialog()
    local rootPanel = modules.game_interface.getRootPanel()
    if not rootPanel then
        return
    end

    AutoLootUI.closeDialog()

    mainWindow = g_ui.createWidget('AutoLootDialog', rootPanel)
    mainWindow.onDestroy = function()
        mainWindow = nil
    end

    building = true
    mainWindow:recursiveGetChildById('enabledCheck'):setChecked(AutoLootManager.isEnabled())
    building = false

    if #AutoLootManager.getSettings().rules > 0 then
        selectedIndex = 1
    end
    AutoLootUI.refresh()

    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
end

function AutoLootUI.onEnabledChange(checked)
    if building then
        return
    end
    AutoLootManager.setEnabled(checked)
end

local function getNamesById()
    if not namesById then
        namesById = {}
        for _, entry in ipairs(AutoLootItemData) do
            namesById[entry.id] = entry.name
        end
    end
    return namesById
end

local function getItemName(itemId)
    local name = getNamesById()[itemId] or 'Item #' .. itemId
    return name:sub(1, 1):upper() .. name:sub(2)
end

-- backpacks of the same type are told apart by a number, e.g. "Purple backpack 2"
local function getRuleName(rule)
    local name = getItemName(rule.backpack)
    if AutoLootManager.hasMultipleRules(rule.backpack) then
        name = name .. ' ' .. (rule.number or 1)
    end
    return name
end

-- only backpacks the player really carries that are not used by a rule yet, so a backpack can be added
-- as often as the player owns it
local function getOwnedBackpackEntries()
    local entries = {}
    for id, owned in pairs(AutoLootManager.getOwnedBackpackCounts()) do
        if owned > AutoLootManager.getRuleCount(id) then
            table.insert(entries, { id = id, name = getItemName(id) })
        end
    end
    table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
    return entries
end

-- every word of the query has to occur in the name, names starting with the query come first
local function search(entries, query, isHidden)
    local words = query:lower():split(' ')
    local prefixMatches = {}
    local otherMatches = {}

    for _, entry in ipairs(entries) do
        if not isHidden(entry.id) then
            local name = entry.name:lower()
            local matches = true
            for _, word in ipairs(words) do
                if word ~= '' and not name:find(word, 1, true) then
                    matches = false
                    break
                end
            end

            if matches then
                if words[1] and name:find(words[1], 1, true) == 1 then
                    table.insert(prefixMatches, entry)
                else
                    table.insert(otherMatches, entry)
                end
            end
        end
    end

    local results = {}
    for _, list in ipairs({ prefixMatches, otherMatches }) do
        for _, entry in ipairs(list) do
            if #results >= MAX_RESULTS then
                return results
            end
            table.insert(results, entry)
        end
    end
    return results
end

local function createRow(list, itemId, buttonText, onClick)
    local row = g_ui.createWidget('AutoLootItemRow', list)
    row:getChildById('icon'):setItemId(itemId)
    row:getChildById('nameLabel'):setText(getItemName(itemId))

    local button = row:getChildById('removeButton')
    button:setText(buttonText)
    button.onClick = onClick
    return row
end

local function clearSearch(searchId)
    building = true
    mainWindow:recursiveGetChildById(searchId):clearText()
    building = false
end

function AutoLootUI.onBackpackSearch(text)
    if building then
        return
    end
    backpackQuery = text:trim()
    AutoLootUI.refresh()
end

-- the field may already have the focus when the window opens, then a click raises no focus event
function AutoLootUI.onBackpackSearchClick()
    if building or not mainWindow or browsingBackpacks then
        return
    end

    AutoLootUI.startBrowsingBackpacks()
end

-- Lists the backpacks the player has. The server reports them, no container has to be opened; the list
-- refreshes when the answer arrives.
function AutoLootUI.startBrowsingBackpacks()
    browsingBackpacks = true
    AutoLootManager.requestBackpacks()
    AutoLootUI.refresh()
end

function AutoLootUI.onBackpacksChanged()
    if mainWindow and (browsingBackpacks or backpackQuery ~= '') then
        AutoLootUI.refresh()
    end
end

-- focusing the search field lists every backpack the player has, leaving it (with no text) goes back
-- to the configured backpacks; the delay keeps the list alive long enough for a click on "Add"
function AutoLootUI.onBackpackSearchFocus(focused)
    if building or not mainWindow then
        return
    end

    if focused then
        AutoLootUI.startBrowsingBackpacks()
        return
    end

    scheduleEvent(function()
        if not mainWindow then
            return
        end
        local searchField = mainWindow:recursiveGetChildById('backpackSearch')
        if not searchField:isFocused() and backpackQuery == '' then
            browsingBackpacks = false
            AutoLootUI.refresh()
        end
    end, 300)
end

function AutoLootUI.onItemSearch(text)
    if building then
        return
    end
    itemQuery = text:trim()
    AutoLootUI.refresh()
end

function AutoLootUI.removeSelectedBackpack()
    if not selectedIndex then
        return
    end

    AutoLootManager.removeRule(selectedIndex)
    local count = #AutoLootManager.getSettings().rules
    selectedIndex = count > 0 and math.min(selectedIndex, count) or nil
    AutoLootUI.refresh()
end

function AutoLootUI.selectBackpack(index)
    selectedIndex = index
    AutoLootUI.refresh()
end

function AutoLootUI.buildBackpacks(rules)
    local list = mainWindow:recursiveGetChildById('backpackList')
    local emptyLabel = mainWindow:recursiveGetChildById('emptyBackpacks')
    list:destroyChildren()

    if browsingBackpacks or backpackQuery ~= '' then
        local results = search(getOwnedBackpackEntries(), backpackQuery, function() return false end)
        for _, entry in ipairs(results) do
            createRow(list, entry.id, tr('Add'), function()
                AutoLootManager.addRule(entry.id)
                selectedIndex = #AutoLootManager.getSettings().rules
                backpackQuery = ''
                browsingBackpacks = false
                clearSearch('backpackSearch')
                AutoLootUI.refresh()
            end)
        end

        emptyLabel:setText(tr('No backpack found.'))
        emptyLabel:setVisible(#results == 0)
        return
    end

    for index, rule in ipairs(rules) do
        local row = g_ui.createWidget('AutoLootBackpackRow', list)
        row:getChildById('icon'):setItemId(rule.backpack)
        row:getChildById('nameLabel'):setText(getRuleName(rule))
        row:getChildById('countLabel'):setText(#rule.items)
        row:setOn(index == selectedIndex)
        row.onClick = function()
            AutoLootUI.selectBackpack(index)
            return true
        end
    end

    emptyLabel:setText(tr('No containers yet. Search one above.'))
    emptyLabel:setVisible(#rules == 0)
end

function AutoLootUI.buildItems(rules)
    local list = mainWindow:recursiveGetChildById('itemList')
    local emptyLabel = mainWindow:recursiveGetChildById('emptyItems')
    local title = mainWindow:recursiveGetChildById('itemsTitle')
    list:destroyChildren()

    local rule = selectedIndex and rules[selectedIndex]

    mainWindow:recursiveGetChildById('itemSearch'):setEnabled(rule ~= nil)
    mainWindow:recursiveGetChildById('removeBackpackButton'):setEnabled(rule ~= nil)

    if not rule then
        title:setText(tr('Items'))
        emptyLabel:setText(tr('Add a backpack first.'))
        emptyLabel:setVisible(true)
        return
    end

    title:setText(tr('Items for %s', getRuleName(rule)))

    if itemQuery ~= '' then
        local results = search(AutoLootItemData, itemQuery, AutoLootManager.isItemAssigned)
        for _, entry in ipairs(results) do
            createRow(list, entry.id, tr('Add'), function()
                AutoLootManager.addRuleItem(selectedIndex, entry.id)
                itemQuery = ''
                clearSearch('itemSearch')
                AutoLootUI.refresh()
            end)
        end

        emptyLabel:setText(tr('No item found.'))
        emptyLabel:setVisible(#results == 0)
        return
    end

    for _, itemId in ipairs(rule.items) do
        createRow(list, itemId, tr('Remove'), function()
            AutoLootManager.removeRuleItem(selectedIndex, itemId)
            AutoLootUI.refresh()
        end)
    end

    emptyLabel:setText(tr('No items yet. Search one above.'))
    emptyLabel:setVisible(#rule.items == 0)
end

function AutoLootUI.refresh()
    if not mainWindow then
        return
    end

    local rules = AutoLootManager.getSettings().rules
    AutoLootUI.buildBackpacks(rules)
    AutoLootUI.buildItems(rules)
end
