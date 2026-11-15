#!/usr/bin/env python3
"""Execute production iOS route and pinned VID_ApplyJoyState with transport stubs."""
from pathlib import Path
import re, subprocess, tempfile, os, shlex
r=Path(__file__).resolve().parents[2]
source=(r/'Vendor/wrath-darkplaces/vid_shared.c').read_text()
def function(name):
 a=source.index(name+'(') if name+'(' in source else source.index(name+' (')
 a=source.rfind('\n',0,a)+1;b=source.index('{',a);depth=1;i=b+1
 while depth:
  depth+=(source[i]=='{')-(source[i]=='}');i+=1
 return source[a:i]
route=(r/'Gate5C/WrathControllerRoute.inc').read_text()
start=source.index('static int joybuttonkey[MAXJOYBUTTON]')
end=source.index('int VID_Shared_SetJoystick',start)
apply=source[start:end]
keys=sorted(set(re.findall(r'\bK_[A-Z0-9_]+',apply+route)))
cvars=sorted(set(re.findall(r'\b(joy_\w+|cl_\w+)\.(?:integer|value)',apply)))
preamble='''#include <algorithm>
#include <cmath>
#include <cstring>
#include <cassert>
#include <cstdio>
#include <deque>
#include <vector>
#include <string>
using std::size_t;
using qboolean=bool;
#define MAXJOYBUTTON 36
#define MAXJOYAXIS 16
#define CONFIG_MENU 1
#define bound(a,b,c) std::clamp((float)(b),(float)(a),(float)(c))
struct cvar { int integer=0;float value=1;};
using cvar_t=cvar;
struct vid_joystate_t {bool is360=false;float axis[16]={};int button[36]={};};
static vid_joystate_t vid_joystate;
static double realtime=0;
static struct {struct{float forwardmove=0,sidemove=0,upmove=0;}cmd;float viewangles[3]={};float realframetime=.016f,sensitivityscale=1,viewzoom=1;bool csqc_loaded=true,csqc_wantsmousemove=false;}cl;
static float in_mouse_x,in_mouse_y;
struct Event{int key;bool down;};static std::vector<Event> events;
void Key_Event(int key,int,bool down){events.push_back({key,down});}
void CL_VM_InputEvent(int,float,float){}
void MR_InputEvent(int,float,float){}
static cvar joy_active;
void Cvar_SetValueQuick(cvar *c,float x){c->value=x;c->integer=x;}
void Con_Printf(const char *,...){}
'''
preamble+='enum {'+','.join(k+'='+str(i+100) for i,k in enumerate(keys))+'};\n'
preamble+='static cvar '+','.join(cvars)+';\n'
preamble+='''static std::deque<int> edges;static unsigned long long consumed;
void WrathIOSTouchBeginControllerFrame(){consumed=0;}
int WrathIOSTouchNextKey(){if(edges.empty())return 0;int e=edges.front();auto b=1ULL<<(abs(e)-1);if(consumed&b)return 0;consumed|=b;edges.pop_front();return e;}
static float look=0,move=0,nav=0;static bool menu=false;
void WrathIOSTouchFrame(float*y,float*p,float*s,float*f,unsigned*b){*y=look;*p=0;*s=move;*f=move;*b=0;look=0;}
int WrathIOSTouchMenuPad(float*x,float*y){*x=nav;*y=0;return menu;}
static bool artifact=false;static float artifactX=0,artifactY=0;
int WrathIOSTouchArtifactStick(float*x,float*y){*x=artifactX;*y=artifactY;return artifact;}
static std::string binds[1000];
const char *Key_GetBind(int key,int){return binds[key].c_str();}
void Key_FindKeysForCommand(const char*c,int*k,int n,int){std::fill(k,k+n,-1);for(int i=0,j=0;i<1000&&j<n;i++)if(binds[i]==c)k[j++]=i;}
'''
preamble+='#include "WrathTouchActions.hpp"\nconst char *WrathIOSTouchActionCommand(int a,int){return wrathios::touch::Actions[a].down;}\n'
p='#include <SDL.h>\n'+preamble
p+='''\n#define SDL_ALLOW_XINPUT 0
static cvar joy_enable,joy_index,joy_detected;
static SDL_GameController *vid_sdlcontroller;
static SDL_Joystick *vid_sdljoystick;
static int vid_sdljoystickindex=-1;
void VID_Shared_BuildJoyState_Begin(vid_joystate_t*j){*j={};}
void VID_Shared_BuildJoyState_Finish(vid_joystate_t*){}
enum controllertype_t {CONTROLLER_NULL,CONTROLLER_GENERIC,CONTROLLER_XBOX,CONTROLLER_PLAYSTATION,CONTROLLER_NINTENDO,CONTROLLER_STEAM};
'''
subprocess.run(['python3',str(r/'scripts/materialize_engine_patches.py')],check=True)
native=(r/'Derived/wrath-darkplaces-ios/vid_sdl.c').read_text()
def fun(name):
 a=native.index('\n'+name) if '\n'+name in native else native.index(name+'(')
 a=native.rfind('\n',0,a)+1;b=native.index('{',a);depth=1;i=b+1
 while depth:depth+=(native[i]=='{')-(native[i]=='}');i+=1
 return native[a:i]
