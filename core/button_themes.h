// Image-based button themes, packed into the core at build time
// (tools/pack_button_themes.swift writes the matching .c file).
#ifndef MT_BUTTON_THEMES_H
#define MT_BUTTON_THEMES_H

typedef struct {
    const unsigned char *data;  // PNG bytes, NULL if missing
    unsigned int len;
} mt_png;

// [theme][button: close, minimize, zoom][state: normal, hover, pressed, inactive]
extern const mt_png mt_image_themes[][3][4];
extern const int mt_image_theme_count;

#endif
