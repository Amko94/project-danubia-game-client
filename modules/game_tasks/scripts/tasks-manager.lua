TasksManager = {}

local activeTasks = {}
local availableTasks = {}

function TasksManager.init()
    TasksManager.clear()
end

function TasksManager.terminate()
    TasksManager.clear()
end

function TasksManager.clear()
    activeTasks = {}
    availableTasks = {}
end

function TasksManager.calculateTaskPointsReward(amount, experience, category)
    if amount > 1000 then
        amount = 1000
    end

    local categoryMultiplier = 1

    if category == 1 then
        categoryMultiplier = 0.1
    elseif category == 2 then
        categoryMultiplier = 0.5
    elseif category == 3 then
        categoryMultiplier = 1
    elseif category == 4 then
        categoryMultiplier = 1.5
    end

    local basePointsPerKill = (experience / 10000) * categoryMultiplier

    local totalTP = math.floor(basePointsPerKill * amount)

    totalTP = math.floor(totalTP / 2)

    return totalTP
end

function TasksManager.calculateGoldReward(amount, experience, category)

    if amount > 1000 then
        amount = 1000
    end
    local baseRewardPerKill = experience / 5

    if category >= 3 then
        baseRewardPerKill = baseRewardPerKill / 3
    end

    local totalGold = math.floor(baseRewardPerKill * amount)

    return totalGold
end

function TasksManager.calculateExperienceReward(amount, experience)
    if amount > 1000 then
        amount = 1000
    end

    local totalExp = math.floor(amount * experience * 0.55)

    return totalExp
end

function TasksManager.calculateExperienceReward(amount, experience)
    if amount > 1000 then
        amount = 1000
    end

    local totalExp = math.floor(amount * experience * 0.55)

    return totalExp
end

function TasksManager.updateTaskProgress(taskId, progress, amount)
    for _, task in ipairs(activeTasks) do
        if task.taskId == taskId then
            task.progress = progress
            task.amount = amount
            break
        end
    end
    if TaskUI then
        TaskUI.refresh()
    end
end

function TasksManager.isAvailableTasksLoaded()
    return #availableTasks > 0
end

function TasksManager.updateActiveTasks(data)
    activeTasks = data
    TaskUI.refresh()
end

function TasksManager.addAvailableTasks(data)
    local newlyAdded = false
    for _, newTask in ipairs(data) do
        local exists = false
        for _, existingTask in ipairs(availableTasks) do
            if existingTask.id == newTask.id then
                exists = true
                break
            end
        end

        if not exists then
            table.insert(availableTasks, newTask)
            newlyAdded = true
        end
    end

    if newlyAdded then
        TaskUI.onAvailableTasksUpdate()
    end
end

function TasksManager.getActiveTasks()
    return activeTasks
end

function TasksManager.getAvailableTasks()
    return availableTasks
end

function TasksManager.getTrackedTask()
    for _, task in ipairs(activeTasks) do
        if task.active == 1 and task.paused == 0 then
            return task
        end
    end
    return nil
end

function TasksManager.getTaskStatusByTaskId(taskId)
    for _, task in ipairs(activeTasks) do
        if task.taskId == taskId then
            return task
        end
    end
    return nil
end

function TasksManager.getMaxAmountForTask(taskId)
    for _, task in ipairs(availableTasks) do
        if task.id == taskId then
            return task.maxAmount or 0
        end
    end
    return 0
end

function TasksManager.getTaskNameById(taskId)
    for _, task in ipairs(availableTasks) do
        if task.id == taskId then
            return task.taskName
        end
    end
    return "Unknown"
end

function TasksManager.getTaskById(taskId)
    for _, task in ipairs(availableTasks) do
        if task.id == taskId then
            return task
        end
    end
    return nil
end

