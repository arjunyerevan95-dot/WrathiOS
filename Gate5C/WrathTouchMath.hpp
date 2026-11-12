#pragma once
#include <algorithm>
#include <cmath>
namespace wrathios::touch {
struct Vector { double x=0,y=0; };
inline Vector Gyro(double x,double y,bool landscapeRight) {
 const double sign=landscapeRight?-1:1;
 return {-x*sign,y*sign}; // screen-horizontal yaw, screen-vertical pitch, radians/sec
}
inline Vector Stick(Vector delta,double radius=54) {
 double length=std::hypot(delta.x,delta.y);
 if(length<=radius*.12)return {};
 double magnitude=std::min(1.0,(length/radius-.12)/.88);
 return {delta.x/length*magnitude,-delta.y/length*magnitude};
}
inline double SafeDelta(double dt){return std::clamp(dt,0.0,.05);}
}

#include <deque>
namespace wrathios::touch {
struct PointerEvent { float x=0,y=0; int button=0; };
struct Pointer {
 std::deque<PointerEvent> events;
 PointerEvent last;
 bool down=false,release=false,valid=false;
 double until=0;
 void input(float x,float y,int button,double now){last={x,y,button};valid=true;until=now+.35;if(button)events.push_back(last);}
 bool owns(double now)const{return valid&&(!events.empty()||down||now<until);}
 PointerEvent point()const{return events.empty()?last:events.front();}
 int next(){if(events.empty())return 0;int edge=events.front().button;events.pop_front();down=edge==1;return edge;}
 void reset(){release=release||down;down=false;valid=false;events.clear();}
 bool takeRelease(){bool r=release;release=false;return r;}
};
}
