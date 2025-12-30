TaskProtocol = {}

TaskProtocol.SendOpcode = {
    ActivateTask = 0x01,
    RequestData = 0x03,
    RequestAll = 0x04,
    ResumeTask = 0x05,
    PauseTask = 0x06,
    CancelTask = 0x07
}

TaskProtocol.RecvOpcode = {
    TaskProgressUpdate = 1,
    ActiveTasks = 3,
    AvailablePart = 4,
    TaskResumed = 5,
    ResumeError = 101
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
        local data = safeJsonDecode(buffer)
        TasksManager.updateActiveTasks(data)

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
            local data = safeJsonDecode(buffer:sub(#PART_TOKEN + 1))
            TasksManager.addAvailableTasks(data)
        end

    elseif opcode == TaskProtocol.RecvOpcode.TaskResumed then
        TaskProtocol.requestTasksFromServer()

    elseif opcode == TaskProtocol.RecvOpcode.ResumeError then
        if TaskUI then
            TaskUI.showStartTaskError()
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