import 'package:flutter/material.dart';
import 'Repository/store_repository.dart';

/// App-wide tabs with role-based visibility.
enum AppTab { home, inventory, transactions, reports, settings }

List<AppTab> tabsForRole(UserRole role) =>
    role == UserRole.owner
        ? const [AppTab.home, AppTab.inventory, AppTab.transactions, AppTab.reports, AppTab.settings]
        : const [AppTab.home, AppTab.inventory, AppTab.transactions, AppTab.settings];

String _labelFor(AppTab tab) {
  switch (tab) {
    case AppTab.home:
      return 'Home';
    case AppTab.inventory:
      return 'Inventory';
    case AppTab.transactions:
      return 'Transactions';
    case AppTab.reports:
      return 'Reports';
    case AppTab.settings:
      return 'Settings';
  }
}

IconData _iconFor(AppTab tab) {
  switch (tab) {
    case AppTab.home:
      return Icons.home;
    case AppTab.inventory:
      return Icons.inventory;
    case AppTab.transactions:
      return Icons.swap_horiz;
    case AppTab.reports:
      return Icons.bar_chart;
    case AppTab.settings:
      return Icons.settings;
  }
}

BottomNavigationBar buildBottomNav({
  required BuildContext context,
  required UserRole role,
  required AppTab activeTab,
  required Widget Function(AppTab tab) destinationBuilder,
}) {
  final tabs = tabsForRole(role);
  final currentIndex = tabs.indexOf(activeTab);

  return BottomNavigationBar(
    currentIndex: currentIndex < 0 ? 0 : currentIndex,
    selectedItemColor: Colors.blue,
    unselectedItemColor: Colors.black,
    items: tabs
        .map(
          (tab) => BottomNavigationBarItem(
            icon: Icon(_iconFor(tab)),
            label: _labelFor(tab),
            tooltip: _labelFor(tab),
          ),
        )
        .toList(),
    onTap: (index) {
      if (index == currentIndex) return;
      final tab = tabs[index];
      final destination = destinationBuilder(tab);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    },
  );
}
