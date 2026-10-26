-- TODO: find another hotkey for this. Ctrl+Z will be reserved to undo on textedits.
HOTKEY = 'Ctrl+Z'

bugReportWindow = nil
bugTextEdit = nil

function init()
  g_ui.importStyle('bugreport')

  bugReportWindow = g_ui.createWidget('BugReportWindow', rootWidget)
  bugReportWindow:hide()

  bugTextEdit = bugReportWindow:getChildById('bugTextEdit')

  g_keyboard.bindKeyDown(HOTKEY, show, modules.game_interface.getRootPanel())
end

function terminate()
  g_keyboard.unbindKeyDown(HOTKEY, modules.game_interface.getRootPanel())
  bugReportWindow:destroy()
end

-- must match BUG_REPORT_MAX_LENGTH on the server / bug_reports.content
MAX_LENGTH = 2000

function doReport()
  local text = bugTextEdit:getText():trim()
  if text:len() == 0 then
    return
  end
  -- the server answers with a confirmation (or cooldown) message
  g_game.reportBug(text:sub(1, MAX_LENGTH))
  bugReportWindow:hide()
end

function show()
  if g_game.isOnline() then
    bugTextEdit:setText('')
    bugReportWindow:show()
    bugReportWindow:raise()
    bugReportWindow:focus()
  end
end
