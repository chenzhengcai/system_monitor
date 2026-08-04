#ifndef SYSTEMSTATSC_H
#define SYSTEMSTATSC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 整体 CPU（0..1）。sm_cpu_tick 刷新并内部求差，sm_get_cpu 取最近一次结果 */
typedef struct {
    double percent;
} SMCPUInfo;

/* 内存（单位字节）。
 * used = (internal - purgeable) + wired + compressed  ← 对齐活动监视器「内存」口径
 * percent = used / total */
typedef struct {
    uint64_t total;
    uint64_t used;
    double   percent;
} SMMemInfo;

/* 磁盘（单位字节）。free = 可用；percent = used/total */
typedef struct {
    uint64_t total;
    uint64_t free;
    double   percent;
} SMDiskInfo;

/* 网络：上传/下载 字节每秒（两次 sm_net_tick 之间求差） */
typedef struct {
    uint64_t up_bps;
    uint64_t down_bps;
} SMNetInfo;

/* CPU */
void sm_cpu_tick(void);
int  sm_get_cpu(SMCPUInfo *out);

/* 内存 */
int  sm_get_memory(SMMemInfo *out);

/* 磁盘：按挂载路径（固定 "/") */
int  sm_get_disk(const char *path, SMDiskInfo *out);

/* 网络 */
void sm_net_tick(void);
int  sm_get_network(SMNetInfo *out);

#ifdef __cplusplus
}
#endif

#endif /* SYSTEMSTATSC_H */