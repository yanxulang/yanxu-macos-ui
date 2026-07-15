# 架构与原生宿主

`yanxu-macos-ui` 分成两层：言序描述层和 Swift 原生宿主层。

## 描述层

言序代码构建一棵应用描述树：

```text
麦金塔应用
  窗口
    根视图
      子视图
  菜单
    命令
  设置视图
```

描述树最终序列化为 JSON。schema 名称为 `dev.yanxu.mac-ui.v1`，用于让宿主拒绝未知协议。

## 宿主层

`native/` 是一个 Swift Package，产物为动态库：

```text
libYanxuMacUIHost.dylib
```

当前 `0.1.x` 包清单保持纯言序形态，不声明原生制品，避免安装阶段要求用户拥有 Swift 工具链或预构建动态库。等发布按平台区分、带 SHA-256 校验的动态库后，再按言序原生扩展协议加入清单。

宿主分工：

- `YanxuNativeABI.swift`：定义言序原生扩展 ABI v1 的 Swift 侧结构；
- `YanxuMacUIModel.swift`：解码应用、窗口、菜单、命令、视图；
- `YanxuMacUIRenderer.swift`：把视图描述递归渲染为 SwiftUI；
- `YanxuMacUIAppHost.swift`：用 AppKit 管理 `NSApplication`、窗口控制器和工具栏；
- `YanxuMacUIExports.swift`：导出 `validate` 和 `launch` 原生函数。

## 为什么 JSON 字段仍是英文

公开 API 是中文；协议字段是英文。这是有意为之：

- Swift、日志、调试器和外部工具处理英文 key 更稳定；
- schema 可与非中文工具共享；
- 中文语义留在言序层，不牺牲跨语言互操作。

## 安全边界

言序层只生成描述，不执行系统命令。正式启用原生扩展时必须通过清单权限与动态库校验。事件只是名称和载荷，不代表宿主可以直接执行危险操作；真正的文件、网络、签名、公证等行为应由应用业务层继续做权限与输入校验。
