/*
 * antirobot.m — 在微信进程内 hook CGEvent 检测函数，
 * 让微信无法区分合成事件和真实硬件输入。
 *
 * 与 unsharingtype.m 合并编译为一个 dylib 注入微信。
 *
 * Hook 策略:
 * 1. CGEventGetIntegerValueField — 当查询 kCGEventSourceStateID 时返回 HID 系统状态
 * 2. CGEventSourceStateID 相关查询 — 总返回 kCGHIDEventTap
 * 3. CGEventGetFlags — 清除 NX_NONCOALSCEDEVENTMASK 等合成标记
 *
 * 编译 (独立):
 *   clang -shared -framework Foundation -framework AppKit -framework CoreGraphics \
 *     -arch arm64 -o antirobot.dylib antirobot.m
 *
 * 编译 (与 unsharingtype 合并):
 *   clang -shared -framework Foundation -framework AppKit -framework CoreGraphics \
 *     -arch arm64 -Wno-deprecated-declarations \
 *     -o unsharingtype.dylib unsharingtype.m antirobot.m
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

// ── fishhook 内联实现 (Facebook, BSD License) ──
// 简化版，只需要 rebind_symbols 功能

#include <mach-o/loader.h>
#include <mach-o/nlist.h>

struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

// fishhook 核心实现
static void perform_rebinding_with_section(
    struct rebinding rebindings[], size_t rebindings_nel,
    const struct mach_header *header, intptr_t slide,
    const uint32_t lazy_sym_sect_idx, const char *sect_name,
    uint32_t *indirect_symtab, const struct nlist_64 *symtab,
    const char *strtab, uint32_t nsyms)
{
    uint32_t *indirect_symbol_indices = indirect_symtab + lazy_sym_sect_idx;

    const struct section_64 *sect = NULL;
    const uint8_t *cur = (const uint8_t *)header + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cur;
            const struct section_64 *sections = (const struct section_64 *)(cur + sizeof(struct segment_command_64));
            for (uint32_t j = 0; j < seg->nsects; j++) {
                if (sections[j].reserved1 == lazy_sym_sect_idx) {
                    sect = &sections[j];
                    break;
                }
            }
        }
        cur += lc->cmdsize;
    }
    if (!sect) return;

    uint32_t nentries = (uint32_t)(sect->size / sizeof(void *));
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + sect->addr);

    for (uint32_t i = 0; i < nentries; i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == 0x80000000 || symtab_index == (0x80000000 | 0x40000000))
            continue;
        if (symtab_index >= nsyms) continue;
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        const char *symbol_name = strtab + strtab_offset;
        if (symbol_name[0] == '_') symbol_name++;

        for (size_t j = 0; j < rebindings_nel; j++) {
            if (strcmp(symbol_name, rebindings[j].name) == 0) {
                if (rebindings[j].replaced && !*rebindings[j].replaced) {
                    *rebindings[j].replaced = indirect_symbol_bindings[i];
                }
                indirect_symbol_bindings[i] = rebindings[j].replacement;
                break;
            }
        }
    }
}

static int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    for (uint32_t img = 0; img < _dyld_image_count(); img++) {
        const struct mach_header *header = _dyld_get_image_header(img);
        intptr_t slide = _dyld_get_image_vmaddr_slide(img);
        if (header->magic != MH_MAGIC_64) continue;

        const uint8_t *cur = (const uint8_t *)header + sizeof(struct mach_header_64);
        const struct symtab_command *symtab_cmd = NULL;
        const struct dysymtab_command *dysymtab_cmd = NULL;
        const struct segment_command_64 *linkedit_seg = NULL;

        for (uint32_t i = 0; i < header->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cur;
            if (lc->cmd == LC_SYMTAB)
                symtab_cmd = (const struct symtab_command *)cur;
            else if (lc->cmd == LC_DYSYMTAB)
                dysymtab_cmd = (const struct dysymtab_command *)cur;
            else if (lc->cmd == LC_SEGMENT_64 &&
                     strcmp(((const struct segment_command_64 *)cur)->segname, SEG_LINKEDIT) == 0)
                linkedit_seg = (const struct segment_command_64 *)cur;
            cur += lc->cmdsize;
        }
        if (!symtab_cmd || !dysymtab_cmd || !linkedit_seg) continue;

        uintptr_t linkedit_base = (uintptr_t)slide + linkedit_seg->vmaddr - linkedit_seg->fileoff;
        const struct nlist_64 *symtab = (const struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
        const char *strtab = (const char *)(linkedit_base + symtab_cmd->stroff);
        uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

        // 遍历所有 section 找 lazy/non-lazy symbol pointers
        cur = (const uint8_t *)header + sizeof(struct mach_header_64);
        for (uint32_t i = 0; i < header->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cur;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cur;
                const struct section_64 *sections = (const struct section_64 *)(cur + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    uint8_t type = sections[j].flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                        perform_rebinding_with_section(
                            rebindings, rebindings_nel,
                            header, slide,
                            sections[j].reserved1, sections[j].sectname,
                            indirect_symtab, symtab, strtab,
                            symtab_cmd->nsyms);
                    }
                }
            }
            cur += lc->cmdsize;
        }
    }
    return 0;
}

// ── Hook 实现 ──

// 原始函数指针
static int64_t (*orig_CGEventGetIntegerValueField)(CGEventRef event, CGEventField field) = NULL;
static CGEventFlags (*orig_CGEventGetFlags)(CGEventRef event) = NULL;

// 关键 field 常量
// kCGEventSourceStateID = 45
// kCGEventSourceUnixProcessID = 41
// kCGEventSourceUserData = 42
#define kFieldSourceStateID 45
#define kFieldSourcePID     41
#define kFieldSourceUserData 42

// Hook: CGEventGetIntegerValueField
// 当微信查询事件来源状态时，总返回 kCGHIDEventTap (1) = 硬件来源
static int64_t hook_CGEventGetIntegerValueField(CGEventRef event, CGEventField field) {
    if (field == kFieldSourceStateID) {
        // 返回 1 = kCGEventSourceStateHIDSystemState，即"来自硬件"
        return 1;
    }
    if (field == kFieldSourcePID) {
        // 返回 0 = 没有来源进程，看起来像硬件事件
        return 0;
    }
    if (field == kFieldSourceUserData) {
        // 清除用户数据标记
        return 0;
    }
    return orig_CGEventGetIntegerValueField(event, field);
}

// Hook: CGEventGetFlags
// 清除可能标识合成事件的 flag
static CGEventFlags hook_CGEventGetFlags(CGEventRef event) {
    CGEventFlags flags = orig_CGEventGetFlags(event);
    // Bit 29 (0x20000000) = NX_NONCOALSCEDEVENTMASK，有时被用来标记合成事件
    flags &= ~0x20000000;
    return flags;
}

__attribute__((constructor))
static void antirobot_init(void) {
    NSLog(@"[AntiRobot] 加载中...");

    struct rebinding rebindings[] = {
        {"CGEventGetIntegerValueField", (void *)hook_CGEventGetIntegerValueField, (void **)&orig_CGEventGetIntegerValueField},
        {"CGEventGetFlags", (void *)hook_CGEventGetFlags, (void **)&orig_CGEventGetFlags},
    };

    int ret = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    if (ret == 0) {
        NSLog(@"[AntiRobot] ✅ CGEvent hooks 已安装");
        NSLog(@"[AntiRobot]   - CGEventGetIntegerValueField: 来源字段已伪装");
        NSLog(@"[AntiRobot]   - CGEventGetFlags: 合成标记已清除");
    } else {
        NSLog(@"[AntiRobot] ❌ hook 安装失败 (%d)", ret);
    }
}
