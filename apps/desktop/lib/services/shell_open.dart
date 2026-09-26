import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:quizsync_core/quizsync_core.dart' show AppLogger;
import 'package:win32/win32.dart';

/// 用系统默认程序打开链接 / 文件夹（用户反馈 6「字体许可协议」、
/// 用户反馈 10「打开文件资源管理器跳到数据目录」）。
///
/// 直接走 `ShellExecuteW`（win32 已经在本项目的依赖里），
/// 不再引入 url_launcher，也不需要任何额外权限。
bool openExternal(String target) {
  if (target.trim().isEmpty) return false;
  final verb = 'open'.toNativeUtf16();
  final file = target.toNativeUtf16();
  try {
    final result = ShellExecute(
      NULL,
      verb,
      file,
      nullptr,
      nullptr,
      SW_SHOWNORMAL,
    );
    // ShellExecute 的返回值 > 32 才算成功（<= 32 是各种错误码）。
    final ok = result > 32;
    if (!ok) {
      AppLogger.instance.warn('shell', '打开失败（$result）：$target');
    }
    return ok;
  } catch (e) {
    AppLogger.instance.warn('shell', '打开失败：$e');
    return false;
  } finally {
    calloc.free(verb);
    calloc.free(file);
  }
}

/// 在资源管理器里打开某个目录（不存在时返回 false）。
bool revealFolder(String path) => openExternal(path);

// ---------------------------------------------------------------------------
// 原生「另存为」对话框（用户反馈 2）
// ---------------------------------------------------------------------------

const int _ofnOverwritePrompt = 0x00000002;
const int _ofnNoChangeDir = 0x00000008;
const int _ofnPathMustExist = 0x00000800;
const int _ofnExplorer = 0x00080000;

/// 文件名缓冲区长度（Windows 路径上限 260，留足余量）。
const int _maxPath = 1024;

// comdlg32 的错误码（CommDlgExtendedError 返回 0 表示「用户取消」）。
//
// 注意 0x3000 段是 **FNERR_**（文件名相关），不是 CDERR_*（那个在 0x0000 段）。
// M12 就是靠它定位到「导出全部失败」的真凶：0x3002 = FNERR_INVALIDFILENAME
// —— 调用方用 `Directory('$root/exports')` 拼出来的预填路径是
// `<盘符>\...\userdata/exports\all-xxx.md`（**正反斜杠混用**），资源管理器对话框
// 直接拒绝这个文件名，`GetSaveFileNameW` 立刻返回 0。原来把「返回 0」一律
// 当成「用户取消」，于是什么都没发生、也没有任何提示。
const int _cdErrDialogFailure = 0xffff; // CDERR_DIALOGFAILURE
const int _cdErrStructureSize = 0x0001; // CDERR_STRUCTSIZE
const int _cdErrInitialization = 0x0002; // CDERR_INITIALIZATION
const int _cdErrNoInstance = 0x0004; // CDERR_NOHINSTANCE
const int _cdErrMemAlloc = 0x0009; // CDERR_MEMALLOCFAILURE
const int _fnErrSubclassFailure = 0x3001; // FNERR_SUBCLASSFAILURE
const int _fnErrInvalidFilename = 0x3002; // FNERR_INVALIDFILENAME
const int _fnErrBufferTooSmall = 0x3003; // FNERR_BUFFERTOOSMALL

final DynamicLibrary _comdlg32 = DynamicLibrary.open('comdlg32.dll');
final int Function() _commDlgExtendedError = _comdlg32
    .lookupFunction<Uint32 Function(), int Function()>('CommDlgExtendedError');

