abstract final class AppBreakpoints {
  static const double compact = 375;
  static const double medium = 600;
  static const double expanded = 1024;

  static double contentMaxWidth(double width) {
    if (width >= expanded) return 720;
    if (width >= medium) return 600;
    return width;
  }
}
