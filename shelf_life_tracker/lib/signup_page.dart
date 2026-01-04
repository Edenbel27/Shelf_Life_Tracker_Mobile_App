import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_page.dart' as login_page;
import 'pages/home_page.dart' as owner_home;
import 'Staff/staff_home_page.dart' as staff_home;

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});
  
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static const _webClientId =
      '779825959200-mue8g2oushhjgb4n1h73ue86qoepm2fu.apps.googleusercontent.com';
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
  );

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    // Icon
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.blue.shade100,
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        size: 32,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    const Text(
                      "Shelf Life Tracker",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text("Sign-Up", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),

                    // First name
                    TextField(
                      controller: _firstNameCtrl,
                      decoration: InputDecoration(
                        labelText: "First Name",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Last name
                    TextField(
                      controller: _lastNameCtrl,
                      decoration: InputDecoration(
                        labelText: "Last Name",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone number
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: "Phone Number",
                        hintText: "+251900000000",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        labelText: "Email",
                        hintText: "example@gmail.com",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        hintText: "Enter your password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Role fixed as Staff
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Role: Staff (default)'),
                    ),
                    const SizedBox(height: 20),

                    // Sign up Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                            final first = _firstNameCtrl.text.trim();
                            final last = _lastNameCtrl.text.trim();
                            final phone = _phoneCtrl.text.trim();
                            final email = _emailCtrl.text.trim();
                            final pass = _passwordCtrl.text;
                            final emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
                            final phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
                            if (first.isEmpty || last.isEmpty || phone.isEmpty || email.isEmpty || pass.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill all fields')),
                              );
                              return;
                            }
                            if (!emailRegex.hasMatch(email)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid email format')),
                              );
                              return;
                            }
                            if (!phoneRegex.hasMatch(phone)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid phone number format')),
                              );
                              return;
                            }
                            if (pass.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Password must be at least 6 characters')),
                              );
                              return;
                            }
                            try {
                              final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                email: email,
                                password: pass,
                              );
                              await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
                                'firstName': first,
                                'lastName': last,
                                'phone': phone,
                                'email': email,
                                'role': 'staff',
                                'approved': false,
                                'createdVia': 'email',
                              });
                              if (!mounted) return;
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Registration submitted'),
                                  content: const Text('Your account requires store owner approval before you can sign in.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (_) => const login_page.LoginPage()),
                                        );
                                      },
                                      child: const Text('OK'),
                                    )
                                  ],
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Sign Up",
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Google Sign Up Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.g_translate, color: Colors.black87),
                        label: const Text('Sign Up with Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _handleGoogleSignup,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Go to login
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context, 
                          MaterialPageRoute( 
                            builder:(_) => const login_page.LoginPage() 
                            )
                             );
                      },
                      child: const Text(
                        "Already have an account? Sign in",
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),

                    const SizedBox(height: 12),

                  ],
                ),
              ),
            ),
          ),
        ),
      );
     
  }

  Future<void> _handleGoogleSignup() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return; // User cancelled Google picker
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to sign in with Google')),
        );
        return;
      }

      final usersRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var snapshot = await usersRef.get();

      if (!snapshot.exists) {
        final displayName = user.displayName ?? '';
        final parts = displayName.trim().split(' ');
        final firstName = parts.isNotEmpty ? parts.first : '';
        final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

        await usersRef.set({
          'firstName': firstName,
          'lastName': lastName,
          'phone': user.phoneNumber ?? '',
          'email': user.email ?? googleUser.email,
          'role': 'staff',
          'approved': false,
          'createdVia': 'google',
        });

        snapshot = await usersRef.get();
      }

      final data = snapshot.data();
      final role = data?['role'] ?? 'staff';
      final approved = data?['approved'] ?? false;

      if (!approved) {
        await FirebaseAuth.instance.signOut();
        await _googleSignIn.signOut();
        if (!mounted) return;
        _showApprovalDialog();
        return;
      }

      if (role == 'owner') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const owner_home.StoreOwnerHomePage()),
        );
        return;
      }

      if (role == 'staff') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const staff_home.StaffHomePage()),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unknown user role')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _showApprovalDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Registration submitted'),
        content: const Text('Your account requires store owner approval before you can sign in.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const login_page.LoginPage()),
              );
            },
            child: const Text('OK'),
          )
        ],
      ),
    );
  }
}
