# SystemMonitor 架构与代码审查报告

> 审查日期：2026-08-04 · 代码规模：648 行（C 211 / Swift 437）· 提交：`e959905`
> 审查环境：Apple Silicon 8 核（4P+4E）/ 24 GB / 页大小 16 KB / Swift 6.3.3 / Retina 2560×1664

---

## 0. 执行摘要

这是一个**小而扎实**的项目。C 采集层在 `-Wall -Wextra -Wconversion -Wshadow` 下**零警告**，clang 静态分析器**零告警**，这在手写 mach/BSD API 的代码里相当难得。分层（C 采集 → Swift 调度 → SwiftUI 视图）意图清晰，`ContentView` / `StatsContent` 拆分以避免全树重建、`monospacedDigit` + 固定宽度防数字抖动这类细节，说明作者对 SwiftUI 渲染开销有真实理解。

但也正因为它以「极低开销 + 准确监控」为卖点，下面几个问题就显得关键 —— 它们**恰好动摇了这两个核心卖点**：

| # | 问题 | 已验证证据 | 优先级 |
|---|------|-----------|--------|
| 1 | 内存口径比活动监视器**低报 15.8 个百分点** | 实测 47.0% vs 62.8%（差 3.78 GB） | **P0** |
| 2 | 环形图动画使应用**每秒有 60% 时间在重绘** | `0.6s` 动画 / `1.0s` 数据周期，代码可推定 | **P0** |
| 3 | **无条件强制注册开机自启**，用户关不掉 | `sfltool dumpbtm` 确认已注册 | **P0** |
| 4 | 登录项指向**源码目录**，`build-app.sh` 会删掉它 | 注册 URL 落在工作区内 | **P0** |
| 5 | 编译产物 `.app` **二进制被提交进 Git** | `git ls-files` 确认 | **P0** |
| 6 | `mach_host_self()` 送权**引用泄漏** | 实测 9000 次调用 → 引用 1→9001 | P1 |
| 7 | Swift 6 严格并发**15 处告警**（未来编译错误） | `-strict-concurrency=complete` 实测 | P1 |
| 8 | 休眠 / 锁屏 / 遮挡时**不降频**，无 `stop()` | 代码审查 | P1 |

> **一句话结论**：代码写得干净，但「监控准不准」和「省不省电」这两件最该做对的事，目前都存在可量化的偏差。建议先做第 1、2、3 项 —— 三项加起来改动不超过 40 行。

---

## 1. 架构全景

### 1.1 当前分层

```
main.swift  (NSApplication.accessory 入口)
    └── AppDelegate            ← 采集启动 + 登录项注册 + 窗口创建 + 定位（职责过多）
            ├── StatsCollector      ← DispatchSourceTimer 1s → 串行队列采集 → main.async 赋值
            │       └── SystemStatsC (C)   ← mach / sysctl / statvfs / getifaddrs
            └── WidgetPanel         ← NSPanel + NSHostingView<AnyView>
                    └── ContentView
                            └── StatsContent  ← 唯一订阅 stats 的节点
                                    ├── RingView × 3
                                    └── NetworkView
```

### 1.2 分层评价

**做得好的地方**（值得保留）：

- **C 层职责单一**：`tick`（推进状态）与 `get`（读取快照）分离，是正确的设计 —— 采样与读取解耦，便于将来做多消费者。
- **视图订阅粒度**：`ContentView` 只依赖 `settings`，把每秒变化的 `stats` 下推到 `StatsContent`，避免了整棵树重建。这个优化很多人想不到。
- **窗口层接管右键**：`WidgetPanel.rightMouseDown` + `WidgetHostView.rightMouseDown` 双保险，覆盖圆环间隙，是对 SwiftUI 命中测试局限的务实绕行。
- **零第三方依赖**：对一个常驻后台的小工具，这是正确取舍。

**结构性问题**：

| 问题 | 说明 | 影响 |
|------|------|------|
| C 层全局可变状态 | 8 个 `static` 全局变量，等于隐式单例 | 无法多实例、无法测试、无法重置 |
| 无抽象边界 | Swift 层直接 `import SystemStatsC` 调 C 函数 | 无法注入 mock，测试必须跑真机采集 |
| `AppDelegate` 职责过载 | 采集 + 登录项 + 窗口 + 定位 四合一 | 45 行里塞了 4 个关注点 |
| 无持久化层 | scale、窗口位置、任何偏好都不存盘 | 每次重启回到默认 |
| 无错误通道 | `sm_get_*` 返回值除 disk 外全部忽略 | 采集失败显示 0%，用户无法分辨 |

---

## 2. 逐模块分析

### 2.1 `SystemStatsC.c` — C 采集层（211 行）

> 整体质量最高的一层。严格警告与静态分析均零告警。以下问题都不是"写错了"，而是"口径 / 契约"层面的。

