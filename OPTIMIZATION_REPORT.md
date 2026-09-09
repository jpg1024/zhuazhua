# 爪爪 · 桌面宠物 — 代码优化扫描报告

- **扫描日期**：2026-09-09
- **代码版本**：`main` @ `d517599`（v1.1.0+2），工作区干净
- **扫描范围**：`lib/` 全部 19 个 Dart 文件（约 5,800 行）、`pubspec.yaml` / `pubspec.lock`、`analysis_options.yaml`、`test/`、`tool/`、`assets/animals/`
- **验证手段**：逐文件精读 + `flutter analyze` + `flutter test` + 实测资源体积/分辨率 + 全局引用交叉检索（确认死代码）
- **基线状态**：`flutter analyze` 仅 11 条 info（全部在 `tool/` 脚本的 `avoid_print`），`flutter test` 6/6 通过。**没有编译错误或告警级问题。**

> 本报告只做分析，未修改任何代码。每条都标注了证据位置与置信度。
> 「24/7 常驻 + 透明置顶窗口」是这个应用的本质特征，所以**性能/功耗类的权重被刻意调高**——一次每秒几十次的无效唤醒，在这个场景里的代价远高于普通桌面软件。

---

## 0. 总体结论

代码质量整体**明显高于同类业余项目水准**：分层清晰（core / ai / growth / pet / settings / skin）、安全意识到位（DPAPI 加密、路径穿越防护、PID 过滤 HWND、明文 HTTP 警告）、已有的防御性修复（点击穿透自愈、多阶段 DWM 重合成）都留下了说明性注释。

问题集中在**四个方向**，按影响排序：

| # | 方向 | 严重度 | 一句话 |
|---|---|---|---|
| 1 | **持久化：同步 I/O 在 UI 线程 + 非原子写 + 静默吞异常** | 🔴 高 | 一次点击触发 2–3 次同步写盘；写盘中断会**静默丢档**；12 处 `catch (_) {}` 让失败完全不可见 |
| 2 | **常驻功耗：空闲时每秒 ~23 次定时器唤醒 + ~4,460 次 FFI 调用** | 🔴 高 | 其中一整套打字速度机制是**死代码**，却带着一个 60Hz 永久定时器 |
| 3 | **资源体积：26 张 1024×1024 PNG = 21.1 MB，占发布包 40%** | 🟠 中 | 实际最大显示尺寸仅 192 逻辑像素；设置页头像**未设 `cacheWidth`**，解码后可达 ~104 MB |
| 4 | **可维护性：魔法数字三处重复、840/946 行巨型文件、测试只覆盖皮肤** | 🟡 低 | 纯逻辑单元（成长/成就/每日任务/配置）零测试，但极易测 |

另有 **5 个确定的功能性缺陷**（见 P0），其中 2 个用户可直接感知。

---

## P0 · 正确性与数据可靠性

### P0-1 🔴 窗口位置不校验工作区 → 拔副屏后宠物永久失踪
**位置**：`lib/main.dart:50-54`、`lib/main.dart:241-245`

```dart
if (appConfig.windowX != null && appConfig.windowY != null) {
  await windowManager.setPosition(Offset(appConfig.windowX!, appConfig.windowY!));
} else {
  await windowManager.setAlignment(Alignment.bottomRight);
}
```

启动与关闭设置页时都直接套用磁盘上的历史坐标，**不与当前屏幕工作区做任何比对**。

**失败场景**：用户在 2560×1440 副屏上把宠物拖到 `(3000, 800)` → 拔掉副屏 / 换成 1920×1080 笔记本屏 → 下次启动宠物落在完全不可见的坐标上。此时：
- `_applyEdgeSnap()`（`main.dart:167`）只在 `onWindowMoved` 之后触发，而窗口够不着就永远不会 move；
- `Ctrl+Alt+P` 只做 show/hide（`main.dart:154`），**不重置位置**；
- 唯一出路是手改 `%APPDATA%\zoo_desktop_pet\config.json`。

**修复**：启动时把保存的坐标钳制进 `WindowUtils.instance.workArea()`；若矩形与工作区无交集则回退 `setAlignment(Alignment.bottomRight)`。约 15 行。
**置信度**：高（纯代码路径推导，无需运行即可确认）。

---

### P0-2 🔴 保存 AI 配置后主动提示不会启动（必须重启）
**位置**：`lib/pet/pet_controller.dart:372-390`，调用点仅 `lib/pet/pet_controller.dart:75`（构造函数）

```dart
void _scheduleTip() {
  if (!config.ai.enabled) return;   // ← 只在构造时判断一次
  ...
  _tipTimer = Timer(delay, () async { ... _scheduleTip(); });
}
```

`_scheduleTip()` 只在构造函数里调用一次，之后靠自身回调续期。`SettingsPage._save()`（`settings_page.dart:126-156`）保存后会立即同步快捷键开关和自启动注册表，**但没有通知 PetController 重排提示定时器**。

**失败场景**：
1. 用户首次启动时 AI 关闭 → `_scheduleTip()` 立即 return，定时器从未创建；
2. 用户在设置页填好 Base URL / Key / Model，打开开关，点「保存」，看到「已保存。」；
3. 「测试连接」也成功了；
4. **宠物永远不会主动发提示**，直到用户自己想到去重启。README 第 6 节把这个功能写成了保存即生效，与实现不符。

反向也有问题：启动时 AI 开着、之后关掉并保存 → 已排定的定时器仍会触发（`ai.chat()` 因 `ready == false` 返回 null 而静默无事发生），并按旧间隔**无限续期**下去。

**修复**：把 `_scheduleTip()` 改成幂等的公开方法（先 `_tipTimer?.cancel()` 再按当前 `config.ai.enabled` 重排），由 `_save()` 调用。约 10 行。
**置信度**：高。

---

### P0-3 🟠 配置/存档为非原子写 + 12 处静默吞异常 → 损坏即无声清零
**位置**：`config.dart:171-192`、`growth_service.dart:136-152`、`achievements.dart:194-206`、`daily_tasks.dart:124-134`

所有落盘都是直接 `writeAsStringSync(目标文件)`，没有「写临时文件 → rename」的原子替换。所有读取都包在 `catch (_) {}` 里，失败后回落到全默认值。

**失败场景**：进程在写入中途被杀（任务管理器结束、蓝屏、断电、`exit(0)` 时机不巧）→ `config.json` / `growth\cat.json` 被截断成半个 JSON → 下次启动 `jsonDecode` 抛异常 → `catch (_) {}` 静默吃掉 → `AppConfig()` / `GrowthService` 全默认值 → **用户积累几个月的等级、陪伴时长、相识天数、成就全部归零，且没有任何提示、没有日志、没有备份**。

对一个主打「陪伴时长」「相识天数」「12 个成就」的应用，这是最伤用户感情的失效模式。`_exit()`（`main.dart:249`）和 `_restart()`（`settings_page.dart:157`）都直接 `exit(0)`，绕过了 Flutter 的正常 teardown，进一步放大了这个窗口。

