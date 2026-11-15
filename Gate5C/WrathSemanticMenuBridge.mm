#import "WrathSemanticMenuBridge.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <SDL.h>
#include "WrathTouchMath.hpp"
#include "WrathTouchActions.hpp"
#include "WrathMobileGraphics.h"
#include <deque>
#include <mutex>

namespace {
using wrathios::touch::PointerEvent;
struct State {
 std::mutex mutex;
 bool menu=false,game=false,suspended=false,textFocus=false,captured=false;
 bool artifactHeld=false,artifactPad=false;float artifactX=0,artifactY=0;
 std::deque<int> text;
 wrathios::touch::Pointer pointer,pad;
 bool menuPad=false;float navX=0,navY=0;
 float width=640,height=480,x=0,y=0,lookX=0,lookY=0,moveX=0,moveY=0;
 unsigned buttons=0; unsigned long long consumed=0;
 std::deque<int> keys;
};
State &S(){static State s;return s;}
void ResetLocked(State &s){s.artifactHeld=false;s.artifactX=s.artifactY=0;s.pointer.reset();s.pad.reset();s.menuPad=false;s.navX=s.navY=0;s.text.clear();s.lookX=s.lookY=s.moveX=s.moveY=0;s.buttons=0;s.keys.clear();for(int i=1;i<=wrathios::touch::ActionCount+2;i++)s.keys.push_back(-i);}
constexpr NSInteger tag=0x57524335;
}