---

#### **C-1【P0】内存口径与活动监视器差异显著**

**位置**：`SystemStatsC.c:93-95`

```c
uint64_t used = ((uint64_t)vmstat.active_count
               + (uint64_t)vmstat.wire_count
               + (uint64_t)vmstat.compressor_page_count) * (uint64_t)pageSize;
```

**实测证据**（本机 24 GB）：

| 口径 | 数值 | 占比 |
|------|------|------|
| 本项目 `active + wired + compressed` | 11.29 GB | **47.0%** |
| 活动监视器 `(internal - purgeable) + wired + compressed` | 15.07 GB | **62.8%** |
| **差值** | **−3.78 GB** | **−15.8 个百分点** |

**根因**：`active_count` 并不等于「App 内存」。macOS 的 App Memory 口径是 `internal_page_count - purgeable_count`。本机 `inactive` 高达 762,584 页（约 11.6 GB），其中相当部分属于已分配但未活跃的 App 内存，被本公式整体漏掉。

**为什么这是 P0 而不是 P1**：应用的右键菜单里**就有「打开活动监视器」**。用户点开一对比，widget 显示 47%、活动监视器显示 63%，直接击穿信任。一个监控工具报错数字，比不报更糟。

**建议**：

```c
/* 对齐活动监视器 "已使用内存" 口径 */
uint64_t internal  = (uint64_t)vmstat.internal_page_count;
uint64_t purgeable = (uint64_t)vmstat.purgeable_count;
uint64_t app_mem   = (internal > purgeable) ? (internal - purgeable) : 0;
uint64_t used = (app_mem
               + (uint64_t)vmstat.wire_count
               + (uint64_t)vmstat.compressor_page_count) * (uint64_t)pageSize;
```

> 若刻意想显示「内存压力」而非「已用内存」，那是另一个合理设计 —— 但必须在 UI 上改标签（如「压力」），且在 README 写明，否则仍是误导。

---

#### **C-2【P1】`mach_host_self()` 送权引用泄漏**

**位置**：`SystemStatsC.c:48`（cpu）、`:85`（page_size）、`:89`（statistics64）

`mach_host_self()` 每次调用都会**新增一个 send right 引用**，必须配对 `mach_port_deallocate`。当前每 tick 调用 3 次，从不释放。

**实测证据**：

```
baseline                     send-right refs = 1
after 1000 ticks (3000x)     send-right refs = 9001
```

严格 1:1 线性增长，泄漏确认。

**影响评估（实事求是）**：3 refs/秒 = 259,200/天。`mach_port_urefs_t` 为 32 位，理论溢出需约 **45 年**，所以**实际不会导致崩溃**。但它是真实的资源泄漏，会被 Instruments / 代码审查工具标记，且违反 Mach API 契约。属于「不紧急但应当修正」。

**建议**：缓存 host port（页大小同理，见 C-3）：

```c
static mach_port_t cached_host(void) {
    static mach_port_t h = MACH_PORT_NULL;
    if (h == MACH_PORT_NULL) h = mach_host_self();   /* 进程生命周期内持有一份 */
    return h;
}
```

---

#### **C-3【P2】`host_page_size` 每 tick 重复调用，且失败回退值在 Apple Silicon 上错 4 倍**

**位置**：`SystemStatsC.c:84-85`

```c
vm_size_t pageSize = 4096;              // ← Apple Silicon 实际为 16384
host_page_size(mach_host_self(), &pageSize);
```

页大小是进程生命周期内的常量（本机实测 `hw.pagesize = 16384`），每秒查一次纯属浪费。更重要的是：**一旦 `host_page_size` 失败，回退值 4096 会让内存读数直接变成实际值的 1/4**，静默产生离谱错误。

**建议**：改用 `vm_kernel_page_size`（libSystem 导出的全局变量，无需系统调用），或 static 缓存一次并在失败时返回 `-1` 而非用错误默认值。

---

#### **C-4【P2】全局可变状态无同步，线程契约未文档化**

**位置**：`SystemStatsC.c:39-42`、`:117-120`

`g_cpuPct` / `g_netUpBps` / `g_netPrevUp` 等 8 个全局变量既无 `_Atomic` 也无锁。当前**恰好**安全 —— 因为所有调用都来自 `StatsCollector` 的单一串行队列。但：

- 这个约定**只存在于作者脑中**，头文件里一个字没写；
- 任何人从主线程调一次 `sm_get_cpu()` 就构成数据竞争；
- 这正是能力扩展（如菜单栏模式需要另一个消费者）时最容易踩的坑。

