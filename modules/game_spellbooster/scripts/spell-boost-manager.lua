SpellBoosterManager = {}

function SpellBoosterManager.requestSpellPrice(spellName)
    SpellBoosterProtocol.sendSpellPriceRequest(spellName)
end

function SpellBoosterManager.confirmBoostSpell(spellName)
    SpellBoosterProtocol.confirmBoostSpell(spellName)
end

function SpellBoosterManager.handleOpenDialog(spellData)
    local data = spellData or SpellBoosterProtocol.getSpellDefinitions()
    if data and SpellBoosterUI then
        SpellBoosterUI.openDialog(data)
        return
    end
    print('BOOST: spell definitions are nil (Dialog noch nicht geladen?)')
end

function SpellBoosterManager.handlePriceResponse(price)
    if SpellBoosterUI then
        SpellBoosterUI.openBoostConfirmDialog(price)
    end
end

function SpellBoosterManager.handleBoostError(errorMessage)
    if SpellBoosterUI then
        SpellBoosterUI.displayBuyError(errorMessage)
    end
end

function SpellBoosterManager.handleCloseDialog()
    if SpellBoosterUI then
        SpellBoosterUI.closeDialog()
    end
end

function SpellBoosterManager.getPlayerSpellLevels()
    local spellLevels = SpellBoosterProtocol.getPlayerSpellLevels()

    if not spellLevels then
        print('spell levels are nil', spellLevels)
    end

    return SpellBoosterProtocol.getPlayerSpellLevels()
end

function SpellBoosterManager.getSpellDefinitions()
    return SpellBoosterProtocol.getSpellDefinitions()
end
