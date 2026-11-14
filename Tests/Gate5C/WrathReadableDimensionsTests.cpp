#include "WrathReadableDimensions.h"
#include <cassert>
#include <initializer_list>
#include <cstdio>
int main() {
 for (auto width : {1600, 1912, 2048}) {
  auto r = WrathReadableUI(width, 880, width/2, 440, 1);
  assert(r.width == width/4.0f && r.height == 220);
  // 12 logical units stays 24 UIKit points, now 48 scene pixels.
  assert(12.0f * width/r.width/2 == 24);
  auto again=WrathReadableUI(width,880,r.width,r.height,1);
  assert(again.width==r.width && again.height==r.height);
  auto off=WrathReadableUI(width,880,width/2,440,0);
  assert(off.width==width/2 && off.height==440);
  auto custom=WrathReadableUI(width,880,700,350,1);
  assert(custom.width==700 && custom.height==350);
 }
 puts("Readable UI: physical size, repeat, opt-out and custom dimensions passed");
}
