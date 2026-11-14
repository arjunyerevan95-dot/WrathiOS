#include "WrathReadableDimensions.h"
#include <cassert>
#include <initializer_list>
#include <cstdio>
int main() {
 for (auto width : {1600, 1912, 2048}) {
  auto r = WrathReadableUI(width, 880, static_cast<float>(width/2), 440, 1);
  assert(r.width == width/4.0f && r.height == 220);
  // 12 logical units stays 24 UIKit points, now 48 scene pixels.
  assert(12.0f * width/r.width/2 == 24);
  auto again=WrathReadableUI(width,880,r.width,r.height,1);
  assert(again.width==r.width && again.height==r.height);
  auto off=WrathReadableUI(width,880,static_cast<float>(width/2),440,0);
  assert(off.width==static_cast<float>(width/2) && off.height==440);
  auto custom=WrathReadableUI(width,880,700,350,1);
  assert(custom.width==700 && custom.height==350);
 }
 for(auto pixels : {3000,2010,1500}){
  auto r=WrathReadableUIScaled(pixels,pixels/2,1000,500,static_cast<float>(pixels/2),static_cast<float>(pixels/4),1);
  assert(r.width==500 && r.height==250);
  auto custom=WrathReadableUIScaled(pixels,pixels/2,1000,500,723,311,1);assert(custom.width==723&&custom.height==311);
  auto off=WrathReadableUIScaled(pixels,pixels/2,1000,500,static_cast<float>(pixels/2),static_cast<float>(pixels/4),0);assert(off.width==pixels/2);
 }
 puts("Readable UI: physical size, repeat, opt-out and custom dimensions passed");
}
