# 入门

`yanxu-macos-ui` 的核心思路很简单：用言序写出应用的骨架，用事件名连接业务逻辑，用原生宿主把它呈现为麦金塔应用。

应用作者只写言序。SwiftUI 和 AppKit 位于包内原生宿主层，负责呈现窗口、控件和系统交互，不要求业务项目包含 Swift 源码。

## 安装

```sh
yanbao add macos-ui
```

`macos-ui` 会解析到 `yanxulang/yanxu-macos-ui`。需要固定版本时可追加版本约束，例如 `--version '^0.1'`。

或者在本仓库中直接引用源码：

```yanxu
引「../src/言序麦金塔界面.yx」为 界面；
```

## 一个窗口

```yanxu
定 根 为 界面.垂直（【
    界面.标题（「第一扇窗」）,
    界面.文本（「言序描述应用，宿主负责原生呈现。」）,
    界面.按钮（「继续」，「next」）
】）.设样式（「padding」，20）；

定 窗口 为 界面.窗口（「示例」，根）.尺寸（860，560）；
```

## 一个应用

```yanxu
定 应用 为 界面.应用（「示例」）
    .设强调色（「teal」）
    .添窗口（窗口）；

界面.运行（应用）；
```

应用必须至少有一个窗口。事件名必须是稳定 ASCII 标识，例如 `draft.save`、`build.start`，这样原生层、日志和测试都能可靠识别。

## 加菜单和快捷键

```yanxu
定 文件菜单 为 界面.菜单（「文件」）
    .添命令（界面.命令（「保存」，「draft.save」）.设快捷键（「s」，【「command」】））；

应用.添菜单（文件菜单）；
```

菜单描述会进入 JSON schema。当前宿主已建模菜单数据；更完整的系统菜单挂载会在后续版本继续加深。

## 打开窗口

示例末尾调用 `界面.运行（应用）`。当前 `0.1.x` 还没有把宿主动态库接入言序原生扩展清单，所以它会启动仓库自带 runner，把应用描述交给原生宿主打开窗口：

```sh
swift build -c release --package-path native
export YANXU_MACOS_UI_RUNNER="$PWD/native/.build/release/yanxu-macos-ui-runner"
yanxu 执 examples/项目工作台.yx
```

顶层项目需要允许 `进程 = true`。如果 runner 已在 `PATH` 中，则不需要设置环境变量；也可以在代码中先调用 `界面.设运行器（路径）`。

`yanbao add macos-ui` 安装的是言序包源码，不会自动安装 runner。团队项目可以把构建好的 `yanxu-macos-ui-runner` 放入自己的工具目录，然后在启动脚本中设置 `YANXU_MACOS_UI_RUNNER`。

## 原生宿主源码

```sh
swift build -c release --package-path native
```

当前 `0.1.x` 清单不声明原生制品，安装时不会要求用户构建 Swift。仓库保留宿主源码和 runner，用于维护、本地预览和后续发布正式动态库制品。正式接入原生扩展时，会按言序协议发布目标平台、文件路径和 SHA-256 校验和。

本地构建产物通常位于：

```text
native/.build/release/libYanxuMacUIHost.dylib
```
