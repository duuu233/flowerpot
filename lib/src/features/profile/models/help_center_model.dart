class HelpCenterFaqItem {
  const HelpCenterFaqItem({
    required this.id,
    required this.question,
    required this.answer,
  });

  final String id;
  final String question;
  final String answer;
}

class HelpCenterPageModel {
  const HelpCenterPageModel({
    required this.items,
    this.initiallyExpandedIds = const <String>{},
  });

  final List<HelpCenterFaqItem> items;
  final Set<String> initiallyExpandedIds;
}
