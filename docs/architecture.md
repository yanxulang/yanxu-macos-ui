# 架构与原生宿主

`yanxu-macos-ui` 分成三层：言序对象模型、稳定传输协议和 Swift 原生宿主。

## 描述层

言序代码构建一棵对象图：

```text
麦金塔应用
  窗口
    根视图
      子视图
  菜单
    命令
  设置视图
```

视图根类只保存共同树行为。文本、按钮、输入控件和容器由不同子类表达，动作与修饰器也是独立对象。工厂函数返回具体类，因而言序可以在编译期检查 `设内容`、`当文本变化`、`设值`、`设间距` 等控件专用操作。

对象图最终投影为 JSON。schema 名称为 `dev.yanxu.mac-ui.v1`，用于让宿主拒绝未知协议。`kind` 和通用 property bag 属于这一传输层，而不是公开对象模型；这使 0.4 的 OOP API 可以继续使用 0.3 原生宿主。新增原生控件仍需在 Swift 渲染器中实现。

## 事件与更新闭环

```text
AppKit / SwiftUI 控件
  -> ABI v2 callback_post（事件名、载荷）
  -> 言序宿主有界队列
  -> owner-thread pump
  -> 应用.当事件 处理器
  -> 界面.更新（应用）
  -> SwiftUI 可观察状态存储
```

`run` 在应用事件循环期间保留回调句柄，退出时成对释放。控件事件发生后宿主投递并立即泵送，业务处理器可以嵌套调用 `update`。`update` 接收完整应用快照，更新可观察状态、窗口元数据、菜单和工具栏；它不是任意线程可调用的 UI API。

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
- `YanxuMacUIRenderer.swift`：把视图描述递归渲染为 SwiftUI；
- `YanxuMacUIAppHost.swift`：用 AppKit 管理 `NSApplication`、窗口控制器和工具栏；
- `YanxuMacUIExports.swift`：保留 ABI v1 `validate` 和 `launch` 原生函数；
- `YanxuMacUIExportsV2.swift`：导出 ABI v2 `validate`、`run` 和 `update` 原生函数；
- `YanxuMacUICallback.swift`：管理回调 retain/release、类型值编码、事件投递和 owner-thread pump。

## 为什么 JSON 字段仍是英文

公开 API 是中文；协议字段是英文。这是有意为之：

- Swift、日志、调试器和外部工具处理英文 key 更稳定；
- schema 可与非中文工具共享；
- 中文语义留在言序层，不牺牲跨语言互操作。

## 安全边界

言序层只生成描述，不执行任意系统命令。原生宿主必须通过清单权限与动态库校验后才会被装载。事件只是名称和载荷，不代表宿主可以直接执行危险操作；真正的文件、网络、签名、公证等行为应由应用业务层继续做权限与输入校验。
