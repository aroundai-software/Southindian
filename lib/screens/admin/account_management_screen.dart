import 'package:flutter/material.dart';
import 'package:Orderx/screens/admin/salesman_management_tab.dart';
import 'package:Orderx/screens/admin/admin_management_tab.dart';
import 'package:Orderx/screens/admin/salesman_sessions_screen.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final GlobalKey<SalesmanManagementTabState> _salesmenKey =
      GlobalKey<SalesmanManagementTabState>();
  final GlobalKey<AdminManagementTabState> _adminsKey =
      GlobalKey<AdminManagementTabState>();
  final GlobalKey<SalesmanSessionsTabState> _sessionsKey =
      GlobalKey<SalesmanSessionsTabState>();

  void _refreshCurrentTab(int index) {
    switch (index) {
      case 0:
        _salesmenKey.currentState?.reload();
        break;
      case 1:
        _adminsKey.currentState?.reload();
        break;
      default:
        _sessionsKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Account Management'),
              actions: [
                AppBarRefreshButton(
                  onPressed: () => _refreshCurrentTab(tabController.index),
                ),
                const GlobalCompanySwitcher(),
              ],
              bottom: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: 'Salesmen'),
                  Tab(text: 'Admins'),
                  Tab(text: 'Active Sessions'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                SalesmanManagementTab(key: _salesmenKey),
                AdminManagementTab(key: _adminsKey),
                SalesmanSessionsTab(key: _sessionsKey),
              ],
            ),
          );
        },
      ),
    );
  }
}
