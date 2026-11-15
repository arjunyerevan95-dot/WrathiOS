#pragma once
/* OpenGL ES 3 copy source must be single sampled. SDL exposes both its draw
 * and resolve FBOs. Restore both bindings so the engine's state cache is valid. */
static inline void WrathGLES3CopyResolvedToTexture(GLenum target, GLint level,
    GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height,
    GLuint screen, GLuint resolve, int drawableWidth, int drawableHeight) {
    GLint previousRead = 0, previousDraw = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead);
    const int needsResolve = resolve != 0 && (GLuint)previousRead == screen;
    if (needsResolve) {
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousDraw);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, resolve);
        glBlitFramebuffer(0, 0, drawableWidth, drawableHeight,
                          0, 0, drawableWidth, drawableHeight,
                          GL_COLOR_BUFFER_BIT, GL_NEAREST);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, resolve);
    }
    glCopyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height);
    if (needsResolve) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previousRead);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)previousDraw);
    }
}
