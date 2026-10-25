-- Danubia shop window: offers, points/purchase history and point transfers.
-- Everything is server driven (game-server/data/lib/shop_manager.lua) over the extended-opcode
-- channel. Purchases made here are delivered by the server's ShopCommands globalevent, exactly
-- like purchases made on the website.

-- Must match game-server/data/lib/shop_manager.lua's SHOP_EXTENDED_OPCODES table -- these
-- numbers share one flat namespace with every other feature using the extended-opcode channel.
SHOP_OPCODES = {
  REQUEST_OFFERS = 70,
  BUY_OFFER = 71,
  REQUEST_HISTORY = 72,
  TRANSFER_POINTS = 73,
  OFFERS = 74,
  HISTORY = 75,
  RESULT = 76,
  BALANCE = 77,
  CONVERT_TO_COINS = 78,
}

-- Points a single Danubia Coin costs; must match POINTS_PER_COIN in shop_manager.lua.
local POINTS_PER_COIN = 10

-- ProjectDanubia.Enums.ShopCategory in the web-service.
local CATEGORY_TITLES = {
  [1] = 'Premium Account',
  [2] = 'Outfits',
  [3] = 'Items',
  [4] = 'Services',
}
local CATEGORY_ITEMS = 3

-- ProjectDanubia.Enums.TransactionType in the web-service.
local TRANSACTION_TYPES = {
  [1] = { label = 'TOP-UP', color = '#5fd38a', sign = '+', filter = 'topup', details = 'Danubia Points purchased' },
  [2] = { label = 'EARNED', color = '#9fb4ff', sign = '+', filter = 'topup', details = 'Danubia Points earned' },
  [3] = { label = 'PURCHASE', color = '#e8a33c', sign = '-', filter = 'purchase', details = 'Shop purchase' },
  [4] = { label = 'RECEIVED', color = '#5fc8d3', sign = '+', filter = 'transfer', details = 'Points received from another player' },
  [5] = { label = 'SENT', color = '#e07a7a', sign = '-', filter = 'transfer', details = 'Points sent to another player' },
}

-- ShopPurchases.Delivered as written by the server's ShopCommands globalevent.
local DELIVERY_STATUS = {
  [0] = { label = 'PENDING', color = '#e8a33c' },
  [1] = { label = 'DELIVERED', color = '#5fd38a' },
  [2] = { label = 'FAILED', color = '#e05a5a' },
}

local BLOCKED_BUTTON_TEXT = {
  owned = 'Owned',
  pending = 'Pending delivery',
  rookgaard = 'Not on Rookgaard',
}

-- Buttons are locked while a purchase/transfer is in flight; unlock them again if the
-- server never answers (e.g. the connection dropped).
local PENDING_TIMEOUT = 8000

shopWindow = nil
local shopButton = nil
local msgWindow = nil

local balanceCoin, balanceValue, deliveryLabel, statusLabel
local tabs, panels = {}, {}
local categoryButtons = {}
local categoryTitle, subCategoryBar, offerList, offersEmpty
local historyFilterBar, historyList, historyEmpty, historyInfo
local recipientEdit, amountSpin, transferError, transferButton
local summaryBalance, summaryAmount, summaryAfter
local convertAmountSpin, convertError, convertButton
local convertSummaryBalance, convertSummaryCost, convertSummaryAfter

local balance = 0
local currencyClientId = 0
local offers = {}
local offersLoaded = false
local rookgaardShop = false
local history = {}
local historyLimit = 0
local historyLoaded = false
local currentTab = 'shop'
local currentCategory = 1
local currentSubCategory = 0
local currentHistoryFilter = 'all'
local pendingAction = nil
local pendingEvent = nil

local function formatNumber(value)
  local sign, digits = tostring(math.floor(tonumber(value) or 0)):match('^(%-?)(%d+)$')
  if not digits then
    return '0'
  end
  digits = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return sign .. digits
end

local function sendOpcode(opcode, buffer)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(opcode, buffer or '')
  end
end

local function setStatus(text)
  if statusLabel then
    statusLabel:setText(text or '')
  end
end

local function setBadge(widget, text, color)
  widget:setText(text)
  widget:setColor(color)
  widget:setBorderColor(color)
  widget:setBackgroundColor(color .. '22')
  widget:setVisible(true)
end

local function closeMessage()
  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end
end

