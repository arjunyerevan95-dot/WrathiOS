#include "WrathTouchMath.hpp"
#include <cassert>
#include <iostream>
using namespace wrathios::touch;
int main(){
 auto l=Gyro(1,2,false),r=Gyro(1,2,true);assert(l.x==-1&&l.y==2&&r.x==1&&r.y==-2);
 assert(Stick({0,0}).x==0);assert(Stick({2,2}).y==0);
 auto stick=Stick({54,-54});assert(stick.x>0&&stick.y>0&&std::hypot(stick.x,stick.y)<=1.00001);
 assert(SafeDelta(-1)==0&&SafeDelta(1)==.05);
 Pointer p;p.input(.2f,.3f,1,1);p.input(.8f,.9f,2,1.1);
 assert(p.point().x==.2f&&p.next()==1);assert(p.point().x==.8f&&p.next()==2);
 assert(!p.owns(2)); // controller takeover, no permanent mouse ownership
 p.input(.1f,.1f,1,3);p.reset();assert(p.next()==0&&!p.takeRelease()); // cancelled before delivery
 p.input(.1f,.1f,1,4);assert(p.next()==1);p.reset();assert(p.takeRelease()&&!p.takeRelease()); // cancel after delivery
 p.input(.1f,.1f,1,5);p.input(.1f,.1f,2,5);p.input(.9f,.9f,1,5);p.input(.9f,.9f,2,5);
 assert(p.next()==1&&p.next()==2&&p.next()==1&&p.next()==2); // rapid taps remain paired
 p.input(.1f,.1f,1,6);p.next();p.reset();p.reset();assert(p.takeRelease()); // repeated reset preserves release
 std::cout<<"Native touch: gyro orientation, deadzone, dt, pointer ordering, rapid taps, cancellation, reset and controller takeover passed\n";
}
