import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../state/sequencer/sample_bank.dart';
import '../../utils/app_colors.dart';

/// Simplified sample bank widget for testing
/// 
/// Shows numbered sample slots with basic load/unload functionality
class SimplifiedSampleBank extends StatelessWidget {
  const SimplifiedSampleBank({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SampleBankState>(
      builder: (context, sampleBank, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Scroll left button
              IconButton(
                onPressed: () {
                  // TODO: Implement scrolling if needed
                },
                icon: const Icon(Icons.chevron_left),
                color: AppColors.sequencerText,
              ),
              
              // Sample slots (show first 8 for simplicity)
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(8, (index) {
                    return _buildSampleSlot(context, sampleBank, index);
                  }),
                ),
              ),
              
              // Scroll right button
              IconButton(
                onPressed: () {
                  // TODO: Implement scrolling if needed
                },
                icon: const Icon(Icons.chevron_right),
                color: AppColors.sequencerText,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSampleSlot(BuildContext context, SampleBankState sampleBank, int slot) {
    final isLoaded = sampleBank.isSlotLoaded(slot);
    final isActive = sampleBank.activeSlot == slot;

    return GestureDetector(
      onTap: () {
        // Set active slot
        sampleBank.setActiveSlot(slot);
      },
      onLongPress: () {
        // Load/unload sample
        if (isLoaded) {
          _showUnloadDialog(context, sampleBank, slot);
        } else {
          _loadSample(context, sampleBank, slot);
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _getSlotColor(isLoaded, isActive, slot),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? AppColors.sequencerAccent : AppColors.sequencerBorder,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: AppColors.sequencerAccent.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 0),
            ),
          ] : null,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${slot + 1}',
                style: TextStyle(
                  color: _getSlotTextColor(isLoaded, isActive),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (isLoaded)
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.sequencerAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSlotColor(bool isLoaded, bool isActive, int slot) {
    if (isLoaded) {
      // Use a simple color based on slot index
      final colors = [
        AppColors.sequencerAccent,
        AppColors.sequencerSecondaryButton,
        AppColors.sequencerSurfaceRaised,
      ];
      return colors[slot % colors.length];
    } else {
      return AppColors.sequencerSurfacePressed;
    }
  }

  Color _getSlotTextColor(bool isLoaded, bool isActive) {
    if (isActive) {
      return AppColors.sequencerPageBackground;
    } else if (isLoaded) {
      return AppColors.sequencerText;
    } else {
      return AppColors.sequencerLightText;
    }
  }

  void _loadSample(BuildContext context, SampleBankState sampleBank, int slot) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final success = await sampleBank.loadSample(slot, filePath);
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Loaded sample ${slot + 1}: ${result.files.single.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load sample'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading sample: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showUnloadDialog(BuildContext context, SampleBankState sampleBank, int slot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unload Sample ${slot + 1}'),
        content: Text('Remove "${sampleBank.getSlotName(slot)}" from slot ${slot + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              sampleBank.unloadSample(slot);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Unloaded sample ${slot + 1}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Unload'),
          ),
        ],
      ),
    );
  }
}
