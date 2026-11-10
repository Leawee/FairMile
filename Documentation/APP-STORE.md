# App Store 上架资料

商店文案是英文，可以直接粘贴。括号里的中文是给你看的说明。

## 已经公开的地址

- 隐私政策：https://leawee.github.io/FairMile/
- 支持页面：https://leawee.github.io/FairMile/support.html
- 商品 ID 已经写在 App 和 RevenueCat 里，三边必须一致：
  - `app.fairmile.plus.monthly`
  - `app.fairmile.plus.yearly`
  - `app.fairmile.plus.lifetime`

## App 信息

| 栏 | 填写 |
| --- | --- |
| Name | FairMile |
| Subtitle | Editable IRS mileage log |
| Bundle ID | app.fairmile.ios |
| SKU | fairmile-ios |
| Primary category | Finance |
| Secondary category | Business |
| Price | Free |
| Copyright | 2026 加上你的法定姓名 |
| Content rights | 不包含第三方内容 |
| Age rating | 4+。没有不受限网页、没有用户之间的分享、没有博彩、没有医疗建议。 |

Subtitle 共 26 个字符，上限 30。

### Promotional text

Editable trips, IRS rates by date, and a full-year export. $39.99/year after a 7-day trial.

### Description

FairMile is a mileage log you can check. Start when you leave, end when you park, then fix the trip so the record matches what happened.

It measures the path while FairMile is open. This version does not track in the background. You can also add a past trip by hand.

Each business, charity, or medical trip uses the IRS standard mileage rate for the day it started. A year with two rates stays two rates. Personal trips stay in the log and are left out of the estimate.

Edit the miles, move the start or end, split a mixed drive, or merge two adjacent trips. Edited records stay marked. Parking and tolls can be attached to a trip.

Export a PDF or CSV with the date, places, miles, purpose, category, rate, and estimated amount. The yearly plan includes the full calendar year.

FairMile Plus is $4.99 a month, $39.99 a year with a 7-day free trial, or $79.99 once. The free log includes 15 trips each calendar month.

Records are for you and your tax professional. This is not tax advice. FairMile is not affiliated with the IRS.

### Keywords

IRS mileage,1099,Schedule C,mileage log,reimbursement,tax log

### What's New

First release. Record a trip, edit it, and export a log that uses the IRS rate for each start date.

### Review notes

FairMile is a manual mileage log. The user taps Start and End. Location is When In Use only. There is no background tracking and no Always permission.

No account is required. The log stays on the device. Purchases use StoreKit: monthly app.fairmile.plus.monthly, yearly app.fairmile.plus.yearly with a 7-day free trial, lifetime app.fairmile.plus.lifetime.

The app is not tax software and does not claim an IRS certification. The disclaimer is on the home screen, in Settings, on the paywall, and in the PDF footer.

Please exclude mainland China from availability.

### App Privacy

- Precise Location: App Functionality. Not linked to identity. Not used for tracking.
- Photos: App Functionality, receipt photos only. Not linked. Not used for tracking.
- Tracking: No.
- Data is not sold.

### 订阅（App Store Connect）

订阅组名：FairMile Plus。Family Sharing 关闭。

| 产品 | 类型 | 价格 | 显示名 | 说明 |
| --- | --- | --- | --- | --- |
| app.fairmile.plus.yearly | 自动续期，1 年 | 39.99 USD | FairMile Plus Yearly | Unlimited trips, receipt photos, and full-year PDF and CSV export, with a 7-day free trial. |
| app.fairmile.plus.monthly | 自动续期，1 个月 | 4.99 USD | FairMile Plus Monthly | Unlimited trips, receipt photos, and full-year PDF and CSV export. |
| app.fairmile.plus.lifetime | 非消耗型 | 79.99 USD | FairMile Plus Lifetime | Unlimited trips, receipt photos, and full-year PDF and CSV export. |

年费的介绍优惠：免费试用，1 周，1 个周期。只挂在年费上。

可用性：美国。不要勾选中国大陆。不要用「所有国家」一键全选。

订阅审核需要一张付费页截图。付费页已经在 App 的 Plus 里。

## 只能由账号持有人完成

- 加入 Apple Developer Program，并签 Paid Applications 协议。
- 填写税务表和收款银行。
- 用你的开发者团队签名，上传第一条构建版本。
- 在 App Store Connect 创建 App、订阅组和三个商品。RevenueCat 里的商品 ID 已经对齐，但 Apple 侧还没有这些商品。
