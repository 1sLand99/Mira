#import <Foundation/Foundation.h>

#include "shell/ish_hostfs.h"

#include <TargetConditionals.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "fs/fd.h"
#include "fs/path.h"
#include "fs/real.h"
#include "kernel/calls.h"
#include "kernel/errno.h"
#include "kernel/fs.h"

extern char **environ;

typedef enum mira_proc_node {
  MIRA_PROC_NODE_ROOT = 1,
  MIRA_PROC_NODE_STATUS,
  MIRA_PROC_NODE_CMDLINE,
  MIRA_PROC_NODE_ENVIRON,
  MIRA_PROC_NODE_MAPS,
  MIRA_PROC_NODE_IMAGES,
  MIRA_PROC_NODE_TASK,
  MIRA_PROC_NODE_FD,
  MIRA_PROC_NODE_FD_ENTRY,
  MIRA_PROC_NODE_FDINFO,
  MIRA_PROC_NODE_BUNDLE,
  MIRA_PROC_NODE_PATHS,
} mira_proc_node_t;

typedef struct mira_proc_path {
  mira_proc_node_t node;
  int host_fd;
} mira_proc_path_t;

typedef struct mira_proc_buffer {
  char *data;
  size_t length;
  size_t capacity;
} mira_proc_buffer_t;

typedef struct mira_proc_fd_data {
  mira_proc_node_t node;
  int host_fd;
  char *data;
  size_t size;
} mira_proc_fd_data_t;

typedef struct mira_proc_entry {
  const char *name;
  mira_proc_node_t node;
} mira_proc_entry_t;

static const mira_proc_entry_t g_mira_proc_root_entries[] = {
    {"status", MIRA_PROC_NODE_STATUS},   {"cmdline", MIRA_PROC_NODE_CMDLINE},
    {"environ", MIRA_PROC_NODE_ENVIRON}, {"maps", MIRA_PROC_NODE_MAPS},
    {"images", MIRA_PROC_NODE_IMAGES},   {"task", MIRA_PROC_NODE_TASK},
    {"fd", MIRA_PROC_NODE_FD},           {"fdinfo", MIRA_PROC_NODE_FDINFO},
    {"bundle", MIRA_PROC_NODE_BUNDLE},   {"paths", MIRA_PROC_NODE_PATHS},
};

static int mira_proc_buffer_append(mira_proc_buffer_t *buffer, const void *data,
                                   size_t length) {
  if (length == 0) {
    return 0;
  }
  size_t needed = buffer->length + length + 1U;
  if (needed > buffer->capacity) {
    size_t next = buffer->capacity == 0 ? 4096U : buffer->capacity;
    while (next < needed) {
      next *= 2U;
    }
    char *resized = (char *)realloc(buffer->data, next);
    if (resized == NULL) {
      return _ENOMEM;
    }
    buffer->data = resized;
    buffer->capacity = next;
  }
  memcpy(buffer->data + buffer->length, data, length);
  buffer->length += length;
  buffer->data[buffer->length] = '\0';
  return 0;
}

static int mira_proc_buffer_append_cstr(mira_proc_buffer_t *buffer,
                                        const char *string) {
  return mira_proc_buffer_append(buffer, string, strlen(string));
}

static int mira_proc_buffer_appendf(mira_proc_buffer_t *buffer,
                                    const char *format, ...) {
  va_list args;
  va_start(args, format);
  va_list copy;
  va_copy(copy, args);
  int needed = vsnprintf(NULL, 0, format, args);
  va_end(args);
  if (needed < 0) {
    va_end(copy);
    return _EIO;
  }
  char *scratch = (char *)malloc((size_t)needed + 1U);
  if (scratch == NULL) {
    va_end(copy);
    return _ENOMEM;
  }
  vsnprintf(scratch, (size_t)needed + 1U, format, copy);
  va_end(copy);
  int err = mira_proc_buffer_append(buffer, scratch, (size_t)needed);
  free(scratch);
  return err;
}

static bool mira_proc_host_fd_is_valid(int fd) {
  if (fd < 0) {
    return false;
  }
  errno = 0;
  if (fcntl(fd, F_GETFD) >= 0) {
    return true;
  }
  return errno != EBADF;
}

static int mira_proc_host_fd_limit(void) {
  int limit = getdtablesize();
  if (limit <= 0 || limit > 65536) {
    limit = 1024;
  }
  return limit;
}

static bool mira_proc_parse_fd_entry(const char *text, int *fd_out) {
  if (text == NULL || text[0] == '\0') {
    return false;
  }
  char *end = NULL;
  errno = 0;
  long value = strtol(text, &end, 10);
  if (errno != 0 || end == text || *end != '\0' || value < 0 ||
      value > INT32_MAX) {
    return false;
  }
  *fd_out = (int)value;
  return true;
}

