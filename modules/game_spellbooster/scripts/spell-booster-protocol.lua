SpellBoosterProtocol = {}

local SEND_SPELL_BOOST_OPCODES = {
    SPELL_PRICE_REQUEST = 30,
    CONFIRM_BOOST_SPELL = 32
}

local RECEIVED_SPELL_BOOST_OPCODES = {
    OPEN_BOOSTER_DIALOG = 200,
    SPELL_PRICE_RESPONSE = 31,

    NO_ENOUGH_MONEY = 103,
    MISSING_TOME_OF_SPELL_MASTERY = 104
}

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
    if opcode == RECEIVED_SPELL_BOOST_OPCODES.OPEN_BOOSTER_DIALOG then
        local spellData = json.decode(buffer)

        for _, spell in ipairs(spellData) do
            print("Id:", spell.id)
            print("SpellName:", spell.spellName)
            print("RequiredCharacterLevel:", spell.requiredLevel)
            print("Group:", spell.group)
            

        end

        SpellBoosterManager.handleOpenDialog(spellData)
    end

    if opcode == RECEIVED_SPELL_BOOST_OPCODES.SPELL_PRICE_RESPONSE then
        local price = json.decode(buffer)
        SpellBoosterManager.handlePriceResponse(price)
    end

    if opcode == RECEIVED_SPELL_BOOST_OPCODES.SPELL_PRICE_RESPONSE then
        local price = json.decode(buffer)
        SpellBoosterManager.handlePriceResponse(price)
    end

    if opcode == RECEIVED_SPELL_BOOST_OPCODES.NO_ENOUGH_MONEY then
        SpellBoosterManager.handleBoostError('No enough gold')
    end

    if opcode == RECEIVED_SPELL_BOOST_OPCODES.MISSING_TOME_OF_SPELL_MASTERY then
        SpellBoosterManager.handleBoostError('You need a tome of spell mastery in your backpack')
    end
end

function SpellBoosterProtocol.terminate()
    SpellBoosterProtocol.disconnect()
    disconnect(g_game, {
        onGameStart = SpellBoosterProtocol.connect,
        onGameEnd = SpellBoosterProtocol.disconnect
    })
end

function SpellBoosterProtocol.SendSpellPriceRequest(spellName)
    local protocol = g_game.getProtocolGame()
    if protocol then

        protocol:sendExtendedOpcode(SEND_SPELL_BOOST_OPCODES.SPELL_PRICE_REQUEST, spellName)
    end
end

function SpellBoosterProtocol.ConfirmBoostSpell(spellName)
    print(spellName, '<-- Spellname')
    local protocol = g_game.getProtocolGame()
    if protocol then

        protocol:sendExtendedOpcode(SEND_SPELL_BOOST_OPCODES.CONFIRM_BOOST_SPELL, spellName)
    end
end
