function init()
    SpellBoosterProtocol.registerOpcode()
    SpellBoosterUI.init()

    if modules.client_topmenu then
        modules.client_topmenu.addRightGameToggleButton("taskButton", tr("Spell Boosts"), "/images/topbuttons/spelllist", SpellBoosterUI.toggle)
    end
end

function terminate()

    if SpellBoosterProtocol then
        SpellBoosterProtocol.terminate()
        SpellBoosterUI.terminate()
    end
end