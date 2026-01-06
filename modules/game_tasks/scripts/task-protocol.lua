TaskProtocol = {}

TaskProtocol.SendOpcode = {
    ActivateTask = 0x01,
    RequestData = 0x03,
    RequestAll = 0x04,
    ResumeTask = 0x05,
    PauseTask = 0x06,
    CancelTask = 0x07,
    TaskRewardRequest = 0x08,
    ConfirmClaimReward = 0x09,
}

TaskProtocol.RecvOpcode = {
    TaskProgressUpdate = 1,
    ActiveTasks = 3,
    AvailablePart = 4,
    TaskResumed = 5,
    TaskRewardResponse = 8,
    ClaimRewardSuccess = 10,
    PauseTaskSuccess = 11,
    PlayerTaskPoints = 12,

    ResumeError = 101,
    TaskNoFinished = 102,

}

local PART_TOKEN = "TASKLIST_PART;"

function TaskProtocol.init()
    connect(g_game, { onGameStart = TaskProtocol.connect, onGameEnd = TaskProtocol.disconnect })
    if g_game.isOnline() then
        TaskProtocol.connect()
    end
end

function TaskProtocol.terminate()
    TaskProtocol.disconnect()
    disconnect(g_game, { onGameStart = TaskProtocol.connect, onGameEnd = TaskProtocol.disconnect })
end

function TaskProtocol.connect()
    local protocol = g_game.getProtocolGame()
    if protocol then
        connect(protocol, { onExtendedOpcode = TaskProtocol.onExtendedOpcode })
        TaskProtocol.requestTasksFromServer()
    end
end

function TaskProtocol.disconnect()
    local protocol = g_game.getProtocolGame()
    if protocol then
        disconnect(protocol, { onExtendedOpcode = TaskProtocol.onExtendedOpcode })
    end
end

function TaskProtocol.onExtendedOpcode(protocol, opcode, buffer)
    if opcode == TaskProtocol.RecvOpcode.ActiveTasks then
        local parts = string.split(buffer, ";", 2)
        local playerId = tonumber(parts[1])
        local jsonData = parts[2]

        local data = json.decode(jsonData)
        TasksManager.updateActiveTasks(data, playerId)

    elseif opcode == TaskProtocol.RecvOpcode.TaskProgressUpdate then
        if buffer:sub(1, 13) == "TASK_UPDATED;" then
            local parts = string.split(buffer, ";")
            local taskId = tonumber(parts[2])
            local progress = tonumber(parts[3])
            local amount = tonumber(parts[4])

            if taskId and progress and amount then
                TasksManager.updateTaskProgress(taskId, progress, amount)
            end
        end


    elseif opcode == TaskProtocol.RecvOpcode.AvailablePart then
        if buffer:sub(1, #PART_TOKEN) == PART_TOKEN then
            local data = json.decode(buffer:sub(#PART_TOKEN + 1))
            TasksManager.addAvailableTasks(data)
        end

    elseif opcode == TaskProtocol.RecvOpcode.PlayerTaskPoints then
        local parts = string.split(buffer, ";", 2)
        local playerId = tonumber(parts[1])
        local taskPoints = tonumber(parts[2])
        TasksManager.playerTaskPoints = taskPoints
        TasksManager.currentPlayerId = playerId

    elseif opcode == TaskProtocol.RecvOpcode.TaskResumed then
        TaskProtocol.requestTasksFromServer()

    elseif opcode == TaskProtocol.RecvOpcode.ResumeError then
        if TaskUI then
            TaskUI.showStartTaskError()
        end

    elseif opcode == TaskProtocol.RecvOpcode.TaskRewardResponse then
        if TaskUI then

            local parts = string.split(buffer, ";")
            local gold = tonumber(parts[1]) or 0
            local exp = tonumber(parts[2]) or 0
            local points = tonumber(parts[3]) or 0

            TaskUI.showClaimRewardDialog(gold, exp, points)
        end

    elseif opcode == TaskProtocol.RecvOpcode.ClaimRewardSuccess then
        TaskUI.hide()


    elseif opcode == TaskProtocol.RecvOpcode.PauseTaskSuccess then
        if TaskUI then
            TaskUI.resetActiveTask()
        end
    end
end

function TaskProtocol.requestTasksFromServer()
    local protocol = g_game.getProtocolGame()
    if protocol and protocol:isConnected() then

        if not TasksManager.isAvailableTasksLoaded() then
            protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.RequestAll, "")
        end
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.RequestData, "")
    end
end

function TaskProtocol.sendStartTask(id, amount)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.ActivateTask, id .. ";" .. amount)
    end
end

function TaskProtocol.sendResumeTask(id)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.ResumeTask, id)
    end
end

function TaskProtocol.sendPauseTask(id)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.PauseTask, id)
    end
end

function TaskProtocol.sendGetReward(id)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.RequestData, id)
    end
end

function TaskProtocol.cancelTask(id)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.CancelTask, id)
    end
end

function TaskProtocol.confirmRewardClaiming(taskId, selectedReward)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.ConfirmClaimReward, taskId .. ";" .. selectedReward)
    end
end

function TaskProtocol.taskRewardRequest(taskId)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(TaskProtocol.SendOpcode.TaskRewardRequest, tostring(taskId))
    end
end


