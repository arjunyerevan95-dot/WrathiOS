#pragma once
// Commands audited against pinned WRATH menu.qc controllerdiagram_validcontrols.
namespace wrathios::touch {
struct Action {const char *label,*down,*up;};
inline constexpr Action Actions[]={
 {"FIRE","+attack 700\n","-attack 700\n"},
 {"JUMP","+jump 701\n","-jump 701\n"},
 {"ALT","+button3 702\n","-button3 702\n"},
 {"MENU","",""},
 {"CROUCH","+button4 704\n","-button4 704\n"},
 {"USE","+button5 705\n","-button5 705\n"},
 {"ACTIONS","",""},
 {"ZOOM","+zoom 707\n","-zoom 707\n"},
 {"WALK","+button7 708\n","-button7 708\n"},
 {"SWIM UP","+moveup 709\n","-moveup 709\n"},
 {"SWIM DN","+movedown 710\n","-movedown 710\n"},
 {"INVENTORY","+button6 711\n","-button6 711\n"},
 {"BLADE","impulse 1\n",""},
 {"REVOLVER","impulse 2\n",""},
 {"SHOTGUN","impulse 3\n",""},
 {"SPITTER","impulse 4\n",""},
 {"RETCHER","impulse 5\n",""},
 {"SLAG","impulse 6\n",""},
 {"LANCE","impulse 7\n",""},
 {"BOILER","impulse 8\n",""},
 {"MACE","impulse 9\n",""},
 {"NEXT WEP","impulse 55\n",""},
 {"PREV WEP","impulse 56\n",""},
 {"LAST WEP","impulse 57\n",""},
 {"PREV ART","impulse 16\n",""},
 {"NEXT ART","impulse 17\n",""},
 {"USE ART","impulse 15\n",""},
 {"TETHER","impulse 81\n",""},
 {"JOURNAL","impulse 35\n",""},
 {"LOAD","impulse 89\n",""},
 {"ZOOM TOG","togglezoom\n",""},
 {"SETTINGS","",""},
};
inline constexpr int ActionCount=sizeof(Actions)/sizeof(Actions[0]);
}
