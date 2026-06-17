function init()
    TasksManager.init()
    TaskUI.init()
    TaskProtocol.init()

    if modules.client_topmenu then
        modules.client_topmenu.addRightGameToggleButton("taskButton", tr("Tasks"), "/images/topbuttons/tasks", TaskUI.toggle)
    end
end

function terminate()
    TaskProtocol.terminate()
    TaskUI.terminate()
    TasksManager.terminate()
end