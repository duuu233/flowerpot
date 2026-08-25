"""Regenerates docs/DP_GAP_REPORT.html from the table below.

The report is written by hand each round rather than derived from the source
tree — the status column is a reading of the code, not something a script can
decide. What this file buys is that the strip, the counters and the appendix
can never disagree with each other: they all come from `ROWS`.

Run from the repository root:

    python3 tool/build_dp_gap_report.py
"""

import html

REPORT = 'docs/DP_GAP_REPORT.html'

# (dp, 名称, 标识符, 数据类型, 读写, 状态, 当前实现)
ROWS = [
    (101, '设备状态上报', 'device_status', 'string', '可下发可上报', 'idle',
     '读进 deviceStatus，界面未使用，也从未写回；取值语义仍未定义'),
    (102, '陪伴天数', 'together_days', 'value', '只上报', 'ok',
     '首页/设备信息「已陪伴 N 天」，未上报时按绑定时间兜底'),
    (103, '电量', 'battery_level', 'value', '只上报', 'ok', '首页电量、电量状态页；上报即刷新'),
    (104, '电池状态', 'battery_status', 'enum', '只上报', 'ok', '电量状态页枚举，设备未报时回落阈值'),
    (105, '水位', 'water_level', 'value', '只上报', 'ok', '水位状态页与水位报表；上报即刷新'),
    (106, '土壤湿度', 'soil_moist', 'value', '只上报', 'ok', '土壤湿度状态页与报表；上报即刷新'),
    (107, '需水状态', 'water_needs_status', 'enum', '只上报', 'ok', '需水状态页枚举'),
    (108, '光照状态', 'lighting_condition', 'enum', '只上报', 'ok', '光照状态页枚举'),
    (109, '光照值', 'light_intensity', 'value', '只上报', 'ok', '光照值与光照报表'),
    (110, '光照PPFD值', 'light_ppfd_value', 'value', '只上报', 'ok',
     '光照状态页 PPFD 卡片，DLI 由 PPFD 推算'),
    (111, '光照PAR值', 'light_par_value', 'value', '只上报', 'idle',
     '读进 SensorSnapshot.par，界面仍未展示'),
    (112, '空气温度', 'air_temperature', 'value', '只上报', 'ok',
     '读取除以 10；单位跟随 146，App 只换标签不做二次换算'),
    (113, '空气温度状态', 'air_temperature_status', 'enum', '只上报', 'ok', '温度状态页枚举'),
    (114, '空气湿度', 'air_humidity', 'value', '只上报', 'ok', '读取除以 10，湿度状态页'),
    (115, '空气湿度状态', 'air_humidity_status', 'enum', '只上报', 'ok', '湿度状态页枚举'),
    (116, '植物品种', 'plant_variety', 'string', '可下发可上报', 'ok',
     '后端 tuYaRemark 作为标识符；绑定成功后下发，上报反向更新当前植物'),
    (117, '显示屏幕亮度开关', 'disp_brightness_switch', 'bool', '可下发可上报', 'ok',
     '显示设置页自动亮度；设备回执会回写本地设置'),
    (118, '声音互动开关', 'voice_interaction_switch', 'bool', '可下发可上报', 'ok', '听觉设置页开关'),
    (119, '声音互动灵敏度', 'sound_sensitivity', 'value', '可下发可上报', 'ok', '听觉设置页灵敏度滑杆'),
    (120, '触摸交互开关（指的是植物触摸）', 'touch_interact_switch', 'bool', '可下发可上报', 'ok',
     '触摸设置页开关'),
    (121, '触摸交互灵敏度', 'touch_sense_sensitivity', 'value', '可下发可上报', 'ok', '触摸设置页灵敏度滑杆'),
    (122, '震动开关', 'vibration_switch', 'bool', '可下发可上报', 'ok', '震动设置页主开关'),
    (123, '触摸按键震动开关', 'touch_vib_switch', 'bool', '可下发可上报', 'ok',
     '震动设置页新增「触摸按键震动」开关'),
    (124, '触摸植物震动开关', 'touch_plant_vib_switch', 'bool', '可下发可上报', 'ok',
     '震动设置页新增「触摸植物震动」开关'),
    (125, '中午小憩开关', 'nap_time_switch', 'bool', '可下发可上报', 'ok', '行为设置页中午小憩开关'),
    (126, '中午小憩开始时间', 'nap_start_time', 'value', '可下发可上报', 'ok',
     '行为设置页时间段；展示跟随 147，写回仍是 24h 的分钟数'),
    (127, '中午小憩结束时间', 'nap_end_time', 'value', '可下发可上报', 'ok', '同 126'),
    (128, '夜间睡眠开关', 'night_sleep_switch', 'bool', '可下发可上报', 'ok', '行为设置页夜间睡眠开关'),
    (129, '夜间睡眠开始时间', 'night_sleep_start_time', 'value', '可下发可上报', 'ok', '同 126'),
    (130, '夜间睡眠结束时间', 'night_sleep_end_time', 'value', '可下发可上报', 'ok', '同 126'),
    (131, '水仓水位历史日', 'tank_level_daily_hist', 'raw', '只上报', 'ok',
     'TuyaHistoryCodec 解码；上报即并入快照，图表需重进页面才重画'),
    (132, '水仓水位历史周', 'tank_level_weekly_hist', 'raw', '只上报', 'ok', '同 131'),
    (133, '水仓水位历史月', 'tank_level_monthly_hist', 'raw', '只上报', 'ok', '同 131'),
    (134, '土壤湿度历史日', 'soil_moist_daily_hist', 'raw', '只上报', 'ok', '同 131'),
    (135, '土壤湿度历史周', 'soil_moist_weekly_hist', 'raw', '只上报', 'ok', '同 131'),
    (136, '土壤湿度历史月', 'soil_moist_monthly_hist', 'raw', '只上报', 'ok', '同 131'),
    (137, '光照历史日', 'light_daily_hist', 'raw', '只上报', 'ok', '同 131（2 字节采样）'),
    (138, '光照历史周', 'light_weekly_hist', 'raw', '只上报', 'ok', '同 131（2 字节采样）'),
    (139, '光照历史月', 'light_monthly_hist', 'raw', '只上报', 'ok', '同 131（2 字节采样）'),
    (140, '水位校准动作', 'water_level_calib', 'enum', '只下发', 'ok',
     '四次确认依次下发 step0–step3，取消下发 step5；step4 保留不用'),
    (141, '恢复出厂设置', 'factory_reset', 'bool', '只下发', 'cond',
     '解绑前先下发 141，再调 SDK resetFactory；固件收到后的行为待确认'),
    (142, '下载图片', 'dl_url', 'raw', '只下发', 'none',
     'APP 后端已提供图片上传与 URL；硬件 raw 编码、限制和回执仍待确认'),
    (143, '显示图片', 'dl_show', 'string', '只下发', 'none', '同 142，没有「显示指定图片」入口'),
    (144, '取消显示', 'dl_cancel', 'bool', '只下发', 'none', '同 142，没有「取消显示」入口'),
    (145, '充电状态', 'charge_status', 'bool', '只上报', 'ok', '首页与电量状态页充电态'),
    (146, '温度单位转换', 'temp_unit_convert', 'enum', '可下发可上报', 'ok',
     '设置页下发 C/F；App 的温度标签、舒适阈值与建议文案都跟随'),
    (147, '时间格式', 'time_format', 'enum', '可下发可上报', 'ok',
     '设置页下发 24h/12h；作息标签跟随，趋势图刻度仍固定 24h'),
    (148, '固件版本', 'firmware_version', 'string', '只上报', 'ok', '设备信息页固件版本'),
    (149, '硬件版本', 'hardware_version', 'value', '只上报', 'ok', '设备信息页硬件版本'),
    (150, '重新配网', 're_pairing', 'bool', '只下发', 'cond',
     '产品口径：不下发 150，触发时重走配网流程；DP 保留未用'),
]

