import Foundation
import SystemStatsC

/// 采集调度器：后台轮询 SystemStatsC，主线程刷新 @Published。
/// CPU/内存/磁盘/网速 1s 刷新一阶平滑后展示。
/// （按优化要求：已移除进程枚举采样与 Top 列表，进一步降低 CPU 开销。）
final class StatsCollector: ObservableObject {

    @Published var cpuPercent: Double = 0
    @Published var memPercent: Double = 0
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var diskPercent: Double = 0
    @Published var diskTotal: UInt64 = 0
    @Published var diskFree: UInt64 = 0
    let diskPath: String = "/"   // 固定根目录，暂不支持切换
    @Published var netUp: UInt64 = 0
    @Published var netDown: UInt64 = 0

    private let queue = DispatchQueue(label: "stats.collector", qos: .utility)
    private var lightTimer: DispatchSourceTimer?

    func start() {
        // 打底采样（结果丢弃，用于建立 delta 基准）
        sm_cpu_tick()
        sm_net_tick()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.onTick() }
        t.resume()
        lightTimer = t
    }

    // MARK: - private

    private func onTick() {
        sm_cpu_tick()
        sm_net_tick()

        var ci = SMCPUInfo()
        var mi = SMMemInfo()
        var di = SMDiskInfo()
        var ni = SMNetInfo()

        sm_get_cpu(&ci)
        sm_get_memory(&mi)
        let diskOk = diskPath.withCString { p in sm_get_disk(p, &di) == 0 }
        sm_get_network(&ni)

        let newCpu  = ci.percent
        let newMem  = mi.percent
        let newDisk = diskOk ? di.percent : 0

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // CPU 做一阶低通平滑，减弱每秒抖动
            self.cpuPercent  = max(0, min(1, self.cpuPercent * 0.6 + newCpu * 0.4))
            self.memPercent  = max(0, min(1, newMem))
            self.memUsed     = mi.used
            self.memTotal    = mi.total
            self.diskPercent = max(0, min(1, newDisk))
            self.diskTotal   = diskOk ? di.total : 0
            self.diskFree    = diskOk ? di.free : 0
            self.netUp       = ni.up_bps
            self.netDown     = ni.down_bps
        }
    }
}