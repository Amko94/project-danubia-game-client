local json = {}

function json.decode(str)
    if not str or str == "" then
        return {}
    end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, 1) == "[" and str:sub(-1) == "]" then
        local result = {}
        local items = str:sub(2, -2)
        if items == "" then
            return result
        end
        local objects, current, inString, braceLevel, i = {}, "", false, 0, 1
        while i <= #items do
            local char = items:sub(i, i)
            local prevChar = i > 1 and items:sub(i - 1, i - 1) or ""
            if char == '"' and prevChar ~= "\\" then
                inString = not inString
            end
            if not inString then
                if char == "{" then
                    braceLevel = braceLevel + 1
                elseif char == "}" then
                    braceLevel = braceLevel - 1
                elseif char == "," and braceLevel == 0 then
                    if current ~= "" then
                        table.insert(objects, current)
                    end
                    current, i = "", i + 1
                    goto continue
                end
            end
            current, i = current .. char, i + 1
            :: continue ::
        end
        if current ~= "" then
            table.insert(objects, current)
        end
        for _, obj in ipairs(objects) do
            local task = json.parseObject(obj)
            if task then
                table.insert(result, task)
            end
        end
        return result
    end
    return {}
end

function json.parseObject(str)
    if not str then
        return nil
    end
    str = str:match("^%s*{(.-)}%s*$")
    if not str then
        return nil
    end
    local task, pairs, current, inString, braceLevel, bracketLevel, i = {}, {}, "", false, 0, 0, 1
    while i <= #str do
        local char = str:sub(i, i)
        local prevChar = i > 1 and str:sub(i - 1, i - 1) or ""
        if char == '"' and prevChar ~= "\\" then
            inString = not inString
        end
        if not inString then
            if char == "{" then
                braceLevel = braceLevel + 1
            elseif char == "}" then
                braceLevel = braceLevel - 1
            elseif char == "[" then
                bracketLevel = bracketLevel + 1
            elseif char == "]" then
                bracketLevel = bracketLevel - 1
            elseif char == "," and braceLevel == 0 and bracketLevel == 0 then
                if current ~= "" then
                    table.insert(pairs, current)
                end
                current, i = "", i + 1
                goto continue2
            end
        end
        current, i = current .. char, i + 1
        :: continue2 ::
    end
    if current ~= "" then
        table.insert(pairs, current)
    end
    for _, pair in ipairs(pairs) do
        local key, value = pair:match('^%s*"([^"]+)"%s*:%s*"([^"]*)"')
        if key and value then
            task[key] = value
        else
            key, value = pair:match('^%s*"([^"]+)"%s*:%s*([%d.]+)')
            if key and value then
                task[key] = tonumber(value)
            else
                key, value = pair:match('^%s*"([^"]+)"%s*:%s*(%[.*%])')
                if key and value then
                    local arrayStr = value:sub(2, -2)
                    local arrayResult = {}
                    if arrayStr ~= "" then
                        for num in arrayStr:gmatch('[^,]+') do
                            num = tonumber(num)
                            if num then
                                table.insert(arrayResult, num)
                            end
                        end
                    end
                    task[key] = arrayResult
                end
            end
        end
    end
    return next(task) and task or nil
end

function safeJsonDecode(str)
    local status, result = pcall(function()
        return json.decode(str)
    end)
    return status and result or {}
end

local tasksWindow, currentPlayerTaskList, protocol = nil, nil, nil
local selectedTask, currentCategory, filterText = nil, 0, ""
local activeTasks, availableTasks = {}, {}

local function getTrackedTask()
    for _, task in ipairs(activeTasks) do
        if task.active == 1 and task.paused == 0 then
            return task
        end
    end
    return nil
end

local function getTaskStatusByTaskId(taskId)
    for _, task in ipairs(activeTasks) do
        if task.taskId == taskId then
            return task
        end
    end
    return nil
end

local function getMaxAmountForTask(taskId)
    for _, task in ipairs(availableTasks) do
        if task.id == taskId then
            return task.maxAmount or 0
        end
    end
    return 0
end

local function getTaskNameById(taskId)
    for _, task in ipairs(availableTasks) do
        if task.id == taskId then
            return task.taskName
        end
    end
    return "Unknown"
end

