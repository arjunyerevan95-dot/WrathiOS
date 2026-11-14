// Experimental desktop GL compatibility bridge. CPU readback, not zero-copy.
#define WRATH_ZINK_IMPL
#include "WrathZinkBridge.h"
#ifdef WRATH_IOS_ZINK
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <mach/mach.h>
#include <os/proc.h>
#include <unistd.h>
#include <fcntl.h>
#include <atomic>
#include "WrathMemoryCutoff.h"

// Zink-only diagnostic cutoff. A large driver allocation can still outrun this
// sampler. Abrupt exit deliberately stops driver workers; it is not a graceful
// save. Never enable this path on the GLES rollback.
static std::atomic<int> memoryStage{0};
static dispatch_source_t memoryTimer,memoryLogTimer;
static int memoryFD=-1;
static std::atomic<uint64_t> memoryPeak{0},memoryFootprint{0},memoryAvailable{0};
static bool WrathMemorySample(void) {
 task_vm_info_data_t info={};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
 bool valid=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS;
 uint64_t footprint=valid?info.phys_footprint:0,available=os_proc_available_memory();
 if(footprint>memoryPeak.load())memoryPeak=footprint;
 memoryFootprint=footprint;memoryAvailable=available;
 bool stop=WrathMemoryShouldStop(valid,footprint,available);
 return !stop;
}
static void WrathMemoryWriteLastSample(void) {
 // Separate serial queue: slow storage must never stall the cutoff sampler.
 char line[384];int n=snprintf(line,sizeof(line),"{\"stage\":%d,\"footprint\":%llu,\"peak\":%llu,\"available\":%llu}\n",memoryStage.load(),(unsigned long long)memoryFootprint.load(),(unsigned long long)memoryPeak.load(),(unsigned long long)memoryAvailable.load());
 if(memoryFD>=0&&n>0){pwrite(memoryFD,line,(size_t)n,0);ftruncate(memoryFD,n);}
}
static bool WrathStartMemoryCutoff(void) {
 if(memoryTimer)return true;
 NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
 NSString *dir=[base stringByAppendingPathComponent:@"WrathiOS/Runtime"];
 if(![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nullptr])return false;
 memoryFD=open([[dir stringByAppendingPathComponent:@"zink-memory.json"] fileSystemRepresentation],O_CREAT|O_TRUNC|O_WRONLY,0600);
 if(memoryFD<0||!WrathMemorySample())return false;
 dispatch_queue_t queue=dispatch_queue_create("wrath.zink.memory-cutoff",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INITIATED,0));
 memoryTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
 if(!memoryTimer)return false;
 dispatch_source_set_timer(memoryTimer,dispatch_time(DISPATCH_TIME_NOW,0),20*NSEC_PER_MSEC,2*NSEC_PER_MSEC);
 dispatch_source_set_event_handler(memoryTimer,^{if(!WrathMemorySample())_Exit(78);});
 dispatch_resume(memoryTimer);
 dispatch_queue_t logQueue=dispatch_queue_create("wrath.zink.memory-log",DISPATCH_QUEUE_SERIAL);
 memoryLogTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,logQueue);
 if(memoryLogTimer){
  dispatch_source_set_timer(memoryLogTimer,dispatch_time(DISPATCH_TIME_NOW,0),250*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
  dispatch_source_set_event_handler(memoryLogTimer,^{WrathMemoryWriteLastSample();});
  dispatch_resume(memoryLogTimer);
 }
 return true;
}

