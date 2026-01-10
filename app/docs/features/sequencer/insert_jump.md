# 🎯 Step Insert Feature

**Quick pattern building by automatically jumping to next cells after sample placement.**

## Usage

1. **Select cells** in the sound grid
2. **Click step insert button** - toggles mode and opens settings panel when turning on
3. **Configure step size** using the slider (1-16 steps)
4. **Tap sample banks** - sample places in selected cells and jumps X steps down
5. **Continue tapping** to rapidly build patterns

## Implementation

### State Management
- **Toggle Mode**: Boolean flag to enable/disable step insert behavior
- **Configurable Steps**: Slider control for 1-16 step jump size
- **Separate Settings**: Step insert has its own settings panel

### Core Logic
```dart
bool _isStepInsertMode = false; // Toggle for step insert mode
int _stepInsertSize = 2; // Default jump size (1-16 steps)
MultitaskPanelMode _currentPanelMode = MultitaskPanelMode.placeholder;
```

### UI Components
- **Step Insert Button**: Shows current step size number with down arrow below
  - **Display**: Number (current step size) with arrow underneath
  - **Color**: Gray when off, accent color when active
  - **Click**: Toggles mode and shows settings panel when turning on (doesn't auto-close)
- **Settings Panel**: Slider widget with 1-16 range and close button  
- **Default Behavior**: Sample banks open sound settings when mode is off

## Behavior

### When Step Insert Mode is OFF (Default)
- **Normal Behavior**: Tapping sample banks opens sound settings
- **Standard Grid**: Individual cell editing and selection

### When Step Insert Mode is ON
- **Step Insert**: Tapping sample banks places samples in selected cells
- **Auto Jump**: Selection automatically moves down by configured step size
- **Rapid Building**: Quick pattern creation workflow

## Benefits
- **User Control** - Toggle mode on/off as needed
- **Visual Feedback** - Button shows active state with different icon
- **Flexible Workflow** - Switch between normal editing and rapid pattern building
- **Configurable Steps** - Precise control over jump distance (1-16 steps) 