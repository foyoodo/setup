// Move a window to another Space using SkyLight.
#import <Cocoa/Cocoa.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <objc/message.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopySpacesForWindows(int cid, int selector, CFArrayRef windows);

static const int kAllSpaces = 0x7;

// hs.spaces.moveWindowToSpace reports success and does nothing on this OS.
// The call that actually moves a window is a private SkyLight symbol.
static void *findSkyLightSymbol(const char *target) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "SkyLight")) continue;

        uint64_t slide = _dyld_get_image_vmaddr_slide(i);
        struct mach_header_64 *header = (struct mach_header_64 *)_dyld_get_image_header(i);
        uint64_t offset = sizeof(struct mach_header_64);
        struct segment_command_64 *linkedit = NULL;
        struct symtab_command *symtab = NULL;
        for (uint32_t c = 0; c < header->ncmds; c++) {
            struct load_command *cmd = (struct load_command *)((uint8_t *)header + offset);
            if (cmd->cmd == LC_SEGMENT_64) {
                struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
                if (strcmp(seg->segname, SEG_LINKEDIT) == 0) linkedit = seg;
            } else if (cmd->cmd == LC_SYMTAB) {
                symtab = (struct symtab_command *)cmd;
            }
            offset += cmd->cmdsize;
        }
        if (!linkedit || !symtab) return NULL;

        char *strings = (char *)(linkedit->vmaddr - linkedit->fileoff) + symtab->stroff + slide;
        struct nlist_64 *symbols = (struct nlist_64 *)((uintptr_t)(linkedit->vmaddr - linkedit->fileoff) + symtab->symoff + slide);
        for (uint32_t s = 0; s < symtab->nsyms; s++) {
            if (strcmp(strings + symbols[s].n_un.n_strx, target) == 0) {
                return (void *)(symbols[s].n_value + slide);
            }
        }
    }
    return NULL;
}

static BOOL windowOnlyOnSpace(int cid, uint32_t wid, uint64_t sid) {
    CFArrayRef spaces = SLSCopySpacesForWindows(cid, kAllSpaces, (__bridge CFArrayRef)@[@(wid)]);
    if (!spaces) return NO;
    BOOL only = CFArrayGetCount(spaces) == 1
        && [(__bridge NSNumber *)CFArrayGetValueAtIndex(spaces, 0) unsignedLongLongValue] == sid;
    CFRelease(spaces);
    return only;
}

static int cmdMove(uint32_t wid, uint64_t sid) {
    typedef int64_t (*PerformFn)(void *);
    static PerformFn perform;
    static BOOL lookedUp = NO;
    if (!lookedUp) {
        lookedUp = YES;
        perform = findSkyLightSymbol(
            "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
    }
    Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!perform || !cls) {
        fprintf(stderr, "focus-space: move unavailable\n");
        return 1;
    }

    int cid = SLSMainConnectionID();
    if (windowOnlyOnSpace(cid, wid, sid)) return 0;

    SEL init = sel_registerName("initWithWindows:spaceID:");
    id operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], init, @[@(wid)], sid);
    if (!operation) return 1;
    perform((__bridge void *)operation);

    // The operation is delivered to WindowServer after this process yields.
    for (int i = 0; i < 30 && !windowOnlyOnSpace(cid, wid, sid); i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    if (!windowOnlyOnSpace(cid, wid, sid)) {
        fprintf(stderr, "focus-space: window %u did not move to %llu\n", wid, sid);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 4 && strcmp(argv[1], "move") == 0) {
        return cmdMove((uint32_t)strtoul(argv[2], NULL, 10), strtoull(argv[3], NULL, 10));
    }
    fprintf(stderr, "usage: focus-space move <windowID> <spaceID>\n");
    return 1;
}