static void *mesa,*context;
static void (*destroyContext)(void*);
static SDL_Renderer *presenter;
static SDL_Texture *texture;
static unsigned char *pixels;
static int width,height;
void WrathZinkGetDrawableSize(SDL_Window*,int*w,int*h){if(w)*w=width;if(h)*h=height;}
static void *(*createContext)(const int*,void*);
static unsigned char (*makeCurrent)(void*,void*,unsigned,int,int);
static void *(*getProc)(const char*);
static int WrathZinkEnsureLibrary(void);
int WrathZinkLoadLibrary(const char*){return WrathZinkEnsureLibrary();}
int WrathZinkSetAttribute(SDL_GLattr,int){return 0;}
int WrathZinkGetAttribute(SDL_GLattr a,int*v){
 if(!v)return -1;
 *v=a==SDL_GL_DEPTH_SIZE?24:a==SDL_GL_STENCIL_SIZE?8:a==SDL_GL_DOUBLEBUFFER?1:
    (a==SDL_GL_RED_SIZE||a==SDL_GL_GREEN_SIZE||a==SDL_GL_BLUE_SIZE||a==SDL_GL_ALPHA_SIZE)?8:0;
 return 0;
}
int WrathZinkSetSwapInterval(int interval){return presenter?SDL_RenderSetVSync(presenter,interval?1:0):-1;}
SDL_Window *WrathZinkCreateWindow(const char*n,int x,int y,int w,int h,Uint32 f){
 return SDL_CreateWindow(n,x,y,w,h,(f&~SDL_WINDOW_OPENGL)|SDL_WINDOW_ALLOW_HIGHDPI);
}
void *WrathZinkGetProcAddress(const char*n){
 if(WrathZinkEnsureLibrary()!=0)return nullptr;
 return getProc(n);
}
void WrathZinkDrain(void){if(context&&getProc){auto finish=(void(*)(void))getProc("glFinish");if(finish)finish();}}
void WrathZinkDestroyWindow(SDL_Window*w){
 WrathZinkDrain();if(texture)SDL_DestroyTexture(texture);texture=nullptr;
 if(presenter)SDL_DestroyRenderer(presenter);presenter=nullptr;
 if(context&&destroyContext)destroyContext(context);context=nullptr;
 free(pixels);pixels=nullptr;SDL_DestroyWindow(w);
 // Keep loaded modules alive: driver worker threads can outlive a context.
}
static int WrathZinkEnsureLibrary(void){
 if(mesa&&createContext&&makeCurrent&&getProc&&destroyContext)return 0;
 if(!WrathStartMemoryCutoff()){SDL_SetError("Zink memory telemetry unavailable or insufficient headroom");return -1;}
 memoryStage=1;
 NSString *dir=NSBundle.mainBundle.privateFrameworksPath;
 const char *vk=[[dir stringByAppendingPathComponent:@"libMoltenVK.dylib"] fileSystemRepresentation];
 unsetenv("MESA_GL_VERSION_OVERRIDE");unsetenv("MESA_GLSL_VERSION_OVERRIDE");
 setenv("GALLIUM_DRIVER","zink",1);setenv("ZINK_VULKAN_LIBRARY",vk,1);
 setenv("MESA_SHADER_CACHE_DISABLE","true",1);
 // Do not override reported GL/GLSL versions or advertise unsupported capabilities.
 mesa=dlopen([[dir stringByAppendingPathComponent:@"libOSMesa.dylib"] fileSystemRepresentation],RTLD_NOW|RTLD_LOCAL);
 if(!mesa){SDL_SetError("OSMesa load failed: %s",dlerror());return -1;}
 createContext=(void*(*)(const int*,void*))dlsym(mesa,"OSMesaCreateContextAttribs");
 makeCurrent=(unsigned char(*)(void*,void*,unsigned,int,int))dlsym(mesa,"OSMesaMakeCurrent");
 getProc=(void*(*)(const char*))dlsym(mesa,"OSMesaGetProcAddress");
 destroyContext=(void(*)(void*))dlsym(mesa,"OSMesaDestroyContext");
 if(!createContext||!makeCurrent||!getProc||!destroyContext){SDL_SetError("Incomplete OSMesa entry points");return -1;}
 return 0;
}
SDL_GLContext WrathZinkCreateContext(SDL_Window*w){
 if(WrathZinkEnsureLibrary()!=0)return nullptr;
 SDL_GetWindowSize(w,&width,&height);
 // Diagnostic candidate: one scene pixel per UIKit point, no 2x amplification.
 memoryStage=2;
 if(width<1||height<1||width>4096||height>4096){SDL_SetError("Invalid scene size");return nullptr;}
 const int attributes[]={0x22,0x1908,0x30,24,0x31,8,0x33,0x35,0x36,2,0x37,1,0};
 context=createContext(attributes,nullptr);memoryStage=3;pixels=(unsigned char*)calloc((size_t)width*height,4);
 if(!context||!pixels||!makeCurrent(context,pixels,0x1401,width,height)){SDL_SetError("Desktop compatibility context unavailable");return nullptr;}
 auto gs=(const unsigned char*(*)(unsigned))getProc("glGetString");
 const char *renderer=gs?(const char*)gs(0x1F01):nullptr;
 const char *version=gs?(const char*)gs(0x1F02):nullptr;
 int major=0,minor=0;if(version)sscanf(version,"%d.%d",&major,&minor);
 if(!renderer||(!strstr(renderer,"zink")&&!strstr(renderer,"Zink"))||strstr(renderer,"llvmpipe")||strstr(renderer,"lavapipe")||major<2||(major==2&&minor<1)){
  SDL_SetError("Expected hardware Zink desktop GL >=2.1, got %s / %s",renderer?renderer:"none",version?version:"none");return nullptr;
 }
 SDL_SetHint(SDL_HINT_RENDER_DRIVER,"metal");SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY,"linear");
 presenter=SDL_CreateRenderer(w,-1,SDL_RENDERER_ACCELERATED|SDL_RENDERER_PRESENTVSYNC);
 if(!presenter)return nullptr;
 SDL_RenderSetLogicalSize(presenter,width,height);
 texture=SDL_CreateTexture(presenter,SDL_PIXELFORMAT_RGBA32,SDL_TEXTUREACCESS_STREAMING,width,height);
 if(!texture)return nullptr;
 memoryStage=4;
 fprintf(stderr,"WRATH Zink experimental: %s; %s; %dx%d CPU readback to Metal\n",renderer,version,width,height);
 return context;
}
void WrathZinkSwapWindow(SDL_Window*){
 if(!context||!texture||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
 memoryStage=5;
 auto read=(void(*)(int,int,int,int,unsigned,unsigned,void*))getProc("glReadPixels");if(!read)return;
 read(0,0,width,height,0x1908,0x1401,pixels);
 SDL_SetRenderDrawColor(presenter,0,0,0,255);
 if(SDL_UpdateTexture(texture,nullptr,pixels,width*4)||SDL_RenderClear(presenter)||SDL_RenderCopyEx(presenter,texture,nullptr,nullptr,0,nullptr,SDL_FLIP_VERTICAL))return;
 SDL_RenderPresent(presenter);
}
#endif
