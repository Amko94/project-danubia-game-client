function init()
    SpellBoosterProtocol.registerOpcode()
    SpellBoosterUI.init()
end

function terminate()

    if SpellBoosterProtocol then
        SpellBoosterProtocol.terminate()
        SpellBoosterUI.terminate()
    end
end