static bool mira_proc_lookup_path(const char *path, mira_proc_path_t *result) {
  if (path == NULL || path[0] == '\0' || strcmp(path, "/") == 0) {
    *result = (mira_proc_path_t){.node = MIRA_PROC_NODE_ROOT, .host_fd = -1};
    return true;
  }
  if (path[0] == '/') {
    path++;
  }

  if (strncmp(path, "fd/", 3) == 0) {
    int host_fd = -1;
    if (!mira_proc_parse_fd_entry(path + 3, &host_fd) ||
        !mira_proc_host_fd_is_valid(host_fd)) {
      return false;
    }
    *result =
        (mira_proc_path_t){.node = MIRA_PROC_NODE_FD_ENTRY, .host_fd = host_fd};
    return true;
  }
  if (strchr(path, '/') != NULL) {
    return false;
  }
  for (size_t i = 0; i < sizeof(g_mira_proc_root_entries) /
                             sizeof(g_mira_proc_root_entries[0]);
       ++i) {
    if (strcmp(path, g_mira_proc_root_entries[i].name) == 0) {
      *result = (mira_proc_path_t){.node = g_mira_proc_root_entries[i].node,
                                   .host_fd = -1};
      return true;
    }
  }
  return false;
}

static const char *mira_proc_node_name(mira_proc_node_t node) {
  if (node == MIRA_PROC_NODE_ROOT) {
    return "";
  }
  for (size_t i = 0; i < sizeof(g_mira_proc_root_entries) /
                             sizeof(g_mira_proc_root_entries[0]);
       ++i) {
    if (g_mira_proc_root_entries[i].node == node) {
      return g_mira_proc_root_entries[i].name;
    }
  }
  return "unknown";
}

static bool mira_proc_node_is_directory(mira_proc_node_t node) {
  return node == MIRA_PROC_NODE_ROOT || node == MIRA_PROC_NODE_FD;
}

static bool mira_proc_node_is_symlink(mira_proc_node_t node) {
  return node == MIRA_PROC_NODE_FD_ENTRY;
}

static uint64_t mira_proc_inode_for_path(mira_proc_path_t path) {
  if (path.node == MIRA_PROC_NODE_FD_ENTRY) {
    return 0x6d6972611000ULL + (uint64_t)path.host_fd;
  }
  return 0x6d6972610000ULL + (uint64_t)path.node;
}

static char mira_proc_prot_char(vm_prot_t prot, vm_prot_t mask, char value) {
  return (prot & mask) ? value : '-';
}

static bool mira_proc_header_is_64(const struct mach_header *header) {
  return header != NULL &&
         (header->magic == MH_MAGIC_64 || header->magic == MH_CIGAM_64);
}

static const char *mira_proc_image_name_for_address(uintptr_t address,
                                                    const char **segment_out) {
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; ++i) {
    const struct mach_header *header = _dyld_get_image_header(i);
    if (!mira_proc_header_is_64(header)) {
      continue;
    }
    const struct mach_header_64 *header64 =
        (const struct mach_header_64 *)header;
    intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    const uint8_t *cursor = (const uint8_t *)(header64 + 1);
    for (uint32_t command_index = 0; command_index < header64->ncmds;
         ++command_index) {
      const struct load_command *command = (const struct load_command *)cursor;
      if (command->cmd == LC_SEGMENT_64) {
        const struct segment_command_64 *segment =
            (const struct segment_command_64 *)command;
        uintptr_t start =
            (uintptr_t)((uint64_t)segment->vmaddr + (uint64_t)slide);
        uintptr_t end = start + (uintptr_t)segment->vmsize;
        if (address >= start && address < end) {
          if (segment_out != NULL) {
            *segment_out = segment->segname;
          }
          return _dyld_get_image_name(i);
        }
      }
      cursor += command->cmdsize;
    }
  }
  if (segment_out != NULL) {
    *segment_out = "";
  }
  return "";
}

static int mira_proc_append_status(mira_proc_buffer_t *buffer) {
  struct utsname uts = {};
  uname(&uts);
  @autoreleasepool {
    NSProcessInfo *processInfo = NSProcessInfo.processInfo;
    NSBundle *bundle = NSBundle.mainBundle;
    return mira_proc_buffer_appendf(
        buffer,
        "Name:\t%s\n"
        "Pid:\t%d\n"
        "Uid:\t%d\n"
        "Gid:\t%d\n"
        "BundleId:\t%s\n"
        "ProcessName:\t%s\n"
        "Executable:\t%s\n"
        "Home:\t%s\n"
        "OS:\t%s %s\n"
        "Machine:\t%s\n"
        "DyldImages:\t%u\n"
        "Scope:\tcurrent iOS app process and app-accessible paths only\n",
        processInfo.processName.UTF8String ?: "Mira", getpid(), getuid(),
        getgid(), bundle.bundleIdentifier.UTF8String ?: "",
        processInfo.processName.UTF8String ?: "",
        bundle.executableURL.fileSystemRepresentation ?: "",
        NSHomeDirectory().fileSystemRepresentation, uts.sysname, uts.release,
        uts.machine, _dyld_image_count());
  }
}

