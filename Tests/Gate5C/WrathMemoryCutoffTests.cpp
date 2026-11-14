#include "WrathMemoryCutoff.h"
#include <cassert>
int main(){
 const uint64_t M=1024*1024;
 assert(!WrathMemoryShouldStop(true,1536*M-1,512*M));
 assert(WrathMemoryShouldStop(true,1536*M,512*M));
 assert(WrathMemoryShouldStop(true,100*M,512*M-1));
 assert(WrathMemoryShouldStop(false,0,1024*M));
}
