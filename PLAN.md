# Zoo Desktop Pet — Windows 桌面动物宠物 开发计划

> 技术栈：**Flutter (Dart) + Windows 桌面端**
> 目标平台：Windows 10/11 x64
> 项目目录：`D:\PGitCode\zoo_desktop_pet`
> Flutter SDK：`D:\Soft\flutter_sdk`（建议将 `D:\Soft\flutter_sdk\bin` 加入 PATH）

---

## 1. 项目概述

一个常驻 Windows 桌面的卡通动物宠物应用：

- 支持 26 种动物卡通形象，用户可切换（切换后重启生效）
- 每种动物有独立的成长记录（JSON 文件持久化）
- 可接入任意 OpenAI 兼容格式的 AI 服务（国内云端或本地 Ollama/LM Studio 等）
- 点击宠物可互动，宠物会弹出气泡文字（互动回复 / AI 主动提示）

## 2. 支持的动物（26 种）

| 分类 | 动物 |
|------|------|
| 哺乳类（14） | 老虎、狮子、狗狗、猫、大象、猴子、熊猫、袋鼠、长颈鹿、海豹、河马、猩猩、水獭、小熊猫 |
| 鸟类（12） | 鹰、鹦鹉、鸳鸯、企鹅、信天翁、天鹅、鸵鸟、鹭、松鸡、啄木鸟、海鸥、蜂鸟 |

> 动物以英文 id 标识（如 `tiger`、`red_panda`、`otter`），素材与成长记录均以 id 关联。

### 素材方案（按优先级）

1. **首选**：AI 生成统一风格的卡通 PNG 序列帧（每动物 4 组动作 × 4–8 帧：待机 idle、眨眼/摆动 blink、开心 happy、睡觉 sleep），透明背景，256×256
2. 备选：Rive/Lottie 矢量动画（表现力最佳，但 27 种动物制作成本高，可后期逐步替换）
3. 兜底：单张静态 PNG + Flutter 代码动画（缩放呼吸感、位移）——首版可用此方案快速跑通

## 3. 技术选型与关键依赖

