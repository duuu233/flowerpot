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

  static const HelpCenterPageModel figma = HelpCenterPageModel(
    initiallyExpandedIds: <String>{'add-device'},
    items: <HelpCenterFaqItem>[
      HelpCenterFaqItem(
        id: 'add-device',
        question: '如何添加设备？',
        answer:
            '1.请确认智能花盆已开机，并处于待绑定状态。\n'
            '2.在首页点击【添加设备】\n'
            '3.选择搜索到的设备，点击【连接】\n'
            '4.连接成功后，即可开始管理植物养护。\n'
            '若未搜索到设备，请将手机靠近花盆，并确认设备\n'
            '电量充足后重新搜索。',
      ),
      HelpCenterFaqItem(
        id: 'wifi-pairing',
        question: 'Wi-Fi配网问题',
        answer: '请确认手机已连接2.4GHz Wi-Fi（不能是5GHz），并已开启定位权限。输入正确的Wi-Fi密码后，将手机靠近智能花盆重新配网。',
      ),
      HelpCenterFaqItem(
        id: 'device-not-found',
        question: '为什么搜索不到设备？',
        answer: '请确认设备已开机并处于配网状态（指示灯闪烁）。若指示灯没有闪烁，请长按复位键让设备重新进入配网模式，必要时先为花盆充电。',
      ),
      HelpCenterFaqItem(
        id: 'device-offline',
        question: '设备离线了怎么办？',
        answer: '请检查设备电量和家庭网络是否正常。将设备重新开机并等待网络恢复；长时间离线时，可在设置中重新配网。',
      ),
      HelpCenterFaqItem(
        id: 'soil-moisture',
        question: '为什么土壤湿度没有变化？',
        answer: '浇水后传感器读数需要一定时间稳定。请确认植物内胆安装到位、土壤与传感区域接触良好，并稍后刷新查看。',
      ),
      HelpCenterFaqItem(
        id: 'rebind-plant',
        question: '如何重新绑定植物？',
        answer: '进入设备设置，点击“选择植物”，重新选择当前种植的植物并确认即可。',
      ),
    ],
  );
}
