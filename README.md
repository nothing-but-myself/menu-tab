# Menu Bar Rotator

通过快捷键轮换 macOS 菜单栏图标，解决 MacBook 刘海遮挡问题。

## 核心创意

利用 macOS 原生的 `Command + 拖拽` 重排图标功能，通过程序模拟拖拽操作实现图标轮换。

```
轮换前：[被遮挡1][被遮挡2][刘海][可见1][可见2][系统图标]
                           ↓ 按下快捷键
轮换后：[被遮挡2][可见1][刘海][可见2][被遮挡1][系统图标]
```

**优势**：
- 不需要屏幕录制权限
- 不需要额外的下拉栏
- 利用系统原生功能，更优雅

## 快速开始

```bash
# 编译
swift build

# 运行
.build/debug/MenuBarRotator
```

首次运行需要授予辅助功能权限：
**系统设置 → 隐私与安全 → 辅助功能**

## 使用方法

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘ ⇧ Space` | 向左轮换（把右侧图标移到左侧） |
| `⌘ ⇧ ⌥ Space` | 向右轮换（把左侧图标移到右侧） |

### 菜单操作

点击状态栏图标（🔄）显示菜单：

- **Rotate Left/Right**: 基于检测到的图标轮换
- **Blind Rotate**: 基于估算位置轮换（适用于第三方图标）
- **Cyclic Rotate**: 批量轮换多个图标

## 工作原理

### 1. 图标检测

```swift
// 通过 CGWindowListCopyWindowInfo 获取 Layer 25 的窗口
let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
// 过滤状态栏层级 (layer == 25)
```

**限制**：只能检测到系统控制中心图标，第三方 `NSStatusItem` 不可见。

### 2. 模拟拖拽

```swift
func simulateDrag(from: CGPoint, to: CGPoint) {
    // 1. 按下 Command 键
    // 2. 鼠标按下
    // 3. 分步拖拽（更自然）
    // 4. 鼠标松开
    // 5. 松开 Command 键
}
```

### 3. 盲轮换算法

当无法精确检测图标位置时，基于屏幕布局估算：

```
屏幕宽度: 1470px
刘海区域: 615px - 855px (约 240px)
左侧可用: 100px - 605px
右侧可用: 865px - 1270px
```

## 配置文件

位置：`~/.config/menu-bar-rotator/config.json`

```json
{
  "pinnedApps": [
    "com.apple.controlcenter",
    "com.apple.Spotlight"
  ],
  "rotationStep": 2,
  "iconWidth": 28,
  "menuBarY": 12,
  "rightMargin": 200,
  "notchWidth": 240
}
```

| 参数 | 说明 |
|------|------|
| `pinnedApps` | 固定不参与轮换的应用 Bundle ID |
| `rotationStep` | 每次轮换的图标数量 |
| `iconWidth` | 估算的图标宽度（px） |
| `menuBarY` | 状态栏中心 Y 坐标 |
| `rightMargin` | 右侧系统图标区域宽度 |
| `notchWidth` | 刘海宽度 |

## 技术细节

### 为什么需要辅助功能权限？

- `CGEvent` API 需要权限才能发送键盘/鼠标事件
- 用于模拟 Command+拖拽操作

### 为什么检测不到第三方图标？

第三方应用使用 `NSStatusItem` 创建状态栏图标，这些图标不会作为独立窗口出现在 `CGWindowListCopyWindowInfo` 结果中。

可能的改进：
1. 使用 Accessibility API (`AXUIElement`) 遍历菜单栏
2. 让用户手动配置图标位置
3. 使用屏幕截图 + 图像识别（但这需要屏幕录制权限）

## 项目结构

```
menu-bar-rotator/
├── Package.swift
├── MenuBarRotator/
│   └── main.swift           # 主程序
└── README.md
```

## 已知问题

1. **第三方图标检测**：无法直接获取位置，需要使用盲轮换
2. **不同机型刘海大小**：需要手动配置 `notchWidth`
3. **外接显示器**：无刘海时此工具意义不大

## 后续计划

- [ ] 添加 GUI 配置界面
- [ ] 支持自定义快捷键
- [ ] 自动检测 MacBook 型号和刘海尺寸
- [ ] 使用 Accessibility API 获取完整图标列表
- [ ] 支持多显示器
- [ ] LaunchAgent 开机自启

## License

MIT