**修复**（三件事，都很小）：
1. 抽一个 `AtomicJsonStore.write(File, String)`：写 `xxx.json.tmp` → `flush` → `renameSync` 覆盖（Windows 上 `renameSync` 对已存在目标会失败，需先 `deleteSync` 旧的或用 `File.rename` + 备份轮替）；
2. `catch (_) {}` 改为 `catch (e, st) { debugPrint(...); }`，并在解析失败时把坏文件改名成 `xxx.corrupt-<ts>.json` 保留现场；
3. 可选：保留一份 `xxx.json.bak`。

**置信度**：高（写入路径与异常处理均已逐行确认）。

---

### P0-4 🟠 未被追踪的 Timer 在 dispose 后回调 `notifyListeners()`
**位置**：`pet_controller.dart:352-357`（眨眼内层 260ms）、`pet_controller.dart:406-411`（`interact()` 1200ms）、`pet_controller.dart:432-437`（`feed()` 1600ms）

```dart
Timer(const Duration(milliseconds: 1200), () {
  if (state == PetState.happy) { state = PetState.idle; notifyListeners(); }
});
```

`dispose()`（`pet_controller.dart:466-481`）取消了 11 个具名 Timer，但这三处**匿名 Timer 没有句柄**。`PetController extends ChangeNotifier`，dispose 之后再 `notifyListeners()` 在 debug 下会命中 `ChangeNotifier` 的断言并抛异常。

**实际影响有限**（`AppShell` 是根 Widget，其 dispose 基本只在应用退出时发生，而退出走的是 `exit(0)`），但这是一颗定时炸弹：一旦将来支持「热切换动物而不重启」，立刻变成崩溃。

**修复**：统一收进一个 `Set<Timer> _transientTimers`，或复用一个 `_stateResetTimer` 字段；`dispose()` 里全部 cancel。约 12 行。
**置信度**：高。

---

### P0-5 🟠 「保存并重启」不 await `Process.start` → 偶发不重启
**位置**：`lib/settings/settings_page.dart:157-164`

```dart
Future<void> _restart() async {
  final saved = await _save();
  if (!saved) return;
  widget.pet.growth.save();
  Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);  // ← 未 await
  exit(0);
}
```

`Process.start` 返回 `Future<Process>`。不 await 就 `exit(0)`，进程创建可能尚未提交就被自身终止 → 用户点了「保存并重启」，应用关掉了但没起来。同时该 Future 的错误也无人接收。

**修复**：`await Process.start(...)`，并用 try/catch 包住，失败时提示用户手动重启而不是直接退出。3 行。
**同类**：`main.dart:249-253` 的 `_exit()` 也是 `trayManager.destroy()` 不 await 就 `exit(0)`，会导致**托盘残留幽灵图标**（要鼠标划过才消失）。改为 `async` + `await`。
**置信度**：中高（竞态窗口很小，属偶发；但代码缺陷确定存在）。

---

### P0-6 🟡 `workArea()` 只返回主显示器 → 多屏下贴边吸附失效
**位置**：`lib/core/window_utils.dart:66-77`

`SystemParametersInfoW(SPI_GETWORKAREA, ...)` 按 Win32 文档**只返回主显示器的工作区**。`_applyEdgeSnap()`（`main.dart:167-197`）拿它和窗口绝对坐标比距离，宠物在副屏上时四个边的距离都不成立 → 吸附功能在副屏上完全不工作（好消息是不会误吸附到主屏，因为阈值 40px 挡住了）。

**修复**：改用 `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)` + `GetMonitorInfoW(MONITORINFOF.rcWork)`，返回宠物当前所在屏幕的工作区。约 40 行 FFI。
**置信度**：高（API 语义明确）。**优先级低于 P0-1**，因为这是「功能不生效」而非「功能出错」。

---

## P1 · 性能与常驻功耗

> 这是本报告**最值得投入**的一节。桌面宠物 24 小时运行，每秒省下 20 次无效唤醒，一年就是 6 亿次。

### P1-1 🔴 一整套「打字速度」机制是死代码，却带着一个 60Hz 永久定时器
**位置**：`lib/core/keyboard_hook.dart:33-44`（声明）、`:59-67`（`_decayTimer`）、`:88-101`（计算）

全局检索 `typingSpeed` / `typingSpeedStream` 的结果：**除 `keyboard_hook.dart` 自身外，`lib/` 内零引用**。

但它带来的成本是实打实的：

```dart
_decayTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {   // 62.5 次/秒，永不停止
  if (_typingSpeed > 0.001) { ... }
  else if (_typingSpeed > 0) { ... }
  // 速度为 0 时什么都不做，但定时器照样每秒唤醒 62 次
});
```

即使从不打字，这个定时器也会**以 60fps 的频率永久唤醒 Dart isolate**，阻止 CPU 进入深度空闲状态（笔记本上直接影响续航）。

**修复**（二选一）：
- **直接删掉**整套打字速度机制（`_typingSpeed` / `_lastKeyTimestamp` / `_decayTimer` / `_typingSpeedController` / `typingSpeedStream` / `typingSpeed`），约 -45 行；
- 若将来打算用（比如按打字强度调整宠物情绪），至少改成**惰性启停**：速度 > 0 时才创建定时器，衰减到 0 立刻 `cancel()` 并置 null。

**置信度**：高（死代码已通过全局检索确认）。

---

### P1-2 🔴 `_pollKeys()` 每 50ms 扫描 223 个虚拟键码 = 4,460 次 FFI 调用/秒
**位置**：`lib/core/keyboard_hook.dart:55-57`（50ms 轮询）、`:84-105`（键码循环）

```dart
for (var vk = 0x20; vk <= 0xFE; vk++) {          // 223 次迭代
  if (vk >= 0x01 && vk <= 0x06) continue;        // ← 死分支：vk 从 0x20 起，永不成立
  final state = _getAsyncKeyState(vk);           // 每次一个 dart:ffi 调用
  if (state & 0x8000 != 0) { ...; break; }
}
```

无键按下时（绝大多数时间）循环走满 223 次，**每次都跨越 Dart↔native 边界**：223 × 20 次/秒 ≈ **4,460 FFI 调用/秒**。加上 `break` 前的短路，实际按键时反而更快。

同时扫描范围过宽，把 `VK_NUMLOCK(0x90)`、`VK_SCROLL(0x91)`、`VK_RSHIFT(0xA1)`、`VK_VOLUME_MUTE(0xAD)`、媒体键等都算作「在打字」——单独按一下 Shift 或调音量就会触发宠物巡逻。

**修复**：
1. 删掉 `:85` 的死分支；
2. 把扫描集收窄成一个**显式常量列表**（`0x20` 空格、`0x30-0x39` 数字、`0x41-0x5A` 字母、`0xBA-0xC0` / `0xDB-0xDE` 标点 ≈ **53 个码**，是现在的 1/4），排除修饰键与小键盘锁定键；
3. 轮询间隔 50ms → **80~100ms**。`isTyping` 的判定阈值本来就是 1500ms（`:47`），巡逻启动还有 300ms 防抖（`pet_controller.dart:133`），把采样降到 100ms 对用户完全无感。

