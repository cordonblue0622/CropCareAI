import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/social_button.dart';
import '../providers/auth_provider.dart';
import '../../home/home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _navigatingHome = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      _showError(auth.errorMessage ?? 'Sign-in failed.');
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!mounted) return;
    if (!ok) _showError(auth.errorMessage ?? 'Google sign-in failed.');
  }

  Future<void> _signInWithFacebook() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithFacebook();
    if (!mounted) return;
    if (!ok) _showError(auth.errorMessage ?? 'Facebook sign-in failed.');
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address first, then tap Forgot Password.');
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _showError('Enter a valid email address first.');
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;
    _showError(
      ok
          ? 'Password reset email sent to $email. Check your inbox and spam folder.'
          : auth.errorMessage ?? 'Could not send the reset email.',
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _routeHomeIfAuthenticated(AuthProvider auth) {
    if (_navigatingHome || !auth.isAuthenticated) {
      return;
    }

    _navigatingHome = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _routeHomeIfAuthenticated(auth);

    return Scaffold(
      backgroundColor: AppColors.splashGrad4,
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.splashGrad1,
                AppColors.splashGrad2,
                AppColors.splashGrad3,
                AppColors.splashGrad4,
              ],
              stops: [0.0, 0.28, 0.62, 1.0],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),

                        // ── Logo + title ───────────────────────────────────────
                        _LogoSection(),
                        const SizedBox(height: 32),

                        // ── Auth card ──────────────────────────────────────────
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Email
                                CustomTextField(
                                  label: 'EMAIL ADDRESS',
                                  hint: 'agronomist@cropcare.ai',
                                  keyboardType: TextInputType.emailAddress,
                                  controller: _emailCtrl,
                                  prefixIcon: const Icon(Icons.alternate_email,
                                      color: AppColors.textLightGray, size: 20),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Email is required';
                                    }
                                    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                                    if (!re.hasMatch(v)) return 'Invalid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 18),

                                // Password header row (label + forgot)
                                Row(
                                  children: [
                                    const Text(
                                      'PASSWORD',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textGray,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _forgotPassword,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'FORGOT PASSWORD?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFD32F2F),
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Password field (no repeated label)
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _signIn(),
                                  style: const TextStyle(
                                      fontSize: 15, color: AppColors.textDark),
                                    decoration: InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(
                                        color: AppColors.textLightGray),
                                    prefixIcon: Padding(
                                      padding:
                                          EdgeInsets.only(left: 14, right: 10),
                                      child: Icon(Icons.lock_outline_rounded,
                                          color: AppColors.textLightGray,
                                          size: 20),
                                    ),
                                    prefixIconConstraints: BoxConstraints(
                                        minWidth: 44, minHeight: 44),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: AppColors.textLightGray,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (v.length < 6) return 'Min 6 characters';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 22),

                                // Sign In button
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: auth.isLoading ? null : _signIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    child: auth.isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white),
                                          )
                                        : const Text('Sign In',
                                            style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // OR divider
                                Row(
                                  children: [
                                    Expanded(
                                        child: Divider(
                                            color: Colors.grey.shade300)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(
                                        'OR CONTINUE WITH',
                                        style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1.2,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Expanded(
                                        child: Divider(
                                            color: Colors.grey.shade300)),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Social buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: SocialButton(
                                        label: 'Google',
                                        icon: _GoogleIcon(),
                                        onPressed: auth.isLoading
                                            ? null
                                            : _signInWithGoogle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SocialButton(
                                        label: 'Facebook',
                                        icon: const Icon(Icons.facebook_rounded,
                                            color: Color(0xFF1877F2), size: 22),
                                        onPressed: auth.isLoading
                                            ? null
                                            : _signInWithFacebook,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Create account link ────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "New to the field? ",
                              style: TextStyle(
                                  fontSize: 14, color: Color(0xFF4A6055)),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (_) => const RegisterScreen()),
                              ),
                              child: const Text(
                                'Create an account',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Security badge ─────────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              'ENCRYPTED DIAGNOSTIC ENVIRONMENT',
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Private sub-widgets ──────────────────────────────────────────────────────

class _LogoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.eco_rounded,
                  color: Colors.lightGreenAccent, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'CropCare AI',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark),
        ),
        const SizedBox(height: 6),
        const Text(
          'Precision intelligence for your\nflourishing landscape.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF4A6055), height: 1.5),
        ),
      ],
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Draw coloured arcs to simulate the Google logo
    const colors = [
      Color(0xFF4285F4), // blue
      Color(0xFF34A853), // green
      Color(0xFFFBBC05), // yellow
      Color(0xFFEA4335), // red
    ];
    final sweeps = [90.0, 90.0, 90.0, 90.0];
    double start = -90;

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start * (3.14159 / 180),
        sweeps[i] * (3.14159 / 180),
        false,
        Paint()
          ..color = colors[i]
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
      start += sweeps[i];
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
