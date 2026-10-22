# APP 机器日志对接表

| 等级 | 中文 | English | 抓取 DP | 触发条件 | DP111 位 |
|---|---|---|---|---|---|
| 严重 | 电池异常，机器已停机 | Battery fault, machine stopped | DP120 | 值 = `1` | `device 0x001` |
| 通知 | 电池异常已恢复 | Battery fault cleared | DP120 | 值 = `101` | `device 0x001` |
| 严重 | IMU 异常，机器已停机 | IMU fault, machine stopped | DP120 | 值 = `2` | `device 0x002` |
| 通知 | IMU 异常已恢复 | IMU fault cleared | DP120 | 值 = `102` | `device 0x002` |
| 严重 | 存储异常，机器已停机 | Storage fault, machine stopped | DP120 | 值 = `3` | `device 0x004` |
| 通知 | 存储异常已恢复 | Storage fault cleared | DP120 | 值 = `103` | `device 0x004` |
| 严重 | 左轮电机离线，机器已停机 | Left wheel motor offline, machine stopped | DP120 | 值 = `4` | `device 0x008` |
| 通知 | 左轮电机离线已恢复 | Left wheel motor back online | DP120 | 值 = `104` | `device 0x008` |
| 严重 | 右轮电机离线，机器已停机 | Right wheel motor offline, machine stopped | DP120 | 值 = `5` | `device 0x010` |
| 通知 | 右轮电机离线已恢复 | Right wheel motor back online | DP120 | 值 = `105` | `device 0x010` |
| 严重 | 刀盘电机离线，机器已停机 | Blade motor offline, machine stopped | DP120 | 值 = `6` | `device 0x020` |
| 通知 | 刀盘电机离线已恢复 | Blade motor back online | DP120 | 值 = `106` | `device 0x020` |
| 严重 | 机器倾覆，请检查现场 | Machine tilted, check the site | DP120 | 值 = `11` | `error 0x0001` |
| 通知 | 机器倾覆已恢复 | Machine tilt cleared | DP120 | 值 = `111` | `error 0x0001` |
| 严重 | 机器被抬起，已停机 | Machine lifted, stopped | DP120 | 值 = `12` | `error 0x0002` |
| 通知 | 机器被抬起已恢复 | Machine lift cleared | DP120 | 值 = `112` | `error 0x0002` |
| 严重 | 边界线信号异常，机器已停机 | Boundary signal fault, machine stopped | DP120 | 值 = `13` | `error 0x0004` |
| 通知 | 边界线信号已恢复 | Boundary signal restored | DP120 | 值 = `113` | `error 0x0004` |
| 严重 | 左轮电机过流，机器已停机 | Left wheel overcurrent, machine stopped | DP120 | 值 = `14` | `error 0x0008` |
| 通知 | 左轮电机过流已恢复 | Left wheel overcurrent cleared | DP120 | 值 = `114` | `error 0x0008` |
| 严重 | 左轮电机过温，机器已停机 | Left wheel overheated, machine stopped | DP120 | 值 = `15` | `error 0x0010` |
| 通知 | 左轮电机过温已恢复 | Left wheel overheat cleared | DP120 | 值 = `115` | `error 0x0010` |
| 严重 | 左轮电机霍尔异常，机器已停机 | Left wheel hall error, machine stopped | DP120 | 值 = `16` | `error 0x0020` |
| 通知 | 左轮电机霍尔异常已恢复 | Left wheel hall error cleared | DP120 | 值 = `116` | `error 0x0020` |
| 严重 | 右轮电机过流，机器已停机 | Right wheel overcurrent, machine stopped | DP120 | 值 = `17` | `error 0x0040` |
| 通知 | 右轮电机过流已恢复 | Right wheel overcurrent cleared | DP120 | 值 = `117` | `error 0x0040` |
| 严重 | 右轮电机过温，机器已停机 | Right wheel overheated, machine stopped | DP120 | 值 = `18` | `error 0x0080` |
| 通知 | 右轮电机过温已恢复 | Right wheel overheat cleared | DP120 | 值 = `118` | `error 0x0080` |
| 严重 | 右轮电机霍尔异常，机器已停机 | Right wheel hall error, machine stopped | DP120 | 值 = `19` | `error 0x0100` |
| 通知 | 右轮电机霍尔异常已恢复 | Right wheel hall error cleared | DP120 | 值 = `119` | `error 0x0100` |
| 严重 | 刀盘电机过温，机器已停机 | Blade motor overheated, machine stopped | DP120 | 值 = `20` | `error 0x0400` |
| 通知 | 刀盘电机过温已恢复 | Blade motor overheat cleared | DP120 | 值 = `120` | `error 0x0400` |
| 严重 | 刀盘电机霍尔异常，机器已停机 | Blade hall error, machine stopped | DP120 | 值 = `21` | `error 0x0800` |
| 通知 | 刀盘电机霍尔异常已恢复 | Blade hall error cleared | DP120 | 值 = `121` | `error 0x0800` |
| 严重 | 刀盘堵转（可能卡异物），机器已停机 | Blade stalled (possible obstruction), stopped | DP120 | 值 = `22` | `error 0x1000` |
| 通知 | 刀盘堵转已恢复 | Blade stall cleared | DP120 | 值 = `122` | `error 0x1000` |
| 严重 | 机器在边界外，已停机 | Machine outside boundary, stopped | DP120 | 值 = `23` | `error 0x4000` |
| 通知 | 边界外停机已解除 | Outside-boundary stop cleared | DP120 | 值 = `123` | `error 0x4000` |
| 严重 | 定点作业位置超出边界，已停机 | Spot position out of boundary, stopped | DP120 | 值 = `24` | `error 0x8000` |
| 通知 | 定点割草位置已回到界内 | Spot position back in boundary | DP120 | 值 = `124` | `error 0x8000` |
| 严重 | 机器被困（陷坑），已停机 | Machine stuck (pit), stopped | DP120 | 值 = `31` | `function 0x002` |
| 通知 | 机器被困（陷坑）已解除 | Machine stuck (pit) cleared | DP120 | 值 = `131` | `function 0x002` |
| 严重 | 机器故障停机 | Machine stopped: fault | DP5 | 值变为 `6` | — |
| 严重 | 机器被急停 | Emergency stop activated | DP5 | 值变为 `7` | — |
| 轻微 | 机器陷入坑洼，正在脱困 | Recovering from stuck | DP120 | 值 = `41` | `circularize 0x008` |
| 通知 | 机器已脱困 | Recovered from stuck | DP120 | 值 = `141` | `circularize 0x008` |
| 轻微 | 丢失边界信号，正在搜索 | Boundary signal lost, searching | DP120 | 值 = `42` | `circularize 0x010` |
| 通知 | 边界信号已找回 | Boundary signal found | DP120 | 值 = `142` | `circularize 0x010` |
| 轻微 | 机器在边界外，正在找回 | Outside boundary, recovering | DP120 | 值 = `43` | `circularize 0x020` |
| 通知 | 机器已自行回到边界内 | Back inside boundary | DP120 | 值 = `143` | `circularize 0x020` |
| 轻微 | 机器被抬起 | Machine lifted | DP120 | 值 = `44` | `circularize 0x1000` |
| 通知 | 机器已被放下 | Machine put down | DP120 | 值 = `144` | `circularize 0x1000` |
| 轻微 | 机器盖子被打开 | Cover opened | DP118 | 由 `1` 变 `0` | — |
| 通知 | 检测到积水，机器自动回充 | Water detected, returning to dock | DP120 | 值 = `45` | `circularize 0x002` |
| 通知 | 积水已消失 | Water cleared | DP120 | 值 = `145` | `circularize 0x002` |
| 通知 | 电量过低，机器自动回充 | Battery too low, returning to dock | DP120 | 值 = `46` | `circularize 0x004` |
| 通知 | 电量已回升 | Battery level recovered | DP120 | 值 = `146` | `circularize 0x004` |
| 通知 | 开始割草 | Mowing started | DP5 | 值变为 `1` | — |
| 通知 | 开始沿边割草 | Edge mowing started | DP5 | 值变为 `8` | — |
| 通知 | 开始定点割草 | Spot mowing started | DP5 | 值变为 `3` | — |
| 通知 | 开始第二区域割草 | Secondary area mowing started | DP5 | 值变为 `11` | — |
| 通知 | 作业结束，正在返回充电桩 | Work finished, returning to dock | DP5 | 由 `1/3/8/11` 变为 `4` | — |
| 通知 | 作业已取消，机器待机 | Work cancelled, standby | DP5 | 由 `1/3/8/11` 变为 `0` | — |
| 通知 | 机器已回到充电桩 | Machine docked | DP5 | 由 `4` 变为 `9` 或 `10` | — |
| 通知 | 检测到降雨，机器等待雨停 | Rain detected, waiting at dock | DP5 | 值变为 `10` | — |
| 通知 | 已开始充电 | Charging started | DP117 | 值变为 `1` | — |
| 通知 | 充电完成 | Charging complete | DP117 | 值变为 `2` | — |
| 通知 | 机器已离开充电桩 | Machine left the dock | DP117 | 由 `1/2` 变为 `0` | — |
| 通知 | 电量低（{v}%），即将自动回充 | Battery low ({v}%), returning soon | DP13 | 首次 ≤ `35` | — |
| 通知 | 机器盖子已关闭 | Cover closed | DP118 | 由 `0` 变 `1` | — |
| 通知 | 设备已关机 | Device powered off | DP113 | 由 `false` 变 `true` | — |
| 通知 | 设备已开机 | Device powered on | DP113 | 由 `true` 变 `false` | — |
| — | （上电复位值，不记日志） | (boot reset value, ignore) | DP120 | 值 = `0` | — |