综合下来 FFI 调用从 ~4,460/s 降到 ~530/s，**降幅约 88%**，定时器唤醒从 20Hz 降到 10Hz。
**置信度**：高（调用次数为精确计算；CPU 占比未实测，估算量级为 0.05%~0.4%，主要收益在减少唤醒而非算力）。

---

### P1-3 🟠 每次 `growth.save()` 都走一遍 `existsSync` 链
**位置**：`lib/core/config.dart:8-13`（`AppPaths.root`）、`:15-20`（`growthDir`）、`lib/growth/growth_service.dart:109`（`_file` getter）

```dart
static Directory get root {
  final dir = Directory('$appData\\zoo_desktop_pet');
  if (!dir.existsSync()) dir.createSync(recursive: true);   // 每次访问都 stat 一遍
  return dir;
}
static Directory get growthDir {
  final dir = Directory('${root.path}\\growth');            // → 再触发一次 root
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
```
```dart
File get _file => File('${AppPaths.growthDir.path}\\$animalId.json');   // 每次 save 都走完整链
```

一次 `growth.save()` = 构造 2 个 `Directory` + **2 次 `existsSync` 系统调用**，纯属重复劳动。目录在应用生命周期内不会消失。

**修复**：改成 `static final Directory root = ...`（懒初始化，只求值一次），`growthDir` / `skinDir` 同理。约 10 行，零风险。
**置信度**：高。

---

### P1-4 🟠 `_checkAchievements()` 每分钟同步读遍全部成长档案
**位置**：`lib/pet/pet_controller.dart:113-122`，触发链 `growth_service.dart:158`（分钟 tick）→ `pet_controller.dart:83-89`（`_onGrowthTick`）

```dart
void _checkAchievements() {
  final stats = AchievementsService.aggregate(
      GrowthSnapshot.loadAll(), achievements.pomodoros);   // ← listSync + N×readAsStringSync + N×jsonDecode
  ...
}
```

`GrowthSnapshot.loadAll()`（`growth_service.dart:66-84`）会 `listSync()` 整个 `growth/` 目录，然后**同步**读取并解析每一个 JSON。用户用过 26 只动物后，这就是**每 60 秒在 UI isolate 上做 ~30 次文件系统调用 + 26 次 JSON 解析**。

而成就判定所需的统计量里，除了当前动物，其余 25 只的数值在运行期**根本不会变**（它们没有活跃的 `GrowthService`）。

**修复**：
- 在 `AchievementsService` 里缓存「其他动物」的快照，只在启动时加载一次；当前动物的数据直接从内存里的 `growth` 实例取，不读盘；
- 或者最简单：把检测频率从「每分钟」降到「每 5 分钟 + 关键事件后」（`feed()` / 番茄钟完成 / 升级时），成就本身不是秒级需求。

**置信度**：高。

---

### P1-5 🟠 一次点击/喂食触发 2–3 次同步写盘
**位置**：`pet_controller.dart:404-425`（`interact`）、`:427-448`（`feed`）

`interact()` 的落盘链：
1. `growth.interact()` → `save()`（写 `growth\<id>.json`，含最多 200 条 events 的 pretty-print JSON）
2. `daily.add('interact')` → `_save()`（写 `daily_tasks.json`）
3. 若任务达成 → `_applyTaskReward()` → `growth.grantExp()` → `save()`（**再写一次同一个文件**）

`feed()` 在此基础上还追加 `_checkAchievements()` → 26 次读（见 P1-4）。

全部是 `writeAsStringSync`，全部在 UI isolate 上。单次点击最多 **3 次写 + 28 次读**的同步磁盘操作，机械硬盘或杀毒软件实时扫描介入时会造成可感知卡顿。

**修复**：
- 引入**脏标记 + 合并落盘**：`save()` 只置 `_dirty = true`，由一个 2~5 秒的节流定时器统一 flush；`_exit()` / `_restart()` / `dispose()` 时强制 flush（这三处已有 `growth.save()` 调用，改成 `flush()` 即可）；
- 或者最小改动：把 `save()` 换成 `writeAsString(..., flush: true)` 的异步版本 + `unawaited()`，至少不阻塞 UI 线程（但要配合 P0-3 的原子写，否则并发写更危险）。

推荐前者，顺带解决 P0-3 的写入频次问题。
**置信度**：高。

---

### P1-6 🟠 `AppConfig.save()` 每次都重新做一次 DPAPI 加密
**位置**：`lib/core/config.dart:88-91`（`_encryptKey`）、`:171-192`（`save` → `ai.toJson()`）

```dart
static String _encryptKey(String key) {
  if (key.isEmpty) return '';
  final cipher = Dpapi.protect(key);        // CryptProtectData + base64
  return cipher == null ? key : '$_cipherPrefix$cipher';
}
```

`onWindowMoved` 有 1 秒防抖（`main.dart:158-166`），也就是说**拖着宠物满屏走的时候，每秒都会执行一次 Win32 `CryptProtectData` + base64 编码 + 整个 config.json 重写**。

而且 DPAPI 输出带随机盐，每次密文都不同 → `config.json` 内容持续抖动，对做备份/同步/diff 的用户不友好。

**修复**：在 `AiConfig` 里缓存 `(明文 → 密文)`，仅当 `apiKey` 实际变更时才重新加密；`toJson()` 复用缓存值。约 12 行。
**置信度**：高。

---

### P1-7 🟡 5 层嵌套 `Transform` 每帧重建
**位置**：`lib/pet/pet_page.dart:525-546`

```dart
return Opacity(
  child: Transform.translate(          // 层 1
    child: Transform.rotate(           // 层 2
      child: Transform.scale(          // 层 3
        child: Transform.flip(         // 层 4
          child: child,
```

`_breath` 是 `repeat(reverse: true)`（`pet_page.dart:65-67`），意味着**这个 builder 以 60fps 永久运行**，每帧构造 4 个 Transform widget + 4 次矩阵运算 + 4 个 render object 更新。

好消息是 `child` 已经通过 `AnimatedBuilder` 的 `child:` 参数做了缓存（`_PetVisual` 不重建），`RepaintBoundary` 也套了（`:417`）——**架构是对的，只是变换链太碎**。

**修复**：把 translate / rotate / scale / flip 合并成**一个** `Transform(transform: matrix)`：
```dart
final m = Matrix4.identity()
  ..translate(0.0, bounceY + patrolBob)
  ..rotateZ(spinAngle + patrolTilt + yawnTilt + moodTilt)
  ..scale(squishX * (2 - stretch).clamp(0.9, 1.1) * spinShrink,
          breathScale * squishY * stretch * spinShrink * wingFlap * yawnScaleY)
  ..rotateY(_patrolFlipX ? math.pi : 0.0);   // flipX 等价于绕 Y 转 180°
```
4 层 → 1 层，每帧少 3 个 widget + 3 次矩阵乘法。
**置信度**：高（结构确认）。实际帧时间收益未实测，估计在 5%~15% 量级。

---

### P1-8 🟡 隐藏窗口时轮询服务不停
**位置**：`lib/main.dart:152-161`（`_toggleVisible`）、`lib/core/click_through.dart:122-125`

`_toggleVisible()` 做了正确的一半：`windowManager.hide()` + `TickerMode(enabled: _visible)` 暂停所有动画 ticker ✓。