# Extract full definitions by signature; keep native SDL sampling/query intact.
def extract(signature):
 a=native.index(signature);b=native.index('{',a);depth=1;i=b+1
 while depth:depth+=(native[i]=='{')-(native[i]=='}');i+=1
 return native[a:i]
p+=function('VID_JoyState_GetAxis')+'\n'+function('VID_KeyEventForButton')+'\n'+apply+'\n'
p+=extract('void VID_BuildJoyState(vid_joystate_t *joystate)')+'\n'
p+=(r/'Gate5C/WrathControllerRoute.inc').read_text()+'\n'
p+=extract('void VID_EnableJoystick(qboolean enable)')+'\n'+extract('controllertype_t VID_ControllerType(int index)')+'\n'
looksource=(r/'Derived/wrath-darkplaces-ios/cl_input.c').read_text()
a=looksource.index('#ifdef WRATH_IOS_GATE5C\n\t{float touchYaw,touchPitch;')
b=looksource.index('#endif',a)+len('#endif')
p+='\nstatic int key_consoleactive=0,key_dest=1;enum{key_game=1,YAW=1,PITCH=0};static cvar cl_prydoncursor;void V_StopPitchDrift(){}\n'
p+='void ApplyTouchLook(){\n'+looksource[a:b]+'\n}\n'
p+='''int main(){
 SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,"1");assert(SDL_Init(SDL_INIT_JOYSTICK|SDL_INIT_GAMECONTROLLER)==0);
 // Non-controller device occupies slot zero: production must select real touch Xbox.
 int dummy=SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_FLIGHT_STICK,2,2,0);assert(dummy==0);
 joy_x360_axisside.integer=0;joy_x360_axisforward.integer=1;joy_x360_axisyaw.integer=2;joy_x360_axispitch.integer=3;joy_x360_axisup.integer=-1;
 joy_x360_deadzoneside.value=joy_x360_deadzoneforward.value=joy_x360_deadzoneyaw.value=joy_x360_deadzonepitch.value=0;
 binds[K_X360_RIGHT_TRIGGER]="+attack";binds[K_X360_A]="+jump";
 auto tick=[](){VID_EnableJoystick(true);vid_joystate_t j;VID_BuildJoyState(&j);WrathIOSControllerFrame(&j);VID_ApplyJoyState(&j);realtime+=.016;};
 joy_axiskeyevents.integer=1;
 edges={1};look=2;move=.7;tick();assert(joy_axiskeyevents.integer==0);
 assert(joy_index.integer==1);assert(joy_active.integer==1);assert(joy_detected.integer==2);assert(VID_ControllerType(joy_index.integer)==CONTROLLER_XBOX);
 assert(std::any_of(events.begin(),events.end(),[](Event e){return e.key==K_X360_RIGHT_TRIGGER&&e.down;}));assert(wrath_ios_look_yaw==2);
 assert(cl.cmd.forwardmove>.6&&cl.cmd.sidemove>.6);
 look=3;tick();assert(wrath_ios_look_yaw==5);
 binds[K_X360_RIGHT_TRIGGER]="+button3"; // release original key even after binding changes
 edges={-1};tick();assert(std::any_of(events.begin(),events.end(),[](Event e){return e.key==K_X360_RIGHT_TRIGGER&&!e.down;}));
 menu=true;nav=.4;edges={33,-33};tick();assert(events.back().key==K_X360_A&&events.back().down);
 tick();assert(events.back().key==K_X360_A&&!events.back().down);
 edges={34,-34};tick();assert(events.back().key==K_X360_B&&events.back().down);tick();assert(events.back().key==K_X360_B&&!events.back().down);
 binds[40]="impulse 10";assert(WrathIOSActionKey(5)==0);
 // Artifact selection is an absolute native right-stick direction, held
 // across no-motion frames and fed to native controller sampler.
 cl.csqc_wantsmousemove=true;menu=false;nav=0;look=8;tick();
 assert(vid_joystate.axis[2]>.99);float pending=wrath_ios_look_yaw;
 tick();assert(vid_joystate.axis[2]>.99);assert(wrath_ios_look_yaw==pending);
 look=-16;tick();assert(vid_joystate.axis[2]<-.99);
 // The visible stick supplies an absolute direction; gyro/relative look
 // must not accumulate into it, and neutral cancellation must clear it.
 artifact=true;artifactX=.4;artifactY=-.8;look=400;tick();
 assert(std::abs(vid_joystate.axis[2]-.4)<.001&&std::abs(vid_joystate.axis[3]-.8)<.001);
 tick();assert(std::abs(vid_joystate.axis[2]-.4)<.001);
 artifactX=artifactY=0;tick();assert(vid_joystate.axis[2]==0&&vid_joystate.axis[3]==0);artifact=false;
 cl.csqc_wantsmousemove=false;look=1;tick();assert(vid_joystate.axis[2]==0);assert(wrath_ios_look_yaw==pending);
 look=4;tick();assert(wrath_ios_look_yaw==pending+4);
 float yaw,pitch;WrathIOSControllerTakeRelativeLook(&yaw,&pitch);assert(yaw==pending+4);assert(wrath_ios_look_yaw==0);
 wrath_ios_look_yaw=15;wrath_ios_look_pitch=6;float beforeYaw=cl.viewangles[YAW];ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-15);assert(cl.viewangles[PITCH]==6);
 wrath_ios_look_yaw=30;ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-45); // doubling slider doubles actual look
 cl.csqc_wantsmousemove=true;wrath_ios_look_yaw=20;ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-45);assert(wrath_ios_look_yaw==0);cl.csqc_wantsmousemove=false;
 SDL_JoystickDetachVirtual(dummy);tick();assert(joy_index.integer==0);assert(VID_ControllerType(joy_index.integer)==CONTROLLER_XBOX);
 puts("PASS: production route, enumerated SDL Xbox, native sampler/query/apply, device-index shift, A press/release, held-fire mouse look");
 WrathIOSControllerShutdown();VID_EnableJoystick(false);assert(SDL_NumJoysticks()==0);
 tick();assert(SDL_NumJoysticks()==1);assert(VID_ControllerType(joy_index.integer)==CONTROLLER_XBOX);
 WrathIOSControllerShutdown();VID_EnableJoystick(false);SDL_Quit();
}'''

with tempfile.TemporaryDirectory() as d:
 src=Path(d)/'test.cpp';src.write_text(p)
 flags=shlex.split(os.environ.get('WRATH_TEST_SDL_FLAGS',''))
 if not flags:
  flags=shlex.split(subprocess.check_output(['sdl2-config','--cflags','--libs'],text=True))
 subprocess.run(['c++','-std=c++20','-Wno-narrowing','-DWRATH_IOS_GATE5C','-I'+str(r/'Gate5C'),str(src),*flags,'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
