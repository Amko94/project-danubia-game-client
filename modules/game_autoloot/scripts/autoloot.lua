function init()
    AutoLootManager.init()
    AutoLootUI.init()

    if modules.client_topmenu then
        modules.client_topmenu.addRightGameToggleButton("autoLootButton", tr("Auto Loot"), "/images/topbarButtons/shop", AutoLootUI.toggle)
    end
end

function terminate()
    AutoLootUI.terminate()
    AutoLootManager.terminate()
end