但漏了另一半：
- `ClickThroughService` 的 100ms 定时器**继续运行**（每 tick 还有 2 次 `calloc`/`free`，见 `click_through.dart:129-141`）——窗口都隐藏了，判断「光标是否在宠物矩形内」毫无意义；
- `PetController` 的 `_blinkTimer` / `_actionTimer` / `_greetTimer` 继续触发 `notifyListeners()`。`TickerMode` 只静音 ticker，**不阻止 `ListenableBuilder` 重建**，所以隐藏状态下宠物仍在「眨眼」并重建 widget 树、仍会弹出没人看得见的气泡。

**修复**：`AppShell` 把 `_visible` 传给 `PetController` 和 `ClickThroughService`，隐藏时 `stop()` / 跳过状态机推进，显示时恢复。约 20 行。
**附带**：`click_through.dart` 的 `pt` / `rc` 两个 `calloc` 缓冲区应在 `start()` 时分配一次、`stop()` 时释放，而不是每 100ms 分配释放（现在 = **20 次 native malloc/free 每秒**）。
**置信度**：高。

---

### P1-9 🟡 巡逻期间以 60Hz 调用 `windowManager.setPosition`
**位置**：`lib/pet/pet_page.dart:235-236`、`:250-262`

```dart
_patrolMoveTimer = Timer.periodic(
    const Duration(milliseconds: 16), (_) => _updatePatrolPosition());
```

`_updatePatrolPosition()` 每次都 `await`-less 调用 `windowManager.setPosition()` → 走 MethodChannel → 原生 `SetWindowPos` → **DWM 重新合成整个置顶透明窗口**。以 60Hz 连续做这件事 4~5 秒（`_patrolWave` 周期，`pet_page.dart:84-86`），是巡逻期间 CPU/GPU 的主要开销来源，也可能与 `ClickThroughService` 的 100ms 轮询、`onWindowMoved` 的防抖存档互相打架（`setPosition` 会触发 `onWindowMoved` → 1 秒后把**巡逻中的临时坐标**当成用户位置存进 config！）。

⚠️ **这里可能还藏着一个数据正确性 bug**：巡逻结束时 `_stopPatrolAnimation()` 会把窗口移回 `_patrolOrigin`，同样触发 `onWindowMoved`，1 秒后存盘。正常情况能存回正确位置。但如果用户在巡逻进行中退出应用（`_exit()` 不经过 `onWindowMoved` 的防抖回调），config 里可能留下一个偏移了 ±100px 的坐标。建议实测确认。

**修复**：
1. 巡逻期间置一个 `_patrolling` 标志，让 `onWindowMoved` 直接 return，不存档、不做贴边判定；
2. 定时器 16ms → 33ms（30fps），巡逻是缓慢的正弦漂移，30fps 肉眼无差别，合成次数直接减半。

**置信度**：定时器频率与调用链为高；「存档被污染」为中（需实测）。

---

### P1-10 🟡 `ModelPetView` 每帧软件重渲染最多 6 万面
**位置**：`lib/skin/model_pet_view.dart:29-36`（`_tick` → `_scene.update()`）、`lib/skin/skin_service.dart:21`（`_maxObjFaces = 60000`）

`_sway` 是 4500ms 的 `repeat(reverse: true)`，`_tick` 每帧调用 `_scene?.update()`。`flutter_cube` 是**纯 Dart + Canvas 的 CPU 软件渲染**，没有 GPU 加速。6 万面 @ 60fps 的软件光栅化会直接把一个 CPU 核心吃满。

`_maxObjFaces = 60000` 这个上限对 `flutter_cube` 而言**过于宽松**——注释说「会导致卡顿」，但 6 万面已经不是卡顿而是不可用。

**修复**（任选，成本递增）：
1. 把上限降到 **5,000~8,000 面**（桌面宠物 96~192px 的显示尺寸，这个面数完全看不出差别），并把提示文案改成实际阈值；
2. 摆动动画从每帧 `update()` 降到 ~20fps（`_sway` 改用 Timer 驱动，或 `_tick` 内做帧间隔节流）；
3. 长远看，`flutter_cube: 0.1.1` 已多年未更新，若 3D 皮肤是重点方向，考虑换 `flutter_gl` / `three_dart` 或直接嵌 `Texture` + 原生渲染；若不是重点，考虑**移除该依赖**（见 P2-2）。

**置信度**：中高（flutter_cube 为 CPU 渲染这一点基于其实现方式，未做性能实测）。

---

## P2 · 体积与依赖

### P2-1 🟠 26 张 1024×1024 PNG = 21.1 MB，占发布包 40%
**实测数据**（读取 PNG IHDR 得到，非估算）：

| 项 | 值 |
|---|---|
| PNG 数量 / 分辨率 / 位深 | 26 张，**全部 1024×1024**，8-bit，colorType=6（RGBA） |
| PNG 合计 | **21.13 MB**（单张 520 KB ~ 1,114 KB，均值 ~832 KB） |
| SVG 合计（兜底渲染用） | 718 KB |
| `assets/animals/` 合计 | 22.9 MB |
| Release 构建产物合计 | **56.4 MB** |
| **资源占比** | **40.6%** |

而实际显示尺寸（`pet_page.dart:683`）：`size = 96 * scale`，`scale ∈ [0.6, 2.0]` → **最大 192 逻辑像素**。`cacheWidth: (size * dpr).round()` 在 DPR=2.0 时解码到 384px，DPR=3.0 时 576px。

**1024×1024 比最坏情况所需（576px）还大 78%。**

**修复**：把所有 PNG 降采样到 **512×512**（覆盖 DPR ≤ 2.67，桌面场景足够），并用 `oxipng` / `pngquant` 做无损或视觉无损压缩。

预期效果：21.1 MB → **约 4~6 MB**（降采样约 4× + 压缩再省 20~30%），发布包 56.4 MB → **约 40 MB**。

⚠️ **注意保留原图**：`assets/animals/` 里的 1024px 原图应移入一个不参与构建的目录（如 `_source_assets/`，加进 `.gitignore` 之外的版本管理但不在 `pubspec.yaml` 声明），以便将来出高分屏版本或做宣传素材。当前 `.gitignore` 已有 `/assets/remove_background/` 的先例，可参照。

**顺带**：26 个 SVG（718 KB）是「PNG 加载失败时的兜底」（`pet_page.dart:702-708`）。PNG 是打包进 asset bundle 的，加载失败几乎不可能发生。这层兜底 + 第三层 emoji 兜底属于三重保险，可以只留 emoji 那一层，再省 718 KB 和 `flutter_svg` 依赖（**但要先确认 `flutter_svg` 没有别处在用**——检索结果显示仅 `pet_page.dart:6` 一处 import，所以确实可以移除）。
**置信度**：体积/分辨率为实测；压缩后大小为估算。

---

### P2-2 🟡 两个完全未使用的直接依赖
**证据**：对 `lib/` 全局检索 `path_provider` / `cupertino` / `CupertinoIcons` / `getApplicationSupportDirectory` → **0 匹配**。

