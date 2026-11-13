/* Included by pinned vid_sdl.c. Touch registers a real enumerated SDL Xbox
 * controller, then uses the unmodified VID_BuildJoyState polling path.
 * No Cbuf action dispatch, binding writes, or menu-VM state manipulation. */
static SDL_GameController *wrath_ios_controller;
static SDL_Joystick *wrath_ios_joystick;
static SDL_JoystickID wrath_ios_instance = -1;
static void WrathIOSControllerPrepare(void) {
 int i, index = -1;
 if (!wrath_ios_controller) {
  SDL_VirtualJoystickDesc desc;
  memset(&desc, 0, sizeof(desc));
  desc.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
  desc.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
  desc.naxes = 6; desc.nbuttons = 15;
  desc.vendor_id = 0x045e; desc.product_id = 0x028e;
  desc.name = "WRATH Touch Xbox 360";
  desc.axis_mask = (1u << 6) - 1; desc.button_mask = (1u << 15) - 1;
  index = SDL_JoystickAttachVirtualEx(&desc);
  if (index < 0) return;
  wrath_ios_controller = SDL_GameControllerOpen(index);
  if (!wrath_ios_controller) { SDL_JoystickDetachVirtual(index); return; }
  wrath_ios_joystick = SDL_GameControllerGetJoystick(wrath_ios_controller);
  wrath_ios_instance = SDL_JoystickInstanceID(wrath_ios_joystick);
 }
 /* Resolve current device index, never reuse an instance ID as an index. */
 for (i=0;i<SDL_NumJoysticks();i++)
  if (SDL_JoystickGetDeviceInstanceID(i)==wrath_ios_instance) { index=i; break; }
 if (index < 0) return;
 if (!joy_enable.integer) Cvar_SetValueQuick(&joy_enable,1);
 /* Retain a selected physical game controller. A non-controller device at
  * slot zero must not hide the actual touch Xbox from controller_query. */
 if (joy_index.integer < 0 || joy_index.integer >= SDL_NumJoysticks() ||
     !SDL_IsGameController(joy_index.integer)) Cvar_SetValueQuick(&joy_index,index);
}
void VID_BuildJoyState(vid_joystate_t *joystate);

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
static float wrath_ios_look_yaw,wrath_ios_look_pitch;
static float wrath_ios_radial_x,wrath_ios_radial_y;
static int wrath_ios_captured;
void WrathIOSControllerTakeRelativeLook(float *yaw,float *pitch) {
 *yaw=wrath_ios_look_yaw;*pitch=wrath_ios_look_pitch;
 wrath_ios_look_yaw=wrath_ios_look_pitch=0;
}
static void WrathIOSControllerShutdown(void) {
 int i;
 if(wrath_ios_controller) SDL_GameControllerClose(wrath_ios_controller);
 wrath_ios_controller=NULL;wrath_ios_joystick=NULL;
 for(i=0;i<SDL_NumJoysticks();i++)
  if(SDL_JoystickGetDeviceInstanceID(i)==wrath_ios_instance){SDL_JoystickDetachVirtual(i);break;}
 wrath_ios_instance=-1;
 memset(wrath_ios_actionkey,0,sizeof(wrath_ios_actionkey));
 wrath_ios_look_yaw=wrath_ios_look_pitch=wrath_ios_radial_x=wrath_ios_radial_y=0;wrath_ios_captured=0;
}
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
 /* Populate the registered device, not a fabricated vid_joystate_t. */
 if(!wrath_ios_joystick)return;
 if(joy_axiskeyevents.integer)Cvar_SetValueQuick(&joy_axiskeyevents,0);
 {
  static const SDL_GameControllerButton padbuttons[14] = {
   SDL_CONTROLLER_BUTTON_DPAD_UP,SDL_CONTROLLER_BUTTON_DPAD_DOWN,
   SDL_CONTROLLER_BUTTON_DPAD_LEFT,SDL_CONTROLLER_BUTTON_DPAD_RIGHT,
   SDL_CONTROLLER_BUTTON_START,SDL_CONTROLLER_BUTTON_BACK,
   SDL_CONTROLLER_BUTTON_LEFTSTICK,SDL_CONTROLLER_BUTTON_RIGHTSTICK,
   SDL_CONTROLLER_BUTTON_LEFTSHOULDER,SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
   SDL_CONTROLLER_BUTTON_A,SDL_CONTROLLER_BUTTON_B,
   SDL_CONTROLLER_BUTTON_X,SDL_CONTROLLER_BUTTON_Y
  };
  int held[24]={0}; float axes[6]={0,0,0,0,-1,-1};
  vid_joystate_t touch;
  SDL_GameController *physical_controller=vid_sdlcontroller;
  SDL_Joystick *physical_joystick=vid_sdljoystick;
  for(i=0;i<34;i++){int index=WrathIOSPadIndex(wrath_ios_actionkey[i]);if(index>=0)held[index]=1;}
  WrathIOSTouchFrame(&yaw,&pitch,&side,&forward,&buttons);
  axes[0]=side;axes[1]=-forward;
  if(WrathIOSTouchMenuPad(&nx,&ny)){axes[2]=nx;axes[3]=-ny;}
  if(cl.csqc_wantsmousemove){
   /* WRATH radial selects by absolute right-stick direction, not velocity.
    * Hold the accumulated direction between events so the native radial can
    * converge. Both swipe and gyro arrive in angular units here. */
   if(!wrath_ios_captured)wrath_ios_radial_x=wrath_ios_radial_y=0;
   wrath_ios_radial_x+=yaw/8.0f;wrath_ios_radial_y+=pitch/8.0f;
   {float length=sqrtf(wrath_ios_radial_x*wrath_ios_radial_x+wrath_ios_radial_y*wrath_ios_radial_y);
    if(length>1){wrath_ios_radial_x/=length;wrath_ios_radial_y/=length;}}
   axes[2]=wrath_ios_radial_x;axes[3]=wrath_ios_radial_y;
  }else wrath_ios_radial_x=wrath_ios_radial_y=0;
  for(i=0;i<14;i++)SDL_JoystickSetVirtualButton(wrath_ios_joystick,padbuttons[i],held[i]);
  axes[4]=held[14]?1:-1;axes[5]=held[15]?1:-1;
  if(held[16])axes[1]=1;
  if(held[17])axes[1]=-1;
  if(held[18])axes[0]=-1;
  if(held[19])axes[0]=1;
  if(held[20])axes[3]=1;
  if(held[21])axes[3]=-1;
  if(held[22])axes[2]=-1;
  if(held[23])axes[2]=1;
  for(i=0;i<6;i++)SDL_JoystickSetVirtualAxis(wrath_ios_joystick,i,(Sint16)(bound(-1,axes[i],1)*32767));
  SDL_JoystickUpdate();
  /* Read through the actual native engine controller sampler, preserving
   * simultaneous physical-controller input when another device is selected. */
  vid_sdlcontroller=wrath_ios_controller;vid_sdljoystick=wrath_ios_joystick;
  VID_BuildJoyState(&touch);
  vid_sdlcontroller=physical_controller;vid_sdljoystick=physical_joystick;
  if(physical_controller==wrath_ios_controller)*joy=touch;
  else {
   joy->is360=touch.is360;
   for(i=0;i<24;i++)joy->button[i]|=touch.button[i];
   for(i=0;i<4;i++)joy->axis[i]=bound(-1,joy->axis[i]+touch.axis[i],1);
   for(i=4;i<6;i++)if(touch.axis[i]>joy->axis[i])joy->axis[i]=touch.axis[i];
  }
 }
 /* Touch/gyro are relative angles, not an emulated gamepad for aiming.
  * CL_Input applies them at the mouse-look stage before native angle clamps,
  * independent of physical-mouse sensitivity/acceleration/filter settings. */
 if(!cl.csqc_wantsmousemove&&!wrath_ios_captured){
  wrath_ios_look_yaw+=yaw;wrath_ios_look_pitch+=pitch;
 }
 wrath_ios_captured=cl.csqc_wantsmousemove;
}
