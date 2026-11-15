// Changed-path smoke only: real UIKit surface + SDL/EAGL; transport touch stubs.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES3/gl.h>
#import <SDL.h>
#import <SDL_system.h>
#include "WrathSemanticMenuBridge.h"
#include "WrathMobileGraphics.h"
#include "WrathGLES3Resolve.h"
#include "FXAAFragment.h"
#include <vector>
#include <algorithm>

static void Require(bool ok,NSString *message){if(!ok)[NSException raise:@"MobileSmoke" format:@"%@",message];}
static void Clean(NSString *message){Require(glGetError()==GL_NO_ERROR,message);}
// The real engine implements these Cvar accessors. This UI fixture supplies
// configuration transport only; the package build links the real definitions.
static int requestedSamples=2,fxaaEnabled=1;
int WrathIOSGraphicsRequestedSamples(void){return requestedSamples;}
int WrathIOSGraphicsActiveSamples(void){GLint n=0;glGetIntegerv(GL_SAMPLES,&n);return n>1?n:1;}
int WrathIOSGraphicsFXAA(void){return fxaaEnabled;}
void WrathIOSGraphicsSetSamples(int n){requestedSamples=n;}
void WrathIOSGraphicsSetFXAA(int n){fxaaEnabled=n!=0;}

@interface WrathSemanticTouchSurface:UIView
-(CGRect)buttonRect:(int)b;
-(CGPoint)artifactStickCenter;
-(void)refresh;
-(void)reset;
-(void)showSettings;
-(void)closeSettings;
@end
@interface SmokeTouch:NSObject
@property CGPoint point;
@property double stamp;
-(CGPoint)locationInView:(UIView *)view;
-(NSTimeInterval)timestamp;
@end
@implementation SmokeTouch
-(CGPoint)locationInView:(UIView *)view{(void)view;return self.point;}
-(NSTimeInterval)timestamp{return self.stamp;}
@end
static SmokeTouch *Touch(CGPoint p,double age=0){SmokeTouch *t=[SmokeTouch new];t.point=p;t.stamp=NSProcessInfo.processInfo.systemUptime-age;return t;}
static NSSet *Touches(SmokeTouch *t){return [NSSet setWithObject:t];}
static std::vector<int> Drain(){std::vector<int> keys;for(int frame=0;frame<35;frame++){WrathIOSTouchBeginControllerFrame();int k;while((k=WrathIOSTouchNextKey()))keys.push_back(k);}return keys;}
static bool Has(const std::vector<int>&v,int k){return std::find(v.begin(),v.end(),k)!=v.end();}
static UIView *Find(UIView *v,NSString *identifier){if([v.accessibilityIdentifier isEqual:identifier])return v;for(UIView *c in v.subviews){UIView *found=Find(c,identifier);if(found)return found;}return nil;}
static bool StickVisible(WrathSemanticTouchSurface *v){for(UIAccessibilityElement *e in v.accessibilityElements)if([e.accessibilityIdentifier isEqual:@"WrathArtifactRightStick"])return true;return false;}

