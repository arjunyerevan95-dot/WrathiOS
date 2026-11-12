#import "WrathSemanticMenuBridge.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#include "WrathTouchMath.hpp"
#include <deque>
#include <mutex>

namespace {
using wrathios::touch::PointerEvent;
struct State {
 std::mutex mutex;
 bool menu=false,game=false,suspended=false;
 wrathios::touch::Pointer pointer;
 float width=640,height=480,x=0,y=0,lookX=0,lookY=0,moveX=0,moveY=0;
 unsigned buttons=0;
 std::deque<int> keys;
};
State &S(){static State s;return s;}
void ResetLocked(State &s){s.pointer.reset();s.lookX=s.lookY=s.moveX=s.moveY=0;s.buttons=0;s.keys.clear();for(int i=1;i<=4;i++)s.keys.push_back(-i);}
constexpr NSInteger tag=0x57524335;
}

@interface WrathSemanticTouchSurface : UIView {
 NSMutableDictionary<NSValue *,NSNumber *> *_owners;
 NSMutableDictionary<NSValue *,NSValue *> *_last;
 CGPoint _moveOrigin;
 CMMotionManager *_motion;
 UIInterfaceOrientation _orientation;
 double _sampleTime;
 BOOL _wasGame;
 int _lastMode;
}
- (void)refresh;
- (void)reset;
@end
@implementation WrathSemanticTouchSurface
- (instancetype)initWithFrame:(CGRect)frame {
 if(!(self=[super initWithFrame:frame]))return nil;
 NSLog(@"WRATHIOS_NATIVE_TOUCH_V12");
 self.backgroundColor=UIColor.clearColor;self.multipleTouchEnabled=YES;
 self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 _owners=[NSMutableDictionary new];_last=[NSMutableDictionary new];_motion=[CMMotionManager new];
 _motion.deviceMotionUpdateInterval=1.0/100;
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
 return self;
}
- (void)dealloc {[_motion stopDeviceMotionUpdates];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)reset {
 [_owners removeAllObjects];[_last removeAllObjects];_sampleTime=0;
 auto &s=S();std::scoped_lock lock(s.mutex);ResetLocked(s);
}
- (void)inactive:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=true;}[_motion stopDeviceMotionUpdates];}
- (void)active:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=false;}[self refresh];}
- (void)refresh {
 bool game,enabled;{auto &s=S();std::scoped_lock lock(s.mutex);game=s.game&&!s.suspended;enabled=(s.menu||s.game)&&!s.suspended;}
 UIInterfaceOrientation orientation=self.window.windowScene.interfaceOrientation;
 int mode=enabled?(game?2:1):0;
 if(_lastMode!=mode||(_orientation!=UIInterfaceOrientationUnknown&&orientation!=_orientation))[self reset];
 _lastMode=mode;_wasGame=game;_orientation=orientation;
 self.hidden=!enabled;self.userInteractionEnabled=enabled;
 if(!game){[_motion stopDeviceMotionUpdates];_sampleTime=0;}
 else if(!_motion.deviceMotionActive&&_motion.deviceMotionAvailable){
  __weak WrathSemanticTouchSurface *weakSelf=self;
  [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical toQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *m,NSError *error){
   WrathSemanticTouchSurface *v=weakSelf;if(!v||error||!m)return;
   if(NSProcessInfo.processInfo.systemUptime-m.timestamp>.15)return;
   double now=m.timestamp,dt=v->_sampleTime?wrathios::touch::SafeDelta(now-v->_sampleTime):0;v->_sampleTime=now;
   UIInterfaceOrientation o=v.window.windowScene.interfaceOrientation;
   if(o!=UIInterfaceOrientationLandscapeLeft&&o!=UIInterfaceOrientationLandscapeRight)return;
   auto rate=wrathios::touch::Gyro(m.rotationRate.x,m.rotationRate.y,o==UIInterfaceOrientationLandscapeRight);
   if(fabs(rate.x)<.018)rate.x=0;if(fabs(rate.y)<.018)rate.y=0;
   auto &s=S();std::scoped_lock lock(s.mutex);
   if(s.game&&!s.suspended){s.lookX+=rate.x*57.2957795*dt;s.lookY+=rate.y*57.2957795*dt;}
  }];
 }
 [self setNeedsDisplay];
}
- (CGRect)buttonRect:(int)b {
 CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
 if(b==0)return CGRectMake(w-88,h-160,70,70); // fire
 if(b==1)return CGRectMake(w-172,h-84,66,66); // jump
 if(b==2)return CGRectMake(w-88,h-246,70,62); // alternate fire
 return CGRectMake(w-90,16,72,42); // menu
}
- (void)drawRect:(CGRect)rect {
 (void)rect;if(!_wasGame)return;
 NSArray *names=@[@"FIRE",@"JUMP",@"ALT",@"MENU"];
 for(int i=0;i<4;i++){
  CGRect r=[self buttonRect:i];[[UIColor colorWithWhite:0 alpha:.28] setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:16] fill];
  [names[i] drawInRect:CGRectInset(r,8,18) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }
 [@"MOVE" drawAtPoint:CGPointMake(65,self.bounds.size.height-95) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
}
- (void)menuPoint:(CGPoint)p button:(int)button {
 auto &s=S();std::scoped_lock lock(s.mutex);
 s.x=std::clamp((float)(p.x/MAX(1,self.bounds.size.width)),0.f,1.f);
 s.y=std::clamp((float)(p.y/MAX(1,self.bounds.size.height)),0.f,1.f);s.pointer.input(s.x,s.y,button,CACurrentMediaTime());

}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 (void)event;bool menu;{auto &s=S();std::scoped_lock lock(s.mutex);menu=s.menu;}
 for(UITouch *t in touches){
  NSValue *key=[NSValue valueWithNonretainedObject:t];CGPoint p=[t locationInView:self];
  int owner=-1;
  if(menu){if(_owners.count)continue;owner=10;[self menuPoint:p button:1];}
  else {
   for(int b=0;b<4;b++)if(CGRectContainsPoint([self buttonRect:b],p)){owner=b;break;}
   if(owner<0)owner=p.x<self.bounds.size.width*.42?4:5;
   if((owner==4||owner==5)&&[_owners.allValues containsObject:@(owner)])continue;
   if(owner==4)_moveOrigin=p;
   if(owner<4){auto &s=S();std::scoped_lock lock(s.mutex);if(!(s.buttons&(1u<<owner)))s.keys.push_back(owner+1);s.buttons|=1u<<owner;}
  }
  _owners[key]=@(owner);_last[key]=[NSValue valueWithCGPoint:p];
 }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 (void)event;
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;
  int owner=n.intValue;CGPoint p=[t locationInView:self],last=[_last[key] CGPointValue];
  if(owner==10)[self menuPoint:p button:0];
  else {auto &s=S();std::scoped_lock lock(s.mutex);
   if(owner==5){s.lookX+=(p.x-last.x)*.15;s.lookY+=(p.y-last.y)*.15;}
   if(owner==4){auto stick=wrathios::touch::Stick({p.x-_moveOrigin.x,p.y-_moveOrigin.y});s.moveX=stick.x;s.moveY=stick.y;}
  }
  _last[key]=[NSValue valueWithCGPoint:p];
 }
}
- (void)finish:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;int owner=n.intValue;
  if(owner==10){if(cancelled){auto &s=S();std::scoped_lock lock(s.mutex);s.pointer.reset();}else [self menuPoint:[t locationInView:self] button:2];}
  [_owners removeObjectForKey:key];[_last removeObjectForKey:key];
  auto &s=S();std::scoped_lock lock(s.mutex);
  if(owner==4)s.moveX=s.moveY=0;
  if(owner<4&&![_owners.allValues containsObject:@(owner)]){s.buttons&=~(1u<<owner);s.keys.push_back(-(owner+1));}
 }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches cancelled:NO];}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches cancelled:YES];}
