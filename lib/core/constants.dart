import 'package:flutter/material.dart';

/// 宠物窗口尺寸（与 main.dart 的 kPetWindowSize 保持一致，作为两处共享真源）。
const Size kPetWindowSize = Size(280, 380);

/// 单独暴露宽高，供 pet_page.dart 内计算命中矩形和菜单钳制时使用。
const double kPetWindowWidth = 280;
const double kPetWindowHeight = 380;

/// 设置页窗口尺寸。
const Size kSettingsWindowSize = Size(720, 840);
