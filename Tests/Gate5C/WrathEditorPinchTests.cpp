#include "../../Gate5C/WrathTouchMath.hpp"
#include <cassert>
#include <limits>
int main(){using wrathios::touch::PinchSize;
 static_assert(wrathios::touch::SwipeMaximum==2.0);static_assert(wrathios::touch::GyroMaximum==5.0);
 assert(PinchSize(1,1.5)==1.5);assert(PinchSize(1,100)==1.8);
 assert(PinchSize(1,.01)==.65);assert(PinchSize(1,0)==1);
 assert(PinchSize(1,-2)==1);assert(PinchSize(1,std::numeric_limits<double>::quiet_NaN())==1);
 assert(PinchSize(std::numeric_limits<double>::infinity(),1)==1);
 assert(PinchSize(1.2,1)==1.2);
}