@end

namespace {
void Refresh(){
 // Engine and UIKit run on the same thread; never dispatch input behind Host_Main.
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
  if(scene.activationState!=UISceneActivationStateForegroundActive||![scene isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *w in ((UIWindowScene *)scene).windows.reverseObjectEnumerator){
   if(w.hidden||!w.isKeyWindow)continue;
   WrathSemanticTouchSurface *surface=(WrathSemanticTouchSurface *)[w viewWithTag:tag];
   if(!surface){surface=[[WrathSemanticTouchSurface alloc]initWithFrame:w.bounds];surface.tag=tag;[w addSubview:surface];}
   [w bringSubviewToFront:surface];[surface refresh];return;
  }
 }
}
}
const unsigned char *WrathIOSGate5CMenuProgramData(long long *size){static NSData *data;static dispatch_once_t once;dispatch_once(&once,^{data=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"wrathios-menu" withExtension:@"dat"]];});if(size)*size=data.length;return (const unsigned char *)data.bytes;}
void WrathIOSGate5CSnapshotBegin(int menu,float w,float h){(void)menu;auto &s=S();std::scoped_lock lock(s.mutex);if(w>0&&h>0){s.width=w;s.height=h;}}
void WrathIOSGate5CSnapshotEntry(int e,float x,float y,float w,float h,int f,int o){(void)e;(void)x;(void)y;(void)w;(void)h;(void)f;(void)o;}
void WrathIOSGate5CSnapshotEnd(int hover){(void)hover;}
int WrathIOSGate5CPointer(float *x,float *y){auto &s=S();std::scoped_lock lock(s.mutex);if(!s.menu||!s.pointer.owns(CACurrentMediaTime()))return 0;auto p=s.pointer.point();if(x)*x=p.x;if(y)*y=p.y;return 1;}
int WrathIOSGate5CNextButtonEvent(void){auto &s=S();std::scoped_lock lock(s.mutex);return s.pointer.next();}
int WrathIOSTouchTakeMenuRelease(void){auto &s=S();std::scoped_lock lock(s.mutex);return s.pointer.takeRelease();}
void WrathIOSGate5CSetMenuActive(int active){auto &s=S();{std::scoped_lock lock(s.mutex);if(s.menu!=(active!=0)){ResetLocked(s);s.menu=active!=0;if(active)s.game=false;}}Refresh();}
void WrathIOSTouchSetMode(int menu,int game){auto &s=S();{std::scoped_lock lock(s.mutex);if(s.menu!=(menu!=0)||s.game!=(game!=0)){ResetLocked(s);s.menu=menu!=0;s.game=game!=0;}}Refresh();}
int WrathIOSTouchNextKey(void){auto &s=S();std::scoped_lock lock(s.mutex);if(s.keys.empty())return 0;int key=s.keys.front();s.keys.pop_front();return key;}
void WrathIOSTouchFrame(float *yaw,float *pitch,float *side,float *forward,unsigned *buttons){
 auto &s=S();std::scoped_lock lock(s.mutex);*yaw=s.game?s.lookX:0;*pitch=s.game?s.lookY:0;*side=s.game?s.moveX:0;*forward=s.game?s.moveY:0;*buttons=s.suspended?0:s.buttons;s.lookX=s.lookY=0;
}
