#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES3/gl.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>

static void Require(BOOL ok, NSString *what) { if(!ok) [NSException raise:@"GLES3Probe" format:@"%@",what]; }
static void Clean(NSString *stage) { GLenum e=glGetError(); Require(e==GL_NO_ERROR,[NSString stringWithFormat:@"%@ GL error 0x%x",stage,e]); }
static GLuint Shader(GLenum kind,const char *source) {
 GLuint s=glCreateShader(kind); glShaderSource(s,1,&source,NULL); glCompileShader(s);
 GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);char log[4096]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);
 Require(ok,[NSString stringWithFormat:@"ESSL100 compile: %s",log]);return s;
}
static GLuint Program(const char *fragment) {
 const char *vertex="attribute vec2 position; varying highp vec2 uv; void main(){uv=position*.5+.5;gl_Position=vec4(position,-.5,1.);}";
 GLuint v=Shader(GL_VERTEX_SHADER,vertex),f=Shader(GL_FRAGMENT_SHADER,fragment),p=glCreateProgram();
 glAttachShader(p,v);glAttachShader(p,f);glBindAttribLocation(p,0,"position");glLinkProgram(p);
 GLint ok=0;glGetProgramiv(p,GL_LINK_STATUS,&ok);char log[4096]={0};glGetProgramInfoLog(p,sizeof(log),NULL,log);
 Require(ok,[NSString stringWithFormat:@"ESSL100 link: %s",log]);glDeleteShader(v);glDeleteShader(f);return p;
}
static GLuint Texture(GLint internal,GLenum format,GLenum type) {
 GLuint t;glGenTextures(1,&t);glBindTexture(GL_TEXTURE_2D,t);
 glTexImage2D(GL_TEXTURE_2D,0,internal,8,8,0,format,type,NULL);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
 Clean(@"texture allocation");return t;
}
static void Complete(NSString *label) {Require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,label);Clean(label);}
@interface ProbeView:UIView @end
@implementation ProbeView
+(Class)layerClass{return CAEAGLLayer.class;}
@end
@interface ProbeApp:NSObject<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) ProbeView *surface;
-(void)runProbe;
@end
@implementation ProbeApp
-(BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)options {
 (void)app;(void)options;
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
 UIViewController *vc=[UIViewController new];self.window.rootViewController=vc;
 self.surface=[[ProbeView alloc]initWithFrame:CGRectMake(0,0,32,32)];self.surface.contentScaleFactor=1;
 CAEAGLLayer *layer=(CAEAGLLayer*)self.surface.layer;layer.opaque=YES;layer.drawableProperties=@{kEAGLDrawablePropertyRetainedBacking:@YES,kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
 [vc.view addSubview:self.surface];[self.window makeKeyAndVisible];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self runProbe];});return YES;
}
-(void)runProbe {
 NSMutableDictionary *receipt=[@{@"schema":@1,@"passed":@NO,@"probe":@"real ES3 GPU FBO/depth/manual-PCF",@"deviceTested":@NO} mutableCopy];
 NSMutableArray *checks=[NSMutableArray new];receipt[@"checks"]=checks;
 @try {
 EAGLContext *context=[[EAGLContext alloc]initWithAPI:kEAGLRenderingAPIOpenGLES3];Require(context!=nil,@"ES3 context unavailable");Require([EAGLContext setCurrentContext:context],@"make current");
 receipt[@"renderer"]=@((const char*)glGetString(GL_RENDERER));receipt[@"version"]=@((const char*)glGetString(GL_VERSION));
 GLuint screen,screenColor;glGenFramebuffers(1,&screen);glGenRenderbuffers(1,&screenColor);Require(screen!=0,@"nonzero UIKit FBO");
 glBindRenderbuffer(GL_RENDERBUFFER,screenColor);Require([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.surface.layer],@"UIKit drawable storage");
 glBindFramebuffer(GL_FRAMEBUFFER,screen);glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,screenColor);Complete(@"UIKit initial FBO");
 GLuint color=Texture(GL_RGBA8,GL_RGBA,GL_UNSIGNED_BYTE),depth=Texture(GL_DEPTH_COMPONENT16,GL_DEPTH_COMPONENT,GL_UNSIGNED_SHORT),packed=Texture(GL_DEPTH24_STENCIL8,GL_DEPTH_STENCIL,GL_UNSIGNED_INT_24_8);
 GLuint fbo;glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,color,0);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,depth,0);Complete(@"RGBA8 plus depth16");[checks addObject:@"rgba8-depth16-complete"];
 glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,0,0);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_TEXTURE_2D,packed,0);Complete(@"RGBA8 plus depth24-stencil8");[checks addObject:@"rgba8-depth24stencil8-complete"];
 glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_TEXTURE_2D,0,0);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,0,0);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,depth,0);
 GLenum none=GL_NONE;glDrawBuffers(1,&none);glReadBuffer(GL_NONE);Complete(@"depth-only FBO");
 GLuint depthProgram=Program("precision highp float;void main(){gl_FragColor=vec4(1.);}");
 const GLfloat triangle[]={-1,-1,3,-1,-1,3};GLuint vbo;glGenBuffers(1,&vbo);glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,sizeof(triangle),triangle,GL_STATIC_DRAW);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,0);glEnableVertexAttribArray(0);
 glViewport(0,0,8,8);glEnable(GL_DEPTH_TEST);glDepthFunc(GL_ALWAYS);glDepthMask(GL_TRUE);glClearDepthf(1);glClear(GL_DEPTH_BUFFER_BIT);glUseProgram(depthProgram);glDrawArrays(GL_TRIANGLES,0,3);Clean(@"depth-only actual draw");[checks addObject:@"depth-only-essl100-draw"];
 glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,0,0);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,color,0);GLenum target=GL_COLOR_ATTACHMENT0;glDrawBuffers(1,&target);glReadBuffer(target);Complete(@"sample target");
 const char *sample="precision highp float;varying highp vec2 uv;uniform highp sampler2D depthTex;void main(){float d=texture2D(depthTex,uv).r;float p=0.;p+=step(.2,texture2D(depthTex,uv+vec2(.0625,0.)).r);p+=step(.2,texture2D(depthTex,uv-vec2(.0625,0.)).r);p+=step(.2,texture2D(depthTex,uv+vec2(0.,.0625)).r);p+=step(.2,texture2D(depthTex,uv-vec2(0.,.0625)).r);gl_FragColor=vec4(d,p*.25,step(.3,d),1.);}";
 GLuint sampleProgram=Program(sample);glUseProgram(sampleProgram);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,depth);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_COMPARE_MODE,GL_NONE);glUniform1i(glGetUniformLocation(sampleProgram,"depthTex"),0);glDisable(GL_DEPTH_TEST);glDrawArrays(GL_TRIANGLES,0,3);
 GLubyte pixel[4]={0};glReadPixels(4,4,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);Clean(@"depth sample readback");
 Require(abs((int)pixel[0]-64)<=2&&pixel[1]>=253&&pixel[2]<=2&&pixel[3]==255,@"raw .r depth/manual PCF pixel mismatch");receipt[@"depthSampleRGBA"]=@[@(pixel[0]),@(pixel[1]),@(pixel[2]),@(pixel[3])];[checks addObject:@"raw-depth-r-manual-pcf-pixel"];
 for(int pass=0;pass<2;pass++) {
  if(pass){self.surface.frame=CGRectMake(0,0,48,40);[self.surface layoutIfNeeded];glBindRenderbuffer(GL_RENDERBUFFER,screenColor);Require([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.surface.layer],@"resized drawable storage");}
  glBindFramebuffer(GL_FRAMEBUFFER,screen);Complete(@"restored UIKit FBO");glBindRenderbuffer(GL_RENDERBUFFER,screenColor);GLint w=0,h=0;glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_WIDTH,&w);glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_HEIGHT,&h);Require(w==(pass?48:32)&&h==(pass?40:32),@"drawable dimensions after resize");
  glViewport(0,0,w,h);glClearColor(.125,.5,.75,1);glClear(GL_COLOR_BUFFER_BIT);glReadPixels(w/2,h/2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);Clean(@"screen restore readback");Require(abs(pixel[0]-32)<=2&&abs(pixel[1]-128)<=2&&abs(pixel[2]-191)<=2,@"screen clear pixel mismatch");Require([context presentRenderbuffer:GL_RENDERBUFFER],@"present restored screen");
 }
 [checks addObject:@"nonzero-uikit-restore-resize-present"];
 glDeleteProgram(depthProgram);glDeleteProgram(sampleProgram);glDeleteBuffers(1,&vbo);glDeleteFramebuffers(1,&fbo);glDeleteTextures(1,&color);glDeleteTextures(1,&depth);glDeleteTextures(1,&packed);[EAGLContext setCurrentContext:nil];receipt[@"passed"]=@YES;
 }@catch(NSException *e){receipt[@"error"]=e.reason?:e.name;}
 NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;NSData *data=[NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil];[data writeToURL:[documents URLByAppendingPathComponent:@"gles3-probe.json"] atomically:YES];NSLog(@"WRATH_GLES3_PROBE %@",receipt);
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeApp.class));}}
