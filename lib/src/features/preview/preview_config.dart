/// Switch for the static UI demo build handed to reviewers.
///
/// When [enabled] is `true` the app still runs the real navigation graph
/// (login → shell → pairing → device detail), but the mock backend starts
/// without any bound device so the whole flow can be walked from a clean
/// state. Set it to `false` to restore the production data seeding.
abstract final class StaticPreviewConfig {
  static const bool enabled = true;
  static const String demoDeviceId = 'planter-demo-01';
}
