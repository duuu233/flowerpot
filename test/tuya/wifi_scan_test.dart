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
