import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import '../../../../core/widgets/glassmorphic_container.dart';

class ConstellationNode {
  double x;
  double y;
  double vx;
  double vy;

  ConstellationNode({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  });
}

class NetworkConstellationPainter extends CustomPainter {
  final List<ConstellationNode> nodes;
  final Color color;

  NetworkConstellationPainter(this.nodes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    // Draw lines
    for (int i = 0; i < nodes.length; i++) {
      final nodeA = nodes[i];
      final posA = Offset(nodeA.x * size.width, nodeA.y * size.height);
      
      for (int j = i + 1; j < nodes.length; j++) {
        final nodeB = nodes[j];
        final posB = Offset(nodeB.x * size.width, nodeB.y * size.height);
        
        final distance = (posA - posB).distance;
        if (distance < 90) {
          final opacity = (1.0 - (distance / 90)).clamp(0.0, 0.35);
          linePaint.color = color.withValues(alpha: opacity);
          canvas.drawLine(posA, posB, linePaint);
        }
      }
    }

    // Draw nodes
    for (var node in nodes) {
      final pos = Offset(node.x * size.width, node.y * size.height);
      paint.color = color.withValues(alpha: 0.5);
      canvas.drawCircle(pos, 2.5, paint);
      
      paint.color = color.withValues(alpha: 0.12);
      canvas.drawCircle(pos, 5.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _constellationController;
  final List<ConstellationNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize nodes
    final random = Random();
    for (int i = 0; i < 24; i++) {
      _nodes.add(
        ConstellationNode(
          x: random.nextDouble(),
          y: random.nextDouble(),
          vx: (random.nextDouble() - 0.5) * 0.35,
          vy: (random.nextDouble() - 0.5) * 0.35,
        ),
      );
    }

    _constellationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        _updateNodes();
      })..repeat();
  }

  void _updateNodes() {
    if (!mounted) return;
    setState(() {
      for (var node in _nodes) {
        node.x += node.vx * 0.01;
        node.y += node.vy * 0.01;
        
        if (node.x < 0 || node.x > 1.0) node.vx = -node.vx;
        if (node.y < 0 || node.y > 1.0) node.vy = -node.vy;
        
        node.x = node.x.clamp(0.0, 1.0);
        node.y = node.y.clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _constellationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF13131B), // Obsidian Background
      body: Stack(
        children: [
          // Background Atmospheric Gradients
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              key: const ValueKey('topGlow'),
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -150,
            child: Container(
              key: const ValueKey('bottomGlow'),
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.05),
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App Bar Title Branding
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_rounded, color: theme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Chatly',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE4E1ED),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  
                  // Visual global network constellation
                  Column(
                    children: [
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.primaryColor.withValues(alpha: 0.02),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Constellation custom painter
                            Positioned.fill(
                              child: CustomPaint(
                                painter: NetworkConstellationPainter(_nodes, theme.primaryColor),
                              ),
                            ),
                            // Central glowing glass ball logo
                            GlassmorphicContainer(
                              width: 80,
                              height: 80,
                              borderRadius: 40,
                              blur: 16,
                              backgroundOpacity: 0.1,
                              borderOpacity: 0.25,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withValues(alpha: 0.12),
                                  blurRadius: 20,
                                ),
                              ],
                              child: Center(
                                child: Icon(
                                  CupertinoIcons.chat_bubble_fill,
                                  color: theme.primaryColor,
                                  size: 32,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // Title Text
                      Text(
                        'Connect. Chat. Discover.',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE4E1ED),
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      
                      // Subtext description
                      Text(
                        'The smartest way to message privately. Zero cloud footprint, military-grade E2E encryption, and effortless local intelligence.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          height: 1.6,
                          color: const Color(0xFFC7C4D7).withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  
                  // Action buttons
                  Column(
                    children: [
                      // Get Started gradient button
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8083FF), Color(0xFF494BD6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8083FF).withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const OnboardingScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get Started',
                                style: TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                               Icon(CupertinoIcons.arrow_right, color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Existing user navigation link
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Existing user? Log In',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
