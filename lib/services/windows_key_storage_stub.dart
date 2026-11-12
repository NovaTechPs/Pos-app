/// Web build stand-in: the real storage needs dart:ffi (Windows DPAPI),
/// which does not exist on web. Web keeps the default secure storage.
abstract final class WindowsKeyStorage {
  static Future<void> install() async {}
}
