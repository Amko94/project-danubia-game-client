BUY = 1
SELL = 2
CURRENCY = 'gold'
CURRENCY_DECIMAL = false
MAX_AMOUNT = 100
-- Matches the server's NPC default talkRadius (game-server/data/npc/lib/npcsystem/npchandler.lua:73):
-- trade should only be reachable within the same range NPC conversation itself works in.
TALK_RADIUS = 3

-- Must match game-server/data/creaturescripts/scripts/others/extendedopcode.lua's
-- NPCTRADE_EXTENDED_OPCODES table -- these numbers share one flat namespace with every other
-- feature using the extended-opcode channel (tasks, spell booster, hide and seek), so they
-- can't be picked independently on either side.
NPCTRADE_OPCODES = {
  REQUEST_ITEM_COUNT = 60,
  ITEM_COUNT_RESPONSE = 61,
}

npcWindow = nil
itemsPanel = nil
searchText = nil
setupPanel = nil
quantityScroll = nil
totalLabel = nil
tradeButton = nil
buyTab = nil
sellTab = nil
radioTabs = nil
radioItems = nil
initialized = false

tradeItems = {}
selectedItem = nil

shopDataByLowerName = {}
currentNpcName = nil

-- Fluid subtype values used by GameNewFluids (protocol 8.00).
local FLUID_SUBTYPES = {
  water = 1,
  mana = 2,
  beer = 3,
  oil = 4,
  blood = 5,
  slime = 6,
  mud = 7,
  lemonade = 8,
  milk = 9,
  wine = 10,
  life = 11,
  health = 11,
  rum = 13,
  juice = 14,
  coconut = 15,
  tea = 16,
  mead = 17
}

local function createShopItem(entry)
  -- Allow an explicit subtype in npcshopdata.lua and otherwise infer common vial
  -- contents from their display name/keyword. Empty vials keep subtype 0.
  if entry.id == 2006 or entry.id == 7490 then
    local subType = entry.subType
    if subType == nil then
      local description = ((entry.name or '') .. ' ' .. (entry.keyword or '')):lower()
      subType = 0
      for fluidName, fluidSubType in pairs(FLUID_SUBTYPES) do
        if description:find(fluidName, 1, true) then
          subType = fluidSubType
          break
        end
      end
    end
    return Item.create(entry.clientId, subType)
  end

  return Item.create(entry.clientId)
end
currentNpcCreature = nil

-- This module talks to NPCs purely via chat (the server's NPC shops use the classic
-- keyword system, not the binary shop protocol): opening the dialog and confirming a
-- trade send the exact same text a player would type manually ("trade", "buy 1 x", "yes").

function init()
  npcWindow = g_ui.displayUI('npctrade')
  npcWindow:setVisible(false)

  itemsPanel = npcWindow:recursiveGetChildById('itemsPanel')
  searchText = npcWindow:recursiveGetChildById('searchText')

  setupPanel = npcWindow:recursiveGetChildById('setupPanel')
  quantityScroll = setupPanel:getChildById('quantityScroll')
  quantityScroll.onMousePress = onQuantitySliderPress
  g_mouse.bindPressMove(quantityScroll, function(mousePos, mouseMoved)
    onQuantitySliderDrag(quantityScroll, mousePos, mouseMoved)
  end)
  local quantityValueDisplay = quantityScroll:getChildById('valueLabel')
  if quantityValueDisplay then
    quantityValueDisplay:setPhantom(true)
  end
  totalLabel = setupPanel:getChildById('total')
  tradeButton = npcWindow:recursiveGetChildById('tradeButton')

  buyTab = npcWindow:getChildById('buyTab')
  sellTab = npcWindow:getChildById('sellTab')

  radioTabs = UIRadioGroup.create()
  radioTabs:addWidget(buyTab)
  radioTabs:addWidget(sellTab)
  radioTabs:selectWidget(buyTab)
  radioTabs.onSelectionChange = onTradeTypeChange

  shopDataByLowerName = {}
  for npcName, data in pairs(NpcShopData or {}) do
    shopDataByLowerName[npcName:lower()] = data
  end

  connect(g_game, { onGameStart = connectExtendedOpcode,
                     onGameEnd = onGameEnd,
                     onTalk = onGameTalk })

  connect(LocalPlayer, { onPositionChange = checkNpcRange })

  modules.game_console.addFilter(onOutgoingChat)

  initialized = true
