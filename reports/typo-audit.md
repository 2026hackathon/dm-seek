# 🔍 Typo & Grammar Audit Report

**wonder-consumer-project** · backend + frontend · 2026-06-14

---

| total | spelling | grammar | double spaces |
|-------|----------|---------|---------------|
| **38** | 5 | 23 | 10 |

---

## 1️⃣ Spelling Mistakes (5 found)

| # | File | Current | Fix | Type |
|---|------|---------|-----|------|
| 1 | `restaurant-service-v2/.../BOBrandBundleItemService.java:191` | ~~anther~~ brand bundle item | **another** brand bundle item | spelling |
| 2 | `restaurant-service-v2/.../BOBrandMenuItemService.java:193` | ~~anther~~ brand bundle item | **another** brand bundle item | spelling |
| 3 | `restaurant-service-v2/.../ErrorCodes.java:7` | `DUPLICATED_NAME` | `DUPLICATE_NAME` | code name |
| 4 | `merchandising-site-frontend/.../module.ts:25` (×3 files) | `"DUPLICATED_NAME"` | `"DUPLICATE_NAME"` | code name |

> ⚠️ **#3–4**: `DUPLICATED_NAME` is used as an error code string across backend (7 call sites) and frontend (3 files). "Duplicated" is not standard English — "Duplicate" is correct. Changing it requires **coordinated backend + frontend release** since the frontend parses this error code string in `ERROR_CODE_LIST`.

---

## 2️⃣ Grammar Issues — User-Facing Strings (23 found)

### A. "not find" → "not found" / "cannot find"

| # | File | Current | Fix |
|---|------|---------|-----|
| 1 | `CartItemValidator.java:77` (×3 files) | ~~bundle choice not find~~ | **bundle choice not found** |
| 2 | `CartItemValidator.java:106` (×3 files) | ~~menu item option not find~~ | **menu item option not found** |
| 3 | `BOBundleItemService.java:53` | ~~not find bundle item~~ | **bundle item not found** |
| 4 | `GiftCardService.java:198` | ~~can not found~~ gift card product | **cannot find** gift card product |

### B. "can not" → "cannot"

| # | File | Current | Fix |
|---|------|---------|-----|
| 1 | `CancelOrderValidator.java:60` | ~~can not~~ cancel order when food is delivered. | **Cannot** cancel order when food is delivered. |
| 2 | `CancelOrderValidator.java:81` | ~~can not~~ fail order for current order status | **Cannot** fail order for current order status |
| 3 | `BORestaurantBrandService.java:217` | ~~can not~~ delete a restaurant brand when it was linked | **Cannot** delete a restaurant brand when it is linked |
| 4 | `BOHDRFeeConfigurationService.java:149` | ~~can not delete~~ | **cannot be deleted** |
| 5 | `BOHDRFeeConfigurationService.java:224` | ~~can not delete~~ | **cannot be deleted** |
| 6 | `BOHDRFeeConfigurationService.java:309` | ~~can not delete~~ | **cannot be deleted** |
| 7 | `BOHDRTipConfigurationService.java:130` | ~~can not delete~~ | **cannot be deleted** |
| 8 | `BOWonderSpotFeeConfigurationService.java:174` | ~~can not delete~~ | **cannot be deleted** |
| 9 | `TaxService.java:190` | You ~~can not~~ apply fee tax | You **cannot** apply fee tax |
| 10 | `TaxService.java:215` | ~~can not apply~~ rule | **cannot apply** rule |
| 11 | `BOChallengeService.java:80` | ~~can not edit~~ expire | **Cannot edit** expired |
| 12 | `BOChallengeService.java:214` | ~~can not update~~ start date | **cannot update** start date |
| 13 | `BOChallengeService.java:217` | ~~can not update to before~~ | **cannot be set to a past date** |
| 14 | `BOChallengeService.java:223` | ~~can not update~~ start date | **cannot update** start date |
| 15 | `BOChallengeService.java:226` | ~~can not update to today and before~~ | **cannot be set to today or earlier** |
| 16 | `BOOrderService.java:409` | ~~can not resend~~ email. | **Cannot resend** email. |
| 17 | `CustomerCancelOrderService.java:308` | order ~~can not cancel~~ at this time | order **cannot be cancelled** at this time |
| 18 | `HDRCancelOrderService.java:369` | order ~~can not cancel~~ at this time | order **cannot be cancelled** at this time |

