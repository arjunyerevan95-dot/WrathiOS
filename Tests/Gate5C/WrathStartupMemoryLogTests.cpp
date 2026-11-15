#include "../../Gate5/WrathStartupMemoryLog.h"
#include <assert.h>
#include <limits.h>
#include <fstream>
#include <iostream>

int main(int argc, char **argv) {
    assert(argc == 2);
    char record[WrathStartupRecordBytes];
    WrathStartupMemorySample extreme = {UINT64_MAX, UINT64_MAX, UINT64_MAX, UINT64_MAX, UINT64_MAX,
        false, LLONG_MIN, LLONG_MAX, LLONG_MIN, LLONG_MAX};
    assert(WrathStartupEncodeRecord(record, extreme,
        "an-extremely-long-event-name-that-will-be-truncated-and-still-fit",
        "C:\\private\\source\\quotes\"and-newline\n.c"));
    assert(record[sizeof(record) - 1] == '\n');
    assert(strstr(record, "private") == nullptr);
    assert(strstr(record, "\"valid\":false") != nullptr);
    std::ofstream extremes(std::string(argv[1]) + ".extreme", std::ios::binary);
    extremes.write(record, sizeof(record));
    extremes.close();

    std::ofstream output(argv[1], std::ios::binary);
    assert(output.good());
    for (uint64_t seq = 0; seq < 4096; ++seq) {
        WrathStartupMemorySample sample = {seq, seq * 10, 6442456904ULL, 2000000000ULL, 17,
            true, 2868, 1320, 1, 32856};
        assert(WrathStartupEncodeRecord(record, sample, "texture-upload-enter", ""));
        output.seekp((std::streamoff)WrathStartupRecordOffset(seq));
        output.write(record, sizeof(record));
        assert(output.good());
    }
    assert(output.tellp() == WrathStartupRecordBytes * WrathStartupRecordSlots);
    output.close();
    std::cout << "Startup ring: extreme values, private-path removal, 4096 writes and bounded wrap passed\n";
}