static int mira_proc_append_cmdline(mira_proc_buffer_t *buffer) {
  @autoreleasepool {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (arguments.count == 0) {
      const char *fallback =
          NSBundle.mainBundle.executableURL.fileSystemRepresentation ?: "Mira";
      return mira_proc_buffer_append(buffer, fallback, strlen(fallback) + 1U);
    }
    for (NSString *argument in arguments) {
      const char *text = argument.UTF8String ?: "";
      int err = mira_proc_buffer_append(buffer, text, strlen(text) + 1U);
      if (err < 0) {
        return err;
      }
    }
  }
  return 0;
}

static int mira_proc_append_environ(mira_proc_buffer_t *buffer) {
  if (environ == NULL) {
    return 0;
  }
  for (char **item = environ; *item != NULL; ++item) {
    int err = mira_proc_buffer_append(buffer, *item, strlen(*item) + 1U);
    if (err < 0) {
      return err;
    }
  }
  return 0;
}

static int mira_proc_append_paths(mira_proc_buffer_t *buffer) {
  @autoreleasepool {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSURL *> *documents = [manager URLsForDirectory:NSDocumentDirectory
                                                  inDomains:NSUserDomainMask];
    NSArray<NSURL *> *library = [manager URLsForDirectory:NSLibraryDirectory
                                                inDomains:NSUserDomainMask];
    NSArray<NSURL *> *applicationSupport =
        [manager URLsForDirectory:NSApplicationSupportDirectory
                        inDomains:NSUserDomainMask];
    NSArray<NSURL *> *caches = [manager URLsForDirectory:NSCachesDirectory
                                               inDomains:NSUserDomainMask];

    int err = mira_proc_buffer_appendf(
        buffer, "home=%s\n", NSHomeDirectory().fileSystemRepresentation);
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "tmp=%s\n", NSTemporaryDirectory().fileSystemRepresentation);
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "bundle=%s\n",
        NSBundle.mainBundle.bundleURL.fileSystemRepresentation);
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "executable=%s\n",
        NSBundle.mainBundle.executableURL.fileSystemRepresentation);
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "documents=%s\n",
        documents.firstObject.fileSystemRepresentation ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(buffer, "library=%s\n",
                                   library.firstObject.fileSystemRepresentation
                                       ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "application_support=%s\n",
        applicationSupport.firstObject.fileSystemRepresentation ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(buffer, "caches=%s\n",
                                   caches.firstObject.fileSystemRepresentation
                                       ?: "");
    if (err < 0)
      return err;
    NSURL *ishRoot = [[[applicationSupport.firstObject
        URLByAppendingPathComponent:@"Mira"
                        isDirectory:YES] URLByAppendingPathComponent:@"iSH"
                                                         isDirectory:YES]
        URLByAppendingPathComponent:@"default"
                        isDirectory:YES];
    return mira_proc_buffer_appendf(buffer, "ish_root=%s\n",
                                    ishRoot.fileSystemRepresentation ?: "");
  }
}

static int mira_proc_append_bundle(mira_proc_buffer_t *buffer) {
  @autoreleasepool {
    NSBundle *bundle = NSBundle.mainBundle;
    NSDictionary *info = bundle.infoDictionary;
    int err = mira_proc_buffer_appendf(
        buffer, "bundle_path=%s\n", bundle.bundleURL.fileSystemRepresentation);
    if (err < 0)
      return err;
    err =
        mira_proc_buffer_appendf(buffer, "executable_path=%s\n",
                                 bundle.executableURL.fileSystemRepresentation);
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(buffer, "identifier=%s\n",
                                   bundle.bundleIdentifier.UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "name=%s\n",
        [info[@"CFBundleName"] description].UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "display_name=%s\n",
        [info[@"CFBundleDisplayName"] description].UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "version=%s\n",
        [info[@"CFBundleShortVersionString"] description].UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "build=%s\n",
        [info[@"CFBundleVersion"] description].UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(
        buffer, "minimum_os=%s\n",
        [info[@"MinimumOSVersion"] description].UTF8String ?: "");
    if (err < 0)
      return err;
    err = mira_proc_buffer_appendf(buffer, "embedded_provision=%s\n",
                                   [bundle pathForResource:@"embedded"
                                                    ofType:@"mobileprovision"]
                                           .UTF8String
                                       ?: "");
    if (err < 0)
      return err;

    NSError *error = nil;
    NSArray<NSString *> *items = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:bundle.bundlePath
                            error:&error];
    if (items != nil) {
      err = mira_proc_buffer_append_cstr(buffer, "\nroot_entries:\n");
      if (err < 0)
        return err;
      for (NSString *item in
           [items sortedArrayUsingSelector:@selector(compare:)]) {
        err = mira_proc_buffer_appendf(buffer, "%s\n", item.UTF8String);
        if (err < 0)
          return err;
      }
    } else {
      err = mira_proc_buffer_appendf(buffer, "\nroot_entries_error=%s\n",
                                     error.localizedDescription.UTF8String
                                         ?: "unknown");
      if (err < 0)
        return err;
    }
  }
  return 0;
}

