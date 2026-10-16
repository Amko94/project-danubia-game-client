/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "application.h"
#include <csignal>
#include <framework/core/clock.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/modulemanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/configmanager.h>
#include "asyncdispatcher.h"
#include <framework/luaengine/luainterface.h>
#include <framework/platform/crashhandler.h>
#include <framework/platform/platform.h>
#include <framework/http/http.h>

#ifndef FREE_VERSION
#include <atomic>
#include <filesystem>
#include <thread>
#ifdef WIN32
#include <windows.h>
#endif
#endif

#include <locale>

#include <framework/net/connection.h>
#include <framework/proxy/proxy.h>

void exitSignalHandler(int sig)
{
    static bool signaled = false;
    switch(sig) {
        case SIGTERM:
        case SIGINT:
            if(!signaled && !g_app.isStopping() && !g_app.isTerminated()) {
                signaled = true;
                g_dispatcher.addEvent(std::bind(&Application::close, &g_app));
            }
            break;
    }
}

Application::Application()
{
    m_appName = "application";
    m_appCompactName = "app";
    m_appVersion = "none";
    m_charset = "cp1252";
    m_stopping = false;
}

void Application::init(std::vector<std::string>& args)
{
    // capture exit signals
    signal(SIGTERM, exitSignalHandler);
    signal(SIGINT, exitSignalHandler);

    // setup locale
    std::locale::global(std::locale());

    // process args encoding
    g_platform.processArgs(args);

    g_asyncDispatcher.init();

    std::string startupOptions;
    for(uint i=1;i<args.size();++i) {
        const std::string& arg = args[i];
        startupOptions += " ";
        startupOptions += arg;
    }
    if(startupOptions.length() > 0)
        g_logger.info(stdext::format("Startup options: %s", startupOptions));

    m_startupOptions = startupOptions;

    // initialize configs
    g_configs.init();

    // initialize lua
    g_lua.init();
    registerLuaFunctions();

    // initalize proxy
    g_proxy.init();
}

void Application::deinit()
{
    g_lua.callGlobalField("g_app", "onTerminate");

    // run modules unload events
    g_modules.unloadModules();
    g_modules.clear();

    // release remaining lua object references
    g_lua.collectGarbage();

    // poll remaining events
    poll();

    // disable dispatcher events
    g_dispatcher.shutdown();
}

void Application::terminate()
{
    // terminate network
    Connection::terminate();

    // release configs
    g_configs.terminate();

    // release resources
    g_resources.terminate();

    // terminate script environment
    g_lua.terminate();

    // terminate proxy
    g_proxy.terminate();

    m_terminated = true;

    signal(SIGTERM, SIG_DFL);
    signal(SIGINT, SIG_DFL);
}

void Application::poll()
{
    Connection::poll();

    g_dispatcher.poll();

    // poll connection again to flush pending write
    Connection::poll();
}

void Application::exit()
{
    g_lua.callGlobalField<bool>("g_app", "onExit");
    m_stopping = true;
}

void Application::quick_exit()
{
#ifdef _MSC_VER
    ::quick_exit(0);
#else
    ::exit(0);
#endif
}

void Application::close()
{
    if(!g_lua.callGlobalField<bool>("g_app", "onClose"))
        exit();
}

#ifndef FREE_VERSION
namespace {
#ifdef WIN32
// Starts the binary and waits (bounded) until the new process has its window
// up and is idle waiting for input, so the old client only disappears once the
// new one is actually there. Returns 0 on success, otherwise the error code.
int launchBinary(const std::string& binary, const std::vector<std::string>& args)
{
    std::wstring path = std::filesystem::path(binary).wstring();
    std::wstring commandLine = L"\"" + path + L"\"";
    for (const std::string& arg : args)
        commandLine += L" \"" + stdext::utf8_to_utf16(arg) + L"\"";

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {};
    if (!CreateProcessW(path.c_str(), &commandLine[0], NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

    DWORD exitCode = STILL_ACTIVE;
    for (int i = 0; i < 200 && WaitForInputIdle(pi.hProcess, 100) == WAIT_TIMEOUT; ++i) {
        if (GetExitCodeProcess(pi.hProcess, &exitCode) && exitCode != STILL_ACTIVE)
            break;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
#else
int launchBinary(const std::string& binary, const std::vector<std::string>& args)
{
    return g_platform.spawnProcess(binary, args) ? 0 : -1;
}
#endif

// A running process can't swap its own exe/dlls, so restarting means starting
// the (just updated) binary and closing this one. A freshly written, unsigned
// exe can stay locked by an antivirus scan (Windows Defender) for anything from
// a few seconds up to ~2 minutes, so launching is retried on a background
// thread while the client stays open and responsive. This instance only exits
// once the new one is running; if it never starts, g_app.onRestartFailed is
// called instead and the client keeps running.
void restartInBackground(const std::string& binary, const std::vector<std::string>& args)
{
    static std::atomic<bool> restarting(false);
    if (restarting.exchange(true))
        return;

    g_logger.info(stdext::format("Restarting, launching %s", binary));
    std::thread([binary, args] {
        constexpr int MAX_ATTEMPTS = 180;
        bool started = false;
        for (int attempt = 1; attempt <= MAX_ATTEMPTS && !g_app.isStopping(); ++attempt) {
            int error = launchBinary(binary, args);
            if ((started = error == 0))
                break;
            if (attempt == 1 || attempt % 30 == 0)
                g_logger.info(stdext::format("Restart: can't launch %s yet (error %d, attempt %d), retrying", binary, error, attempt));
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        if (g_app.isStopping())
            return;

        g_dispatcher.addEvent([started, binary] {
            if (started) {
                g_app.exit();
                return;
            }
            restarting = false;
            g_logger.warning(stdext::format("Restart failed, could not launch %s", binary));
            g_lua.callGlobalField("g_app", "onRestartFailed");
        });
    }).detach();
}
}
#endif

void Application::restart()
{
#ifndef FREE_VERSION
    restartArgs({});
#else
    exit();
#endif
}

void Application::restartArgs(const std::vector<std::string>& args)
{
#ifndef FREE_VERSION
    // prefer the exact binary just downloaded by the updater (if any) - the
    // bare binary name would otherwise resolve back to the OLD executable
    std::string binary = g_resources.getNewBinaryPath();
    if (binary.empty())
        binary = g_resources.getBinaryPath();
    restartInBackground(binary, args);
#else
    exit();
#endif
}

std::string Application::getOs()
{
#if defined(WIN32)
    return "windows";
#elif defined(__APPLE__)
    return "mac";
#elif __linux
    return "linux";
#else
    return "unknown";
#endif
}
