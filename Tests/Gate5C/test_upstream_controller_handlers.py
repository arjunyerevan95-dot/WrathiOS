#!/usr/bin/env python3
"""Execute pinned QC handler bodies as C++ with narrow syntax adaptation.

NOT an engine/UI integration test. Geometry, VM dispatch, SDL transport, save
parsing/loading and the rendering tail of profile_click are outside this test.
Profile selection/version logic is real; available slots are supplied as fixtures.
"""
from pathlib import Path
import re, subprocess, tempfile, hashlib, os
ROOT = Path(__file__).resolve().parents[2]
qc = ROOT / "Vendor/wrath-qc"
menu = (qc / "menuqc/menu.qc").read_text()
inputs = (qc / "input_manager.qc").read_text()

def body(text, marker):
    start = text.index("{", text.index(marker))
    depth = 1
    i = start + 1
    while depth:
        depth += (text[i] == "{") - (text[i] == "}")
        i += 1
    return text[start+1:i-1]

def adapt(s):
    # QC entity fields become reference-wrapper fields in the fixture.
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"\bthis\b", "self", s)
    s = s.replace("profile_loadimage.length", "3")
    s = s.replace("for(float i", "for(int i")
    s = s.replace("uitext_c slot", "Element &slot")
    s = s.replace("uipicture_c page", "Element &page")
    s = s.replace("profile_button_selected.button_index", "profile_button_selected->button_index")
    s = s.replace("profile_button_selected.text", "profile_button_selected->text")
    s = s.replace("profile_button_selected = self", "profile_button_selected = &self")
    return s

thumb = body(inputs, "void input_thumbsticks(")
profile = body(menu, "void(uitext_c this) profile_click =")
# Exact selection and incompatible-version guard. Deliberately stop before
# metadata/file/render work: no substitute rendering implementation is tested.
prefix = profile[:profile.index("\n\t\tcheckdates(this.text);")]
handlers = {
    "void select_profile(Element &self)": prefix,
    "void select_save(Element &self)": body(menu, "void(uielement_c this) saveslot_click ="),
    "bool can_load(Element &self)": body(menu, "float(uielement_c this) load_conditional ="),
    "void click_load(Element &self)": body(menu, "void(uielement_c this) load_click ="),
}
source = r"""
#include <cassert>
#include <cstring>
#include <string>
#include <iostream>
enum {IE_KEYDOWN=0, IE_KEYUP=1, IE_JOYAXIS=6, IN_MODE_GAMEPAD=2,
 K_XIN_TRIGGER_RIGHT=100, K_XIN_TRIGGER_LEFT, K_XIN_BTN_A, K_XIN_BTN_B,
 K_XIN_START, K_MOUSE1=200, K_MOUSE2, K_ESCAPE};
namespace UIFLAG { constexpr int HIDE=1; }
constexpr bool FALSE=false, TRUE=true;
struct Element { int button_index=0,flags=0; const char *text=""; };
Element profile_loadimage[3],profile_loadbutton[3],menu_loadprofile_warning;
Element *profile_button_selected=nullptr;
int save_selected=-1,profile_selected=-1,profileslot=0,profilemenuversion=1,menuversion=1;
const char *profilename="";
std::string written_name,load_kind;
int written_slot=0,sounds=0;
void Journal_Sound(){sounds++;}
void check_profilemenuversion_byname(const char*){}
void write_currentprofileslot_byname(const char* name,int slot){written_name=name;written_slot=slot;}
void load_tether(){load_kind="tether";}
void load_shrine(){load_kind="shrine";}
void load_autosave(){load_kind="autosave";}
int input_mode=IN_MODE_GAMEPAD,ui_usemouse=1;
float autocvar_joy_x360_axispitch=3,autocvar_joy_x360_axisyaw=2;
float autocvar_joy_axispitch=3,autocvar_joy_axisyaw=2;
float thumbstick_look[2]={},thumbstick_right[2]={};
"""
source += "\nvoid input_thumbsticks(float &EventType,float &charx,float &scany) {"+thumb+"}\n"
for sig, code in handlers.items():
    source += sig+" {"+adapt(code)+"}\n"
