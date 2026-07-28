# 爪爪 · 桌面宠物

> 一个基于 Flutter 的 Windows 桌面宠物应用。26 种卡通动物常驻桌面陪伴你工作，可点击互动、记录成长、缩放大小，并支持接入自定义 AI（OpenAI 兼容接口）主动送出暖心提示。

内部包名：`zoo_desktop_pet` · 版本：`1.0.0+1`

---

## 1. 作用（这是什么）

「爪爪」是一只挂在桌面上的透明、无边框、始终置顶的小宠物：

- **陪伴常驻**：无边框透明窗口，置顶显示，不占用任务栏。
- **26 种动物**：14 种哺乳动物（老虎、狮子、狗狗、猫、大象、猴子、熊猫、袋鼠、长颈鹿、海豹、河马、猩猩、水獭、小熊猫）+ 12 种鸟类（鹰、鹦鹉、鸳鸯、企鹅、信天翁、天鹅、鸵鸟、鹭、松鸡、啄木鸟、海鸥、蜂鸟）。切换动物在**重启后生效**。
- **成长系统**：每只动物**独立**记录等级、经验、心情、互动次数、陪伴时长、相识天数，数据以 JSON 落盘。
- **互动反馈**：
  - 左键单击 → 宠物开心弹跳 + 气泡对话。
  - 双击 → 展开/收起成长记录卡片。
  - 右键 → 自定义动画菜单（互动 / 成长记录 / 放大 / 缩小 / 设置 / 退出）。
  - 拖拽 → 移动窗口位置（位置会被记住）。
- **缩放**：右键菜单「放大 / 缩小」或设置页滑块调整宠物大小（0.6×–2.0×）。
- **AI 助手（可选）**：填入任意 OpenAI 兼容服务（如 DeepSeek、通义、Ollama 本地模型等）后，宠物会定时主动发出「喝水、久坐提醒、休息」等暖心提示，并在互动时偶尔用 AI 回应。
- **系统托盘**：托盘图标支持显示/隐藏、打开设置、退出。

数据保存在：`%APPDATA%\zoo_desktop_pet\`
- `config.json` — 应用配置（当前动物、AI 配置、窗口位置、缩放比例）。
- `growth\<animalId>.json` — 每只动物的成长档案。

---

## 2. 使用的技术

- **语言 / 框架**：[Flutter](https://flutter.dev/) 3.44.5（stable）/ Dart SDK `^3.12.2`，Material 3。
- **桌面窗口能力**：
  - [`window_manager`](https://pub.dev/packages/window_manager) `^0.5.2` — 无边框 / 置顶 / 隐藏任务栏 / 拖拽 / 尺寸与位置控制。
  - [`flutter_acrylic`](https://pub.dev/packages/flutter_acrylic) `^1.1.4` — 窗口透明效果（`WindowEffect.transparent`）。
  - [`tray_manager`](https://pub.dev/packages/tray_manager) `^0.5.3` — 系统托盘图标与菜单。
- **网络**：[`dio`](https://pub.dev/packages/dio) `^5.11.0` — 调用 OpenAI 兼容的 `/v1/chat/completions`。
- **资源渲染**：[`flutter_svg`](https://pub.dev/packages/flutter_svg) `^2.3.0` — SVG 兜底渲染；`path_provider` `^2.1.6`（预留）。
- **图标字体**：Font Awesome 7 Free Solid（`assets/fonts/fa7-solid.otf`，字体族 `FA7Solid`）用于菜单与设置界面图标。
- **宠物美术**：Microsoft Fluent Emoji（3D PNG 为主，Color SVG 兜底，emoji 文本为最后回退）；其中 5 种常见动物（熊猫/狗/猫/老虎/大象）替换为 icons8 3D-Fluency 透明渲染图。

### 架构分层（`lib/`）

```
lib/
├── main.dart                # 入口：窗口初始化、AppShell、托盘、pet↔settings 模式切换
├── core/
│   ├── animals.dart         # 26 种动物定义（id/名称/emoji/性格/主题色/台词）
│   ├── config.dart          # AppPaths + AppConfig + AiConfig（读写 JSON）
│   └── fa_icons.dart        # Font Awesome 7 图标码点封装（Fa7 类）
├── ai/
│   └── ai_client.dart       # OpenAI 兼容聊天客户端（chat / test）
├── growth/
│   └── growth_service.dart  # 成长逻辑：经验/心情/等级/陪伴时长，定时 tick + 落盘
└── pet/
    ├── pet_controller.dart  # 宠物状态机（idle/blink/happy/sleep）、气泡、缩放、AI 触发
    └── pet_page.dart        # 宠物渲染、手势、动画右键菜单、气泡/成长卡片