LABEL = {'ok': '已接入', 'cond': '有条件', 'idle': '已读未用', 'none': '未接入'}

CLOSED = [
    ('DP 实时上报已接通',
     'Android <code>registerDevListener</code>、iOS <code>ThingSmartDeviceDelegate</code>，两端推同一条事件通道 '
     '<code>com.common.yikaltd/tuya_events</code>；Dart 把增量并进设备快照后刷新界面。没有轮询。'),
    ('iOS 配网前置已补齐',
     '<code>scanWifi</code> 与 <code>prepareActivatorToken</code> 已实现，令牌缓存 8 分钟且单次使用。'
     'iOS 拿不到附近网络列表是平台限制，不是未实现。'),
    ('五条无源曲线改成空态',
     '按产品口径「没有就为空」：温度、湿度、电量、DLI 与报表页不再用当前读数画一个点。数据源本身仍缺，见 P1。'),
    ('温标与时间格式 App 侧跟随',
     'DP 112 的单位列写的就是 <code>°C/°F</code>，设备切华氏后上报值已是华氏，因此只换标签、只换算 App 自己的摄氏阈值。'),
    ('两个震动场景开关补上界面',
     '<code>touch_vib_switch</code>（123）与 <code>touch_plant_vib_switch</code>（124）在震动设置页主卡下方独立成卡，'
     '主卡 Figma 尺寸不变。'),
    ('恢复出厂改为先下发 141',
     '解绑前下发 DP 141，再调 SDK <code>resetFactory</code>；设备离线不阻断解绑。重新配网按口径不下发 150。'),
    ('OTA 两端对齐',
     'iOS 补上 <code>getFirmwareUpgradeInfo</code> → <code>upgradeFirmware</code>；Android 改为只在 '
     '<code>upgradeStatus == 1</code> 时报新版本，不再无条件提示有升级。'),
    ('植物品种双向链路已接通',
     '后端植物 <code>tuYaRemark</code> 作为 DP 116 标识符；先绑定用户植物再下发，设备上报已知值会反向更新 App。'),
    ('水位校准枚举已确认',
     '四次确认严格发送 <code>step0</code>–<code>step3</code>，取消发送 <code>step5</code>，任何路径都不发送 <code>step4</code>。'),
    ('Dart 代码已运行验证',
     '<code>dart analyze</code> 无编译错误，后端、DP 116、校准弹窗与相关页面定向测试已通过；真机链路仍单列为风险。'),
]