source += r"""
int main(){
 // Paired DOWN/UP stay paired under the actual upstream remapper.
 for(int key: {K_XIN_BTN_A,K_XIN_TRIGGER_RIGHT,K_XIN_TRIGGER_LEFT,K_XIN_BTN_B,K_XIN_START}) {
   float down=IE_KEYDOWN,up=IE_KEYUP,a=key,b=key,scan=0;
   input_thumbsticks(down,a,scan); input_thumbsticks(up,b,scan);
   assert(down==IE_KEYDOWN && up==IE_KEYUP && a==b);
   assert(a==(key==K_XIN_TRIGGER_LEFT?K_MOUSE2:
     key==K_XIN_BTN_B||key==K_XIN_START?K_ESCAPE:K_MOUSE1));
 }
 // No remapping in gameplay/non-gamepad contexts.
 for(int mode: {0,int(IN_MODE_GAMEPAD)}) {
   input_mode=mode; ui_usemouse=(mode==0);
   float type=IE_KEYDOWN,key=K_XIN_BTN_A,s=0;
   input_thumbsticks(type,key,s); assert(key==K_XIN_BTN_A);
 }
 input_mode=IN_MODE_GAMEPAD;ui_usemouse=1;
 float t=IE_JOYAXIS,axis=2,value=.75f;
 input_thumbsticks(t,axis,value); assert(thumbstick_right[0]==.75f);
 axis=3;value=-.5f;input_thumbsticks(t,axis,value);
 assert(thumbstick_right[1]==.5f);
 Element alice{4,0,"fixture-alice"},bob{7,0,"fixture-bob"},dummy;
 for(int slot=0;slot<3;slot++){
   select_profile(alice);
   assert(profile_button_selected==&alice && profile_selected==4);
   assert(std::string(profilename)=="fixture-alice" && save_selected==-1);
   assert(!can_load(dummy)); // selection alone cannot enable Load
   // Fixture boundary: available save slots, not filesystem/parser emulation.
   profile_loadbutton[slot].flags=0;profile_loadbutton[slot].button_index=slot;
   select_save(profile_loadbutton[slot]);assert(can_load(dummy));
   click_load(dummy);
   assert(written_name=="fixture-alice" && written_slot==5);
   assert(load_kind==(slot==0?"autosave":slot==1?"tether":"shrine"));
   profile_loadbutton[slot].flags=UIFLAG::HIDE;assert(!can_load(dummy));
 }
 select_profile(bob);assert(save_selected==-1 && profile_button_selected==&bob);
 assert(!can_load(dummy)); // old profile's selected slot must not leak
 profilemenuversion=2;select_profile(alice);
 assert(!(menu_loadprofile_warning.flags&UIFLAG::HIDE));
 for(int i=0;i<3;i++)assert(profile_loadbutton[i].flags&UIFLAG::HIDE);
 assert(!can_load(dummy));
 Element blank{1,0," "};select_profile(blank);
 assert(profile_button_selected==&alice);
 profile_button_selected=nullptr;load_kind="";click_load(dummy);assert(load_kind.empty());
 std::cout<<"PASS: upstream controller pair/axes; profile selection/version guard; "
             "save selection/gating; all three Load dispatches. Not a UI/engine test.\n";
}
"""
with tempfile.TemporaryDirectory(prefix="wrath-qc-handlers-") as td:
    cpp=Path(td)/"handlers.cpp";binary=Path(td)/"handlers"
    cpp.write_text(source)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++17","-Wall","-Wextra",str(cpp),"-o",str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
print("Extracted QC SHA256:",hashlib.sha256((inputs+menu).encode()).hexdigest())