local function showMessage(title, message)
  closeMessage()
  msgWindow = displayInfoBox(title, message)
  msgWindow.onDestroy = function(widget)
    if widget == msgWindow then
      msgWindow = nil
    end
  end
  msgWindow:raise()
  msgWindow:focus()
end

local function confirm(title, message, onYes)
  closeMessage()
  local yes = function()
    closeMessage()
    onYes()
  end
  msgWindow = displayGeneralBox(title, message, {
    { text = 'Yes', callback = yes },
    { text = 'No', callback = closeMessage },
    anchor = AnchorHorizontalCenter }, yes, closeMessage)
  msgWindow:raise()
  msgWindow:focus()
end

local function getPreviewOutfit(lookType)
  local outfit = { type = lookType, head = 78, body = 69, legs = 58, feet = 76, addons = 0 }
  local player = g_game.getLocalPlayer()
  if player then
    local current = player:getOutfit()
    outfit.head, outfit.body, outfit.legs, outfit.feet = current.head, current.body, current.legs, current.feet
  end
  return outfit
end

-- ImageUrl is a path on the website (e.g. /shop/14_days_premium.png). Bundled thumbnails
-- with the same file name are preferred; anything else is downloaded from the website.
local function loadOfferImage(widget, url)
  local localPath = '/images/game/shop/' .. (url:match('([^/]+)$') or '')
  if g_resources.fileExists(localPath) then
    widget:setImageSource(localPath)
    widget:setVisible(true)
    return
  end

  if url:sub(1, 4):lower() ~= 'http' then
    if type(Services) ~= 'table' or not Services.website then
      return
    end
    url = Services.website .. url
  end
  HTTP.downloadImage(url, function(path, err)
    if err or widget:isDestroyed() then
      return
    end
    widget:setImageSource(path)
    widget:setVisible(true)
  end)
end

local function setupPreview(preview, offer)
  if offer.clientId > 0 then
    preview.item:setItemId(offer.clientId)
    preview.item:setItemCount(offer.quantity)
    preview.item:setShowCount(false)
    preview.item:setVisible(true)
  elseif offer.lookType > 0 then
    preview.creature:setOutfit(getPreviewOutfit(offer.lookType))
    preview.creature:setAutoRotating(true)
    preview.creature:setAnimate(true)
    preview.creature:setVisible(true)
  elseif offer.image ~= '' then
    loadOfferImage(preview.image, offer.image)
  end

  if offer.blocked == 'owned' then
    preview.badge:setText('OWNED')
    preview.badge:setBackgroundColor('#5fd38a')
    preview.badge:setVisible(true)
  elseif offer.premiumDays > 0 then
    preview.badge:setText(offer.premiumDays .. ' DAYS')
    preview.badge:setVisible(true)
  elseif offer.quantity > 1 then
    preview.badge:setText('x' .. offer.quantity)
    preview.badge:setVisible(true)
  end
end

local function setPending(action)
  pendingAction = action
  removeEvent(pendingEvent)
  pendingEvent = nil

  if action then
    local statusTexts = {
      buy = 'Processing your purchase...',
      convert = 'Processing your conversion...',
    }
    setStatus(statusTexts[action] or 'Processing your transfer...')
    pendingEvent = scheduleEvent(function()
      pendingEvent = nil
      setPending(nil)
      setStatus('The server did not answer. Please try again.')
    end, PENDING_TIMEOUT)
  end

  if offerList then
    for _, card in ipairs(offerList:getChildren()) do
      if card.buyable then
        card.buyButton:setEnabled(not action)
      end
    end
  end
  updateTransferSummary()
  updateConvertSummary()
end

local function buyOffer(offer)
  if pendingAction then
    return
  end
  local player = g_game.getLocalPlayer()
  local message = string.format(
    'Do you want to buy %s for %s Danubia Points?\n\nIt will be delivered to %s.\nYour balance afterwards: %s Danubia Points.',
    offer.name, formatNumber(offer.points), player and player:getName() or 'your character',
    formatNumber(balance - offer.points))
  confirm('Confirm Purchase', message, function()
    setPending('buy')
    sendOpcode(SHOP_OPCODES.BUY_OFFER, tostring(offer.id))
  end)
end