```

---

## 3. 如何二次开发

### 3.1 环境准备

1. **安装 Flutter SDK**（建议 3.44.x stable），并将 `flutter/bin` 加入 `PATH`。本机 SDK 位于 `D:\Soft\flutter_sdk`。
2. **安装 Visual Studio 2022**（或 Build Tools），勾选 **“使用 C++ 的桌面开发”** 工作负载 —— 编译 Windows 原生 runner 必需。
3. **启用 Windows 开发者模式**（设置 → 隐私和安全性 → 开发者选项）。Flutter 插件依赖符号链接，未开启时 `flutter pub get` 会报 “Building with plugins requires symlink support”。
   - 若无法开启开发者模式，可用目录联接（junction）手动替代 `windows/flutter/ephemeral/.plugin_symlinks/` 下的插件链接（指向 `pub` 缓存里对应插件目录）。
4. 拉取依赖：
   ```bash
   flutter pub get
   ```

### 3.2 运行与调试

```bash
flutter run -d windows            # 调试运行
flutter analyze lib               # 静态检查
```

### 3.3 常见二开任务

**新增一种动物**
1. 在 `lib/core/animals.dart` 的 `kAnimals` 列表里增加一条 `AnimalInfo`（`id` 需唯一，作为资源文件名与成长档案名）。
2. 在 `assets/animals/` 放入 `<id>.png`（透明 3D 图，推荐 ~512px），可选 `<id>.svg` 作为兜底。
3. 无需改 `pubspec.yaml`（整个 `assets/animals/` 目录已声明）。重启后可在设置里选择。

**渲染优先级**：`assets/animals/<id>.png` → 加载失败回退 `<id>.svg` → 再回退 `AnimalInfo.emoji` 文本。

**调整窗口大小**：`lib/main.dart` 顶部的 `kPetWindowSize` / `kSettingsWindowSize`。

**调整缩放范围**：`lib/pet/pet_controller.dart` 的 `minScale` / `maxScale`（同时留意宠物窗口宽度是否放得下）。

**修改右键菜单**：`lib/pet/pet_page.dart` 中 `_buildMenu` / `_menuTile` / `_select`。图标来自 `lib/core/fa_icons.dart`（如需新图标，按 Font Awesome 码点新增常量）。

**修改成长规则**：`lib/growth/growth_service.dart`（每分钟 tick 加经验、心情衰减、`interact()` 奖励、`expToNext` 升级曲线等）。

**修改 AI 行为**：`lib/pet/pet_controller.dart` 的 `_systemPrompt()`（人设 prompt）与 `_scheduleTip()`（主动提示节奏）；网络细节在 `lib/ai/ai_client.dart`。

**更换应用 / 托盘图标**：
- 应用图标：`windows/runner/resources/app_icon.ico`（多尺寸 .ico）。
- 托盘图标：`assets/tray_icon.ico`。
- 可用工具从 PNG 生成 .ico（例如 Python PIL：`img.save('app_icon.ico', sizes=[(16,16),(32,32),(48,48),(256,256)])`）。

**修改可执行文件名 / 产品名**：`windows/CMakeLists.txt` 的 `BINARY_NAME`，以及 `windows/runner/Runner.rc` 中的产品/版权信息。

---

## 4. 如何打包正式版

```bash
# 1. （可选）清理
flutter clean && flutter pub get

# 2. 编译 Windows Release
flutter build windows --release

