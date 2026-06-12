import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'login_screen.dart';
import '../../../../core/widgets/glassmorphic_container.dart';

class AnimatedShieldIllustration extends StatefulWidget {
  final IconData icon;
  final Color color;

  const AnimatedShieldIllustration({
    super.key,
    required this.icon,
    required this.color,
  });

  @override
  State<AnimatedShieldIllustration> createState() => _AnimatedShieldIllustrationState();
}

class _AnimatedShieldIllustrationState extends State<AnimatedShieldIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring 1 (Pulsing)
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.04 + 0.04 * sin(_controller.value * 2 * pi)),
                  width: 1.5,
                ),
              ),
            ),
            // Outer ring 2 (Cos pulsing)
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.08 + 0.06 * cos(_controller.value * 2 * pi)),
                  width: 1.0,
                ),
              ),
            ),
            // Core Glass Box
            GlassmorphicContainer(
              width: 130,
              height: 130,
              borderRadius: 40,
              blur: 20,
              backgroundOpacity: 0.08,
              borderOpacity: 0.18,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.12),
                  blurRadius: 25,
                ),
              ],
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 56,
                  color: widget.color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Private & Secure',
      description: 'Your conversations are protected with enterprise-grade end-to-end encryption. Only you hold the decryption keys.',
      icon: CupertinoIcons.shield_fill,
      color: const Color(0xFF8083FF), // Premium Violet/Indigo
    ),
    OnboardingData(
      title: 'Anonymous Match',
      description: 'Discover and connect anonymously with others based on interests without revealing your username or phone number.',
      icon: CupertinoIcons.eye_slash_fill,
      color: const Color(0xFFFFB300), // Amber Accent
    ),
    OnboardingData(
      title: 'Smart Algorithms',
      description: 'Experience conversation memory scores, offline queues, and local toxicity filters keeping your chats secure and engaging.',
      icon: CupertinoIcons.sparkles,
      color: const Color(0xFF10B981), // Emerald
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF13131B), // Obsidian Background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Skip Button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      color: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              
              // Onboarding Slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final data = _pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedShieldIllustration(
                          icon: data.icon,
                          color: data.color,
                        ),
                        const SizedBox(height: 50),
                        Text(
                          data.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE4E1ED),
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Text(
                            data.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              height: 1.6,
                              color: const Color(0xFFC7C4D7).withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              // Page Indicators & Button
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0, left: 8.0, right: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dot Indicators
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          height: 6,
                          width: _currentPage == index ? 24 : 6,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? _pages[index].color
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    
                    // Next/Finish FAB
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _currentPage == _pages.length - 1
                              ? [const Color(0xFF10B981), const Color(0xFF059669)]
                              : [const Color(0xFF8083FF), const Color(0xFF494BD6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_currentPage == _pages.length - 1
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF8083FF))
                                .withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (_currentPage < _pages.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (context) => const LoginScreen()),
                              );
                            }
                          },
                          child: Icon(
                            _currentPage == _pages.length - 1
                                ? CupertinoIcons.checkmark
                                : CupertinoIcons.arrow_right,
                            color: Colors.white,
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
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
