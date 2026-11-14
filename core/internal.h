// Core-internal header: objc helpers and the interface between modules.
#ifndef MT_INTERNAL_H
#define MT_INTERNAL_H

#import <objc/message.h>
#import <objc/runtime.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdbool.h>
#include <stdint.h>

#include "shared.h"

// ---------------------------------------------------------------------------
// objc_msgSend helpers. The core links no frameworks, so AppKit classes and
// methods are reached by name.

#define SEL_(name) sel_registerName(name)
static inline id MSG(id o, const char *s) { return o ? ((id(*)(id, SEL))objc_msgSend)(o, SEL_(s)) : nil; }
static inline bool MSG_BOOL(id o, const char *s) { return o ? ((BOOL(*)(id, SEL))objc_msgSend)(o, SEL_(s)) : false; }
static inline long MSG_LONG(id o, const char *s) { return o ? ((long(*)(id, SEL))objc_msgSend)(o, SEL_(s)) : 0; }
static inline void MSG_VOID(id o, const char *s) {
    if (o) ((void (*)(id, SEL))objc_msgSend)(o, SEL_(s));
}
static inline void MSG_SET_BOOL(id o, const char *s, BOOL v) {
    if (o) ((void (*)(id, SEL, BOOL))objc_msgSend)(o, SEL_(s), v);
}
static inline const char *MSG_CSTR(id o) {
    return o ? ((const char *(*)(id, SEL))objc_msgSend)(o, SEL_("UTF8String")) : NULL;
}
static inline bool RESPONDS(id o, const char *s) {
    return o && ((BOOL(*)(id, SEL, SEL))objc_msgSend)(o, SEL_("respondsToSelector:"), SEL_(s));
}
// A macro, not a function: an id returned from a function gets retained by ARC,
// and retaining a class object runs its +initialize. Doing that for AppKit
// classes from our constructor (before the app is set up) recurses until the
// stack overflows.
#define CLASS(name) ((id)objc_getClass(name))

// +alloc and -init... through objc_msgSend: tell ARC the result is already
// retained (and that -init consumes the receiver), or every call leaks.
typedef id __attribute__((ns_returns_retained)) (*mt_alloc_fn)(id, SEL);
static inline id MSG_ALLOC(const char *cls) { return ((mt_alloc_fn)objc_msgSend)(CLASS(cls), SEL_("alloc")); }

// Replaces a method with a block and returns the original implementation (core.m).
IMP mt_hook(Class cls, const char *selector, id block);

// Settings (core.m). The first call opens the notify registrations.
bool mt_enabled(void);                            // agent running, enabled, and this app not excluded
bool mt_flag(uint64_t bit);                       // enabled and the bit is set in the global state
bool mt_target_radius(double *top, double *bottom);  // true when the corner radius should change
uint64_t mt_settings(void);                       // raw global state

// Modules: each installs its hooks once.
void mt_corners_install(void);   // corners.m
void mt_titlebar_install(void);  // titlebar.m
void mt_buttons_install(void);   // buttons.m

#endif