local function createOfferCard(offer)
  local card = g_ui.createWidget('ShopOfferCard', offerList)
  card.name:setText(offer.name)
  card.description:setText(offer.description ~= '' and offer.description or 'No description.')
  card.price:setText(formatNumber(offer.points))
  card.coin:setItemId(currencyClientId)
  card.coin:setShowCount(false)
  setupPreview(card.preview, offer)

  local tooltip = offer.description
  if offer.blockedMessage ~= '' then
    tooltip = tooltip .. (tooltip ~= '' and '\n\n' or '') .. offer.blockedMessage
  end
  if tooltip ~= '' then
    card.description:setTooltip(tooltip)
  end

  local affordable = balance >= offer.points
  card.price:setColor(affordable and '#f0c75e' or '#e07a7a')

  local button = card.buyButton
  if offer.blocked == 'website' then
    button:setText('Buy on Website')
    button.onClick = function() openWebsite('/offers') end
  elseif offer.blocked ~= '' then
    button:setText(BLOCKED_BUTTON_TEXT[offer.blocked] or 'Unavailable')
    button:setEnabled(false)
  elseif not affordable then
    button:setText('Not enough points')
    button:setEnabled(false)
  else
    card.buyable = true
    button:setEnabled(not pendingAction)
    button.onClick = function() buyOffer(offer) end
  end
end

local function isOfferVisible(offer)
  return not rookgaardShop or offer.category ~= CATEGORY_ITEMS or offer.rookgaardAllowed
end

local function refreshOffers()
  if not offerList then
    return
  end
  offerList:destroyChildren()

  local shown = 0
  for _, offer in ipairs(offers) do
    if isOfferVisible(offer) and offer.category == currentCategory and (currentCategory ~= CATEGORY_ITEMS or currentSubCategory == 0
        or offer.subCategory == currentSubCategory) then
      createOfferCard(offer)
      shown = shown + 1
    end
  end

  local emptyText = rookgaardShop and currentCategory == CATEGORY_ITEMS
      and 'There are no Rookgaard-compatible items here yet.' or 'There are no offers here yet.'
  offersEmpty:setText(offersLoaded and emptyText or 'Loading offers...')
  offersEmpty:setVisible(shown == 0)
end

local function updateCategoryCounts()
  local counts = {}
  for _, offer in ipairs(offers) do
    if isOfferVisible(offer) then
      counts[offer.category] = (counts[offer.category] or 0) + 1
    end
  end
  for id, button in pairs(categoryButtons) do
    button.count:setText(counts[id] and tostring(counts[id]) or '')
  end
end

local function getHistoryDetails(entry, info)
  if entry.status < 0 then
    return info.details
  end
  local text = entry.offer ~= '' and entry.offer or info.details
  if entry.newName ~= '' then
    text = text .. ' (' .. entry.newName .. ')'
  end
  if entry.player ~= '' then
    text = text .. ' for ' .. entry.player
  end
  return text
end

local function createHistoryRow(entry, index)
  local row = g_ui.createWidget(index % 2 == 0 and 'ShopHistoryRowAlt' or 'ShopHistoryRow', historyList)

  local info = TRANSACTION_TYPES[entry.type] or { label = '?', color = '#b8b8b8', sign = '', details = '' }
  row.date:setText(os.date('%d.%m.%Y', entry.time) .. '\n' .. os.date('%H:%M', entry.time))
  setBadge(row.type, info.label, info.color)
  row.details:setText(getHistoryDetails(entry, info))
  row.details:setTooltip(row.details:getText())

  local status = DELIVERY_STATUS[entry.status]
  if status then
    setBadge(row.status, status.label, status.color)
  else
    row.status:setVisible(false)
  end

  row.amount:setText(info.sign .. formatNumber(entry.amount))
  row.amount:setColor(info.sign == '-' and '#e07a7a' or '#5fd38a')
  row.balance:setText(formatNumber(entry.balance))
end

local function refreshHistory()
  if not historyList then
    return
  end
  historyList:destroyChildren()

  local shown = 0
  for _, entry in ipairs(history) do
    local info = TRANSACTION_TYPES[entry.type]
    if currentHistoryFilter == 'all' or (info and info.filter == currentHistoryFilter) then
      shown = shown + 1
      createHistoryRow(entry, shown)
    end
  end

  historyEmpty:setText(historyLoaded and 'No transactions found.' or 'Loading history...')
  historyEmpty:setVisible(shown == 0)
  historyInfo:setText(historyLimit > 0 and string.format('Showing your last %d transactions', historyLimit) or '')
