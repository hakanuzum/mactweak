// Buttons module: traffic light themes.
//   -[_NSThemeWidgetCell drawWithFrame:inView:]
// buttonID is 25 for close, 26 for minimize, 27 for zoom (measured on macOS 27).
// app/Previews.swift draws the same themes for the settings app; keep them in step.

#include <math.h>

#include "button_themes.h"
#include "internal.h"

typedef struct {
    double r, g, b;
} RGB;

static const RGB kRed = {1.00, 0.373, 0.341}, kYellow = {0.996, 0.737, 0.180}, kGreen = {0.157, 0.784, 0.251};
static const RGB kPastelRed = {0.957, 0.651, 0.627}, kPastelYellow = {0.965, 0.835, 0.557},
                 kPastelGreen = {0.659, 0.867, 0.647};
static const RGB kGraphite = {0.557, 0.557, 0.576}, kInactive = {0.80, 0.80, 0.81}, kBlack = {0, 0, 0},
                 kWhite = {1, 1, 1}, kNearBlack = {0.14, 0.14, 0.15}, kSymbolGray = {0.45, 0.45, 0.47};

enum { BUTTON_CLOSE = 25, BUTTON_MINIMIZE = 26, BUTTON_ZOOM = 27 };

static inline double mid_x(CGRect r) { return r.origin.x + r.size.width / 2; }
static inline double mid_y(CGRect r) { return r.origin.y + r.size.height / 2; }
static inline CGRect inset(CGRect r, double d) {
    return CGRectMake(r.origin.x + d, r.origin.y + d, r.size.width - 2 * d, r.size.height - 2 * d);
}
static inline RGB mix(RGB a, RGB b, double t) {
    return (RGB){a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t};
}
static inline RGB scale(RGB a, double k) { return (RGB){a.r * k, a.g * k, a.b * k}; }

static id color(RGB c, double alpha) {
    return ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
        CLASS("NSColor"), SEL_("colorWithSRGBRed:green:blue:alpha:"), c.r, c.g, c.b, alpha);
}
static id oval_path(CGRect r) {
    return ((id(*)(id, SEL, CGRect))objc_msgSend)(CLASS("NSBezierPath"), SEL_("bezierPathWithOvalInRect:"), r);
}
static id rounded_path(CGRect r, double radius) {
    return ((id(*)(id, SEL, CGRect, double, double))objc_msgSend)(
        CLASS("NSBezierPath"), SEL_("bezierPathWithRoundedRect:xRadius:yRadius:"), r, radius, radius);
}
static void fill(id path, id c) {
    MSG_VOID(c, "setFill");
    MSG_VOID(path, "fill");
}
static void stroke(id path, id c, double width) {
    MSG_VOID(c, "setStroke");
    ((void (*)(id, SEL, double))objc_msgSend)(path, SEL_("setLineWidth:"), width);
    MSG_VOID(path, "stroke");
}
/// Linear gradient inside a path, from `first` at the visual top to `last` at the bottom.
static void fill_vertical(id path, id first, id last, bool flipped) {
    typedef id __attribute__((ns_returns_retained)) (*init_fn)(__attribute__((ns_consumed)) id, SEL, id, id);
    id g = ((init_fn)objc_msgSend)(MSG_ALLOC("NSGradient"), SEL_("initWithStartingColor:endingColor:"), first, last);
    ((void (*)(id, SEL, id, double))objc_msgSend)(g, SEL_("drawInBezierPath:angle:"), path, flipped ? 90.0 : -90.0);
}
static void save_gstate(void) { MSG_VOID(CLASS("NSGraphicsContext"), "saveGraphicsState"); }
static void restore_gstate(void) { MSG_VOID(CLASS("NSGraphicsContext"), "restoreGraphicsState"); }
static void set_glow(id c, double blur) {
    typedef id __attribute__((ns_returns_retained)) (*init_fn)(__attribute__((ns_consumed)) id, SEL);
    id shadow = ((init_fn)objc_msgSend)(MSG_ALLOC("NSShadow"), SEL_("init"));
    ((void (*)(id, SEL, id))objc_msgSend)(shadow, SEL_("setShadowColor:"), c);
    ((void (*)(id, SEL, double))objc_msgSend)(shadow, SEL_("setShadowBlurRadius:"), blur);
    ((void (*)(id, SEL, CGSize))objc_msgSend)(shadow, SEL_("setShadowOffset:"), CGSizeMake(0, 0));
    MSG_VOID(shadow, "set");
}

static void line(id path, double x0, double y0, double x1, double y1) {
    void (*point)(id, SEL, CGPoint) = (void (*)(id, SEL, CGPoint))objc_msgSend;
    point(path, SEL_("moveToPoint:"), CGPointMake(x0, y0));
    point(path, SEL_("lineToPoint:"), CGPointMake(x1, y1));
}

