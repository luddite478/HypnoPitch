/// Layer tab label (A, B, … Z, AA, …) matching the sound grid layer tabs.
String sequencerLayerLabelForIndex(int index) {
  if (index < 0) return '?';
  int value = index + 1;
  final List<int> codeUnits = <int>[];
  while (value > 0) {
    final int remainder = (value - 1) % 26;
    codeUnits.add(65 + remainder); // A..Z
    value = (value - 1) ~/ 26;
  }
  return String.fromCharCodes(codeUnits.reversed);
}