| 依赖 | 状态 | 说明 |
|---|---|---|
| `path_provider: ^2.1.6` | **未使用** | README 第 2 节自己标注为「预留」。它会拉入 Windows 原生插件（`path_provider_foundation` / `path_provider_windows`）并编进 Release。 |
| `cupertino_icons: ^1.0.8` | **未使用** | Flutter 模板默认带的。本项目是 Windows-only + Material 3，无 Cupertino 组件。 |

**修复**：从 `pubspec.yaml` 删除两者。

但要注意 README 第 5.1 节明确写了「跨平台时应改用 `path_provider` 的 `getApplicationSupportDirectory()`」——所以 `path_provider` 是**有意的技术债标记**。建议：现在就删掉（减少当前包体），把「改用 path_provider」写进跨平台迁移清单，真要迁移时再加回来。同时 `AppPaths`（`config.dart:6-32`）目前用 `Platform.environment['APPDATA']` + 字符串拼 `\\`，**只能在 Windows 上工作**，这个约束应该在代码注释里也写明，而不只在 README。

**置信度**：高（零引用已检索确认）。

---

### P2-3 🟡 `flutter_cube: 0.1.1` — 单一可选功能绑定一个陈旧依赖
`pubspec.lock:201-208` 确认解析版本为 `0.1.1`。它**只**服务于「上传 OBJ 3D 模型皮肤」这一个可选功能（引用点：`skin_service.dart:7` 的 `loadObj`、`model_pet_view.dart` 整个文件）。

代价：额外的原生/Dart 体积、CPU 软件渲染的性能天花板（见 P1-10）、以及一个长期未维护的依赖带来的升级阻力。

**建议**：先看一下实际使用情况——如果极少有人上传 OBJ，考虑把 3D 皮肤降级为「实验性功能」或直接下线，删掉 `flutter_cube` + `model_pet_view.dart` + `skin_service.pickModel()`，能同时消掉 P1-10 和一部分 P2-3。**这是个产品决策，需要用户拍板，不建议直接动手。**
**置信度**：依赖关系为高；「是否值得移除」需要用户输入。

---

### P2-4 🟡 依赖树里有一个被撤回（retracted）的包
`flutter pub get` 输出：
```
jni 1.0.1 (retracted, 1.0.3 available)
jni_flutter 1.0.1 (1.0.3 available)
```

`jni` 是 `file_selector` → `objective_c` 链路带进来的传递依赖（服务于 Android/iOS，Windows 构建不会编译它），所以**实际风险很低**。但 lockfile 里留着 retracted 版本是供应链卫生问题。

**修复**：`flutter pub upgrade jni jni_flutter`，或在 `pubspec.yaml` 加 `dependency_overrides`。同时 `flutter pub outdated` 显示 30 个包有更新版本（受约束限制），建议做一次例行 `flutter pub upgrade` 并跑一遍 analyze + test。
**置信度**：高（pub 自身报告）。

---

## P3 · 可维护性与测试

### P3-1 🟡 窗口尺寸 280×380 在三处硬编码
| 位置 | 写法 |
|---|---|
| `lib/main.dart:19` | `const Size kPetWindowSize = Size(280, 380);` ← 唯一真源 |
| `lib/pet/pet_page.dart:99` | `const w = 280.0, h = 380.0;`（`_petHitRect`） |
| `lib/pet/pet_page.dart:172` | `const w = 280.0, h = 380.0;`（`_openMenu`） |

README 第 3.3 节明确把「调整窗口大小：`lib/main.dart` 顶部的 `kPetWindowSize`」写成二开指引，但**改了它并不会同步这两处** → 点击穿透的命中矩形会错位（宠物能看见但点不着，或点空白处也触发），右键菜单位置钳制也会算错。这是一个**文档与实现不一致导致的陷阱**。

**修复**：`pet_page.dart` 直接 `import '../main.dart'` 或把 `kPetWindowSize` 移到一个共享常量文件（更干净），两处改用 `kPetWindowSize.width/height`。6 行。
**置信度**：高。

---

### P3-2 🟡 `_menuHeight = 320` 是手工测量值，菜单一改就崩
**位置**：`lib/pet/pet_page.dart:167-169`

```dart
/// 菜单实际最大高度（压缩后的菜单 ≈299px，留余量用于位置钳制）
static const double _menuHeight = 320;
```

`_openMenu` 用 `dy.clamp(8.0, h - _menuHeight - 8.0)` = `clamp(8, 52)` 来防菜单溢出窗口。这个 320 是**手工估算 + 留余量**，与 `_buildMenu()`（`:266-300`）的实际内容没有任何联动。往菜单里加一项（约 +30px）就会让菜单底部超出 380px 窗口而被裁掉，且没有任何编译期或运行期提示。

**修复**：给菜单套一层测量（`LayoutBuilder` + `onSizeChanged`，或渲染后用 `RenderBox.size` 回读），把实测高度反馈给钳制逻辑；或者干脆把菜单渲染成一个独立的可滚动区域，高度上限用 `min(实际, 窗口高-16)`。
**置信度**：高。

---

### P3-3 🟡 两个巨型文件 + 成长卡片 UI 重复实现
| 文件 | 行数 | 承担的职责 |
|---|---|---|
| `lib/pet/pet_page.dart` | **946** | 8 个 AnimationController、巡逻动画状态机、右键菜单、气泡、成长卡片、番茄钟 chip、宠物视觉、命中测试 |
| `lib/settings/settings_page.dart` | **840** | 成长档案浏览器、动物选择、皮肤上传、大小/巡逻/休眠、行为开关、番茄钟+任务+成就（已委托 `play_sections.dart`）、AI 配置 |

**明确的重复**：`pet_page.dart:790-880` 的 `_GrowthCard` 与 `settings_page.dart:232-345` 的 `_buildGrowthSection` 是**同一个 UI 的两份实现**——同样的等级徽章渐变、同样的经验条 `Stack` + `FractionallySizedBox`、同样的 `_row`/`_growthRow`、同样的 `_moodEmoji`（`pet_page.dart:891` 与 `settings_page.dart:222` 逐字相同）。改一处忘另一处是必然的。

**修复**：
1. 抽出 `lib/widgets/growth_stats_panel.dart`，接收一个统一的只读视图模型（`GrowthSnapshot` 已经很适合当这个角色，让 `GrowthService` 暴露一个 `toSnapshot()`），两处共用；`_moodEmoji` 提到 `core/` 里；
2. `pet_page.dart` 把巡逻动画状态机（`:56-60, 205-262`）拆到 `patrol_animation.dart`，右键菜单（`:167-171, 266-380`）拆到 `pet_menu.dart`；
3. `settings_page.dart` 的 `build()`（`:426-745`，**320 行的单个方法**）按区块拆成 `_buildGrowthBlock()` / `_buildAnimalBlock()` / `_buildBehaviorBlock()` / `_buildAiBlock()`——`_buildSkinSection()` 已经是这个模式了，照抄即可。

**置信度**：高（重复已逐段比对确认）。

---

### P3-4 🟡 `growth.events` 写了 200 条，没有任何 UI 读它
**证据**：全局检索 `\.events` → 只在 `growth_service.dart` 内部（`_load` / `save` / `addEvent`）出现。`_GrowthCard` 和设置页的成长区块都**不展示事件流**。