end

function terminate()
  initialized = false
  npcWindow:destroy()

  disconnectExtendedOpcode()

  disconnect(g_game, { onGameStart = connectExtendedOpcode,
                        onGameEnd = onGameEnd,
                        onTalk = onGameTalk })

  disconnect(LocalPlayer, { onPositionChange = checkNpcRange })

  modules.game_console.removeFilter(onOutgoingChat)
end

-- The count request/response ride the OTClientV8 "extended opcode" channel (a raw byte + a
-- free-form string, forwarded to Lua on both ends without needing new fixed protocol opcodes).
function connectExtendedOpcode()
  local protocol = g_game.getProtocolGame()
  if protocol then
    connect(protocol, { onExtendedOpcode = onExtendedOpcode })
  end
end

function disconnectExtendedOpcode()
  local protocol = g_game.getProtocolGame()
  if protocol then
    disconnect(protocol, { onExtendedOpcode = onExtendedOpcode })
  end
end

function onExtendedOpcode(protocol, opcode, buffer)
  if opcode ~= NPCTRADE_OPCODES.ITEM_COUNT_RESPONSE then return end

  local parts = buffer:split(';')
  local itemId = tonumber(parts[1])
  local count = tonumber(parts[2])
  if not itemId or not count then return end

  -- The response is async: only apply it if it's still about the item currently selected
  -- (the player may have clicked another item, or switched tabs, while it was in flight).
  if selectedItem and selectedItem.id == itemId and getCurrentTradeType() == SELL then
    applyOwnedCount(count)
  end
end

function applyOwnedCount(count)
  local maxAmount = math.max(1, math.min(getMaxAmount(), count))
  quantityScroll:setMaximum(maxAmount)
  if quantityScroll:getValue() > maxAmount then
    quantityScroll:setValue(maxAmount)
  end
end

function show()
  if g_game.isOnline() then
    if #tradeItems[BUY] > 0 then
      radioTabs:selectWidget(buyTab)
    else
      radioTabs:selectWidget(sellTab)
    end

    npcWindow:show()
    npcWindow:raise()
    npcWindow:focus()
  end
end

function hide()
  npcWindow:hide()

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  clearSelectedItem()

  searchText:clearText()
  setupPanel:disable()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
    radioItems = nil
  end

  layout:enableUpdates()
  layout:update()
end

function onGameEnd()
  currentNpcName = nil
  currentNpcCreature = nil
  hide()
end

-- Finds the actual NPC creature near the player matching this name, so we can keep checking
-- distance to it later (talk range is enforced by tile position, not just by name).
function findNpcCreature(name)
  local player = g_game.getLocalPlayer()
  if not player then return nil end

  local spectators = g_map.getSpectatorsInRangeEx(player:getPosition(), false, TALK_RADIUS, TALK_RADIUS, TALK_RADIUS, TALK_RADIUS)
  for _, creature in ipairs(spectators) do
    if creature:isNpc() and creature:getName() == name then
      return creature
    end
  end
  return nil
end

-- Same range check the server itself uses to decide whether an NPC still listens to/focuses
-- on the player (NpcHandler:isInRange, talkRadius=3 by default): same floor, within a square
-- of TALK_RADIUS tiles. Trade must not be reachable outside of that range either.
function isNpcInRange()
  if not currentNpcCreature then return false end
  local player = g_game.getLocalPlayer()
  if not player then return false end
  return Position.isInRange(player:getPosition(), currentNpcCreature:getPosition(), TALK_RADIUS, TALK_RADIUS)
end

-- Called whenever the local player moves. If we walk out of talk range of the NPC we were
-- tracking, the trade possibility must go away too, exactly like NPC conversation itself
-- would stop working at that point.
function checkNpcRange()
  if not currentNpcName then return end
  if not isNpcInRange() then
    currentNpcName = nil
    currentNpcCreature = nil
    if npcWindow:isVisible() then
      hide()
    end
  end
