function init()
    SpellBoosterProtocol.registerOpcode()
    SpellBoosterUI.init()

    if modules.client_topmenu then
        modules.client_topmenu.addRightGameToggleButton("spellBoostButton", tr("Spell Boosts"), "/images/topbarButtons/spell_boosts", SpellBoosterUI.toggle)
    end
end

function terminate()

    if SpellBoosterProtocol then
        SpellBoosterProtocol.terminate()
        SpellBoosterUI.terminate()
    end
end