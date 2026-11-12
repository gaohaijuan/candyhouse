# 甜蜜糖果屋 · Google Play 内购与广告接入方案(总指挥,2026-11-12)

用户要求:上架 Google Play 前,先按 Google 的接口要求定内购价格与广告接入的做法。本文是调研结论与落地分工;包名待用户申请(倾向带 candyhouse)。

## 1. 硬性要求(截至 2026-11-12)
- 新应用和更新必须 target Android 16(API 36),2026-08-31 起生效。
- Play 结算库:第 7 版已停用(2026-08-31,延期到 11-01),新上传至少用第 8 版;第 8 版截止 2027-08-31。
- 上传格式 AAB;Play App Signing;上传密钥由用户创建保管。
- 数字商品(金币、礼包、去广告)必须走 Google Play 结算。

## 2. 价格:语言 ≠ 币种
- 价格与币种由 Google Play 按**玩家 Play 账户地区**决定,与游戏语言无关(美国玩家设日语仍付美元;Play 不在中国大陆上架,简体中文玩家多在新加坡、马来西亚等地)。现在“中文=人民币、日文=日元、韩文=韩元”的写死做法只能留给电脑调试。
- Play 后台:每个商品填一个默认价(美元),Play 按汇率和各地“好看的价格”自动生成各国本地价,可逐国手改。
- 游戏内:启动和打开商店时 `query_product_details` 取回各商品的本地化价格字符串(如 “US$0.99”“¥160”“₩1,500”)和以微单位表示的金额,**原样显示**。查不到(无网络、不在 Play、商品未上架)就显示“暂不可购买”,按钮置灰,不显示写死价格。
- 礼包上的对比文案(“价值 ¥6”“超值 64 倍”“1折”“+10%”)必须按 Play 返回的真实金额算,不能写死,避免误导性定价。做法:以 coins_600 的单价换算礼包内容的“价值”,倍数和折扣由此计算。
- 带价格的美术(限时礼包贴纸、主页礼包图标)要换成**无价格底图 + 程序文字**,文字按“框上文字要融为一体”的规矩做。日/韩价格图因此不再使用。

## 3. 内购接入(Godot)
- 插件:Godot 官方 GodotGooglePlayBilling(godot-sdk-integrations,v3.x,基于结算库 8.x,支持 Godot 4.2+)。需要开启 Gradle 构建(`gradle_build/use_gradle_build=true`)。
- 接口:`BillingClient.start_connection()` → `query_product_details(ids, ProductType.INAPP)` → `purchase(id)` → 信号 `on_purchase_updated` → 消耗型 `consume_purchase(token)`、非消耗型 `acknowledge_purchase(token)`;启动时 `query_purchases(INAPP)` 补发未处理订单。
- **3 天内必须 consume 或 acknowledge**,否则 Google 自动退款并收回。
- `PENDING` 状态(待付款)不能发货,等变成 `PURCHASED`。
- 商品类型(对应 data/economy.json 的 iap):
  - coins_600 / coins_3300 / coins_8000 / coins_16000 / coins_45000 / coins_95000:消耗型。
  - starter(1折礼包)、limited(限时礼包):一次性,做成非消耗型(acknowledge),换机/重装后恢复时只恢复“已买过”标记,不重复发货。
  - no_ads:非消耗型,恢复时恢复去广告。
- 订单校验:暂无服务器,先做本地校验——用 Play 后台的应用公钥,`Crypto.verify(SHA256)` 验 `original_json` 的签名;以后有服务器再改用 Play Developer API 服务端校验。
- 测试:先上传带结算权限的包到“内部测试”轨道才能建商品;用户把测试账号加为许可测试人员,真机上测购买、取消、待付款、恢复。

## 4. 广告接入
- 平台 AdMob;插件 poingstudios/godot-admob-plugin(v5,Godot 4.5+,有激励、插屏、横幅、开屏等,内置 UMP 同意管理)。
- 用到的形式:激励视频(免费金币、道具、体力、签到翻倍、胜利翻倍、复活、宝箱翻倍,次数见 economy.json ad_limits);插屏(第 8 关起每 3 关、间隔不少于 90 秒)。买了去广告:不再插屏,激励直接给奖励(现有逻辑)。
- 同意:欧洲经济区、英国、瑞士必须用 Google 认证的同意管理(UMP)在首次展示广告前征求同意;设置页要加“隐私选项”入口让玩家改选择。
- 开发期只用 Google 的测试广告位 ID(ca-app-pub-3940256099942544/…),绝不点自己的正式广告。
- Play 后台:声明“含广告”;数据安全表填写广告 ID 等设备标识用于广告;隐私政策写明 AdMob。广告 SDK 会自带 AD_ID 权限。
- 目标年龄建议选 13 岁以上,避免进入“家庭”政策(儿童向应用的广告与 AD_ID 限制更严)。
- 建议准备一个开发者网站放 app-ads.txt 和隐私政策,商店页填该网站。

## 5. 分工与顺序
1. 总指挥(代码):`purchase_service.gd` 接 Play 结算(无插件时仍用模拟,电脑调试照常);价格改为 Play 返回字符串,查不到置灰;对比文案按真实金额计算;恢复购买;本地签名校验。`ad_service.gd` 接 AdMob(测试 ID)+ UMP 同意 + 设置页隐私选项。保持现有两个接口不变,页面不用改调用。
2. Codex(Windows):装两个插件、Android 构建模板、JDK 17、Android SDK(build-tools、platform 36);导出 AAB/APK(测试广告 ID、调试签名);出无价格礼包底图(image_gen)。
3. 用户:Google Play 开发者账号、建应用、定包名、上传密钥;Play 后台按上表建 9 个商品(默认美元价按现有档位);许可测试人员;AdMob 账号、应用、广告位;隐私政策网址。
4. 联测:内部测试轨道 + 真机,逐项测购买/恢复/广告/同意弹窗。
