// Title bar module.
//
// Apps built with an SDK older than macOS 26 get the old metrics on macOS 27:
// a 28 pt title bar (new: 32) and 20 pt between traffic lights (new: 23).
// AppKit computes each metric with a "hasSolariumAppearance" argument that is
// NO for those apps; when the setting is on we pass YES.

#include <crt_externs.h>
#include <mach-o/loader.h>

#include "internal.h"

typedef double (*metric_fn)(id, SEL, unsigned long, BOOL);
typedef CGPoint (*point_fn)(id, SEL);

static IMP g_metric_orig[16];
static int g_metric_count;

static void hook_metric(const char *cls, const char *selector, uint64_t bit) {
    int k = g_metric_count++;
    SEL s = SEL_(selector);
    g_metric_orig[k] = mt_hook(objc_getMetaClass(cls), selector, ^double(id self, unsigned long mask, BOOL solarium) {
        return ((metric_fn)g_metric_orig[k])(self, s, mask, solarium || mt_flag(bit));
    });
}

// Was the main executable built with a pre-macOS 26 SDK? That is what AppKit
// uses to pick the old look. Reads the sdk field of LC_BUILD_VERSION.
static int g_legacy_sdk = -1;

static bool legacy_sdk(void) {
    if (g_legacy_sdk >= 0) return g_legacy_sdk;
    g_legacy_sdk = 0;
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_NSGetMachExecuteHeader();
    if (!mh || mh->magic != MH_MAGIC_64) return false;
    const struct load_command *lc = (const struct load_command *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_BUILD_VERSION) {
            uint32_t sdk = ((const struct build_version_command *)lc)->sdk;  // xxxx.yy.zz
            g_legacy_sdk = (sdk >> 16) < 26;
            break;
        }
        if (lc->cmd == LC_VERSION_MIN_MACOSX) {  // very old binaries
            g_legacy_sdk = 1;
            break;
        }
        lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
    }
    return g_legacy_sdk;
}

static IMP orig_minimize_origin, orig_zoom_origin, orig_center_lights;

void mt_titlebar_install(void) {
    const char *classes[] = {"NSThemeFrame", "NSTitledFrame"};
    for (int i = 0; i < 2; i++) {
        hook_metric(classes[i], "_titlebarHeight:hasSolariumAppearance:", MT_F_LEGACY_TITLEBAR);
        hook_metric(classes[i], "_windowTitlebarTitleMinHeight:hasSolariumAppearance:", MT_F_LEGACY_TITLEBAR);
        hook_metric(classes[i], "_contentToFrameMaxYHeight:hasSolariumAppearance:", MT_F_LEGACY_TITLEBAR);
    }

    Class frame = objc_getClass("NSThemeFrame");

    // The zoom button's origin is derived from the minimize button's, so both get +3.
    orig_minimize_origin = mt_hook(frame, "_collapseButtonOrigin", ^CGPoint(id self) {
        CGPoint p = ((point_fn)orig_minimize_origin)(self, SEL_("_collapseButtonOrigin"));
        if (mt_flag(MT_F_LEGACY_SPACING) && legacy_sdk()) p.x += 3;
        return p;
    });
    orig_zoom_origin = mt_hook(frame, "_zoomButtonOrigin", ^CGPoint(id self) {
        CGPoint p = ((point_fn)orig_zoom_origin)(self, SEL_("_zoomButtonOrigin"));
        if (mt_flag(MT_F_LEGACY_SPACING) && legacy_sdk()) p.x += 3;
        return p;
    });

    // Indent (9 -> 20 pt) and vertically center the traffic lights. In windows
    // with a toolbar AppKit aligns them with the toolbar items; leave those alone.
    orig_center_lights = mt_hook(frame, "_shouldCenterTrafficLights", ^BOOL(id self) {
        if (mt_flag(MT_F_INDENT_LIGHTS) && !MSG(MSG(self, "window"), "toolbar")) return YES;
        return ((BOOL(*)(id, SEL))orig_center_lights)(self, SEL_("_shouldCenterTrafficLights"));
    });
}
