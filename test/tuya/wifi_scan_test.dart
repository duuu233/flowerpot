import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

WifiNetwork _network(String ssid, int level, int frequency) =>
    WifiNetwork(ssid: ssid, level: level, frequency: frequency);

void main() {
  test('device hotspots are the planter access points, strongest first', () {
    const scan = WifiScan(
      networks: <WifiNetwork>[
        WifiNetwork(ssid: 'TP-LINK_2.4G', level: -40, frequency: 2437),
        WifiNetwork(ssid: 'SmartLife-A1B2', level: -70, frequency: 2412),
        WifiNetwork(ssid: 'TY_C3D4', level: -55, frequency: 2412),
        WifiNetwork(ssid: 'YSplanter-01', level: -60, frequency: 2412),
      ],
    );

    expect(scan.deviceHotspots.map((item) => item.ssid), <String>[
      'TY_C3D4',
      'YSplanter-01',
      'SmartLife-A1B2',
    ]);
  });

  test('只列某一刻之后真的看见过的热点：缓存里的旧条目不算', () {
    // 2026-09-21 产品：「不要缓存，根据实际搜索的情况展示」。系统扫描缓存里混着几分钟前
    // 的结果——设备早关了，热点还挂在里面。
    final roundStart = DateTime(2026, 9, 21, 10);
    final before = roundStart.subtract(const Duration(minutes: 3));
    final after = roundStart.add(const Duration(seconds: 2));
    final scan = WifiScan(
      networks: <WifiNetwork>[
        WifiNetwork(ssid: 'TY_OLD', level: -40, frequency: 2412, seenAt: before),
        // 同一个热点名一新一旧：旧的那条信号更强，也不能把新的那条顶掉。
        WifiNetwork(
          ssid: 'SmartLife-A1B2',
          level: -45,
          frequency: 2412,
          seenAt: before,
        ),
        WifiNetwork(
          ssid: 'SmartLife-A1B2',
          level: -70,
          frequency: 2412,
          seenAt: after,
        ),
        // 恰好在那一刻看见的算本轮。
        WifiNetwork(
          ssid: 'YSplanter-01',
          level: -60,
          frequency: 2412,
          seenAt: roundStart,
        ),
        // 平台不报时间：判不了新旧，照列。
        _network('TY_C3D4', -80, 2412),
        _network('TP-LINK_2.4G', -30, 2437),
      ],
    );

    final fresh = scan.deviceHotspotsSeenSince(roundStart);
    expect(fresh.map((item) => item.ssid), <String>[
      'YSplanter-01',
      'SmartLife-A1B2',
      'TY_C3D4',
    ]);
    expect(fresh[1].level, -70);
    // 不按时间筛的那份照旧全列。
    expect(scan.deviceHotspots, hasLength(4));
  });

  test('hotspot naming variants across firmware builds still count', () {
    // A shipped planter was seen raising `SmartLift-8987`; the whitelist used
    // to require `smartlife`, so the pairing pages reported no device while
    // the raw scan in the SDK console showed it.
    expect(WifiNetwork.isDeviceHotspotName('SmartLift-8987'), isTrue);
    expect(WifiNetwork.isDeviceHotspotName('SmartLife-A1B2'), isTrue);
    expect(WifiNetwork.isDeviceHotspotName('smart_life 8987'), isTrue);
    expect(WifiNetwork.isDeviceHotspotName('TuyaSmart-77'), isTrue);
    expect(WifiNetwork.isDeviceHotspotName('TY_C3D4'), isTrue);
    expect(WifiNetwork.isDeviceHotspotName('YSplanter-01'), isTrue);
    // Near misses stay out: `ty` without its separator is an ordinary word.
    expect(WifiNetwork.isDeviceHotspotName('Tybee_Home'), isFalse);
    expect(WifiNetwork.isDeviceHotspotName('TP-LINK_2.4G'), isFalse);
    expect(WifiNetwork.isDeviceHotspotName(''), isFalse);
  });

  test('other networks are the manual pick list: no hotspots, no 5 GHz', () {
    final scan = WifiScan(
      networks: <WifiNetwork>[
        _network('SmartLife-A1B2', -50, 2412),
        _network('Home', -72, 2412),
        _network('Home', -48, 2462),
        _network('Home_5G', -40, 5180),
        // iOS-style entry with no band reported: unknown, so it stays.
        _network('Unknown_Band', -60, 0),
        _network('', -45, 2437),
      ],
    );

    expect(scan.otherNetworks.map((item) => item.ssid), <String>[
      'Home',
      'Unknown_Band',
    ]);
    expect(scan.otherNetworks.first.level, -48);
  });

  test('router networks drop 5 GHz, hotspots and duplicate SSIDs', () {
    final scan = WifiScan(
      networks: <WifiNetwork>[
        // Same network seen twice; the stronger reading wins.
        _network('Home', -72, 2412),
        _network('Home', -48, 2462),
        _network('Home_5G', -40, 5180),
        _network('SmartLife-A1B2', -50, 2412),
        _network('', -45, 2437),
        _network('Office', -66, 2437),
      ],
    );

    expect(scan.routerNetworks.map((item) => item.ssid), <String>[
      'Home',
      'Office',
    ]);
    expect(scan.routerNetworks.first.level, -48);
  });

  test('an unknown band is not reported as 5 GHz', () {
    // iOS sends no frequency at all, and Android answers 0 or -1 when it is not
    // connected. Neither may turn into "switch to 2.4G" advice.
    expect(const WifiScan(networks: <WifiNetwork>[]).currentIs24g, isNull);
    expect(
      const WifiScan(
        networks: <WifiNetwork>[],
        currentFrequency: 0,
      ).currentIs24g,
      isNull,
    );
    expect(
      const WifiScan(
        networks: <WifiNetwork>[],
        currentFrequency: 2437,
      ).currentIs24g,
      isTrue,
    );
    expect(
      const WifiScan(
        networks: <WifiNetwork>[],
        currentFrequency: 5180,
      ).currentIs24g,
      isFalse,
    );
  });

  test('the phone itself can be sitting on a planter hotspot', () {
    // Which is exactly the state AP provisioning has to be started from.
    expect(
      const WifiScan(
        networks: <WifiNetwork>[],
        current: 'SmartLife-A1B2',
      ).currentIsDeviceHotspot,
      isTrue,
    );
    expect(
      const WifiScan(
        networks: <WifiNetwork>[],
        current: 'TP-LINK_2.4G',
      ).currentIsDeviceHotspot,
      isFalse,
    );
    expect(
      const WifiScan(networks: <WifiNetwork>[]).currentIsDeviceHotspot,
      isFalse,
    );
  });

  test('signal bars follow the usual four steps', () {
    expect(_network('a', -40, 2437).signalBars, 4);
    expect(_network('a', -60, 2437).signalBars, 3);
    expect(_network('a', -70, 2437).signalBars, 2);
    expect(_network('a', -90, 2437).signalBars, 1);
  });
}
