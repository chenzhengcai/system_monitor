#include "SystemStatsC.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>

#include <sys/sysctl.h>
#include <sys/statvfs.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>

/* ---------------- 通用辅助 ---------------- */
static double clamp01(double v) { if (v < 0) return 0; if (v > 1) return 1; return v; }

static double now_secs(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static uint64_t cached_total_mem(void) {
    static uint64_t m = 0;
    if (m == 0) {
        size_t len = sizeof(m);
        if (sysctlbyname("hw.memsize", &m, &len, NULL, 0) != 0) m = 0;
    }
    return m;
}

/* ---------------- 整体 CPU ---------------- */
static uint64_t g_cpuPrevTotal = 0;
static uint64_t g_cpuPrevIdle  = 0;
static int      g_cpuPrimed = 0;
static double   g_cpuPct = 0;

void sm_cpu_tick(void) {
    natural_t numCpu = 0;
    processor_cpu_load_info_t cpuLoad = NULL;
    mach_msg_type_number_t numCpuInfo = 0;
    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                            &numCpu, (processor_info_array_t *)&cpuLoad, &numCpuInfo);
    if (kr != KERN_SUCCESS) return;

    uint64_t total = 0, idle = 0;
    for (natural_t i = 0; i < numCpu; i++) {
        idle  += cpuLoad[i].cpu_ticks[CPU_STATE_IDLE];
        total += cpuLoad[i].cpu_ticks[CPU_STATE_USER]
               + cpuLoad[i].cpu_ticks[CPU_STATE_SYSTEM]
               + cpuLoad[i].cpu_ticks[CPU_STATE_NICE]
               + cpuLoad[i].cpu_ticks[CPU_STATE_IDLE];
    }
    if (g_cpuPrimed && total > g_cpuPrevTotal) {
        uint64_t dT = total - g_cpuPrevTotal;
        uint64_t dI = idle  - g_cpuPrevIdle;
        if (dT > 0) g_cpuPct = 1.0 - (double)dI / (double)dT;
    }
    g_cpuPrevTotal = total;
    g_cpuPrevIdle  = idle;
    g_cpuPrimed    = 1;
    vm_deallocate(mach_task_self(), (vm_address_t)cpuLoad,
                  (vm_size_t)(numCpuInfo * sizeof(integer_t)));
}

int sm_get_cpu(SMCPUInfo *out) {
    if (!out) return -1;
    out->percent = clamp01(g_cpuPct);
    return 0;
}

/* ---------------- 内存 ---------------- */
int sm_get_memory(SMMemInfo *out) {
    if (!out) return -1;
    uint64_t totalMem = cached_total_mem();
    if (totalMem == 0) return -1;

    vm_size_t pageSize = 4096;
    host_page_size(mach_host_self(), &pageSize);

    vm_statistics64_data_t vmstat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&vmstat, &count) != KERN_SUCCESS) {
        return -1;
    }
    uint64_t used = ((uint64_t)vmstat.active_count
                   + (uint64_t)vmstat.wire_count
                   + (uint64_t)vmstat.compressor_page_count) * (uint64_t)pageSize;
    out->total = totalMem;
    out->used  = used;
    out->percent = clamp01((double)used / (double)totalMem);
    return 0;
}

/* ---------------- 磁盘 ---------------- */
int sm_get_disk(const char *path, SMDiskInfo *out) {
    if (!out || !path) return -1;
    struct statvfs s;
    if (statvfs(path, &s) != 0) return -1;
    uint64_t total = (uint64_t)s.f_blocks * (uint64_t)s.f_frsize;
    uint64_t avail = (uint64_t)s.f_bavail * (uint64_t)s.f_frsize;
    uint64_t used  = (total > avail) ? (total - avail) : 0;
    out->total = total;
    out->free  = avail;
    out->percent = total > 0 ? clamp01((double)used / (double)total) : 0;
    return 0;
}

/* ---------------- 网络 ---------------- */
static uint64_t g_netPrevUp = 0, g_netPrevDown = 0;
static double   g_netPrevTime = 0;
static int      g_netPrimed = 0;
static double   g_netUpBps = 0, g_netDownBps = 0;

static void read_net_counters(uint64_t *up, uint64_t *down) {
    *up = 0; *down = 0;
    struct ifaddrs *ifa = NULL;
    if (getifaddrs(&ifa) != 0) return;
    for (struct ifaddrs *p = ifa; p != NULL; p = p->ifa_next) {
        if (p->ifa_addr == NULL) continue;
        if (p->ifa_addr->sa_family != AF_LINK) continue;  /* 只取链路层 */
        if (p->ifa_name == NULL) continue;
        if (strcmp(p->ifa_name, "lo0") == 0) continue;     /* 排除回环 */
        struct if_data *ifd = (struct if_data *)p->ifa_data;
        if (ifd == NULL) continue;
        *up   += (uint64_t)ifd->ifi_obytes;
        *down += (uint64_t)ifd->ifi_ibytes;
    }
    if (ifa) freeifaddrs(ifa);
}

void sm_net_tick(void) {
    uint64_t up = 0, down = 0;
    read_net_counters(&up, &down);
    double now = now_secs();
    if (g_netPrimed) {
        double dt = now - g_netPrevTime;
        if (dt <= 0) dt = 1e-6;
        if (up   >= g_netPrevUp)   g_netUpBps   = (double)(up   - g_netPrevUp)   / dt;
        if (down >= g_netPrevDown) g_netDownBps = (double)(down - g_netPrevDown) / dt;
    }
    g_netPrevUp   = up;
    g_netPrevDown = down;
    g_netPrevTime = now;
    g_netPrimed   = 1;
}

int sm_get_network(SMNetInfo *out) {
    if (!out) return -1;
    out->up_bps   = (uint64_t)(g_netUpBps   + 0.5);
    out->down_bps = (uint64_t)(g_netDownBps + 0.5);
    return 0;
}