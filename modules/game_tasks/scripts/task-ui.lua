TaskUI = {}

local PLAYER_OUTFIT_TYPES = {
    ['Amazon'] = { type = 137, head = 113, body = 120, legs = 95, feet = 115 },
    ['Valkyrie'] = { type = 139, head = 113, body = 38, legs = 76, feet = 96 },
    ['Adept of the Cult'] = { type = 194, head = 114, body = 94, legs = 94, feet = 57 },
    ['Acolyte of the Cult'] = { type = 194, head = 114, body = 121, legs = 121, feet = 57 },
    ['Novice of the Cult'] = { type = 133, head = 114, body = 95, legs = 114, feet = 114 },
    ['Barbarian Bloodwalker'] = { type = 255, head = 114, body = 132, legs = 113, feet = 113 },
    ['Barbarian Headsplitter'] = { type = 253, head = 132, body = 105, legs = 0, feet = 132 },
    ['Barbarian Skullhunter'] = { type = 254, head = 0, body = 77, legs = 77, feet = 114 },
    ['Bandit'] = { type = 129, head = 58, body = 40, legs = 24, feet = 95 },
    ['Hunter'] = { type = 129, head = 95, body = 116, legs = 120, feet = 115 },
    ['Stalker'] = { type = 128, head = 97, body = 116, legs = 95, feet = 95 },
    ['Wild Warrior'] = { type = 131, head = 57, body = 57, legs = 57, feet = 57 },
    ['Black Knight'] = { type = 131, head = 95, body = 95, legs = 95, feet = 95 },
    ['Warlock'] = { type = 130, head = 0, body = 52, legs = 128, feet = 95 },
    ['Ice Witch'] = { type = 149, head = 0, body = 47, legs = 105, feet = 105 },
    ['Fury'] = { type = 149, head = 94, body = 77, legs = 96, feet = 0, addons = 3 }
}

local tasksWindow = nil
local currentPlayerTaskList = nil
local currentCategory = 0
local filterText = ""
local debounceEvent = nil
local selectedActiveTask = nil
local selectedPausedTask = nil

