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
#include <cerrno>
#include <cstdlib>
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
#endif
#ifdef WIN32
#include <windows.h>
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

    // Arguments have already been decoded and restart arguments consumed in main.
    m_startupArgs.assign(args.begin() + 1, args.end());

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
    m_restartCancelled = true;
    if (m_restartThread.joinable())
        m_restartThread.join();

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
    m_restartCancelled = true;
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
// Quote according to CommandLineToArgvW, including quotes and trailing slashes.
std::wstring quoteArgument(const std::wstring& arg)
{
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (wchar_t c : arg) {
        if (c == L'\\') {
            ++slashes;
            continue;
        }
        result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        result += c;
        slashes = 0;
    }
    result.append(slashes * 2, L'\\');
    return result + L'"';
}

// The child waits for this process to exit before opening settings or deleting
// the old executable. Waiting for its input idle here would deadlock that handoff.
int launchBinary(const std::string& binary, const std::vector<std::string>& args)
{
    std::wstring path = std::filesystem::path(binary).wstring();
    std::wstring commandLine = quoteArgument(path);
    for (const std::string& arg : args)
        commandLine += L" " + quoteArgument(stdext::utf8_to_utf16(arg));
    commandLine += L" --wait-for-parent " + std::to_wstring(GetCurrentProcessId());

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {};
    if (!CreateProcessW(path.c_str(), &commandLine[0], NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

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

}
#endif

bool Application::prepareStartup(std::vector<std::string>& args)
{
    g_platform.processArgs(args);
#ifdef WIN32
    auto flag = std::find(args.begin() + 1, args.end(), "--wait-for-parent");
    if (flag != args.end()) {
        if (flag + 1 == args.end())
            return false;
        const std::string pidText = *(flag + 1);
        char* end = nullptr;
        errno = 0;
        unsigned long pid = std::strtoul(pidText.c_str(), &end, 10);
        if (pidText.empty() || pidText.find_first_not_of("0123456789") != std::string::npos ||
            errno == ERANGE || *end != '\0' || pid == 0 || pid == GetCurrentProcessId())
            return false;
        HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, pid);
        if (parent) {
            DWORD result = WaitForSingleObject(parent, 60000);
            CloseHandle(parent);
            if (result != WAIT_OBJECT_0)
                return false;
        } else if (GetLastError() != ERROR_INVALID_PARAMETER) {
            return false;
        }
        args.erase(flag, flag + 2);
    }
#endif
    return true;
}

void Application::restart()
{
#ifndef FREE_VERSION
    restartArgs(m_startupArgs);
#else
    exit();
#endif
}

void Application::restartArgs(const std::vector<std::string>& args)
{
#ifndef FREE_VERSION
    if (m_restarting)
        return;
    if (m_restartThread.joinable())
        m_restartThread.join();
    m_restarting = true;
    m_restartCancelled = false;
    // prefer the exact binary just downloaded by the updater (if any) - the
    // bare binary name would otherwise resolve back to the OLD executable
    std::string binary = g_resources.getNewBinaryPath();
    if (binary.empty())
        binary = g_resources.getBinaryPath();
    // Defender can temporarily lock a downloaded EXE. Keep the UI responsive
    // while retrying and retain this instance if Windows cannot start the child.
    m_restartThread = std::thread([this, binary, args] {
        bool started = false;
        int error = 0;
        for (int attempt = 0; attempt < 180 && !m_restartCancelled; ++attempt) {
            error = launchBinary(binary, args);
            if ((started = error == 0))
                break;
            for (int tick = 0; tick < 10 && !m_restartCancelled; ++tick)
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (m_restartCancelled)
            return;
        g_dispatcher.addEvent([this, started, error] {
            if (started) {
                exit();
            } else {
                m_restarting = false;
                g_logger.warning(stdext::format("Restart failed (error %d)", error));
                g_lua.callGlobalField("g_app", "onRestartFailed");
            }
        });
    });
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
