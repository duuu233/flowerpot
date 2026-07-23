/// Temporary switch for the static-page styling workflow.
///
/// Set [enabled] to `false` when the real product navigation should be
/// restored. The remaining preview code can stay in the project for later UI
/// reviews without affecting the production flow.
abstract final class StaticPreviewConfig {
  static const bool enabled = true;
  static const String demoDeviceId = 'planter-demo-01';
}