GAPS = [
    ('p0', '挡住跨平台发布：Dart 逻辑已验证，但 iOS 与真实后端/设备仍未完成真机闭环。', [
        ('G15', 'APP 后端 HTTPS 与真实账号未验证', ['API_BASE_URL', 'Swagger', 'userToken'], [
            ('现状', 'Swagger 契约已完成代码接入；2026-08-25 核验时提供的 HTTPS 域名返回备案阻断页，'
                     '机器端口只用于读取契约，没有使用真实 Token 调用写接口。'),
            ('缺什么', '恢复可用 HTTPS 服务，配置后台产品 <code>broadcastId</code> 与涂鸦 PID 映射，'
                     '再用测试账号验证登录、设备关联、植物绑定和图片增删。'),
            ('影响', '当前只能证明请求形状、状态编排与 Mock 测试正确，不能证明生产服务数据和权限配置正确。'),
        ], ['lib/src/core/backend/app_backend_repository.dart', 'docs/history/2026-08/2026-08-25-app-backend-plant-dp116-calibration.md']),
        ('G02', 'iOS 真机链路整体未验证', ['ThingSmartCryption', 'Podfile', 'Bundle ID'], [
            ('现状', '安全组件刚放进 <code>ios/TuyaSDK/</code>，Podfile 跟随其 SDK 线改为 '
                     '<code>ThingSmartHomeKit ~> 7.8.0</code>。AppKey/AppSecret 走 <code>Tuya.xcconfig</code>，'
                     '签名与 Bundle ID 尚未在 Xcode 侧核对。'),
            ('缺什么', '<code>pod install</code>、Bundle ID 与平台一致性核对、真机登录与配网。'
                     '若要读到当前 Wi-Fi 名，还需在 Target 打开 Access WiFi Information 能力。'),
            ('影响', 'iOS 端账号、配网、DP 上报、OTA 全部处于「代码写完、没跑过」状态。'),
        ], ['ios/Podfile', 'ios/Runner/AppDelegate.swift', 'ios/TuyaSDK/']),
    ]),
    ('p1', '功能点表里有、或界面上已经存在，但还差一段链路的能力。', [
        ('G03', '图片下发链路仍未接', ['142 dl_url', '143 dl_show', '144 dl_cancel'], [
            ('现状', 'APP 后端图片列表、上传和删除已经接通；<code>uploadAnimation</code> 两端仍返回 '
                     '<code>product_protocol_required</code>，尚未把云端 URL 发给硬件。'),
            ('缺什么', '确认 <code>dl_url</code> 的 raw 编码、文件格式/大小限制与下载回执，再补 143/144 显示控制。'),
            ('影响', '图片能进入账号云端列表，但真机屏幕仍不会播放。'),
        ], ['lib/src/core/backend/app_backend_repository.dart', 'android/…/MainActivity.kt uploadAnimation']),
        ('G04', 'iOS 没有「分享链接」这个接口', ['createShareLink'], [
            ('现状', 'Android 用业务拓展 SDK 的 <code>createShareInfo</code> 生成链接；iOS Home SDK 的设备分享只有'
                     '<strong>按账号分享</strong>（<code>ThingSmartDeviceShare</code>），涂鸦文档里没有 iOS 的链接接口。'),
            ('缺什么', '产品先定分享形态：改成填写接收方账号，还是 iOS 单独降级。定了才好写，'
                     '现在 iOS 返回 <code>share_service_unavailable</code>。'),
            ('影响', '同一版本的 App，iOS 比 Android 少一项设备能力。'),
        ], ['ios/Runner/AppDelegate.swift createShareLink']),
        ('G05', '五条曲线仍然没有数据源', ['PPFD', 'DLI', '温度', '湿度', '电池'], [
            ('现状', '功能点表只给了水位、土壤湿度、光照三组历史（131–139）。这五个指标已按口径显示空态，不再画假点。'),
            ('缺什么', '要么固件补历史 DP，要么开通涂鸦设备数据统计服务或自建后端。'),
            ('影响', '真机上这五页的图表区域长期是空态卡片。'),
        ], ['lib/src/tuya/tuya_config.dart history', 'lib/…/widgets/metric_history_empty_card.dart']),
        ('G06', '趋势图不随实时上报刷新', ['131–139'], [
            ('现状', '读数会自己变（<code>FlowerpotScope</code> 是 <code>InheritedNotifier</code>），'
                     '但图表取的是 <code>historyFor</code> 返回的 <code>Future</code>，只在进页面时求值一次。'),
            ('缺什么', '把历史改成随设备快照重建，或在收到历史 DP 时重新触发一次取数。'),
            ('影响', '设备推来新的历史包时，正停在报表页的用户看不到变化，要退出重进。'),
        ], ['lib/…/reports_page.dart', 'lib/…/water_status_page.dart']),
        ('G07', '「修复系统文件」是个空按钮', ['无对应功能点'], [
            ('现状', '设备设置页里的入口点了只提示「系统修复暂未开放」。功能点表从 140 直接跳到 141。'),
            ('缺什么', '产品确认这个功能是否保留：保留就让固件补一条 DP，不保留就把入口去掉。'),
            ('影响', '目前是设置页里唯一一个明说「没做」的入口。'),
        ], ['lib/…/device_other_settings_page.dart']),
    ]),
    ('p2', '需要产品或固件先给一个说法，代码改动本身都不大。', [
        ('G08', '设备状态上报的语义还没定义', ['101 device_status'], [
            ('现状', '表里唯一一条可下发可上报的 string，导出件没写取值。读进了 deviceStatus，界面没用，也从没写过。'),
            ('缺什么', '产品给出取值枚举和读写约定，再决定放在首页还是设备信息页。'),
            ('影响', '一条 rw 功能点闲置；如果它承载的是设备工作模式，那影响的是首页主状态。'),
        ], ['lib/src/tuya/tuya_models.dart deviceStatus']),
        ('G09', '光照 PAR 读了不展示', ['111 light_par_value'], [
            ('现状', '值已经进了 <code>SensorSnapshot.par</code>，光照状态页只展示光照值、PPFD 和推算的 DLI。'),
            ('缺什么', '确认 PAR 要不要露出：要就在光照状态页加一格，不要就把字段一并去掉。'),
            ('影响', '小；但留着不用的字段会让人以为界面漏了。'),
        ], ['lib/…/widgets/light_status_summary_card.dart']),
        ('G12', '固件收到 141 之后做什么', ['141 factory_reset'], [
            ('现状', 'App 已按口径在解绑前下发 141，再调 SDK 的 <code>resetFactory</code>。'),
            ('缺什么', '固件确认：收到 141 后设备清哪些数据、是否自己断开绑定、要不要回执，以及和 SDK 解绑的先后是否有要求。'),
            ('影响', '顺序或语义错了，会出现「云端已解绑、设备还留着旧数据」这类不一致。'),
        ], ['lib/src/state.dart _publishFactoryReset']),
        ('G13', '123/124 与主开关 122 的关系', ['122', '123', '124'], [
            ('现状', '功能点表把三者列为各自独立的可写点，所以界面上三个开关互不联动。'),
            ('缺什么', '固件确认 122 是不是总闸：如果是，关掉 122 时两个场景开关应当置灰。'),
            ('影响', '当前用户可以在总开关关闭时仍然打开场景开关，界面表达可能和设备实际行为不符。'),
        ], ['lib/…/widgets/vibration_scene_switches_card.dart']),
        ('G14', '配网前两步仍是模拟，iOS 更没有扫描', ['搜索设备', '选择设备'], [
            ('现状', '整条配网动线里只有 Wi-Fi 那一步是真实 SDK 调用。iOS 侧连当前网络名都要额外能力才读得到，'
                     '附近网络列表在 iOS 上不存在公开 API。'),
            ('缺什么', '产品早前的建议是改成「确认设备已进入配网状态」的引导页——设备只支持 2.4 GHz Wi-Fi、没有蓝牙，'
                     '本来就不存在设备发现这一步。需要拍板。'),
            ('影响', '真机配网时这两页给的是假反馈，且两端表现不一致。'),
        ], ['lib/…/device_search_page.dart', 'lib/…/device_selection_page.dart']),
    ]),
]

