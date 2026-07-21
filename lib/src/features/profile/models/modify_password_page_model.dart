class ModifyPasswordPageModel {
  const ModifyPasswordPageModel({
    this.minimumLength = 8,
    this.maximumLength = 20,
  });

  final int minimumLength;
  final int maximumLength;

  bool hasValidLength(String password) {
    return password.length >= minimumLength && password.length <= maximumLength;
  }
}
