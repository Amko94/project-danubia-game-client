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
#ifndef BOOST_PROCESS_VERSION
#define BOOST_PROCESS_VERSION 1
#endif
#include <boost/process/v1/args.hpp>
#include <boost/process/v1/child.hpp>
#include <thread>
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
// A binary that was just written to disk by the updater can be briefly
// locked by antivirus/real-time-scan (e.g. Windows Defender), which makes
// launching it right away fail with a transient error. Retry a few times
// before giving up, and surface the real error message instead of letting
// it bubble up as an opaque "C++ call failed" lua error.
void spawnRestartProcess(const std::string& binary, const std::vector<std::string>* args)
{
    // Windows Defender (and similar on-access scanners) can hold an exclusive
    // scan lock on a freshly-written, unsigned exe for several seconds before
    // releasing it - worth waiting out rather than failing the update.
    constexpr int MAX_ATTEMPTS = 30;
    constexpr auto RETRY_DELAY = std::chrono::milliseconds(500);

    std::string lastError;
    for (int attempt = 1; attempt <= MAX_ATTEMPTS; ++attempt) {
        try {
            boost::process::child c = args ? boost::process::child(binary, boost::process::args(*args))
                                            : boost::process::child(binary);
            std::error_code ec2;
            const bool exited = c.wait_for(std::chrono::seconds(1), ec2);
            if (exited && c.exit_code() != 0) {
                g_logger.fatal(stdext::format("Updater restart error, new process exited with code %i. Please restart application", c.exit_code()));
                return;
            }
            if (!exited)
                c.detach();
            return;
        } catch (const std::exception& e) {
            lastError = e.what();
            if (attempt < MAX_ATTEMPTS)
                std::this_thread::sleep_for(RETRY_DELAY);
        }
    }
    g_logger.fatal(stdext::format("Updater restart error, failed to launch %s: %s", binary, lastError));
}
}
#endif

void Application::restart()
{
#ifndef FREE_VERSION
    // prefer the exact binary just downloaded by the updater (if any) - the
    // bare binary name would otherwise resolve back to the OLD executable
    std::string binary = g_resources.getNewBinaryPath();
    if (binary.empty())
        binary = g_resources.getBinaryPath();
    spawnRestartProcess(binary, nullptr);
    quick_exit();
#else
    exit();
#endif
}

void Application::restartArgs(const std::vector<std::string>& args)
{
#ifndef FREE_VERSION
    std::string binary = g_resources.getNewBinaryPath();
    if (binary.empty())
        binary = g_resources.getBinaryPath();
    spawnRestartProcess(binary, &args);
    quick_exit();
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
