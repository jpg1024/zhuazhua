import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../ai/ai_client.dart';
import '../core/animals.dart';
import '../core/config.dart';
import '../core/fa_icons.dart';
import '../skin/skin_service.dart';

class SettingsPage extends StatefulWidget {
  final AppConfig config;
  final VoidCallback onClose;

  const SettingsPage({super.key, required this.config, required this.onClose});

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
  String? _status;
  bool _testing = false;
  bool _skinBusy = false;

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
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _save() {
    final animalChanged = _animalId != cfg.animalId;
    cfg.animalId = _animalId;
    cfg.ai
      ..baseUrl = _baseUrl.text.trim()
      ..apiKey = _apiKey.text.trim()
      ..model = _model.text.trim()
      ..enabled = _aiEnabled
      ..tipIntervalMinutes = int.tryParse(_interval.text) ?? 45;
    cfg.petScale = _scale;
    cfg.save();
    setState(() =>
        _status = animalChanged ? '已保存。切换动物将在重启后生效。' : '已保存。');
  }

  void _restart() {
    _save();
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
                const Row(
                  children: [
                    Icon(Fa7.paw, size: 14, color: Color(0xFF5C6BC0)),
                    SizedBox(width: 8),
                    Text('选择动物（重启后生效）',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kAnimals.map((a) {
                    final selected = a.id == _animalId;
                    return ChoiceChip(
                      label: Text('${a.emoji} ${a.name}', style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor: a.themeColor.withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _animalId = a.id),
                    );
                  }).toList(),
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