| 用途 | 方案 |
|------|------|
| 框架 | Flutter 3.x（stable）+ Windows desktop |
| 无边框/置顶/透明窗口 | `window_manager` + `flutter_acrylic`（透明背景） |
| 点击穿透（非宠物区域不挡鼠标） | Windows 原生代码：`WS_EX_LAYERED` + 按需切换 `WS_EX_TRANSPARENT`（在 `windows/runner` 中写少量 C++，通过 MethodChannel 控制） |
| 系统托盘 | `tray_manager`（右键菜单：切换动物、设置、退出） |
| 开机自启 | `launch_at_startup`（可选项） |
| 本地存储 | JSON 文件（`dart:io` + `path_provider`，存于 `%APPDATA%\zoo_desktop_pet\`） |
| AI 请求 | `dio`（HTTP，流式 SSE 可选），OpenAI 兼容 `/v1/chat/completions` |
| 状态管理 | `riverpod`（轻量、可测试） |
| 动画 | Flutter 自带 `AnimationController` + 序列帧 `Image`；后期可换 `rive` |
| 打包 | `flutter build windows` + Inno Setup 制作安装包（可选） |

## 4. 架构设计

```
zoo_desktop_pet/
├── PLAN.md
├── pubspec.yaml
├── assets/
│   └── animals/<animal_id>/          # 每种动物一个目录
│       ├── idle/*.png  blink/*.png  happy/*.png  sleep/*.png
│       └── meta.json                 # 名称、帧率、锚点、气泡偏移
├── lib/
│   ├── main.dart                     # 窗口初始化（透明、置顶、无边框）
│   ├── core/
│   │   ├── config.dart               # 应用配置模型（当前动物、AI 配置等）
│   │   ├── storage.dart              # JSON 读写封装（配置 + 成长记录）
│   │   └── native_window.dart        # MethodChannel：点击穿透开关
│   ├── pet/
│   │   ├── pet_widget.dart           # 宠物渲染（帧动画、状态机）
│   │   ├── pet_state_machine.dart    # idle→blink→happy→sleep 状态流转
│   │   ├── drag_handler.dart         # 拖拽移动宠物
│   │   └── bubble.dart               # 气泡文字组件（自动消失）
│   ├── growth/
│   │   ├── growth_model.dart         # 成长数据模型
│   │   └── growth_service.dart       # 经验/等级/心情计算，事件记录
│   ├── ai/
│   │   ├── ai_config.dart            # baseUrl / apiKey / model / 开关
│   │   ├── ai_client.dart            # OpenAI 兼容客户端（chat completions）
│   │   └── proactive_tips.dart       # 定时主动提示调度器
│   ├── interaction/
│   │   └── click_actions.dart        # 点击/双击/长按 → 互动逻辑
│   └── settings/
│       └── settings_window.dart      # 设置界面（动物切换、AI 配置）
└── windows/runner/                   # 原生：点击穿透、DPI 等
```

### 4.1 窗口模型

- 主窗口：全透明、无边框、置顶、不出现在任务栏；实际可见的只有宠物本体（约 200×200 逻辑像素）与气泡
- 鼠标位于宠物贴图不透明区域 → 接收点击/拖拽；其余区域 → 点击穿透到桌面
- 设置窗口：普通窗口，从托盘菜单打开（Flutter 单引擎限制下用同窗口切换页面或 `desktop_multi_window` 插件开子窗口，首版用托盘弹出同窗口面板即可）

### 4.2 成长记录（JSON）

每种动物一个文件：`%APPDATA%\zoo_desktop_pet\growth\<animal_id>.json`

```json
{
  "animalId": "tiger",
  "createdAt": "2026-07-27T10:00:00+08:00",
  "level": 3,
  "exp": 140,
  "mood": 80,
  "totalInteractions": 52,
  "totalOnlineMinutes": 1310,
  "lastActiveAt": "2026-07-27T18:30:00+08:00",
  "events": [
    { "time": "2026-07-27T12:00:00+08:00", "type": "levelUp", "detail": "升到 Lv.3" },
    { "time": "2026-07-27T12:05:00+08:00", "type": "aiTip", "detail": "记得喝水哦" }
  ]
}
```

成长规则（首版）：

- 在线陪伴：每 10 分钟 +1 exp（应用运行即累计）
- 互动：单击 +2 exp（每分钟限 1 次防刷）
- 升级：`expToNext = 100 * level`；升级触发 happy 动画 + 气泡祝贺
- 心情 mood（0–100）：互动回升，长时间无互动缓慢下降；影响待机动画频率
- events 只保留最近 200 条，防止文件膨胀

应用配置：`%APPDATA%\zoo_desktop_pet\config.json`（当前动物、AI 配置、窗口位置、开机自启等）。**切换动物只写入 config.json，提示"重启后生效"，下次启动加载新动物与其成长记录。**

### 4.3 AI 接入（OpenAI 兼容）

设置项：`baseUrl`（如 `https://api.deepseek.com/v1`、`http://localhost:11434/v1`）、`apiKey`（本地服务可空）、`model`、启用开关、主动提示间隔。

两种使用场景：

1. **互动回复**：点击宠物时按概率（如 30%）调用 AI，system prompt 注入动物人设 + 成长数据（等级/心情/陪伴时长），生成一句 ≤40 字的拟人回复；未启用 AI 或请求失败 → 回落到本地预置语料库（每种动物 ≥10 条）
2. **主动提示**：定时器（默认 30–60 分钟随机）触发，AI 结合时间段生成提示（喝水、休息、久坐提醒等），气泡显示 8 秒；同时写入成长 events

约束：请求超时 15s；失败静默降级本地语料；apiKey 仅存本地 config.json（明文，文档中提示风险）。

### 4.4 点击互动

| 操作 | 行为 |
|------|------|
| 单击 | happy 动画 + 气泡（本地语料或 AI 回复）+ exp |
| 双击 | 显示成长面板小卡片（等级/经验条/心情/陪伴时长） |
| 长按拖拽 | 移动宠物位置（保存到 config） |
| 右键 | 快捷菜单：互动、成长记录、设置、退出 |
| 托盘图标 | 显示/隐藏宠物、设置、退出 |

## 5. 开发里程碑

| 阶段 | 内容 | 预估 |
|------|------|------|
| M1 骨架 | Flutter Windows 工程、透明置顶无边框窗口、托盘、拖拽移动、单动物静态图显示 | 2–3 天 |
| M2 点击穿透 | 原生 C++ 实现区域点击穿透 + MethodChannel 联调 | 1–2 天 |
| M3 动画与状态机 | 序列帧播放、idle/blink/happy/sleep 状态机、气泡组件 | 2–3 天 |
| M4 成长系统 | JSON 存储、经验/等级/心情、成长面板、事件记录 | 2 天 |
| M5 动物与切换 | 27 种动物素材接入（首版可先做 6–8 种，其余静态图兜底）、设置页切换 + 重启生效 | 3–5 天（素材为主要工作量） |
| M6 AI 接入 | OpenAI 兼容客户端、互动回复、主动提示、失败降级 | 2 天 |
| M7 打磨发布 | 开机自启、多显示器/DPI 适配、打包安装程序 | 2 天 |

**总计约 2–3 周（单人业余时间约 1 个月）。**

## 6. 复杂度评估

| 模块 | 复杂度 | 说明 |
|------|--------|------|
| 透明置顶窗口 | ★★☆ | 插件成熟，注意 DPI 与多显示器 |
| 点击穿透 | ★★★ | 需写原生 C++，是 Flutter 方案最大风险点；兜底方案：窗口缩到仅包裹宠物，放弃像素级穿透 |
| 帧动画/状态机 | ★★☆ | Flutter 动画能力强，纯 Dart 实现 |
| 成长系统 | ★☆☆ | 简单 JSON 读写与数值计算 |
| AI 接入 | ★★☆ | 标准 HTTP，注意超时与降级 |
| 27 种动物素材 | ★★★ | 工程量最大项，建议 AI 批量生成统一风格素材，分批交付 |
| 整体 | **中等偏上** | 核心难点在原生穿透与素材量 |

## 7. 风险与对策

1. **点击穿透实现难**：兜底方案是把窗口尺寸缩小到刚好包住宠物，牺牲像素级穿透，可用性依然良好
2. **素材风格不统一**：先定 1 张风格参考图，所有动物用同一 prompt 模板生成；首版允许仅静态图
3. **AI 服务不稳定/费用**：默认关闭 AI，本地语料保证核心体验；支持本地 Ollama 零成本
4. **内存占用**：仅加载当前动物的素材（切换重启生效的设计天然规避了多套素材同时驻留）

## 8. 首版（v0.1）验收标准

- [ ] 宠物置顶显示在桌面，可拖拽，不挡非宠物区域鼠标操作（或采用兜底方案）
- [ ] 至少 6 种动物可选，切换后重启生效
- [ ] 单击有动画 + 气泡回复；双击查看成长面板
- [ ] 成长记录按动物分文件保存为 JSON，重启后数据保留
- [ ] 设置页可配置 OpenAI 兼容 AI（baseUrl/apiKey/model），启用后互动回复与主动提示生效，失败自动降级
- [ ] 托盘菜单可用，可正常退出
