import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/user_state.dart';
import '../utils/app_colors.dart';

class CommonHeaderWidget extends StatelessWidget {
  final String? customTitle; // Optional custom title instead of current user name

  const CommonHeaderWidget({
    Key? key,
    this.customTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<UserState>(
      builder: (context, userState, child) {
        final currentUser = userState.currentUser;
        if (currentUser == null && customTitle == null) return const SizedBox();
        
        return Container(
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
              // User info with online indicator
              Expanded(
                child: Row(
                  children: [
                    Text(
                      customTitle ?? currentUser!.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.menuText,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (customTitle == null) ...[
                      const SizedBox(width: 8),
                      // Online indicator next to user name
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.menuOnlineIndicator,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 