import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../ai/ai_client.dart';
import '../core/animals.dart';
import '../core/config.dart';
import '../core/fa_icons.dart';
import '../core/keyboard_hook.dart';
import '../core/window_utils.dart';
import '../growth/growth_service.dart';
import '../pet/pet_controller.dart';
import '../skin/skin_service.dart';
import 'play_sections.dart';

class SettingsPage extends StatefulWidget {
  final AppConfig config;
  final VoidCallback onClose;
  final PetController pet;

  const SettingsPage({
    super.key,
    required this.config,
    required this.onClose,
    required this.pet,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _animalId;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _interval;
  late bool _aiEnabled;
  late double _scale;
  late String _patrolDirection;
  late double _sleepTimeoutMinutes;
  late bool _edgeSnap;
  late bool _hotkeyEnabled;
  late bool _autoStart;
  String? _status;
  bool _testing = false;
  bool _skinBusy = false;

  List<GrowthSnapshot> _growthList = [];
  bool _growthDesc = true;
  String? _selectedGrowthId;

  AppConfig get cfg => widget.config;

  @override
  void initState() {
    super.initState();
    _animalId = cfg.animalId;
    _baseUrl = TextEditingController(text: cfg.ai.baseUrl);
    _apiKey = TextEditingController(text: cfg.ai.apiKey);
    _model = TextEditingController(text: cfg.ai.model);
    _interval = TextEditingController(text: '${cfg.ai.tipIntervalMinutes}');
    _aiEnabled = cfg.ai.enabled;
    _scale = cfg.petScale;
    _patrolDirection = cfg.patrolDirection;
    _sleepTimeoutMinutes = cfg.sleepTimeoutMinutes;
    _edgeSnap = cfg.edgeSnap;
    _hotkeyEnabled = cfg.hotkeyEnabled;
    _autoStart = cfg.autoStart;
    _growthList = GrowthSnapshot.loadAll();
    _sortGrowth();
    if (_growthList.isNotEmpty) _selectedGrowthId = _growthList.first.animalId;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// AI 开启且 baseUrl 为非本地 http:// → API Key 将明文传输。
  bool get _unsafeHttpAi => _aiEnabled && _isUnsafeHttpUrl(_baseUrl.text);

  static bool _isUnsafeHttpUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'http') return false;
    final host = u.host.toLowerCase();
    return host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '[::1]' &&
        host != '::1';
  }

  Future<bool> _confirmUnsafeHttp() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('不安全的连接地址', style: TextStyle(fontSize: 16)),
        content: const Text(
            'AI 地址使用了 http://（非本地地址），API Key 将以明文传输，可能被网络中间人截获。\n\n'
            '建议改用 https:// 地址；本地服务（localhost / 127.0.0.1）不受影响。',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('仍要保存')),
        ],
      ),
    );
    return proceed == true;
  }

  /// 保存配置；返回 false 表示用户取消了保存（不安全地址确认框）。
  Future<bool> _save() async {
    if (_unsafeHttpAi && !await _confirmUnsafeHttp()) {
      if (mounted) {
        setState(() => _status = '已取消保存：请改用 https:// 或本地地址');
      }
      return false;
    }
    final animalChanged = _animalId != cfg.animalId;
    cfg.animalId = _animalId;
    cfg.ai
      ..baseUrl = _baseUrl.text.trim()
      ..apiKey = _apiKey.text.trim()
      ..model = _model.text.trim()
      ..enabled = _aiEnabled
      ..tipIntervalMinutes = int.tryParse(_interval.text) ?? 45;
    cfg.petScale = _scale;
    cfg.patrolDirection = _patrolDirection;
    cfg.sleepTimeoutMinutes = _sleepTimeoutMinutes;
    cfg.edgeSnap = _edgeSnap;
    cfg.hotkeyEnabled = _hotkeyEnabled;
    cfg.autoStart = _autoStart;
    cfg.save();
    // 快捷键与开机自启动立即生效
    KeyboardHookService.instance.hotkeyEnabled = _hotkeyEnabled;
    final autoStartOk = WindowUtils.instance.setAutoStart(_autoStart);
    if (mounted) {
      setState(() => _status = !autoStartOk
          ? '已保存，但自启动写入注册表失败'
          : (animalChanged ? '已保存。切换动物将在重启后生效。' : '已保存。'));
    }
    return true;
  }

  Future<void> _restart() async {
    final saved = await _save();
    if (!saved) return;
    Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _testAi() async {
    setState(() {
      _testing = true;
      _status = '正在测试 AI 连接…';
    });
    final tmp = AiConfig(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      enabled: true,
    );
    final ok = await AiClient(tmp).test();
    if (mounted) {
      setState(() {
        _testing = false;
        _status = ok ? 'AI 连接成功！' : 'AI 连接失败，请检查地址/密钥/模型名。';
      });
    }
  }

  Future<void> _uploadImage() async {
    setState(() => _skinBusy = true);
    try {
      final r = await SkinService.pickAndProcessImage(cfg, _animalId);
      if (r.message.isNotEmpty) {
        cfg.save();
        if (mounted) setState(() => _status = r.message);
      }
    } catch (e) {
      debugPrint('upload image failed: $e');
      if (mounted) setState(() => _status = '图片处理失败，请换一张图片重试');
    } finally {
      if (mounted) setState(() => _skinBusy = false);
    }
  }

  Future<void> _uploadModel() async {
    setState(() => _skinBusy = true);
    try {
      final r = await SkinService.pickModel(cfg, _animalId);
      if (r.message.isNotEmpty) {
        cfg.save();
        if (mounted) setState(() => _status = r.message);
      }
    } catch (e) {
      debugPrint('upload model failed: $e');
      if (mounted) setState(() => _status = '模型导入失败，请检查文件后重试');
    } finally {
      if (mounted) setState(() => _skinBusy = false);
    }
  }

  void _resetSkin() {
    SkinService.clearSkin(cfg, _animalId);
    cfg.save();
    setState(() => _status = '已恢复默认形象');
  }

  void _sortGrowth() {
    _growthList.sort((a, b) => _growthDesc
        ? b.totalOnlineMinutes.compareTo(a.totalOnlineMinutes)
        : a.totalOnlineMinutes.compareTo(b.totalOnlineMinutes));
  }

  String _moodEmoji(int mood) {
    if (mood >= 80) return '😊';
    if (mood >= 50) return '🙂';
    return '😔';
  }

  /// 把分钟数格式化为"X 小时 / X.5 小时"显示
  String _fmtSleepHours(double minutes) {
    final h = minutes / 60;
    return h == h.roundToDouble() ? '${h.round()} 小时' : '$h 小时';
  }

  Widget _buildGrowthSection() {
    if (_growthList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: const Text('暂无成长记录',
            style: TextStyle(fontSize: 12, color: Colors.black38)),
      );
    }

    final selected = _growthList.firstWhere(
      (g) => g.animalId == _selectedGrowthId,
      orElse: () => _growthList.first,
    );
    final animal = animalById(selected.animalId);
    final color = animal.themeColor;
    final days = DateTime.now().difference(selected.createdAt).inDays + 1;
    final hours = selected.totalOnlineMinutes ~/ 60;
    final mins = selected.totalOnlineMinutes % 60;
    final progress = (selected.exp / selected.expToNext).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdown<String>(
          value: selected.animalId,
          items: _growthList.map((g) {
            final a = animalById(g.animalId);
            final h = g.totalOnlineMinutes ~/ 60;
            final m = g.totalOnlineMinutes % 60;
            return DropdownMenuItem(
              value: g.animalId,
              child: Row(
                children: [
                  _animalAvatar(a.id, a.emoji),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${a.name} · $h小时$m分',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedGrowthId = v),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(animal.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(animal.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color.alphaBlend(
                              Colors.black.withValues(alpha: 0.25), color))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        color,
                        Color.lerp(color, Colors.white, 0.25)!,
                      ]),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('Lv.${selected.level}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _growthRow(Fa7.star, '经验',
                  '${selected.exp}/${selected.expToNext}', color),
              const SizedBox(height: 2),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F3),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress <= 0 ? 0.001 : progress,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          color,
                          Color.lerp(color, Colors.white, 0.35)!,
                        ]),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _growthRow(Fa7.faceSmile, '心情',
                  '${_moodEmoji(selected.mood)} ${selected.mood}/100', color),
              _growthRow(Fa7.handPointer, '互动次数',
                  '${selected.totalInteractions}', color),
              _growthRow(Fa7.clock, '陪伴时长', '$hours小时$mins分钟', color),
              _growthRow(Fa7.calendarDays, '相识天数', '$days天', color),
            ],
          ),
        ),
      ],
    );
  }

  Widget _growthRow(IconData icon, String k, String v, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(k,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A))),
            const Spacer(),
            Text(v,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3A3A3A),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildSkinSection() {
    final skin = cfg.skinOf(_animalId);
    final animal = animalById(_animalId);
    String statusText;
    Widget? preview;
    if (skin.modelPath != null) {
      statusText = '3D 模型：${skin.modelPath!.split('\\').last}';
    } else if (skin.imagePath != null) {
      statusText = '自定义图片';
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(skin.imagePath!),
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          key: ValueKey(skin.imagePath),
          errorBuilder: (_, e, s) => const SizedBox.shrink(),
        ),
      );
    } else {
      statusText = '默认形象';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: animal.themeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Fa7.wandMagicSparkles, size: 13, color: animal.themeColor),
              const SizedBox(width: 8),
              Text('外观自定义（${animal.emoji} ${animal.name}）',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              ?preview,
            ],
          ),
          const SizedBox(height: 6),
          Text('当前：$statusText',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _skinBusy ? null : _uploadImage,
                icon: const Icon(Fa7.image, size: 13),
                label: const Text('上传图片', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: _skinBusy ? null : _uploadModel,
                icon: const Icon(Fa7.cube, size: 13),
                label:
                    const Text('上传3D模型 (.obj)', style: TextStyle(fontSize: 12)),
              ),
              if (!skin.isEmpty)
                TextButton.icon(
                  onPressed: _skinBusy ? null : _resetSkin,
                  icon: const Icon(Fa7.rotateLeft, size: 13),
                  label: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                ),
              if (_skinBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('图片：自动去纯色背景并加伪3D摆动；透明PNG效果最佳。3D：OBJ 格式（可带 MTL 材质与贴图）。',
              style: TextStyle(fontSize: 11, color: Colors.black38)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              color: const Color(0xFF5C6BC0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Fa7.gear, color: Colors.white, size: 15),
                  const SizedBox(width: 8),
                  const Text('爪爪 · 设置',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Fa7.xmark, color: Colors.white, size: 18),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                Row(
                  children: [
                    const Icon(Fa7.chartLine, size: 14, color: Color(0xFF5C6BC0)),
                    const SizedBox(width: 8),
                    const Text('成长记录',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_growthList.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _growthDesc = !_growthDesc;
                          _sortGrowth();
                        }),
                        icon: Icon(_growthDesc ? Fa7.arrowDown : Fa7.arrowUp,
                            size: 12),
                        label: Text('陪伴时长 ${_growthDesc ? '倒序' : '升序'}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildGrowthSection(),
                const Divider(height: 32),
                const Row(
                  children: [
                    Icon(Fa7.paw, size: 14, color: Color(0xFF5C6BC0)),
                    SizedBox(width: 8),
                    Text('选择动物（重启后生效）',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                _dropdown<String>(
                  value: _animalId,
                  items: kAnimals
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Row(
                              children: [
                                _animalAvatar(a.id, a.emoji),
                                const SizedBox(width: 8),
                                Text(a.name,
                                    style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _animalId = v);
                  },
                ),
                const SizedBox(height: 16),
                _buildSkinSection(),
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Fa7.magnifyingGlassPlus, size: 14, color: Color(0xFF5C6BC0)),
                    const SizedBox(width: 8),
                    const Text('宠物大小',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${(_scale * 100).round()}%',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF5C6BC0))),
                  ],
                ),
                Slider(
                  value: _scale,
                  min: 0.6,
                  max: 2.0,
                  divisions: 14,
                  label: '${(_scale * 100).round()}%',
                  onChanged: (v) => setState(() => _scale = v),
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Fa7.keyboard, size: 14, color: Color(0xFF5C6BC0)),
                    const SizedBox(width: 8),
                    const Text('打字时宠物移动方向',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      {'left': '左侧消失', 'right': '右侧消失', 'random': '随机'}[
                              _patrolDirection] ??
                          '左侧消失',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5C6BC0)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _dropdown<String>(
                  value: _patrolDirection,
                  items: const [
                    DropdownMenuItem(
                        value: 'left',
                        child: Text('从左侧消失，右侧进入',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'right',
                        child: Text('从右侧消失，左侧进入',
                            style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'random',
                        child: Text('随机方向',
                            style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _patrolDirection = v);
                  },
                ),
                const SizedBox(height: 4),
                const Text('重启后生效。检测到键盘输入时宠物会在 200px 范围内巡逻。',
                    style: TextStyle(fontSize: 11, color: Colors.black38)),
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Fa7.clock, size: 14, color: Color(0xFF5C6BC0)),
                    const SizedBox(width: 8),
                    const Text('休眠时间',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      _fmtSleepHours(_sleepTimeoutMinutes),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5C6BC0)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _dropdown<double>(
                  value: _sleepTimeoutMinutes,
                  items: const [
                    DropdownMenuItem(
                        value: 30.0,
                        child:
                            Text('0.5 小时', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 60.0,
                        child: Text('1 小时', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 90.0,
                        child:
                            Text('1.5 小时', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 120.0,
                        child: Text('2 小时', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 150.0,
                        child:
                            Text('2.5 小时', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 180.0,
                        child: Text('3 小时', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sleepTimeoutMinutes = v);
                  },
                ),
                const SizedBox(height: 4),
                const Text('无操作达到设定时长后，宠物自动进入休眠。修改后无需重启，1 分钟内生效。',
                    style: TextStyle(fontSize: 11, color: Colors.black38)),
                const Divider(height: 32),
                const Row(
                  children: [
                    Icon(Fa7.sliders, size: 14, color: Color(0xFF5C6BC0)),
                    SizedBox(width: 8),
                    Text('行为偏好',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                _switchRow(Fa7.magnet, '贴边吸附', '拖动到屏幕边缘自动吸附，吸附后半透明、悬停恢复',
                    _edgeSnap, (v) => setState(() => _edgeSnap = v)),
                _switchRow(Fa7.keyboard, '全局快捷键 Ctrl+Alt+P', '任意界面下显示 / 隐藏宠物',
                    _hotkeyEnabled, (v) => setState(() => _hotkeyEnabled = v)),
                _switchRow(Fa7.powerOff, '开机自启动', '登录 Windows 后自动运行（写入注册表）',
                    _autoStart, (v) => setState(() => _autoStart = v)),
                const SizedBox(height: 4),
                const Text('开关在点击「保存」后生效。',
                    style: TextStyle(fontSize: 11, color: Colors.black38)),
                const Divider(height: 32),
                PlaySections(pet: widget.pet),
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Fa7.robot, size: 14, color: Color(0xFF5C6BC0)),
                    const SizedBox(width: 8),
                    const Text('AI 助手（OpenAI 兼容格式）',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Switch(
                      value: _aiEnabled,
                      onChanged: (v) => setState(() => _aiEnabled = v),
                    ),
                  ],
                ),
                _field(_baseUrl, 'Base URL',
                    'https://api.deepseek.com/v1 或 http://localhost:11434/v1'),
                _field(_apiKey, 'API Key', '本地服务可留空', obscure: true),
                _field(_model, '模型名称', '如 deepseek-chat / qwen2.5:7b'),
                _field(_interval, '主动提示间隔（分钟）', '默认 45'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _testAi,
                      icon: const Icon(Fa7.plug, size: 13),
                      label: const Text('测试连接'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Fa7.floppyDisk, size: 13),
                        label: const Text('保存')),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                        onPressed: _restart,
                        icon: const Icon(Fa7.rotateRight, size: 13),
                        label: const Text('保存并重启')),
                  ],
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_status!,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF5C6BC0))),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _animalAvatar(String id, String emoji, {double size = 22}) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/animals/$id.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            Text(emoji, style: TextStyle(fontSize: size * 0.8)),
      ),
    );
  }

  Widget _switchRow(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF5C6BC0).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: const Color(0xFF5C6BC0)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: Colors.black26),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