function TaskUI.init()
    g_ui.importStyle('/modules/game_tasks/ui/tasks-main-window')
    g_ui.importStyle('/modules/game_tasks/ui/active-task-panel')
    g_ui.importStyle('/modules/game_tasks/ui/paused-task-list')
    g_ui.importStyle('/modules/game_tasks/ui/task-box')
    g_ui.importStyle('/modules/game_tasks/ui/reward-box')
    g_ui.importStyle('/modules/game_tasks/ui/confirm-dialog')
    g_ui.importStyle('/modules/game_tasks/ui/no-selected-task-warning')
    g_ui.importStyle('/modules/game_tasks/ui/error-start-task-dialog')
    g_ui.importStyle('/modules/game_tasks/ui/start-task-dialog')
    g_ui.importStyle('/modules/game_tasks/ui/current-task-container')
    g_ui.importStyle('/modules/game_tasks/ui/claim-reward-dialog')
    g_ui.importStyle('/modules/game_tasks/ui/pz-block-dialog.otui')
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

    local label = tasksWindow:recursiveGetChildById("taskPointsLabel")
    if label and TasksManager.playerTaskPoints then
        label:setText(tostring("Task Points: " .. TasksManager.playerTaskPoints))
    end

    TaskUI.updateCategoryButtons()

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
    local rootPanel = modules.game_interface.getRootPanel()

    local dialogs = {
        'claimRewardDialog',
        'startTaskDialog',
        'confirmDialog',
        'errorStartTaskDialog',
        'noTaskWarningDialog',
        'pzBlockDialog'
    }

    for _, dialogId in ipairs(dialogs) do
        local dialog = rootPanel:getChildById(dialogId)
        if dialog then
            dialog:destroy()
        end
    end
    selectedActiveTask = nil
    selectedPausedTask = nil
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

            local startBtn = box:getChildById("startTaskButton")

            startBtn:setVisible(true)

            startBtn.task = task
            startBtn.onClick = function(widget)
                TaskUI.openStartTaskDialog(widget.task)
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
    local emptyLabel = tasksWindow:recursiveGetChildById("emptyActiveLabel")
    local rewardBtn = tasksWindow:recursiveGetChildById("rewardButton")
    local cancelBtn = tasksWindow:recursiveGetChildById("cancelTaskButton")
    local pauseBtn = tasksWindow:recursiveGetChildById("pauseButton")
    local activeTitle = tasksWindow:recursiveGetChildById("activeTitle")

    if not activeTaskBase then
        return
    end

    activeTaskBase:destroyChildren()
    local tracked = TasksManager.getTrackedTask()

    if not tracked then
        selectedActiveTask = nil
        if emptyLabel then
            emptyLabel:setVisible(true)
        end

        if cancelBtn then
            cancelBtn:setEnabled(false)
        end

        if pauseBtn then
            pauseBtn:setEnabled(false)
        end

        if rewardBtn then
            rewardBtn:setEnabled(false)
        end

        if activeTitle then
            activeTitle:setColor("#666666")
        end

        return
    end

    if emptyLabel then
        emptyLabel:setVisible(false)
    end

    selectedActiveTask = tracked

    if selectedActiveTask.finished == 1 then
        if pauseBtn then
            pauseBtn:setEnabled(false)
        end
        if cancelBtn then
            cancelBtn:setEnabled(false)
        end
        if rewardBtn then
            rewardBtn:setEnabled(true)
            rewardBtn:setColor("#FFD700")
        end
    else
        if rewardBtn then
            rewardBtn:setEnabled(true)
        end
        if cancelBtn then
            cancelBtn:setEnabled(true)
        end
        if pauseBtn then
            pauseBtn:setEnabled(true)
        end
    end

    if activeTitle then
        activeTitle:setColor("#25E00B")
    end

    local display = g_ui.createWidget("CurrentTaskContainer", activeTaskBase)
    display:fill('parent')

    local taskData = TasksManager.getTaskById(tracked.taskId)
    if taskData then
        display:getChildById("taskName"):setText(taskData.taskName)
        if taskData.lookTypeIds and #taskData.lookTypeIds > 0 then
            display:getChildById("monsterIcon"):setOutfit({ type = taskData.lookTypeIds[1] })
        end

        if taskData.monsterNames and #taskData.monsterNames > 0 then
            local monsterList = table.concat(taskData.monsterNames, "\n")
            display:getChildById("monsterIcon"):setTooltip(monsterList)
        end
    end

    local percent = math.floor((tracked.progress / tracked.amount) * 100)
    local progressPanel = display:getChildById("progressPanel")
    if progressPanel then
        local progressBar = progressPanel:getChildById("progressBar")
        local progressLabel = progressPanel:getChildById("progressLabel")

        if progressBar then
            local barWidth = math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100)))
            progressBar:setWidth(barWidth)
        end

        if progressLabel then
            progressLabel:setText(tracked.progress .. "/" .. tracked.amount .. " (" .. percent .. "%)")
        end
    end
end