// The ×, − and + shown while hovering (or always, for Symbols).
static void draw_glyph(long button, CGRect r, id c) {
    id path = MSG(CLASS("NSBezierPath"), "bezierPath");
    double cx = mid_x(r), cy = mid_y(r), d = fmin(r.size.width, r.size.height) * 0.24;
    if (button == BUTTON_CLOSE) {
        line(path, cx - d, cy - d, cx + d, cy + d);
        line(path, cx - d, cy + d, cx + d, cy - d);
    } else {
        line(path, cx - d * 1.2, cy, cx + d * 1.2, cy);
        if (button == BUTTON_ZOOM) line(path, cx, cy - d * 1.2, cx, cy + d * 1.2);
    }
    ((void (*)(id, SEL, unsigned long))objc_msgSend)(path, SEL_("setLineCapStyle:"), 1);  // round caps
    stroke(path, c, fmax(1.1, r.size.width * 0.11));
}

// Glossy gel: deeper color at the top, a glow at the bottom, a bright highlight above.
static void draw_aqua(CGRect r, RGB tint, double alpha, bool flipped) {
    id shape = oval_path(r);
    fill_vertical(shape, color(scale(tint, 0.72), alpha), color(mix(tint, kWhite, 0.38), alpha), flipped);
    double w = r.size.width, h = r.size.height;
    CGRect hi = CGRectMake(r.origin.x + w * 0.17, flipped ? r.origin.y + h * 0.05 : r.origin.y + h * 0.50, w * 0.66, h * 0.45);
    fill_vertical(oval_path(hi), color(kWhite, 0.85 * alpha), color(kWhite, 0.08 * alpha), flipped);
    stroke(shape, color(scale(tint, 0.5), 0.7 * alpha), 0.6);
}

// Beveled gray box; close is empty, minimize has lines, zoom an inner box.
static void draw_platinum(long button, CGRect r, double alpha, bool flipped) {
    CGRect box = inset(r, 0.5);
    id shape = rounded_path(box, 1.5);
    fill_vertical(shape, color((RGB){0.97, 0.97, 0.97}, alpha), color((RGB){0.72, 0.72, 0.73}, alpha), flipped);
    stroke(rounded_path(inset(box, 1.1), 0.8), color(kWhite, 0.85 * alpha), 0.7);
    stroke(shape, color((RGB){0.28, 0.28, 0.30}, alpha), 0.9);
    id marks = MSG(CLASS("NSBezierPath"), "bezierPath");
    double w = box.size.width, cx = mid_x(box), cy = mid_y(box);
    if (button == BUTTON_MINIMIZE) {
        for (int i = -1; i <= 1; i++) line(marks, cx - w * 0.28, cy + i * w * 0.16, cx + w * 0.28, cy + i * w * 0.16);
        stroke(marks, color((RGB){0.35, 0.35, 0.37}, alpha), 0.7);
    } else if (button == BUTTON_ZOOM) {
        stroke(rounded_path(CGRectMake(cx - w * 0.22, cy - w * 0.22, w * 0.44, w * 0.44), 0.5),
               color((RGB){0.35, 0.35, 0.37}, alpha), 0.8);
    }
}

// Dark button with a glowing colored rim.
static void draw_neon(CGRect r, RGB tint, double alpha, double size) {
    CGRect ring = inset(r, size * 0.08);
    fill(oval_path(ring), color((RGB){0.10, 0.10, 0.11}, alpha));
    save_gstate();
    set_glow(color(tint, 0.9 * alpha), size * 0.38);
    stroke(oval_path(ring), color(tint, alpha), fmax(1.2, size * 0.11));
    restore_gstate();
}

// Image themes: NSImage per (theme, button, state), made once from the packed PNG bytes.
static __strong id g_images[16][3][4];

static id theme_image(int theme, int button, int state) {
    if (theme < 0 || theme >= mt_image_theme_count || theme >= 16) return nil;
    if (!g_images[theme][button][state]) {
        mt_png p = mt_image_themes[theme][button][state];
        if (!p.data) return nil;
        id data = ((id(*)(id, SEL, const void *, unsigned long, BOOL))objc_msgSend)(
            CLASS("NSData"), SEL_("dataWithBytesNoCopy:length:freeWhenDone:"), p.data, (unsigned long)p.len, NO);
        typedef id __attribute__((ns_returns_retained)) (*init_fn)(__attribute__((ns_consumed)) id, SEL, id);
        g_images[theme][button][state] = ((init_fn)objc_msgSend)(MSG_ALLOC("NSImage"), SEL_("initWithData:"), data);
    }
    return g_images[theme][button][state];
}

static void draw_image(id image, CGRect r, double alpha) {
    ((void (*)(id, SEL, CGRect, CGRect, unsigned long, double, BOOL, id))objc_msgSend)(
        image, SEL_("drawInRect:fromRect:operation:fraction:respectFlipped:hints:"), r, CGRectMake(0, 0, 0, 0),  // not CGRectZero: the core links no frameworks
        2 /* source over */, alpha, YES, nil);
}

static IMP orig_draw;