end

-- Tracks which NPC we're currently talking to, so a later "trade"/"offer" message can be
-- matched to that NPC's shop data. NPC replies now arrive via the private TALKTYPE_PRIVATE_NP
-- talktype (Npc::doSayToPlayer in game-server/src/npc.cpp), which the client sees as
-- MessageModes.NpcFrom -- a reliable, position-independent signal that "an NPC just replied
-- to me", regardless of whether that NPC happens to sell anything. This must update on
-- *every* NPC reply, not just ones with shop data, otherwise talking to a shopless NPC after
-- a real shop NPC would leave currentNpcName stuck on the old one and wrongly reopen its
-- item list.
function onGameTalk(name, level, mode, message, channelId, creaturePos)
  if not name then return end

  if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
    currentNpcName = name
    currentNpcCreature = findNpcCreature(name)
  end
end

-- Called for every outgoing chat message (game_console filter). Never blocks the message:
-- the real "trade"/"offer" text still reaches the server and the NPC conversation continues
-- exactly as if this dialog didn't exist; we just also open our own view of it locally.
-- Gated on talk range so trade can't open (and the item list can't be built) for an NPC
-- we've since walked away from.
function onOutgoingChat(message)
  if currentNpcName and isNpcInRange() then
    local shop = shopDataByLowerName[currentNpcName:lower()]
    if shop then
      local lowerMessage = message:lower()
      if string.find(lowerMessage, 'trade', 1, true) or string.find(lowerMessage, 'offer', 1, true) then
        openForNpc(currentNpcName)
      end
    end
  end
  return false
end

function openForNpc(npcName)
  local shop = shopDataByLowerName[npcName:lower()]
  if not shop then return end

  tradeItems[BUY] = {}
  tradeItems[SELL] = {}

  -- entry.id is the server id (npc scripts/items.xml); entry.clientId is what the loaded
  -- .dat actually indexes sprites by -- the two diverge for most items on this server.
  for _, entry in ipairs(shop.buy) do
    table.insert(tradeItems[BUY], { ptr = createShopItem(entry), id = entry.id, name = entry.name, keyword = entry.keyword, price = entry.price })
  end
  for _, entry in ipairs(shop.sell) do
    table.insert(tradeItems[SELL], { ptr = createShopItem(entry), id = entry.id, name = entry.name, keyword = entry.keyword, price = entry.price })
  end

  refreshTradeItems()
  show()
end

function onItemBoxChecked(widget)
  if widget:isChecked() then
    selectedItem = widget.item
    refreshItem(selectedItem)
    tradeButton:enable()
  end
end

function onQuantityValueChange(quantity)
  if selectedItem then
    totalLabel:setText(formatCurrency(getItemPrice(selectedItem)))
  end
end

local function setQuantityFromMouse(widget, mousePos)
  local decrementButton = widget:getChildById('decrementButton')
  local incrementButton = widget:getChildById('incrementButton')
  local leftInset = decrementButton and decrementButton:getWidth() or 0
  local rightInset = incrementButton and incrementButton:getWidth() or 0
  local trackWidth = widget:getWidth() - leftInset - rightInset
  if trackWidth <= 0 then return end

  local trackX = widget:getX() + leftInset
  local ratio = math.max(0, math.min(1, (mousePos.x - trackX) / trackWidth))
  local minimum = widget:getMinimum()
  local maximum = widget:getMaximum()
  widget:setValue(math.floor(minimum + (maximum - minimum) * ratio + 0.5))
end

function onQuantitySliderPress(widget, mousePos, mouseButton)
  if mouseButton ~= MouseLeftButton or not widget:isEnabled() then
    return false
  end

  setQuantityFromMouse(widget, mousePos)
  return true
end

function onQuantitySliderDrag(widget, mousePos, mouseMoved)
  if not widget:isEnabled() then return end
  setQuantityFromMouse(widget, mousePos)
end

