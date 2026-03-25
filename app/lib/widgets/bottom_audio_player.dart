import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/audio_player_state.dart';
import '../utils/app_colors.dart';

class BottomAudioPlayer extends StatefulWidget {
  const BottomAudioPlayer({Key? key}) : super(key: key);

  @override
  State<BottomAudioPlayer> createState() => _BottomAudioPlayerState();
}

class _BottomAudioPlayerState extends State<BottomAudioPlayer> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  IconData _getLoopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.single:
        return Icons.repeat_one;
      case LoopMode.playlist:
        return Icons.repeat;
      case LoopMode.off:
        return Icons.repeat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        if (audioPlayer.currentlyPlayingItemId == null) {
          return const SizedBox.shrink();
        }

        final isPlaying = audioPlayer.isPlaying;
        final position = audioPlayer.position;
        final duration = audioPlayer.duration;
        final loopMode = audioPlayer.loopMode;
        final shuffleEnabled = audioPlayer.shuffleEnabled;

        final durMs = duration.inMilliseconds;
        final posMs = position.inMilliseconds;
        // Stream position can exceed reported duration by a tick; keep UI in range.
        final safePosMs = durMs > 0 ? posMs.clamp(0, durMs) : 0;

        final displayPosition = _isDragging
            ? Duration(
                milliseconds:
                    _dragValue.round().clamp(0, durMs > 0 ? durMs : 0),
              )
            : Duration(milliseconds: safePosMs);

        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            border: Border(
              top: BorderSide(color: AppColors.sequencerBorder, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatDuration(displayPosition),
                        style: TextStyle(
                          color: AppColors.sequencerLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: durMs > 0
                            ? _SeekSlider(
                                durationMs: durMs,
                                positionMs: safePosMs,
                                isDragging: _isDragging,
                                dragValue: _dragValue,
                                onDragStart: (v) {
                                  setState(() {
                                    _isDragging = true;
                                    _dragValue = v;
                                  });
                                },
                                onDragUpdate: (v) {
                                  setState(() => _dragValue = v);
                                },
                                onDragEnd: (v) async {
                                  await audioPlayer.seek(
                                    Duration(milliseconds: v),
                                  );
                                  if (!mounted) return;
                                  setState(() => _isDragging = false);
                                },
                              )
                            : Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  color: AppColors.sequencerBorder
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        durMs > 0
                            ? _formatDuration(duration)
                            : '--:--',
                        style: TextStyle(
                          color: AppColors.sequencerLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: shuffleEnabled
                              ? AppColors.sequencerAccent
                              : AppColors.sequencerLightText,
                          size: 20,
                        ),
                        onPressed: () => audioPlayer.toggleShuffle(),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous,
                          color: AppColors.sequencerText,
                          size: 28,
                        ),
                        onPressed: () => audioPlayer.playPrevious(),
                        padding: EdgeInsets.zero,
                      ),
                      GestureDetector(
                        onTap: () async {
                          if (isPlaying) {
                            await audioPlayer.pause();
                          } else {
                            await audioPlayer.resume();
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.sequencerAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.sequencerPageBackground,
                            size: 24,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next,
                          color: AppColors.sequencerText,
                          size: 28,
                        ),
                        onPressed: () => audioPlayer.playNext(),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        icon: Icon(
                          _getLoopIcon(loopMode),
                          color: loopMode != LoopMode.off
                              ? AppColors.sequencerAccent
                              : AppColors.sequencerLightText,
                          size: 20,
                        ),
                        onPressed: () => audioPlayer.toggleLoopMode(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Slider with value always clamped to [0, durationMs]. No [Slider] when duration unknown.
class _SeekSlider extends StatelessWidget {
  const _SeekSlider({
    required this.durationMs,
    required this.positionMs,
    required this.isDragging,
    required this.dragValue,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final int durationMs;
  final int positionMs;
  final bool isDragging;
  final double dragValue;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final Future<void> Function(int milliseconds) onDragEnd;

  @override
  Widget build(BuildContext context) {
    final max = durationMs.toDouble();
    final raw = isDragging ? dragValue : positionMs.toDouble();
    final value = raw.clamp(0.0, max);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        activeTrackColor: AppColors.sequencerAccent,
        inactiveTrackColor: AppColors.sequencerBorder.withOpacity(0.5),
        thumbColor: AppColors.sequencerText,
        overlayColor: AppColors.sequencerAccent.withOpacity(0.2),
      ),
      child: Slider(
        value: value,
        min: 0,
        max: max,
        onChangeStart: (v) => onDragStart(v.clamp(0.0, max)),
        onChanged: (v) => onDragUpdate(v.clamp(0.0, max)),
        onChangeEnd: (v) async {
          final ms = v.round().clamp(0, durationMs);
          await onDragEnd(ms);
        },
      ),
    );
  }
}