local debounceEvent = nil

function switchActiveTab()
    if not tasksWindow then
        return
    end

    local activeTab = tasksWindow:recursiveGetChildById("activeTab")
    local pausedTab = tasksWindow:recursiveGetChildById("pausedTab")
    local activeContent = tasksWindow:recursiveGetChildById("activeTaskContent")
    local pausedContent = tasksWindow:recursiveGetChildById("pausedTaskContent")

    if activeContent then
        activeContent:setVisible(true)
    end
    if pausedContent then
        pausedContent:setVisible(false)
    end
    if activeTab then
        activeTab:setOn(true)
    end
    if pausedTab then
        pausedTab:setOn(false)
    end
end

function switchPausedTab()
    if not tasksWindow then
        return
    end

    local activeTab = tasksWindow:recursiveGetChildById("activeTab")
    local pausedTab = tasksWindow:recursiveGetChildById("pausedTab")
    local activeContent = tasksWindow:recursiveGetChildById("activeTaskContent")
    local pausedContent = tasksWindow:recursiveGetChildById("pausedTaskContent")

    if activeContent then
        activeContent:setVisible(false)
    end
    if pausedContent then
        pausedContent:setVisible(true)
    end
    if activeTab then
        activeTab:setOn(false)
    end
    if pausedTab then
        pausedTab:setOn(true)
    end
end

function setupActiveTaskPanelTabs()
    if not tasksWindow then
        return
    end

    switchActiveTab()
end

local function updateCategoryButtons()
    if not tasksWindow then
        return
    end
    local panel = tasksWindow:getChildById("categoryPanel")
    if not panel then
        return
    end

    local buttonMap = {
        [0] = "categoryAll",
        [1] = "categoryLow",
        [2] = "categoryMedium",
        [3] = "categoryHard",
        [4] = "categoryVeryHard"
    }

    for catId, objId in pairs(buttonMap) do
        local btn = panel:getChildById(objId)
        if btn then
            btn:setOn(currentCategory == catId)
        end
    end
end

function filterTasks(text)
    if debounceEvent then
        removeEvent(debounceEvent)
    end
    filterText = text:lower()
    debounceEvent = scheduleEvent(function()
        rebuildTaskList()
    end, 100)
end

local function createIconGrid(box, lookTypeIds)
    local container = box:getChildById("iconContainer")
    if not container then
        return
    end
    container:destroyChildren()
    if #lookTypeIds == 0 then
        return
    end
    local cols = (#lookTypeIds == 4) and 2 or math.min(#lookTypeIds, 3)
    container:getLayout():setNumColumns(cols)
    local cellSize, spacing = 64, -18
    container:setWidth((cols * cellSize) + ((cols - 1) * spacing))
    for _, id in ipairs(lookTypeIds) do
        if type(id) == "number" and id > 0 then
            local icon = g_ui.createWidget("UICreature", container)
            icon:setSize({ width = cellSize, height = cellSize })
            icon:setOutfit({ type = id })
            icon:setPhantom(true)
        end
    end
end

function updateActiveTaskPanel()
    if not tasksWindow or tasksWindow:isDestroyed() then
        return
    end

    local activeTaskBase = tasksWindow:recursiveGetChildById("activeTaskBase")
    if not activeTaskBase then
        return
    end

    activeTaskBase:destroyChildren()

    local tracked = nil
    for _, task in ipairs(activeTasks) do
        if task.active == 1 and task.paused == 0 then
            tracked = task
            break
        end
    end

    if not tracked then
        local empty = g_ui.createWidget("Label", activeTaskBase)
        empty:setText("No task started yet")
        empty:setTextAlign(AlignCenter)
        empty:fill("parent")
        return
    end

    local activeBox = g_ui.createWidget("TaskBox", activeTaskBase)
    activeBox:setMargin(0)
    activeBox:fill("parent")

    for _, avail in ipairs(availableTasks) do
        if avail.id == tracked.taskId and avail.taskName then
            activeBox:getChildById("taskName"):setText(avail.taskName)
            createIconGrid(activeBox, avail.lookTypeIds)
            break
        end
    end

    local progressPanel = activeBox:getChildById("progressPanel")
    if progressPanel then
        local percent = math.floor((tracked.progress / tracked.amount) * 100)
        progressPanel:getChildById("progressLabel"):setText(tracked.progress .. "/" .. tracked.amount .. " " .. "(" .. percent .. "%)")
        local bar = progressPanel:getChildById("progressBar")

        local barWidth = math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100)))
        bar:setWidth(barWidth)
        progressPanel:setVisible(true)
    end
