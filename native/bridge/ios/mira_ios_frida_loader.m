#include "mira_pty_ios_shim.h"

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static pthread_mutex_t g_frida_loader_mutex = PTHREAD_MUTEX_INITIALIZER;
static int g_frida_loader_attempted = 0;
static int g_frida_loader_loaded = 0;
static char g_frida_loader_detail[256] = "idle";

static void mira_frida_loader_set_detail(const char *text) {
    snprintf(g_frida_loader_detail, sizeof(g_frida_loader_detail), "%s", text == NULL ? "unknown" : text);
}

int mira_ios_frida_loader_ensure_loaded(void) {
    pthread_mutex_lock(&g_frida_loader_mutex);
    if (g_frida_loader_attempted) {
        int loaded = g_frida_loader_loaded;
        pthread_mutex_unlock(&g_frida_loader_mutex);
        return loaded;
    }
    g_frida_loader_attempted = 1;
    pthread_mutex_unlock(&g_frida_loader_mutex);

    @autoreleasepool {
        NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
        if (NSBundle.mainBundle.privateFrameworksURL != nil) {
            [candidates addObject:[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"libdynamic.dylib"]];
        }
        [candidates addObject:[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"libdynamic.dylib"]];

        for (NSURL *candidate in candidates) {
            if (candidate == nil || ![NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
                continue;
            }

            void *handle = dlopen(candidate.path.fileSystemRepresentation, RTLD_NOW);
            pthread_mutex_lock(&g_frida_loader_mutex);
            if (handle != NULL) {
                g_frida_loader_loaded = 1;
                mira_frida_loader_set_detail("loaded");
                pthread_mutex_unlock(&g_frida_loader_mutex);
                return 1;
            }

            const char *error_text = dlerror();
            snprintf(g_frida_loader_detail,
                     sizeof(g_frida_loader_detail),
                     "load failed: %s",
                     error_text != NULL ? error_text : "unknown error");
            pthread_mutex_unlock(&g_frida_loader_mutex);
            return 0;
        }
    }

    pthread_mutex_lock(&g_frida_loader_mutex);
    g_frida_loader_loaded = 0;
    mira_frida_loader_set_detail("missing bundled gadget");
    pthread_mutex_unlock(&g_frida_loader_mutex);
    return 0;
}

const char *mira_ios_frida_loader_status(void) {
    static char snapshot[256];
    pthread_mutex_lock(&g_frida_loader_mutex);
    snprintf(snapshot, sizeof(snapshot), "%s", g_frida_loader_detail);
    pthread_mutex_unlock(&g_frida_loader_mutex);
    return snapshot;
}

int mira_ios_frida_loader_is_loaded(void) {
    pthread_mutex_lock(&g_frida_loader_mutex);
    int loaded = g_frida_loader_loaded;
    pthread_mutex_unlock(&g_frida_loader_mutex);
    return loaded;
}
