// Border module: a colored border around windows, fading of inactive windows,
// and window shadows. Updated when a window is ordered on screen and when the
// key window changes:
//   -[NSWindow orderWindow:relativeTo:], -[NSWindow becomeKeyWindow], -[NSWindow resignKeyWindow]
// The border is drawn by a transparent view on top of the window frame (the
// frame view is not always layer-backed on macOS 27, so a bare sublayer has
// nowhere to go). The view ignores clicks and takes the window's corner radius,
// so it sits exactly inside the window's mask. Only values this module changed
// are put back (alpha, shadow), never an app's own settings.
//
// The window server draws a rim with the shadow: a dark line outside the window
// and, with Increase Contrast, a white line about 2 pt wide just inside it.
// AppKit sends their strength with the shadow in -[NSWindow shadowParameters];
// the user's outline and shadow settings scale those values. The inner line
// covers half of a 2 pt border, so it is always off under our border.

#include <stdio.h>
#include <stdlib.h>

#include "internal.h"

static char kBorderView, kDimmed, kShadowOff, kShadowParts;

static CGRect rect_of(id o, const char *selector) {
#if defined(__x86_64__)
    return ((CGRect(*)(id, SEL))objc_msgSend_stret)(o, SEL_(selector));
#else
    return ((CGRect(*)(id, SEL))objc_msgSend)(o, SEL_(selector));
#endif
}

static bool flag(id w, const void *key) { return objc_getAssociatedObject(w, key) != nil; }
static void set_flag(id w, const void *key, bool on) {
    // +[NSNumber new] is nil (class cluster), so store a real number.
    id yes = ((id(*)(id, SEL, BOOL))objc_msgSend)(CLASS("NSNumber"), SEL_("numberWithBool:"), YES);
    objc_setAssociatedObject(w, key, on ? yes : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id nsstring(const char *s) {
    return ((id(*)(id, SEL, const char *))objc_msgSend)(CLASS("NSString"), SEL_("stringWithUTF8String:"), s);
}

static void without_animation(void (^block)(void)) {
    id tx = CLASS("CATransaction");
    MSG_VOID(tx, "begin");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(tx, SEL_("setDisableActions:"), YES);
    block();
    MSG_VOID(tx, "commit");
}

// NSView subclass made at runtime whose -hitTest: returns nil, so clicks pass through.
static Class border_view_class(void) {
    static Class cls;
    if (!cls) {
        cls = objc_allocateClassPair(objc_getClass("NSView"), "MTBorderView", 0);
        if (cls) {
            class_addMethod(cls, SEL_("hitTest:"), imp_implementationWithBlock(^id(id self, CGPoint p) { return nil; }),
                            "@@:{CGPoint=dd}");
            objc_registerClassPair(cls);
        } else {
            cls = objc_getClass("MTBorderView");
        }
    }
    return cls;
}

static id make_border_view(CGRect bounds) {
    typedef id __attribute__((ns_returns_retained)) (*alloc_fn)(id, SEL);
    typedef id __attribute__((ns_returns_retained)) (*init_fn)(__attribute__((ns_consumed)) id, SEL, CGRect);
    id v = ((init_fn)objc_msgSend)(((alloc_fn)objc_msgSend)((id)border_view_class(), SEL_("alloc")),
                                   SEL_("initWithFrame:"), bounds);
    MSG_SET_BOOL(v, "setWantsLayer:", YES);
    ((void (*)(id, SEL, unsigned long))objc_msgSend)(v, SEL_("setAutoresizingMask:"), 2 | 16);  // width + height sizable
    return v;
}

void mt_border_update(id w) {
    if (!w) return;
    unsigned long mask = (unsigned long)MSG_LONG(w, "styleMask");
    bool titled = mask & 1, fullscreen = mask & (1UL << 14);
    uint64_t b = (titled && !fullscreen) ? mt_border() : 0;
    bool key = MSG_BOOL(w, "isKeyWindow");

    // Border
    id frame = MSG(MSG(w, "contentView"), "superview");
    id view = objc_getAssociatedObject(w, &kBorderView);
    bool show = frame && (b & MT_B_ENABLED) && mt_border_width(b) > 0 && (key || !(b & MT_B_ACTIVE_ONLY));
    if (getenv("MACTWEAK_LOG"))
        fprintf(stderr, "[mactweak] border: state=0x%llx key=%d show=%d\n", b, key, show);
    if (show && !view) {
        view = make_border_view(rect_of(frame, "bounds"));
        objc_setAssociatedObject(w, &kBorderView, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (view) {
        without_animation(^{
            MSG_SET_BOOL(view, "setHidden:", !show);
            if (!show) return;
            // Keep it the frame's topmost subview (AppKit may add views later).
            if (MSG(view, "superview") != frame || MSG(MSG(frame, "subviews"), "lastObject") != view)
                ((void (*)(id, SEL, id, long, id))objc_msgSend)(frame, SEL_("addSubview:positioned:relativeTo:"), view,
                                                                1 /* above */, nil);
            ((void (*)(id, SEL, CGRect))objc_msgSend)(view, SEL_("setFrame:"), rect_of(frame, "bounds"));
            id layer = MSG(view, "layer");
            double radius = RESPONDS(w, "_cornerRadius") ? ((double (*)(id, SEL))objc_msgSend)(w, SEL_("_cornerRadius")) : 0;
            ((void (*)(id, SEL, double))objc_msgSend)(layer, SEL_("setCornerRadius:"), radius);
            ((void (*)(id, SEL, double))objc_msgSend)(layer, SEL_("setBorderWidth:"), mt_border_width(b));
            id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
                CLASS("NSColor"), SEL_("colorWithSRGBRed:green:blue:alpha:"), (double)(b & 0xFF) / 255.0,
                (double)((b >> 8) & 0xFF) / 255.0, (double)((b >> 16) & 0xFF) / 255.0, (double)((b >> 24) & 0xFF) / 255.0);
            void *cg = ((void *(*)(id, SEL))objc_msgSend)(color, SEL_("CGColor"));
            ((void (*)(id, SEL, void *))objc_msgSend)(layer, SEL_("setBorderColor:"), cg);
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
