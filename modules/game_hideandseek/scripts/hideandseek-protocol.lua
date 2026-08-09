HideAndSeekProtocol = {}

-- Must match HIDEANDSEEK_EXTENDED_OPCODES in the server's
-- data/creaturescripts/scripts/others/extendedopcode.lua
HideAndSeekProtocol.RecvOpcode = {
    TeamHide = 40,
    TeamSeek = 41,
    RoleCleared = 42,
    HiddenPlayersUpdate = 43,
}

HideAndSeekProtocol.SendOpcode = {
    DisguiseNext = 44,
    DisguisePrev = 45,
}

-- creature IDs the server currently reports as hidden (disguised) players
local hiddenIds = {}
-- original creature names must be restored explicitly when the hidden flag is
-- cleared; setName("") permanently changes the client-side Creature object
local originalNames = {}
-- this client's own current role for the active round: "hide" | "seek" | nil
local myRole = nil

local function applyHiddenState(creatureId, hidden)
    local creature = g_map.getCreatureById(creatureId)
    if not creature then
        if not hidden then
            originalNames[creatureId] = nil
        end
        return
    end

    if hidden then
        local currentName = creature:getName()
        if currentName and currentName ~= "" then
            originalNames[creatureId] = currentName
        end
        creature:setName("")
        creature:hideInformation(true)
    else
        creature:hideInformation(false)
        local originalName = originalNames[creatureId]
        if originalName then
            creature:setName(originalName)
        end
        originalNames[creatureId] = nil
    end
end

local function clearAllHiddenStates()
    for creatureId in pairs(hiddenIds) do
        applyHiddenState(creatureId, false)
    end
    hiddenIds = {}
    originalNames = {}
end

function HideAndSeekProtocol.isHiddenCreature(creatureId)
    return hiddenIds[creatureId] == true
end

-- A creature's hidden state can change (in either direction) while it's out of
-- this client's view: a hider can enter view after HiddenPlayersUpdate/RoleCleared
-- already fired (e.g. a seeker walking closer, or a hidden player un-hiding while
-- out of sight) — g_map.getCreatureById would have found nothing at broadcast
-- time, so applyHiddenState(..., false) was a no-op and the *next* Creature object
-- for that id starts life with m_hideInformation still true, permanently hiding
-- its name/health/mana bar for this client until reconnect. Re-sync to the
-- current authoritative state (hidden or not) every time a creature appears,
-- instead of only ever re-applying "hidden".
local function onCreatureAppear(creature)
    applyHiddenState(creature:getId(), HideAndSeekProtocol.isHiddenCreature(creature:getId()))
end

-- Cross-module entry point. Sandboxed modules only expose bare top-level
-- globals via modules.<name>.<func> (their tables/nested fields aren't
-- reachable from other modules' sandboxes) — see game_battle/battle.lua and
-- game_interface/gameinterface.lua for the callers.
function HideAndSeekIsHidden(creatureId)
    return HideAndSeekProtocol.isHiddenCreature(creatureId)
end

function HideAndSeekProtocol.init()
    connect(g_game, { onGameStart = HideAndSeekProtocol.connect, onGameEnd = HideAndSeekProtocol.disconnect })
    if g_game.isOnline() then
        HideAndSeekProtocol.connect()
    end
end

function HideAndSeekProtocol.terminate()
    HideAndSeekProtocol.disconnect()
    disconnect(g_game, { onGameStart = HideAndSeekProtocol.connect, onGameEnd = HideAndSeekProtocol.disconnect })
end

function HideAndSeekProtocol.connect()
    local protocol = g_game.getProtocolGame()
    if protocol then
        connect(protocol, { onExtendedOpcode = HideAndSeekProtocol.onExtendedOpcode })
    end
    connect(Creature, { onAppear = onCreatureAppear })

    local gameRootPanel = modules.game_interface.getRootPanel()
    g_keyboard.bindKeyDown('Shift+Left', HideAndSeekProtocol.sendDisguisePrev, gameRootPanel)
    g_keyboard.bindKeyDown('Shift+Right', HideAndSeekProtocol.sendDisguiseNext, gameRootPanel)
end

function HideAndSeekProtocol.disconnect()
    local protocol = g_game.getProtocolGame()
    if protocol then
        disconnect(protocol, { onExtendedOpcode = HideAndSeekProtocol.onExtendedOpcode })
    end
    disconnect(Creature, { onAppear = onCreatureAppear })

    local gameRootPanel = modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown('Shift+Left', gameRootPanel)
    g_keyboard.unbindKeyDown('Shift+Right', gameRootPanel)

    clearAllHiddenStates()
    myRole = nil
end

function HideAndSeekProtocol.onExtendedOpcode(protocol, opcode, buffer)
    if opcode == HideAndSeekProtocol.RecvOpcode.TeamHide then
        myRole = "hide"
        modules.game_textmessage.displayGameMessage("You are HIDING! Use Shift+Left and Shift+Right to change your disguise.")

    elseif opcode == HideAndSeekProtocol.RecvOpcode.TeamSeek then
        myRole = "seek"
        modules.game_textmessage.displayGameMessage("You are SEEKING! Aim a rune at a hidden player's tile.")

    elseif opcode == HideAndSeekProtocol.RecvOpcode.RoleCleared then
        myRole = nil
        -- RoleCleared is the authoritative end-of-event signal. Clear the
        -- visual disguise state here as well, so names and health/mana bars
        -- recover even if the following empty hidden-player update is lost.
        clearAllHiddenStates()

    elseif opcode == HideAndSeekProtocol.RecvOpcode.HiddenPlayersUpdate then
        local newIds = {}
        if buffer and buffer ~= "" then
            for _, idStr in ipairs(string.split(buffer, ";")) do
                local id = tonumber(idStr)
                if id then newIds[id] = true end
            end
        end

        -- un-hide anyone no longer in the new list, hide everyone in it —
        -- full-replace semantics, matches the server's broadcast contract
        for creatureId in pairs(hiddenIds) do
            if not newIds[creatureId] then
                applyHiddenState(creatureId, false)
            end
        end
        for creatureId in pairs(newIds) do
            applyHiddenState(creatureId, true)
        end

        hiddenIds = newIds
    end
end

function HideAndSeekProtocol.sendDisguiseNext()
    if myRole ~= "hide" then return end
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(HideAndSeekProtocol.SendOpcode.DisguiseNext, "")
    end
end

function HideAndSeekProtocol.sendDisguisePrev()
    if myRole ~= "hide" then return end
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(HideAndSeekProtocol.SendOpcode.DisguisePrev, "")
    end
end
