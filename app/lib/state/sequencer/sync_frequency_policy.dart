/// Centralized cadence policy for timer-driven sync.
class SyncFrequencyPolicy {
  final int tableCadence;
  final int sampleCadence;
  final int undoCadence;

  const SyncFrequencyPolicy({
    required this.tableCadence,
    required this.sampleCadence,
    required this.undoCadence,
  });

  static const SyncFrequencyPolicy activePlayback = SyncFrequencyPolicy(
    tableCadence: 1,
    sampleCadence: 3,
    undoCadence: 4,
  );

  static const SyncFrequencyPolicy idle = SyncFrequencyPolicy(
    tableCadence: 3,
    sampleCadence: 8,
    undoCadence: 10,
  );

  static SyncFrequencyPolicy forPlaybackState({required bool isPlaying}) {
    return isPlaying ? activePlayback : idle;
  }
}
