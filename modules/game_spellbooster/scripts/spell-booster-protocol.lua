SpellBoosterProtocol = {}

local OPCODE_SPELL_BOOSTER_DIALOG = 200

function SpellBoosterProtocol.registerOpcode()
    print("[SPELL_BOOSTER_PROTOCOL] Registering opcode handler...")

    local protocol = g_game.getProtocolGame()
    if protocol and protocol:isConnected() then
        print("[SPELL_BOOSTER_PROTOCOL] Game is online, connecting protocol...")
        SpellBoosterProtocol.connect()
    end

    connect(g_game, {
        onGameStart = SpellBoosterProtocol.connect,
        onGameEnd = SpellBoosterProtocol.disconnect
    })
end

function SpellBoosterProtocol.connect()
    print("[SPELL_BOOSTER_PROTOCOL] Connecting...")
    local protocol = g_game.getProtocolGame()
    if protocol then
        connect(protocol, { onExtendedOpcode = SpellBoosterProtocol.onExtendedOpcode })
        print("[SPELL_BOOSTER_PROTOCOL] Connected!")
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

        for i, spell in ipairs(spellData) do
            print(spell.name)
            print(spell.type)
            print(spell.words)
        end

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