写入点有 8 处（`pet_controller.dart:119/239/327/385/441`，`growth_service.dart:130/154/225`），每次 `save()` 都把最多 200 条事件 pretty-print 序列化进 JSON——**而这是每分钟都要做的事**（见 P1-5）。

也就是说：一份从未被消费的数据，贡献了存档文件的绝大部分体积和序列化开销。

**修复**（二选一，都是好选择）：
- **展示它**：在成长卡片或设置页加一个「相处时光轴」，把 `achievement` / `levelUp` / `pomodoro` / `birth` 事件渲染成时间线。这直接强化产品的「陪伴感」，而数据已经在盘上了，**性价比极高**；
- **删掉它**：移除 `events` 字段与 8 个 `addEvent` 调用，存档体积和序列化时间大幅下降。

推荐第一个。
**置信度**：高。

---

### P3-5 🟡 `WindowUtils.autoStartEnabled()` 是死代码，导致设置页显示陈旧的自启动状态
**证据**：全局检索 `autoStartEnabled` → 仅 `window_utils.dart:78` 的定义处，**零调用**。

`SettingsPage` 的 `_autoStart` 初值取自 `cfg.autoStart`（`settings_page.dart:69`），也就是**只读配置里记的意图，从不核对注册表的实际状态**。

**失败场景**：用户用系统「启动应用」设置页、或安全软件、或手动 regedit 关掉了 `HKCU\...\Run\zhuazhua` → 爪爪设置页仍然显示「开机自启动：开」→ 用户以为开着，下次开机没起来，且没有任何线索。

**修复**：`initState` 里用 `WindowUtils.instance.autoStartEnabled()` 校正 `_autoStart`（若与 config 不一致，以注册表为准并回写 config）。5 行，且能顺便让已写好的函数不再是死代码。
**置信度**：高。

---

### P3-6 🟡 测试只覆盖皮肤模块，纯逻辑单元零覆盖
**现状**：`test/` 下 2 个文件、6 个测试，全部通过，全部围绕 `SkinService` / `ModelPetView` / `Pseudo3DImage`。测试质量本身不错（去背景四角断言、路径穿越 6 种变体、OBJ 面数正则）。

**覆盖缺口**——以下全是**无副作用的纯逻辑**，不需要 widget test，写起来极快：

| 模块 | 该测什么 | 为什么值得测 |
|---|---|---|
| `growth_service.dart` | `_gainExp` 连续升级循环、`expToNext = 100*level` 曲线、`mood` 的 `clamp(0,100)`、互动/喂食的 60 秒经验冷却、`events` 200 条截断 | 成长是核心玩法，数值错了用户立刻能感觉到 |
| `achievements.dart` | `aggregate()` 的跨档案聚合（max vs sum 混用，容易写错）、`checkAll()` 只返回**新**解锁、重复调用幂等 | `maxLevel`/`maxMood`/`maxDays` 取 max 而 `totalInteractions` 取 sum，这种混合语义正是回归高发区 |
| `daily_tasks.dart` | `_rollover()` 跨天清零、`add()` 只在**首次**达标时返回 def（重复调用必须返回 null，否则奖励会重复发放）、`clamp` 显示 | 奖励重复发放 = 数值通胀，且很难在手工测试中发现 |
| `config.dart` | `AppConfig` → JSON → `AppConfig` 往返一致；`AiConfig` 明文旧档自动迁移为 `dpapi:` 密文；损坏 JSON 回落默认值 | 迁移逻辑（`config.dart:93-99`）是一次性的，出错就永久丢密钥 |
| `pet_controller.dart` | `_resolvePatrolDirection()` 三种配置 + 未知值兜底；`_timePhrase()` 的 7 个时段边界（5/9/12/14/18/23 点）与周末分支 | 边界条件密集，`hour >= 18 && hour < 23` 这类写法很容易在改动时漏掉 23 点 |
| `settings_page.dart` | `_isUnsafeHttpUrl()`：localhost / 127.0.0.1 / `[::1]` 放行，公网 http 拦截，https 放行，无 scheme / 畸形 URL 不崩 | 这是**安全边界**，最该有测试 |
| `animals.dart` | `kAnimals` 的 `id` 唯一性、每个 id 都有对应 PNG 资源、`animalById()` 未知 id 回落首个 | id 是资源文件名 + 存档文件名，重复会静默串档 |

**另外两个测试基建问题**：
1. 测试用 `File('_test_assets/test_white_bg.png')` **相对路径**（`skin_pipeline_test.dart:11`、`skin_render_test.dart:12`）→ 只有在项目根目录执行 `flutter test` 才能通过，CI 里换个 cwd 就全红。改用 `Platform.script` 或 `Directory.current` 显式解析。
2. `GrowthService` / `AppConfig` / `AchievementsService` / `DailyTaskService` 都**硬编码 `AppPaths`**（`config.dart:6-32`，依赖 `%APPDATA%` 环境变量），无法注入临时目录 → 这几个模块事实上**不可单测**。建议给 `AppPaths` 加一个 `@visibleForTesting static String? overrideRoot`，或改成构造函数注入 `Directory root`。这是解锁上表大部分测试的前置条件。

**置信度**：高。

---

### P3-7 🟢 `analysis_options.yaml` 仍是模板默认值
**位置**：`analysis_options.yaml:22-25`，`rules:` 下只有两行被注释掉的示例，**没有启用任何额外规则**。

这个项目里有几类已被证实存在的问题，恰好都能被现成的 lint 规则自动捕获：

| 建议启用的规则 | 能抓到本项目的什么问题 |
|---|---|
| `unawaited_futures` | P0-5 的 `Process.start` / `trayManager.destroy()` 未 await；`pet_page.dart` 里大量 fire-and-forget 的 `windowManager.setPosition` |
| `cancel_subscriptions` | `main.dart:126` 与 `pet_controller.dart:129` 的 `StreamSubscription` 从未保存也从未 cancel |
| `close_sinks` | `keyboard_hook.dart` 的三个 broadcast controller |
| `use_build_context_synchronously` | `settings_page.dart` 多处 `await` 之后用 `context`（部分已有 `if (mounted)` 保护，但不一致） |
| `avoid_slow_async_io` | 项目大量用同步 I/O，这条能防止未来无意引入慢速异步 API |
| `always_declare_return_types` / `prefer_final_locals` | 通用可读性 |
| `unnecessary_lambdas` / `prefer_const_constructors` | Flutter 性能相关（`prefer_const_constructors` 已在 flutter_lints 里） |

**修复**：分批启用，先开 `unawaited_futures` + `cancel_subscriptions` + `use_build_context_synchronously` 这三条（收益最高），修完告警再开其余。
**置信度**：高（规则与问题的对应关系已逐条核对代码）。

---

### P3-8 🟢 `pubspec.yaml` 元数据仍是脚手架默认值
**位置**：`pubspec.yaml:2`

```yaml
description: "A new Flutter project."
```

