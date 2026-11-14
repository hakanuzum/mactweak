// Buttons module: traffic light themes.
//   -[_NSThemeWidgetCell drawWithFrame:inView:]
// buttonID is 25 for close, 26 for minimize, 27 for zoom (measured on macOS 27).

#include <math.h>

#include "internal.h"

typedef struct {
    double r, g, b;
} RGB;

static const RGB kRed = {1.00, 0.373, 0.341}, kYellow = {0.996, 0.737, 0.180}, kGreen = {0.157, 0.784, 0.251};
static const RGB kPastelRed = {0.957, 0.651, 0.627}, kPastelYellow = {0.965, 0.835, 0.557},
                 kPastelGreen = {0.659, 0.867, 0.647};
static const RGB kGraphite = {0.557, 0.557, 0.576}, kInactive = {0.80, 0.80, 0.81}, kBlack = {0, 0, 0},
                 kWhite = {1, 1, 1};

enum { BUTTON_CLOSE = 25, BUTTON_MINIMIZE = 26, BUTTON_ZOOM = 27 };

static inline double mid_x(CGRect r) { return r.origin.x + r.size.width / 2; }
static inline double mid_y(CGRect r) { return r.origin.y + r.size.height / 2; }
static inline CGRect inset(CGRect r, double d) {
    return CGRectMake(r.origin.x + d, r.origin.y + d, r.size.width - 2 * d, r.size.height - 2 * d);
}

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

// The ×, − and + shown while hovering.
static void draw_glyph(long button, CGRect r, id c) {
    id path = MSG(CLASS("NSBezierPath"), "bezierPath");
    double cx = mid_x(r), cy = mid_y(r), d = r.size.width * 0.24;
    void (*move)(id, SEL, CGPoint) = (void (*)(id, SEL, CGPoint))objc_msgSend;
    SEL moveTo = SEL_("moveToPoint:"), lineTo = SEL_("lineToPoint:");
    if (button == BUTTON_CLOSE) {
        move(path, moveTo, CGPointMake(cx - d, cy - d));
        move(path, lineTo, CGPointMake(cx + d, cy + d));
        move(path, moveTo, CGPointMake(cx - d, cy + d));
        move(path, lineTo, CGPointMake(cx + d, cy - d));
    } else {
        move(path, moveTo, CGPointMake(cx - d * 1.2, cy));
        move(path, lineTo, CGPointMake(cx + d * 1.2, cy));
        if (button == BUTTON_ZOOM) {
            move(path, moveTo, CGPointMake(cx, cy - d * 1.2));
            move(path, lineTo, CGPointMake(cx, cy + d * 1.2));
        }
    }
    ((void (*)(id, SEL, unsigned long))objc_msgSend)(path, SEL_("setLineCapStyle:"), 1);  // round caps
    stroke(path, c, fmax(1.1, r.size.width * 0.11));
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

        double size = fmin(frame.size.width, frame.size.height);
        if (theme == MT_THEME_DOT) size *= 0.64;
        CGRect r = inset(CGRectMake(mid_x(frame) - size / 2, mid_y(frame) - size / 2, size, size), 0.5);

        RGB base = button == BUTTON_CLOSE ? kRed : button == BUTTON_MINIMIZE ? kYellow : kGreen;
        if (theme == MT_THEME_PASTEL)
            base = button == BUTTON_CLOSE ? kPastelRed : button == BUTTON_MINIMIZE ? kPastelYellow : kPastelGreen;
        if (theme == MT_THEME_GRAPHITE) base = kGraphite;
        RGB tint = colored ? base : kInactive;
        double alpha = enabled ? 1.0 : 0.45;
        if (interaction >= 2) alpha *= 0.75;  // pressed

        id shape = theme == MT_THEME_SQUARE ? rounded_path(r, size * 0.28) : oval_path(r);
        if (theme == MT_THEME_RING && interaction == 0) {
            stroke(shape, color(tint, alpha), fmax(1.2, size * 0.12));
        } else {
            fill(shape, color(tint, alpha));
            stroke(shape, color(kBlack, 0.12), 0.5);
        }
        if (interaction != 0 && colored && theme != MT_THEME_DOT)
            draw_glyph(button, r, theme == MT_THEME_GRAPHITE ? color(kWhite, 0.9) : color(kBlack, 0.55));
    });
}