function TaskUI.updatePausedTasksList()
    if not tasksWindow then
        return
    end
    local pausedList = tasksWindow:recursiveGetChildById("pausedTaskContainer")
    local pausedTitle = tasksWindow:recursiveGetChildById("pausedTitle")
    if not pausedList then
    end

    pausedList:destroyChildren()
    local active = TasksManager.getActiveTasks()

    local pausedTasks = {}
    for _, task in ipairs(active) do
        if task.paused == 1 and task.active == 1 then
            task.cachedName = TasksManager.getTaskNameById(task.taskId)
            table.insert(pausedTasks, task)
        end
    end

    table.sort(pausedTasks, function(a, b)
        return a.cachedName:lower() < b.cachedName:lower()
    end)

    local pausedCount = #pausedTasks
    for _, task in ipairs(pausedTasks) do
        local item = g_ui.createWidget("PausedTaskListItem", pausedList)
        item.taskData = task
        item:getChildById("taskName"):setText(task.cachedName)

        local taskData = TasksManager.getTaskById(task.taskId)
        if taskData and taskData.lookTypeIds then
            item:getChildById("monsterIcon"):setOutfit({ type = taskData.lookTypeIds[1] })
        end

        local percent = math.floor((task.progress / task.amount) * 100)
        local pLabel = item:recursiveGetChildById("progressLabel")
        if pLabel then
            pLabel:setText(task.progress .. "/" .. task.amount)
        end

        local bar = item:recursiveGetChildById("progressBar")
        local progressPanel = item:getChildById("progressPanel")
        if bar and progressPanel then
            bar:setBackgroundColor("#ff9900")
            scheduleEvent(function()
                if bar and progressPanel then
                    local barWidth = math.max(0, math.floor((progressPanel:getWidth() - 2) * (percent / 100)))
                    bar:setWidth(barWidth)
                end
            end, 10)
        end

        item.onClick = function()
            selectedPausedTask = task
            for _, child in ipairs(pausedList:getChildren()) do
                child:setBorderColor("#333333")
            end
            item:setBorderColor("#ffffff")
        end
    end

    if pausedTitle then
        pausedTitle:setText(string.format("PAUSED (%d)", pausedCount))
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

    local taskData = box.taskData
    local taskName = taskData and taskData.taskName or ""
    local monsterNames = (taskData and type(taskData.monsterNames) == 'table') and taskData.monsterNames or {}

    local cols = (#lookTypeIds == 4) and 2 or math.min(#lookTypeIds, 3)
    container:getLayout():setNumColumns(cols)
    local cellSize, spacing = 64, -18
    container:setWidth((cols * cellSize) + ((cols - 1) * spacing))

    for idx, id in ipairs(lookTypeIds) do
        if type(id) == "number" and id > 0 then
            local icon = g_ui.createWidget("UICreature", container)
            icon:setSize({ width = cellSize, height = cellSize })

            local finalOutfit = { type = id }

            if idx <= #monsterNames then
                local mName = monsterNames[idx]
                local special = PLAYER_OUTFIT_TYPES[mName]
                if special and special.type == id then
                    finalOutfit = special
                end
            end

            if not finalOutfit.head and taskName ~= "" then
                local special = PLAYER_OUTFIT_TYPES[taskName]
                if special and special.type == id then
                    finalOutfit = special
                end
            end

            icon:setOutfit(finalOutfit)
            icon:setPhantom(true)
        end
    end
end

function TaskUI.cancelTask()
    local rootPanel = modules.game_interface.getRootPanel()

    if not selectedActiveTask then
        if rootPanel:getChildById('noTaskWarningDialog') then
            return
        end
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    if rootPanel:getChildById('confirmDialog') then
        return
    end

    if TaskUI.checkPlayerPz() then
        return
    end

    local confirm = g_ui.createWidget("ConfirmDialog", rootPanel)
    confirm:getChildById("taskNameAndProcess"):setText(string.format("%s (%d/%d)",
            TasksManager.getTaskNameById(selectedActiveTask.taskId),
            selectedActiveTask.progress,
            selectedActiveTask.amount))

    confirm.taskId = selectedActiveTask.taskId

    confirm:show()
    confirm:raise()
    confirm:focus()
end

function TaskUI.cancelPausedTask()
    local rootPanel = modules.game_interface.getRootPanel()

    if not selectedPausedTask then
        if rootPanel:getChildById('noTaskWarningDialog') then
            return
        end
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    if rootPanel:getChildById('confirmDialog') then
        return
    end

    if TaskUI.checkPlayerPz() then
        return
    end

    local confirm = g_ui.createWidget("ConfirmDialog", rootPanel)
    confirm:getChildById("taskNameAndProcess"):setText(string.format("%s (%d/%d)",
            TasksManager.getTaskNameById(selectedPausedTask.taskId),
            selectedPausedTask.progress,
            selectedPausedTask.amount))

    confirm.taskId = selectedPausedTask.taskId

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

function TaskUI.resumeTaskViaItem(item)
    if item and item.taskData then
        TaskProtocol.sendResumeTask(item.taskData.taskId)
    end
end

function TaskUI.showStartTaskError()
    local rootPanel = modules.game_interface.getRootPanel()

    if rootPanel:getChildById('errorStartTaskDialog') then
        return
    end

    local errorDialog = g_ui.createWidget("ErrorStartTaskDialog", rootPanel)
    errorDialog:show()
    errorDialog:raise()
    errorDialog:focus()
end

function TaskUI.pauseTask()
    if not selectedActiveTask then
        local rootPanel = modules.game_interface.getRootPanel()
        if rootPanel:getChildById('noTaskWarningDialog') then
            return
        end
        local noTask = g_ui.createWidget("NoTaskWarningDialog", rootPanel)
        noTask:show()
        noTask:raise()
        noTask:focus()
        return
    end

    if TaskUI.checkPlayerPz() then
        return
    end

    TaskProtocol.sendPauseTask(selectedActiveTask.taskId)
end

function TaskUI.openStartTaskDialog(task)
    if not task then
        return
    end

    if TasksManager.getTrackedTask() then
        TaskUI.showStartTaskError()
        return
    end

    local rootPanel = modules.game_interface.getRootPanel()

    if rootPanel:getChildById('startTaskDialog') then
        return
    end

    if TaskUI.checkPlayerPz() then
        return
    end

    local dialog = g_ui.createWidget("StartTaskDialog", rootPanel)

    if not dialog then
        print("ERROR: Could not create StartTaskDialog")
        return
    end
    dialog:setText(task.taskName)
    dialog.taskId = task.id
    dialog.taskCategory = task.category
    dialog.taskExperience = task.experience

    if task.lookTypeIds and #task.lookTypeIds > 0 then
        local iconContainer = dialog:recursiveGetChildById("iconContainer")
        if iconContainer then
            TaskUI.createIconGridForDialog(iconContainer, task)
        end
    end

    local amountInput = dialog:recursiveGetChildById("amountInput")
    if amountInput and task.minAmount then
        amountInput:setText(50)

        if (amountInput > 1000) then
            amountInput:setText(1000)
        end

        if (amountInput < 50) then
            amountInput:setText(50)
        end

    end

    dialog:show()
    dialog:raise()
    dialog:focus()
end

function TaskUI.updateTaskAmount(dialog, text)
    if not dialog or not text or text == "" then
        return
    end

    local amountInput = dialog:recursiveGetChildById("amountInput")
    local errorLabel = dialog:recursiveGetChildById("errorLabel")
    if not amountInput then
        return
    end

    local val = tonumber(text)

    if not val then
        amountInput:setText(text:gsub("%D+", ""))

        if errorLabel then
            errorLabel:setVisible(true)
            scheduleEvent(function()
                if errorLabel then
                    errorLabel:setText("Only numbers allowed")
                    errorLabel:setVisible(false)

                end
            end, 2000)
        end
        return
    end

    if val > 1000 then
        amountInput:setText(1000)
    elseif val < 0 then
        amountInput:setText(0)
    end

    TaskUI.updateRewardPreview(dialog, val)
end

function TaskUI.updateRewardPreview(dialog, amount)
    if not dialog or not amount or amount == 0 then
        return
    end

    local goldSection = dialog:recursiveGetChildById("goldCoinRewardSection")
    local goldAmountLabel = dialog:recursiveGetChildById("goldCoinAmount")
    local expAmountLabel = dialog:recursiveGetChildById("expAmount")
    local tpLabel = dialog:recursiveGetChildById("taskPointsAmount")

    if not goldSection or not goldAmountLabel then
        return
    end

    local totalGold = TasksManager.calculateGoldReward(amount, dialog.taskExperience, dialog.taskCategory)
    local totalExp = TasksManager.calculateExperienceReward(amount, dialog.taskExperience)
    local totalTaskPoints = TasksManager.calculateTaskPointsReward(amount, dialog.taskExperience, dialog.taskCategory)

    goldAmountLabel:setText(TaskUI.formatGoldAmount(totalGold))

    if expAmountLabel then
        expAmountLabel:setText(TaskUI.formatAmount(totalExp))
    end

    if tpLabel then
        tpLabel:setText(totalTaskPoints)
    end
end

function TaskUI.formatGoldAmount(amount)
    if amount >= 1000000 then
        return string.format("%.2f", amount / 1000000):gsub("%.?0+$", "") .. "kk"
    elseif amount >= 1000 then
        return string.format("%.2f", amount / 1000):gsub("%.?0+$", "") .. "k"
    else
        return tostring(amount .. 'gp')
    end
end

function TaskUI.formatAmount(amount)
    if amount >= 1000000 then
        return string.format("%.2f", amount / 1000000):gsub("%.?0+$", "") .. "kk"
    elseif amount >= 1000 then
        return string.format("%.2f", amount / 1000):gsub("%.?0+$", "") .. "k"
    else
        return tostring(amount)
    end
end

function TaskUI.confirmStartTask()
    local root = modules.game_interface.getRootPanel()
    local dialog = root:getChildById('startTaskDialog')
    if not dialog then
        return
    end
    local errorLabel = dialog:recursiveGetChildById("errorLabel")
    local amount = tonumber(dialog:recursiveGetChildById("amountInput"):getText()) or 0

    if (amount < 50 or not amount) and errorLabel then
        errorLabel:setText("Minimum 50 monsters")
        errorLabel:setVisible(true)
        return false
    end

    TaskProtocol.sendStartTask(dialog.taskId, amount)
    dialog:destroy()
end

function TaskUI.createIconGridForDialog(container, task)
    if not container or not task.lookTypeIds or #task.lookTypeIds == 0 then
        return
    end
    container:destroyChildren()

    local monsterNames = task.monsterNames or {}
    local taskName = task.taskName or ""
    local cellSize = 64
    local spacing = -15
    local numIcons = #task.lookTypeIds

    local totalWidth = (numIcons * cellSize) + ((numIcons - 1) * spacing)
    container:setWidth(totalWidth)

    for idx, id in ipairs(task.lookTypeIds) do
        if type(id) == "number" and id > 0 then
            local icon = g_ui.createWidget("UICreature", container)
            icon:setSize({ width = cellSize, height = cellSize })
            local finalOutfit = { type = id }

            if monsterNames and idx <= #monsterNames then
                local mName = monsterNames[idx]
                local special = PLAYER_OUTFIT_TYPES[mName]
                if special and special.type == id then
                    finalOutfit = special
                end
            end

            if not finalOutfit.head and taskName ~= "" then
                local special = PLAYER_OUTFIT_TYPES[taskName]
                if special and special.type == id then
                    finalOutfit = special
                end
            end

            icon:setOutfit(finalOutfit)
            icon:setPhantom(true)
        end
    end
end

function TaskUI.onTaskMenuChange(button, option)
    local item = button:getParent()
    if not item or not item.taskData then
        return
    end
    local task = item.taskData

    if option == "Resume" then
        if TaskUI.checkPlayerPz() then
            return
        end
        TaskProtocol.sendResumeTask(task.taskId)
    elseif option == "Cancel" then
        selectedPausedTask = task
        TaskUI.cancelPausedTask()
    end
end

function TaskUI.taskRewardRequest()
    if not selectedActiveTask then
        print("ERROR: No taskId provided")
        return false
    end

    TaskProtocol.taskRewardRequest(selectedActiveTask.id)
end

function TaskUI.showClaimRewardDialog(goldStr, expStr, pointsStr)
    local gold = tonumber(goldStr) or 0
    local exp = tonumber(expStr) or 0
    local points = tonumber(pointsStr) or 0

    local rootPanel = modules.game_interface.getRootPanel()

    if rootPanel:getChildById('claimRewardDialog') then
        return
    end

    local dialog = g_ui.createWidget("ClaimRewardDialog", rootPanel)

    if not dialog then
        print("ERROR: Could not create ClaimRewardDialog")
        return
    end

    if selectedActiveTask then
        dialog.taskId = selectedActiveTask.id
    end

    dialog:recursiveGetChildById("goldAmount"):setText(TaskUI.formatGoldAmount(gold))
    dialog:recursiveGetChildById("expAmount"):setText(TaskUI.formatAmount(exp))
    dialog:recursiveGetChildById("taskPointsAmount"):setText("+ " .. points)
    dialog:recursiveGetChildById("splitGoldAmount"):setText(TaskUI.formatGoldAmount(math.floor(gold / 2)))
    dialog:recursiveGetChildById("splitExpAmount"):setText(TaskUI.formatAmount(math.floor(exp / 2)))
    local claimButton = dialog:recursiveGetChildById("claimButton")
    local pzWarningLabel = dialog:recursiveGetChildById("pzWarningLabel")

    local goldSection = dialog:recursiveGetChildById("goldSection")
    local expSection = dialog:recursiveGetChildById("expSection")
    local splitSection = dialog:recursiveGetChildById("splitSection")

    if not goldSection or not expSection or not splitSection then
        print("ERROR: Could not find reward sections")
        return
    end

    dialog.goldValue = gold
    dialog.expValue = exp
    dialog.pointsValue = points
    dialog.selectedReward = "gold"

    if selectedActiveTask.finished == 1 then
        claimButton:setEnabled(true)
    end

    local function updateBorders()
        goldSection:setBackgroundColor("#1a1a1a")
        expSection:setBackgroundColor("#1a1a1a")
        splitSection:setBackgroundColor("#1a1a1a")

        if dialog.selectedReward == "gold" then
            goldSection:setBackgroundColor("#2a3a1a")
        elseif dialog.selectedReward == "exp" then
            expSection:setBackgroundColor("#2a1a3a")
        elseif dialog.selectedReward == "split" then
            splitSection:setBackgroundColor("#2a3a1a")
        end
    end

    goldSection.onClick = function()
        dialog.selectedReward = "gold"
        updateBorders()
    end

    expSection.onClick = function()
        dialog.selectedReward = "exp"
        updateBorders()
    end

    splitSection.onClick = function()
        dialog.selectedReward = "split"
        updateBorders()
    end

    updateBorders()

    if TaskUI.checkPlayerPz(true) then
        if pzWarningLabel then
            pzWarningLabel:setVisible(true)
        end
        if claimButton then
            claimButton:setEnabled(false)
        end
    end

    dialog:show()
    dialog:raise()
    dialog:focus()
end

function TaskUI.confirmClaimReward()
    local rootPanel = modules.game_interface.getRootPanel()
    local dialog = rootPanel:getChildById('claimRewardDialog')

    if not dialog then
        return
    end

    if not dialog.taskId then
        print("ERROR: No taskId in dialog")
        return
    end

    if TaskUI.checkPlayerPz() then
        return
    end

    local selectedReward = dialog.selectedReward or "gold"
    local taskId = dialog.taskId

    TaskProtocol.confirmRewardClaiming(taskId, selectedReward)
end

function TaskUI.showPzBlockDialog()
    local rootPanel = modules.game_interface.getRootPanel()

    if rootPanel:getChildById('pzBlockDialog') then
        return
    end

    local dialog = g_ui.createWidget("PzBlockDialog", rootPanel)
    dialog:show()
    dialog:raise()
    dialog:focus()
end

function TaskUI.resetActiveTask()
    selectedActiveTask = nil
end

function TaskUI.checkPlayerPz(isClaimReward)
    local player = g_game.getLocalPlayer()
    if player and player:hasState(PlayerStates.Swords) and not isClaimReward then
        TaskUI.showPzBlockDialog()
        return true
    end
    return false
end