### C. Broken grammar

| # | File | Current | Fix |
|---|------|---------|-----|
| 1 | `CartItemValidator.java:89` (×3) | bundle item choice ~~can not more than~~ | **cannot exceed** |
| 2 | `CartItemValidator.java:114` (×3) | menu item options ~~can not more than~~ | **cannot exceed** |
| 3 | `BundleItemHelper.java:279` | values' number ~~must greater than or equal min~~ | values' count **must be ≥ min choice** |
| 4 | `BundleItemHelper.java:283` | values' number ~~must greater than or equal max~~ | values' count **must be ≤ max choice** |

---

## 3️⃣ Double Spaces Inside Strings (10 found)

| # | File | Current | Fix |
|---|------|---------|-----|
| 1 | `CartItemValidator.java:77` (×3) | `bundle choice not find`**`  `**`,choice id = {}` | `bundle choice not found, choice id = {}` |
| 2 | `CartItemValidator.java:89` (×3) | `bundle item choice can not`**`  `**`more than {}` | `bundle item choice cannot exceed {}` |
| 3 | `FirstPlaceOrderService.java:40` | `can not find`**`  `**`the question` | `cannot find the question` |
| 4 | `BOBrandBundleItemService.java:191` | `{} is used`**`  `**`by anther brand...` | `{} is used by another brand...` |
| 5 | `BOItemPriceWebServiceImpl.java:99` | `item number`**`  `**`option id`**`  `**`option value id`**`  `**`not be null` | `item number, option id, option value id must not be null` |
| 6 | `BOItemPriceWebServiceImpl.java:145` | `item number`**`  `**`option id`**`  `**`option value id`**`  `**`not be null` | `item number, option id, option value id must not be null` |
| 7 | `BundleItemHelper.java:279` | `values' number`**`  `**`must greater...` | `values' count must be ≥ min choice` |
| 8 | `BundleItemHelper.java:283` | `values' number`**`  `**`must greater...` | `values' count must be ≤ max choice` |
| 9 | `RestaurantBrandBuilder.java:107` | `can not find brand`**`  `**`id`**`  `**`=` | `cannot find brand, id = ` |
| 10 | `CustomerPromotionService.java:18-19` | `promotion_id = ?`**`  `**`ORDER BY...` | `promotion_id = ? ORDER BY...` |

---

## 4️⃣ Files Affected

| File | Count | Issues |
|------|-------|--------|
| `wonder-cart-service/.../CartItemValidator.java` (popcart) | 3 | "not find" + double spaces + "can not more than" |
| `wonder-cart-service/.../WebCartItemValidator.java` | 3 | same issues (duplicate code) |
| `wonder-cart-service/.../CartItemValidator.java` (wondercart) | 3 | same issues (3rd copy) |
| `restaurant-service-v2/.../BOBrandBundleItemService.java` | 2 | "anther" + "is used  by" |
| `restaurant-service-v2/.../BOBrandMenuItemService.java` | 1 | "anther" |
| `restaurant-service-v2/.../BundleItemHelper.java` | 2 | double space + broken grammar |
| `restaurant-service-v2/.../BOItemPriceWebServiceImpl.java` | 2 | double spaces ×3 each |
| `restaurant-service-v2/.../ErrorCodes.java` | 2 | DUPLICATED_NAME + CAN_NOT_CLOSE |
| `order-service/.../CancelOrderValidator.java` | 3 | "can not" grammar |
| `wonder-setting-service/.../BOHDRFeeConfigurationService.java` | 3 | "can not delete" |
| `marketing-service/.../BOChallengeService.java` | 5 | "can not" + broken grammar |
| + *12 more files with 1–2 issues each* | 14 | minor |

---

## 📌 Summary

38 findings across **~24 files**. No findings affect runtime behavior — all are cosmetic/readability. The `DUPLICATED_NAME` error code requires a coordinated change (backend + frontend). The 3 duplicate CartItemValidator files have identical issues — fixing once in all 3 is cleanest.

> dm-seek typo audit · wonder-consumer-project · 2026-06-14
