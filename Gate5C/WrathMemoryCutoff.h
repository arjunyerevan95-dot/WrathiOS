#pragma once
#include <cstdint>
// Conservative diagnostic limits, not an OS-enforced allocation sandbox.
inline bool WrathMemoryShouldStop(bool valid,uint64_t footprint,uint64_t available) {
 return !valid || footprint>=1536ULL*1024*1024 || available<512ULL*1024*1024;
}
