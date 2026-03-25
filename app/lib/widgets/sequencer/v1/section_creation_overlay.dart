import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/table.dart';

class SectionCreationOverlay extends StatefulWidget {
  final VoidCallback? onBack;
  const SectionCreationOverlay({super.key, this.onBack});

  @override
  State<SectionCreationOverlay> createState() => _SectionCreationOverlayState();
}

class _SectionCreationOverlayState extends State<SectionCreationOverlay> {

  @override
  Widget build(BuildContext context) {
    return Consumer<TableState>(
      builder: (context, tableState, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: AppColors.sequencerSurfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(context),
              
              // Content
              Expanded(
                child: _buildContent(context, tableState),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final headerHeight = screenSize.height * 0.08;
    
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0.02),
        child: Row(
          children: [
            // Back arrow to return to previous section
            GestureDetector(
              onTap: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                }
              },
              child: Container(
                width: screenSize.width * 0.08,
                height: screenSize.width * 0.08,
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfacePressed,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.sequencerBorder,
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: AppColors.sequencerLightText,
                  size: screenSize.width * 0.045,
                ),
              ),
            ),
            const Spacer(),
            // Title centered
            Text(
              'Create New Section',
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TableState tableState) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: MediaQuery.of(context).size.height * 0.02,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Create Blank Button
          _buildSimpleButton(
            context,
            text: 'Create Empty',
            onPressed: () {
              tableState.appendSection();
            },
          ),
          
          SizedBox(height: MediaQuery.of(context).size.height * 0.02),
          
          // Create From Label
          Text(
            'Copy:',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          SizedBox(height: MediaQuery.of(context).size.height * 0.01),
          
          // Scrollable list of sections
          Expanded(
            child: ListView.builder(
              itemCount: tableState.sectionsCount,
              itemBuilder: (context, index) {
                return _buildSectionCopyButton(context, tableState, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleButton(
    BuildContext context, {
    required String text,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.02,
        ),
        decoration: BoxDecoration(
          color: AppColors.sequencerAccent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCopyButton(BuildContext context, TableState tableState, int sectionIndex) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.01),
      child: GestureDetector(
        onTap: () {
          tableState.appendSection(copyFrom: sectionIndex);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.015,
            horizontal: MediaQuery.of(context).size.width * 0.03,
          ),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfacePressed,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
          ),
          child: Text(
            'Section ${sectionIndex + 1}',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
 
} 