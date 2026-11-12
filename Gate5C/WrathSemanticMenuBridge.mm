#import "WrathSemanticMenuBridge.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#include "WrathTouchMath.hpp"
#include "WrathTouchActions.hpp"
#include <deque>
#include <mutex>

namespace {
using wrathios::touch::PointerEvent;
struct State {
 std::mutex mutex;
 bool menu=false,game=false,suspended=false,textFocus=false,captured=false;
 std::deque<int> text;
 wrathios::touch::Pointer pointer,pad;
 bool menuPad=false;float navX=0,navY=0;
 float width=640,height=480,x=0,y=0,lookX=0,lookY=0,moveX=0,moveY=0;
 unsigned buttons=0;
 std::deque<int> keys;
};
State &S(){static State s;return s;}
void ResetLocked(State &s){s.pointer.reset();s.pad.reset();s.menuPad=false;s.navX=s.navY=0;s.text.clear();s.lookX=s.lookY=s.moveX=s.moveY=0;s.buttons=0;s.keys.clear();for(int i=1;i<=wrathios::touch::ActionCount;i++)s.keys.push_back(-i);}
constexpr NSInteger tag=0x57524335;
}

@interface WrathSemanticTouchSurface : UIView <UIKeyInput> {
 NSMutableDictionary<NSValue *,NSNumber *> *_owners;
 NSMutableDictionary<NSValue *,NSValue *> *_last;
 CGPoint _moveOrigin,_navOrigin;
 CMMotionManager *_motion;
 UIInterfaceOrientation _orientation;
 double _sampleTime;
 BOOL _wasGame;
 int _lastMode;
 BOOL _textFocused;
 int _tray; BOOL _captured;
 CGFloat _controlScale,_opacity,_swipeGain,_gyroGain;
 UIView *_settingsPanel;
}
- (void)refresh;
- (void)reset;
@end
@implementation WrathSemanticTouchSurface
- (instancetype)initWithFrame:(CGRect)frame {
 if(!(self=[super initWithFrame:frame]))return nil;
 NSLog(@"WRATHIOS_NATIVE_TOUCH_V13");
 [NSUserDefaults.standardUserDefaults registerDefaults:@{@"WrathTouchScale":@1,@"WrathTouchOpacity":@.5,@"WrathTouchSwipe":@.15,@"WrathTouchGyro":@1}];
 _controlScale=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchScale"];_opacity=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchOpacity"];
 _swipeGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchSwipe"];_gyroGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchGyro"];
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
 [_owners removeAllObjects];[_last removeAllObjects];_sampleTime=0;_tray=0;_settingsPanel.hidden=YES;
 [self resignFirstResponder];_textFocused=NO;
 auto &s=S();std::scoped_lock lock(s.mutex);ResetLocked(s);
}
- (void)inactive:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=true;}[_motion stopDeviceMotionUpdates];}
- (void)active:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=false;}[self refresh];}
- (BOOL)canBecomeFirstResponder {return YES;}
- (BOOL)hasText {return YES;}
- (UIKeyboardType)keyboardType {return UIKeyboardTypeASCIICapable;}
- (UITextAutocorrectionType)autocorrectionType {return UITextAutocorrectionTypeNo;}
- (UITextAutocapitalizationType)autocapitalizationType {return UITextAutocapitalizationTypeNone;}
- (UIReturnKeyType)returnKeyType {return UIReturnKeyDone;}
- (void)insertText:(NSString *)text {
 for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];
  if(c=='\n'||c=='\r'){[self resignFirstResponder];continue;}
  if(c>0&&c<128){auto &s=S();std::scoped_lock lock(s.mutex);s.text.push_back(c);}
 }
}
- (void)deleteBackward {auto &s=S();std::scoped_lock lock(s.mutex);s.text.push_back(8);}
- (void)refresh {
 bool game,enabled,captured;{auto &s=S();std::scoped_lock lock(s.mutex);game=s.game&&!s.suspended;captured=s.captured;enabled=(s.menu||s.game)&&!s.suspended;}
 UIInterfaceOrientation orientation=self.window.windowScene.interfaceOrientation;
 int mode=enabled?(game?2:1):0;
 if(_lastMode!=mode||(_orientation!=UIInterfaceOrientationUnknown&&orientation!=_orientation))[self reset];
 _lastMode=mode;_wasGame=game;_orientation=orientation;_captured=captured;
 self.hidden=!enabled;self.userInteractionEnabled=enabled;
 bool textWanted;{auto &s=S();std::scoped_lock lock(s.mutex);textWanted=s.menu&&s.textFocus&&!s.suspended;}
 if(textWanted&&!_textFocused)[self becomeFirstResponder];
 if(!textWanted&&_textFocused)[self resignFirstResponder];
 _textFocused=textWanted;
 if(!game||captured||_gyroGain<=0||(_settingsPanel&&!_settingsPanel.hidden)){[_motion stopDeviceMotionUpdates];_sampleTime=0;}
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
   if(s.game&&!s.suspended&&!s.captured){s.lookX+=rate.x*57.2957795*dt*v->_gyroGain;s.lookY+=rate.y*57.2957795*dt*v->_gyroGain;}
  }];
 }
 [self setNeedsDisplay];
}
- (void)settingChanged:(UISlider *)slider {
 NSArray *keys=@[@"WrathTouchSwipe",@"WrathTouchGyro",@"WrathTouchScale",@"WrathTouchOpacity"];
 CGFloat value=slider.value;[NSUserDefaults.standardUserDefaults setDouble:value forKey:keys[slider.tag]];
 if(slider.tag==0)_swipeGain=value;if(slider.tag==1)_gyroGain=value;if(slider.tag==2)_controlScale=value;if(slider.tag==3)_opacity=value;
 [self refresh];
}
- (void)closeSettings { _settingsPanel.hidden=YES;[self refresh]; }
- (void)showSettings {
 [self reset];
 if(!_settingsPanel){
  _settingsPanel=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,280)];_settingsPanel.backgroundColor=[UIColor colorWithWhite:.08 alpha:.96];_settingsPanel.layer.cornerRadius=16;
  NSArray *labels=@[@"Swipe sensitivity",@"Gyro strength (0 = off)",@"Button size",@"Button opacity"];
  float low[]={.04,0,.7,.15},high[]={.4,3,1.3,.9};
  float values[]={(float)_swipeGain,(float)_gyroGain,(float)_controlScale,(float)_opacity};
  for(int i=0;i<4;i++){
   UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(15,12+i*52,290,20)];label.text=labels[i];label.textColor=UIColor.whiteColor;label.font=[UIFont systemFontOfSize:13];[_settingsPanel addSubview:label];
   UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(15,31+i*52,290,25)];slider.minimumValue=low[i];slider.maximumValue=high[i];slider.value=values[i];slider.tag=i;[slider addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];[_settingsPanel addSubview:slider];
  }
  UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];done.frame=CGRectMake(110,230,100,40);[done setTitle:@"Done" forState:UIControlStateNormal];[done addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];[_settingsPanel addSubview:done];[self addSubview:_settingsPanel];
 }
 _settingsPanel.center=CGPointMake(self.bounds.size.width*.5,self.bounds.size.height*.5);_settingsPanel.hidden=NO;[self bringSubviewToFront:_settingsPanel];[self refresh];
}
- (CGRect)buttonRect:(int)b {
 CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
 CGFloat size=46*_controlScale,gap=6,step=size+gap,right=MAX(12,self.safeAreaInsets.right),top=MAX(10,self.safeAreaInsets.top);
 // Compact upper-right cluster; lower-right remains a true unoccupied look pad.
 const int cluster[]={2,0,1,5,4,21,6,22,31};
 for(int i=0;i<9;i++)if(b==cluster[i])return CGRectMake(w-right-3*step+(i%3)*step,top+(i/3)*step,size,size);
 if(b==3)return CGRectMake(MAX(16,self.safeAreaInsets.left),16,62,36);
 if(!_tray)return CGRectNull;
 if(_tray==1){
  const int radial[]={11,28,26,25,27,29,12,7};
  for(int i=0;i<8;i++)if(b==radial[i]){double a=-M_PI_2+i*M_PI/4;return CGRectMake(w*.53+cos(a)*115-43,h*.52+sin(a)*95-24,86,48);}
  return CGRectNull;
 }
 CGFloat cell=(w-300)/6;
 return b>=7?CGRectMake(112+((b-7)%6)*cell,64+((b-7)/6)*48,cell-5,43):CGRectNull;
}
- (void)drawRect:(CGRect)rect {
 (void)rect;
 if(!_wasGame){
  NSDictionary *a=@{NSFontAttributeName:[UIFont boldSystemFontOfSize:13],NSForegroundColorAttributeName:UIColor.whiteColor,NSBackgroundColorAttributeName:[UIColor colorWithWhite:0 alpha:.5]};
  [@" BACK " drawAtPoint:CGPointMake(16,16) withAttributes:a];
  [@" KEYBOARD " drawAtPoint:CGPointMake(self.bounds.size.width-115,16) withAttributes:a];
  CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
  [[UIColor colorWithWhite:0 alpha:.45]setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(30,h-160,120,120)]fill];
  [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(w-105,h-115,90,75) cornerRadius:20]fill];
  [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(w-200,h-110,80,65) cornerRadius:20]fill];
  [@"CURSOR" drawAtPoint:CGPointMake(60,h-110) withAttributes:a];
  [@"A ACCEPT" drawAtPoint:CGPointMake(w-100,h-85) withAttributes:a];
  [@"B BACK" drawAtPoint:CGPointMake(w-195,h-85) withAttributes:a];return;
 }
 for(int i=0;i<wrathios::touch::ActionCount;i++){
  CGRect r=[self buttonRect:i];if(CGRectIsNull(r))continue;[[UIColor colorWithWhite:0 alpha:_opacity] setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:16] fill];
  [[NSString stringWithUTF8String:(_captured&&i==0)?"ACCEPT":(_tray==1&&i==12)?"MORE":wrathios::touch::Actions[i].label] drawInRect:CGRectInset(r,5,(r.size.height-15)/2) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:i>=7?10:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }
 CGPoint center=[_owners.allValues containsObject:@100]?_moveOrigin:CGPointMake(90,self.bounds.size.height-100);
 [[UIColor colorWithWhite:1 alpha:.3]setStroke];UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-54,center.y-54,108,108)];ring.lineWidth=2;[ring stroke];
 [@"MOVE" drawAtPoint:CGPointMake(65,self.bounds.size.height-95) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
}
- (void)menuPoint:(CGPoint)p button:(int)button {
 auto &s=S();std::scoped_lock lock(s.mutex);
 s.x=std::clamp((float)(p.x/MAX(1,self.bounds.size.width)),0.f,1.f);
 s.y=std::clamp((float)(p.y/MAX(1,self.bounds.size.height)),0.f,1.f);s.menuPad=false;s.navX=s.navY=0;s.pointer.input(s.x,s.y,button,CACurrentMediaTime());

}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 (void)event;bool menu;{auto &s=S();std::scoped_lock lock(s.mutex);menu=s.menu;}
 for(UITouch *t in touches){
  NSValue *key=[NSValue valueWithNonretainedObject:t];CGPoint p=[t locationInView:self];
  int owner=-1;
  if(menu){
   if(p.y<54&&p.x>self.bounds.size.width-125){if(self.isFirstResponder)[self resignFirstResponder];else [self becomeFirstResponder];continue;}
   if(p.y<54&&p.x<85){auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(4);s.keys.push_back(-4);continue;}
   CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
   if(CGRectContainsPoint(CGRectMake(20,h-170,140,140),p)){
    if([_owners.allValues containsObject:@103])continue;owner=103;_navOrigin=p;
    auto &s=S();std::scoped_lock lock(s.mutex);s.menuPad=true;s.pointer.reset();
   }else if(CGRectContainsPoint(CGRectMake(w-110,h-120,100,85),p)){
    if([_owners.allValues containsObject:@104])continue;owner=104;
    auto &s=S();std::scoped_lock lock(s.mutex);s.menuPad=true;s.pointer.reset();s.pad.input(0,0,1,CACurrentMediaTime());
   }else if(CGRectContainsPoint(CGRectMake(w-205,h-115,90,75),p)){
    auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(4);s.keys.push_back(-4);continue;
   }else{
    if([_owners.allValues containsObject:@102])continue;owner=102;[self menuPoint:p button:1];
   }
  }
  else {
   for(int b=wrathios::touch::ActionCount-1;b>=0;b--)if(CGRectContainsPoint([self buttonRect:b],p)){owner=b;break;}
   if(owner==6){_tray=_tray?0:1;[self setNeedsDisplay];continue;}
   if(owner==31){[self showSettings];continue;}
   if(_tray==1&&owner==12){_tray=2;[self setNeedsDisplay];continue;}
   if(owner<0)owner=p.x<self.bounds.size.width*.42?100:101;
   if((owner==100||owner==101)&&[_owners.allValues containsObject:@(owner)])continue;
   if(owner==100)_moveOrigin=p;
   if(owner<wrathios::touch::ActionCount){auto &s=S();std::scoped_lock lock(s.mutex);if(!(s.buttons&(1u<<owner)))s.keys.push_back(owner+1);s.buttons|=1u<<owner;}
  }
  _owners[key]=@(owner);_last[key]=[NSValue valueWithCGPoint:p];
 }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 (void)event;
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;
  int owner=n.intValue;CGPoint p=[t locationInView:self],last=[_last[key] CGPointValue];
  if(owner==102)[self menuPoint:p button:0];
  else {auto &s=S();std::scoped_lock lock(s.mutex);
   if(owner==101){s.lookX+=(p.x-last.x)*_swipeGain;s.lookY+=(p.y-last.y)*_swipeGain;}
   if(owner==103){auto stick=wrathios::touch::Stick({p.x-_navOrigin.x,p.y-_navOrigin.y});s.navX=stick.x;s.navY=stick.y;}
   if(owner==100){auto stick=wrathios::touch::Stick({p.x-_moveOrigin.x,p.y-_moveOrigin.y});s.moveX=stick.x;s.moveY=stick.y;}
  }
  _last[key]=[NSValue valueWithCGPoint:p];
 }
}
- (void)finish:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;int owner=n.intValue;
  if(owner==102){if(cancelled){auto &s=S();std::scoped_lock lock(s.mutex);s.pointer.reset();}else [self menuPoint:[t locationInView:self] button:2];}
  [_owners removeObjectForKey:key];[_last removeObjectForKey:key];
  auto &s=S();std::scoped_lock lock(s.mutex);
  if(owner==100)s.moveX=s.moveY=0;
  if(owner==103)s.navX=s.navY=0;
  if(owner==104){if(cancelled)s.pad.reset();else s.pad.input(0,0,2,CACurrentMediaTime());}
  if(owner<wrathios::touch::ActionCount&&![_owners.allValues containsObject:@(owner)]){s.buttons&=~(1u<<owner);s.keys.push_back(-(owner+1));}
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
   if(w.hidden||w.windowLevel!=UIWindowLevelNormal||!w.isKeyWindow)continue;
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
int WrathIOSTouchTakeMenuRelease(void){auto &s=S();std::scoped_lock lock(s.mutex);bool a=s.pointer.takeRelease(),b=s.pad.takeRelease();return a||b;}
void WrathIOSGate5CSetMenuActive(int active){auto &s=S();{std::scoped_lock lock(s.mutex);if(s.menu!=(active!=0)){ResetLocked(s);s.menu=active!=0;if(active)s.game=false;}}Refresh();}
void WrathIOSTouchSetMode(int menu,int game){auto &s=S();{std::scoped_lock lock(s.mutex);if(s.menu!=(menu!=0)||s.game!=(game!=0)){ResetLocked(s);s.menu=menu!=0;s.game=game!=0;}}Refresh();}
int WrathIOSTouchNextKey(void){auto &s=S();std::scoped_lock lock(s.mutex);if(s.keys.empty())return 0;int key=s.keys.front();s.keys.pop_front();return key;}
void WrathIOSTouchFrame(float *yaw,float *pitch,float *side,float *forward,unsigned *buttons){
 auto &s=S();std::scoped_lock lock(s.mutex);*yaw=s.game?s.lookX:0;*pitch=s.game?s.lookY:0;*side=s.game?s.moveX:0;*forward=s.game?s.moveY:0;*buttons=s.suspended?0:s.buttons;s.lookX=s.lookY=0;
}

void WrathIOSTouchTextFocus(int active){auto &s=S();{std::scoped_lock lock(s.mutex);s.textFocus=active!=0;}Refresh();}
int WrathIOSTouchNextText(void){auto &s=S();std::scoped_lock lock(s.mutex);if(s.text.empty())return 0;int c=s.text.front();s.text.pop_front();return c;}

const char *WrathIOSTouchActionCommand(int action,int down){if(action<0||action>=wrathios::touch::ActionCount)return "";return down?wrathios::touch::Actions[action].down:wrathios::touch::Actions[action].up;}

int WrathIOSTouchMenuPad(float *x,float *y){auto &s=S();std::scoped_lock lock(s.mutex);*x=s.navX;*y=s.navY;return s.menu&&s.menuPad;}
int WrathIOSTouchNextPadButton(void){auto &s=S();std::scoped_lock lock(s.mutex);return s.pad.next();}

void WrathIOSTouchSetCapture(int captured){auto &s=S();std::scoped_lock lock(s.mutex);s.captured=captured!=0;}