static int mira_proc_append_images(mira_proc_buffer_t *buffer) {
  uint32_t count = _dyld_image_count();
  int err = mira_proc_buffer_appendf(buffer, "count=%u\n", count);
  if (err < 0) {
    return err;
  }
  for (uint32_t i = 0; i < count; ++i) {
    const struct mach_header *header = _dyld_get_image_header(i);
    intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    const char *name = _dyld_get_image_name(i);
    err = mira_proc_buffer_appendf(
        buffer, "%4u 0x%016llx slide=%+lld magic=0x%08x %s\n", i,
        (unsigned long long)(uintptr_t)header, (long long)slide,
        header == NULL ? 0 : header->magic, name == NULL ? "" : name);
    if (err < 0) {
      return err;
    }
  }
  return 0;
}

static int mira_proc_append_maps(mira_proc_buffer_t *buffer) {
  mach_port_t task = mach_task_self();
  vm_address_t address = 0;
  natural_t depth = 0;
  int err = mira_proc_buffer_append_cstr(
      buffer,
      "start-end              prot maxp share tag depth segment image\n");
  if (err < 0) {
    return err;
  }

  for (unsigned region_count = 0; region_count < 20000; ++region_count) {
    vm_size_t size = 0;
    vm_region_submap_info_data_64_t info = {};
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    kern_return_t kr = vm_region_recurse_64(
        task, &address, &size, &depth, (vm_region_recurse_info_t)&info, &count);
    if (kr != KERN_SUCCESS) {
      break;
    }
    if (info.is_submap) {
      depth++;
      continue;
    }

    const char *segment = "";
    const char *image =
        mira_proc_image_name_for_address((uintptr_t)address, &segment);
    vm_address_t end = address + size;
    err = mira_proc_buffer_appendf(
        buffer, "0x%016llx-0x%016llx %c%c%c %c%c%c %5u %3u %5u %-16s %s\n",
        (unsigned long long)address, (unsigned long long)end,
        mira_proc_prot_char(info.protection, VM_PROT_READ, 'r'),
        mira_proc_prot_char(info.protection, VM_PROT_WRITE, 'w'),
        mira_proc_prot_char(info.protection, VM_PROT_EXECUTE, 'x'),
        mira_proc_prot_char(info.max_protection, VM_PROT_READ, 'r'),
        mira_proc_prot_char(info.max_protection, VM_PROT_WRITE, 'w'),
        mira_proc_prot_char(info.max_protection, VM_PROT_EXECUTE, 'x'),
        info.share_mode, info.user_tag, depth, segment == NULL ? "" : segment,
        image == NULL ? "" : image);
    if (err < 0) {
      return err;
    }
    if (end <= address) {
      break;
    }
    address = end;
  }
  return 0;
}

static int mira_proc_append_task(mira_proc_buffer_t *buffer) {
  task_vm_info_data_t vm_info = {};
  mach_msg_type_number_t vm_count = TASK_VM_INFO_COUNT;
  kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO,
                               (task_info_t)&vm_info, &vm_count);
  if (kr == KERN_SUCCESS) {
    int err =
        mira_proc_buffer_appendf(buffer,
                                 "virtual_size=%llu\n"
                                 "resident_size=%llu\n"
                                 "resident_size_peak=%llu\n"
                                 "phys_footprint=%llu\n"
                                 "internal=%llu\n"
                                 "compressed=%llu\n"
                                 "external=%llu\n"
                                 "reusable=%llu\n",
                                 (unsigned long long)vm_info.virtual_size,
                                 (unsigned long long)vm_info.resident_size,
                                 (unsigned long long)vm_info.resident_size_peak,
                                 (unsigned long long)vm_info.phys_footprint,
                                 (unsigned long long)vm_info.internal,
                                 (unsigned long long)vm_info.compressed,
                                 (unsigned long long)vm_info.external,
                                 (unsigned long long)vm_info.reusable);
    if (err < 0) {
      return err;
    }
  } else {
    int err = mira_proc_buffer_appendf(buffer, "task_vm_info_error=%s\n",
                                       mach_error_string(kr));
    if (err < 0) {
      return err;
    }
  }

  task_basic_info_64_data_t basic = {};
  mach_msg_type_number_t basic_count = TASK_BASIC_INFO_64_COUNT;
  kr = task_info(mach_task_self(), TASK_BASIC_INFO_64, (task_info_t)&basic,
                 &basic_count);
  if (kr == KERN_SUCCESS) {
    return mira_proc_buffer_appendf(
        buffer,
        "suspend_count=%d\n"
        "user_time=%d.%06d\n"
        "system_time=%d.%06d\n",
        basic.suspend_count, basic.user_time.seconds,
        basic.user_time.microseconds, basic.system_time.seconds,
        basic.system_time.microseconds);
  }
  return mira_proc_buffer_appendf(buffer, "task_basic_info_error=%s\n",
                                  mach_error_string(kr));
}