@interface WrathSemanticTouchSurface : UIView <UIGestureRecognizerDelegate> {
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
 UIView *_layoutToolbar; BOOL _editingLayout; UISlider *_buttonSize; int _layoutSelection;
 NSMutableDictionary *_layoutPositions;
 UIPinchGestureRecognizer *_layoutPinch; NSArray *_pinchOriginal; int _pinchButton; CGFloat _pinchStartSize; CGPoint _pinchCenter;
 NSMutableDictionary<NSNumber *,UIAccessibilityElement *> *_accessibleButtons;
 UIAccessibilityElement *_accessibleKeyboard,*_accessibleArtifactStick;
 CGPoint _artifactOrigin;
}
- (void)refresh;
- (void)reset;
- (CGRect)buttonRect:(int)b;
- (CGPoint)artifactStickCenter;
- (void)artifactPoint:(CGPoint)p relativeTo:(CGPoint)origin;
- (CGRect)defaultButtonRect:(int)b;
- (void)requestKeyboard:(BOOL)show;
@end
@implementation WrathSemanticTouchSurface
- (instancetype)initWithFrame:(CGRect)frame {
 if(!(self=[super initWithFrame:frame]))return nil;
 NSLog(@"WRATHIOS_NATIVE_TOUCH_V18_ARTIFACT_GLYPH_CONTROLLER");
 [NSUserDefaults.standardUserDefaults registerDefaults:@{@"WrathTouchScale":@1,@"WrathTouchOpacity":@.5,@"WrathTouchSwipe":@.15,@"WrathTouchGyro":@1}];
 _controlScale=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchScale"];_opacity=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchOpacity"];
 _swipeGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchSwipe"];_gyroGain=[NSUserDefaults.standardUserDefaults doubleForKey:@"WrathTouchGyro"];
 self.accessibilityIdentifier=@"WrathNativeControls";
 self.backgroundColor=UIColor.clearColor;self.multipleTouchEnabled=YES;
 self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 _layoutPositions=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"WrathTouchLayoutV1"] mutableCopy]?:[NSMutableDictionary new];
 _layoutPinch=[[UIPinchGestureRecognizer alloc]initWithTarget:self action:@selector(pinchLayout:)];
 _layoutPinch.delegate=self;_layoutPinch.enabled=NO;_layoutPinch.cancelsTouchesInView=YES;[self addGestureRecognizer:_layoutPinch];_pinchButton=-1;
 _accessibleButtons=[NSMutableDictionary new];
 _owners=[NSMutableDictionary new];_last=[NSMutableDictionary new];_motion=[CMMotionManager new];
 _motion.deviceMotionUpdateInterval=1.0/100;
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
 return self;
}
- (void)dealloc {[_motion stopDeviceMotionUpdates];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)reset {
 _layoutPinch.enabled=NO;_editingLayout=NO;_layoutToolbar.hidden=YES;
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
 if(!game||_editingLayout||_gyroGain<=0||(_settingsPanel&&!_settingsPanel.hidden)){[_motion stopDeviceMotionUpdates];_sampleTime=0;}
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
   if(s.game&&!s.suspended&&!s.artifactHeld){s.lookX+=rate.x*57.2957795*dt*v->_gyroGain;s.lookY+=rate.y*57.2957795*dt*v->_gyroGain;}
  }];
 }
 NSMutableArray *elements=[NSMutableArray new];
 for(int i=0;i<wrathios::touch::ActionCount;i++){CGRect rect=[self buttonRect:i];if(CGRectIsNull(rect))continue;
  UIAccessibilityElement *e=_accessibleButtons[@(i)];if(!e){e=[[UIAccessibilityElement alloc]initWithAccessibilityContainer:self];_accessibleButtons[@(i)]=e;}e.accessibilityLabel=[NSString stringWithUTF8String:wrathios::touch::Actions[i].label];e.accessibilityIdentifier=[@"WrathAction_" stringByAppendingString:e.accessibilityLabel];e.accessibilityTraits=UIAccessibilityTraitButton;e.accessibilityFrameInContainerSpace=rect;[elements addObject:e];
 }
 if(!game){if(!_accessibleKeyboard)_accessibleKeyboard=[[UIAccessibilityElement alloc]initWithAccessibilityContainer:self];UIAccessibilityElement *e=_accessibleKeyboard;e.accessibilityLabel=@"Keyboard";e.accessibilityIdentifier=@"WrathKeyboardButton";e.accessibilityTraits=UIAccessibilityTraitButton;e.accessibilityFrameInContainerSpace=CGRectMake(self.bounds.size.width*.5-62,10,125,42);[elements addObject:e];}
  if(_artifactHolding){
   if(!_accessibleArtifactStick)_accessibleArtifactStick=[[UIAccessibilityElement alloc]initWithAccessibilityContainer:self];
   CGPoint center=[self artifactStickCenter];auto &s=S();std::scoped_lock lock(s.mutex);
   _accessibleArtifactStick.accessibilityLabel=@"Artifact selection stick";_accessibleArtifactStick.accessibilityIdentifier=@"WrathArtifactRightStick";
   _accessibleArtifactStick.accessibilityTraits=UIAccessibilityTraitAdjustable;_accessibleArtifactStick.accessibilityFrameInContainerSpace=CGRectMake(center.x-62,center.y-62,124,124);
   _accessibleArtifactStick.accessibilityValue=[NSString stringWithFormat:@"%.2f,%.2f",s.artifactX,s.artifactY];[elements addObject:_accessibleArtifactStick];
  }
  if(_editingLayout&&_layoutToolbar)[elements addObject:_layoutToolbar];
 self.accessibilityElements=(_settingsPanel&&!_settingsPanel.hidden)?@[_settingsPanel]:elements;
  if([_owners.allValues containsObject:@201]&&!_artifactHolding&&NSProcessInfo.processInfo.systemUptime-_artifactStart>.3){
   _artifactHolding=YES;{auto &s=S();std::scoped_lock lock(s.mutex);s.artifactHeld=s.artifactPad=true;s.artifactX=s.artifactY=s.lookX=s.lookY=0;s.keys.push_back(12);}
   // A right-look finger already held when Artifact opens becomes the selector.
   for(NSValue *key in _owners.allKeys)if(_owners[key].intValue==101){_owners[key]=@106;[self artifactPoint:[_last[key] CGPointValue] relativeTo:[self artifactStickCenter]];break;}
  }
 [self setNeedsDisplay];
}
- (void)settingChanged:(UISlider *)slider {
 NSArray *keys=@[@"WrathTouchSwipe",@"WrathTouchGyro",@"WrathTouchScale",@"WrathTouchOpacity"];
 CGFloat value=slider.value;[NSUserDefaults.standardUserDefaults setDouble:value forKey:keys[slider.tag]];
 if(slider.tag==0)_swipeGain=value;if(slider.tag==1)_gyroGain=value;if(slider.tag==2)_controlScale=value;if(slider.tag==3)_opacity=value;
 [self refresh];
}
- (void)resolutionChanged:(UISegmentedControl *)sender {
 const double scales[]={1.0,.67,.5,.33};NSInteger i=sender.selectedSegmentIndex;
 if(i>=0&&i<4)[NSUserDefaults.standardUserDefaults setDouble:scales[i] forKey:@"WrathRenderScaleV1"];
}
- (void)closeSettings { _settingsPanel.hidden=YES;[self refresh]; }
#ifdef WRATH_IOS_GLES3
- (void)msaaChanged:(UISegmentedControl *)sender {
 const int samples[]={1,2,4};NSInteger i=sender.selectedSegmentIndex;
 if(i>=0&&i<3){[NSUserDefaults.standardUserDefaults setInteger:samples[i] forKey:@"WrathMSAASamplesV1"];WrathIOSGraphicsSetSamples(samples[i]);}
}
- (void)fxaaChanged:(UISwitch *)sender {
 [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"WrathFXAAV1"];WrathIOSGraphicsSetFXAA(sender.on);
}
#endif
- (void)showSettings {
 [self reset];
 // Rebuild from current preferences/cvars; opening Settings never writes them.
 [_settingsPanel removeFromSuperview];
 CGFloat panelHeight=MIN(350.,self.bounds.size.height-24.);
 _settingsPanel=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,panelHeight)];_settingsPanel.backgroundColor=[UIColor colorWithWhite:.08 alpha:.96];_settingsPanel.layer.cornerRadius=16;
 UIScrollView *scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(0,0,320,panelHeight-54)];scroll.accessibilityIdentifier=@"WrathSettingsScroll";[_settingsPanel addSubview:scroll];
 UIView *body=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,430)];[scroll addSubview:body];scroll.contentSize=body.bounds.size;
 NSArray *labels=@[@"Swipe sensitivity",@"Gyro strength (0 = off)",@"Button size",@"Button opacity"];
 float low[]={.04,0,.7,.15},high[]={(float)wrathios::touch::SwipeMaximum,(float)wrathios::touch::GyroMaximum,1.3,.9};
 float values[]={(float)_swipeGain,(float)_gyroGain,(float)_controlScale,(float)_opacity};
 for(int i=0;i<4;i++){
  UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(15,12+i*52,290,20)];label.text=labels[i];label.textColor=UIColor.whiteColor;label.font=[UIFont systemFontOfSize:13];[body addSubview:label];
  UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(15,31+i*52,290,25)];slider.minimumValue=low[i];slider.maximumValue=high[i];slider.value=values[i];slider.tag=i;[slider addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];[body addSubview:slider];
 }
