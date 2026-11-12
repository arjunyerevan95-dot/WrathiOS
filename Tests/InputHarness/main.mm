#import <UIKit/UIKit.h>
#import <SDL.h>
#import <SDL_system.h>
#import "WrathSemanticMenuBridge.h"
@interface InputHarness : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation InputHarness
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
 (void)app;(void)options;
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[UIViewController new];[self.window makeKeyAndVisible];
 dispatch_async(dispatch_get_main_queue(),^{
  SDL_SetMainReady();SDL_iPhoneSetEventPump(SDL_TRUE);SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS,"0");
  if(SDL_Init(SDL_INIT_VIDEO)!=0)abort();
  if(!SDL_CreateWindow("Input integration test",0,0,844,390,SDL_WINDOW_SHOWN))abort();
  BOOL gameplay=[NSProcessInfo.processInfo.arguments containsObject:@"--gameplay"];
  BOOL profile=[NSProcessInfo.processInfo.arguments containsObject:@"--profile"];
  NSMutableString *typed=[NSMutableString new];int accepts=0;
  NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  // Match the production Host_Main ownership: main-thread blocking loop, with
  // UIKit served by SDL's real iOS event pump rather than a fake responder.
  while(1){@autoreleasepool{
   WrathIOSTouchSetMode(!gameplay,gameplay);WrathIOSTouchTextFocus(profile);
   SDL_Event event;
   while(SDL_PollEvent(&event)){
    if(event.type==SDL_TEXTINPUT)[typed appendString:[NSString stringWithUTF8String:event.text.text]];
    if(event.type==SDL_KEYDOWN&&event.key.keysym.sym==SDLK_BACKSPACE&&typed.length)[typed deleteCharactersInRange:NSMakeRange(typed.length-1,1)];
   }
   int edge=WrathIOSTouchNextPadButton();if(edge==1)accepts++;
   NSDictionary *state=@{@"typed":typed,@"accepts":@(accepts),@"gameplay":@(gameplay),@"keyboard":@(SDL_IsScreenKeyboardShown(SDL_GetKeyboardFocus()))};
   [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil]writeToURL:[dir URLByAppendingPathComponent:[NSString stringWithFormat:@"harness-%@.json",gameplay?@"game":profile?@"profile":@"manual"]] atomically:YES];
   SDL_Delay(10);
  }}
 });
 return YES;
}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {(void)application;(void)window;return UIInterfaceOrientationMaskLandscape;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(InputHarness.class));}}