static int mira_proc_readlink_fd(int host_fd, char *buf, size_t buf_size) {
  if (!mira_proc_host_fd_is_valid(host_fd)) {
    return _ENOENT;
  }
#if defined(F_GETPATH)
  char path[MAX_PATH] = {0};
  if (fcntl(host_fd, F_GETPATH, path) == 0 && path[0] != '\0') {
    if (strcmp(path, "/") == 0) {
      snprintf(buf, buf_size, "/mira");
    } else if (path[0] == '/') {
      snprintf(buf, buf_size, "/mira%s", path);
    } else {
      snprintf(buf, buf_size, "%s", path);
    }
    return 0;
  }
#endif
  struct stat statbuf;
  if (fstat(host_fd, &statbuf) == 0) {
    if (S_ISSOCK(statbuf.st_mode)) {
      snprintf(buf, buf_size, "socket:[%d]", host_fd);
      return 0;
    }
    if (S_ISFIFO(statbuf.st_mode)) {
      snprintf(buf, buf_size, "pipe:[%d]", host_fd);
      return 0;
    }
    if (S_ISCHR(statbuf.st_mode)) {
      snprintf(buf, buf_size, "char:[%d]", host_fd);
      return 0;
    }
    if (S_ISDIR(statbuf.st_mode)) {
      snprintf(buf, buf_size, "dir:[%d]", host_fd);
      return 0;
    }
  }
  snprintf(buf, buf_size, "anon:[%d]", host_fd);
  return 0;
}

static int mira_proc_append_fdinfo(mira_proc_buffer_t *buffer) {
  int limit = mira_proc_host_fd_limit();
  for (int host_fd = 0; host_fd < limit; ++host_fd) {
    if (!mira_proc_host_fd_is_valid(host_fd)) {
      continue;
    }
    char target[MAX_PATH] = {0};
    int err = mira_proc_readlink_fd(host_fd, target, sizeof(target));
    if (err < 0) {
      continue;
    }
    int flags = fcntl(host_fd, F_GETFL);
    err = mira_proc_buffer_appendf(buffer, "%d flags=0x%x target=%s\n", host_fd,
                                   flags < 0 ? 0 : flags, target);
    if (err < 0) {
      return err;
    }
  }
  return 0;
}

static int mira_proc_generate_file(mira_proc_node_t node, char **data_out,
                                   size_t *size_out) {
  mira_proc_buffer_t buffer = {};
  int err = 0;
  switch (node) {
  case MIRA_PROC_NODE_STATUS:
    err = mira_proc_append_status(&buffer);
    break;
  case MIRA_PROC_NODE_CMDLINE:
    err = mira_proc_append_cmdline(&buffer);
    break;
  case MIRA_PROC_NODE_ENVIRON:
    err = mira_proc_append_environ(&buffer);
    break;
  case MIRA_PROC_NODE_MAPS:
    err = mira_proc_append_maps(&buffer);
    break;
  case MIRA_PROC_NODE_IMAGES:
    err = mira_proc_append_images(&buffer);
    break;
  case MIRA_PROC_NODE_TASK:
    err = mira_proc_append_task(&buffer);
    break;
  case MIRA_PROC_NODE_FDINFO:
    err = mira_proc_append_fdinfo(&buffer);
    break;
  case MIRA_PROC_NODE_BUNDLE:
    err = mira_proc_append_bundle(&buffer);
    break;
  case MIRA_PROC_NODE_PATHS:
    err = mira_proc_append_paths(&buffer);
    break;
  case MIRA_PROC_NODE_ROOT:
  case MIRA_PROC_NODE_FD:
    err = _EISDIR;
    break;
  case MIRA_PROC_NODE_FD_ENTRY:
    err = _EINVAL;
    break;
  }
  if (err < 0) {
    free(buffer.data);
    return err;
  }
  if (buffer.data == NULL) {
    buffer.data = strdup("");
    if (buffer.data == NULL) {
      return _ENOMEM;
    }
  }
  *data_out = buffer.data;
  *size_out = buffer.length;
  return 0;
}

