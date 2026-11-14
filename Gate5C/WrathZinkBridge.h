#pragma once
#include <SDL.h>
#ifdef __cplusplus
extern "C" {
#endif
SDL_Window *WrathZinkCreateWindow(const char*,int,int,int,int,Uint32);
void WrathZinkDestroyWindow(SDL_Window*);
SDL_GLContext WrathZinkCreateContext(SDL_Window*);
void *WrathZinkGetProcAddress(const char*);
void WrathZinkSwapWindow(SDL_Window*);
int WrathZinkLoadLibrary(const char*);
int WrathZinkSetAttribute(SDL_GLattr,int);
int WrathZinkGetAttribute(SDL_GLattr,int*);
int WrathZinkSetSwapInterval(int);
void WrathZinkDrain(void);
void WrathZinkGetDrawableSize(SDL_Window*,int*,int*);
#ifdef __cplusplus
}
#endif
#if defined(WRATH_IOS_ZINK) && !defined(WRATH_ZINK_IMPL)
#define SDL_DestroyWindow WrathZinkDestroyWindow
#define SDL_CreateWindow WrathZinkCreateWindow
#define SDL_GL_GetDrawableSize WrathZinkGetDrawableSize
#define SDL_GL_CreateContext WrathZinkCreateContext
#define SDL_GL_GetProcAddress WrathZinkGetProcAddress
#define SDL_GL_SwapWindow WrathZinkSwapWindow
#define SDL_GL_LoadLibrary WrathZinkLoadLibrary
#define SDL_GL_SetAttribute WrathZinkSetAttribute
#define SDL_GL_GetAttribute WrathZinkGetAttribute
#define SDL_GL_SetSwapInterval WrathZinkSetSwapInterval
#endif
