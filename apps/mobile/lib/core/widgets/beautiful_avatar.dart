import 'package:flutter/material.dart';

class BeautifulAvatar extends StatelessWidget {
  final String name;
  final String username;
  final double radius;

  const BeautifulAvatar({
    super.key,
    required this.name,
    required this.username,
    required this.radius,
  });

  static const List<LinearGradient> _avatarGradients = [
    LinearGradient(
      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo to Purple
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)], // Blue to Cyan
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF10B981), Color(0xFF34D399)], // Emerald to Green
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFF59E0B), Color(0xFFF97316)], // Amber to Orange
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFEC4899), Color(0xFFF43F5E)], // Pink to Rose
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  LinearGradient _getAvatarGradient(String key) {
    if (key.isEmpty) return _avatarGradients[0];
    final hash = key.codeUnits.fold(0, (prev, element) => prev + element);
    return _avatarGradients[hash % _avatarGradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _getAvatarGradient(username.isNotEmpty ? username : name);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: gradient.colors[0].withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.9,
            shadows: const [
              Shadow(
                color: Colors.black26,
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
