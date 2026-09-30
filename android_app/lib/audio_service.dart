import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Service phát âm thanh thông báo máy giặt xong
class AudioService {
  static final AudioPlayer _player = AudioPlayer();

  /// Phát file âm thanh washer_done.mp3 từ assets
  static Future<void> playWasherDoneSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/washer_done.mp3'));
      debugPrint('[AudioService] Đang phát âm thanh máy giặt xong');
    } catch (e) {
      debugPrint('[AudioService] Lỗi phát âm thanh: $e');
    }
  }

  static Future<void> stop() async {
    await _player.stop();
  }
}