end

local function setBalance(value)
  if value == nil then
    return
  end
  balance = tonumber(value) or 0
  balanceValue:setText(formatNumber(balance))
  amountSpin:setMaximum(balance)
  convertAmountSpin:setMaximum(math.floor(balance / POINTS_PER_COIN))
  updateTransferSummary()
  updateConvertSummary()
end

local function setCurrencyClientId(value)
  local clientId = tonumber(value) or 0
  if clientId <= 0 then
    return
  end

  currencyClientId = clientId
  balanceCoin:setItemId(currencyClientId)
  balanceCoin:setShowCount(false)
end

local function onOffers(protocol, opcode, data)
  if type(data) ~= 'table' then
    return
  end
  offers = data.offers or {}
  rookgaardShop = data.rookgaard == true
  offersLoaded = true
  setCurrencyClientId(data.currencyClientId)
  setBalance(data.balance)
  updateCategoryCounts()
  refreshOffers()
end

local function onHistory(protocol, opcode, data)
  if type(data) ~= 'table' then
    return
  end
  history = data.entries or {}
  historyLimit = data.limit or 0
  historyLoaded = true
  setCurrencyClientId(data.currencyClientId)
  setBalance(data.balance)
  refreshHistory()
end

local function onResult(protocol, opcode, data)
  if type(data) ~= 'table' then
    return
  end
  setPending(nil)
  setStatus('')
  setBalance(data.balance)
  refreshOffers()

  if data.action == 'transfer' then
    showMessage(data.success and 'Transfer Successful' or 'Transfer Failed', data.message or '')
    if data.success then
      recipientEdit:setText('')
      amountSpin:setValue(0)
    end
  elseif data.action == 'convert' then
    showMessage(data.success and 'Conversion Successful' or 'Conversion Failed', data.message or '')
    if data.success then
      convertAmountSpin:setValue(0)
    end
  else
    showMessage(data.success and 'Purchase Successful' or 'Purchase Failed', data.message or '')
  end

  if data.success and currentTab == 'history' then
    requestHistory()
  end
end

-- Pushed to the receiving player of a transfer.
local function onBalance(protocol, opcode, data)
  if type(data) ~= 'table' then
    return
  end
  setCurrencyClientId(data.currencyClientId)
  setBalance(data.balance)
  refreshOffers()
end

local function setupHistoryHeader()
  local header = shopWindow:recursiveGetChildById('historyHeader')
  local columns = { date = 'Date', type = 'Type', details = 'Details', status = 'Status', amount = 'Amount', balance = 'Balance' }
  for id, text in pairs(columns) do
    local column = header:getChildById(id)
    column:setText(text)
    column:setColor('#80c7f8')
    column:setBorderWidth(0)
    column:setHeight(18)
  end
end