**建议**（按投入递增）：
1. 最低成本：在 `SystemStatsC.h` 明确写「所有函数非线程安全，须在同一线程/串行队列调用」；
2. 更稳妥：给标量结果加 `_Atomic`；
3. 最佳：改为上下文句柄式 API（`sm_context_t *ctx`），彻底消除全局状态，同时解锁可测试性。

---

#### **C-5【P2】`statvfs` 同步阻塞 —— 扩展前必须处理**

**位置**：`SystemStatsC.c:105-106`

`statvfs` 是阻塞系统调用。当前固定 `"/"`，本地 APFS，风险低。但 README 已把「磁盘挂载点切换」列为待办 —— **一旦允许选择网络卷（NFS/SMB），挂起的挂载点会把整个采集线程卡死数秒到数十秒**，连带 CPU/内存/网络全部停止刷新。

**建议**：开放挂载点切换之前，先把磁盘采集移到独立队列 + 超时保护，并降低采集频率（磁盘占用 30s 一次足够）。

**附：磁盘口径当前基本正确**。实测 `df /` 显示 460 Gi 总 / 245 Gi 可用 → 本公式得 46.7%，与 `diskutil` 报告的 Container Free 263.5 GB 一致。注意 `/` 在 APFS 上是只读密封系统快照卷，`statvfs` 返回的是**容器级**可用空间 —— 这恰好是用户想看的。唯一欠缺是未扣除 purgeable（可清除）空间。

---

#### **C-6【P3】网络计数器回退时速率卡顿一拍**

**位置**：`SystemStatsC.c:146-147`

```c
if (up >= g_netPrevUp) g_netUpBps = (double)(up - g_netPrevUp) / dt;
```

拔掉 USB 网卡、断开 VPN 时，接口从 `getifaddrs` 列表消失，累计总量**下降**，条件不成立 → 该 tick 保留上一次的速率值。由于 `g_netPrevUp` 在 149 行**无条件更新**，只会卡 1 拍（1 秒）后自愈。

影响很小，但正确做法是显式归零：

```c
if (up >= g_netPrevUp) g_netUpBps = (double)(up - g_netPrevUp) / dt;
else                   g_netUpBps = 0;   /* 接口移除 / 计数回绕 */
```

---

#### **C-7【P3】无错误上报通道**

所有 `sm_get_*` 失败时返回 `-1`，但 Swift 层只检查了 disk（`StatsCollector.swift:48`），CPU / 内存 / 网络的返回值**被完全忽略**。采集失败时 UI 显示 0%，用户无法区分「真的空闲」和「采集挂了」。

**建议**：`StatsCollector` 增加 `isStale` 状态，UI 上用灰色环或 `--` 表示不可用。

---

### 2.2 `StatsCollector.swift` — 调度层（68 行）

---

#### **S-1【P1】Swift 6 严格并发 5 处告警**

**实测**（`swift build -Xswiftc -strict-concurrency=complete`）：

```
StatsCollector.swift:56  capture of 'self' with non-Sendable type 'StatsCollector?' in a '@Sendable' closure
StatsCollector.swift:60  reference to captured var 'mi' in concurrently-executing code
StatsCollector.swift:61  reference to captured var 'mi' in concurrently-executing code
StatsCollector.swift:63  reference to captured var 'di' in concurrently-executing code
StatsCollector.swift:64  reference to captured var 'di' in concurrently-executing code
StatsCollector.swift:65  reference to captured var 'ni' in concurrently-executing code
```

**值得注意的是**：代码已经对百分比做了正确处理 —— 先取出 `newCpu` / `newMem` / `newDisk` 三个不可变标量再进闭包（`:51-53`）。但对 `mi` / `di` / `ni` 三个结构体却直接在闭包里访问。**同一个函数里两种写法并存**，说明作者知道该怎么做，只是漏了一半。

**建议**：定义不可变快照值类型，一次性传入：

```swift
struct StatsSnapshot: Sendable {
    let cpu, mem, disk: Double
    let memUsed, memTotal, diskTotal, diskFree, netUp, netDown: UInt64
}
```

这同时解决了 S-2。

---

#### **S-2【P1】8 个 `@Published` 每秒各发一次事件，且无变化也刷新**

**位置**：`StatsCollector.swift:9-18`、`:58-66`

每 tick 触发 **8 次** `objectWillChange`。SwiftUI 会在同一 runloop 内合并成一次视图更新，所以**不是 8 倍重绘**（这点要说清楚，避免夸大）—— 但 Combine 管线的发布/订阅开销确实是 8 倍。

更实际的浪费是：**磁盘占用几分钟才变一次，`memTotal` / `diskTotal` 几乎永不变**，却每秒无条件赋值触发失效。

**建议**：合并为单个 `@Published var snapshot: StatsSnapshot`，并加变化判断：

```swift
let next = StatsSnapshot(...)
DispatchQueue.main.async { [weak self] in
    guard let self, next != self.snapshot else { return }   // 需 Equatable
    self.snapshot = next
}
```