项目已有完善的 README、LICENSE(Apache-2.0)、`windows/runner/Runner.rc` 里的产品信息，唯独 pubspec 的 description 没改。它会出现在 `flutter build` 的产物元数据和任何未来的打包工具（Inno Setup / MSIX）里。

**修复**：改成 `"26 种卡通动物常驻桌面的 Windows 桌面宠物"` 之类，并顺手补上 `homepage` / `repository`（`publish_to: 'none'` 已设置，不影响发布）。
**置信度**：高。

---

## P4 · 产品与体验（低优先，供参考）

| # | 点 | 位置 | 说明 |
|---|---|---|---|
| P4-1 | 无崩溃兜底与日志 | `lib/main.dart:24-77` | 没有 `runZonedGuarded`、没有 `FlutterError.onError`。一个 24/7 常驻的应用静默崩溃后，用户和开发者都拿不到任何信息。配合 P0-3 的静默吞异常，形成「出问题完全不可观测」的组合。建议加一个 `%APPDATA%\zoo_desktop_pet\crash.log`（滚动保留最近 3 份）。 |
| P4-2 | DWM「nudge」hack 可能已冗余 | `lib/main.dart:59-74` | 首帧后在 0/300ms/1s/3s 四个时间点各做一次 `setSize(+1)` → `setSize(-1)`，用来治「开机自启动后窗口不接收鼠标输入」（commit `742e402`）。但**之后**又加了点击穿透的 100ms 自愈轮询（commit `f5c919e`，`click_through.dart:151-162`），后者已经在持续强制同步 `WS_EX_*` 实际状态。两套机制可能在治同一个病。建议实测：临时注释掉 nudge，在开机自启动场景下验证是否复发。若已不复发，可删掉 4 次窗口尺寸抖动（每次都可能触发 DWM 重合成）。 |
| P4-3 | 隐藏状态下仍累计「陪伴时长」 | `growth_service.dart:158` | `_tick()` 无条件 `totalOnlineMinutes++`，与窗口是否可见无关。用户按 `Ctrl+Alt+P` 隐藏宠物 8 小时，回来发现「陪伴时长 +8 小时」「解锁成就：常驻居民」。这可能是设计意图（后台陪伴也算陪伴），也可能是漏洞——**需要产品拍板**。若要区分，`_toggleVisible` 时通知 `GrowthService` 暂停计时即可。 |
| P4-4 | AI Base URL 容错不足 | `ai/ai_client.dart:28-31` | 用户若填完整的 `https://api.x.com/v1/chat/completions`，会拼成 `.../chat/completions/v1/chat/completions` 而 404，只看到「AI 连接失败，请检查地址/密钥/模型名」。建议在拼接前检测是否已以 `/chat/completions` 结尾；或在设置页 hint 里更明确地说明该填到哪一级。 |
| P4-5 | 请求缺 `User-Agent` | `ai/ai_client.dart:32-37` | 部分网关/WAF 会拒绝无 UA 的请求。加一个 `'User-Agent': 'zoo_desktop_pet/1.1.0'` 成本为零。 |
| P4-6 | `interact()` 无并发去重 | `pet_controller.dart:418-424` | 快速连点会以 30% 概率并发发起多个 AI 请求（`_rand.nextDouble() < 0.3`），后返回的覆盖先返回的气泡，且每次都会 `growth.addEvent('aiChat', ...)`。建议加一个 `_aiInFlight` 标志。 |
| P4-7 | 番茄钟每秒触发 5 个 `ListenableBuilder` 重建 | `pet_page.dart:400/551/583/614` 等 | `build()` 里有 5 处独立的 `ListenableBuilder(listenable: c)`，`_pomoTick()`（`pet_controller.dart:337`）每秒 `notifyListeners()` 一次 → 每秒 5 次子树重建，只为更新一个倒计时文本。把 `pomoRemaining` 单独包成 `ValueNotifier<int>`，只让倒计时 chip 订阅它。 |
| P4-8 | 全部字符串硬编码中文 | 全项目 | 无 `flutter_localizations`、无 ARB。当前定位是中文用户，不是问题；但如果将来想上英文版，需要一次全量抽取。现在至少可以养成「新字符串集中管理」的习惯。 |
| P4-9 | 测试资源目录名以 `_` 开头易被工具忽略 | `_test_assets/` | 部分打包/同步工具默认跳过 `_` 前缀目录。已被 git 跟踪所以没问题，但 `flutter pub publish`（虽然设了 `publish_to: none`）等场景要留意。 |

---

## 5. 建议实施顺序

按「**收益 / 风险比**」排序，分四批。每批之间跑一次 `flutter analyze && flutter test` 作为闸门。

### 第 1 批 · 快赢（预计 1~2 小时，零风险，全是删代码或加约束）
| 项 | 动作 | 预期收益 |
|---|---|---|
| P1-1 | 删除死掉的打字速度机制（含 60Hz 永久定时器） | **-45 行；每秒少 62 次 isolate 唤醒** |
| P1-2 | 删死分支 + 键码集收窄到 53 个 + 轮询 50→100ms | **FFI 调用 -88%（4,460/s → 530/s）** |
| P1-3 | `AppPaths` 的 `root`/`growthDir`/`skinDir` 改 `static final` | 每次存档少 2 次 syscall |
| P2-2 | 删除 `path_provider`、`cupertino_icons` | 减少原生插件编译产物 |
| P3-1 | `pet_page.dart` 两处 `280.0/380.0` 改用 `kPetWindowSize` | **消除文档陷阱**（改窗口尺寸不再静默错位） |
| P3-5 | `initState` 用 `autoStartEnabled()` 校正开关状态 | 设置页不再显示陈旧状态 |
| P3-8 | 改 `pubspec.yaml` description | 元数据正确 |
| P1-8 附带 | `ClickThroughService` 的两个 `calloc` 缓冲区改为 start/stop 时分配释放 | 每秒少 20 次 native malloc/free |

### 第 2 批 · 数据可靠性（预计 2~3 小时，中风险，需要仔细测）
| 项 | 动作 |
|---|---|
| P0-3 | 抽 `AtomicJsonStore`（tmp + rename）替换全部 4 处 `writeAsStringSync`；12 处 `catch (_) {}` 改为记录日志 + 坏文件改名保留 |
| P1-5 | 存档改「脏标记 + 2~5 秒节流 flush」，`_exit`/`_restart`/`dispose` 强制 flush |
| P0-1 | 启动时把窗口坐标钳制进当前工作区，无交集则回退右下角 |
| P0-5 | `_restart()` await `Process.start`；`_exit()` 改 async + await `trayManager.destroy()` |
| P0-4 | 三处匿名 Timer 收进可取消集合 |
| P3-6 前置 | `AppPaths` 支持注入测试根目录（解锁后续所有单元测试） |

