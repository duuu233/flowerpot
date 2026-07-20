class LegalDocumentPageModel {
  const LegalDocumentPageModel({
    required this.pageTitle,
    required this.documentTitle,
    required this.updatedAt,
    required this.effectiveAt,
    required this.sections,
  });

  factory LegalDocumentPageModel.privacy() {
    return const LegalDocumentPageModel(
      pageTitle: '隐私政策',
      documentTitle: '《YSplanter 隐私政策》',
      updatedAt: '2026-6-13',
      effectiveAt: '2026-6-13',
      sections: <LegalDocumentSection>[
        LegalDocumentSection(
          heading: '前言',
          body:
              '欢迎使用 YSplanter（以下简称“本应用”）。\n'
              '我们深知个人信息对您的重要性，并将尽力保护您的个人信息安全可靠。本隐私政策旨在向您说明，我们会如何收集、使用、存储、共享和保护您的个人信息，以及您享有的相关权利。\n'
              '使用本应用前，请您仔细阅读并理解本隐私政策。您使用本应用，即表示您已充分理解并同意本隐私政策所述内容。',
        ),
        LegalDocumentSection(
          heading: '一、我们收集哪些信息？',
          body:
              '1. 您主动提供的信息\n'
              '　　在您注册、登录、使用本应用相关功能时，可能需要您提供以下信息：\n'
              '（1）账号信息：手机号码、验证码、昵称、头像等。\n'
              '（2）快捷登录信息：当您使用微信、支付宝等第三方账号登录时，我们可能会根据您的授权获取头像、昵称、账号标识等必要信息。\n'
              '（3）反馈信息：当您通过意见反馈、客服或帮助中心联系我们时，您可能会提供问题描述、联系方式、截图或其他辅助信息。\n'
              '（4）植物信息：您在应用中添加的植物名称、植物类型、养护记录、提醒设置等内容。\n'
              '2. 设备及使用信息\n'
              '　　为了实现智能花盆设备连接、控制和状态查看，我们可能会收集以下信息：\n'
              '（1）设备信息：设备型号、设备名称、设备编号、固件版本、MAC 地址等。\n'
              '（2）传感器数据：水位、土壤湿度、光照、温度、空气湿度、电量等。\n'
              '（3）网络信息：Wi-Fi 名称、网络状态、IP 地址等。Wi-Fi 密码仅用于设备配网，不会用于其他用途。\n'
              '（4）日志信息：功能访问记录、设备操作记录、异常日志等。',
        ),
        LegalDocumentSection(
          heading: '二、我们如何使用这些信息？',
          body:
              '我们收集的信息将用于账号注册与登录、智能花盆连接和控制、植物养护提醒、运行状态展示、故障排查、客户服务以及产品体验改进。未经您的授权，我们不会将个人信息用于与上述目的无关的用途。',
        ),
        LegalDocumentSection(
          heading: '三、设备权限的使用',
          body:
              '蓝牙和位置权限用于发现及连接附近设备；相册和相机权限用于设置头像或提交反馈；通知权限用于发送设备状态和养护提醒。相关权限仅在功能需要时申请，您可以在系统设置中随时关闭。',
        ),
        LegalDocumentSection(
          heading: '四、信息的存储与保护',
          body:
              '我们会在实现服务目的所必需的期限内保存个人信息，并采用访问控制、传输加密、权限隔离和安全审计等措施保护信息。超过保存期限后，我们将依法删除或匿名化处理相关信息。',
        ),
        LegalDocumentSection(
          heading: '五、信息的共享与第三方服务',
          body:
              '除获得您的明确同意、履行法定义务或提供核心服务所必需外，我们不会向无关第三方共享您的个人信息。涉及第三方 SDK 或云服务时，我们会要求服务提供方按照约定和适用法律处理数据。',
        ),
        LegalDocumentSection(
          heading: '六、您的个人信息权利',
          body:
              '您可以依法访问、更正或删除个人信息，管理系统权限，解除设备绑定，撤回授权或申请注销账号。部分信息删除后，相关功能可能无法继续使用。',
        ),
        LegalDocumentSection(
          heading: '七、未成年人保护',
          body:
              '本应用主要面向成年人。未成年人应在监护人指导下使用本应用并提供个人信息；如发现未经有效同意收集了未成年人信息，我们会尽快依法处理。',
        ),
        LegalDocumentSection(
          heading: '八、本政策的更新',
          body:
              '我们可能根据业务变化或法律法规要求更新本政策。发生重大变更时，我们会通过应用内提示等合理方式告知您，并在页面中更新生效日期。',
        ),
        LegalDocumentSection(
          heading: '九、联系我们',
          body: '如您对本隐私政策或个人信息保护有任何疑问、意见或请求，可以通过应用内帮助中心联系我们。我们会在法律规定的期限内核实并处理。',
        ),
      ],
    );
  }

  factory LegalDocumentPageModel.agreement() {
    return const LegalDocumentPageModel(
      pageTitle: '用户协议',
      documentTitle: '《YSplanter 用户协议》',
      updatedAt: '2026-6-13',
      effectiveAt: '2026-6-13',
      sections: <LegalDocumentSection>[
        LegalDocumentSection(
          heading: '前言',
          body: '欢迎使用 YSplanter。使用本应用前，请您认真阅读并理解本协议。您开始使用本应用，即表示您同意遵守本协议。',
        ),
        LegalDocumentSection(
          heading: '一、服务内容',
          body: '本应用提供账号、设备配置与管理、传感器数据展示、设备控制、分享、固件升级和植物养护建议等服务。',
        ),
        LegalDocumentSection(
          heading: '二、账号安全',
          body: '请妥善保管账号与验证码，不得利用本服务实施破坏设备、网络或他人合法权益的行为。',
        ),
        LegalDocumentSection(
          heading: '三、设备数据',
          body: '传感器数据仅用于辅助养护，不构成农业、医疗或安全领域的专业结论；异常情况请结合实际植物状态判断。',
        ),
        LegalDocumentSection(
          heading: '四、服务变更',
          body: '因设备固件、云服务或法律政策变化，我们可能更新功能和条款，并在重要变更时进行提示。',
        ),
        LegalDocumentSection(
          heading: '五、责任限制',
          body: '因断网、停电、设备不当使用或第三方平台不可用造成的服务中断，将在法律允许范围内合理处理。',
        ),
      ],
    );
  }

  final String pageTitle;
  final String documentTitle;
  final String updatedAt;
  final String effectiveAt;
  final List<LegalDocumentSection> sections;
}

class LegalDocumentSection {
  const LegalDocumentSection({required this.heading, required this.body});

  final String heading;
  final String body;
}