> 项目 `platforms` 已声明 `.macOS(.v14)`，可直接用 **Observation 框架**（`@Observable`）替代 `ObservableObject`，它天生按字段粒度追踪，比手工合并更优雅。

---

#### **S-3【P1】无 `stop()`、不感知休眠 / 锁屏 / 遮挡**

**位置**：`StatsCollector.swift:23-33`

`lightTimer` 一旦 `resume()` 就永不停止，类上**没有 `stop()` 方法**。这意味着：

- 屏幕休眠时仍在全速采集；
- 锁屏时仍在全速采集；
- 面板被全屏窗口完全遮挡时，**仍在跑 3 个环的动画**（见 V-1）。

这直接违背 README「极低开销、空闲 CPU 几乎为 0」的承诺。

**建议**：

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.willSleepNotification, ...)      // → suspend
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, ...)        // → resume
// 面板遮挡：NSWindow.occlusionState / didChangeOcclusionStateNotification
```

**这是"省电"卖点上投入产出比最高的一项修改。**

---

#### **S-4【P2】采集频率硬编码，各指标未分级**

`1.0s` 写死在 `:29`。但四类指标的合理频率差异巨大：

| 指标 | 合理频率 | 当前 |
|------|---------|------|
| 网络速率 | 1s | 1s ✓ |
| CPU | 1–2s | 1s ✓ |
| 内存 | 2–5s | 1s |
| 磁盘 | **30–60s** | 1s ← 浪费 |

**建议**：分级调度，磁盘单独一个低频定时器。

---

### 2.3 `WidgetPanel.swift` — 窗口层（142 行）

---

#### **W-1【P1】`resizeKeepingTopRight` 可能读到旧布局尺寸**

**位置**：`WidgetPanel.swift:43-49`、`:115-123`

```swift
settings.$scale
    .removeDuplicates()
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.resizeKeepingTopRight() }
```

`resizeKeepingTopRight` 依赖 `hosting.fittingSize`。但 sink 触发时，SwiftUI **未必已经用新 scale 完成布局**，`fittingSize` 可能仍是旧值 → 窗口尺寸与内容不匹配（内容被裁剪或留白）。

**建议**（二选一）：
1. 调用前强制布局：`hosting.layoutSubtreeIfNeeded()`；
2. **更好**：尺寸是纯函数，直接算 —— `width = 224 * scale`，无需问 SwiftUI。这同时消除了对布局时序的隐式依赖。

---

#### **W-2【P2】窗口位置与 scale 完全不持久化**

用户精心拖到某个位置、调成「小 50%」，**重启全部丢失**，回到右上角 100%。

对一个「开机自启、常驻桌面」的工具来说，这是**日常体验上最刺痛的缺失** —— 每次重启都要重新调一遍。

**建议**：`UserDefaults` 保存 `frame.origin` + `scale`，启动时恢复并做屏幕边界钳制。

---

#### **W-3【P2】多显示器 / 分辨率变化未处理**

**位置**：`AppDelegate.swift:35-42`

只在启动时读一次 `NSScreen.main`。外接显示器拔出后，面板可能停留在**已不存在的屏幕坐标**上，用户看不见也拖不回来，只能重启应用。

**建议**：监听 `NSApplication.didChangeScreenParametersNotification`，检测面板是否仍在任一屏幕的 `visibleFrame` 内，否则拉回主屏。

---

#### **W-4【P2】编译告警：`override` 冗余**

**位置**：`WidgetPanel.swift:129`

```
warning: 'override' is implied when overriding a required initializer
```

**这是当前唯一的编译告警**，一行即可修复（删掉 `override`）。保持零告警对小项目很有价值。

---

#### **W-5【P3】`AnyView` 类型擦除**

**位置**：`WidgetPanel.swift:13-18`

`AnyView` 抹掉静态类型，削弱 SwiftUI 的结构化标识与差分优化。此处视图树很小，实际影响有限，但没有必要 —— 改成泛型 `NSHostingView<ContentView>` 即可。

---

#### **W-6【P3】`canBecomeKey = true` 与「不抢焦点」表述冲突**

`WidgetPanel.swift:52` 返回 `true`，配合 `.nonactivatingPanel`，意味着面板**可以成为 key window**。README 声称「不抢焦点」。右键菜单其实不需要 key 状态。建议评估改回 `false`，或修正 README 表述。

---

#### **W-7【P3】菜单每次重建 + 档位硬编码在 UI 层**

`showContextMenu` 每次右键都 `NSMenu()` 新建；三档 scale 的标签与数值硬编码在 `:68-70`。建议档位由 `WidgetSettings` 的枚举驱动，UI 只做渲染。

---

#### **W-8【P3】`openActivityMonitor` 静默失败**

`guard let ... else { return }` —— 用户点了没反应，也不知道为什么。`completionHandler: nil` 同样吞掉了启动错误。

---

### 2.4 视图层 — `ContentView` / `RingView` / `NetworkView`

---

#### **V-1【P0】环形图动画是全应用最大的 CPU 消耗源**

**位置**：`RingView.swift:23`

```swift
.animation(.easeInOut(duration: 0.6), value: progress)
```

**数据每 1.0 秒变化一次，动画时长 0.6 秒** —— 意味着应用**每秒有 60% 的时间处于动画状态**，以显示器刷新率持续重绘 3 个环形描边 + 3 组文字。在 60 Hz 下约等于每秒 36 帧实际绘制；Retina 2560×1664 下每帧还要走 Core Animation 合成。

这是一个**常驻后台、宣称「空闲 CPU 几乎为 0」**的工具 —— 而它实际上大部分时间都在画动画。README 里为了省 CPU 特意移除了进程枚举（见 README 末尾），却在这里把省下的开销加倍还了回去。

**建议**（按效果排序）：

1. **缩短动画**至 `0.25s`，动画占空比从 60% 降到 25%；
2. **小变化跳过动画** —— CPU 抖动 1% 不值得播 0.6 秒动画：
   ```swift
   .animation(abs(progress - lastProgress) > 0.03 ? .easeInOut(duration: 0.25) : nil,
              value: progress)
   ```
3. 配合 S-3，**面板被遮挡 / 屏幕休眠时彻底停止**；
4. 进阶：三个环改用单个 `Canvas` 绘制，减少视图树与图层数量。

> 这是整个项目**性价比最高的性能优化** —— 改一行常数即可见效。

---

#### **V-2【P1】布局魔数散落三处且需手工同步**

| 数值 | 出现位置 | 含义 |
|------|---------|------|
| `224` | `AppDelegate.swift:31`、`ContentView.swift:16` | 面板宽度（两处重复） |
| `52` / `16` | `ContentView.swift:30-42` | 环直径 / 环间距 |
| `188` | `NetworkView.swift:16` | **手工算出的** `3×52 + 2×16` |

改任意一个环的尺寸，`188` 就会错位，而编译器不会报错 —— 只会在界面上看到网络行和圆环行对不齐。

**建议**：抽出统一常量，让派生值自动计算：

```swift
enum Metrics {
    static let ringSize: CGFloat = 52
    static let ringGap:  CGFloat = 16
    static let ringCount = 3
    static var ringRowWidth: CGFloat { ringSize * CGFloat(ringCount) + ringGap * CGFloat(ringCount - 1) }
    static let padding: CGFloat = 10
    static var panelWidth: CGFloat { ringRowWidth + padding * 2 + 16 }
}
```

---

#### **V-3【P2】配色语义不一致，磁盘 / 内存失去告警能力**

**位置**：`ContentView.swift:33-42`、`:48-52`

CPU 有绿 / 黄 / 红三档阈值着色，**内存固定 orange、磁盘固定 purple**。结果是：磁盘用到 98% 依然是一片紫色，用户完全得不到警示 —— 而磁盘满恰恰是**后果最严重**的一种资源耗尽。

**建议**：`ringColor()` 统一应用于三个环，或至少为磁盘 / 内存设置各自的告警阈值（磁盘 >90% 转红）。

---

#### **V-4【P3】`NetworkView` 单位换算硬编码且进制存疑**

**位置**：`NetworkView.swift:47-54`

- 字符串硬编码 `B/s` / `KB/s`，未走 `ByteCountFormatter`，无本地化；
- 使用 1024 进制。网络速率业界惯例是 **1000 进制**（与 ISP 标称、活动监视器「网络」标签页一致），存储才用 1024。当前混用，数值会比活动监视器略小。

---

#### **V-5【P3】`trim` 的 `0.0001` 魔数缺注释**

`RingView.swift:20` 的 `max(0.0001, ...)` 是为规避 progress 为 0 时的渲染异常，属合理 hack，但应加一行注释说明，否则后人会当成 bug 顺手"修掉"。

---

### 2.5 `WidgetSettings.swift` — 设置层（11 行）

#### **X-1【P1】贫血模型，不持久化，无扩展空间**

整个类只有一个 `scale`，且不存盘。所有 P2 级体验改进（窗口位置、刷新频率、告警阈值、配色、显示项开关）都**没有落脚点**。

**建议**：先扩成带持久化的配置模型，后续所有功能才有地方挂：

```swift
@Observable final class WidgetSettings {
    var scale: Double        { didSet { persist() } }
    var refreshInterval: TimeInterval
    var showNetwork: Bool
    var diskPath: String
    var alertThreshold: Double
    // UserDefaults 读写 + 版本迁移
}
```

---

### 2.6 `AppDelegate.swift` / `main.swift` — 生命周期（53 行）

---

#### **A-1【P0】无条件强制注册开机自启，用户无法关闭**

**位置**：`AppDelegate.swift:22-28`

```swift
private func registerLoginItem() {
    do { try SMAppService.mainApp.register() }
    catch { print(...) }
}
```

**每次启动都无条件 `register()`**。用户在「系统设置 → 登录项」里手动关掉，下次启动又被**悄悄加回来**。

这是**流氓软件的典型行为模式** —— 即便本意良善（作者自用工具），也应当立即修正。用户对自己机器的启动项拥有最终控制权。

**实测确认已注册**：
```
Name: SystemMonitor
Identifier: 2.com.personal.systemmonitor
URL: file:///Users/chenzhengcai/coding/system_monitor/SystemMonitor.app/
```

**建议**：

```swift
// 1) 只在从未注册过时注册（用 UserDefaults 记录"已询问过"）
// 2) 右键菜单加「开机自启」勾选项，双向同步
switch SMAppService.mainApp.status {
case .notRegistered where !hasAskedBefore: try? SMAppService.mainApp.register()
default: break   // 尊重用户的选择，包括 .notFound / 用户主动禁用
}
```

---

#### **A-2【P0】登录项指向源码目录，`build-app.sh` 会摧毁它**

承 A-1 的实测结果：注册的路径是 `/Users/chenzhengcai/coding/system_monitor/SystemMonitor.app/` —— **开发工作区内部**。

而 `build-app.sh:20` 是：

```bash
rm -rf "${APP}"       # ← 每次重新打包都会删掉登录项指向的那个 bundle
```

**后果链条**：
1. 每次 `./build-app.sh`，登录项指向的 bundle 被删除后重建，签名变化，注册可能失效；
2. 用户一旦移动或删除代码仓库 → 开机自启静默失败；
3. 系统设置里残留一条指向不存在路径的僵尸条目，且**卸载应用不会自动清理**。

**建议**：`build-app.sh` 增加安装步骤（或至少提示）把 `.app` 拷到 `/Applications` 再运行；注册前校验 `Bundle.main.bundlePath` 是否位于合理位置。

---

#### **A-3【P1】严格并发 6 处告警集中于此**

```
AppDelegate.swift:32  call to main actor-isolated initializer in a synchronous nonisolated context
AppDelegate.swift:37  main actor-isolated property 'frame' can not be referenced from a nonisolated context
AppDelegate.swift:38  call to main actor-isolated instance method 'setFrameOrigin' ...
AppDelegate.swift:41  call to main actor-isolated instance method 'center()' ...
AppDelegate.swift:43  call to main actor-isolated instance method 'orderFrontRegardless()' ...
AppDelegate.swift:32  sending 'self.stats' risks causing data races      ← Swift 6 下为错误
AppDelegate.swift:32  sending 'self.settings' risks causing data races   ← Swift 6 下为错误
```

**修复成本极低**：给 `AppDelegate` 加 `@MainActor` 标注即可消除绝大部分。建议现在就做，避免将来升级 Swift 6 语言模式时集中爆发。

---

#### **A-4【P2】`print` 而非 `os.Logger`**

**位置**：`AppDelegate.swift:26`

打包成 `.app` 双击运行后，`print` 输出**无处可见**（没有终端）。这条精心写的错误提示，在最需要它的场景下恰恰看不到。

**建议**：`Logger(subsystem: "com.personal.systemmonitor", category: "lifecycle")`，可通过 Console.app 查看。

---

#### **A-5【P2】职责过载 + 无退出清理**

- 45 行里塞了采集启动、登录项、窗口创建、屏幕定位四个关注点；
- `disableSuddenTermination()` 调用后无对应恢复；
- 退出时不提供「注销开机自启」的途径。

**建议**：拆出 `PanelController`（窗口生命周期）与 `LoginItemService`（登录项状态管理）。

---

### 2.7 构建与工程化

---

#### **B-1【P0】编译产物二进制被提交进 Git，且无 `.gitignore`**

**实测 `git ls-files`**：

```
SystemMonitor.app/Contents/Info.plist
SystemMonitor.app/Contents/MacOS/SystemMonitor        ← Mach-O 可执行文件在版本库里
SystemMonitor.app/Contents/_CodeSignature/CodeResources
```

且**项目根目录没有 `.gitignore`**，`.DS_Store` 已在污染工作区。

**问题**：
- 每次重新打包都会产生一个全新的二进制 diff，仓库体积持续膨胀且无法压缩；
- 二进制无法 code review —— 从供应链安全角度，版本库里的可执行文件是**不可审计**的；
- `.build/` 目录目前只是碰巧没被 `git add`，随时可能误入。

**建议（立即执行）**：

```bash
git rm -r --cached SystemMonitor.app
printf '.build/\n*.app/\n.DS_Store\n' > .gitignore
git add .gitignore && git commit -m "chore: 忽略构建产物与系统文件"
```

---

#### **B-2【P1】零测试，且无测试 target**

648 行代码，**0 个测试**。而这个项目里有大量**极易测试的纯逻辑**：

| 可测目标 | 位置 |
|---------|------|
| `clamp01` 边界 | `SystemStatsC.c:21` |
| 百分比计算（含除零） | `sm_get_disk` / `sm_get_memory` |
| 网络 delta 与回退处理 | `sm_net_tick` |
| 单位换算 B/KB/MB/GB 边界 | `NetworkView.format` |
| CPU 平滑滤波收敛性 | `StatsCollector:58` |

**建议**：加 `SystemMonitorTests` target，从 `NetworkView.format` 和 `clamp01` 入手 —— 这两个不需要任何 mock，10 分钟能写出第一批用例。

> 注意：要测 C 层的采集逻辑，必须先解决 C-4（全局状态）—— 这两项是相互关联的，建议一起做。

---

#### **B-3【P2】`build-app.sh` 吞掉 codesign 真实错误**

**位置**：`build-app.sh:26-28`

```bash
codesign --force --sign - "${APP}" 2>/dev/null \
  || codesign --force --deep --sign - "${APP}" 2>/dev/null \
  || echo "  (codesign 跳过 — 可能未勾选命令行工具权限)"
