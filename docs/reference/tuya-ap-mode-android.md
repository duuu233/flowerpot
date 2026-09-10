# Wi-Fi 热点模式
热点配网又称 **热点模式** 或 AP（Access Point）配网，是一种通过 Wi-Fi 进行配网的连接能力。将手机连接到配网设备 Wi-Fi 热点后，App 与设备直接通过 Wi-Fi 进行通信配网。成功率高、可靠性好，可适配 2.4G/5G 混频路由器配网，但用户需要手动切换手机的 Wi-Fi 设置。

## 热点配网原流程
### 初始化配网参数

**接口说明**

```java
ActivatorBuilder builder = new ActivatorBuilder()
        .setContext(context)
        .setSsid(ssid)
        .setPassword(password)
        .setActivatorModel(ActivatorModelEnum.TY_AP)
        .setTimeOut(timeout)
        .setToken(token)
        .setListener(new IThingSmartActivatorListener() {

                @Override
                public void onError(String errorCode, String errorMsg) {

                }

                @Override
                public void onActiveSuccess(DeviceBean devResp) {

                }

                @Override
                public void onStep(String step, Object data) {

                }
            }
        ));
```

**参数说明**

| 参数 | 说明 |
| ---- | ---- |
| token | 配网所需要的激活 Token |
| context | 需要传入 `activity` 的 `context` |
| ssid | 配网之后，设备工作 Wi-Fi 的名称 |
| password | 配网之后，设备工作 Wi-Fi 的密码 |
| activatorModel | 配网模式，快连模式：`ActivatorModelEnum.TY_AP` |
| timeout | 配网的超时时间设置，默认是 100s，单位是秒 |

### 获取配网 Token

开始配网之前，SDK 需要在联网状态下从云端获取配网 Token，Token 的有效期为 10 分钟。且配置成功后就会失效，再次配网需要重新获取。

**接口说明**

```java
ThingHomeSdk.getActivatorInstance().getActivatorToken(homeId,
        new IThingActivatorGetToken() {

            @Override
            public void onSuccess(String token) {

            }

            @Override
            public void onFailure(String s, String s1) {

            }
        });
```

**参数说明**

