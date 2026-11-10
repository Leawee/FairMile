# 合规

用户能看见的合规句子以 `FairMile/Services/Copy.swift` 为准。权限弹窗字符串在 `project.yml`，测试要求它和 `Copy.locationUsage`、`Copy.cameraUsage` 相同。

这些句子要出现的位置：

- `Copy.notTaxAdvice`：首页、设置、导出、付费页、引导最后一页，以及 PDF 正文和页脚。
- `Copy.locationUsage`：系统定位说明、定位被拒绝的提示、设置里的 Location。
- `Copy.keepOpen`：记录中的屏幕。
- `Copy.standardMileageReminder`：收据区和有收据的 PDF。
- `Copy.notTheIRS`：税率页、导出页、PDF。
- `Copy.editedMeaning`：行程编辑的历史区，以及 PDF。

不要使用 IRS 标志，不要写 certified、guaranteed，也不要写 automatically tracks。

## 税率

唯一的内置数字在 `FairMile/Resources/Rates.json`。2026-11-10 对照 IRS 标准里程税率页核过：

- 2026-01-01 至 2026-06-30：商务 72.5（IR-2025-128），慈善 14，医疗 20.5
- 2026-07-01 至 2026-12-31：商务 76（IR-2026-29），慈善 14，医疗 23.5
- 2025 全年：商务 70，慈善 14，医疗 21（IR-2024-312）

医疗税率在 2026 年年中也变了。新增一年时改 JSON，写上 IRS notice，并在 `LedgerTests` 里锁住 6 月 30 日和 7 月 1 日。没有税率的日期，估算留空。自定义行盖过同一天的 IRS 行；两条自定义重叠时，开始日较晚的那条生效。

行程用设备本地时区的开始日选税率。

## 定位和隐私

只用 When In Use。Info.plist 不包含 `UIBackgroundModes`。不要把行程、轨迹或收据发到自建服务器。隐私政策的公开页是 `https://leawee.github.io/FairMile/`，源文件是 `docs/index.html`。

## 导出和付费

CSV 列名在 `CSVExporter.headers`。商务行程没有事由，或商务/慈善/医疗没有税率时，不生成文件。

商品 ID：

- `app.fairmile.plus.monthly`：$4.99
- `app.fairmile.plus.yearly`：$39.99，7 天免费试用
- `app.fairmile.plus.lifetime`：$79.99

免费额度是每个自然月 15 趟，按行程开始日所在月份计算。近 30 天可以导出。完整自然年导出需要 Plus。恢复购买必须留着。付费页把三档价格都写出来，年费是主按钮。

App Store Connect 的隐私标签按实际勾选：精确位置和收据照片用于 App 功能，不关联身份，不用于追踪。分发排除中国大陆。
