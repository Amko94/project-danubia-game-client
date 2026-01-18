SpellBoosterManager = {}

function SpellBoosterManager.requestSpellPrice(spellName)
    SpellBoosterProtocol.SendSpellPriceRequest(spellName)
end

function SpellBoosterManager.confirmBoostSpell(spellName)
    SpellBoosterProtocol.ConfirmBoostSpell(spellName)
end

function SpellBoosterManager.handleOpenDialog(spellData)
    if spellData and SpellBoosterUI then
        SpellBoosterUI.openDialog(spellData)
    end
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