void mt_buttons_install(void) {
    orig_draw = mt_hook(objc_getClass("_NSThemeWidgetCell"), "drawWithFrame:inView:", ^(id self, CGRect frame, id view) {
        int theme = mt_enabled() ? mt_theme(mt_settings()) : MT_THEME_SYSTEM;
        id window = MSG(view, "window");
        bool active = MSG_BOOL(window, "isKeyWindow") || MSG_BOOL(window, "isMainWindow");
        bool inactive_color = mt_flag(MT_F_INACTIVE_COLOR);
        if (theme == MT_THEME_SYSTEM && (active || !inactive_color)) {
            ((void (*)(id, SEL, CGRect, id))orig_draw)(self, SEL_("drawWithFrame:inView:"), frame, view);
            return;
        }
        if (theme == MT_THEME_SYSTEM) theme = MT_THEME_CLASSIC;  // keep colors in an inactive window

        long button = MSG_LONG(self, "buttonID");
        long interaction = RESPONDS(self, "_bezelInteractionState") ? MSG_LONG(self, "_bezelInteractionState") : 0;
        bool enabled = MSG_BOOL(self, "isEnabled");
        bool colored = enabled && (active || inactive_color);
        bool flipped = MSG_BOOL(view, "isFlipped");

        double size = fmin(frame.size.width, frame.size.height);
        if (theme >= MT_THEME_IMAGE_BASE) {
            int b = button == BUTTON_CLOSE ? 0 : button == BUTTON_MINIMIZE ? 1 : 2;
            int state = interaction >= 2 ? 2 : interaction == 1 ? 1 : colored ? 0 : 3;
            id image = theme_image(theme - MT_THEME_IMAGE_BASE, b, state);
            if (!image) image = theme_image(theme - MT_THEME_IMAGE_BASE, b, 0);
            if (image) {
                CGRect sq = CGRectMake(mid_x(frame) - size / 2, mid_y(frame) - size / 2, size, size);
                draw_image(image, sq, enabled ? 1.0 : 0.45);
                return;
            }
            theme = MT_THEME_CLASSIC;
        }
        if (theme == MT_THEME_DOT) size *= 0.64;
        CGRect r = inset(CGRectMake(mid_x(frame) - size / 2, mid_y(frame) - size / 2, size, size), 0.5);
        if (theme == MT_THEME_CAPSULE) r = CGRectMake(mid_x(frame) - size * 0.5, mid_y(frame) - size * 0.31, size, size * 0.62);

        RGB base = button == BUTTON_CLOSE ? kRed : button == BUTTON_MINIMIZE ? kYellow : kGreen;
        if (theme == MT_THEME_PASTEL)
            base = button == BUTTON_CLOSE ? kPastelRed : button == BUTTON_MINIMIZE ? kPastelYellow : kPastelGreen;
        if (theme == MT_THEME_GRAPHITE) base = kGraphite;
        if (theme == MT_THEME_BLACK) base = kNearBlack;
        if (theme == MT_THEME_SYMBOLS) base = kSymbolGray;
        RGB tint = colored ? base : (theme == MT_THEME_BLACK ? (RGB){0.42, 0.42, 0.44} : kInactive);
        double alpha = enabled ? 1.0 : 0.45;
        if (interaction >= 2) alpha *= 0.75;  // pressed

        switch (theme) {
        case MT_THEME_AQUA: draw_aqua(r, tint, alpha, flipped); break;
        case MT_THEME_PLATINUM: draw_platinum(button, r, colored ? alpha : alpha * 0.6, flipped); break;
        case MT_THEME_NEON: draw_neon(r, tint, alpha, size); break;
        case MT_THEME_RING:
            if (interaction == 0) {
                stroke(oval_path(r), color(tint, alpha), fmax(1.2, size * 0.12));
                break;
            }
            // fallthrough: filled on hover
        default: {
            id shape = theme == MT_THEME_SQUARE    ? rounded_path(r, size * 0.28)
                       : theme == MT_THEME_CAPSULE ? rounded_path(r, r.size.height / 2)
                                                   : oval_path(r);
            if (theme == MT_THEME_BLACK)
                fill_vertical(shape, color(scale(tint, 1.7), alpha), color(tint, alpha), flipped);
            else
                fill(shape, color(tint, alpha));
            stroke(shape, color(kBlack, 0.12), 0.5);
        }
        }

        // Symbols always show their glyph; the others on hover. Dot and Platinum never.
        bool glyph = theme == MT_THEME_SYMBOLS ? enabled : (interaction != 0 && colored);
        if (glyph && theme != MT_THEME_DOT && theme != MT_THEME_PLATINUM) {
            bool light = theme == MT_THEME_GRAPHITE || theme == MT_THEME_BLACK || theme == MT_THEME_SYMBOLS;
            id c = theme == MT_THEME_NEON ? color(tint, 1) : light ? color(kWhite, 0.92) : color(kBlack, 0.55);
            draw_glyph(button, r, c);
        }
    });
}
