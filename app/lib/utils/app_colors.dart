import 'package:flutter/material.dart';

/// Centralized color management for the HypnoPitch app
/// 
/// Contains two main color palettes:
/// 1. Sequencer colors - Dark theme for sequencer screens and widgets
/// 2. Menu colors - Black-white/dark-light gray theme for menu screens
class AppColors {
  
  // Sequencer colors - dark theme for music production interface
  static const Color sequencerPageBackground = Color(0xFF3A3A3A); // Dark gray background
  static const Color sequencerSurfaceBase = Color(0xFF4A4A47); // Gray-beige base surface
  static const Color sequencerSurfaceRaised = Color(0xFF525250); // Protruding surface color
  static const Color sequencerSurfacePressed = Color(0xFF424240); // Pressed/active surface
  static const Color sequencerText = Color(0xFFE8E6E0); // Light text for contrast
  static const Color sequencerLightText = Color(0xFFB8B6B0); // Muted light text
  static const Color sequencerAccent = Color(0xFF8B7355); // Brown accent for highlights
  static const Color sequencerBorder = Color(0xFF5A5A57); // Subtle borders
  static const Color sequencerShadow = Color(0xFF2A2A2A); // Dark shadows for depth
  static const Color sequencerCellEmpty = Color.fromARGB(255, 67, 67, 64); // Empty grid cells (matches pattern preview)
  static const Color sequencerCellEmptyAlternate = Color.fromARGB(255, 70, 70, 67); // Same as cellEmpty for consistency
  static const Color sequencerCellFilled = Color(0xFF5C5A55); // Filled grid cells
  static const Color sequencerSecondaryButton = Color(0xFF6A6A67); // Grayed out secondary buttons
  static const Color sequencerSecondaryButtonAlt = Color(0xFF5A5A57); // Alternative secondary button
  static const Color sequencerPrimaryButton = Color(0xFF9B8365); // Lighter main action button
  static const Color tutorialPulseColor = Color.fromARGB(255, 65, 185, 255); // Shared tutorial pulse/highlight color
  static const Color tutorialArrowColor = Color.fromARGB(235, 32, 13, 173); // Shared tutorial arrow color
  static const Color tutorialTextOverlayColor = Color.fromARGB(235, 78, 58, 228); // Shared tutorial text-card background color
  
  // Selection visuals
  static const Color sequencerSelectionBorder = Color(0xFFFFFFFF); // White border for selected items
  
  // Icon backgrounds
  static const Color sequencerIconBackground = Color(0xFF545454); // Background for FAB and icons
  
  // Menu colors - black-white/dark-light gray theme for navigation and content screens
  static const Color menuPageBackground = Color(0xFFF8F8F8); // Light gray background
  static const Color menuEntryBackground = Color(0xFFFFFFFF); // White entry background
  static const Color menuText = Color(0xFF1A1A1A); // Dark gray/black text
  static const Color menuLightText = Color(0xFF666666); // Medium gray text
  static const Color menuBorder = Color(0xFFE0E0E0); // Light gray border
  static const Color menuOnlineIndicator = Color(0xFF4CAF50); // Green indicator
  static const Color menuOnlineIndicatorActive = Color(0xFF7629C3); // Purple for active/online states
  static const Color menuErrorColor = Color(0xFFDC2626); // Red for errors
  
  // Button colors for menu screens
  static const Color menuPrimaryButton = Color(0xFF1A1A1A); // Dark primary button
  static const Color menuPrimaryButtonText = Color(0xFFFFFFFF); // White text on dark button
  static const Color menuSecondaryButton = Color(0xFFFFFFFF); // White secondary button
  static const Color menuSecondaryButtonText = Color(0xFF1A1A1A); // Dark text on light button
  static const Color menuSecondaryButtonBorder = Color(0xFF1A1A1A); // Dark border for secondary button
  
  // Legacy button colors for gradual migration
  static const Color menuButtonBackground = Color(0xFFF0F0F0); // Light gray for subtle buttons
  static const Color menuButtonBorder = Color(0xFFD0D0D0); // Gray border for subtle buttons
  
  // Checkpoint-specific colors
  static const Color menuCheckpointBackground = Color(0xFFF5F5F5); // Checkpoint cards
  static const Color menuCurrentUserCheckpoint = Color(0xFFEEEEEE); // Current user checkpoints
  
  // Sample Bank Colors - Vibrant Diverse Palette (26 unique colors for bank slots 0–25)
  // High color diversity with vibrant saturation across full spectrum
  static const List<Color> sampleBankPalette = [
    Color(0xFF8B3A28), // A - Burnt Sienna
    Color(0xFF2A6B4A), // B - Emerald
    Color(0xFFB54A28), // C - Rust Orange
    Color(0xFF2A4A7B), // D - Royal Blue
    Color(0xFF8B8B28), // E - Golden Olive
    Color(0xFF8B2A5A), // F - Burgundy
    Color(0xFF2A6B8B), // G - Teal
    Color(0xFF4A8B2A), // H - Lime Green
    Color(0xFFA53A3A), // I - Crimson
    Color(0xFF2A8B6B), // J - Jade
    Color(0xFF6B2A8B), // K - Purple
    Color(0xFF3A6B3A), // L - Forest Green
    Color(0xFFB56B2A), // M - Amber
    Color(0xFF2A5A7B), // N - Ocean Blue
    Color(0xFFC59B3A), // O - Gold
    Color(0xFF4A3A8B), // P - Indigo
    Color(0xFF2A7B7B), // Q - Cyan
    Color(0xFF8B3A7B), // R - Orchid
    Color(0xFF6B8B2A), // S - Chartreuse
    Color(0xFF2A5A3A), // T - Deep Green
    Color(0xFFB55A3A), // U - Terracotta
    Color(0xFF3A4A8B), // V - Sapphire
    Color(0xFF6B4A8B), // W - Violet
    Color(0xFF2A8B5A), // X - Sea Green
    Color(0xFFB58B3A), // Y - Honey
    Color(0xFF3A6B6B), // Z - Seafoam
  ];
} 