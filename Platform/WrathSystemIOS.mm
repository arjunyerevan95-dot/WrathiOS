// SPDX-License-Identifier: GPL-2.0-only

#if WRATH_ENGINE_LINKED

#import <Foundation/Foundation.h>
#import <SDL.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

extern "C" {

int sys_supportsdlgetticks = 1;

void Sys_InitConsole(void) {
}

void Sys_PrintToTerminal(const char *text) {
    if (text == nullptr) {
        return;
    }
    fputs(text, stderr);
    fflush(stderr);
}

void Sys_Shutdown(void) {
    SDL_Quit();
}

__attribute__((noreturn, format(printf, 1, 2)))
void Sys_Error(const char *format, ...) {
    char message[16384];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(message, sizeof(message), format, arguments);
    va_end(arguments);

    fprintf(stderr, "WRATH fatal error: %s\n", message);
    fflush(stderr);
    abort();
}

char *Sys_ConsoleInput(void) {
    return nullptr;
}

char *Sys_GetClipboardData(void) {
    // The engine expects zone-allocated ownership. Clipboard integration belongs
    // in the input milestone, not the static-link diagnostic.
    return nullptr;
}

unsigned int Sys_SDL_GetTicks(void) {
    return SDL_GetTicks();
}

void Sys_SDL_Delay(unsigned int milliseconds) {
    SDL_Delay(milliseconds);
}

} // extern "C"

#endif // WRATH_ENGINE_LINKED
