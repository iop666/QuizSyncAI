import 'package:flutter/foundation.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 会话导航语义（SPEC 第 5 节，用户已定）：
/// - 「上一次」= 时间上**更早**的那条会话（列表倒序中索引 +1）；
/// - 「下一次」= 时间上**更晚**的那条（索引 -1）；
/// - 「回到本次」= 跳回**最近一次识别**（列表第一条，索引 0）；
/// - 「本次」始终指向最新那条，翻旧会话不改变它。
class SessionNav extends ChangeNotifier {
  /// 时间倒序（最新在前）。
  final List<Session> sessions;

  int _index = 0;

  SessionNav(this.sessions) : _index = 0;

  int get index => _index.clamp(0, sessions.isEmpty ? 0 : sessions.length - 1);

  /// 当前查看的会话；空列表返回 null。
  Session? get current => sessions.isEmpty ? null : sessions[index];

  /// 是否正停在「本次」（最新一条）。
  bool get isAtLatest => sessions.isEmpty || index == 0;

  bool get canGoPrev => index < sessions.length - 1;
  bool get canGoNext => index > 0;

  /// 上一次（更早）。
  void goPrev() {
    if (canGoPrev) {
      _index = index + 1;
      notifyListeners();
    }
  }

  /// 下一次（更晚）。
  void goNext() {
    if (canGoNext) {
      _index = index - 1;
      notifyListeners();
    }
  }

  /// 回到本次（最新）。
  void backToLatest() {
    _index = 0;
    notifyListeners();
  }

  /// 跳到指定会话（新识别完成时调用；该会话即成为「本次」所在列表头）。
  void jumpTo(String sessionId) {
    final i = sessions.indexWhere((s) => s.sessionId == sessionId);
    if (i >= 0) {
      _index = i;
      notifyListeners();
    } else {
      backToLatest();
    }
  }

  /// 「第 X / Y 条记录」。
  String get positionLabel =>
      sessions.isEmpty ? '第 0 / 0 条记录' : '第 ${index + 1} / ${sessions.length} 条记录';
}