/// 错误码 → 人话（写进日志与异常消息）。
String commDlgErrorMessage(int code) => switch (code) {
      0 => '用户取消',
      _cdErrDialogFailure => '对话框创建失败（CDERR_DIALOGFAILURE）',
      _cdErrStructureSize => 'OPENFILENAME 结构尺寸不对（CDERR_STRUCTSIZE）',
      _cdErrInitialization => '对话框初始化失败（CDERR_INITIALIZATION）',
      _cdErrNoInstance => '没有可用的对话框实例（CDERR_NOHINSTANCE）',
      _cdErrMemAlloc => '内存不足（CDERR_MEMALLOCFAILURE）',
      _fnErrSubclassFailure => '对话框子类化失败（FNERR_SUBCLASSFAILURE）',
      _fnErrInvalidFilename => '预填的文件名非法（FNERR_INVALIDFILENAME）',
      _fnErrBufferTooSmall => '文件名缓冲区太小（FNERR_BUFFERTOOSMALL）',
      _ => 'CommDlgExtendedError=0x${code.toRadixString(16)}',
    };

/// 交给资源管理器对话框的路径**必须是纯反斜杠**。
///
/// Dart 的 `Directory('$root/exports')` / `'$root/logs'` 会留下正斜杠，
/// 拼成的 `lpstrFile` 混用两种分隔符时 `GetSaveFileNameW` 直接报
/// FNERR_INVALIDFILENAME 并返回 0（用户看到的就是「点了导出没反应」）。
/// 这里统一归一化，顺手去掉结尾多余的分隔符。
String normalizeForDialog(String path) {
  var s = path.replaceAll('/', r'\');
  while (s.length > 3 && s.endsWith(r'\')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

// shell32 的 EnumWindows 回调原型（只在本文件用一次，避免引入额外类型）。
typedef _EnumWindowsProc = Int32 Function(IntPtr, IntPtr);
typedef _EnumWindowsNative = Int32 Function(
    Pointer<NativeFunction<_EnumWindowsProc>>, IntPtr);
typedef _EnumWindowsDart = int Function(
    Pointer<NativeFunction<_EnumWindowsProc>>, int);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);

final _user32 = DynamicLibrary.open('user32.dll');
final _enumWindows =
    _user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');
final _getWindowThreadProcessId = _user32.lookupFunction<
    _GetWindowThreadProcessIdNative,
    _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
final _getCurrentProcessId =
    DynamicLibrary.open('kernel32.dll').lookupFunction<Uint32 Function(),
        int Function()>('GetCurrentProcessId');
final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');

int _candidateOwner = 0;

/// 找**本进程**的第一个可见顶层窗口当对话框的 owner；找不到返回 0。
///
/// 不用 `FindWindow(title)`：标题是可变文案，改一次标题这个 owner 就丢了
/// （拿不到 owner 的对话框在某些情况下会跑到窗口后面，用户看到的就是
/// 「点了导出什么都没发生」）。按进程 id 找没有这个问题。
int findOwnWindow() {
  _candidateOwner = 0;
  final pid = _getCurrentProcessId();
  // NativeCallable.isolateLocal：回调由窗口消息循环在**本 isolate 的线程**上
  // 触发（这里就是从主 isolate 同步调用 EnumWindows，枚举过程是同步的）。
  final cb = NativeCallable<_EnumWindowsProc>.isolateLocal(
    (int hwnd, int _) {
      if (_candidateOwner != 0) return 0; // 已经找到，提前结束枚举
      if (_isWindowVisible(hwnd) == 0) return 1;
      final out = calloc<Uint32>();
      try {
        _getWindowThreadProcessId(hwnd, out);
        if (out.value == pid) {
          _candidateOwner = hwnd;
          return 0;
        }
      } finally {
        calloc.free(out);
      }
      return 1; // 继续枚举
    },
    exceptionalReturn: 0,
  );
  try {
    _enumWindows(cb.nativeFunction, 0);
  } finally {
    cb.close();
  }
  return _candidateOwner;
}

/// 「另存为」对话框的入参。
typedef SavePathChooser = String? Function({
  required String title,
  required String defaultDir,
  required String defaultName,
  required String extension,
  String filterLabel,
});

/// 当前使用的「另存为」实现（默认 [nativePickSavePath]）。
///
/// widget 测试里原生对话框不可用，也不需要真的弹窗：测试直接把它换成
/// 「返回一个固定路径」的假实现即可（见 `test/collections_ui_test.dart`）。
SavePathChooser savePathChooser = nativePickSavePath;

/// 弹出系统「另存为」对话框，返回用户选择的完整路径；取消返回 null。
///
/// 用 `GetSaveFileNameW`（comdlg32）而不是新增 `file_selector` 依赖：
/// win32 / ffi 已经在本项目的依赖里，对话框也是 Windows 原生外观。
///
/// [defaultDir] 是**默认打开目录**（用户反馈 2：默认落在软件所在目录下），
/// [defaultName] 是预填文件名，[extension] 是不带点的默认扩展名。
///
/// M12：失败时用 `CommDlgExtendedError()` 把**真实原因**写进日志 ——
/// 原来只判断 `ok == 0` 就当成「用户取消」，任何真实错误（对话框创建失败、
/// 上一轮没结束……）都会被静默吞掉，用户看到的就是「点了导出没反应」。
String? nativePickSavePath({
  required String title,
  required String defaultDir,
  required String defaultName,
  required String extension,
  String filterLabel = '文件',
}) {
  final owner = findOwnWindow();
  // 路径一律用纯反斜杠（见 [normalizeForDialog]）：混用分隔符会让
  // GetSaveFileNameW 直接以 FNERR_INVALIDFILENAME 失败。
  final dir = normalizeForDialog(defaultDir);
  // 文件名缓冲区：用 Uint16 分配（`Utf16` 是 opaque 类型，不能 asTypedList），
  // 传给 OPENFILENAME 时再 cast 成 Pointer<Utf16>。
  final buffer = calloc<Uint16>(_maxPath);
  final filter = '$filterLabel (*.$extension)\u0000*.$extension\u0000'
          '所有文件 (*.*)\u0000*.*\u0000\u0000'
      .toNativeUtf16();
  final initialDir = dir.toNativeUtf16();
  final titlePtr = title.toNativeUtf16();
  final defExt = extension.toNativeUtf16();
  final initial = '$dir\\$defaultName'.toNativeUtf16();
  final ofn = calloc<OPENFILENAME>();
  try {
    // 预填「目录 + 文件名」（lpstrInitialDir 单独给，行为最稳）。
    final codes = buffer.asTypedList(_maxPath);
    codes.setAll(0, initial.cast<Uint16>().asTypedList(initial.length + 1));
    ofn.ref
      ..lStructSize = sizeOf<OPENFILENAME>()
      ..hwndOwner = owner
      ..hInstance = NULL
      ..lpstrFilter = filter
      ..nFilterIndex = 1
      ..lpstrFile = buffer.cast<Utf16>()
      ..nMaxFile = _maxPath
      ..lpstrInitialDir = initialDir
      ..lpstrTitle = titlePtr
      ..lpstrDefExt = defExt
      ..Flags = _ofnExplorer |
          _ofnOverwritePrompt |
          _ofnPathMustExist |
          _ofnNoChangeDir;

    AppLogger.instance
        .info('shell', '另存为：owner=$owner dir=$dir name=$defaultName');
    final ok = GetSaveFileName(ofn);
    if (ok == 0) {
      final err = _commDlgExtendedError();
      final message = commDlgErrorMessage(err);
      AppLogger.instance
          .warn('shell', '另存为未返回路径：$message（owner=$owner dir=$dir）');
      // err == 0 才是用户点「取消」；其它错误必须让调用方报错，
      // 不能假装成「已取消导出」（M12 的教训）。
      if (err != 0) throw StateError('另存为对话框失败：$message');
      return null;
    }
    final end = codes.indexOf(0);
    final picked = String.fromCharCodes(codes.sublist(0, end < 0 ? _maxPath : end));
    AppLogger.instance.info('shell', '另存为选中：$picked');
    return picked.isEmpty ? null : picked;
  } finally {
    calloc.free(ofn);
    calloc.free(buffer);
    calloc.free(initial);
    calloc.free(filter);
    calloc.free(initialDir);
    calloc.free(titlePtr);
    calloc.free(defExt);
  }
}

