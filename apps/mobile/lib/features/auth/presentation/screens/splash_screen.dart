import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'welcome_screen.dart';
import '../../../../services/auth_service.dart';
import '../../../../navigation/main_navigation.dart';
import '../../../../core/widgets/glassmorphic_container.dart';

class Particle {
  double x;
  double y;
  double speed;
  double radius;
  double opacity;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.radius,
    required this.opacity,
  });
}

class ParticlesPainter extends CustomPainter {
  final List<Particle> particles;
  final Color color;

  ParticlesPainter(this.particles, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var particle in particles) {
      paint.color = color.withValues(alpha: particle.opacity);
      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _particlesController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  
  final List<Particle> _particles = [];
  double _progress = 0.0;
  String _statusText = "Initializing kernel";

  final List<Map<String, dynamic>> _handshakeSteps = [
    {"progress": 20.0, "status": "Initializing kernel"},
    {"progress": 45.0, "status": "Establishing Secure Channel"},
    {"progress": 70.0, "status": "Handshaking quantum keys"},
    {"progress": 90.0, "status": "Encrypting environment"},
    {"progress": 100.0, "status": "Synchronizing history"},
  ];

  @override
  void initState() {
    super.initState();
    
    // Logo animations
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    _logoController.forward();

    // Initialize background particles
    final random = Random();
    for (int i = 0; i < 20; i++) {
      _particles.add(
        Particle(
          x: random.nextDouble(),
          y: random.nextDouble(),
          speed: 0.15 + random.nextDouble() * 0.35,
          radius: 1.0 + random.nextDouble() * 2.0,
          opacity: 0.08 + random.nextDouble() * 0.35,
        ),
      );
    }

    // Particles loop controller
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        _updateParticles();
      })..repeat();

    // Cryptographic loading sequence
    _startHandshake();
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (var p in _particles) {
        p.y -= p.speed * 0.002;
        if (p.y < 0) {
          p.y = 1.0;
          p.x = Random().nextDouble();
        }
      }
    });
  }

  void _startHandshake() {
    Timer.periodic(const Duration(milliseconds: 140), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        final r = Random();
        _progress += r.nextDouble() * 6 + 1.5;
        
        if (_progress >= 100) {
          _progress = 100.0;
          _statusText = "Connection Secure";
          timer.cancel();
          _navigateNext();
        } else {
          for (var step in _handshakeSteps) {
            if (_progress <= step["progress"]) {
              _statusText = step["status"];
              break;
            }
          }
        }
      });
    });
  }

  Future<void> _navigateNext() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    // Capture the navigator before crossing any async boundary to satisfy the
    // use_build_context_synchronously lint rule.
    final navigator = Navigator.of(context);

    final hasSession = await AuthService().tryAutoLogin();
    if (!mounted) return;
    if (hasSession) {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF13131B), // Obsidian Background
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    Color(0xFF1F1F27),
                    Color(0xFF13131B),
                  ],
                ),
              ),
            ),
          ),
          
          // Atmospheric Particles Painter
          Positioned.fill(
            child: CustomPaint(
              painter: ParticlesPainter(_particles, theme.primaryColor),
            ),
          ),
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 40),
                
                // Central Brand Logo Section
                Column(
                  children: [
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: GlassmorphicContainer(
                          width: 140,
                          height: 140,
                          borderRadius: 36,
                          blur: 24,
                          backgroundOpacity: 0.08,
                          borderOpacity: 0.15,
                          boxShadow: [
                            BoxShadow(
                              color: theme.primaryColor.withValues(alpha: 0.08),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.chat_bubble_fill,
                                  size: 64,
                                  color: theme.primaryColor,
                                ),
                                Positioned(
                                  bottom: 22,
                                  right: 22,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF13131B),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.primaryColor.withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.lock_fill,
                                      size: 14,
                                      color: theme.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        'Chatly',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE4E1ED),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        'SMART. PRIVATE. CONNECTED.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFC7C4D7).withValues(alpha: 0.6),
                          letterSpacing: 4.0,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Bottom loading cluster
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
                  child: Column(
                    children: [
                      // Loading Status Texts
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _statusText,
                              key: ValueKey<String>(_statusText),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.primaryColor.withValues(alpha: 0.85),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            '${_progress.toInt()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFC7C4D7).withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Progress Bar
                      Container(
                        width: double.infinity,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _progress / 100.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.primaryColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Vignette overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.4,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
