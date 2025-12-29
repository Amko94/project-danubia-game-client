TaskUI = {}

local tasksWindow = nil
local currentPlayerTaskList = nil
local selectedTask = nil
local currentCategory = 0
local filterText = ""
local debounceEvent = nil
local selectedActiveTask = nil
local selectedPausedTask = nil

function TaskUI.init()
    g_ui.importStyle('/modules/game_tasks/ui/tasks-main-window')
    g_ui.importStyle('/modules/game_tasks/ui/active-task-panel')
    g_ui.importStyle('/modules/game_tasks/ui/task-box')
    g_ui.importStyle('/modules/game_tasks/ui/reward-box')
    g_ui.importStyle('/modules/game_tasks/ui/confirm-dialog')
    g_ui.importStyle('/modules/game_tasks/ui/no-selected-task-warning')
    g_ui.importStyle('/modules/game_tasks/ui/error-resume-dialog')
end

function TaskUI.terminate()
    TaskUI.hide()
end

function TaskUI.toggle()
    if tasksWindow then
        TaskUI.hide()
    else
        TaskUI.show()
    end
end

function TaskUI.show()
    if not tasksWindow then
        tasksWindow = g_ui.createWidget("TaskWindow", modules.game_interface.getRootPanel())
        currentPlayerTaskList = tasksWindow:getChildById("taskList")
        tasksWindow.onDestroy = function()
            tasksWindow = nil
        end
    end

    tasksWindow:show()
    tasksWindow:raise()
    tasksWindow:focus()
    TaskUI.updateCategoryButtons()
    TaskUI.switchActiveTab()

    scheduleEvent(function()
        if not tasksWindow then
            return
        end
        TaskUI.refresh()

    end, 50)
end

function TaskUI.hide()
    if tasksWindow then
        tasksWindow:destroy()
        tasksWindow = nil
    end
end

function TaskUI.refresh()
    if not tasksWindow then
        return
    end

    TaskUI.onAvailableTasksUpdate()
    TaskUI.updateFilterMonsterList()
    TaskUI.updateActiveTaskPanel()
    TaskUI.updatePausedTasksList()
end

function TaskUI.onAvailableTasksUpdate()
    if not tasksWindow then
        return
    end
    local available = TasksManager.getAvailableTasks()
    local currentUiCount = currentPlayerTaskList:getChildCount()

    if #available > currentUiCount then
        TaskUI.appendMissingTasks(available, currentUiCount)
    end
end

function TaskUI.appendMissingTasks(available, currentCount)
    for i = currentCount + 1, #available do
        local task = available[i]

        local alreadyInUi = false
        for _, child in ipairs(currentPlayerTaskList:getChildren()) do
            if child.taskData and child.taskData.id == task.id then
                alreadyInUi = true
                break
            end
        end

        if not alreadyInUi then
            local box = g_ui.createWidget("TaskBox", currentPlayerTaskList)
            box.taskData = task
            box:getChildById("taskName"):setText(task.taskName)
            TaskUI.createIconGrid(box, task.lookTypeIds)
            box:getChildById("progressPanel"):setVisible(false)

            box.onClick = function()
                selectedTask = task
                for _, child in ipairs(currentPlayerTaskList:getChildren()) do
                    child:setOn(child == box)
                end
            end
        end
    end
    TaskUI.updateFilterMonsterList()
end

function TaskUI.updateFilterMonsterList()
    if not tasksWindow or not currentPlayerTaskList then
        return
    end
    local trackedTask = TasksManager.getTrackedTask()
    local active = TasksManager.getActiveTasks()
    local count = 0

    for _, box in ipairs(currentPlayerTaskList:getChildren()) do
        local task = box.taskData
        local isTracked = trackedTask and (trackedTask.taskId == task.id)
        local isPaused = false
        for _, aT in ipairs(active) do
            if aT.taskId == task.id and aT.paused == 1 then
                isPaused = true
                break
            end
        end

        local categoryMatch = (currentCategory == 0 or task.category == currentCategory)
        local textMatch = (filterText == "" or task.taskName:lower():find(filterText, 1, true))

        if not isTracked and not isPaused and categoryMatch and textMatch then
            box:setVisible(true)
            count = count + 1
        else
            box:setVisible(false)
        end
    end

    local empty = tasksWindow:getChildById("emptyList")
    if empty then
        empty:setVisible(count == 0)
    end
