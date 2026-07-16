# 架构与原生宿主

`yanxu-macos-ui` 分成三层：言序对象模型、稳定传输协议和 Swift 原生宿主。

## 描述层

言序代码构建一棵对象图：

```text
麦金塔应用
  运行会话
  场景
    窗口 / 设置 / 菜单栏 / 文档
      根视图
        子视图
  菜单
    命令
  异步请求
    打开 / 保存 / 窗口 / 设置 / 文档
```

视图根类只保存共同树行为。文本、按钮、输入控件和容器由不同子类表达，动作与修饰器也是独立对象。工厂函数返回具体类，因而言序可以在编译期检查 `设内容`、`当文本变化`、`设值`、`设间距` 等控件专用操作。

对象图最终投影为 JSON。当前 schema 为 `dev.yanxu.mac-ui.v2`，包含状态表和 revision；宿主继续解码 v1 快照以兼容旧应用。`kind` 和通用 property bag 属于传输层，而不是公开对象模型。新增原生控件仍需有对应 SwiftUI renderer。

### 源码职责

言序源码按领域职责拆分：

| 模块 | 职责 |
| --- | --- |
| `基础.yx` | 标识、尺寸、文字和属性复制等共享边界 |
| `动作.yx` | 用户意图值对象及动作名解析 |
| `修饰器.yx` | modifier 策略基类与具体修饰器 |
| `状态.yx` | 具体状态子类、Binding 引用和值类型校验 |
| `视图.yx` | 必须共享继承链的视图、控件和容器 |
| `应用模型.yx` | 事件、窗口、命令、菜单和应用聚合根 |
| `请求.yx` | 请求继承树、结果对象与 request ID 关联 |
| `运行时.yx` | 运行会话、原生模块生命周期与双向调用 |
| `言序麦金塔界面.yx` | 不含领域实现的稳定公共门面 |

`视图.yx` 中的继承树暂时保持在同一模块，因为言序 1.1 尚不支持模块限定类型和跨模块 `承`/`纳`。强行继续拆分会把具体类型退化为 `任意`，反而破坏静态检查。语言侧改进已记录在 [yanxulang/yanxu#14](https://github.com/yanxulang/yanxu/issues/14)；支持后可再把控件族拆成独立模块，公共门面无需变化。

## 事件与更新闭环

```text
AppKit / SwiftUI 控件
  -> ABI v2 callback_post（binding、revision、值）
  -> 言序宿主有界队列
  -> owner-thread pump
  -> 状态对象回写
  -> 应用.当事件 处理器
  -> 自动状态 patch
  -> SwiftUI 可观察状态存储
```

`run` 在应用事件循环期间保留回调句柄，退出时成对释放。控件事件发生后宿主投递并立即泵送。`patch` 按 revision 更新既有状态，拒绝增删状态或改变类型；`update` 接收完整应用快照；`request` 发起窗口或异步系统面板操作，结果继续走同一持久回调。所有双向入口都只能在言序所有者主线程调用。

## 宿主层

`native/` 是一个 Swift Package，产物为动态库：

```text
libYanxuMacUIHost.dylib
yanxu-macos-ui-runner（兼容调试）
```

当前包清单声明麦金塔 arm64 ABI v2 原生制品，并记录大小与 SHA-256。言包解析依赖时会选择当前目标平台的动态库并写入锁文件；顶层应用仍须显式授权 `原生扩展 = true`。runner 保留为旧调试路径，不参与普通用户运行。

宿主分工：

- `YanxuNativeABI.swift`：定义言序原生扩展 ABI v1/v2 的 Swift 侧结构；
- `YanxuMacUIModel.swift`：解码应用、窗口、菜单、命令、视图；
- `YanxuMacUIApplicationStore.swift`：状态表、revision 和 v1 输入兼容；
- `YanxuMacUIRenderer.swift` 与各能力 renderer：递归分派控件、布局、集合、呈现和样式；
- `YanxuMacUIAppHost.swift`：用 AppKit 管理 `NSApplication`、窗口控制器和工具栏；
- `YanxuMacUIRequestCoordinator.swift`：管理 `NSOpenPanel`、`NSSavePanel`、多文档窗口和请求结果；
- `YanxuMacUIMenuBarItemController.swift`：管理 `NSStatusItem`、`NSPopover` 和菜单栏 SwiftUI 内容；
- `YanxuMacUIExports.swift`：保留 ABI v1 `validate` 和 `launch` 原生函数；
- `YanxuMacUIExportsV2.swift`：导出 ABI v2 `validate`、`run`、`update`、`patch`、`request` 和 `stop`；
- `YanxuMacUICallback.swift`：管理回调 retain/release、类型值编码、事件投递和 owner-thread pump。

## 为什么 JSON 字段仍是英文

公开 API 是中文；协议字段是英文。这是有意为之：

- Swift、日志、调试器和外部工具处理英文 key 更稳定；
- schema 可与非中文工具共享；
- 中文语义留在言序层，不牺牲跨语言互操作。

## 安全边界

言序层不执行任意系统命令。原生宿主必须通过清单权限与动态库校验后才会被装载。0.6 文件能力只通过用户确认的系统面板读写，限制单文件 16 MiB，并返回 security-scoped bookmark；网络、签名、公证和文档内容校验仍由应用业务层负责。
