#include "lagdiagnostics.h"
#include <cassert>
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    if (argc != 2) return 1;
    const std::filesystem::path path(argv[1]);
    LagDiagnostics::record(LagDiagnostics::FrameGap, 80);
    assert(!std::filesystem::exists(path));
    assert(LagDiagnostics::start(path));
    LagDiagnostics::record(LagDiagnostics::FrameGap, 80);
    LagDiagnostics::record(LagDiagnostics::FrameGap, 90);
    LagDiagnostics::record(LagDiagnostics::WalkWait, 120);
    LagDiagnostics::output.close();
    std::ifstream input(path);
    std::string line;
    int lines = 0;
    while (std::getline(input, line)) {
        ++lines;
        if (lines == 1) assert(line.find("event=session") != std::string::npos);
        if (lines == 2) assert(line.find("event=frame-gap duration_ms=80") != std::string::npos);
        if (lines == 3) assert(line.find("event=walk-wait duration_ms=120") != std::string::npos);
    }
    assert(lines == 3);
    std::cout << "PASS: disabled by default, log creation, distinct event types, per-event rate limit\n";
}