static void InputSmoke(WrathSemanticTouchSurface *v,NSMutableArray *checks){
 auto begin=^(SmokeTouch *t){[v touchesBegan:Touches(t) withEvent:nil];};
 auto move=^(SmokeTouch *t){[v touchesMoved:Touches(t) withEvent:nil];};
 auto end=^(SmokeTouch *t){[v touchesEnded:Touches(t) withEvent:nil];};
 [v reset];WrathIOSTouchSetCapture(0);Drain();
 SmokeTouch *left=Touch(CGPointMake(v.bounds.size.width*.15,v.bounds.size.height*.55));begin(left);left.point=CGPointMake(left.point.x+54,left.point.y);move(left);
 SmokeTouch *fire=Touch(CGPointMake(CGRectGetMidX([v buttonRect:0]),CGRectGetMidY([v buttonRect:0])));begin(fire);
 SmokeTouch *hold=Touch(CGPointMake(CGRectGetMidX([v buttonRect:26]),CGRectGetMidY([v buttonRect:26])),.5);begin(hold);[v refresh];[v refresh];
 Require(StickVisible(v),@"stationary Artifact hold must expose a visible right stick");auto keys=Drain();Require(Has(keys,12),@"hold must send native Inventory down");WrathIOSTouchSetCapture(1);
 CGPoint center=[v artifactStickCenter];SmokeTouch *right=Touch(CGPointMake(center.x+54,center.y));begin(right);float x=0,y=0;
 Require(WrathIOSTouchArtifactStick(&x,&y)&&x>.99&&fabs(y)<.001,@"right direction");[v refresh];Require(WrathIOSTouchArtifactStick(&x,&y)&&x>.99,@"direction persists without motion");
 float yaw,pitch,side,forward;unsigned buttons;WrathIOSTouchFrame(&yaw,&pitch,&side,&forward,&buttons);Require(side>.99&&(buttons&1),@"move and fire ownership survive Artifact/right-stick hold");
 end(right);Require(WrathIOSTouchArtifactStick(&x,&y)&&x==0&&y==0,@"lifting selector returns stick to center without releasing Inventory");
 right=Touch(CGPointMake(center.x,center.y-54));begin(right);Require(WrathIOSTouchArtifactStick(&x,&y)&&y>.99,@"up direction");end(hold);[v refresh];keys=Drain();Require(Has(keys,-12)&&!Has(keys,27),@"hold release must select via native Inventory release, never tap-use");Require(!StickVisible(v),@"stick hides on holder release");
 WrathIOSTouchSetCapture(0);Require(!WrathIOSTouchArtifactStick(&x,&y),@"capture end clears selector override");end(left);end(fire);Drain();[checks addObject:@"artifact-visible-absolute-selection-simultaneous-move-fire"];
 hold=Touch(CGPointMake(CGRectGetMidX([v buttonRect:26]),CGRectGetMidY([v buttonRect:26])),.5);begin(hold);[v refresh];[v refresh];WrathIOSTouchSetCapture(1);right=Touch(CGPointMake(center.x-54,center.y));begin(right);[v touchesCancelled:Touches(hold) withEvent:nil];keys=Drain();Require(Has(keys,-12)&&!Has(keys,27),@"cancel releases Inventory without tap-use");Require(WrathIOSTouchArtifactStick(&x,&y)&&x==0&&y==0,@"cancel neutralizes selector");WrathIOSTouchSetCapture(0);[checks addObject:@"artifact-cancel-neutral-no-stuck-inventory"];
 hold=Touch(CGPointMake(CGRectGetMidX([v buttonRect:26]),CGRectGetMidY([v buttonRect:26])),.5);begin(hold);[v refresh];hold.point=CGPointMake(hold.point.x+54,hold.point.y);move(hold);Require(WrathIOSTouchArtifactStick(&x,&y)&&x>.99,@"holder can also drag to select");end(hold);WrathIOSTouchSetCapture(0);Drain();[v refresh];
 SmokeTouch *tap=Touch(CGPointMake(CGRectGetMidX([v buttonRect:26]),CGRectGetMidY([v buttonRect:26])));begin(tap);end(tap);keys=Drain();Require(Has(keys,27)&&Has(keys,-27)&&!Has(keys,12),@"short Artifact tap still uses selected artifact");[checks addObject:@"artifact-holder-drag-and-short-tap-retained"];
}
static void SettingsSmoke(WrathSemanticTouchSurface *v,NSMutableArray *checks){
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;NSString *domain=NSBundle.mainBundle.bundleIdentifier;
 [prefs setDouble:1 forKey:@"WrathRenderScaleV1"];[prefs setObject:@{@"0":@[@.8,@.5,@1.2]} forKey:@"WrathTouchLayoutV1"];
 requestedSamples=1;fxaaEnabled=0;NSDictionary *before=[prefs persistentDomainForName:domain];[v showSettings];
 UISegmentedControl *scale=(UISegmentedControl *)Find(v,@"WrathRenderResolution");UISegmentedControl *msaa=(UISegmentedControl *)Find(v,@"WrathMSAA");UISwitch *fxaa=(UISwitch *)Find(v,@"WrathFXAA");
 Require(scale.numberOfSegments==4&&scale.selectedSegmentIndex==0&&msaa.selectedSegmentIndex==0&&!fxaa.on,@"saved Native and configured AA Off must stay selected");Require([before isEqual:[prefs persistentDomainForName:domain]],@"opening Settings must not persist or overwrite preferences");
 scale.selectedSegmentIndex=3;[scale sendActionsForControlEvents:UIControlEventValueChanged];Require([prefs doubleForKey:@"WrathRenderScaleV1"]==.33,@"0.33x choice persists");
 msaa.selectedSegmentIndex=1;[msaa sendActionsForControlEvents:UIControlEventValueChanged];fxaa.on=YES;[fxaa sendActionsForControlEvents:UIControlEventValueChanged];Require(requestedSamples==2&&fxaaEnabled==1,@"AA user choices reach engine accessors");Require([[prefs objectForKey:@"WrathTouchLayoutV1"] isEqual:before[@"WrathTouchLayoutV1"]],@"graphics changes preserve control layout");
 [v closeSettings];[prefs removeObjectForKey:@"WrathRenderScaleV1"];before=[prefs persistentDomainForName:domain];[v showSettings];scale=(UISegmentedControl *)Find(v,@"WrathRenderResolution");Require(scale.selectedSegmentIndex==2,@"missing scale defaults to 0.5x");Require([before isEqual:[prefs persistentDomainForName:domain]],@"mobile default must not create a saved choice");[v closeSettings];[checks addObject:@"settings-four-scales-existing-values-no-migration-aa-controls"];
}
static GLuint Program(const char *fragment){const char *vertex="attribute vec2 position;varying highp vec2 TexCoord1;void main(){TexCoord1=position*.5+.5;gl_Position=vec4(position,0.,1.);}";GLuint p=glCreateProgram();for(int i=0;i<2;i++){GLuint s=glCreateShader(i?GL_FRAGMENT_SHADER:GL_VERTEX_SHADER);const char *src=i?fragment:vertex;glShaderSource(s,1,&src,NULL);glCompileShader(s);GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);char log[2048]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);Require(ok,[NSString stringWithFormat:@"shader: %s",log]);glAttachShader(p,s);glDeleteShader(s);}glBindAttribLocation(p,0,"position");glLinkProgram(p);GLint ok=0;glGetProgramiv(p,GL_LINK_STATUS,&ok);Require(ok,@"shader link");return p;}
static GLuint Texture(){GLuint t;glGenTextures(1,&t);glBindTexture(GL_TEXTURE_2D,t);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,16,16,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);return t;}
static void AASmoke(NSMutableArray *checks){
 GLint savedRead,savedDraw;glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&savedRead);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&savedDraw);
 GLuint f[3],rb,vbo;glGenFramebuffers(3,f);GLuint resolve=Texture(),copy=Texture(),output=Texture();
 glBindFramebuffer(GL_FRAMEBUFFER,f[1]);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,resolve,0);glBindFramebuffer(GL_FRAMEBUFFER,f[2]);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,output,0);
 glGenRenderbuffers(1,&rb);glBindRenderbuffer(GL_RENDERBUFFER,rb);glRenderbufferStorageMultisample(GL_RENDERBUFFER,2,GL_RGBA8,16,16);glBindFramebuffer(GL_FRAMEBUFFER,f[0]);glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,rb);Require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,@"2x MSAA framebuffer");GLint samples=0;glGetIntegerv(GL_SAMPLES,&samples);Require(samples>1,@"actual multiple samples required");
 GLuint solid=Program("precision highp float;void main(){gl_FragColor=vec4(1.);}");glGenBuffers(1,&vbo);glBindBuffer(GL_ARRAY_BUFFER,vbo);const GLfloat triangle[]={-1,-1,1,-1,-1,.35f};glBufferData(GL_ARRAY_BUFFER,sizeof(triangle),triangle,GL_STATIC_DRAW);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,0);glEnableVertexAttribArray(0);glViewport(0,0,16,16);glClearColor(0,0,0,1);glClear(GL_COLOR_BUFFER_BIT);glUseProgram(solid);glDrawArrays(GL_TRIANGLES,0,3);
 glBindTexture(GL_TEXTURE_2D,copy);WrathGLES3CopyResolvedToTexture(GL_TEXTURE_2D,0,0,0,0,0,16,16,f[0],f[1],16,16);GLint read,draw;glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw);Require((GLuint)read==f[0]&&(GLuint)draw==f[0],@"resolve/copy restores both engine framebuffer bindings");Clean(@"MSAA resolve and copy");
 glBindFramebuffer(GL_FRAMEBUFFER,f[2]);const GLfloat full[]={-1,-1,3,-1,-1,3};glBufferData(GL_ARRAY_BUFFER,sizeof(full),full,GL_STATIC_DRAW);GLubyte baseline[1024],filtered[1024];GLuint off=Program("precision highp float;varying highp vec2 TexCoord1;uniform sampler2D Texture_First;void main(){gl_FragColor=texture2D(Texture_First,TexCoord1);}");GLuint on=Program(WrathSmokeFXAAFragment);
 for(int pass=0;pass<2;pass++){GLuint p=pass?on:off;glUseProgram(p);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,copy);glUniform1i(glGetUniformLocation(p,"Texture_First"),0);if(pass)glUniform2f(glGetUniformLocation(p,"PixelSize"),1.f/16,1.f/16);glDrawArrays(GL_TRIANGLES,0,3);glReadPixels(0,0,16,16,GL_RGBA,GL_UNSIGNED_BYTE,pass?filtered:baseline);Clean(@"pinned FXAA kernel draw/readback");}
 int changed=0,dark=0,bright=0;for(int i=0;i<1024;i+=4){if(abs((int)baseline[i]-(int)filtered[i])>2)changed++;if(filtered[i]<20)dark++;if(filtered[i]>235)bright++;Require(filtered[i+3]==255,@"FXAA alpha");}Require(changed>0&&dark>5&&bright>5,@"actual FXAA must alter edge pixels while retaining black and white regions");[checks addObject:@"actual-2x-msaa-resolve-copy-pinned-fxaa-edge-pixels"];
 glDeleteProgram(solid);glDeleteProgram(off);glDeleteProgram(on);glDeleteBuffers(1,&vbo);glDeleteRenderbuffers(1,&rb);glDeleteFramebuffers(3,f);glDeleteTextures(1,&resolve);glDeleteTextures(1,&copy);glDeleteTextures(1,&output);glBindFramebuffer(GL_READ_FRAMEBUFFER,savedRead);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,savedDraw);
}
@interface MobileSmokeApp:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
-(void)runSmoke;
@end
@implementation MobileSmokeApp
-(BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options{
 (void)app;(void)options;self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[UIViewController new];[self.window makeKeyAndVisible];
 [NSTimer scheduledTimerWithTimeInterval:.01 repeats:NO block:^(NSTimer *timer){(void)timer;[self runSmoke];}];return YES;
}
-(void)runSmoke{NSMutableDictionary *receipt=[@{@"passed":@NO,@"phoneTested":@NO,@"scope":@"Changed production UIKit behavior with touch/configuration transport stubs; actual SDL/EAGL MSAA and pinned FXAA kernel."} mutableCopy];NSMutableArray *checks=[NSMutableArray new];receipt[@"checks"]=checks;
 @try{[NSUserDefaults.standardUserDefaults setDouble:0 forKey:@"WrathTouchGyro"];SDL_SetMainReady();SDL_iPhoneSetEventPump(SDL_FALSE);Require(SDL_Init(SDL_INIT_VIDEO)==0,@"SDL video");SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION,3);SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION,0);SDL_GL_SetAttribute(SDL_GL_RED_SIZE,8);SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE,8);SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE,8);SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE,8);SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS,1);SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES,2);SDL_Window *w=SDL_CreateWindow("WRATH mobile smoke",0,0,844,390,SDL_WINDOW_SHOWN|SDL_WINDOW_OPENGL|SDL_WINDOW_ALLOW_HIGHDPI);Require(w!=NULL,@"SDL window");Require(SDL_GL_CreateContext(w)!=NULL,@"SDL GLES3 context");int lw,lh,dw,dh;SDL_GetWindowSize(w,&lw,&lh);SDL_GL_GetDrawableSize(w,&dw,&dh);double density=UIScreen.mainScreen.nativeScale;Require(fabs(dw-lw*density*.5)<=1&&fabs(dh-lh*density*.5)<=1,@"actual drawable uses the 0.5 native-pixel default");receipt[@"drawable"]=@[@(dw),@(dh)];receipt[@"actualMSAASamples"]=@(WrathIOSGraphicsActiveSamples());Require(WrathIOSGraphicsActiveSamples()>1,@"SDL actual MSAA");[checks addObject:@"sdl-native-pixel-half-scale-default-msaa"];
 WrathIOSTouchSetMode(0,1);WrathSemanticTouchSurface *surface=nil;for(UIWindow *window in UIApplication.sharedApplication.windows){UIView *v=[window viewWithTag:0x57524335];if(v)surface=(WrathSemanticTouchSurface *)v;}Require(surface!=nil,@"actual production touch surface");[surface refresh];InputSmoke(surface,checks);SettingsSmoke(surface,checks);AASmoke(checks);receipt[@"passed"]=@YES;
 }@catch(NSException *e){receipt[@"error"]=e.reason?:e.name;}
 NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;[[NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[dir URLByAppendingPathComponent:@"mobile-smoke.json"] atomically:YES];NSLog(@"WRATH_MOBILE_SMOKE %@",receipt);
}
-(UIInterfaceOrientationMask)application:(UIApplication *)app supportedInterfaceOrientationsForWindow:(UIWindow *)window{(void)app;(void)window;return UIInterfaceOrientationMaskLandscape;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(MobileSmokeApp.class));}}
