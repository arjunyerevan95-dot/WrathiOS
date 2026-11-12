#import "WrathSemanticMenuBridge.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <SDL.h>
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

@interface WrathSemanticTouchSurface : UIView {
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
 NSInteger _radialSelection; NSTimeInterval _artifactStart; BOOL _artifactHolding; int _radialHeld;
 CGFloat _controlScale,_opacity,_swipeGain,_gyroGain;
 UIView *_settingsPanel;
 NSMutableDictionary<NSNumber *,UIAccessibilityElement *> *_accessibleButtons;
 UIAccessibilityElement *_accessibleKeyboard;
}
- (void)refresh;
- (void)reset;
- (CGRect)buttonRect:(int)b;
- (void)requestKeyboard:(BOOL)show;
@end
@implementation WrathSemanticTouchSurface
- (instancetype)initWithFrame:(CGRect)frame {
 if(!(self=[super initWithFrame:frame]))return nil;
 NSLog(@"WRATHIOS_NATIVE_TOUCH_V15");
 [NSUserDefaults.standardUserDefaults registerDefaults:@{@"WrathTouchScale":@1,@"WrathTouchOpacity":@.5,@"WrathTouchSwipe":@.15,@"WrathTouchGyro":@1}];
 _controlScale=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchScale"];_opacity=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchOpacity"];
 _swipeGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchSwipe"];_gyroGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchGyro"];
 self.accessibilityIdentifier=@"WrathNativeControls";
 self.backgroundColor=UIColor.clearColor;self.multipleTouchEnabled=YES;
 self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 _accessibleButtons=[NSMutableDictionary new];
 _owners=[NSMutableDictionary new];_last=[NSMutableDictionary new];_motion=[CMMotionManager new];
 _motion.deviceMotionUpdateInterval=1.0/100;
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
 return self;
}
- (void)dealloc {[_motion stopDeviceMotionUpdates];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)reset {
 [_owners removeAllObjects];[_last removeAllObjects];_sampleTime=0;_tray=0;_artifactHolding=NO;_radialHeld=0;_settingsPanel.hidden=YES;
 [self requestKeyboard:NO];_textFocused=NO;
 auto &s=S();std::scoped_lock lock(s.mutex);ResetLocked(s);
}
- (void)inactive:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=true;}[_motion stopDeviceMotionUpdates];}
- (void)active:(NSNotification *)n {(void)n;[self reset];{auto &s=S();std::scoped_lock lock(s.mutex);s.suspended=false;}[self refresh];}
- (void)requestKeyboard:(BOOL)show {
 SDL_Window *window=SDL_GetKeyboardFocus();
 if(show){
  // SDL reports its requested flag, not actual first-responder visibility.
  SDL_StopTextInput();
  SDL_StartTextInput();
 }else SDL_StopTextInput();
 NSLog(@"WRATH_INPUT keyboard requested=%d active=%d shown=%d",show,SDL_IsTextInputActive(),window?SDL_IsScreenKeyboardShown(window):0);
}
- (void)refresh {
 bool game,enabled,captured;{auto &s=S();std::scoped_lock lock(s.mutex);game=s.game&&!s.suspended;captured=s.captured;enabled=(s.menu||s.game)&&!s.suspended;}
 UIInterfaceOrientation orientation=self.window.windowScene.interfaceOrientation;
 int mode=enabled?(game?2:1):0;
 if(_lastMode!=mode||(_orientation!=UIInterfaceOrientationUnknown&&orientation!=_orientation))[self reset];
 _lastMode=mode;_wasGame=game;_orientation=orientation;_captured=captured;
 self.hidden=!enabled;self.userInteractionEnabled=enabled;
 bool textWanted;{auto &s=S();std::scoped_lock lock(s.mutex);textWanted=s.menu&&s.textFocus&&!s.suspended&&(!_settingsPanel||_settingsPanel.hidden);}
 if(textWanted&&!_textFocused)[self requestKeyboard:YES];
 if(!textWanted&&_textFocused)[self requestKeyboard:NO];
 _textFocused=textWanted;
 self.accessibilityLabel=game?@"WRATH gameplay controls: fire alt jump crouch use weapons radial settings":@"WRATH menu controls: cursor accept back keyboard";
 static double lastDiagnostic=0;
 double now=CACurrentMediaTime();
 if(now-lastDiagnostic>1){
  lastDiagnostic=now;SDL_Window *w=SDL_GetKeyboardFocus();
  NSDictionary *status=@{@"version":NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]?:@"test",@"mode":game?@"gameplay":@"menu",@"keyboardRequested":@(textWanted),@"keyboardActive":@(SDL_IsTextInputActive()),@"keyboardShown":@(w?SDL_IsScreenKeyboardShown(w):0),@"captured":@(captured)};
  NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  [[NSJSONSerialization dataWithJSONObject:status options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"WrathInputDiagnostics.json"] atomically:YES];
 }
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
 NSMutableArray *elements=[NSMutableArray new];
 for(int i=0;i<wrathios::touch::ActionCount;i++){CGRect rect=[self buttonRect:i];if(CGRectIsNull(rect))continue;
  UIAccessibilityElement *e=_accessibleButtons[@(i)];if(!e){e=[[UIAccessibilityElement alloc]initWithAccessibilityContainer:self];_accessibleButtons[@(i)]=e;}e.accessibilityLabel=[NSString stringWithUTF8String:wrathios::touch::Actions[i].label];e.accessibilityIdentifier=[@"WrathAction_" stringByAppendingString:e.accessibilityLabel];e.accessibilityTraits=UIAccessibilityTraitButton;e.accessibilityFrameInContainerSpace=rect;[elements addObject:e];
 }
 if(!game){if(!_accessibleKeyboard)_accessibleKeyboard=[[UIAccessibilityElement alloc]initWithAccessibilityContainer:self];UIAccessibilityElement *e=_accessibleKeyboard;e.accessibilityLabel=@"Keyboard";e.accessibilityIdentifier=@"WrathKeyboardButton";e.accessibilityTraits=UIAccessibilityTraitButton;e.accessibilityFrameInContainerSpace=CGRectMake(self.bounds.size.width*.5-62,10,125,42);[elements addObject:e];}
 self.accessibilityElements=(_settingsPanel&&!_settingsPanel.hidden)?@[_settingsPanel]:elements;
 if([_owners.allValues containsObject:@201]&&!_artifactHolding&&NSProcessInfo.processInfo.systemUptime-_artifactStart>.3){_artifactHolding=YES;auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(12);}
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
 CGFloat left=MAX(16,self.safeAreaInsets.left),right=MAX(16,self.safeAreaInsets.right);
 CGFloat usable=w-left-right, scale=MIN(_controlScale,1.3);
 // Approved combat hierarchy. USE sits above FIRE with a clear gap.
 auto rect=[&](CGFloat x,CGFloat y,CGFloat diameter){CGFloat d=diameter*scale;return CGRectMake(left+x*usable-d/2,y*h-d/2,d,d);};
 if(b==0)return rect(.83,.49,70);
 if(b==5)return rect(.83,.25,44);
 if(b==2)return rect(.71,.34,50);
 if(b==1)return rect(.95,.28,46);
 if(b==4)return rect(.95,.52,46);
 if(b==26&&_tray!=3)return rect(.60,.24,42);
 if(b==3)return CGRectMake(left,12,62,34);
 if(b==21)return CGRectMake(w-right-192,12,92,34);
 if(b==6)return CGRectMake(w-right-94,12,92,34);
 if(b==31)return CGRectMake(left+72,12,42,34);
 if(!_tray)return CGRectNull;
 static const int weapons[]={12,13,14,15,16,17,18,19,20};
 static const int utilities[]={28,11,27,30,8,29,9,10};
 static const int artifacts[]={24,26,25};
 const int *items=_tray==1?utilities:_tray==2?weapons:artifacts;
 int count=_tray==1?8:_tray==2?9:3;
 for(int i=0;i<count;i++)if(b==items[i]){double a=-M_PI_2+i*2*M_PI/count;return CGRectMake(w*.48+cos(a)*MIN(140.,w*.22)-42,h*.52+sin(a)*MIN(100.,h*.28)-22,84,44);}
 return CGRectNull;
}
- (void)sendAction:(int)action {
 if(action<0||action>=wrathios::touch::ActionCount)return;
 auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(action+1);s.keys.push_back(-(action+1));
}
- (int)radialAt:(CGPoint)p {
 if(!_tray)return -1;
 static const int utilities[]={28,11,27,30,8,29,9,10};
 static const int weapons[]={12,13,14,15,16,17,18,19,20};
 static const int artifacts[]={24,26,25};
 const int *items=_tray==1?utilities:_tray==2?weapons:artifacts;
 int count=_tray==1?8:_tray==2?9:3;
 for(int i=0;i<count;i++)if(CGRectContainsPoint([self buttonRect:items[i]],p))return items[i];
 return -1;
}
- (void)drawRect:(CGRect)rect {
 (void)rect;
 if(!_wasGame){
  NSDictionary *a=@{NSFontAttributeName:[UIFont boldSystemFontOfSize:13],NSForegroundColorAttributeName:UIColor.whiteColor,NSBackgroundColorAttributeName:[UIColor colorWithWhite:0 alpha:.5]};
  [@" KEYBOARD " drawAtPoint:CGPointMake(self.bounds.size.width*.5-55,18) withAttributes:a];
  [@"MENU: FIRE / JUMP / USE = ACCEPT; ALT / CROUCH = BACK" drawAtPoint:CGPointMake(100,self.bounds.size.height-24) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:10],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }
 for(int i=0;i<wrathios::touch::ActionCount;i++){
  CGRect r=[self buttonRect:i];if(CGRectIsNull(r))continue;[(i==_radialSelection&&_tray?[UIColor colorWithRed:.8 green:.35 blue:0 alpha:.8]:[UIColor colorWithWhite:0 alpha:_opacity]) setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:16] fill];
  [[NSString stringWithUTF8String:((!_wasGame||_captured)&&i==0)?"ACCEPT":(!_wasGame&&i==2)?"BACK":(_tray==1&&i==12)?"MORE":(i==21?"WEAPONS":i==6?"UTILITIES":i==26?"ARTIFACT":i==31?"⚙":wrathios::touch::Actions[i].label)] drawInRect:CGRectInset(r,3,(r.size.height-15)/2) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:i>=7?10:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }
 CGPoint center=[_owners.allValues containsObject:@100]?_moveOrigin:CGPointMake(90,self.bounds.size.height-100);
 [[UIColor colorWithWhite:1 alpha:.3]setStroke];UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-54,center.y-54,108,108)];ring.lineWidth=2;[ring stroke];
 [(_wasGame?@"MOVE":@"CURSOR") drawAtPoint:CGPointMake(65,self.bounds.size.height-95) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12],NSForegroundColorAttributeName:UIColor.whiteColor}];
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
   CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
   if(CGRectContainsPoint(CGRectMake(w*.5-62,10,125,42),p)){SDL_Window *window=SDL_GetKeyboardFocus();[self requestKeyboard:!(window&&SDL_IsScreenKeyboardShown(window))];continue;}
   int button=-1;for(int b=wrathios::touch::ActionCount-1;b>=0;b--)if(CGRectContainsPoint([self buttonRect:b],p)){button=b;break;}
   if(button==31){[self showSettings];continue;}
   if(button==6){_tray=_tray?0:1;[self setNeedsDisplay];continue;}
   if(_tray==1&&button==12){_tray=2;[self setNeedsDisplay];continue;}
   if(button==0||button==1||button==5){
    if([_owners.allValues containsObject:@104])continue;owner=104;
    auto &s=S();std::scoped_lock lock(s.mutex);s.menuPad=true;s.pointer.reset();s.pad.input(0,0,1,CACurrentMediaTime());
   }else if(button==2||button==3||button==4){auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(4);s.keys.push_back(-4);continue;
   }else if(button>=0){continue;
   }else if(CGRectContainsPoint(CGRectMake(20,h-170,140,140),p)){
    if([_owners.allValues containsObject:@103])continue;owner=103;_navOrigin=p;
    auto &s=S();std::scoped_lock lock(s.mutex);s.menuPad=true;s.pointer.reset();
   }else{if([_owners.allValues containsObject:@102])continue;owner=102;[self menuPoint:p button:1];}
  }
  else {
   for(int b=wrathios::touch::ActionCount-1;b>=0;b--)if(CGRectContainsPoint([self buttonRect:b],p)){owner=b;break;}
   if((owner==6||owner==21)&&([_owners.allValues containsObject:@200]||[_owners.allValues containsObject:@202]))continue;
   if(owner==6||owner==21){_tray=owner==6?1:2;_radialSelection=-1;owner=200;}
   else if(owner==31){[self showSettings];continue;}
   else if(owner==26&&_tray!=3){_artifactStart=t.timestamp;_artifactHolding=NO;owner=201;}
   else if(_tray){int selected=[self radialAt:p];if(selected>=0){owner=202;_radialSelection=selected;}else{_tray=0;[self setNeedsDisplay];continue;}}
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
  if(owner==200||owner==202){
   _radialSelection=[self radialAt:p];
   int held=(_radialSelection>=0&&wrathios::touch::Actions[_radialSelection].down[0]=='+')?(int)_radialSelection+1:0;
   if(held!=_radialHeld){auto &s=S();std::scoped_lock lock(s.mutex);if(_radialHeld)s.keys.push_back(-_radialHeld);if(held)s.keys.push_back(held);_radialHeld=held;}
   [self setNeedsDisplay];continue;}
  if(owner==201)continue;
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
  if(owner==200||owner==202||owner==201){
   if(owner==201&&_artifactHolding){auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(-12);_artifactHolding=NO;}
   else if(!cancelled&&owner==201)[self sendAction:26];
   else if(!cancelled&&_radialSelection>=0&&!_radialHeld)[self sendAction:(int)_radialSelection];
   if(_radialHeld){auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(-_radialHeld);_radialHeld=0;}
   _tray=0;_radialSelection=-1;[_owners removeObjectForKey:key];[_last removeObjectForKey:key];[self setNeedsDisplay];continue;
  }
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
