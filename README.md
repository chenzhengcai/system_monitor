# SystemMonitor — macOS 系统监控悬浮小插件

原生 Swift + SwiftUI,零第三方依赖。屏幕右上角悬浮置顶、**背景透明**的小面板,
实时显示 **CPU / 内存 / 磁盘** 三个小环形图(中心百分比),以及 **网络上传 / 下载实时速率**。

## 功能
- 三个小环形图:CPU、内存、磁盘(默认根目录 `/`,暂不支持切换),中心显示百分比
- 网络:实时上行 / 下行速率(单位自适应 B/s → KB/s → MB/s → GB/s)
- 背景全透明;右键面板 →「退出软件」
- 悬浮置顶、跨桌面常驻、可拖动、不进 Dock、不抢焦点
- 开机自启(打包为 `.app` 后自动注册到登录项)
- 极低开销:常驻内存约几十 MB、空闲 CPU 几乎为 0(1s 刷新几项轻量指标,一阶平滑)

## 环境要求
- macOS 14+(本机 macOS 26 OK)
- Swift 6.3.1 + Command Line Tools(无需完整 Xcode.app)

## 构建 & 运行

### 开发期直接跑
```bash
cd SystemMonitor
swift build          # 调试构建
swift run SystemMonitor
```
> 直接 `swift run` 时为裸二进制,「开机自启」注册会打印失败信息,属正常;
> 界面与采集全部可用。右键面板可退出。

### 打包成可双击的 .app
```bash
cd SystemMonitor
./build-app.sh       # 产出 SystemMonitor.app,ad-hoc 签名
open SystemMonitor.app
```

## 开机自启
打包并 `open SystemMonitor.app` 后,应用通过 `SMAppService.mainApp` 注册为登录项。
若系统未自动启用,去「系统设置 > 通用 > 登录项与扩展」把 *SystemMonitor* 打开即可。

## 架构
```
Sources/
├── SystemStatsC/              # C 桥接层:mach / statvfs / getifaddrs
│   ├── include/{SystemStatsC.h, module.modulemap}
│   └── SystemStatsC.c         # CPU / 内存 / 磁盘 / 网络 四项采集
└── SystemMonitor/             # Swift UI + 调度
    ├── main.swift             # NSApplication 入口(accessory,不进 Dock)
    ├── AppDelegate.swift      # 启动采集、注册登录项、显示面板
    ├── WidgetPanel.swift      # 悬浮 NSPanel(borderless / floating / 透明 / 无阴影)
    ├── StatsCollector.swift   # 后台定时器:1s 刷新,主线程更新
    ├── ContentView.swift      # 三个环 + 网络条 + 右键退出菜单
    ├── RingView.swift         # Circle.trim 自绘 donut + 中心百分比
    └── NetworkView.swift      # ↑下载 ↓上传 实时速率
```

## 采集方式
- CPU:`host_processor_info(PROCESS_CPU_LOAD_INFO)` 两次求差
- 内存:`host_statistics64(HOST_VM_INFO64)`,used = active + wired + compressed
- 磁盘:`statvfs("/"`)
- 网络:`getifaddrs` 链路层计数,排除 lo0,两次求差

> 进程枚举与 Top 列表已按需移除以进一步降低 CPU 开销。如需恢复占用最高的进程展示,
> 可在 `SystemStatsC` 中重新接入 `proc_listallpids`/`proc_pidinfo`。