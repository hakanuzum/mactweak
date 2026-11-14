// Corners module: window corner radius.
//   -[NSThemeFrame _getCachedDefaultWindowCornerRadius]  uniform corner mask
//   -[NSThemeFrame _getCachedWindowCornerRadii]          per-corner mask
// On macOS 27 the window mask (NSCGSWindowCornerMask) is built from these two.
// The default is 16 pt. Windows without a title bar (for example the input
// language bubble, 11.5 pt) never reach these methods and keep their shape.

#include "internal.h"

static IMP orig_default_radius, orig_radii;

void mt_corners_install(void) {
    Class frame = objc_getClass("NSThemeFrame");
    orig_default_radius = mt_hook(frame, "_getCachedDefaultWindowCornerRadius", ^double(id self) {
        double v = ((double (*)(id, SEL))orig_default_radius)(self, SEL_("_getCachedDefaultWindowCornerRadius"));
        double top, bottom;
        if (v > 0 && mt_target_radius(&top, &bottom)) return top;
        return v;  // 0 stays 0 (full screen)
    });
    orig_radii = mt_hook(frame, "_getCachedWindowCornerRadii", ^id(id self) {
        id v = ((id(*)(id, SEL))orig_radii)(self, SEL_("_getCachedWindowCornerRadii"));
        double top, bottom;
        if (!v || MSG_BOOL(v, "isZero") || !mt_target_radius(&top, &bottom)) return v;
        typedef id __attribute__((ns_returns_retained)) (*init_fn)(__attribute__((ns_consumed)) id, SEL, double, double,
                                                                       double, double);
        return ((init_fn)objc_msgSend)(MSG_ALLOC("NSViewCornerRadii"), SEL_("initWithTopLeft:topRight:bottomLeft:bottomRight:"),
                                       top, top, bottom, bottom);
    });
}