static size_t mira_proc_symlink_size(mira_proc_path_t path) {
  if (path.node != MIRA_PROC_NODE_FD_ENTRY) {
    return 0;
  }
  char target[MAX_PATH] = {0};
  if (mira_proc_readlink_fd(path.host_fd, target, sizeof(target)) < 0) {
    return 0;
  }
  return strlen(target);
}

static void mira_proc_fill_stat(mira_proc_path_t path, struct statbuf *stat,
                                size_t size) {
  memset(stat, 0, sizeof(*stat));
  stat->dev = 0x6d697261;
  stat->inode = mira_proc_inode_for_path(path);
  if (mira_proc_node_is_directory(path.node)) {
    stat->mode = S_IFDIR | 0555;
    stat->nlink = 2;
  } else if (mira_proc_node_is_symlink(path.node)) {
    stat->mode = S_IFLNK | 0777;
    stat->nlink = 1;
    stat->size = size;
  } else {
    stat->mode = S_IFREG | 0444;
    stat->nlink = 1;
    stat->size = size;
  }
  stat->uid = 0;
  stat->gid = 0;
  stat->blksize = 4096;
  stat->blocks = (stat->size + 511U) / 512U;
  struct timeval now;
  gettimeofday(&now, NULL);
  stat->atime = (dword_t)now.tv_sec;
  stat->mtime = (dword_t)now.tv_sec;
  stat->ctime = (dword_t)now.tv_sec;
  stat->atime_nsec = (dword_t)now.tv_usec * 1000U;
  stat->mtime_nsec = stat->atime_nsec;
  stat->ctime_nsec = stat->atime_nsec;
}

static struct fd *mira_procfs_open(struct mount *UNUSED(mount),
                                   const char *path, int flags,
                                   int UNUSED(mode)) {
  if (flags & (O_WRONLY_ | O_RDWR_ | O_CREAT_ | O_TRUNC_)) {
    return ERR_PTR(_EROFS);
  }

  mira_proc_path_t proc_path = {};
  if (!mira_proc_lookup_path(path, &proc_path)) {
    return ERR_PTR(_ENOENT);
  }
  if (mira_proc_node_is_symlink(proc_path.node)) {
    return ERR_PTR(_ELOOP);
  }

  mira_proc_fd_data_t *proc_fd =
      (mira_proc_fd_data_t *)calloc(1, sizeof(*proc_fd));
  if (proc_fd == NULL) {
    return ERR_PTR(_ENOMEM);
  }
  proc_fd->node = proc_path.node;
  proc_fd->host_fd = proc_path.host_fd;
  if (!mira_proc_node_is_directory(proc_path.node)) {
    int err =
        mira_proc_generate_file(proc_path.node, &proc_fd->data, &proc_fd->size);
    if (err < 0) {
      free(proc_fd);
      return ERR_PTR(err);
    }
  }

  extern const struct fd_ops mira_procfs_fdops;
  struct fd *fd = fd_create(&mira_procfs_fdops);
  if (fd == NULL) {
    free(proc_fd->data);
    free(proc_fd);
    return ERR_PTR(_ENOMEM);
  }
  fd->fs_data = proc_fd;
  return fd;
}

static int mira_procfs_stat(struct mount *UNUSED(mount), const char *path,
                            struct statbuf *stat) {
  mira_proc_path_t proc_path = {};
  if (!mira_proc_lookup_path(path, &proc_path)) {
    return _ENOENT;
  }
  size_t size = 0;
  if (mira_proc_node_is_symlink(proc_path.node)) {
    size = mira_proc_symlink_size(proc_path);
  } else if (!mira_proc_node_is_directory(proc_path.node)) {
    char *data = NULL;
    int err = mira_proc_generate_file(proc_path.node, &data, &size);
    free(data);
    if (err < 0) {
      return err;
    }
  }
  mira_proc_fill_stat(proc_path, stat, size);
  return 0;
}

static int mira_procfs_fstat(struct fd *fd, struct statbuf *stat) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd == NULL) {
    return _EBADF;
  }
  mira_proc_path_t proc_path = {.node = proc_fd->node,
                                .host_fd = proc_fd->host_fd};
  mira_proc_fill_stat(proc_path, stat, proc_fd->size);
  return 0;
}

static int mira_procfs_getpath(struct fd *fd, char *buf) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd == NULL) {
    return _EBADF;
  }
  if (proc_fd->node == MIRA_PROC_NODE_ROOT) {
    buf[0] = '\0';
  } else if (proc_fd->node == MIRA_PROC_NODE_FD_ENTRY) {
    snprintf(buf, MAX_PATH, "/fd/%d", proc_fd->host_fd);
  } else {
    snprintf(buf, MAX_PATH, "/%s", mira_proc_node_name(proc_fd->node));
  }
  return 0;
}

