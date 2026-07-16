# SwiftUI 与麦金塔能力路线

本文以 Xcode 16、macOS 15 SDK 的 SwiftUI/SwiftUICore 接口为盘点基线。项目仍支持 README 声明的最低系统版本；新增能力必须按可用性做降级或提高单项能力的最低版本，不能因为开发机 SDK 较新而静默改变整个包的运行要求。

## 目标定义

本项目追求两类完整性：

- SwiftUI 视图能力完整：常用控件、布局、集合、导航、呈现、焦点、手势、动画、无障碍和数据传递都有言序对象模型。
- 麦金塔应用语义完整：窗口、设置、菜单栏应用、文档、命令、工具栏、打开与保存、恢复和生命周期能够构成正式桌面应用。

不追求逐字复制 SwiftUI 的所有泛型重载。SwiftUI 的 result builder、property wrapper、KeyPath、闭包和静态 `Scene` 类型不能无损编码为 JSON。言序 API 应表达相同的应用语义，并保持自身的对象模型和静态检查能力。

## 运行时约束

当前原生宿主在言序进程启动后通过动态库创建 `NSApplication` 和 `NSHostingView`。它不是进程入口，因而不能直接成为 `@main SwiftUI.App`，也不能动态重建 SwiftUI 的静态 `Scene` 图。

因此采用以下边界：

- 视图、控件、modifier、导航内容和呈现内容由 SwiftUI 渲染。
- 窗口、设置、菜单栏项目、文档控制器和应用生命周期由 AppKit 实现 SwiftUI Scene 的等价语义。
- JSON 是对象图的传输协议，不是公开编程模型。
- 原生 ABI v2 已经支持持久回调和双向调用。状态补丁、请求结果和生命周期事件应先扩展应用消息协议，不应仅为增加消息种类升级 FFI ABI。

如果未来要求运行真正的 `SwiftUI.App`/`DocumentGroup`，需要新增独立原生可执行宿主并把言序 VM 嵌入应用入口。这应作为另一种部署模式，不应替换当前直接运行模式。

## 目标对象图

```text
麦金塔应用
├── 麦金塔运行会话
├── 麦金塔场景
│   ├── 麦金塔窗口场景
│   ├── 麦金塔设置场景
│   ├── 麦金塔菜单栏场景
│   └── 麦金塔文档场景
├── 麦金塔命令组
├── 麦金塔状态
│   ├── 麦金塔文字状态
│   ├── 麦金塔数值状态
│   ├── 麦金塔布尔状态
│   └── 麦金塔选择状态
└── 麦金塔视图
    ├── 控件与容器
    ├── 麦金塔绑定
    ├── 麦金塔焦点
    ├── 麦金塔呈现
    ├── 麦金塔动作
    └── 麦金塔视图修饰器
```

言序目前不提供用户定义的泛型类，因此状态不应伪装成 `状态<T>`。用具体状态子类换取可验证的 `文`、`数`、`理` 和选择值边界，比把所有值重新放进 `任意` 更符合本项目的 OOP 方向。

`麦金塔运行会话` 负责原生模块、revision、挂载、补丁提交、请求关联和生命周期。全局 `运行（应用）`、`更新（应用）` 可以继续作为兼容门面，但新代码应能使用 `应用.创建会话（）` 和会话对象完成整个流程。

## 状态协议

完整快照继续作为挂载和恢复边界。0.5 已加入稳定状态表、Binding 和 revision：

```json
{
  "schema": "dev.yanxu.mac-ui.v2",
  "revision": 12,
  "state": [
    {"id": "document.title", "type": "string", "value": "未命名"}
  ],
  "scenes": []
}
```

原生层回传统一消息：

```json
{
  "type": "binding.changed",
  "revision": 12,
  "source": "title-field",
  "binding": "document.title",
  "value": "新标题"
}
```

会话先把值写回对应言序状态对象，再分派可选动作。应用只修改状态即可更新绑定控件；不再要求每次输入都手工解析 `payload`、改 property bag、提交完整应用快照。结构变化仍可提交完整快照，频繁值变化使用带 revision 的补丁。

所有绑定视图必须有显式稳定 ID（只读绑定文本除外）。未绑定的兼容控件仍可使用推导 ID；新 API 不应依赖该策略。

## 能力矩阵

