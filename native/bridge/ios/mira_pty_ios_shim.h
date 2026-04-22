#pragma once

#include "mira/pty.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * iOS 平台桥接薄层。
 *
 * Swift 通过 bridging header(桥接头文件) 直接使用这里的 C API。
 * 当前保持为 pty.h 的稳定转发入口, 后续 iOS App 接入时只在这里增加
 * Swift 需要的轻量包装, 不把 UIKit 或 WebKit 依赖放进 native core(原生核心层)。
 */
const char *mira_pty_ios_backend_name(void);

#ifdef __cplusplus
}
#endif
