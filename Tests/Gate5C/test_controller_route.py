#!/usr/bin/env python3
"""Execute production iOS route and pinned VID_ApplyJoyState with transport stubs."""
from pathlib import Path
import re, subprocess, tempfile
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
void Con_Printf(const char *,const char*){}
'''
preamble+='enum {'+','.join(k+'='+str(i+100) for i,k in enumerate(keys))+'};\n'
preamble+='static cvar '+','.join(cvars)+';\n'
preamble+='''static std::deque<int> edges;static unsigned long long consumed;
void WrathIOSTouchBeginControllerFrame(){consumed=0;}
int WrathIOSTouchNextKey(){if(edges.empty())return 0;int e=edges.front();auto b=1ULL<<(abs(e)-1);if(consumed&b)return 0;consumed|=b;edges.pop_front();return e;}
static float look=0,move=0,nav=0;static bool menu=false;
void WrathIOSTouchFrame(float*y,float*p,float*s,float*f,unsigned*b){*y=look;*p=0;*s=move;*f=move;*b=0;look=0;}
int WrathIOSTouchMenuPad(float*x,float*y){*x=nav;*y=0;return menu;}
static std::string binds[1000];
const char *Key_GetBind(int key,int){return binds[key].c_str();}
void Key_FindKeysForCommand(const char*c,int*k,int n,int){std::fill(k,k+n,-1);for(int i=0,j=0;i<1000&&j<n;i++)if(binds[i]==c)k[j++]=i;}
'''
preamble+='#include "WrathTouchActions.hpp"\nconst char *WrathIOSTouchActionCommand(int a,int){return wrathios::touch::Actions[a].down;}\n'
main='''int main(){
 joy_x360_axisside.integer=0;joy_x360_axisforward.integer=1;joy_x360_axisyaw.integer=2;joy_x360_axispitch.integer=3;joy_x360_axisup.integer=-1;
 joy_x360_deadzoneside.value=joy_x360_deadzoneforward.value=joy_x360_deadzoneyaw.value=joy_x360_deadzonepitch.value=0;
 binds[K_X360_RIGHT_TRIGGER]="+attack";binds[K_X360_A]="+jump";
 auto tick=[](){vid_joystate_t j;WrathIOSControllerFrame(&j);VID_ApplyJoyState(&j);realtime+=.016;};
 joy_axiskeyevents.integer=1; // imported legacy config must not suppress Xbox buttons
 edges={1};look=2;move=.7;tick();assert(joy_axiskeyevents.integer==0);
 assert(events.back().key==K_X360_RIGHT_TRIGGER&&events.back().down);assert(in_mouse_x==40);assert(cl.cmd.forwardmove>.6&&cl.cmd.sidemove>.6);
 look=3;tick();assert(in_mouse_x==100); // aim continues while trigger held
 binds[K_X360_RIGHT_TRIGGER]="+button3"; // remap during hold cannot strand old key
 edges={-1};tick();assert(events.back().key==K_X360_RIGHT_TRIGGER&&!events.back().down);
 menu=true;nav=.4;edges={33,-33};tick();assert(events.back().key==K_X360_A&&events.back().down);assert(vid_joystate.axis[2]>.3);
 tick();assert(events.back().key==K_X360_A&&!events.back().down); // quick tap preserved across frames
 edges={34,-34};tick();assert(events.back().key==K_X360_B&&events.back().down);tick();assert(events.back().key==K_X360_B&&!events.back().down);
 // Fire + distinct look pointer + movement survive; no Cbuf, no profile writes.
 puts("production route + pinned VID_ApplyJoyState: controller pairs, held-fire look, movement, remap-release PASS");
}'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'test.cpp';p.write_text(preamble+function('VID_JoyState_GetAxis')+'\n'+function('VID_KeyEventForButton')+'\n'+apply+'\n'+route+'\n'+main)
 subprocess.run(['c++','-std=c++20','-Wall','-Wextra','-Werror','-I'+str(r/'Gate5C'),str(p),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