| SwiftUI / macOS 领域 | 当前 0.6 | 后续目标 | 阶段 |
| --- | --- | --- | --- |
| 状态与 Binding | 四类状态、revision patch、重复 ID/类型校验 | 派生状态、事务与持久化适配 | 0.7 |
| 控件 | 常用输入、ControlGroup、Disclosure、Menu、Link、Label | 样式族与高级控件 | 0.7 |
| 集合 | List、行对象、Table 选择/字段排序、Outline、简化 Tab | Section、原生多动态列、压力测试 | 0.7 |
| 导航与搜索 | 三栏、NavigationStack、绑定路径、搜索、检查器 | 深链和状态恢复扩展 | 0.7 |
| 呈现 | Sheet、Popover、Alert、文件面板与结果动作 | 确认对话框与高级面板配置 | 0.7 |
| 焦点 | 焦点 Binding、first responder 和命令上下文 | 焦点分区与提交范围 | 0.7 |
| Modifier 与样式 | 字体、内边距、框架、帮助、禁用、强调色 | 布局、外观、控件样式和完整无障碍族 | 0.6-0.7 |
| Scene 与窗口 | 窗口/设置/菜单栏/文档场景、恢复与生命周期 | SwiftUI App 可执行宿主模式 | 后续 |
| 命令与工具栏 | 命令组、placement、角色、默认命令和 Binding 校验 | 完整系统菜单替换策略 | 0.7 |
| 文档与文件 | 多文档窗口、打开/保存/导入/导出、bookmark | 协调读取、版本冲突和自动保存 | 0.7 |
| 拖放、手势、动画、绘图 | 无 | Transferable、手势、过渡、Canvas、Timeline | 0.7 |

## Swift 宿主拆分

0.5 已将 `YanxuMacUIRenderer` 的单一大型 `switch` 拆为按能力域组织的渲染单元：

```text
YanxuMacUIRenderer
├── YanxuMacUIControlRenderer
├── YanxuMacUILayoutRenderer
├── YanxuMacUICollectionRenderer
├── YanxuMacUIPresentationRenderer
└── YanxuMacUIStyleRenderer
```

中央分派仍然必要，因为动态 JSON 最终必须选择一个编译期 SwiftUI 类型，但新增控件不应同时扩大状态、事件、样式和布局代码的同一个文件。渲染上下文统一提供绑定存储、动作出口、焦点、呈现协调器和系统能力查询。

未知节点在开发模式可显示诊断占位；正式运行应在挂载前返回带对象路径的校验错误，不能把“不支持”悄悄渲染进用户界面。

## 版本阶段

### 0.5：反应式视图层（已完成）

- 状态、绑定、稳定 ID 和 revision 补丁。
- Picker、Slider、Stepper、DatePicker、ColorPicker、选择 List、Menu、Link 和 Label。
- 搜索、Sheet、Popover 和 Alert。
- renderer 按能力域拆分，保留 schema v1 解码兼容。

完成标志：计数器不调用通用 `.设`、不手工读取输入 `payload`、不为每次键入提交完整应用快照。

### 0.6：完整麦金塔应用结构（已完成）

- 场景继承树、运行会话、设置窗口、菜单栏项目、窗口打开/关闭、frame 恢复和生命周期事件。
- 命令组、工具栏 placement、角色、默认命令、焦点上下文和 Binding 动态可用状态。
- 多文档窗口模板、打开/保存、导入/导出、security-scoped bookmark 和异步请求结果关联。
- NavigationStack、绑定路径、Table 行/列对象与字段排序、Outline 节点对象、焦点和 inspector。

完成标志：可实现带设置页、多文档窗口、菜单命令、工具栏和系统打开/保存流程的正式应用。

### 0.7：高级交互与表现

- 拖放、剪贴板、分享、手势、动画、过渡、Shape、Canvas 和 Timeline。
- 完整无障碍属性与动作。
- 性能预算、事件合并、列表虚拟化验证和大文档压力测试。

完成标志：高级交互不绕过对象模型写任意 property key，所有跨边界数据有类型、大小和生命周期约束。

## 下一实现切片

0.7 从拖放与 Transferable 开始，随后补充剪贴板、分享、手势、动画、Canvas、完整无障碍动作以及大文档性能预算。动态 Table 在 0.6 受 SwiftUI 静态 `TableColumnBuilder` 约束，使用一个可选择、可排序的复合列承载运行时列定义；原生多动态列属于后续可执行宿主或代码生成模式的设计议题。