```

三级兜底 + `2>/dev/null` 会把**任何**签名失败伪装成"权限问题，已跳过"，真实原因被完全掩埋。另外 `--deep` 已被 Apple 标记为 **deprecated**，不应在新代码中使用。

**建议**：保留 stderr，去掉 `--deep`，签名失败时明确报错并非零退出。脚本其余部分（`set -euo pipefail`、`cd "$(dirname "$0")"`）写得规范，值得保持。

---

#### **B-4【P2】`Package.swift` 工具链版本滞后**

- 声明 `swift-tools-version: 5.9`，实际工具链为 **Swift 6.3.3**；
- 未配置任何 `swiftSettings`，严格并发检查默认关闭 —— 这正是 15 处告警未被察觉的原因。

**建议**：渐进式启用，避免一次性引入大量错误：

```swift
swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
```

---

#### **B-5【P2】`Info.plist` 缺少分发相关键 & 无加固运行时**

缺 `NSHumanReadableCopyright`、`LSApplicationCategoryType`；无 entitlements、无 Hardened Runtime、无 App Sandbox。

**本地自用完全可接受**（这也是当前定位），但需明确：ad-hoc 签名 + 未公证的 `.app` **无法分发** —— 其他人下载后会被 Gatekeeper 拦截。若将来考虑分享，这是必经门槛。

---

#### **B-6【P3】`linkedFramework("ServiceManagement")` 冗余**

`Package.swift:19`。`import ServiceManagement` 已触发自动链接，显式声明非必需（无害，可保留）。

---

## 3. 能力扩展分析

> 评估维度：**用户价值**（对日常使用的实际提升）× **实现可行性**（API 可得性与工作量）

### 3.1 推荐优先落地（高价值 × 高可行）

| 扩展点 | 价值 | 可行性 | 说明 |
|--------|------|--------|------|
| **磁盘 I/O 读写速率** | ★★★★★ | ★★★☆☆ | **当前最明显的能力缺口** —— 有网络速率却没有磁盘速率，语义上不对称。`IOKit` 的 `IOBlockStorageDriver` 统计属公开 API |
| **历史曲线 / sparkline** | ★★★★★ | ★★★★★ | 环形图只显示瞬时值，看不出趋势。仅需环形缓冲区（60 个点）+ SwiftUI `Path`，**纯前端改动，无新系统 API** |
| **阈值告警** | ★★★★☆ | ★★★★★ | 承 V-3，磁盘/内存超阈值变红 + 可选通知。改动极小，价值立竿见影 |
| **菜单栏模式（NSStatusItem）** | ★★★★☆ | ★★★★☆ | 相当多用户偏好菜单栏而非悬浮窗。现有 `StatsCollector` 可直接复用，只需新增一个展示宿主 —— **但需先解决 C-4 的多消费者线程问题** |
| **电池健康与功耗** | ★★★★☆ | ★★★★☆ | 笔记本刚需。`IOPMPowerSource` / `IOPSCopyPowerSourcesInfo` 均为公开 API，无权限门槛 |

### 3.2 值得做但需谨慎

| 扩展点 | 价值 | 可行性 | 风险提示 |
|--------|------|--------|---------|
| **多挂载点 / 多磁盘** | ★★★☆☆ | ★★★★☆ | **必须先做 C-5**（阻塞保护），否则网络卷会冻结整个采集 |
| **Top 进程列表回归** | ★★★☆☆ | ★★★★☆ | README 说明当初正是为省 CPU 而移除。建议改为**按需采集**（悬停/点击时才 `proc_listallpids`），而非常驻轮询 |
| **每网卡分别统计** | ★★★☆☆ | ★★★★★ | `getifaddrs` 已有 `ifa_name`，区分 Wi-Fi / 以太网 / VPN 几乎零成本 |
| **GPU 使用率** | ★★★☆☆ | ★★☆☆☆ | `IOAccelerator` 相关接口稳定性一般，Apple Silicon 上口径复杂 |
| **温度 / 风扇转速** | ★★★★☆ | ★★☆☆☆ | 用户很想要，但 Apple Silicon 上 SMC 读取依赖**私有 API**，跨版本易失效，且无法上架 |

### 3.3 锦上添花

设置窗口（承 X-1）、透明度 / 配色自定义、全局快捷键显隐、历史数据导出。

### 3.4 扩展前的**前置依赖**

> 这一点很重要：上面多数扩展都会被现有架构绊住。

```
C-4 (消除全局状态)  ──→ 菜单栏模式 / 多消费者 / 单元测试
C-5 (阻塞保护)      ──→ 多挂载点切换
X-1 (配置模型)      ──→ 设置窗口 / 阈值告警 / 频率可调 / 配色
S-1 (Snapshot 值类型) ──→ 历史曲线（需要值语义的时间序列）
```

**建议顺序**：先做 X-1 + S-1（成本低、解锁多），再动扩展功能。

---

## 4. 优先级路线图

### 阶段一：正确性与信任（建议立即，约 40 行改动）

| 编号 | 事项 | 预估 |
|------|------|------|
| C-1 | 修正内存口径，对齐活动监视器 | 5 行 |
| V-1 | 动画时长 0.6s → 0.25s + 小变化跳过 | 3 行 |
| A-1 | 开机自启改为「仅首次注册」+ 菜单开关 | 15 行 |
| B-1 | `git rm --cached` 产物 + 补 `.gitignore` | 2 条命令 |
| W-4 | 消除唯一编译告警 | 1 行 |

> 这五项做完，「监控准确」「省电」「不流氓」「仓库干净」四个基本盘就稳了。

### 阶段二：健壮性与工程化

- S-3 休眠 / 遮挡时暂停采集与动画（**省电卖点的关键**）
- S-1 + S-2 引入 `StatsSnapshot`，合并 `@Published`，消除并发告警
- A-3 `AppDelegate` 加 `@MainActor`
- C-2 缓存 host port，消除引用泄漏
- W-2 持久化窗口位置与 scale（**日常体验提升最明显**）
- B-2 建立测试 target，先覆盖纯函数
- A-2 + B-3 打包脚本安装到 `/Applications`，不再吞错误

### 阶段三：架构演进（为扩展铺路）

- C-4 C 层改为上下文句柄式 API，消除全局状态
- X-1 配置模型 + `UserDefaults` 持久化
- A-5 拆分 `PanelController` / `LoginItemService`
- V-2 统一 `Metrics` 常量
- W-3 多显示器适配
- B-4 升级工具链版本 + 开启严格并发

### 阶段四：能力扩展

按 3.1 顺序：历史曲线 → 阈值告警 → 磁盘 I/O → 菜单栏模式 → 电池。

---

## 5. 附录：本次审查的验证方法

所有结论均基于实际执行，而非纯代码阅读：

| 验证项 | 方法 | 结果 |
|--------|------|------|
| C 层代码质量 | `cc -Wall -Wextra -Wconversion -Wshadow` | **0 警告** |
| C 层潜在缺陷 | `clang --analyze` | **0 告警** |
| Release 构建 | `swift build -c release` | 成功，1 警告 |
| 严格并发合规 | `swift build -Xswiftc -strict-concurrency=complete` | **15 警告** |
| mach 端口泄漏 | 自建探针，`mach_port_get_refs` 计数 | 9000 次 → 9001 引用，**泄漏确认** |
| 内存口径偏差 | 自建对比程序，双口径同时计算 | **47.0% vs 62.8%** |
| 磁盘口径 | 对比 `df -h /` 与 `diskutil info /` | 46.7%，**口径正确** |
| 登录项状态 | `sfltool dumpbtm` | 已注册，**路径指向源码目录** |
| 版本库卫生 | `git ls-files` | **二进制已入库，无 .gitignore** |
| 硬件参数 | `sysctl` / `system_profiler` | 8 核 / 24 GB / 页 16 KB / Retina |

> 说明：构建时需 `--disable-sandbox`（审查环境限制导致 SwiftPM 无法嵌套沙箱），与项目本身无关。
