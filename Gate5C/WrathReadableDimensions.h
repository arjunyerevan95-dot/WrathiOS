#pragma once
/* Engine coordinates, not UIKit points. Retain custom/opted-out dimensions. */
typedef struct { float width, height; } WrathReadableDimensions;
static inline WrathReadableDimensions WrathReadableUI(int sceneWidth, int sceneHeight,
                                                     float conWidth, float conHeight, int enabled) {
    WrathReadableDimensions r = {conWidth, conHeight};
    if (enabled && sceneWidth > 0 && sceneHeight > 0 &&
        conWidth == sceneWidth / 2 && conHeight == sceneHeight / 2) {
        r.width = sceneWidth / 4.0f; r.height = sceneHeight / 4.0f;
    }
    return r;
}