static ssize_t mira_procfs_readlink(struct mount *UNUSED(mount),
                                    const char *path, char *buf,
                                    size_t bufsize) {
  mira_proc_path_t proc_path = {};
  if (!mira_proc_lookup_path(path, &proc_path)) {
    return _ENOENT;
  }
  if (proc_path.node != MIRA_PROC_NODE_FD_ENTRY) {
    return _EINVAL;
  }
  char target[MAX_PATH] = {0};
  int err = mira_proc_readlink_fd(proc_path.host_fd, target, sizeof(target));
  if (err < 0) {
    return err;
  }
  size_t length = strlen(target);
  if (bufsize > length) {
    bufsize = length;
  }
  memcpy(buf, target, bufsize);
  return (ssize_t)bufsize;
}

static ssize_t mira_procfs_pread(struct fd *fd, void *buf, size_t bufsize,
                                 off_t off) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd == NULL) {
    return _EBADF;
  }
  if (mira_proc_node_is_directory(proc_fd->node)) {
    return _EISDIR;
  }
  if (off < 0) {
    return _EINVAL;
  }
  size_t offset = (size_t)off;
  if (offset >= proc_fd->size) {
    return 0;
  }
  size_t remaining = proc_fd->size - offset;
  size_t count = remaining < bufsize ? remaining : bufsize;
  memcpy(buf, proc_fd->data + offset, count);
  return (ssize_t)count;
}

static off_t_ mira_procfs_lseek(struct fd *fd, off_t_ off, int whence) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd == NULL) {
    return _EBADF;
  }
  size_t size = proc_fd->size;
  if (proc_fd->node == MIRA_PROC_NODE_ROOT) {
    size =
        sizeof(g_mira_proc_root_entries) / sizeof(g_mira_proc_root_entries[0]) +
        2U;
  } else if (proc_fd->node == MIRA_PROC_NODE_FD) {
    size = (size_t)mira_proc_host_fd_limit() + 2U;
  }
  return generic_seek(fd, off, whence, size);
}

static int mira_procfs_readdir_root(struct fd *fd, struct dir_entry *entry) {
  unsigned long index = fd->offset++;
  if (index == 0) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_ROOT;
    strcpy(entry->name, ".");
    return 1;
  }
  if (index == 1) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_ROOT;
    strcpy(entry->name, "..");
    return 1;
  }
  index -= 2;
  if (index >=
      sizeof(g_mira_proc_root_entries) / sizeof(g_mira_proc_root_entries[0])) {
    return 0;
  }
  mira_proc_path_t child = {.node = g_mira_proc_root_entries[index].node,
                            .host_fd = -1};
  entry->inode = mira_proc_inode_for_path(child);
  snprintf(entry->name, sizeof(entry->name), "%s",
           g_mira_proc_root_entries[index].name);
  return 1;
}

static int mira_procfs_readdir_fd(struct fd *fd, struct dir_entry *entry) {
  unsigned long index = fd->offset;
  fd->offset++;
  if (index == 0) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_FD;
    strcpy(entry->name, ".");
    return 1;
  }
  if (index == 1) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_ROOT;
    strcpy(entry->name, "..");
    return 1;
  }

  int limit = mira_proc_host_fd_limit();
  int candidate = (int)index - 2;
  while (candidate < limit && !mira_proc_host_fd_is_valid(candidate)) {
    candidate++;
  }
  if (candidate >= limit) {
    fd->offset = (unsigned long)limit + 2U;
    return 0;
  }
  fd->offset = (unsigned long)candidate + 3U;
  mira_proc_path_t child = {.node = MIRA_PROC_NODE_FD_ENTRY,
                            .host_fd = candidate};
  entry->inode = mira_proc_inode_for_path(child);
  snprintf(entry->name, sizeof(entry->name), "%d", candidate);
  return 1;
}

static int mira_procfs_readdir(struct fd *fd, struct dir_entry *entry) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd == NULL) {
    return _EBADF;
  }
  if (proc_fd->node == MIRA_PROC_NODE_ROOT) {
    return mira_procfs_readdir_root(fd, entry);
  }
  if (proc_fd->node == MIRA_PROC_NODE_FD) {
    return mira_procfs_readdir_fd(fd, entry);
  }
  return _ENOTDIR;
}

static int mira_procfs_close(struct fd *fd) {
  mira_proc_fd_data_t *proc_fd = (mira_proc_fd_data_t *)fd->fs_data;
  if (proc_fd != NULL) {
    free(proc_fd->data);
    free(proc_fd);
    fd->fs_data = NULL;
  }
  return 0;
}

