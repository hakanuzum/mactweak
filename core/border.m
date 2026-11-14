// Border module: a colored border around windows, fading of inactive windows,
// and window shadows. Updated when a window is ordered on screen and when the
// key window changes:
//   -[NSWindow orderWindow:relativeTo:], -[NSWindow becomeKeyWindow], -[NSWindow resignKeyWindow]
// The border is the window frame view's own layer border: a CALayer draws its
// border above its sublayers, so it covers the whole window without adding a
// view. (An earlier version put a border view on top of the frame; AppKit then
// laid out SwiftUI toolbars differently and the tab capsule of Settings windows
// grew taller.) The frame view gets its layer when the window first draws, so a
// window without one is retried shortly after. Only values this module changed
// are put back (border, alpha, shadow), never an app's own settings.
//
// The window server draws a rim with the shadow: a dark line outside the window
// and, with Increase Contrast, a white line about 2 pt wide just inside it.
// AppKit sends their strength with the shadow in -[NSWindow shadowParameters];
// the user's outline and shadow settings scale those values. The inner line
// covers half of a 2 pt border, so it is always off under our border.

#include <stdio.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>

#include "internal.h"

static char kBorderOn, kSavedRadius, kRetried, kDimmed, kShadowOff, kShadowParts;

static bool flag(id w, const void *key) { return objc_getAssociatedObject(w, key) != nil; }
static void set_flag(id w, const void *key, bool on) {
    // +[NSNumber new] is nil (class cluster), so store a real number.
    id yes = ((id(*)(id, SEL, BOOL))objc_msgSend)(CLASS("NSNumber"), SEL_("numberWithBool:"), YES);
    objc_setAssociatedObject(w, key, on ? yes : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id nsstring(const char *s) {
    return ((id(*)(id, SEL, const char *))objc_msgSend)(CLASS("NSString"), SEL_("stringWithUTF8String:"), s);
}

static double get_double(id o, const char *sel) { return ((double (*)(id, SEL))objc_msgSend)(o, SEL_(sel)); }
static void set_double(id o, const char *sel, double v) { ((void (*)(id, SEL, double))objc_msgSend)(o, SEL_(sel), v); }

static void without_animation(void (^block)(void)) {
    id tx = CLASS("CATransaction");
    MSG_VOID(tx, "begin");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(tx, SEL_("setDisableActions:"), YES);
    block();
    MSG_VOID(tx, "commit");
}

void mt_border_update(id w) {
    if (!w) return;
    unsigned long mask = (unsigned long)MSG_LONG(w, "styleMask");
    bool titled = mask & 1, fullscreen = mask & (1UL << 14);
    uint64_t b = (titled && !fullscreen) ? mt_border() : 0;
    bool key = MSG_BOOL(w, "isKeyWindow");

    // Border
    id frame = MSG(MSG(w, "contentView"), "superview");
    id layer = MSG(frame, "layer");
    bool show = frame && (b & MT_B_ENABLED) && mt_border_width(b) > 0 && (key || !(b & MT_B_ACTIVE_ONLY));
    if (getenv("MACTWEAK_LOG"))
        fprintf(stderr, "[mactweak] border: state=0x%llx key=%d show=%d layer=%d\n", b, key, show, layer != nil);
    if (show && !layer && !flag(w, &kRetried)) {
        set_flag(w, &kRetried, true);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            mt_border_update(w);
        });
    }
    if (layer && (show || flag(w, &kBorderOn))) {
        without_animation(^{
            if (show) {
                double radius = RESPONDS(w, "_cornerRadius") ? get_double(w, "_cornerRadius") : 0;
                if (!objc_getAssociatedObject(w, &kSavedRadius))
                    objc_setAssociatedObject(w, &kSavedRadius,
                                             ((id(*)(id, SEL, double))objc_msgSend)(CLASS("NSNumber"), SEL_("numberWithDouble:"),
                                                                                    get_double(layer, "cornerRadius")),
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                set_double(layer, "setCornerRadius:", radius);
                set_double(layer, "setBorderWidth:", mt_border_width(b));
                id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
                    CLASS("NSColor"), SEL_("colorWithSRGBRed:green:blue:alpha:"), (double)(b & 0xFF) / 255.0,
                    (double)((b >> 8) & 0xFF) / 255.0, (double)((b >> 16) & 0xFF) / 255.0, (double)((b >> 24) & 0xFF) / 255.0);
                ((void (*)(id, SEL, void *))objc_msgSend)(layer, SEL_("setBorderColor:"),
                                                         ((void *(*)(id, SEL))objc_msgSend)(color, SEL_("CGColor")));
                set_flag(w, &kBorderOn, true);
            } else {
                set_double(layer, "setBorderWidth:", 0);
                ((void (*)(id, SEL, void *))objc_msgSend)(layer, SEL_("setBorderColor:"), NULL);
                id saved = objc_getAssociatedObject(w, &kSavedRadius);
                if (saved) set_double(layer, "setCornerRadius:", get_double(saved, "doubleValue"));
                objc_setAssociatedObject(w, &kSavedRadius, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                set_flag(w, &kBorderOn, false);
            }
        });
    }

    // Outline and shadow: the parts the window server should use for this window.
    uint64_t o = (titled && !fullscreen) ? mt_outline() : 0;
    uint64_t parts = o ? (o & 0xFFFFFFFFULL) : MT_OUTLINE_DEFAULT;
    if (show) parts &= ~(0xFFULL << (8 * MT_O_INNER));  // inner line off under our border
    id stored = objc_getAssociatedObject(w, &kShadowParts);
    uint64_t old = stored ? ((unsigned long long (*)(id, SEL))objc_msgSend)(stored, SEL_("unsignedLongLongValue")) : MT_OUTLINE_DEFAULT;
    if (parts != old) {
        id num = parts == MT_OUTLINE_DEFAULT ? nil
                     : ((id(*)(id, SEL, unsigned long long))objc_msgSend)(CLASS("NSNumber"), SEL_("numberWithUnsignedLongLong:"), parts);
        objc_setAssociatedObject(w, &kShadowParts, num, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (RESPONDS(w, "_setShadowParameters")) MSG_VOID(w, "_setShadowParameters");
        MSG_VOID(w, "invalidateShadow");
    }

    // Background window opacity
    int opacity = mt_inactive_opacity(b);
    bool dim = titled && !fullscreen && !key && opacity > 0 && opacity < 100;
    if (dim) {
        ((void (*)(id, SEL, double))objc_msgSend)(w, SEL_("setAlphaValue:"), opacity / 100.0);
        set_flag(w, &kDimmed, true);
    } else if (flag(w, &kDimmed)) {
        ((void (*)(id, SEL, double))objc_msgSend)(w, SEL_("setAlphaValue:"), 1.0);
        set_flag(w, &kDimmed, false);
    }

    // Shadow
    if (b & MT_B_NO_SHADOW) {
        if (MSG_BOOL(w, "hasShadow")) {
            MSG_SET_BOOL(w, "setHasShadow:", NO);
            set_flag(w, &kShadowOff, true);
        }
    } else if (flag(w, &kShadowOff)) {
        MSG_SET_BOOL(w, "setHasShadow:", YES);
        set_flag(w, &kShadowOff, false);
    }
}

static IMP orig_become_key, orig_resign_key, orig_order, orig_shadow_params;

void mt_border_install(void) {
    Class window = objc_getClass("NSWindow");
    orig_become_key = mt_hook(window, "becomeKeyWindow", ^(id self) {
        ((void (*)(id, SEL))orig_become_key)(self, SEL_("becomeKeyWindow"));
        mt_border_update(self);
    });
    orig_resign_key = mt_hook(window, "resignKeyWindow", ^(id self) {
        ((void (*)(id, SEL))orig_resign_key)(self, SEL_("resignKeyWindow"));
        mt_border_update(self);
    });
    orig_shadow_params = mt_hook(window, "shadowParameters", ^id(id self) {
        id params = ((id(*)(id, SEL))orig_shadow_params)(self, SEL_("shadowParameters"));
        id stored = objc_getAssociatedObject(self, &kShadowParts);
        if (!params || !stored) return params;
        uint64_t parts = ((unsigned long long (*)(id, SEL))objc_msgSend)(stored, SEL_("unsignedLongLongValue"));
        static const struct { const char *key; int part; bool density; } kKeys[] = {
            {"com.apple.WindowShadowRimDensityActive", MT_O_OUTER, true},
            {"com.apple.WindowShadowRimDensityInactive", MT_O_OUTER, true},
            {"com.apple.WindowShadowInnerRimDensityActive", MT_O_INNER, true},
            {"com.apple.WindowShadowInnerRimDensityInactive", MT_O_INNER, true},
            {"com.apple.WindowShadowDensityActive", MT_O_STRENGTH, true},
            {"com.apple.WindowShadowDensityInactive", MT_O_STRENGTH, true},
            {"com.apple.WindowShadowRadiusActive", MT_O_SIZE, false},
            {"com.apple.WindowShadowRadiusInactive", MT_O_SIZE, false},
            {"com.apple.WindowShadowVerticalOffsetActive", MT_O_SIZE, false},
            {"com.apple.WindowShadowVerticalOffsetInactive", MT_O_SIZE, false},
        };
        typedef id __attribute__((ns_returns_retained)) (*copy_fn)(id, SEL);
        id copy = ((copy_fn)objc_msgSend)(params, SEL_("mutableCopy"));
        for (size_t i = 0; i < sizeof kKeys / sizeof kKeys[0]; i++) {
            id key = nsstring(kKeys[i].key);
            id value = ((id(*)(id, SEL, id))objc_msgSend)(copy, SEL_("objectForKey:"), key);
            if (!value) continue;
            double v = ((double (*)(id, SEL))objc_msgSend)(value, SEL_("doubleValue")) * mt_outline_part(parts, kKeys[i].part) / 100.0;
            if (kKeys[i].density && v > 1) v = 1;
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                copy, SEL_("setObject:forKey:"), ((id(*)(id, SEL, double))objc_msgSend)(CLASS("NSNumber"), SEL_("numberWithDouble:"), v), key);
        }
        return copy;
    });
    // Windows shown without becoming key never pass through the two above.
    orig_order = mt_hook(window, "orderWindow:relativeTo:", ^(id self, long place, long other) {
        ((void (*)(id, SEL, long, long))orig_order)(self, SEL_("orderWindow:relativeTo:"), place, other);
        if (place != 0 && MSG_BOOL(self, "isVisible")) mt_border_update(self);  // 0 = NSWindowOut
    });
}