end

function TaskUI.updateActiveTaskPanel()
    if not tasksWindow then
        return
    end
    local activeTaskBase = tasksWindow:recursiveGetChildById("activeTaskBase")
    if not activeTaskBase then
        return
    end

    activeTaskBase:destroyChildren()
    local tracked = TasksManager.getTrackedTask()

    if not tracked then
        local empty = g_ui.createWidget("Label", activeTaskBase)
        empty:setText("No task started yet")
        empty:setTextAlign(AlignCenter)
        return
    end

    local activeBox = g_ui.createWidget("TaskBox", activeTaskBase)
    activeBox:setMargin(0)

    selectedActiveTask = tracked
    activeBox:setOn(true)

    local taskData = TasksManager.getTaskById(tracked.taskId)
    if taskData then
        activeBox:getChildById("taskName"):setText(taskData.taskName)
        TaskUI.createIconGrid(activeBox, taskData.lookTypeIds)
    end

    local progressPanel = activeBox:getChildById("progressPanel")
    if progressPanel then
        local percent = math.floor((tracked.progress / tracked.amount) * 100)
        progressPanel:getChildById("progressLabel"):setText(tracked.progress .. "/" .. tracked.amount .. " (" .. percent .. "%)")
        local bar = progressPanel:getChildById("progressBar")
        TaskUI.colorizeProgressBar(bar, percent)
        bar:setWidth(math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100))))
        progressPanel:setVisible(true)
    end
end

function TaskUI.updatePausedTasksList()
    if not tasksWindow then
        return
    end
    local pausedList = tasksWindow:recursiveGetChildById("pausedTaskList")
    local emptyLabel = tasksWindow:recursiveGetChildById("emptyPausedLabel")
    local pausedTab = tasksWindow:recursiveGetChildById("pausedTab")

    pausedList:destroyChildren()
    local active = TasksManager.getActiveTasks()
    local pausedCount = 0

    for _, task in ipairs(active) do
        if task.paused == 1 and task.active == 1 then
            pausedCount = pausedCount + 1
            local box = g_ui.createWidget("TaskBox", pausedList)

            box.onClick = function()
                selectedPausedTask = task

                local parent = box:getParent()
                if parent then
                    for _, child in ipairs(parent:getChildren()) do
                        child:setOn(false)
                    end
                end

                box:setOn(true)
            end

            if pausedCount == 1 then
                selectedPausedTask = task
                box:setOn(true)
            end

            box:setSize({ width = 140, height = 140 })
            box:getChildById("taskName"):setText(TasksManager.getTaskNameById(task.taskId))
            local taskData = TasksManager.getTaskById(task.taskId)
            if taskData then
                TaskUI.createIconGrid(box, taskData.lookTypeIds)
            end

            local progressPanel = box:getChildById("progressPanel")
            if progressPanel then

                local percent = math.floor((task.progress / task.amount) * 100)
                progressPanel:getChildById("progressLabel"):setText(task.progress .. "/" .. task.amount .. " (" .. percent .. "%)")
                local bar = progressPanel:getChildById("progressBar")
                bar:setBackgroundColor("#ff9900")
                bar:setWidth(math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100))))
                progressPanel:setVisible(true)
            end
        end

    end

    emptyLabel:setVisible(pausedCount == 0)
    if pausedTab then
        pausedTab:setText(string.format("Paused (%d)", pausedCount))
    end
end

function TaskUI.colorizeProgressBar(progressBar, percent)
    if not progressBar then
        return
    end

    local color = "#00FF00"

    if percent >= 80 then
        color = "#004D00"
    elseif percent >= 60 then
        color = "#008000"
    elseif percent >= 40 then
        color = "#00B300"
    elseif percent >= 20 then
        color = "#33FF33"
    end

    progressBar:setBackgroundColor(color)
