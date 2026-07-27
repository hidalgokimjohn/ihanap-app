import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'splash_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Form Controllers
  final _emailController       = TextEditingController();
  final _passwordController    = TextEditingController();
  final _fullNameController    = TextEditingController();
  final _contactController     = TextEditingController();
  final _barangayController    = TextEditingController();

  // Responder Specific Controllers
  final _shopNameController    = TextEditingController();
  final _taglineController     = TextEditingController();

  String _selectedRole = 'buyer'; // 'buyer' or 'responder'
  String? _selectedResponderType;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final List<Map<String, String>> _responderTypes = [
    {'emoji': '🚗', 'label': 'Auto Parts Shop',     'value': 'auto_parts'},
    {'emoji': '🔧', 'label': 'Hardware Store',       'value': 'hardware'},
    {'emoji': '🏠', 'label': 'Room / Boarding',      'value': 'rooms'},
    {'emoji': '📦', 'label': 'Rider / Courier',      'value': 'rider'},
    {'emoji': '🏪', 'label': 'General Store',        'value': 'general'},
    {'emoji': '📍', 'label': 'Community Helper',     'value': 'community'},
    {'emoji': '🍽️', 'label': 'Food & Catering',     'value': 'food'},
    {'emoji': '🛠️', 'label': 'Repair & Services',   'value': 'repair'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _contactController.dispose();
    _barangayController.dispose();
    _shopNameController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter both email and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await AuthService.signIn(email: email, password: password);
      if (res.session != null && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoadingSplashScreen()),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('Sign in failed. Please check your credentials.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();
    
    final contactNumber = _contactController.text.trim();
    final barangay      = _barangayController.text.trim();
    final shopName      = _shopNameController.text.trim();
    final tagline       = _taglineController.text.trim();

    if (email.isEmpty || password.isEmpty || fullName.isEmpty) {
      _showSnackBar('Please fill in all required fields (Name, Email, Password).');
      return;
    }
    
    if (_selectedRole == 'responder') {
      if (shopName.isEmpty) {
        _showSnackBar('Please enter your Shop / Business Name.');
        return;
      }
      if (_selectedResponderType == null) {
        _showSnackBar('Please select a Responder Category.');
        return;
      }
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters long.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await AuthService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: _selectedRole,
        contactNumber: contactNumber,
        barangay: barangay,
        shopName: shopName,
        responderType: _selectedResponderType,
        tagline: tagline,
      );

      final currentSession = Supabase.instance.client.auth.currentSession ?? response.session;
      if (currentSession != null && mounted) {
        _showSnackBar('Account created! Welcome to Ping.', isSuccess: true);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoadingSplashScreen()),
          (route) => false,
        );
      } else {
        _showSnackBar('Account created! Please sign in with your email and password.', isSuccess: true);
        _tabController.animateTo(1); // Auto switch to Sign In tab
      }
    } on AuthException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('Registration failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      _showSnackBar('Google Sign-In failed: ${e.toString()}');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String text, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isSuccess ? const Color(0xFF004D40) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2F0F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Color(0xFF004D40), size: 28),
                      ),
                      const SizedBox(width: 10),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF004D40), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: Text(
                          'Ping',
                          style: GoogleFonts.outfit(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Broadcast to local shops in seconds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF004D40),
                    labelColor: const Color(0xFF004D40),
                    unselectedLabelColor: const Color(0xFF64748B),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: 'Create Account'),
                      Tab(text: 'Sign In'),
                    ],
                  ),
                ],
              ),
            ),

            // ── Tab Views ────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSignUpTab(),
                  _buildSignInTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SIGN UP TAB ────────────────────────────────────────────────────────
  Widget _buildSignUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose your primary role:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),

          // ── Role Selector Cards ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildRoleCard(
                  roleId: 'buyer',
                  emoji: '🛍️',
                  title: 'I want to Buy',
                  subtitle: 'Send Pings & find items',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRoleCard(
                  roleId: 'responder',
                  emoji: '🏪',
                  title: 'I am a Merchant',
                  subtitle: 'Send offers & grow business',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),

          // ── Basic Info ─────────────────────────────────────────────────
          _buildTextField(
            controller: _fullNameController,
            label: 'Full Name *',
            hint: 'e.g. Juan dela Cruz',
            icon: Icons.person_outline,
            caps: TextCapitalization.words,
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _emailController,
            label: 'Email Address *',
            hint: 'name@example.com',
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _passwordController,
            label: 'Password *',
            hint: 'At least 6 characters',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _contactController,
            label: 'Contact Number (Optional)',
            hint: '09XX-XXX-XXXX',
            icon: Icons.phone_outlined,
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 14),

          // ── Role-Specific Fields ───────────────────────────────────────
          if (_selectedRole == 'buyer') ...[
            _buildTextField(
              controller: _barangayController,
              label: 'Barangay / Area in Butuan (Optional)',
              hint: 'e.g. Libertad, Montilla, Villa Kananga',
              icon: Icons.location_on_outlined,
              caps: TextCapitalization.words,
            ),
          ] else ...[
            _buildTextField(
              controller: _shopNameController,
              label: 'Shop / Business Name *',
              hint: 'e.g. TechHub Auto Supply',
              icon: Icons.storefront_outlined,
              caps: TextCapitalization.words,
            ),
            const SizedBox(height: 14),

            const Text(
              'Responder Category *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _responderTypes.map((type) {
                final selected = _selectedResponderType == type['value'];
                return ChoiceChip(
                  label: Text('${type['emoji']} ${type['label']}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedResponderType = type['value']),
                  selectedColor: const Color(0xFF004D40),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF334155),
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: selected ? const Color(0xFF004D40) : const Color(0xFFCBD5E1)),
                  ),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            _buildTextField(
              controller: _taglineController,
              label: 'Short Tagline / Description (Optional)',
              hint: 'e.g. Quality parts & fast delivery',
              icon: Icons.description_outlined,
            ),
          ],

          const SizedBox(height: 28),

          // ── Submit Button ──────────────────────────────────────────────
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
            ),
            child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _selectedRole == 'buyer' ? 'Register as Buyer' : 'Register Shop & Start Selling',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 16),
          _buildGoogleDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── SIGN IN TAB ────────────────────────────────────────────────────────
  Widget _buildSignInTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Welcome back!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sign in to access your requests, offers, and shop profile.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),

          _buildTextField(
            controller: _emailController,
            label: 'Email Address',
            hint: 'name@example.com',
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
            ),
            child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text(
                    'Sign In',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 16),
          _buildGoogleDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(),
        ],
      ),
    );
  }

  // ── Helper Widgets ─────────────────────────────────────────────────────
  Widget _buildGoogleDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton(
      onPressed: _isLoading ? null : _handleGoogleSignIn,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Using a simple emoji instead of asset to avoid adding SVG packages right now
          Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blue)),
          SizedBox(width: 12),
          Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required String roleId,
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedRole == roleId;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = roleId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE2F0F0) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [const BoxShadow(color: Color(0x1A006A6B), blurRadius: 10, offset: Offset(0, 4))]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? const Color(0xFF004D40) : const Color(0xFFCBD5E1),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF004D40) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboard,
          textCapitalization: caps,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