end

function updatePausedTasksList()
    if not tasksWindow then
        print("ERROR: tasksWindow is nil")
        return
    end

    local pausedList = tasksWindow:recursiveGetChildById("pausedTaskList")
    local emptyLabel = tasksWindow:recursiveGetChildById("emptyPausedLabel")
    local pausedTab = tasksWindow:recursiveGetChildById("pausedTab")

    pausedList:destroyChildren()

    local hasPausedTasks = false
    local pausedCount = 0


    for i, task in ipairs(activeTasks) do
        if task.paused == 1 and task.active == 1 then
            hasPausedTasks = true
            pausedCount = pausedCount + 1

            local box = g_ui.createWidget("TaskBox", pausedList)
            box:getChildById("taskName"):setText(getTaskNameById(task.taskId))

            for _, avail in ipairs(availableTasks) do
                if avail.id == task.taskId then
                    createIconGrid(box, avail.lookTypeIds)
                    break
                end
            end

            local progressPanel = box:getChildById("progressPanel")
            if progressPanel then
                local percent = math.floor((task.progress / task.amount) * 100)
                progressPanel:getChildById("progressLabel"):setText(task.progress .. "/" .. task.amount .. " " .. "(" .. percent .. "%)")
                local bar = progressPanel:getChildById("progressBar")
                local barWidth = math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100)))
                bar:setWidth(barWidth)
                progressPanel:setVisible(true)
            end
        end
    end


    emptyLabel:setVisible(not hasPausedTasks)
    if pausedTab then
        pausedTab:setText(string.format("Paused (%d)", pausedCount))
    end
end

function rebuildTaskList()
    if not tasksWindow or not currentPlayerTaskList then
        return
    end

    currentPlayerTaskList:destroyChildren()
    local trackedTask = getTrackedTask()

    for _, task in ipairs(availableTasks) do
        local isTracked = trackedTask and (trackedTask.taskId == task.id or trackedTask.taskName == task.taskName)

        -- Prüfe ob Task paused ist
        local isPaused = false
        for _, activeTask in ipairs(activeTasks) do
            if activeTask.taskId == task.id and activeTask.paused == 1 then
                isPaused = true
                break
            end
        end

        -- Nur anzeigen wenn nicht tracked UND nicht paused
        if not isTracked and not isPaused then
            local categoryMatch = (currentCategory == 0 or task.category == currentCategory)
            local textMatch = (filterText == "" or task.taskName:lower():find(filterText, 1, true))

            if categoryMatch and textMatch then
                local box = g_ui.createWidget("TaskBox", currentPlayerTaskList)
                box:getChildById("taskName"):setText(task.taskName)

                if task.lookTypeIds then
                    createIconGrid(box, task.lookTypeIds)
                end

                box:getChildById("progressPanel"):setVisible(false)

                box.onClick = function()
                    selectedTask = task
                    updateButtonState()
                    for _, child in ipairs(currentPlayerTaskList:getChildren()) do
                        child:setOn(child == box)
                    end
                end
            end
        end
    end

    local empty = tasksWindow:getChildById("emptyList")
    if empty then
        empty:setVisible(currentPlayerTaskList:getChildCount() == 0)
    end

    updateActiveTaskPanel()
end

