-- CONFIG
DEV_MODE = false             -- true enables dev tools (terminal, stats, script reload). MUST be false in releases
APP_NAME = "danubia"          -- war "otclientv8" -- WICHTIG (siehe Kommentar im Original)
APP_VERSION = 1                -- war 1341, sinnvoller Startwert für euch

-- If you don't use updater or other service, set it to updater = ""
Services = {
  website = "https://projectdanubia.com",
  updater = "https://projectdanubia.com/api/Updater",  -- war "" -- DAS ist der wichtige
  stats = "",
  crash = "",                    -- otclient.ovh-Crash-Reporter würdet ihr sonst mitnutzen, eher nicht gewünscht
  feedback = "",                 -- gleicher Grund
}

Servers = {
  ProjectDanubia = "65.109.62.62:7171:800",  -- oder wie euer Login-Endpoint heißt/aussieht
  localHost = "127.0.0.1:7171:800",  -- oder wie euer Login-Endpoint heißt/aussieht
}

--Server = "ws://otclient.ovh:3000/"
--Server = "ws://127.0.0.1:88/"
--USE_NEW_ENERGAME = true -- uses entergamev2 based on websockets instead of entergame
ALLOW_CUSTOM_SERVERS = false -- if true it shows option ANOTHER on server list

g_app.setName("ProjectDanubia")
-- CONFIG END

-- print first terminal message
g_logger.info(os.date("== application started at %b %d %Y %X"))
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' .. g_app.getBuildCommit() .. ') made by ' .. g_app.getAuthor() .. ' built on ' .. g_app.getBuildDate() .. ' for arch ' .. g_app.getBuildArch())

if not g_resources.directoryExists("/data") then
  g_logger.fatal("Data dir doesn't exist.")
end

if not g_resources.directoryExists("/modules") then
  g_logger.fatal("Modules dir doesn't exist.")
end

-- settings
g_configs.loadSettings("/config.otml")

-- This client ships with the retro layout only.
g_resources.setLayout("retro")

-- load mods
g_modules.discoverModules()
g_modules.ensureModuleLoaded("corelib")
  
local function loadModules()
  -- libraries modules 0-99
  g_modules.autoLoadModules(99)
  g_modules.ensureModuleLoaded("gamelib")

  -- client modules 100-499
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded("client")

  -- dev tools only (never in releases)
  if DEV_MODE then
    g_modules.ensureModuleLoaded("client_terminal")
    g_modules.ensureModuleLoaded("client_stats")
  end

  -- game modules 500-999
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded("game_interface")

  -- mods 1000-9999
  g_modules.autoLoadModules(9999)
end

-- report crash
if type(Services.crash) == 'string' and Services.crash:len() > 4 and g_modules.getModule("crash_reporter") then
  g_modules.ensureModuleLoaded("crash_reporter")
end

-- run updater, must use data.zip
if type(Services.updater) == 'string' and Services.updater:len() > 4 
  and g_resources.isLoadedFromArchive() and g_modules.getModule("updater") then
  g_modules.ensureModuleLoaded("updater")
  return Updater.init(loadModules)
end
loadModules()