QUESTIONS = [
    ('固件收到 141 之后做什么？', '清哪些数据、是否自己断开绑定、要不要回执，和 SDK 解绑的先后顺序。'),
    ('142 的 raw 数据如何编码？', '后端上传已返回图片 URL；还要定 URL 编码、图片格式与大小上限、设备下载完成怎么回执。'),
    ('101 的取值有哪些？', '它是设备工作模式，还是别的东西。'),
    ('122 是不是 123/124 的总闸？', '决定主开关关闭时两个场景开关要不要置灰。'),
    ('温度、湿度、电池、PPFD、DLI 要不要历史？', '固件加 DP，还是开通涂鸦统计服务/自建后端。'),
    ('设备分享要不要改成按账号分享？', 'iOS Home SDK 没有生成分享链接的接口，两端要统一形态。'),
]


def esc(text):
    return html.escape(text, quote=True)


def build():
    head = open(REPORT, encoding='utf-8').read().split('</style>', 1)[0] + '</style>\n'
    counts = {key: sum(1 for row in ROWS if row[5] == key) for key in LABEL}
    assert sum(counts.values()) == len(ROWS) == 50
    todo = sum(len(items) for _, _, items in GAPS)

    out = [head, '''
<div class="page">

  <header class="masthead">
    <div class="eyebrow"><span>PID orhqsdjyigmh8bwa</span><span>第三版 · 2026-08-25 复核</span><span>DP 101–150</span></div>
    <h1>智能花盆功能点落地差距</h1>
    <p class="lede">第三版把 APP 后端植物与设备图片链路纳入核对，并按最新产品口径关闭 DP 116 双向同步和 DP 140 校准序列缺口；仍未完成的事项继续按真机发布风险排序。</p>
    <div class="meta">
      <span>核对基线 <b>main / 9b057dc + 未提交工作区</b></span>
      <span>对照范围 <b>lib/src/core/backend、tuya、features、android、ios</b></span>
      <span>功能点来源 <b>assets/智能花盆test(orhqsdjyigmh8bwa)_08_20.xlsx</b></span>
    </div>
  </header>

  <section>
    <div class="stats">
''']
    out.append(f'      <div class="stat is-ok"><span class="figure">{counts["ok"]}</span><span class="caption">已接入并有界面</span></div>\n')
    out.append(f'      <div class="stat is-cond"><span class="figure">{counts["cond"]}</span><span class="caption">有条件可用</span></div>\n')
    out.append(f'      <div class="stat is-idle"><span class="figure">{counts["idle"]}</span><span class="caption">读到了没用上</span></div>\n')
    out.append(f'      <div class="stat is-none"><span class="figure">{counts["none"]}</span><span class="caption">完全没接</span></div>\n')
    out.append(f'      <div class="stat"><span class="figure">{todo}</span><span class="caption">待办事项</span></div>\n')
    out.append('''    </div>
  </section>

  <section>
    <div class="section-head">
      <span class="kicker">本轮已关闭</span>
      <h2>按产品口径已经关闭的能力</h2>
      <p>「关闭」指 App 侧契约、代码和定向测试已经对齐；真实后端、固件与跨平台真机验证仍单列为风险。</p>
    </div>
    <ul class="questions">
''')
    for title, body in CLOSED:
        out.append(f'      <li><b>{esc(title)}</b>{body}</li>\n')
    out.append('''    </ul>
  </section>

  <section>
    <div class="section-head">
      <span class="kicker">DP 101 – 150 覆盖</span>
      <h2>五十条功能点的落地状态</h2>
      <p>鼠标停在格子上看功能点名称。DP 实时上报、植物品种双向同步与校准序列已经落实；「有条件」和「未接入」仍表示需要固件、平台或真机验证。</p>
    </div>
    <ul class="strip">
''')
    for dp, name, ident, _typ, _rw, status, _note in ROWS:
        title = f'{dp} {name} · {ident} · {LABEL[status]}'
        out.append(f'<li class="cell {status}" title="{esc(title)}"><span class="cell-id">{dp}</span></li>\n')
    out.append('''    </ul>
    <div class="legend">
      <span><i class="swatch ok"></i>已接入并有界面</span>
      <span><i class="swatch cond"></i>有条件可用</span>
      <span><i class="swatch idle"></i>读到了没用上</span>
      <span><i class="swatch none"></i>完全没接</span>
    </div>
  </section>

  <section>
    <div class="section-head">
''')
    out.append(f'      <span class="kicker">缺口清单 · {todo} 项</span>\n')
    out.append('''      <h2>还缺哪些</h2>
      <p>P0 是挡住跨平台发布的真机验证，P1 是链路还差一段的能力，P2 需要产品或固件先给一个说法。</p>
    </div>
''')
    for tier, note, items in GAPS:
        out.append(f'''
    <div class="band {tier}">
      <span class="tier">{tier.upper()}</span>
      <span class="band-note">{note}</span>
    </div>
    <div class="gaps">
''')
        for gid, title, chips, fields, evidence in items:
            chip_html = ''.join(
                f'<span class="chip{"" if any(c.isdigit() for c in chip) else " plain"}">{esc(chip)}</span>'
                for chip in chips
            )
            out.append(f'''
      <article class="gap">
        <div class="gap-head">
          <div class="gap-title"><span class="gap-id">{gid}</span><h3>{esc(title)}</h3></div>
          <div class="chips">{chip_html}</div>
        </div>
        <dl>
''')
            for term, body in fields:
                out.append(f'          <dt>{term}</dt><dd>{body}</dd>\n')
            ev = ''.join(f'<span class="mono">{esc(item)}</span>' for item in evidence)
            out.append(f'''        </dl>
        <div class="evidence"><span>证据</span>{ev}</div>
      </article>
''')
        out.append('    </div>\n')
    out.append('''  </section>

  <section>
    <div class="section-head">
      <span class="kicker">需要外部答复</span>
''')
    out.append(f'      <h2>等产品或固件回话的{len(QUESTIONS)}个问题</h2>\n')
    out.append('''      <p>这些不是写代码能解决的，建议一次问完。</p>
    </div>
    <ul class="questions">
''')
    for question, detail in QUESTIONS:
        out.append(f'      <li><b>{esc(question)}</b>{esc(detail)}</li>\n')
    out.append('''    </ul>
  </section>

  <section>
    <div class="section-head">
      <span class="kicker">附录</span>
      <h2>全量功能点对照</h2>
      <p>五十条功能点逐行对照当前实现。「有条件可用」的说明里写了它依赖什么。</p>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>DP</th><th>功能点名称</th><th>标识符</th><th>数据类型</th><th>读写</th><th>状态</th><th>当前实现</th></tr>
        </thead>
        <tbody>
''')
    for dp, name, ident, typ, rw, status, note in ROWS:
        out.append(
            f'<tr><td class="num">{dp}</td><td>{esc(name)}</td>'
            f'<td class="mono">{esc(ident)}</td><td class="mono dim">{esc(typ)}</td>'
            f'<td class="dim">{esc(rw)}</td>'
            f'<td><span class="tag {status}">{LABEL[status]}</span></td>'
            f'<td class="note">{esc(note)}</td></tr>\n'
        )
    out.append('''        </tbody>
      </table>
    </div>
  </section>

  <footer>
    <p><b>验证边界：</b>Dart 静态分析与相关定向测试已通过；后端 HTTPS 域名、真实 Token、固件 DP 与 iOS 真机仍未形成端到端闭环。</p>
    <p>核对基线 main / 9b057dc + 未提交工作区 · 功能点表导出于 2026-08-20 · 本页由 <code>tool/build_dp_gap_report.py</code> 生成 · 相关文档：<code>docs/history/2026-08/2026-08-25-app-backend-plant-dp116-calibration.md</code>、<code>docs/TUYA_SDK_SETUP.md</code>、<code>docs/PRD_IMPLEMENTATION.md</code></p>
  </footer>

</div>
''')
    open(REPORT, 'w', encoding='utf-8').write(''.join(out))
    print(f'{REPORT}: {counts}, 待办 {todo} 项')


if __name__ == '__main__':
    build()