function onTradeTypeChange(radioTabs, selected, deselected)
  tradeButton:setText(selected:getText())
  selected:setOn(true)
  deselected:setOn(false)

  refreshTradeItems()
end

-- Sends the exact same chat commands a player would type by hand, e.g. "buy 3 dragon shield"
-- followed by "yes" -- no protocol calls involved.
function onTradeClick()
  if not selectedItem then return end

  local action = getCurrentTradeType() == BUY and 'buy' or 'sell'
  local quantity = quantityScroll:getValue()

  modules.game_console.sendMessage(action .. ' ' .. quantity .. ' ' .. selectedItem.keyword)
  scheduleEvent(function() modules.game_console.sendMessage('yes') end, 300)
end

function onSearchTextChange()
  applySearchFilter()
end

function setCurrency(currency, decimal)
  CURRENCY = currency
  CURRENCY_DECIMAL = decimal
end

function clearSelectedItem()
  totalLabel:clearText()
  tradeButton:disable()
  quantityScroll:setMinimum(0)
  quantityScroll:setMaximum(0)
  if selectedItem then
    if radioItems then radioItems:selectWidget(nil) end
    selectedItem = nil
  end
end

function getCurrentTradeType()
  if tradeButton:getText() == tr('Buy') then
    return BUY
  else
    return SELL
  end
end

function getItemPrice(item, single)
  local amount = single and 1 or quantityScroll:getValue()
  return item.price * amount
end

function refreshItem(item)
  totalLabel:setText(formatCurrency(getItemPrice(item)))

  quantityScroll:setMinimum(1)
  quantityScroll:setMaximum(getMaxAmountFor(item))
  quantityScroll:setValue(1)

  setupPanel:enable()

  -- The client-side estimate above only sees equipped slots + currently open containers.
  -- Ask the server for the real count (it can see the whole inventory tree, closed backpacks
  -- included) and refine the slider once the async response comes back.
  if getCurrentTradeType() == SELL then
    local protocol = g_game.getProtocolGame()
    if protocol then
      protocol:sendExtendedOpcode(NPCTRADE_OPCODES.REQUEST_ITEM_COUNT, tostring(item.id))
    end
  end
end

-- Instant client-side estimate shown before the server's accurate count arrives: equipped
-- slots + currently open containers only (the server never tells the client what's inside a
-- closed backpack, so this can undercount unopened containers).
function getMaxAmountFor(item)
  if getCurrentTradeType() ~= SELL then
    return getMaxAmount()
  end

  local player = g_game.getLocalPlayer()
  local owned = player and player:getItemsCount(item.ptr:getId()) or 0
  return math.max(1, math.min(getMaxAmount(), owned))
end

function refreshTradeItems()
  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  clearSelectedItem()

  searchText:clearText()
  setupPanel:disable()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
  end
  radioItems = UIRadioGroup.create()

  local currentTradeItems = tradeItems[getCurrentTradeType()]
  for _, item in pairs(currentTradeItems) do
    local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
    itemBox.item = item
    itemBox:recursiveGetChildById('name'):setText(item.name)
    itemBox:recursiveGetChildById('price'):setText(formatCurrency(item.price))

    local itemWidget = itemBox:recursiveGetChildById('item')
    itemWidget:setItem(item.ptr)

    radioItems:addWidget(itemBox)
  end

  layout:enableUpdates()
  layout:update()
end

function applySearchFilter()
  local searchFilter = searchText:getText():lower()

  local items = itemsPanel:getChildCount()
  for i = 1, items do
    local itemWidget = itemsPanel:getChildByIndex(i)
    local item = itemWidget.item
    local visible = (searchFilter == '') or string.find(item.name:lower(), searchFilter, 1, true) ~= nil
    itemWidget:setVisible(visible)
  end
end

function formatCurrency(amount)
  if CURRENCY_DECIMAL then
    return string.format("%.02f", amount / 100.0) .. ' ' .. CURRENCY
  else
    return amount .. ' ' .. CURRENCY
  end
end

function getMaxAmount()
  return MAX_AMOUNT
end

function closeNpcTrade()
  hide()
end
