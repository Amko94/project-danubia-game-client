SpellBoosterUI = {}

local mainWindow = nil
local currentSpellName = nil
local currentCategory = 0

function SpellBoosterUI.init()
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-main')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-container')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-confirm-dialog')

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
        currentSpellName = nil
        mainWindow = nil
    else
        print('false')
    end
end

function SpellBoosterUI.openBoostConfirmDialog(price)
    local rootPanel = modules.game_interface.getRootPanel()

    if not rootPanel then
        print("ERROR: Could not get root panel")
        return
    end

    if rootPanel:getChildById('spellBoosterConfirmDialog') then
        return
    end

    local confirmDialog = g_ui.createWidget("SpellBoosterConfirmDialog", rootPanel)
    if not confirmDialog then
        print("ERROR: Could not create SpellBoosterConfirmDialog")
        return
    end

    confirmDialog:getChildById("spellNameLabel"):setText(currentSpellName)
    confirmDialog:getChildById("costLabel"):setText("Cost: " .. price .. " gold coins")
    print('befehl vor setid...', currentSpellName)
    confirmDialog:setId(currentSpellName)

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
end

function SpellBoosterUI.getEmptyProgressBar(spell)
    local levels = #spell.spellBoostLevels
    local basePath = "/images/custom-vegura/"

    return basePath
            .. "empty-"
            .. levels
            .. "level-bar.png"
end

function SpellBoosterUI.buildSpellContainers(spells)
    local spellList = mainWindow:getChildById('spellList')
    spellList:destroyChildren()

    for i, spell in ipairs(spells) do


        local success, spellData = pcall(function()
            return Spells.getSpellByName(spell.spellName)
        end)

        if not success or not spellData then
            print("WARNING: Spell '" .. spell.spellName .. "' nicht in SpellInfo gefunden - skippe")
            goto continue
        end

        local success2, _ = pcall(function()
            local container = g_ui.createWidget("SpellContainer", spellList)

            if container then
                container:setId(spell.spellName)
                container.spellType = spell.group or "attack"

                local iconWidget = container:recursiveGetChildById('spellIcon')
                local progressBar = container:recursiveGetChildById('spellProgressBar')

                local progressPngUrl = SpellBoosterUI.getEmptyProgressBar(spell)

                progressBar:setImageSource(progressPngUrl)

                if iconWidget and spellData.icon then
                    local iconKey = spellData.icon
                    local iconInfo = SpellIcons[iconKey]

                    if iconInfo then
                        local clientId = iconInfo[1]
                        local profile = 'Default'
                        local iconFile = SpelllistSettings[profile].iconFile
                        local imageClip = Spells.getImageClip(clientId, profile)

                        iconWidget:setImageSource(iconFile)
                        iconWidget:setImageClip(imageClip)
                        iconWidget:setSize({ width = 48, height = 48 })
                    end
                end

                local nameLabel = container:getChildById('spellName')
                local wordsLabel = container:getChildById('spellWords')
                if nameLabel then
                    nameLabel:setText(spell.spellName or "Unknown")
                end

                if wordsLabel then
                    wordsLabel:setText(spell.words or "Unknown")
                end
            end
        end)

        if not success2 then
            print("ERROR: Failed to create container for spell '" .. spell.name .. "'")
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
    local buttonMap = { [0] = "all", [1] = "attack", [2] = "healing", [3] = "support" }
    for catId, objId in pairs(buttonMap) do
        local btn = mainWindow:recursiveGetChildById(objId)
        if btn then
            btn:setOn(currentCategory == catId)
        end
    end
end

function SpellBoosterUI.displayBuyError(errorMessage)
    local errorLabel = mainWindow:recursiveGetChildById('errorMessage')
    errorLabel:setText(errorMessage)
end

function SpellBoosterUI.updateFilterSpellList()
    if not mainWindow then
        return
    end

    local spellList = mainWindow:getChildById('spellList')
    local containers = spellList:getChildren()

    for _, container in ipairs(containers) do
        local spellType = container.spellType or "attack"

        local typeToCategory = {
            ['attack'] = 1,
            ['healing'] = 2,
            ['support'] = 3
        }

        local spellCategory = typeToCategory[spellType:lower()] or "attack"

        local shouldShow = (currentCategory == 0) or (currentCategory == spellCategory)
        container:setVisible(shouldShow)
    end
end