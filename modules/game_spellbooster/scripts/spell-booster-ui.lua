SpellBoosterUI = {}

local mainWindow = nil
local confirmDialog = nil
local currentSpellName = nil
local currentCategory = 1
SpellBoosterUI.tooltip = nil

local boostTypeIcons = {
    [1] = "/images/custom-vegura/reduce-mana-cost.png",
    [2] = "/images/custom-vegura/increase-duration.png",
    [3] = "/images/custom-vegura/increase-damage.png",
    [4] = "/images/custom-vegura/increase-speed.png",
    [5] = "/images/custom-vegura/increase-range.png",
    [6] = "/images/custom-vegura/increase-monster-summon.png",
    [7] = "/images/custom-vegura/increase-healing.png",
    [8] = "/images/custom-vegura/increase-rune-amount.png",
    [9] = "/images/custom-vegura/reduce-cooldown.png",
    [10] = "/images/custom-vegura/increase-area-of-effect.png",
    [11] = "/images/custom-vegura/increase-conjure-amount.png"
}

local function normalizeCategory(group)
    if type(group) == "number" then
        return group
    end

    local num = tonumber(group)
    if num then
        return num
    end

    if type(group) ~= "string" then
        return nil
    end

    local key = group:lower()
    local map = {
        attack = 1,
        healing = 2,
        support = 3,
        conjure = 4
    }
    return map[key]
end

function SpellBoosterUI.init()
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-main')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-container')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-confirm-dialog')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-tool-tip')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-level-row')

    connect(g_game, {
        onGameEnd = SpellBoosterUI.onGameEnd,
        onGameStart = SpellBoosterUI.onGameStart
    })
end

function SpellBoosterUI.onGameEnd()
    SpellBoosterUI.closeDialog()
end

function SpellBoosterUI.terminate()
    disconnect(g_game, {
        onGameEnd = SpellBoosterUI.onGameEnd,
        onGameStart = SpellBoosterUI.onGameStart
    })
    SpellBoosterUI.closeDialog()
end

function SpellBoosterUI.closeDialog()
    if mainWindow then
        mainWindow:destroy()
        mainWindow = nil
    end

    if confirmDialog then
        confirmDialog:destroy()
        confirmDialog = nil
    end

    if SpellBoosterUI.tooltip then
        SpellBoosterUI.tooltip:destroy()
        SpellBoosterUI.tooltip = nil
    end

    local rootPanel = modules.game_interface.getRootPanel()
    if rootPanel then
        local dialogs = {
            'spellBoosterDialog',
            'spellBoosterConfirmDialog',
            'SpellBoosterTooltip'
        }

        for _, dialogId in ipairs(dialogs) do
            local dialog = rootPanel:getChildById(dialogId)
            if dialog then
                dialog:destroy()
            end
        end
    end

    currentSpellName = nil
end

function SpellBoosterUI.toggle()
    if mainWindow then
        SpellBoosterUI.closeDialog()
    else
        SpellBoosterUI.openDialog()
    end
end

function SpellBoosterUI.getTooltip()
    if SpellBoosterUI.tooltip then
        return SpellBoosterUI.tooltip
    end

    local rootPanel = modules.game_interface.getRootPanel()
    if not rootPanel then
        return nil
    end

    SpellBoosterUI.tooltip = g_ui.createWidget(
            'SpellBoosterTooltip',
            rootPanel
    )

    SpellBoosterUI.tooltip:hide()
    return SpellBoosterUI.tooltip
end