function init()
  shopWindow = g_ui.displayUI('shop')
  shopWindow:hide()

  balanceCoin = shopWindow:recursiveGetChildById('balanceCoin')
  balanceValue = shopWindow:recursiveGetChildById('balanceValue')
  deliveryLabel = shopWindow:recursiveGetChildById('deliveryLabel')
  statusLabel = shopWindow:recursiveGetChildById('statusLabel')
  for _, tab in ipairs({ 'shop', 'history', 'transfer', 'convert' }) do
    tabs[tab] = shopWindow:recursiveGetChildById(tab .. 'Tab')
    panels[tab] = shopWindow:recursiveGetChildById(tab .. 'Panel')
  end
  for id in pairs(CATEGORY_TITLES) do
    categoryButtons[id] = shopWindow:recursiveGetChildById('category' .. id)
  end
  categoryTitle = shopWindow:recursiveGetChildById('categoryTitle')
  subCategoryBar = shopWindow:recursiveGetChildById('subCategoryBar')
  offerList = shopWindow:recursiveGetChildById('offerList')
  offersEmpty = shopWindow:recursiveGetChildById('offersEmpty')
  historyFilterBar = shopWindow:recursiveGetChildById('historyFilterBar')
  historyList = shopWindow:recursiveGetChildById('historyList')
  historyEmpty = shopWindow:recursiveGetChildById('historyEmpty')
  historyInfo = shopWindow:recursiveGetChildById('historyInfo')
  recipientEdit = shopWindow:recursiveGetChildById('transferRecipient')
  amountSpin = shopWindow:recursiveGetChildById('transferAmount')
  transferError = shopWindow:recursiveGetChildById('transferError')
  transferButton = shopWindow:recursiveGetChildById('transferButton')
  summaryBalance = shopWindow:recursiveGetChildById('summaryBalance')
  summaryAmount = shopWindow:recursiveGetChildById('summaryAmount')
  summaryAfter = shopWindow:recursiveGetChildById('summaryAfter')
  convertAmountSpin = shopWindow:recursiveGetChildById('convertAmount')
  convertError = shopWindow:recursiveGetChildById('convertError')
  convertButton = shopWindow:recursiveGetChildById('convertButton')
  convertSummaryBalance = shopWindow:recursiveGetChildById('convertSummaryBalance')
  convertSummaryCost = shopWindow:recursiveGetChildById('convertSummaryCost')
  convertSummaryAfter = shopWindow:recursiveGetChildById('convertSummaryAfter')

  summaryBalance.caption:setText('Current balance')
  summaryAmount.caption:setText('Amount to transfer')
  summaryAfter.caption:setText('Balance after transfer')
  amountSpin.onValueChange = function() updateTransferSummary() end
  convertSummaryBalance.caption:setText('Current balance')
  convertSummaryCost.caption:setText('Cost in points')
  convertSummaryAfter.caption:setText('Balance after conversion')
  convertAmountSpin.onValueChange = function() updateConvertSummary() end
  setupHistoryHeader()

  selectTab('shop')
  selectCategory(1)
  selectHistoryFilter('all')
  setBalance(0)

  shopButton = modules.client_topmenu.addRightGameToggleButton('shopButton', tr('Shop'), '/images/topbuttons/shop', toggle, false, 8)

  ProtocolGame.registerExtendedJSONOpcode(SHOP_OPCODES.OFFERS, onOffers)
  ProtocolGame.registerExtendedJSONOpcode(SHOP_OPCODES.HISTORY, onHistory)
  ProtocolGame.registerExtendedJSONOpcode(SHOP_OPCODES.RESULT, onResult)
  ProtocolGame.registerExtendedJSONOpcode(SHOP_OPCODES.BALANCE, onBalance)

  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })

  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_OPCODES.OFFERS)
  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_OPCODES.HISTORY)
  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_OPCODES.RESULT)
  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_OPCODES.BALANCE)

  removeEvent(pendingEvent)
  pendingEvent = nil
  closeMessage()
  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if shopWindow then
    shopWindow:destroy()
    shopWindow = nil
  end
  offerList, historyList, amountSpin, convertAmountSpin = nil, nil, nil, nil
end

function onGameEnd()
  hide()
  closeMessage()
  removeEvent(pendingEvent)
  pendingEvent = nil
  pendingAction = nil
  balance = 0
  offers, offersLoaded = {}, false
  rookgaardShop = false
  history, historyLoaded = {}, false
  refreshOffers()
  refreshHistory()
  setStatus('')
end

function show()
  if not shopWindow or not g_game.isOnline() then
    return
  end
  shopWindow:show()
  shopWindow:raise()
  shopWindow:focus()
  if shopButton then
    shopButton:setOn(true)
  end

  local player = g_game.getLocalPlayer()
  deliveryLabel:setText(player and ('Purchases are delivered to ' .. player:getName()) or '')

  refreshOffers()
  sendOpcode(SHOP_OPCODES.REQUEST_OFFERS)
  selectTab(currentTab)
end

function hide()
  if not shopWindow then
    return
  end
  shopWindow:hide()
  if shopButton then
    shopButton:setOn(false)
  end
end

function toggle()
  if shopWindow and shopWindow:isVisible() then
    hide()
  else
    show()
  end
end

function openWebsite(path)
  if type(Services) ~= 'table' or not Services.website then
    return
  end
  local url = Services.website .. (path or '')
  scheduleEvent(function() g_platform.openUrl(url) end, 50)
end

function selectTab(tab)
  currentTab = tab
  for name, button in pairs(tabs) do
    button:setOn(name == tab)
    panels[name]:setVisible(name == tab)
  end

  if tab == 'history' then
    requestHistory()
  elseif tab == 'transfer' then
    updateTransferSummary()
    recipientEdit:focus()
  elseif tab == 'convert' then
    updateConvertSummary()
  end
end

