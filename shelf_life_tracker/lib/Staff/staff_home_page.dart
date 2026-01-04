import 'package:flutter/material.dart';
import '../Repository/store_repository.dart';
import '../pages/home_page.dart';

class StaffHomePage extends StatelessWidget {
  const StaffHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage(role: UserRole.staff);
  }
}