function updateButtonState()
    if not tasksWindow or not selectedTask then
        return
    end
    local panel = tasksWindow:getChildById("inputPanel")
    local okBtn = panel:getChildById("okButton")
    local input = panel:getChildById("amountInput")
    local maxLbl = panel:getChildById("maxAmount")

    local status = getTaskStatusByTaskId(selectedTask.id)
    local maxVal = getMaxAmountForTask(selectedTask.id)
    local activeRunning = getTrackedTask() and getTrackedTask().paused == 0

    maxLbl:setText(maxVal <= 0 and "Completed" or "Max: " .. maxVal)
    input.onTextChange = function(w)
        if tonumber(w:getText()) and tonumber(w:getText()) > maxVal then
            w:setText(tostring(maxVal))
        end
    end

    if status then
        input:setEnabled(false)
        input:setText(tostring(status.amount))
        if status.progress >= status.amount then
            okBtn:setText("Get Reward");
            okBtn:setEnabled(true)
            okBtn.onClick = function()
                getReward(selectedTask.id)
            end
        elseif status.paused == 1 then
            okBtn:setText("Resume");
            okBtn:setEnabled(not activeRunning)
            okBtn.onClick = function()
                resumeTask(selectedTask.id)
            end
        else
            okBtn:setText("Pause");
            okBtn:setEnabled(true)
            okBtn.onClick = function()
                pauseTask(selectedTask.id)
            end
        end
    else
        input:setEnabled(maxVal > 0);
        input:setText(maxVal > 0 and "50" or "0")
        okBtn:setText("Activate");
        --okBtn:setEnabled(not activeRunning and maxVal > 0)
        okBtn.onClick = function()
            startTask(selectedTask.id, tonumber(input:getText()) or 50)
        end
    end
    updateActiveTaskPanel()
end

function onExtendedOpcode(_, opcode, buffer)
    if opcode == 3 then
        activeTasks = safeJsonDecode(buffer)
        rebuildTaskList()
        updateButtonState()
        updatePausedTasksList()
    elseif opcode == 4 and buffer:sub(1, 14) == "TASKLIST_PART;" then
        local part = safeJsonDecode(buffer:sub(15))
        for _, t in ipairs(part) do
            table.insert(availableTasks, t)
        end
        rebuildTaskList()
        updatePausedTasksList()
    elseif opcode == 1 or opcode == 5 then
        requestActiveTasks()
    end
end

function init()
    g_ui.importStyle('tasksWindow');
    g_ui.importStyle('activeTaskPanel')
    g_ui.importStyle('taskbox')
    if modules.client_topmenu then
        modules.client_topmenu.addRightGameToggleButton("taskButton", tr("Tasks"), "/images/topbuttons/questlog", toggle)
    end
    connect(g_game, { onGameStart = onGameStart, onGameEnd = hideWindow })
    if g_game.isOnline() then
        onGameStart()
    end
end

function onGameStart()
    protocol = g_game.getProtocolGame()
    if protocol then
        connect(protocol, { onExtendedOpcode = onExtendedOpcode })
    end
end

function terminate()
    hideWindow()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = hideWindow })
    if protocol then
        disconnect(protocol, { onExtendedOpcode = onExtendedOpcode })
    end
end

function toggle()
    if tasksWindow then
        hideWindow()
    else
        showWindow()
    end
end

function showWindow()
    if not tasksWindow then
        tasksWindow = g_ui.createWidget("TaskWindow", modules.game_interface.getRootPanel())
        currentPlayerTaskList = tasksWindow:getChildById("taskList")
        tasksWindow.onDestroy = function()
            tasksWindow = nil
        end
    end
    tasksWindow:show()
    tasksWindow:raise()

    setupActiveTaskPanelTabs()
    updateActiveTaskPanel()
    updatePausedTasksList()
    requestActiveTasks()
end

function hideWindow()
    if tasksWindow then
        tasksWindow:destroy();
        tasksWindow = nil
    end
end

function requestActiveTasks()
    local proto = g_game.getProtocolGame()
    if proto and proto:isConnected() then
        availableTasks = {}
        proto:sendExtendedOpcode(0x04, "") -- Request all
        proto:sendExtendedOpcode(0x03, "") -- Request active
    end
end

-- Steuerungsfunktionen
function startTask(id, amount)
    local p = g_game.getProtocolGame()
    if p then
        p:sendExtendedOpcode(0x01, id .. ";" .. amount);
        hideWindow()
    end
end

function resumeTask(id)
    if protocol then
        protocol:sendExtendedOpcode(0x05, id)
    end
end

function pauseTask(id)
    if protocol then
        protocol:sendExtendedOpcode(0x06, id)
    end
end

function getReward(id)
    if protocol then
        protocol:sendExtendedOpcode(0x03, id)
    end
end

function filterByCategory(cat)
    currentCategory = cat;
    updateCategoryButtons()
    rebuildTaskList();
    updateButtonState()
end