#ifdef WRATH_IOS_GLES3
 UILabel *resolutionLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,220,290,20)];resolutionLabel.text=@"Resolution (restart to apply)";resolutionLabel.textColor=UIColor.whiteColor;resolutionLabel.font=[UIFont systemFontOfSize:13];[body addSubview:resolutionLabel];
 UISegmentedControl *resolution=[[UISegmentedControl alloc]initWithItems:@[@"1x",@"0.67x",@"0.5x",@"0.33x"]];resolution.frame=CGRectMake(15,244,290,32);resolution.accessibilityIdentifier=@"WrathRenderResolution";
 NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"WrathRenderScaleV1"];double value=WrathMobileRenderScale(saved!=nil,saved.doubleValue);
 resolution.selectedSegmentIndex=WrathMobileRenderScaleIndex(value);[resolution addTarget:self action:@selector(resolutionChanged:) forControlEvents:UIControlEventValueChanged];[body addSubview:resolution];
 UILabel *msaaLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,284,290,20)];msaaLabel.text=@"MSAA (restart to apply)";msaaLabel.textColor=UIColor.whiteColor;msaaLabel.font=[UIFont systemFontOfSize:13];[body addSubview:msaaLabel];
 UISegmentedControl *msaa=[[UISegmentedControl alloc]initWithItems:@[@"Off",@"2x",@"4x"]];msaa.frame=CGRectMake(15,308,290,32);msaa.accessibilityIdentifier=@"WrathMSAA";
 int requested=WrathIOSPreferredMSAASamples(WrathIOSGraphicsRequestedSamples());if(requested>1&&requested!=2&&requested!=4){[msaa insertSegmentWithTitle:[NSString stringWithFormat:@"%dx",requested] atIndex:3 animated:NO];msaa.selectedSegmentIndex=3;}else msaa.selectedSegmentIndex=requested==2?1:requested==4?2:0;[msaa addTarget:self action:@selector(msaaChanged:) forControlEvents:UIControlEventValueChanged];[body addSubview:msaa];
 UILabel *active=[[UILabel alloc]initWithFrame:CGRectMake(15,344,290,18)];int actual=WrathIOSGraphicsActiveSamples();active.text=actual>1?[NSString stringWithFormat:@"Active MSAA: %dx",actual]:@"Active MSAA: Off";active.accessibilityIdentifier=@"WrathMSAAActive";active.textColor=UIColor.lightGrayColor;active.font=[UIFont systemFontOfSize:12];[body addSubview:active];
 UILabel *fxaaLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,377,220,24)];fxaaLabel.text=@"FXAA";fxaaLabel.textColor=UIColor.whiteColor;[body addSubview:fxaaLabel];
 UISwitch *fxaa=[[UISwitch alloc]initWithFrame:CGRectMake(250,374,55,32)];fxaa.accessibilityIdentifier=@"WrathFXAA";fxaa.on=WrathIOSGraphicsFXAA()!=0;[fxaa addTarget:self action:@selector(fxaaChanged:) forControlEvents:UIControlEventValueChanged];[body addSubview:fxaa];
#else
 scroll.contentSize=CGSizeMake(320,215);
