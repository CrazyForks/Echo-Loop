/// ASR 安装状态的单飞 Gate。
///
/// 该状态机仅管理 ASR 磁盘扫描，避免本次工作与 TTS Gate 共用实现。
class AsrModelInstallationGate {
  AsrModelInstallationGate(this._refresh);

  final Future<void> Function({required bool Function() shouldCommit}) _refresh;
  bool _loaded = false;
  bool _loading = false;
  int _generation = 0;
  Future<void>? _loadFuture;

  Future<void> ensureInstallationStatesLoaded() async {
    while (!_loaded) {
      await (_loadFuture ??= _load(_generation));
    }
  }

  void invalidate() {
    _generation++;
    _loaded = false;
  }

  Future<void> refreshNow() {
    invalidate();
    return ensureInstallationStatesLoaded();
  }

  Future<void> _load(int generation) async {
    _loading = true;
    try {
      await _refresh(shouldCommit: () => generation == _generation);
      if (generation == _generation) _loaded = true;
    } finally {
      _loading = false;
      _loadFuture = null;
    }
  }

  bool get isLoading => _loading;
}