⚠️ 这一批**动的是用户存档**，改完务必用真实的 `%APPDATA%\zoo_desktop_pet\` 副本做迁移测试：旧格式能读、新格式能读、损坏文件不炸、退出时确实落盘。

### 第 3 批 · 功能正确性 + 体积（预计 2~4 小时）
| 项 | 动作 |
|---|---|
| P0-2 | `_scheduleTip()` 改幂等公开方法，`_save()` 里调用 → **保存 AI 配置即时生效** |
| P2-1 | 26 张 PNG 降到 512×512 + 压缩；原图移入不参与构建的目录 | **发布包 56 MB → ~40 MB** |
| P3-4 | 把 `growth.events` 渲染成「相处时光轴」（推荐）或删除该字段 | 强化陪伴感 **或** 大幅减少序列化开销 |
| P1-4 | 成就检测：缓存非活跃动物快照，或降频到 5 分钟 | 每分钟少 ~28 次同步 FS 操作 |
| P1-6 | `AiConfig` 缓存 DPAPI 密文 | 拖动窗口时不再每秒加密 |
| P1-9 | 巡逻期间禁用 `onWindowMoved` 存档；定时器 16→33ms | 修可能的坐标污染 + 合成次数减半 |

### 第 4 批 · 重构与测试（预计 4~6 小时，可与前三批并行推进）
| 项 | 动作 |
|---|---|
| P3-6 | 补齐 7 个模块的单元测试（见 P3-6 表格），修 `_test_assets` 相对路径 |
| P3-3 | 抽 `growth_stats_panel.dart` 消除成长卡片双实现；拆分 `pet_page.dart` / `settings_page.dart` |
| P3-7 | 分批启用 lint 规则，先 `unawaited_futures` + `cancel_subscriptions` + `use_build_context_synchronously` |
| P1-7 | 4 层 Transform 合并为单个 Matrix4 |
| P4-1 | 加 `runZonedGuarded` + 滚动崩溃日志 |
| P0-6 | `workArea()` 改 `MonitorFromWindow` + `GetMonitorInfoW`（多屏支持） |
| P1-10 / P2-3 | OBJ 面数上限降到 5k~8k；**并就 `flutter_cube` 去留做产品决策** |

---

## 6. 已经做对的部分（改动时请勿破坏）

扫描中发现以下设计**质量很高**，列出来是为了避免在重构中误伤：

1. **API Key 用 DPAPI 加密落盘**（`core/dpapi.dart`）——`CRYPTPROTECT_UI_FORBIDDEN` 标志设置正确（后台进程必须设，否则会弹窗卡死）；`asTypedList` 之后**先拷贝再 `LocalFree`**（`dpapi.dart:96-98` 的注释准确指出了视图失效问题，这是个很容易踩的坑）；旧明文自动迁移的兼容逻辑（`config.dart:93-99`）考虑周到。
2. **HWND 查找按 PID 过滤**（`click_through.dart:100-118`）——遍历同标题窗口只认本进程的，并明确注释「绝不对外进程窗口设置扩展样式」。这是 commit `44503ff` 的修复，避免了误伤同名窗口，做得对。还带了 32 次迭代的防御性上限。
3. **点击穿透自愈**（`click_through.dart:151-162`）——不依赖缓存短路，每次强制对比 `GetWindowLongPtrW` 的实际值。注释把「缓存与真实状态脱节 → 窗口永久穿透」的根因写清楚了。这是教科书级的 bug 修复注释。
4. **图片处理放 `Isolate.run`**（`skin_service.dart:41-46`）——去背景是 O(像素) 的重活，没有阻塞 UI 线程。
5. **皮肤导入的多层防护**（`skin_service.dart:18-21, 30-40, 106-113, 170-178`）——文件大小 25MB / 像素 4000 万 / OBJ 6 万面三重上限（防解码炸弹），`safeRelativePath` 拒绝绝对路径、盘符、`..` 和 `.` 段（防路径穿越），**且这些防护有对应的单元测试**（`skin_pipeline_test.dart:47-56` 覆盖 6 种穿越变体）。
6. **明文 HTTP 警告**（`settings_page.dart:88-122`）——非本地 http 地址保存前弹窗确认，且正确豁免了 `localhost` / `127.0.0.1` / `[::1]` / `::1` 四种写法。
7. **AI 失败静默降级**（`ai_client.dart:53-61`）——任何异常都回落本地台词，不影响使用；且日志**只记状态码与错误类型，明确不记请求头**（含 API Key），注释写了原因。
8. **主宠物图设了 `cacheWidth`**（`pet_page.dart:698`）——按 `size * dpr` 精确解码，没有把 1024×1024 整张塞进内存。**这个做法是对的，设置页头像（P2-1）应该照抄。**
9. **`RepaintBoundary` + `TickerMode` + `AnimatedBuilder` 的 `child:` 缓存**（`pet_page.dart:417, 452-465`；`main.dart:266`）——渲染层的三个关键优化都用上了，隐藏时暂停全部 ticker 也做对了（只是漏了定时器，见 P1-8）。
10. **皮肤文件存在性缓存**（`pet_page.dart:678-680`）——注释明确说明「避免每帧同步 I/O」，说明作者已经意识到帧内 I/O 的问题。（唯一小瑕疵：这个 static Map 永不失效，换肤路径带时间戳所以会缓慢增长，但量级极小，可忽略。）
11. **README 质量**——二开指引、打包流程、FAQ、隐私与安全边界都写得很实在，甚至诚实标注了 `path_provider` 是「预留」和跨平台迁移的注意事项。**唯一的坑是 P3-1 提到的窗口尺寸指引与实现不同步。**

---

## 附录 · 扫描过程与实测数据

**执行过的验证命令**：
```
flutter analyze    → 11 issues（全部为 tool/*.dart 的 avoid_print，lib/ 零告警）
flutter test       → 6/6 passed（skin_pipeline_test 4 个 + skin_render_test 2 个）
```

**实测资源数据**（写了一个临时 Dart 脚本读 PNG IHDR，用完已删除）：
```
26 张 PNG：全部 1024×1024，8-bit，colorType=6 (RGBA)
体积区间：520 KB (ostrich) ~ 1,114 KB (red_panda)，均值 ~832 KB
PNG 合计：21.13 MB      SVG 合计：718 KB
assets/animals/ 合计：22,892,558 字节
build/windows/x64/runner/Release 合计：56,360,047 字节
资源占发布包比例：40.6%
```

**死代码确认方法**：对 `lib/` 全局正则检索标识符，确认除定义处外零引用。已确认的死代码：
- `KeyboardHookService.typingSpeed` / `typingSpeedStream` / `_decayTimer` / `_lastKeyTimestamp`（P1-1）
- `WindowUtils.autoStartEnabled()`（P3-5）
- `keyboard_hook.dart:85` 的 `if (vk >= 0x01 && vk <= 0x06) continue;`（循环从 0x20 起，永不成立）
- `path_provider` / `cupertino_icons` 两个直接依赖（P2-2）
- `GrowthService.events` 的读取侧（只写不读，P3-4）

**未实测、需运行验证的推断**（报告中已标注置信度）：
- P1-2 / P1-7 的具体 CPU 占用降幅（调用次数为精确计算，耗时占比未 profiling）
- P1-9 的「巡逻坐标污染 config」（调用链推导成立，需实机复现）
- P1-10 的 flutter_cube 渲染耗时（基于其 CPU 软件渲染的实现方式推断）
- P4-2 的 nudge hack 是否已冗余（需注释后在开机自启动场景实测）
