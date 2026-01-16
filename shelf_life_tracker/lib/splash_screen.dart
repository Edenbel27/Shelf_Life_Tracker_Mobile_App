import 'package:flutter/material.dart';
import 'Repository/store_repository.dart';
import 'login_page.dart' as login_page;
import 'pages/home_page.dart' as owner_home;
import 'Staff/staff_home_page.dart' as staff_home;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await StoreRepository.instance.init();
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final repo = StoreRepository.instance;
    if (repo.isLoggedIn) {
      final user = repo.currentUser!;
      if (user.role == UserRole.owner) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const owner_home.StoreOwnerHomePage()),
        );
        return;
      }
      // staff
      if (user.approved) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const staff_home.StaffHomePage()),
        );
        return;
      }
    }
    // default to sign-in
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const login_page.LoginPage(),
      ),
    );
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircleAvatar(
                radius: 36,
                backgroundColor: Color(0xFFE0F2FE),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Shelf Life Tracker',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}