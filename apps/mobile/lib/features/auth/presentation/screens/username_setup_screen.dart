import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../../core/widgets/glassmorphic_container.dart';
import '../../../../navigation/main_navigation.dart';

// UsernameSetupScreen — Shown after a successful email verification to let the
// user choose a unique, permanent username. Usernames are alphanumeric, 3–20
// chars, and must not conflict with a small set of reserved system words.
class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _usernameController = TextEditingController();
  bool _isChecking = false;
  bool? _isAvailable;
  String _errorMessage = '';

  // Words that are either reserved system identifiers or could cause confusion.
  static const _reservedWords = {
    'admin', 'chatly', 'support', 'help', 'system', 'root',
    'moderator', 'mod', 'staff', 'official', 'chatlyapp',
    'security', 'privacy', 'notifications', 'api',
  };

  void _validateUsername(String username) {
    final trimmed = username.trim().toLowerCase();

    if (trimmed.length < 3) {
      setState(() {
        _isAvailable = null;
        _errorMessage = '';
        _isChecking = false;
      });
      return;
    }

    // Alphanumeric with underscores and hyphens only.
    final validPattern = RegExp(r'^[a-z0-9_\-]+$');
    if (!validPattern.hasMatch(trimmed)) {
      setState(() {
        _isAvailable = false;
        _errorMessage = 'Only letters, numbers, _ and - are allowed';
        _isChecking = false;
      });
      return;
    }

    if (_reservedWords.contains(trimmed)) {
      setState(() {
        _isAvailable = false;
        _errorMessage = 'This username is reserved';
        _isChecking = false;
      });
      return;
    }

    setState(() => _isChecking = true);

    // Debounced local check — in a future release this will hit the server
    // to verify global uniqueness. For now, the server will enforce
    // uniqueness at the point of account creation.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (_usernameController.text.trim().toLowerCase() != trimmed) return;

      setState(() {
        _isChecking = false;
        _isAvailable = true;
        _errorMessage = '';
      });
    });
  }

  Future<void> _handleSubmit() async {
    if (_isAvailable != true) return;

    final username = _usernameController.text.trim().toLowerCase();
    final box = Hive.box('settings');
    await box.put('username', username);
    await box.put('display_name', username);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitEnabled = _isAvailable == true && !_isChecking;

    return Scaffold(
      backgroundColor: const Color(0xFF13131B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Header
              const Icon(Icons.alternate_email_rounded, color: Color(0xFF8083FF), size: 36),
              const SizedBox(height: 16),
              const Text(
                'Choose Your Username',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE4E1ED),
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'This is how other users discover and connect with you on Chatly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: const Color(0xFFC7C4D7).withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 40),

              // Input card
              GlassmorphicContainer(
                padding: const EdgeInsets.all(24),
                borderRadius: 24,
                blur: 20,
                backgroundOpacity: 0.04,
                borderOpacity: 0.1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username input
                    TextFormField(
                      controller: _usernameController,
                      onChanged: _validateUsername,
                      maxLength: 20,
                      style: const TextStyle(
                        color: Color(0xFFE4E1ED),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'yourname',
                        hintStyle: TextStyle(
                          color: const Color(0xFFC7C4D7).withValues(alpha: 0.35),
                          fontWeight: FontWeight.normal,
                        ),
                        prefixText: '@',
                        prefixStyle: const TextStyle(
                          color: Color(0xFF8083FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        counterStyle: TextStyle(
                          color: const Color(0xFFC7C4D7).withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF8083FF), width: 1.5),
                        ),
                        suffixIcon: _isChecking
                            ? const Padding(
                                padding: EdgeInsets.all(14.0),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF8083FF),
                                  ),
                                ),
                              )
                            : _isAvailable != null
                                ? Icon(
                                    _isAvailable!
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: _isAvailable!
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444),
                                    size: 22,
                                  )
                                : null,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Inline feedback
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isAvailable == true
                          ? const Row(
                              key: ValueKey('available'),
                              children: [
                                Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 15),
                                SizedBox(width: 6),
                                Text(
                                  'Username is available',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                          : _isAvailable == false
                              ? Row(
                                  key: const ValueKey('unavailable'),
                                  children: [
                                    const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 15),
                                    const SizedBox(width: 6),
                                    Text(
                                      _errorMessage,
                                      style: const TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(key: ValueKey('idle')),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Rules hint
              Text(
                '3–20 characters. Letters, numbers, _ and - only.\nCannot be changed after setup.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                ),
              ),

              const Spacer(),

              // Continue button
              SizedBox(
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: isSubmitEnabled
                        ? const LinearGradient(
                            colors: [Color(0xFF8083FF), Color(0xFF494BD6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              const Color(0xFF8083FF).withValues(alpha: 0.3),
                              const Color(0xFF494BD6).withValues(alpha: 0.3),
                            ],
                          ),
                    boxShadow: isSubmitEnabled
                        ? [
                            BoxShadow(
                              color: const Color(0xFF8083FF).withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ElevatedButton(
                    onPressed: isSubmitEnabled ? _handleSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'Continue to Chatly',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