end
function TaskUI.filterTasks(text)
    if debounceEvent then
        removeEvent(debounceEvent)
    end
    filterText = text:lower()
    debounceEvent = scheduleEvent(function()
        TaskUI.updateFilterMonsterList()
    end, 100)
end

function TaskUI.filterByCategory(cat)
    currentCategory = cat
    TaskUI.updateCategoryButtons()
    TaskUI.updateFilterMonsterList()
end

function TaskUI.updateCategoryButtons()
    if not tasksWindow then
        return
    end
    local buttonMap = { [0] = "categoryAll", [1] = "categoryLow", [2] = "categoryMedium", [3] = "categoryHard", [4] = "categoryVeryHard" }
    for catId, objId in pairs(buttonMap) do
        local btn = tasksWindow:recursiveGetChildById(objId)
        if btn then
            btn:setOn(currentCategory == catId)
        end
    end
end

function TaskUI.createIconGrid(box, lookTypeIds)
    local container = box:getChildById("iconContainer")
    if not container or not lookTypeIds or #lookTypeIds == 0 then
        return
    end
    container:destroyChildren()
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

function TaskUI.switchActiveTab()
    if not tasksWindow then
        return
    end
    tasksWindow:recursiveGetChildById("activeTaskContent"):setVisible(true)
    tasksWindow:recursiveGetChildById("pausedTaskContent"):setVisible(false)
    tasksWindow:recursiveGetChildById("activeTab"):setOn(true)
    tasksWindow:recursiveGetChildById("pausedTab"):setOn(false)
end

function TaskUI.switchPausedTab()
    if not tasksWindow then
        return
    end
    tasksWindow:recursiveGetChildById("activeTaskContent"):setVisible(false)
    tasksWindow:recursiveGetChildById("pausedTaskContent"):setVisible(true)
    tasksWindow:recursiveGetChildById("activeTab"):setOn(false)
    tasksWindow:recursiveGetChildById("pausedTab"):setOn(true)
end

function TaskUI.cancelTask()
    local rootPanel = modules.game_interface.getRootPanel()
    local activeTabVisible = tasksWindow:recursiveGetChildById("activeTaskContent"):isVisible()

    local taskToCancel = activeTabVisible and selectedActiveTask or selectedPausedTask

    if not taskToCancel then
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    local confirm = g_ui.createWidget("ConfirmDialog", rootPanel)
    confirm:getChildById("taskNameAndProcess"):setText(string.format("%s (%d/%d)",
            TasksManager.getTaskNameById(taskToCancel.taskId),
            taskToCancel.progress,
            taskToCancel.amount))

    confirm.taskId = taskToCancel.taskId

    confirm:show()
    confirm:raise()
    confirm:focus()
end

function TaskUI.confirmCancel()
    local rootPanel = modules.game_interface.getRootPanel()
    local dialog = rootPanel:getChildById('confirmDialog')

    if dialog and dialog.taskId then
        TaskProtocol.cancelTask(dialog.taskId)

        selectedActiveTask = nil
        selectedPausedTask = nil

        dialog:destroy()
        TaskUI.refresh()
    end
end

function TaskUI.resumeTask()
    local rootPanel = modules.game_interface.getRootPanel()

    if not selectedPausedTask then
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    TaskProtocol.sendResumeTask(selectedPausedTask.taskId)
end

function TaskUI.showResumeError()
    local rootPanel = modules.game_interface.getRootPanel()

    if rootPanel:getChildById('errorResumeDialog') then
        return
    end

    local errorDialog = g_ui.createWidget("ErrorResume", rootPanel)
    errorDialog:show()
    errorDialog:raise()
    errorDialog:focus()
end

function TaskUI.pauseTask()
    if not selectedActiveTask then
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    TaskProtocol.sendPauseTask(selectedActiveTask.taskId)
end