#pragma once
#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <mutex>

// Opt-in, bounded diagnostics; no packet contents or player information.
namespace LagDiagnostics {
enum Event { Session, FrameGap, ProcessingGap, WalkWait, LateConfirmation, PositionCorrection, WalkCancel, EventCount };
inline bool enabled = false;
inline std::ofstream output;
inline std::mutex outputMutex;
inline std::array<std::chrono::steady_clock::time_point, EventCount> lastReport{};

inline void record(Event event, int64_t durationMs) {
    if (!enabled) return;
    std::unique_lock<std::mutex> lock(outputMutex, std::try_to_lock);
    if (!lock.owns_lock() || !output.good() || output.tellp() >= std::streampos(2 * 1024 * 1024)) return;
    const auto now = std::chrono::steady_clock::now();
    if (now - lastReport[event] < std::chrono::seconds(1)) return;
    lastReport[event] = now;
    static const char* labels[] = {"session", "frame-gap", "processing-gap", "walk-wait", "late-confirmation", "position-correction", "walk-cancel"};
    const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    output << timestamp << " event=" << labels[event] << " duration_ms=" << durationMs << '\n';
    output.flush();
}

inline bool start(const std::filesystem::path& path) {
    output.open(path, std::ios::out | std::ios::trunc);
    enabled = output.good();
    record(Session, 0);
    return enabled;
}
}