function selectCategory(id)
  currentCategory = id
  currentSubCategory = 0
  for categoryId, button in pairs(categoryButtons) do
    button:setOn(categoryId == id)
  end
  categoryTitle:setText(CATEGORY_TITLES[id] or '')
  subCategoryBar:setVisible(id == CATEGORY_ITEMS)
  selectSubCategory(0)
end

function selectSubCategory(id)
  currentSubCategory = id
  for _, pill in ipairs(subCategoryBar:getChildren()) do
    pill:setOn(pill:getId() == 'subCategory' .. id)
  end
  refreshOffers()
end

function selectHistoryFilter(filter)
  currentHistoryFilter = filter
  for _, pill in ipairs(historyFilterBar:getChildren()) do
    pill:setOn(pill:getId():lower() == 'filter' .. filter)
  end
  refreshHistory()
end

function requestHistory()
  refreshHistory()
  sendOpcode(SHOP_OPCODES.REQUEST_HISTORY)
end

function updateTransferSummary()
  if not amountSpin then
    return
  end
  local amount = amountSpin:getValue() or 0
  local after = balance - amount
  summaryBalance.value:setText(formatNumber(balance))
  summaryAmount.value:setText(formatNumber(amount))
  summaryAfter.value:setText(formatNumber(after))
  summaryAfter.value:setColor(after < 0 and '#e07a7a' or '#ffffff')
  transferError:setText('')
  transferButton:setEnabled(not pendingAction and amount > 0 and after >= 0 and recipientEdit:getText():trim() ~= '')
end

-- -1 transfers the whole balance.
function setTransferAmount(amount)
  if amount < 0 then
    amount = balance
  end
  amountSpin.firstchange = false
  amountSpin:setText(tostring(math.min(amount, balance)))
end

function transferPoints()
  if pendingAction then
    return
  end

  local recipient = recipientEdit:getText():trim()
  local amount = amountSpin:getValue() or 0
  local player = g_game.getLocalPlayer()
  if recipient == '' then
    transferError:setText('Please enter the name of the receiving character.')
    return
  elseif amount <= 0 then
    transferError:setText('Please enter an amount greater than 0.')
    return
  elseif amount > balance then
    transferError:setText('You do not have enough Danubia Points.')
    return
  elseif player and player:getName():lower() == recipient:lower() then
    transferError:setText('You cannot transfer points to yourself.')
    return
  end

  confirm('Confirm Transfer', string.format(
    'Do you really want to transfer %s Danubia Points to %s?\n\nThis cannot be undone.',
    formatNumber(amount), recipient), function()
      setPending('transfer')
      sendOpcode(SHOP_OPCODES.TRANSFER_POINTS, amount .. ';' .. recipient)
    end)
end

function updateConvertSummary()
  if not convertAmountSpin then
    return
  end
  local coins = convertAmountSpin:getValue() or 0
  local cost = coins * POINTS_PER_COIN
  local after = balance - cost
  convertSummaryBalance.value:setText(formatNumber(balance))
  convertSummaryCost.value:setText(formatNumber(cost))
  convertSummaryAfter.value:setText(formatNumber(after))
  convertSummaryAfter.value:setColor(after < 0 and '#e07a7a' or '#ffffff')
  convertError:setText('')
  convertButton:setEnabled(not pendingAction and coins > 0 and after >= 0)
end

-- -1 converts as many coins as the balance allows.
function setConvertAmount(coins)
  local maxCoins = math.floor(balance / POINTS_PER_COIN)
  if coins < 0 then
    coins = maxCoins
  end
  convertAmountSpin.firstchange = false
  convertAmountSpin:setText(tostring(math.min(coins, maxCoins)))
end

function convertPoints()
  if pendingAction then
    return
  end

  local coins = convertAmountSpin:getValue() or 0
  if coins <= 0 then
    convertError:setText('Please enter an amount greater than 0.')
    return
  elseif coins * POINTS_PER_COIN > balance then
    convertError:setText('You do not have enough Danubia Points.')
    return
  end

  confirm('Confirm Conversion', string.format(
    'Do you really want to convert %s Danubia Points into %s Danubia Coin(s)?',
    formatNumber(coins * POINTS_PER_COIN), formatNumber(coins)), function()
      setPending('convert')
      sendOpcode(SHOP_OPCODES.CONVERT_TO_COINS, tostring(coins))
    end)
end
