import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/app_colors.dart';
import '../screens/library_screen.dart';

class SimplifiedHeaderWidget extends StatelessWidget {
  const SimplifiedHeaderWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 66, 66, 66),
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side - App icon
          SvgPicture.asset(
            'icons/app_icon.svg',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          
          // Spacer
          const Expanded(
            child: SizedBox(),
          ),
          
          // Right side - Library icon
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LibraryScreen(),
                ),
              );
            },
            icon: Icon(
              Icons.folder_outlined,
              color: AppColors.sequencerText,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}
