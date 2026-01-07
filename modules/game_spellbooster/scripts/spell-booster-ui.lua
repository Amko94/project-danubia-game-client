SpellBoosterUI = {}

local mainWindow = nil
local currentCategory = 0

function SpellBoosterUI.init()
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-booster-main')
    g_ui.importStyle('/modules/game_spellbooster/ui/spell-container')

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
    else
        print('false')
    end
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

function SpellBoosterUI.buildSpellContainers(spells)
    local spellList = mainWindow:getChildById('spellList')
    spellList:destroyChildren()

    for i, spell in ipairs(spells) do

        local success, spellData = pcall(function()
            return Spells.getSpellByName(spell.name)
        end)

        if not success or not spellData then
            print("WARNING: Spell '" .. spell.name .. "' nicht in SpellInfo gefunden - skippe")
            goto continue
        end

        local success2, _ = pcall(function()
            local container = g_ui.createWidget("SpellContainer", spellList)

            if container then
                -- Speichere den type auf dem container
                container:setId(spell.name)  -- optional, für debugging
                container.spellType = spell.type or "attack"  -- Speichere type direkt

                local iconWidget = container:recursiveGetChildById('spellIcon')

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
                    nameLabel:setText(spell.name or "Unknown")
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