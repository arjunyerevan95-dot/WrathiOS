#!/usr/bin/env python3
"""Execute production iOS route and pinned VID_ApplyJoyState with transport stubs."""
from pathlib import Path
import re, subprocess, tempfile, os, shlex, hashlib, json
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
void QCInputAxis(int,float,float);
void CL_VM_InputEvent(int type,float axis,float value){QCInputAxis(type,axis,value);}
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

# Run the pinned game's real axis-consumer branch and radial motion/selection
# arithmetic. The prior fixture stopped at VID_ApplyJoyState with an empty VM
# callback, so it could not detect the modern HUD's capture-free input path.
def block(text,signature):
 a=text.index(signature);b=text.index('{',a);depth=1;i=b+1
 while depth:depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[a:i]
manager=(r/'Vendor/wrath-qc/input_manager.qc').read_text()
hud=(r/'Vendor/wrath-qc/csqc/hud.qc').read_text()
axisbody=block(manager[manager.index('void input_thumbsticks('):],'if (EventType == IE_JOYAXIS)')
radialbody=block(hud[hud.index('radial_prerender ='):],'if (input_mode == IN_MODE_GAMEPAD)')
angles=hud[hud.index('float ang_sep = (360) / 10;'):hud.index('if (radial_selected > 0 && radial_selected <= artifact_icons.length)')]
order=re.search(r'float radial_artifact_order\[\] = \{(.*?)\};',hud,re.S).group(1)
assert 'const float IE_JOYAXIS = 6;' in (r/'Vendor/wrath-qc/dp_keycodes.qc').read_text()
preamble+=r"""
struct QCVector {float a[3]={0,0,0};float &operator[](int i){return a[i];}float operator[](int i)const{return a[i];}};
using vector=QCVector;
static vector operator+(vector a,vector b){return {{a[0]+b[0],a[1]+b[1],a[2]+b[2]}};}
static vector operator-(vector a,vector b){return {{a[0]-b[0],a[1]-b[1],a[2]-b[2]}};}
static vector operator*(vector a,float b){return {{a[0]*b,a[1]*b,a[2]*b}};}
static vector &operator+=(vector &a,vector b){a=a+b;return a;}
static float vlen(vector a){return std::sqrt(a[0]*a[0]+a[1]*a[1]+a[2]*a[2]);}
static vector normalize(vector a){float n=vlen(a);return n>0?a*(1/n):vector{};}
static vector vectoangles(vector a){float yaw=std::atan2(a[1],a[0])*180.f/3.14159265359f;if(yaw<0)yaw+=360;return {{0,yaw,0}};}
enum {IE_JOYAXIS=6,IN_MODE_GAMEPAD=1};
static int input_mode=IN_MODE_GAMEPAD;
static float rmenu=1,clframetime=1.f/60;
static vector thumbstick_look,thumbstick_right,radial_thumbstick,radial_pos;
void QCInputAxis(int EventType,float charx,float scany){
 float autocvar_joy_axisyaw=joy_axisyaw.integer,autocvar_joy_axispitch=joy_axispitch.integer;
 float autocvar_joy_x360_axisyaw=joy_x360_axisyaw.integer,autocvar_joy_x360_axispitch=joy_x360_axispitch.integer;
"""+axisbody+'\n}\n'
preamble+='void QCRadialStep(){\n'+radialbody+'\n}\n'
preamble+='static float radial_artifact_order[]={'+order+'};\n'
preamble+='int QCArtifactChoice(){float radial_dist=vlen(radial_pos),radial_selected=0;\n#define RADIAL_SELECT_THRESHOLD 16\n'+angles+'\nreturn radial_selected>0?(int)radial_artifact_order[(int)radial_selected-1]+1:0;\n}\n'

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
 assert(std::abs(vid_joystate.axis[2]-.4472136)<.001&&std::abs(vid_joystate.axis[3]+.8944272)<.001);
 tick();assert(std::abs(vid_joystate.axis[2]-.4472136)<.001);
 artifactX=artifactY=0;tick();assert(vid_joystate.axis[2]==0&&vid_joystate.axis[3]==0);artifact=false;
 cl.csqc_wantsmousemove=false;look=1;tick();assert(vid_joystate.axis[2]==0);assert(wrath_ios_look_yaw==pending);
 look=4;tick();assert(wrath_ios_look_yaw==pending+4);
 float yaw,pitch;WrathIOSControllerTakeRelativeLook(&yaw,&pitch);assert(yaw==pending+4);assert(wrath_ios_look_yaw==0);
 // Isolate the relative-look case from the preceding real vertical stick input.
 cl.viewangles[PITCH]=0;
 wrath_ios_look_yaw=15;wrath_ios_look_pitch=6;float beforeYaw=cl.viewangles[YAW];ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-15);assert(cl.viewangles[PITCH]==6);
 wrath_ios_look_yaw=30;ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-45); // doubling slider doubles actual look
 cl.csqc_wantsmousemove=true;wrath_ios_look_yaw=20;ApplyTouchLook();assert(cl.viewangles[YAW]==beforeYaw-45);assert(wrath_ios_look_yaw==0);cl.csqc_wantsmousemove=false;
 SDL_JoystickDetachVirtual(dummy);tick();assert(joy_index.integer==0);assert(VID_ControllerType(joy_index.integer)==CONTROLLER_XBOX);
 // Actual modern Artifact HUD: rmenu is open but cursor capture is false.
 // Exercise native SDL sampling -> engine IE_JOYAXIS -> pinned QC look stick
 // -> pinned HUD motion and sector arithmetic, including the 16/20 threshold.
 cl.csqc_wantsmousemove=false;artifact=true;move=.6;look=400;binds[K_X360_RIGHT_TRIGGER]="+attack";edges={1};
 float pendingBeforeArtifact=wrath_ios_look_yaw;
 auto choose=[&](float x,float y,int expected){
  artifactX=x;artifactY=y;radial_pos={};radial_thumbstick={};float oldForward=cl.cmd.forwardmove,oldSide=cl.cmd.sidemove;tick();
  for(int frame=0;frame<20;frame++)QCRadialStep();
  assert(vlen(radial_pos)>19.9f);assert(QCArtifactChoice()==expected);
  assert(wrath_ios_look_yaw==pendingBeforeArtifact);
  assert(cl.cmd.forwardmove-oldForward>.59&&cl.cmd.sidemove-oldSide>.59);assert(vid_joystate.button[15]);
 };
 choose(.2f,0,3); // Modest intentional motion must reach the stock selection radius.
 choose(0,.2f,1);choose(-.2f,0,8);choose(0,-.2f,6);
 // A left-handed/custom profile can put look on 0/1; do not overwrite it.
 joy_x360_axisyaw.integer=0;joy_x360_axispitch.integer=1;
 joy_x360_axisside.integer=2;joy_x360_axisforward.integer=3;
 choose(.2f,0,3);choose(0,.2f,1);
 artifactX=artifactY=0;tick();assert(thumbstick_look[0]==0&&thumbstick_look[1]==0);
 artifact=false;edges={-1};tick();assert(wrath_ios_look_yaw==pendingBeforeArtifact);
 joy_x360_axisyaw.integer=2;joy_x360_axispitch.integer=3;
 joy_x360_axisside.integer=0;joy_x360_axisforward.integer=1;
 puts("PASS: capture-free Artifact hold reaches stock QC radial: Right=3 Up=1 Left=8 Down=6; swapped look axes, neutral cancel, no gyro leakage and simultaneous movement preserved");
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
out=r/'Artifacts/artifact-route';out.mkdir(parents=True,exist_ok=True)
(out/'validation.json').write_text(json.dumps({
 'passed':True,'cursor_capture':False,'default_look_axes':[2,3],'swapped_look_axes':[0,1],
 'stock_qc_slots':{'right':3,'up':1,'left':8,'down':6},
 'actual_qc_axis_body_sha256':hashlib.sha256(axisbody.encode()).hexdigest(),
 'actual_qc_radial_body_sha256':hashlib.sha256(radialbody.encode()).hexdigest(),
 'scope':'Production SDL route/sampler and VID_ApplyJoyState into pinned QC consumer/radial source. No retail VM, phone or performance claim.'},indent=2)+'\n')
