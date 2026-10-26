buttonsWindow = nil
buttonsPanel = nil

function init()
  g_ui.importStyle('buttons')
  buttonsWindow = g_ui.createWidget('ButtonsWindow', modules.game_interface.getRightPanel())
  buttonsWindow:disableResize()
  buttonsWindow:setup()

  buttonsPanel = buttonsWindow:recursiveGetChildById('buttonsPanel')
  buttonsPanel.onGeometryChange = updateButtonWidths
  for _, button in ipairs(buttonsPanel:getChildren()) do
    button.onVisibilityChange = updateButtonWidths
  end
  addEvent(updateButtonWidths)
end

function terminate()
  buttonsWindow:destroy()
end

-- the visible buttons share the available width equally
function updateButtonWidths()
  if not buttonsPanel then return end
  local visible = {}
  for _, button in ipairs(buttonsPanel:getChildren()) do
    if button:isExplicitlyVisible() then
      table.insert(visible, button)
    end
  end
  if #visible == 0 then return end

  local spacing = 2
  local width = math.floor((buttonsPanel:getWidth() - spacing * (#visible - 1)) / #visible)
  if width < 1 then return end
  for _, button in ipairs(visible) do
    if button:getWidth() ~= width then
      button:setWidth(width)
    end
  end
end