static void mira_proc_rootfs_fill_stat(struct statbuf *stat) {
  memset(stat, 0, sizeof(*stat));
  stat->dev = 0x6d697260;
  stat->inode = 0x6d6972600001ULL;
  stat->mode = S_IFDIR | 0555;
  stat->nlink = 2;
  stat->uid = 0;
  stat->gid = 0;
  stat->blksize = 4096;
  struct timeval now;
  gettimeofday(&now, NULL);
  stat->atime = (dword_t)now.tv_sec;
  stat->mtime = (dword_t)now.tv_sec;
  stat->ctime = (dword_t)now.tv_sec;
  stat->atime_nsec = (dword_t)now.tv_usec * 1000U;
  stat->mtime_nsec = stat->atime_nsec;
  stat->ctime_nsec = stat->atime_nsec;
}

static bool mira_proc_rootfs_lookup_directory(const char *path) {
  if (path == NULL || path[0] == '\0' || strcmp(path, "/") == 0) {
    return true;
  }
  if (path[0] == '/') {
    path++;
  }
  return strcmp(path, "self") == 0;
}

static struct fd *mira_proc_rootfs_open(struct mount *UNUSED(mount),
                                        const char *path, int flags,
                                        int UNUSED(mode)) {
  if (flags & (O_WRONLY_ | O_RDWR_ | O_CREAT_ | O_TRUNC_)) {
    return ERR_PTR(_EROFS);
  }
  if (!mira_proc_rootfs_lookup_directory(path)) {
    return ERR_PTR(_ENOENT);
  }
  extern const struct fd_ops mira_proc_rootfs_fdops;
  struct fd *fd = fd_create(&mira_proc_rootfs_fdops);
  if (fd == NULL) {
    return ERR_PTR(_ENOMEM);
  }
  return fd;
}

static int mira_proc_rootfs_stat(struct mount *UNUSED(mount), const char *path,
                                 struct statbuf *stat) {
  if (!mira_proc_rootfs_lookup_directory(path)) {
    return _ENOENT;
  }
  mira_proc_rootfs_fill_stat(stat);
  return 0;
}

static int mira_proc_rootfs_fstat(struct fd *UNUSED(fd), struct statbuf *stat) {
  mira_proc_rootfs_fill_stat(stat);
  return 0;
}

static int mira_proc_rootfs_getpath(struct fd *UNUSED(fd), char *buf) {
  buf[0] = '\0';
  return 0;
}

static int mira_proc_rootfs_readdir(struct fd *fd, struct dir_entry *entry) {
  unsigned long index = fd->offset++;
  if (index == 0) {
    entry->inode = 0x6d6972600001ULL;
    strcpy(entry->name, ".");
    return 1;
  }
  if (index == 1) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_ROOT;
    strcpy(entry->name, "..");
    return 1;
  }
  if (index == 2) {
    entry->inode = 0x6d6972610000ULL + MIRA_PROC_NODE_ROOT;
    strcpy(entry->name, "self");
    return 1;
  }
  return 0;
}

const struct fd_ops mira_procfs_fdops = {
    .pread = mira_procfs_pread,
    .lseek = mira_procfs_lseek,
    .readdir = mira_procfs_readdir,
    .close = mira_procfs_close,
};

const struct fd_ops mira_proc_rootfs_fdops = {
    .readdir = mira_proc_rootfs_readdir,
};

static const struct fs_ops mira_procfs = {
    .name = "mira-proc-self",
    .magic = 0x6d697261,
    .open = mira_procfs_open,
    .readlink = mira_procfs_readlink,
    .stat = mira_procfs_stat,
    .fstat = mira_procfs_fstat,
    .getpath = mira_procfs_getpath,
};

static const struct fs_ops mira_proc_rootfs = {
    .name = "mira-proc",
    .magic = 0x6d697260,
    .open = mira_proc_rootfs_open,
    .stat = mira_proc_rootfs_stat,
    .fstat = mira_proc_rootfs_fstat,
    .getpath = mira_proc_rootfs_getpath,
};

int mira_ish_hostfs_mount(void) {
  (void)generic_mkdirat(AT_PWD, "/mira", 0755);
  (void)generic_mkdirat(AT_PWD, "/mira/proc", 0755);
  (void)generic_mkdirat(AT_PWD, "/mira/proc/self", 0755);
  (void)generic_rmdirat(AT_PWD, "/mira/host");
  int err = do_mount(&realfs, "/", "/mira", "",
                     MS_READONLY_ | MS_NOSUID_ | MS_NODEV_ | MS_NOEXEC_);
  if (err < 0) {
    return err;
  }
  err = do_mount(&mira_proc_rootfs, "mira-proc", "/mira/proc", "",
                 MS_NOSUID_ | MS_NODEV_ | MS_NOEXEC_);
  if (err < 0) {
    return err;
  }
  return do_mount(&mira_procfs, "mira-proc-self", "/mira/proc/self", "",
                  MS_NOSUID_ | MS_NODEV_ | MS_NOEXEC_);
}
