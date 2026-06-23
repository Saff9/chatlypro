import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';
import '../../../../services/auth_service.dart';
import '../../../../core/widgets/glassmorphic_container.dart';
import '../../../../navigation/main_navigation.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'email_verification_screen.dart';
import 'two_factor_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Force redraw when field focus changes so active color updates
    _emailFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final email = _emailController.text.trim();
      final result = await AuthService().login(
        email: email,
        password: _passwordController.text,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result.success) {
          if (result.twoFactorRequired) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TwoFactorScreen(
                  email: email,
                  tempToken: result.tempToken!,
                ),
              ),
            );
          } else {
            // Login success
            final username = AuthService().username ?? '';
            final box = Hive.box('settings');
            await box.put('username', username);
            await box.put('display_name', username);
            
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainNavigation()),
                (route) => false,
              );
            }
          }
        } else {
          if (result.emailVerified == false) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => EmailVerificationScreen(
                  email: email,
                  tempToken: result.tempToken,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.errorMessage ?? 'Authentication failed. Please check inputs.')),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF13131B), // Obsidian Background
      body: Stack(
        children: [
          // Ambient Glow Backgrounds
          Positioned(
            top: -120,
            left: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.04),
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand / Logo Section
                    Column(
                      children: [
                        Text(
                          'Chatly',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: theme.primaryColor,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Elite Communication Infrastructure',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Glass Form Box
                    GlassmorphicContainer(
                      margin: const EdgeInsets.symmetric(horizontal: 20.0),
                      padding: const EdgeInsets.all(28.0),
                      borderRadius: 32,
                      blur: 24,
                      backgroundOpacity: 0.04,
                      borderOpacity: 0.12,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome Back!',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFE4E1ED),
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Please enter your credentials to continue',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFC7C4D7).withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            
                            // Email Field
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EMAIL ADDRESS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _emailFocus.hasFocus
                                        ? theme.primaryColor
                                        : const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _emailController,
                                  focusNode: _emailFocus,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(fontSize: 15, color: Color(0xFFE4E1ED)),
                                  decoration: InputDecoration(
                                    hintText: 'name@company.com',
                                    hintStyle: TextStyle(color: const Color(0xFFC7C4D7).withValues(alpha: 0.35)),
                                    prefixIcon: Icon(
                                      CupertinoIcons.mail,
                                      color: _emailFocus.hasFocus
                                          ? theme.primaryColor
                                          : const Color(0xFFC7C4D7).withValues(alpha: 0.4),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.02),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                                      borderSide: BorderSide(color: theme.primaryColor.withValues(alpha: 0.5), width: 1.5),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your email';
                                    }
                                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                      return 'Please enter a valid email address';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // Password Field
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'PASSWORD',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: _passwordFocus.hasFocus
                                            ? theme.primaryColor
                                            : const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => const ForgotPasswordScreen(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Forgot?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: theme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(fontSize: 15, color: Color(0xFFE4E1ED)),
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(color: const Color(0xFFC7C4D7).withValues(alpha: 0.35)),
                                    prefixIcon: Icon(
                                      CupertinoIcons.lock,
                                      color: _passwordFocus.hasFocus
                                          ? theme.primaryColor
                                          : const Color(0xFFC7C4D7).withValues(alpha: 0.4),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? CupertinoIcons.eye_slash
                                            : CupertinoIcons.eye,
                                        color: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.02),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                                      borderSide: BorderSide(color: theme.primaryColor.withValues(alpha: 0.5), width: 1.5),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    if (value.length < 8) {
                                      return 'Password must be at least 8 characters';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            
                            // Login Gradient Button
                            Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF8083FF), Color(0xFF494BD6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF8083FF).withValues(alpha: 0.25),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.0,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Login',
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
                            
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    
                    // Signup redirect link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: const Color(0xFFC7C4D7).withValues(alpha: 0.6), fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignupScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Sign Up',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
