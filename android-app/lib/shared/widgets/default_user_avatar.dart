import 'package:flutter/material.dart';

/// 内置默认用户头像（AI 绘制的简约线稿头像）。
class DefaultUserAvatar extends StatelessWidget {
  const DefaultUserAvatar({super.key, required this.size});

  final double size;

  static const String assetPath = 'assets/images/default_user_avatar.jpg';

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.scale(
          scale: 1.32,
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
