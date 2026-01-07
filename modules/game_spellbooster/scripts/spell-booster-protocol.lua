SpellBoosterProtocol = {}

local OPCODE_SPELL_BOOSTER_DIALOG = 200

SpellBoosterProtocol.SendOpcode = {
    BoostSpell = 0x16,
}

function SpellBoosterProtocol.registerOpcode()

    local protocol = g_game.getProtocolGame()
    if protocol and protocol:isConnected() then
        SpellBoosterProtocol.connect()
    end

    connect(g_game, {
        onGameStart = SpellBoosterProtocol.connect,
        onGameEnd = SpellBoosterProtocol.disconnect
    })
end

function SpellBoosterProtocol.connect()
    local protocol = g_game.getProtocolGame()
    if protocol then
        connect(protocol, { onExtendedOpcode = SpellBoosterProtocol.onExtendedOpcode })
    else
        print("[SPELL_BOOSTER_PROTOCOL] ERROR: No protocol available")
    end
end

function SpellBoosterProtocol.disconnect()
    print("[SPELL_BOOSTER_PROTOCOL] Disconnecting...")
    local protocol = g_game.getProtocolGame()
    if protocol then
        disconnect(protocol, { onExtendedOpcode = SpellBoosterProtocol.onExtendedOpcode })
    end
end

function SpellBoosterProtocol.onExtendedOpcode(protocol, opcode, buffer)
    if opcode == OPCODE_SPELL_BOOSTER_DIALOG then
        local spellData = json.decode(buffer)

        if spellData and SpellBoosterUI then
            SpellBoosterUI.openDialog(spellData)

        end
    end
end

function SpellBoosterProtocol.terminate()
    SpellBoosterProtocol.disconnect()
    disconnect(g_game, {
        onGameStart = SpellBoosterProtocol.connect,
        onGameEnd = SpellBoosterProtocol.disconnect
    })
end