# 也可指定版本号
flutter build windows --release --build-name=1.0.0 --build-number=1
```

产物目录：

```
build\windows\x64\runner\Release\
├── zoo_desktop_pet.exe        # 主程序
├── flutter_windows.dll        # Flutter 引擎
├── *_plugin.dll               # 各插件原生库
└── data\                      # flutter_assets（动物图、字体、图标等）
```

**分发方式**：将整个 `Release\` 目录一起打包（zip 或安装包）。**不要只拷贝 exe** —— 它依赖同目录的 DLL 与 `data\` 资源。

> 可选：使用 [Inno Setup](https://jrsoftware.org/isinfo.php) / [MSIX](https://pub.dev/packages/msix) 制作安装程序；目标机器通常需要 [VC++ 运行库](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)。

---

## 5. 支持的平台

- ✅ **Windows 10 / 11（x64）** —— 当前唯一已配置并验证的平台（项目仅含 `windows/` 目录）。

> 本项目依赖透明窗口、置顶、托盘等桌面能力，重度绑定桌面平台。**Android / iOS / Web 不适用**。

### 扩展到 macOS / Linux（进阶，需自行适配）

```bash
flutter create . --platforms=macos,linux
```

注意事项：
- `window_manager`、`tray_manager`、`flutter_acrylic` 均支持桌面三端，但**透明 / 亚克力效果在不同系统上表现不同**，需按平台调试。
- 路径逻辑目前用 `%APPDATA%`（`lib/core/config.dart`），跨平台时应改用 `path_provider` 的 `getApplicationSupportDirectory()`。
- 托盘图标、应用图标需为各平台单独准备对应格式。

---

## 6. 配置 AI 助手（可选）

1. 右键宠物 → **设置**，或托盘菜单 → **设置**。
2. 打开「AI 助手」开关，填写：
   - **Base URL**：如 `https://api.deepseek.com/v1`、`http://localhost:11434/v1`（Ollama）。
   - **API Key**：本地服务可留空。
   - **模型名称**：如 `deepseek-chat`、`qwen2.5:7b`。
   - **主动提示间隔（分钟）**：默认 45。
3. 点「测试连接」验证，再「保存」（或「保存并重启」以切换动物）。

请求格式为标准 OpenAI `POST {baseUrl}/chat/completions`；任何返回异常都会静默回退到本地台词，不影响使用。

---

## 7. 目录与数据一览

| 位置 | 说明 |
| --- | --- |
| `%APPDATA%\zoo_desktop_pet\config.json` | 当前动物、AI 配置、窗口位置、缩放比例 |
| `%APPDATA%\zoo_desktop_pet\growth\<id>.json` | 每只动物的成长档案 |
| `assets/animals/` | 动物图片（`<id>.png` / `<id>.svg`） |
| `assets/fonts/fa7-solid.otf` | Font Awesome 7 图标字体 |
| `assets/tray_icon.ico` | 托盘图标 |
| `windows/runner/resources/app_icon.ico` | 应用图标 |
| `PLAN.md` | 详细设计与实现计划 |

---

## 8. 常见问题（FAQ）

- **切换动物没反应？** 动物切换在**重启后**生效（每只动物有独立成长档案，重启以加载对应数据）。
- **`flutter pub get` 报 symlink 错误？** 开启 Windows 开发者模式，或手动创建插件目录联接（见 3.1）。
- **编译报找不到 Visual Studio 工具链？** 安装 VS 2022 的「使用 C++ 的桌面开发」工作负载。
- **双击 exe 打不开 / 缺 DLL？** 需连同 `Release\` 目录下的 DLL 与 `data\` 一起分发。
- **宠物太大/太小？** 右键「放大 / 缩小」，或设置页拖动「宠物大小」滑块（0.6×–2.0×）。

---

## 9. 致谢

- 美术资源：Microsoft **Fluent Emoji**（MIT）、**icons8** 3D-Fluency。
- 图标字体：**Font Awesome 7 Free**（Solid）。
- 依赖作者：`window_manager` / `tray_manager` / `flutter_acrylic` / `dio` / `flutter_svg` 等开源社区。

---

## 10. 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。