#endif
 UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];done.frame=CGRectMake(210,panelHeight-47,100,40);[done setTitle:@"Done" forState:UIControlStateNormal];[done addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];[_settingsPanel addSubview:done];
 UIButton *edit=[UIButton buttonWithType:UIButtonTypeSystem];edit.frame=CGRectMake(15,panelHeight-47,180,40);[edit setTitle:@"Edit button positions" forState:UIControlStateNormal];[edit addTarget:self action:@selector(editLayout) forControlEvents:UIControlEventTouchUpInside];[_settingsPanel addSubview:edit];
 [self addSubview:_settingsPanel];_settingsPanel.center=CGPointMake(self.bounds.size.width*.5,self.bounds.size.height*.5);[self bringSubviewToFront:_settingsPanel];[self refresh];
}
- (void)editLayout {
 [self reset];_editingLayout=YES;_layoutPinch.enabled=YES;_layoutSelection=-1;
 if(!_layoutToolbar){
  _layoutToolbar=[[UIView alloc]initWithFrame:CGRectMake(0,0,450,44)];_layoutToolbar.backgroundColor=[UIColor colorWithWhite:.08 alpha:.95];_layoutToolbar.layer.cornerRadius=10;
  NSArray *titles=@[@"Drag icons",@"Reset",@"Done"];SEL actions[]={NULL,@selector(resetLayout),@selector(finishLayout)};
  for(int i=0;i<3;i++){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(i*80,0,80,44);[b setTitle:titles[i] forState:UIControlStateNormal];if(actions[i])[b addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];else b.enabled=NO;[_layoutToolbar addSubview:b];}
  _buttonSize=[[UISlider alloc]initWithFrame:CGRectMake(245,0,195,44)];_buttonSize.minimumValue=.65;_buttonSize.maximumValue=1.8;_buttonSize.accessibilityIdentifier=@"WrathSelectedButtonSize";_buttonSize.accessibilityLabel=@"Selected button size";[_buttonSize addTarget:self action:@selector(resizeSelectedButton:) forControlEvents:UIControlEventValueChanged];[_layoutToolbar addSubview:_buttonSize];
  [self addSubview:_layoutToolbar];
 }
 _buttonSize.enabled=NO;_buttonSize.value=1;
 _layoutToolbar.center=CGPointMake(self.bounds.size.width*.5,38);_layoutToolbar.hidden=NO;[self bringSubviewToFront:_layoutToolbar];[self refresh];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
 if(gesture!=_layoutPinch)return YES;
 return _editingLayout&&![touch.view isDescendantOfView:_layoutToolbar]&&![touch.view isDescendantOfView:_settingsPanel];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
 if(gesture!=_layoutPinch)return YES;
 if(!_editingLayout||gesture.numberOfTouches!=2)return NO;
 // A pinch must start on a control, not an arbitrary gameplay/look area.
 for(NSUInteger i=0;i<2;i++)for(int b=0;b<wrathios::touch::ActionCount;b++)
  if(CGRectContainsPoint([self buttonRect:b],[gesture locationOfTouch:i inView:self]))return YES;
 return NO;
}
- (void)pinchLayout:(UIPinchGestureRecognizer *)gesture {
 if(gesture.state==UIGestureRecognizerStateBegan){
  _pinchButton=-1;
  for(NSUInteger i=0;i<gesture.numberOfTouches&&_pinchButton<0;i++)for(int b=0;b<wrathios::touch::ActionCount;b++)
   if(CGRectContainsPoint([self buttonRect:b],[gesture locationOfTouch:i inView:self])){_pinchButton=b;break;}
  if(!_editingLayout||_pinchButton<0)return;
  _layoutSelection=_pinchButton;_pinchOriginal=[_layoutPositions[[@(_pinchButton) stringValue]] copy];
  _pinchStartSize=_pinchOriginal.count==3?[_pinchOriginal[2] doubleValue]:1;
  CGRect rect=[self buttonRect:_pinchButton];_pinchCenter=CGPointMake(CGRectGetMidX(rect),CGRectGetMidY(rect));
  [_owners removeAllObjects];[_last removeAllObjects];_buttonSize.enabled=YES;
 }
 if(_pinchButton<0)return;
 if(gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){
  NSString *key=[@(_pinchButton) stringValue];
  if(_pinchOriginal)_layoutPositions[key]=_pinchOriginal;else [_layoutPositions removeObjectForKey:key];
  _buttonSize.value=_pinchStartSize;
 }else if(_editingLayout&&(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged||gesture.state==UIGestureRecognizerStateEnded)){
  _buttonSize.value=wrathios::touch::PinchSize(_pinchStartSize,gesture.scale);
  [self resizeSelectedButton:_buttonSize];
 }
 if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){
  [NSUserDefaults.standardUserDefaults setObject:_layoutPositions forKey:@"WrathTouchLayoutV1"];
  _pinchOriginal=nil;_pinchButton=-1;[_owners removeAllObjects];[_last removeAllObjects];
 }
 [self refresh];
}
- (void)resizeSelectedButton:(UISlider *)sender {
 if(_layoutSelection<0)return;
 int b=_layoutSelection;CGRect rect=[self buttonRect:b];
 CGPoint center=_pinchButton==b?_pinchCenter:CGPointMake(CGRectGetMidX(rect),CGRectGetMidY(rect));
 CGFloat x=center.x/self.bounds.size.width,y=center.y/self.bounds.size.height;
 _layoutPositions[[@(b) stringValue]]=@[@(x),@(y),@(sender.value)];
 [NSUserDefaults.standardUserDefaults setObject:_layoutPositions forKey:@"WrathTouchLayoutV1"];
 [self refresh];
}
- (void)resetLayout {_layoutPinch.enabled=NO;_layoutPinch.enabled=_editingLayout;[_layoutPositions removeAllObjects];_layoutSelection=-1;_buttonSize.enabled=NO;[NSUserDefaults.standardUserDefaults removeObjectForKey:@"WrathTouchLayoutV1"];[self setNeedsDisplay];}
- (void)finishLayout { [NSUserDefaults.standardUserDefaults setObject:_layoutPositions forKey:@"WrathTouchLayoutV1"];_layoutPinch.enabled=NO;_editingLayout=NO;_layoutToolbar.hidden=YES;[_owners removeAllObjects];[_last removeAllObjects];[self refresh]; }
- (void)editTouches:(NSSet<UITouch *> *)touches phase:(int)phase {
 // A pinch moves its fingers before UIKit recognizes it. Those early moves
 // must not pass through the one-finger drag path while the state is Possible.
 if(_layoutPinch.numberOfTouches>1||_layoutPinch.state==UIGestureRecognizerStateBegan||_layoutPinch.state==UIGestureRecognizerStateChanged){
  [_owners removeAllObjects];[_last removeAllObjects];return;
 }
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];CGPoint p=[t locationInView:self];
  if(phase==0){for(int b=0;b<wrathios::touch::ActionCount;b++)if(CGRectContainsPoint([self buttonRect:b],p)){if(![_owners.allValues containsObject:@(b)]){_owners[key]=@(b);_last[key]=[NSValue valueWithCGPoint:p];_layoutSelection=b;NSArray *saved=_layoutPositions[[@(b) stringValue]];_buttonSize.value=saved.count==3?[saved[2] floatValue]:1;_buttonSize.enabled=YES;}break;}}
  else if(phase==1&&_owners[key]){int b=_owners[key].intValue;CGRect r=[self buttonRect:b];CGPoint last=[_last[key] CGPointValue];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
   CGFloat x=std::clamp(CGRectGetMidX(r)+p.x-last.x,self.safeAreaInsets.left+r.size.width/2,w-self.safeAreaInsets.right-r.size.width/2);
   CGFloat y=std::clamp(CGRectGetMidY(r)+p.y-last.y,self.safeAreaInsets.top+r.size.height/2,h-self.safeAreaInsets.bottom-r.size.height/2);
   NSArray *saved=_layoutPositions[[@(b) stringValue]];NSNumber *size=saved.count==3?saved[2]:@1;_layoutPositions[[@(b) stringValue]]=@[@(x/w),@(y/h),size];_last[key]=[NSValue valueWithCGPoint:p];
  }else if(phase==2){[_owners removeObjectForKey:key];[_last removeObjectForKey:key];[NSUserDefaults.standardUserDefaults setObject:_layoutPositions forKey:@"WrathTouchLayoutV1"];}
 }[self setNeedsDisplay];
}
- (CGRect)buttonRect:(int)b {
 if(_captured&&!_editingLayout&&b!=26&&b!=3&&b!=31)return CGRectNull;
 CGRect r=[self defaultButtonRect:b];if(CGRectIsNull(r))return r;
 NSArray *position=_layoutPositions[[@(b) stringValue]];
 if([position isKindOfClass:NSArray.class]&&(position.count==2||position.count==3)&&[position[0] isKindOfClass:NSNumber.class]&&[position[1] isKindOfClass:NSNumber.class]){
  CGFloat factor=position.count==3&&[position[2] isKindOfClass:NSNumber.class]?[position[2] doubleValue]:1;
  if(!isfinite(factor))factor=1;factor=std::clamp(factor,(CGFloat).65,(CGFloat)1.8);
  CGFloat maxW=MAX(1,self.bounds.size.width-self.safeAreaInsets.left-self.safeAreaInsets.right);
  CGFloat maxH=MAX(1,self.bounds.size.height-self.safeAreaInsets.top-self.safeAreaInsets.bottom);
  r.size.width=MIN(r.size.width*factor,maxW);r.size.height=MIN(r.size.height*factor,maxH);
  CGFloat x=[position[0] doubleValue],y=[position[1] doubleValue];if(isfinite(x)&&isfinite(y)){
   r.origin.x=std::clamp(x*self.bounds.size.width-r.size.width/2,self.safeAreaInsets.left,self.bounds.size.width-self.safeAreaInsets.right-r.size.width);
   r.origin.y=std::clamp(y*self.bounds.size.height-r.size.height/2,self.safeAreaInsets.top,self.bounds.size.height-self.safeAreaInsets.bottom-r.size.height);
  }
 }return r;
}
- (CGRect)defaultButtonRect:(int)b {

 CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
 CGFloat left=MAX(16,self.safeAreaInsets.left),right=MAX(16,self.safeAreaInsets.right);
 CGFloat usable=w-left-right, scale=MIN(_controlScale,1.3);
 // Approved combat hierarchy. USE sits above FIRE with a clear gap.
 auto rect=[&](CGFloat x,CGFloat y,CGFloat diameter){CGFloat d=diameter*scale;return CGRectMake(left+x*usable-d/2,y*h-d/2,d,d);};
 if(b==0)return rect(.70,.64,64);
 if(b==5)return rect(.84,.38,48);
 if(b==2)return rect(.80,.57,48);
 if(b==1)return rect(.94,.49,50);
 if(b==4)return rect(.94,.69,48);
 if(b==26&&_tray!=3)return rect(.84,.78,48);
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
- (CGPoint)artifactStickCenter {return CGPointMake(MIN(self.bounds.size.width-self.safeAreaInsets.right-68,MAX(self.safeAreaInsets.left+68,self.bounds.size.width*.73)),self.bounds.size.height*.52);}
- (void)artifactPoint:(CGPoint)p relativeTo:(CGPoint)origin {
 auto stick=wrathios::touch::Stick({p.x-origin.x,p.y-origin.y});
 auto &s=S();std::scoped_lock lock(s.mutex);s.artifactX=stick.x;s.artifactY=stick.y;
 [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
 (void)rect;
 if(!_wasGame){
  NSDictionary *a=@{NSFontAttributeName:[UIFont boldSystemFontOfSize:13],NSForegroundColorAttributeName:UIColor.whiteColor,NSBackgroundColorAttributeName:[UIColor colorWithWhite:0 alpha:.5]};
  [@" KEYBOARD " drawAtPoint:CGPointMake(self.bounds.size.width*.5-55,18) withAttributes:a];
  [@"MENU: FIRE / JUMP / USE = ACCEPT; ALT / CROUCH = BACK" drawAtPoint:CGPointMake(100,self.bounds.size.height-24) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:10],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }
 NSDictionary *symbols=@{@0:@"scope",@1:@"arrow.up",@2:@"burst",@3:@"pause.fill",@4:@"arrow.down",@5:@"hand.raised",@6:@"square.grid.2x2",@21:@"square.stack.3d.up",@26:@"diamond",@31:@"gearshape"};
 for(int i=0;i<wrathios::touch::ActionCount;i++){
  CGRect r=[self buttonRect:i];if(CGRectIsNull(r))continue;
  BOOL pressed=[_owners.allValues containsObject:@(i)]||(i==26&&_artifactHolding)||(i==_radialSelection&&_tray);
  UIBezierPath *plate=[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(14,r.size.height*.28)];
  [(pressed?[UIColor colorWithRed:.9 green:.42 blue:.12 alpha:.65]:[UIColor colorWithWhite:.04 alpha:_opacity*.6]) setFill];[plate fill];
  [[UIColor colorWithWhite:1 alpha:_editingLayout?.8:(pressed?.85:.25)]setStroke];plate.lineWidth=1;[plate stroke];
  NSString *name=symbols[@(i)];if((!_wasGame||_captured)&&i==0)name=@"checkmark";if(!_wasGame&&i==2)name=@"arrow.uturn.backward";
  UIImage *icon=name?[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium]]:nil;
  if(icon){CGFloat d=MIN(28,MIN(r.size.width,r.size.height)*.52);CGFloat ratio=icon.size.width/MAX(1,icon.size.height);CGSize size=ratio>1?CGSizeMake(d,d/ratio):CGSizeMake(d*ratio,d);[[icon imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:CGRectMake(CGRectGetMidX(r)-size.width/2,CGRectGetMidY(r)-size.height/2,size.width,size.height)];}
  else {NSString *label=[NSString stringWithUTF8String:wrathios::touch::Actions[i].label];NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=NSTextAlignmentCenter;CGFloat fontSize=11;while(fontSize>7&&[label sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:fontSize]}].width>r.size.width-6)fontSize-=.5;
   [label drawInRect:CGRectInset(r,3,(r.size.height-fontSize-3)/2) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:style}];}
 }
  if(_artifactHolding){
   CGPoint center=[self artifactStickCenter];float x,y;{auto &s=S();std::scoped_lock lock(s.mutex);x=s.artifactX;y=s.artifactY;}
   [[UIColor colorWithWhite:0 alpha:.5]setFill];UIBezierPath *pad=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-58,center.y-58,116,116)];[pad fill];
   [[UIColor colorWithWhite:1 alpha:.85]setStroke];pad.lineWidth=2;[pad stroke];
   [[UIColor colorWithRed:1 green:.55 blue:.2 alpha:.95]setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x+x*40-13,center.y-y*40-13,26,26)]fill];
   [@"ARTIFACT" drawAtPoint:CGPointMake(center.x-30,center.y+64) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:11],NSForegroundColorAttributeName:UIColor.whiteColor}];
  }
  // Movement is floating: show its origin only while touched, never a fixed MOVE target.
 if([_owners.allValues containsObject:@100]){
  CGPoint center=_moveOrigin;[[UIColor colorWithWhite:1 alpha:.3]setStroke];UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-44,center.y-44,88,88)];ring.lineWidth=1.5;[ring stroke];
  [[UIColor colorWithWhite:1 alpha:.45]setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-8,center.y-8,16,16)]fill];
 }

}
- (void)menuPoint:(CGPoint)p button:(int)button {
 auto &s=S();std::scoped_lock lock(s.mutex);
 s.x=std::clamp((float)(p.x/MAX(1,self.bounds.size.width)),0.f,1.f);
 s.y=std::clamp((float)(p.y/MAX(1,self.bounds.size.height)),0.f,1.f);s.menuPad=false;s.navX=s.navY=0;s.pointer.input(s.x,s.y,button,CACurrentMediaTime());

}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 if(_editingLayout){[self editTouches:touches phase:0];return;}
 (void)event;bool menu;{auto &s=S();std::scoped_lock lock(s.mutex);menu=s.menu;}
 for(UITouch *t in touches){
  NSValue *key=[NSValue valueWithNonretainedObject:t];CGPoint p=[t locationInView:self];
  int owner=-1;
  if(menu){
   CGFloat w=self.bounds.size.width;
   if(CGRectContainsPoint(CGRectMake(w*.5-62,10,125,42),p)){SDL_Window *window=SDL_GetKeyboardFocus();[self requestKeyboard:!(window&&SDL_IsScreenKeyboardShown(window))];continue;}
   int button=-1;for(int b=wrathios::touch::ActionCount-1;b>=0;b--)if(CGRectContainsPoint([self buttonRect:b],p)){button=b;break;}
   if(button==31){[self showSettings];continue;}
   if(button==6){_tray=_tray?0:1;[self setNeedsDisplay];continue;}
   if(_tray==1&&button==12){_tray=2;[self setNeedsDisplay];continue;}
   if(button==0||button==1||button==5){
    if([_owners.allValues containsObject:@104])continue;owner=104;auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(33);
   }else if(button==2||button==3||button==4){
    if([_owners.allValues containsObject:@105])continue;owner=105;auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(34);
   }else if(button>=0){continue;
   }else{
    if([_owners.allValues containsObject:@103])continue;owner=103;_navOrigin=p;
    auto &s=S();std::scoped_lock lock(s.mutex);s.menuPad=true;
   }
  }
  else {
   if(_artifactHolding&&p.x>=self.bounds.size.width*.42&&!CGRectContainsPoint([self buttonRect:26],p)&&!CGRectContainsPoint([self buttonRect:3],p)&&!CGRectContainsPoint([self buttonRect:31],p)){
    if([_owners.allValues containsObject:@106])continue;
    _owners[key]=@106;_last[key]=[NSValue valueWithCGPoint:p];[self artifactPoint:p relativeTo:[self artifactStickCenter]];continue;
   }
   for(int b=wrathios::touch::ActionCount-1;b>=0;b--)if(CGRectContainsPoint([self buttonRect:b],p)){owner=b;break;}
   if((owner==6||owner==21)&&([_owners.allValues containsObject:@200]||[_owners.allValues containsObject:@202]))continue;
   if(owner==6||owner==21){_tray=owner==6?1:2;_radialSelection=-1;owner=200;}
   else if(owner==31){[self showSettings];continue;}
   else if(owner==26&&_tray!=3){if([_owners.allValues containsObject:@201])continue;_artifactStart=t.timestamp;_artifactOrigin=p;_artifactHolding=NO;owner=201;}
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
 if(_editingLayout){[self editTouches:touches phase:1];return;}
 (void)event;
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;
  int owner=n.intValue;CGPoint p=[t locationInView:self],last=[_last[key] CGPointValue];
  if(owner==200||owner==202){
   _radialSelection=[self radialAt:p];
   int held=(_radialSelection>=0&&wrathios::touch::Actions[_radialSelection].down[0]=='+')?(int)_radialSelection+1:0;
   if(held!=_radialHeld){auto &s=S();std::scoped_lock lock(s.mutex);if(_radialHeld)s.keys.push_back(-_radialHeld);if(held)s.keys.push_back(held);_radialHeld=held;}
   [self setNeedsDisplay];continue;}
   if(owner==106){if(_artifactHolding)[self artifactPoint:p relativeTo:[self artifactStickCenter]];_last[key]=[NSValue valueWithCGPoint:p];continue;}
   if(owner==201){
    if(_artifactHolding&&![_owners.allValues containsObject:@106])[self artifactPoint:p relativeTo:_artifactOrigin];
   _last[key]=[NSValue valueWithCGPoint:p];continue;
  }
  if(owner==102)[self menuPoint:p button:0];
  else {auto &s=S();std::scoped_lock lock(s.mutex);
   if(owner==101||owner==0||owner==2){s.lookX+=(p.x-last.x)*_swipeGain;s.lookY+=(p.y-last.y)*_swipeGain;}
   if(owner==103){auto stick=wrathios::touch::Stick({p.x-_navOrigin.x,p.y-_navOrigin.y});s.navX=stick.x;s.navY=stick.y;}
   if(owner==100){auto stick=wrathios::touch::Stick({p.x-_moveOrigin.x,p.y-_moveOrigin.y});s.moveX=stick.x;s.moveY=stick.y;}
  }
  _last[key]=[NSValue valueWithCGPoint:p];
 }
}
- (void)finish:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
 if(_editingLayout){[self editTouches:touches phase:2];return;}
 for(UITouch *t in touches){NSValue *key=[NSValue valueWithNonretainedObject:t];NSNumber *n=_owners[key];if(!n)continue;int owner=n.intValue;
   if(owner==106){
    {auto &s=S();std::scoped_lock lock(s.mutex);s.artifactX=s.artifactY=0;}
    [_owners removeObjectForKey:key];[_last removeObjectForKey:key];[self setNeedsDisplay];continue;
   }
   if(owner==200||owner==202||owner==201){
   if(owner==201&&_artifactHolding){
     {auto &s=S();std::scoped_lock lock(s.mutex);s.keys.push_back(-12);s.artifactHeld=false;if(cancelled)s.artifactX=s.artifactY=0;}
     _artifactHolding=NO;
     for(NSValue *other in _owners.allKeys)if(_owners[other].intValue==106){[_owners removeObjectForKey:other];[_last removeObjectForKey:other];}
    }
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
  if(owner==104)s.keys.push_back(-33);
  if(owner==105)s.keys.push_back(-34);
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
int WrathIOSTouchNextKey(void){auto &s=S();std::scoped_lock lock(s.mutex);if(s.keys.empty())return 0;int key=s.keys.front();unsigned long long bit=1ULL<<(abs(key)-1);if(s.consumed&bit)return 0;s.consumed|=bit;s.keys.pop_front();return key;}
void WrathIOSTouchFrame(float *yaw,float *pitch,float *side,float *forward,unsigned *buttons){
 auto &s=S();std::scoped_lock lock(s.mutex);*yaw=s.game?s.lookX:0;*pitch=s.game?s.lookY:0;*side=s.game?s.moveX:0;*forward=s.game?s.moveY:0;*buttons=s.suspended?0:s.buttons;s.lookX=s.lookY=0;
}

void WrathIOSTouchTextFocus(int active){auto &s=S();{std::scoped_lock lock(s.mutex);s.textFocus=active!=0;}Refresh();}
int WrathIOSTouchNextText(void){auto &s=S();std::scoped_lock lock(s.mutex);if(s.text.empty())return 0;int c=s.text.front();s.text.pop_front();return c;}

const char *WrathIOSTouchActionCommand(int action,int down){if(action<0||action>=wrathios::touch::ActionCount)return "";return down?wrathios::touch::Actions[action].down:wrathios::touch::Actions[action].up;}

int WrathIOSTouchMenuPad(float *x,float *y){auto &s=S();std::scoped_lock lock(s.mutex);*x=s.navX;*y=s.navY;return s.menu&&s.menuPad;}
int WrathIOSTouchNextPadButton(void){auto &s=S();std::scoped_lock lock(s.mutex);return s.pad.next();}

void WrathIOSTouchSetCapture(int captured){auto &s=S();std::scoped_lock lock(s.mutex);s.captured=captured!=0;if(!s.captured&&!s.artifactHeld){s.artifactPad=false;s.artifactX=s.artifactY=0;}}
int WrathIOSTouchArtifactStick(float *x,float *y){auto &s=S();std::scoped_lock lock(s.mutex);*x=s.artifactX;*y=s.artifactY;return s.artifactPad;}

void WrathIOSTouchBeginControllerFrame(void){auto &s=S();std::scoped_lock lock(s.mutex);s.consumed=0;}

void WrathIOSLogicalWindowSize(int *width,int *height){SDL_Window *window=SDL_GetKeyboardFocus();if(window)SDL_GetWindowSize(window,width,height);else{if(width)*width=0;if(height)*height=0;}}

#ifdef WRATH_IOS_GLES3
int WrathIOSPreferredMSAASamples(int configured){NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"WrathMSAASamplesV1"];return WrathMobileMSAASamples(saved!=nil,saved.intValue,configured);}
int WrathIOSPreferredFXAA(int configured){NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"WrathFXAAV1"];return saved?saved.boolValue:configured;}
#endif
