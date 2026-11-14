#pragma once
// Evaluate the actual engine platform header, not just compiler command flags.
#include <TargetConditionals.h>
#include "quakedef.h"
#if defined(WRATH_IOS_ZINK) && defined(USE_GLES2)
#error Zink must compile the desktop GL backend, not GLES wrappers
#endif
#if !defined(WRATH_IOS_ZINK) && !defined(USE_GLES2)
#error GLES rollback must retain the GLES backend
#endif
