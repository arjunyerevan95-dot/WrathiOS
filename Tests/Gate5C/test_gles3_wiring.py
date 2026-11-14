from pathlib import Path
r=Path(__file__).resolve().parents[2];d=r/'Derived/wrath-darkplaces-ios'
checks={
 'glquake.h':['#define qglBindFramebuffer WrathGLES3BindFramebuffer','<OpenGLES/ES3/gl.h>'],
 'vid_sdl.c':['void WrathGLES3BindFramebuffer(', 'wm.info.uikit.framebuffer','SDL_GL_CONTEXT_MAJOR_VERSION, 3','vid.support.arb_framebuffer_object = true'],
 'gl_backend.c':['glDrawBuffers(1, &output); glReadBuffer(output);','#if defined(USE_GLES2) && !defined(WRATH_IOS_GLES3)'],
 'gl_textures.c':['GL_RGBA8','GL_DEPTH24_STENCIL8','#ifndef WRATH_IOS_GLES3\n\t\tqglTexParameteri(textureenum, GL_DEPTH_TEXTURE_MODE_ARB'],
 'r_shadow.c':['#ifdef WRATH_IOS_GLES3\n        case RENDERPATH_GLES2:'],
 'gl_rmain.c':['case RENDERPATH_GLES2:\n        r_fb.usedepthtextures = r_usedepthtextures.integer != 0;']}
for file,tokens in checks.items():
 s=(d/file).read_text()
 for token in tokens:assert token in s,(file,token)
# This is source wiring evidence, not GPU completeness/visual testing.
print('GLES3 source wiring checks passed; SDK/GPU testing still required')
