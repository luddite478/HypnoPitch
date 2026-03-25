import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/user_state.dart';
import '../state/library_state.dart';
import '../utils/app_colors.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header without back button (since this is now a tab)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.menuEntryBackground,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.menuBorder,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Title
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.menuText,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // Settings content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // The logout button has been removed.
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
