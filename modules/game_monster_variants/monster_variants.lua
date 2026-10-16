-- Minor/Major tiers are recognised from the server-assigned name prefix and get
-- an outfit shader (fire / violet energy). No gameplay is decided here.
local opcode = 204
local shaders = {['Minor '] = 'outfit_variant_minor', ['Major '] = 'outfit_variant_major'}
local tracked = {}
local enabled = false
local reapplying = false

local function tierOf(creature)
    if not creature:isMonster() then return nil end
    return shaders[creature:getName():sub(1, 6)]
end

-- tracked[id] = shader currently applied. getOutfit().shader is only filled in
-- when GameOutfitShaders is enabled, so never read it back: setOutfit fires
-- onOutfitChange and that would recurse forever.
local function setShader(creature, shader)
    tracked[creature:getId()] = shader or nil
    local outfit = creature:getOutfit()
    outfit.shader = shader or ''
    reapplying = true
    creature:setOutfit(outfit)
    reapplying = false
end

local function apply(creature)
    local shader = enabled and tierOf(creature) or nil
    if not shader or tracked[creature:getId()] == shader then return end
    setShader(creature, shader)
end

local function clear(creature)
    if tracked[creature:getId()] then setShader(creature, nil) end
end

local function forget(creature)
    tracked[creature:getId()] = nil
end

local function refreshAll(fn)
    local player = g_game.getLocalPlayer()
    if not player then return end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do fn(creature) end
end

local function stop()
    tracked = {}
    enabled = false
end

local function receive(protocol, receivedOpcode, buffer)
    local ok, value = pcall(json.decode, buffer)
    if not ok or type(value) ~= 'table' or type(value.enabled) ~= 'boolean' then return end
    enabled = value.enabled
    -- The initial map can arrive before or after the configuration packet.
    refreshAll(enabled and apply or clear)
end

-- The server may resend the outfit; the new outfit carries no shader, so reapply.
local function outfitChanged(creature)
    if reapplying then return end
    local shader = tracked[creature:getId()]
    if shader then setShader(creature, shader) end
end

function init()
    g_shaders.createOutfitShader('outfit_variant_minor', '/shaders/outfit_variant_vertex', '/shaders/outfit_variant_minor_fragment')
    g_shaders.createOutfitShader('outfit_variant_major', '/shaders/outfit_variant_vertex', '/shaders/outfit_variant_major_fragment')
    ProtocolGame.registerExtendedOpcode(opcode, receive)
    connect(Creature, {onAppear = apply, onDisappear = forget, onOutfitChange = outfitChanged})
    connect(g_game, {onGameEnd = stop})
end

function terminate()
    stop()
    ProtocolGame.unregisterExtendedOpcode(opcode)
    disconnect(Creature, {onAppear = apply, onDisappear = forget, onOutfitChange = outfitChanged})
    disconnect(g_game, {onGameEnd = stop})
end
