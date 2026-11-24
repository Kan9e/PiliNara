import 'dart:async';

import 'package:PiliPlus/services/logger.dart';
import 'package:media_kit/media_kit.dart';

/// iOS「退出页面进入小窗后自动暂停」（上游 #297）的临时诊断埋点。
///
/// 只读取状态、不改变任何播放行为；问题定位完成后应连同各调用点一起删除。
/// 走 [logger] 输出（受「设置 → 日志」开关控制，release 包同样落盘），
/// 因此可以在应用内的日志页直接把记录复制出来。
void pipDiag(String tag, String message) {
  logger.i('[PiPDiag][$tag] $message');
}

/// 给 [pipDiag] 附带调用栈，用来追溯是谁调用了 pause/play。
///
/// 调用栈捕获有开销，只用于低频且必须知道调用方的位置。
String pipDiagStack([int frames = 9]) {
  final lines = StackTrace.current.toString().trimRight().split('\n');
  if (lines.length <= 1) {
    return '';
  }
  // 跳过本函数自身这一帧
  return lines
      .skip(1)
      .take(frames)
      .map((line) => line.trim())
      .join(' <- ');
}

/// 进入小窗后对底层 mpv 做数次只读采样。
///
/// 用来判断「App 已认为暂停」与「mpv 实际是否在跑」是否一致，
/// 以及暂停瞬间音频输出、时钟、缓冲的状态，避免凭猜测改播放逻辑。
/// 采样次数固定且很少，结束后自动停止。
class PipDiagSampler {
  PipDiagSampler._();

  static const Duration _interval = Duration(milliseconds: 600);
  static const int _maxTicks = 5;

  static Timer? _timer;
  static NativePlayer? _player;
  static int _tick = 0;

  static void start(Player? player) {
    stop();
    _player = player is NativePlayer ? player : null;
    _tick = 0;
    if (_player == null) {
      pipDiag('mpv', 'sample skipped: no native player');
      return;
    }
    _sample();
    _timer = Timer.periodic(_interval, (_) {
      _tick++;
      if (_tick >= _maxTicks) {
        stop();
        return;
      }
      _sample();
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _sample() {
    final player = _player;
    if (player == null) {
      return;
    }
    String read(String key) {
      try {
        return player.getProperty(key);
      } catch (e) {
        return 'err($e)';
      }
    }

    pipDiag(
      'mpv',
      't=${_tick * _interval.inMilliseconds}ms '
      'pause=${read('pause')} '
      'idle-active=${read('idle-active')} '
      'core-idle=${read('core-idle')} '
      'time-pos=${read('time-pos')} '
      'cache=${read('demuxer-cache-duration')} '
      'audio-device=${read('audio-device')}',
    );
  }
}