| 参数 | 说明 |
| ---- | ---- |
| homeId | 家庭 ID，详情参考 [家庭管理](https://developer.tuya.com/cn/docs/app-development/homemanage?id=Ka6kjkgere4ae) 章节 |

### 配网方法调用

```java
IThingActivator mThingActivator = ThingHomeSdk.getActivatorInstance().newActivator(builder);
//开始配网
mThingActivator.start();
//停止配网
mThingActivator.stop();
//退出页面销毁一些缓存和监听
mThingActivator.onDestroy();
```

## 热点配网新流程

为了提高用户的配网体验，减少出错概率，提高 SDK 用户的配网成功率，因此引入一套新的配网流程机制。该流程针对新设备固件才有效，只有新设备固件才支持。

:::info
待配网设备的应用固件使用的 TuyaOS 版本号，不低于 3.6.1。
:::

### 获取对应的安全配置列表

```java
 ThingHomeSdk.getActivatorInstance().getDeviceSecurityConfigs(new IThingDataCallback<String>() {
            @Override
            public void onSuccess(String result) {
                securityConfig = result;
                //获取成功

            }

            @Override
            public void onError(String errorCode, String errorMessage) {

            }
        });
```

**接口说明**

```java
ThingApActivatorBuilder builder = new ThingApActivatorBuilder().setContext(this);
```

**参数说明**

| 参数 | 说明 |
| ---- | ---- |
| context | 需要传入 activity 的 context |

**请求示例**

```java
IThingOptimizedActivator mThingActivator = ThingHomeSdk.getActivatorInstance().newOptimizedActivator(builder);
```


### 查询设备扫描到的 Wi-Fi 列表

SDK 会先查询设备此时的状态，如果处于异常状态，例如 SDK 未能识别的状态，则不会向查询 Wi-Fi 列表。

```java
ApQueryBuilder queryBuilder = new ApQueryBuilder.Builder().setContext(context).setTimeout(queryParam.timeout == null ? 0 : queryParam.timeout * 1000).build();
mThingActivator.queryDeviceConfigState(queryBuilder, new IThingResultCallback<List<Wi-FiInfoBean>>() {
        @Override
        public void onSuccess(List<Wi-FiInfoBean> result) {
            //获取 Wi-Fi 列表成功
        }

        @Override
        public void onError(String errorCode, String errorMessage) {
            //获取 Wi-Fi 列表失败
        }
    });
```

**参数说明**

**ApQueryBuilder**

| 参数 | 说明 |
| ---- | ---- |
| context | 需要传入 activity 的 context |
| timeout | 可选项，如果大于 0，则会开启超时计时，单位为 ms |

**Wi-FiInfoBean**

| 参数 | 说明 |
| ---- | ---- |
| ssid | 设备扫描到的 Wi-Fi 名称 |
| rssi | Wi-Fi 的信号强度 |
| sec | 协议值，映射关系如下： <ul><li> 0    -> WAAM_OPEN </li><li> 1    -> WAAM_WEP </li><li> 2    -> WAAM_WPA_PSK </li><li> 3    -> WAAM_WPA2_PSK </li><li> 4    -> WAAM_WPA_WPA2_PSK </li><li> 5    -> WAAM_WPA_WPA3_SAE </li><li> 6    -> WAAM_UNKNOWN </li></ul> 在获取到 Wi-Fi 列表后，如果用户选择了指定 Wi-Fi，可以根据协议，提前判断用户输入的密码。例如 2 ≦ `sec` ≦ 5，密码长度都是不小于 8 位，减少出错率。 |

### 开始配网

可以根据查询到 Wi-Fi 列表，让用户进行选择。

```java
ApActivatorBuilder builder = new ApActivatorBuilder.Builder()
        .setSsid("ssid")
        .setPwd("password")
        .setTimeout(timeout)
        .setToken(token)
        .setSecurityConfig(securityConfig)
        .setListener(new IThingSmartActivatorListener() {
            @Override
            public void onError(String errorCode, String errorMsg) {
                //配网失败
                //errorCode 见文末介绍
            }

            @Override
            public void onActiveSuccess(DeviceBean devResp) {
                //配网成功
            }

            @Override
            public void onStep(String step, Object data) {
                //和原有配网参数一致
            }
        }).build();
mThingActivator.startActivator(builder);
```

**参数说明**

**ApActivatorBuilder**

| 参数 | 说明 |
| ---- | ---- |
| ssid | 配网之后，设备工作 Wi-Fi 的名称 |
| password | 配网之后，设备工作 Wi-Fi 的密码 |
| token | 配网所需要的激活 Token |
| timeout | 配网的超时时间设置，必传，单位是毫秒 |
| securityConfig | 获取对应的安全配置列表 （可选）主要是给设备配网对应安全等级信息 |

### 恢复配网

一般在密码错误情况下，可以使用恢复配网，重新传入 Wi-Fi 名称和密码，恢复配网。

在配网过程中，SDK 会在指定时间内自动去连接 AP 热点，如果连上后，SDK 内部会去获取设备状态，上报给业务方。只针对新设备固件有效。

```java
ApHandlerBean bean = new ApHandlerBean.Builder()
               .setSsid("ssid")
               .setPassword("password")
               .build();
mThingActivator.resumeAPConfigWifi(bean);
```

**参数说明**

**ApHandlerBean**

| 参数 | 说明 |
| ---- | ---- |
| ssid | 配网之后，设备工作 Wi-Fi 的名称 |
| password | 配网之后，设备工作 Wi-Fi 的密码 |

### 停止配网

在配网停止后，或者是资源销毁时需要手动调用结束。

```java
mThingActivator.stopActivator();
```

### 错误码

错误码跟设备连接强关联，设备信息错误都是通过向设备获取。

| 错误码 | 说明 |
| ---- | ---- |
| 207201 | 和设备建立连接通道失败 |
| 207206 | 查询设备状态，设备返回了不能识别的状态，即非正常状态 |
| 207207 | 设备不支持获取 Wi-Fi 列表功能 |
| 207209 | 设备收到配网信息后，配网信息错误 |
| 207210 | 设备收到配网信息后，找不到路由器 |
| 207211 | 设备收到配网信息后，密码错误 |
| 207212 | 设备收到配网信息后，连接路由器失败 |
| 207213 | 设备收到配网信息后，DHCP 失败 |
| 207214 | 设备连云信息激活错误 |
| 207215 | 设备连云失败 |
| 207216 | 设备激活接口失败 |
| 207218 | 设备激云端接口请求失败 |
| 207219 | 设备激活，和云端 iot-dns 连接失败 |
| 207220 | 配网超时 |
| 207222 | 获取设备 Wi-Fi 列表信息失败 |