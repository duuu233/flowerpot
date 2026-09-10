# Wi-Fi 热点模式
热点配网又称 **热点模式**  或 **AP (Access Point) 配网**，是一种通过 Wi-Fi 进行配网的连接能力。将手机连接到配网设备 Wi-Fi 热点后，设备与手机直接通过 Wi-Fi 进行通信配对。成功率高、可靠性好，可适配 2.4GHz 和 5GHz 混频路由器配网，但用户需要手动切换手机的 Wi-Fi 设置。

## 查询配网 Token

开始配网之前，需要在联网状态下从涂鸦查询配网 Token，然后才可以开始快连模式配网。Token 的有效期为 10 分钟，且配置成功后就会失效。再次配网时，需要重新查询 Token。

```java
ThingActivatorDeviceCoreKit.getActivatorInstance()
                .getActivatorToken(spaceId,IThingActivatorGetToken)
```

**参数说明**

| 参数 | 说明 |
| ---- | ---- |
| spaceId | 设备将绑定到的家庭 ID |
| callback | 获取结果回调 |

## 开始配网

```java
val builder = ThingDeviceActiveBuilder()
            .setActiveModel(ThingDeviceActiveModeEnum.AP)
            .setSsid(ssid)
            .setPassword(pwd)
            .setToken(token)
            .setTimeOut(timeout)
            .setListener(object : IThingDeviceStatePauseActiveListener {
                override fun onFind(devId: String) {
                }

                override fun onBind(devId: String) {
                }

                override fun onActiveSuccess(deviceBean: DeviceBean) {

                }

                override fun onActiveError(errorBean: ThingDeviceActiveErrorBean) {

                }

                override fun onActiveLimited(limitBean: ThingDeviceActiveLimitBean) {
                }

        override fun onActivatorStatePauseCallback(stateData: PauseStateData?) {

                }
            })

val mThingActivatorManager = ThingActivatorCoreKit.getActiveManager().newThingActiveManager()
mThingActivatorManager.startActive(builder)
```

**参数说明**

| 参数 | 意义 |
| ---- | ---- |
| ssid | Wi-Fi 名称 |
| password | Wi-Fi 密码 |
| token | token 信息 |
| timeout | 超时时长，单位为秒（s） |
| activeModel | 配网能力枚举 |
| listener | 配网结果回调 |

:::info
- 如果您不需要监听 `onActivatorStatePauseCallback` 逻辑，则可以使用原有的 `IThingDeviceActiveListener` 接口即可。
- `onActivatorStatePauseCallback` 是用来得到热点设备配网暂停状态，会返回对应密码错误或者连接路由器失败，可以重新扫描 Wi-Fi 列表并选择。再次调用 `resumeActive` 方法继续配网该热点设备。
:::

## 恢复配网

部分新热点设备会通过 `onActivatorStatePauseCallback` 方法返回 Wi-Fi 密码错误以及路由器连接失败等信息，可以用过该方法继续设备配网。

```java
val builder = ThingResumeActiveBuilder()
            .setSsid(ssid)
            .setPassword(pwd)

mThingActivatorManager.resumeActive(builder)
```

## 停止配网

```java
mThingActivatorManager.stopActive()
```