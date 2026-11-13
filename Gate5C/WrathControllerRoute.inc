/* Included by pinned vid_sdl.c. Virtual controls join the same Xbox state used
 * by SDL GameController and Windows XInput, before VID_ApplyJoyState.
 * No Cbuf action dispatch, binding writes, or menu-VM state manipulation. */
/* Defined by vid_shared.c, not exported by upstream vid.h. */
extern cvar_t joy_axiskeyevents;
static const int wrath_ios_padkeys[] = {
 K_X360_DPAD_UP,K_X360_DPAD_DOWN,K_X360_DPAD_LEFT,K_X360_DPAD_RIGHT,
 K_X360_START,K_X360_BACK,K_X360_LEFT_THUMB,K_X360_RIGHT_THUMB,
 K_X360_LEFT_SHOULDER,K_X360_RIGHT_SHOULDER,K_X360_A,K_X360_B,
 K_X360_X,K_X360_Y,K_X360_LEFT_TRIGGER,K_X360_RIGHT_TRIGGER,
 K_X360_LEFT_THUMB_DOWN,K_X360_LEFT_THUMB_UP,K_X360_LEFT_THUMB_LEFT,K_X360_LEFT_THUMB_RIGHT,
 K_X360_RIGHT_THUMB_DOWN,K_X360_RIGHT_THUMB_UP,K_X360_RIGHT_THUMB_LEFT,K_X360_RIGHT_THUMB_RIGHT
};
static int wrath_ios_actionkey[34];
static int WrathIOSPadIndex(int key) {
 int i;for(i=0;i<24;i++)if(wrath_ios_padkeys[i]==key)return i;return -1;
}
static int WrathIOSActionKey(int action) {
 char command[128]; const char *raw; size_t n; int i;
 if(action==32)return K_X360_A;
 if(action==33)return K_X360_B;
 if(action==3)return K_X360_START;
 raw=WrathIOSTouchActionCommand(action,1);
 if(!raw||!*raw)return 0;
 n=strcspn(raw,"\r\n");if(n>=sizeof(command))return 0;
 memcpy(command,raw,n);command[n]=0;
 /* Strip the legacy synthetic key ID, not the number in an impulse. */
 if(command[0]=='+'){char *space=strchr(command,' ');if(space)*space=0;}
 for(i=0;i<24;i++){const char *bind=Key_GetBind(wrath_ios_padkeys[i],-1);if(bind&&!strcmp(bind,command))return wrath_ios_padkeys[i];}
 /* Controller-only: surface missing bindings rather than falling back to
  * keyboard or direct commands. Only swipe/gyro uses relative mouse. */
 Con_Printf("WRATH touch action has no loaded controller binding: %s\n",command);
 return 0;
}
static void WrathIOSControllerFrame(vid_joystate_t *joy) {
 int edge,i;float yaw,pitch,side,forward,nx,ny;unsigned buttons;
 WrathIOSTouchBeginControllerFrame();
 while((edge=WrathIOSTouchNextKey())!=0){
  int action=(edge<0?-edge:edge)-1,key;
  if(action<0||action>=34)continue;
  if(edge>0){
   if(wrath_ios_actionkey[action])continue;
   key=WrathIOSActionKey(action);wrath_ios_actionkey[action]=key;
   if(key&&WrathIOSPadIndex(key)<0)Key_Event(key,0,true);
  }else{
   key=wrath_ios_actionkey[action];wrath_ios_actionkey[action]=0;
   if(key&&WrathIOSPadIndex(key)<0)Key_Event(key,0,false);
  }
 }
 /* OR virtual buttons into physical-controller state; shared releases remain
  * held until every owner releases. VID_ApplyJoyState emits genuine paired
  * X360 key events and WRATH's own QC handles profile/save menu semantics. */
 joy->is360=true;
 Cvar_SetValueQuick(&joy_active,1);
 /* The legacy arrow-key compatibility column contains no Xbox keys. */
 if(joy_axiskeyevents.integer)Cvar_SetValueQuick(&joy_axiskeyevents,0);
 for(i=0;i<34;i++){int index=WrathIOSPadIndex(wrath_ios_actionkey[i]);if(index>=0)joy->button[index]=1;}
 WrathIOSTouchFrame(&yaw,&pitch,&side,&forward,&buttons);
 joy->axis[0]=bound(-1,joy->axis[0]+side,1);
 joy->axis[1]=bound(-1,joy->axis[1]+forward,1);
 if(WrathIOSTouchMenuPad(&nx,&ny)){
  joy->axis[2]=bound(-1,joy->axis[2]+nx,1);
  joy->axis[3]=bound(-1,joy->axis[3]+ny,1);
 }
 /* Relative mouse is intentionally independent of held controller Fire/Alt.
  * This is the normal engine mouse route (CSQC/zoom/sensitivity preserved),
  * not a right-stick emulation. WRATH supports concurrent KB/M + controller. */
 if(cl.csqc_wantsmousemove){
  joy->axis[2]=bound(-1,joy->axis[2]+yaw*.08f,1);
  joy->axis[3]=bound(-1,joy->axis[3]-pitch*.08f,1);
 }else{
  in_mouse_x += yaw / 0.05f;
  in_mouse_y += pitch / 0.05f;
 }
}
