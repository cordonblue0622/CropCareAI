import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../providers/auth_provider.dart';
import '../../home/home_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _municipalityCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _agreedToTerms = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _countryCtrl.dispose();
    _provinceCtrl.dispose();
    _municipalityCtrl.dispose();
    _barangayCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (Country country) {
        _countryCtrl.text = country.name;
      },
    );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      _showError('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      fullName: _nameCtrl.text.trim(),
      country: _countryCtrl.text.trim(),
      province: _provinceCtrl.text.trim(),
      municipality: _municipalityCtrl.text.trim(),
      barangay: _barangayCtrl.text.trim(),
    );

    if (!mounted) return;
    if (ok) {
      if (auth.isAuthenticated) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else {
        await _showEmailVerificationPrompt(
          auth.infoMessage ??
              'Account created. Check your email for the verification link, then sign in.',
        );
      }
    } else if (ok == false) {
      _showError(auth.errorMessage ?? 'Registration failed.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showEmailVerificationPrompt(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Verify Your Email'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Go to Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row (logo + name) ───────────────────────────
                Row(
                  children: [
                    // CropCare stamp logo
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.eco_rounded,
                          color: Colors.lightGreenAccent, size: 26),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CropCare AI',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ── Title ─────────────────────────────────────────────
                const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start your journey toward healthier yields today.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textGray,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),

                // ── Full Name ─────────────────────────────────────────
                CustomTextField(
                  label: 'FULL NAME',
                  hint: 'John Doe',
                  controller: _nameCtrl,
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppColors.textLightGray, size: 20),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    if (v.trim().length < 2) return 'Name too short';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // ── Email ─────────────────────────────────────────────
                CustomTextField(
                  label: 'EMAIL ADDRESS',
                  hint: 'agronomist@cropcare.ai',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.alternate_email,
                      color: AppColors.textLightGray, size: 20),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                    if (!re.hasMatch(v)) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                const Text(
                  'FARM LOCATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                CustomTextField(
                  label: 'COUNTRY',
                  hint: 'Select country',
                  controller: _countryCtrl,
                  readOnly: true,
                  onTap: _pickCountry,
                  prefixIcon: const Icon(Icons.public_rounded,
                      color: AppColors.textLightGray, size: 20),
                  suffixIcon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textLightGray, size: 22),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Country is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                CustomTextField(
                  label: 'PROVINCE / STATE',
                  hint: 'Cebu',
                  controller: _provinceCtrl,
                  prefixIcon: const Icon(Icons.map_outlined,
                      color: AppColors.textLightGray, size: 20),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Province or state is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                CustomTextField(
                  label: 'MUNICIPALITY / CITY',
                  hint: 'Dalaguete',
                  controller: _municipalityCtrl,
                  prefixIcon: const Icon(Icons.location_city_outlined,
                      color: AppColors.textLightGray, size: 20),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Municipality or city is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                CustomTextField(
                  label: 'BARANGAY / VILLAGE',
                  hint: 'Mantalongon',
                  controller: _barangayCtrl,
                  prefixIcon: const Icon(Icons.place_outlined,
                      color: AppColors.textLightGray, size: 20),
                ),
                const SizedBox(height: 18),

                // ── Password ──────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PASSWORD',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.textDark),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle:
                            const TextStyle(color: AppColors.textLightGray),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 10),
                          child: Icon(Icons.lock_outline_rounded,
                              color: AppColors.textLightGray, size: 20),
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textLightGray,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password is required';
                        }
                        if (v.length < 8) {
                          return 'Minimum 8 characters';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── Terms checkbox ────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _agreedToTerms,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        onChanged: (v) =>
                            setState(() => _agreedToTerms = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textGray,
                              height: 1.45),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // TODO: open Terms of Service
                                },
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // TODO: open Privacy Policy
                                },
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Create Account button ─────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _createAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.6),
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Create Account',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward,
                                  size: 18, color: Colors.white),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Sign In link ──────────────────────────────────────
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textGray),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign In',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary),
                          recognizer: TapGestureRecognizer()
                            ..onTap =
                                () => Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                          builder: (_) => const LoginScreen()),
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Security footer ───────────────────────────────────
                const Divider(),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'SECURE REGISTRATION',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SecurityBadge(label: 'AES-256'),
                    SizedBox(width: 14),
                    _SecurityBadge(label: 'ISO 27001'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityBadge extends StatelessWidget {
  final String label;
  const _SecurityBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_outlined, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
