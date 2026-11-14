# WRATH v21: initialize the desktop GL loader before symbol lookup

The v20 device screenshot reports a controlled Video modes failed error after Video subsystem initialized. Inspection of the pinned desktop VID_InitMode path shows it calls SDL_GL_LoadLibrary, resolves glGetString, and only then creates a window/context. Our bridge returned success from LoadLibrary without initializing OSMesa; GetProc returned null until CreateContext. The mode therefore could not reach context creation.

LoadLibrary now ensures OSMesa is loaded and its entry points resolved. GetProc safely ensures the same initialization, and CreateContext reuses it. Loader failures propagate rather than reporting false success. No GL/GLSL version overrides or backend capability bypasses were added.

The new regression test checks the real engine ordering and compiles the actual production load/proc function bodies against deterministic loader stubs, covering early symbol resolution, lazy initialization and load failure. Actual iOS build and device launch remain distinct gates. GLES rollback and private data are preserved.