function SpellBoosterUI.buildLevelDescriptions(tooltip, container, currentLevel)
    if not tooltip then
        return
    end

    local levelContent = tooltip:recursiveGetChildById('levelContent')
    if not levelContent then
        return
    end

    levelContent:destroyChildren()

    local highestLevelPerType = {}

    for i, levelData in ipairs(container.spellBoostLevels) do
        local levelIndex = levelData.index or i
        local t = tonumber(levelData.type)

        if t and levelIndex <= currentLevel then
            local currentHighest = highestLevelPerType[t] or 0
            if levelIndex > currentHighest then
                highestLevelPerType[t] = levelIndex
            end
        end
    end

    for i, levelData in ipairs(container.spellBoostLevels) do
        local row = g_ui.createWidget('SpellBoosterLevelRow', levelContent)

        local levelIndex = levelData.index or i
        local t = tonumber(levelData.type)

        local levelLabel = row:getChildById('levelLabel')
        local effectText = row:getChildById('effectText')
        local boostIcon = row:recursiveGetChildById('boostIcon')
        local activeIndicator = row:getChildById('activeIndicator')

        if boostIcon then
            local iconSource = t and boostTypeIcons[t] or nil
            if iconSource then
                boostIcon:setImageSource(iconSource)
                boostIcon:show()
            else
                boostIcon:hide()
            end
        end

        if levelLabel then
            levelLabel:setText("Lvl " .. levelIndex .. ":")
        end

        if effectText then
            effectText:setText(levelData.description or "No description")
        end

        local isActive = (t ~= nil) and (highestLevelPerType[t] == levelIndex)
        if activeIndicator then
            activeIndicator:setVisible(isActive)
        end
    end

    tooltip:setHeight(60 + (#container.spellBoostLevels * 21))
end

function SpellBoosterUI.showTooltip(container, currentLevel)
    local tooltip = SpellBoosterUI.getTooltip()
    if not tooltip then
        return
    end

    local headerSpellName = tooltip:recursiveGetChildById('spellName')

    if headerSpellName then
        headerSpellName:setText(container.spellName:getText())
    end

    local rect = container:getRect()
    local size = container:getSize()

    local x = rect.x + size.width + 8
    local y = rect.y
    SpellBoosterUI.buildLevelDescriptions(tooltip, container, currentLevel)
    tooltip:setPosition({ x = x, y = y })
    tooltip:show()
    tooltip:raise()
end

function SpellBoosterUI.hideTooltip()
    if SpellBoosterUI.tooltip then
        SpellBoosterUI.tooltip:hide()
    end
end

function SpellBoosterUI.openBoostConfirmDialog(price)
    local rootPanel = modules.game_interface.getRootPanel()
    if not rootPanel or confirmDialog then
        return
    end

    confirmDialog = g_ui.createWidget("SpellBoosterConfirmDialog", rootPanel)
    if not confirmDialog then
        return
    end

    confirmDialog.onDestroy = function()
        confirmDialog = nil
    end

    local spellNameLabel = confirmDialog:recursiveGetChildById("spellNameLabel")
    local costLabel = confirmDialog:recursiveGetChildById("costLabel")
    local errorLabel = confirmDialog:recursiveGetChildById("errorMessage")

    if not spellNameLabel then
        print("SpellBoosterConfirmDialog: spellNameLabel not found")
    end
    if not costLabel then
        print("SpellBoosterConfirmDialog: costLabel not found")
    end

    if spellNameLabel then
        spellNameLabel:setText(currentSpellName or "Unknown spell")
    end
    if costLabel then
        costLabel:setText("Cost: " .. tostring(price or "?") .. " gold coins")
    end
    if errorLabel then
        errorLabel:setText("")
    end

    confirmDialog:setId(currentSpellName or "unknown")

    confirmDialog:show()
    confirmDialog:raise()
    confirmDialog:focus()
end

function SpellBoosterUI.confirmBoost(spellName)
    SpellBoosterManager.confirmBoostSpell(spellName)
end

function SpellBoosterUI.requestSpellPrice(spellName)
    currentSpellName = spellName
    SpellBoosterManager.requestSpellPrice(spellName)
end

function SpellBoosterUI.openDialog(spells)
    if not spells then
        spells = SpellBoosterManager.getSpellDefinitions()
    end
    if not spells then
        print('BOOST: spell list missing (not received yet)')
        return
    end

    local rootPanel = modules.game_interface.getRootPanel()

    if not rootPanel then
        print("ERROR: Could not get root panel")
        return
    end

    if mainWindow then
        mainWindow:destroy()
        mainWindow = nil
    end

    mainWindow = g_ui.createWidget("SpellBoosterDialog", rootPanel)
    if not mainWindow then
        print("ERROR: Could not create SpellBoosterDialog")
        return
    end

    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()

    SpellBoosterUI.updateCategoryButtons()
    SpellBoosterUI.buildSpellContainers(spells)
    SpellBoosterUI.updateFilterSpellList()
end

function SpellBoosterUI.getProgressBar(spell, level)
    local levels = #spell.spellBoostLevels
    local basePath = "/images/custom-vegura/"

    if level == 0 then
        return basePath
                .. "empty-"
                .. levels
                .. "level-bar.png"
    end

    if level == #spell.spellBoostLevels then
        return basePath .. levels .. 'level-bar-completed.png'
    end

    return basePath .. levels .. 'level-bar-progress-' .. level .. '.png'

end

function SpellBoosterUI.buildSpellContainers(spells)
    local spellList = mainWindow:getChildById('spellList')
    spellList:destroyChildren()

    local spellLevels = SpellBoosterManager.getPlayerSpellLevels() or {}

    local spellLevelMap = {}
    for _, entry in pairs(spellLevels) do
        spellLevelMap[entry.spell] = entry.level
    end

    for _, spell in ipairs(spells) do
        local success, spellData = pcall(function()
            return Spells.getSpellByName(spell.spellName)
        end)
        if not success or not spellData then
            goto continue
        end

        local container = g_ui.createWidget("SpellContainer", spellList)
        if not container then
            goto continue
        end

        container:setId(spell.spellName)
        container.group = spell.group or "attack"
        container.spellCategory = normalizeCategory(container.group) or 1
        container.spellBoostLevels = spell.spellBoostLevels

        local level = spellLevelMap[spell.spellName] or 0

        local progressBar = container:recursiveGetChildById('spellProgressBar')
        if progressBar then
            local png = SpellBoosterUI.getProgressBar(spell, level)
            progressBar:setImageSource(png)
        end

        local boostButton = container:recursiveGetChildById('boostButton')
        if boostButton then
            local maxLevel = #spell.spellBoostLevels
            local completed = (level >= maxLevel)
            boostButton:setVisible(not completed)
            boostButton:setEnabled(not completed)
        end

        local iconWidget = container:recursiveGetChildById('spellIcon')
        if iconWidget and spellData.icon then
            local iconInfo = SpellIcons[spellData.icon]
            if iconInfo then
                local profile = 'Default'
                iconWidget:setImageSource(SpelllistSettings[profile].iconFile)
                iconWidget:setImageClip(Spells.getImageClip(iconInfo[1], profile))
            end
        end

        local nameLabel = container:getChildById('spellName')
        if nameLabel then
            nameLabel:setText(spell.spellName)
        end

        local wordsLabel = container:getChildById('spellWords')
        if wordsLabel then
            wordsLabel:setText(spell.words or "")
        end

        function container:onHoverChange(hovered)
            if hovered then
                local spellName = self:getId()
                local currentLevel = spellLevelMap[spellName] or 0
                SpellBoosterUI.showTooltip(self, currentLevel)
            else
                SpellBoosterUI.hideTooltip()
            end
        end

        :: continue ::
    end
end

function SpellBoosterUI.animateBoost(container, fromValue, toValue, duration)
    local boostBar = container:recursiveGetChildById('boostBar')
    if not boostBar then
        return
    end

    local startTime = g_clock.millis()

    local function step()
        local t = (g_clock.millis() - startTime) / duration
        if t >= 1 then
            boostBar:setValue(toValue)
            return
        end
        local value = fromValue + (toValue - fromValue) * t
        boostBar:setValue(value)
        scheduleEvent(step, 16)
    end

    step()
end

function SpellBoosterUI.filterByCategory(cat)
    currentCategory = cat
    SpellBoosterUI.updateCategoryButtons()
    SpellBoosterUI.updateFilterSpellList()
end

function SpellBoosterUI.updateCategoryButtons()
    if not mainWindow then
        return
    end
    local buttonMap = { [1] = "attack", [2] = "healing", [3] = "support", [4] = 'conjure' }
    for catId, objId in pairs(buttonMap) do
        local btn = mainWindow:recursiveGetChildById(objId)
        if btn then
            btn:setOn(currentCategory == catId)
        end
    end
end

function SpellBoosterUI.displayBuyError(errorMessage)

    if not confirmDialog then
        print('BOOST: confirmDialog is nil (Dialog noch nicht offen?)')
        return
    end

    local errorLabel = confirmDialog:recursiveGetChildById('errorMessage')
    if errorLabel then
        errorLabel:setText(errorMessage or "")
        errorLabel:show()
    else
        print('BOOST: errorLabel not found (id errorMessage?)')
    end
end

function SpellBoosterUI.updateFilterSpellList()
    if not mainWindow then
        return
    end

    local spellList = mainWindow:getChildById('spellList')
    local containers = spellList:getChildren()

    for _, container in ipairs(containers) do
        local spellCategory = container.spellCategory
        if not spellCategory then
            spellCategory = normalizeCategory(container.group) or 1
        end

        local shouldShow = currentCategory == 0 or
                currentCategory == spellCategory

        container:setVisible(shouldShow)
    end
end
