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
              '位置和附近 Wi-Fi 设备权限用于 2.4GHz Wi-Fi 配网；相册和相机权限用于设置头像或提交反馈；通知权限用于发送设备状态和养护提醒。相关权限仅在功能需要时申请，您可以在系统设置中随时关闭。',
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
          body:
              '欢迎使用 YSplanter（以下简称“本应用”）。\n'
              '本协议是您与 YSplanter 服务提供方之间，就您下载、安装、注册、登录和使用本应用及相关智能设备服务所订立的协议。\n'
              '在使用本应用前，请您仔细阅读并充分理解本协议全部内容。您使用本应用，即表示您已阅读、理解并同意接受本协议的约束。',
        ),
        LegalDocumentSection(
          heading: '一、服务说明',
          body:
              '1. 本应用为智能花盆设备提供移动端管理服务，包括设备添加、WiFi 配网、设备状态查看、植物管理、养护提醒、传感器校准、设备设置、固件升级、设备共享等功能。\n'
              '2. 本应用显示的水位、温度、湿度、电量等信息，来源于设备传感器采集及系统计算结果，可能受到网络环境、设备状态、传感器精度、使用环境等因素影响。\n'
              '3. 本应用提供的植物养护建议、提醒内容和状态提示，仅作为日常养护参考。实际养护时，您仍需结合植物品种、季节、室内环境和实际状态进行判断。\n'
              '4. 我们会尽力保障服务稳定运行，但由于网络波动、系统维护、设备故障、第三方服务异常等原因，服务可能出现中断、延迟或异常。',
        ),
        LegalDocumentSection(
          heading: '二、账号注册与使用规则',
          body:
              '1. 您可以通过手机号码及验证码，或本应用支持的第三方账号完成注册和登录。您应确保所提供的信息真实、准确、完整。\n'
              '2. 您应妥善保管账号、验证码和登录设备，不得将账号转让、出租或出借给他人使用。\n'
              '3. 因您主动泄露、保管不善或遭受他人攻击、诈骗等行为导致的损失，请及时联系我们并采取修改密码等安全措施。\n'
              '4. 如发现账号存在异常使用或安全风险，我们可以依法采取验证身份、限制功能或暂停服务等措施。',
        ),
        LegalDocumentSection(
          heading: '三、设备绑定与使用',
          body:
              '1. 您应按照产品说明正确添加、配置和使用智能花盆，并确保操作环境、供电和网络满足设备要求。\n'
              '2. 绑定、控制、分享或解除绑定设备前，请确认您拥有相应设备的合法使用权。\n'
              '3. 因错误配置、擅自拆卸、非官方固件或违反产品说明造成的设备异常，可能无法获得正常服务支持。',
        ),
        LegalDocumentSection(
          heading: '四、用户行为规范',
          body:
              '您不得利用本应用实施违反法律法规、侵害他人合法权益、干扰网络或设备正常运行、绕过安全验证、传播恶意程序等行为，也不得以未经授权的方式获取或使用他人数据。',
        ),
        LegalDocumentSection(
          heading: '五、知识产权',
          body:
              '本应用的软件、界面、文字、图形、标识及相关技术的知识产权归其合法权利人所有。未经书面许可，您不得复制、修改、反向工程、出售或以其他方式进行商业使用。',
        ),
        LegalDocumentSection(
          heading: '六、服务变更、中断与终止',
          body:
              '我们可能根据产品规划、设备能力、云服务状态或法律法规要求调整服务。发生重大变化时，我们会通过应用内提示等合理方式告知您；停止服务时，将依法为您提供必要的数据处理说明。',
        ),
        LegalDocumentSection(
          heading: '七、免责声明',
          body:
              '在法律允许的范围内，对于因不可抗力、运营商网络故障、第三方服务异常、用户不当操作或设备自然损耗导致的服务中断和损失，我们将积极协助处理，但不承担超出法定范围的责任。',
        ),
        LegalDocumentSection(
          heading: '八、协议更新',
          body: '我们可能根据业务变化和法律法规要求更新本协议。更新后的协议将在本页面展示，并标明新的生效日期；重大变更会以显著方式提示。',
        ),
        LegalDocumentSection(
          heading: '九、联系我们',
          body: '如您对本协议有任何疑问、意见或建议，可以通过应用内帮助中心联系我们。我们会在合理期限内核实并处理。',
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
