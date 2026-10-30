# 抽奖发放会员抵扣券实施方案

日期：2026-10-30。状态：已实现，PGlite 单元测试通过；真实 PostgreSQL 并发脚本和线上流程尚未验证。

## 目标与已定规则

在一个独立网页上举办抽奖活动，奖品是购买永久会员时使用的抵扣券。已确定的规则：

- 活动从服务端上线、开关打开时开始，到 2026-11-11 当天结束（北京时间 11 月 12 日 0 点停止抽奖）。
- 2026-11-11 0 点（北京时间）之前注册的账号都能参加，活动期间新注册的账号也算。
- 每个账号在本次活动中只能抽一次，每次都中奖（最低一档不限量）。
- 券只能用于购买「终身会员」和「终身超级会员」，同一张券在两档的抵扣额不同；可以和首发半价同时享受。
- 券永久有效，一张券只能用一次。
- 活动期间开通终身超级会员（含从终身会员升级）且不使用抵扣券的账号，云空间从 1GB 提升到 5GB。没抽过奖的人买超级会员也算。
  - 活动开始前已经是终身超级会员的账号不补（只在服务端执行，活动页上不写这句）。
  - 5GB 永久保留，只要超级会员有效。
  - 每月下载额度保持 1GB。
- 抽奖页是独立网页，用宝塔面板部署在自己的服务器上；App 端本次不改。
- 网页不接华为登录，用户在 App 里把网页给的验证码加进昵称来证明账号归属，不需要在华为后台登记。

由于 App 不改，券只在服务端为会员购买报价时自动抵扣，App 现有确认框显示的就是用券后的扣点数。主题和听书包兑换时，服务端要核对客户端传来的 `expectedPricePoints`，不能悄悄少扣，所以这两类不接券。

## 奖品档位

充值点按 1 元 = 10 点换算。首发半价期间终身会员 645 点（64.5 元），终身超级会员 1245 点（124.5 元）。

| 档位 | 终身会员抵扣 | 终身超级会员抵扣 | 权重（概率） | 库存 |
|---|---|---|---|---|
| 特等奖 | 30 元（300 点） | 60 元（600 点） | 1（1%） | 20 张 |
| 一等奖 | 20 元（200 点） | 40 元（400 点） | 5（5%） | 100 张 |
| 二等奖 | 10 元（100 点） | 20 元（200 点） | 20（20%） | 不限 |
| 三等奖 | 6 元（60 点） | 12 元（120 点） | 34（34%） | 不限 |
| 幸运奖 | 3 元（30 点） | 6 元（60 点） | 40（40%） | 不限，兜底 |

- 二等奖就是你举的例子，五个人里大约有一个能抽到。特等奖和一等奖限量，抽完后再抽中这两档就改发幸运奖。
- 每档的超级会员抵扣都是终身会员的 2 倍，与两档价格比例（1245 : 645 ≈ 1.9）接近，所以两档的折扣力度差不多。
- 半价叠加券后的到手价：

  | 档位 | 终身会员 | 终身超级会员 |
  |---|---|---|
  | 特等奖 | 34.5 元 | 64.5 元 |
  | 一等奖 | 44.5 元 | 84.5 元 |
  | 二等奖 | 54.5 元 | 104.5 元 |
  | 三等奖 | 58.5 元 | 112.5 元 |
  | 幸运奖 | 61.5 元 | 118.5 元 |

- 平均每张券被用掉时，终身会员约少收 6.5 元，终身超级会员约少收 13 元。没人买会员就不产生成本。特等奖和一等奖的总成本有上限：两档全部发出、全部用在超级会员上，最多抵扣 20 × 60 + 100 × 40 = 5200 元。
- 抵扣上限：一张券最多抵扣本次应付点数的一半，并且抵扣后至少还要扣 1 点。这条主要用于升级：已有半价终身会员的人升级超级会员，只需付 1245 − 645 = 600 点；没有上限的话，特等奖 600 点几乎能全额抵掉。按半价全价购买时，各档都不会碰到这个上限。

券的展示名称不用“30 元券”这类总额，避免用户误以为一张券能抵 30 元；网页和规则统一写成“终身会员立减 10 元 / 终身超级会员立减 20 元”。

## 整体流程

1. 用户在浏览器打开抽奖页，点“开始验证”，页面显示 6 位验证码，10 分钟内有效。
2. 用户打开 App →「会员与账号」→ 修改资料，在昵称后面加上验证码并保存。
3. 回到网页点“我已修改”。服务端找到昵称里含这个验证码、并且在验证码生成之后改过资料的账号，把这个浏览器绑定到该账号，再把验证码从昵称里删掉。
4. 页面查询抽奖状态：不符合资格、可以抽、已抽过（显示结果）。
5. 点击抽奖后，服务端在一个事务里完成“记录抽奖、扣奖品库存、发券”，页面再播放转盘动画停到结果。
6. 用户回到 App，在「会员与账号」页购买终身或终身超级会员。报价时服务端自动选一张可用券；确认框里“本次扣除”就是券后的点数，确认后扣点并把券标成已用。

## 部署结构（宝塔面板）

抽奖页是静态文件，放在宝塔建的站点里；接口仍由现有 Node 服务提供。宝塔站点的 Nginx 把 `/lottery/api/` 反向代理到 Node 服务，浏览器看到的是同一个域名，所以不需要处理跨域，Cookie 也是同站的。

```nginx
location /lottery/api/ {
    proxy_pass http://127.0.0.1:<Node 端口>;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

- 如果 Node 服务不在这台服务器上，`proxy_pass` 改成 `https://qingye.icynol.com`，并加 `proxy_ssl_server_name on;`。
- 宝塔站点要开 HTTPS（宝塔可以一键申请 Let's Encrypt 证书），域名要有 ICP 备案。
- Node 的 `trustedProxies` 要包含 Nginx 的地址，否则限流拿到的都是代理 IP。
- 新增配置 `LOTTERY_PAGE_ORIGIN`（抽奖页的协议加域名），POST 请求的 `Origin` 必须等于它。
- 抽奖页的文件放在仓库 `server/lottery-web/index.html`（单文件，内联 CSS 和 JS），部署时上传到宝塔站点的 `/lottery/` 目录。

## 昵称验证码

### 为什么可行

- App 的「会员与账号」页本来就能改昵称，保存走 `/v1/me/profile`，存进 `app_users.display_name`，允许 1 至 30 个字符，同时更新 `updated_at`。这个功能很早就有，各版本 App 都能用。
- 只有登录了 App 的本人能改自己的昵称，所以“昵称里出现了网页给的验证码”就能证明网页对面是这个账号的主人。
- 验证码随机生成、10 分钟失效，并且只认生成它的那个浏览器（HttpOnly Cookie 里的随机令牌）。别人看到你昵称里的验证码，在他的浏览器里也用不了。

### 接口

- `POST /lottery/api/verify/start`：生成验证码和随机令牌，令牌哈希与验证码存入 `lottery_web_verifications`，令牌写入 Cookie `lottery_verify`（`HttpOnly; Secure; SameSite=Lax; Path=/lottery/api; Max-Age=600`）。返回验证码和过期时间。同一 IP 每分钟最多 5 次。
  - 验证码 6 位，字符集去掉易混淆的 `0 O 1 I L`，共 31 个字符，约 8.9 亿种组合。
  - 生成时检查没有未过期的同码记录，有就重新生成。
- `POST /lottery/api/verify/check`：凭 Cookie 找到未过期、未使用的验证记录，每条记录最多查 60 次。查询：

  ```sql
  SELECT id, display_name FROM app_users
  WHERE updated_at >= $created_at
    AND position($code IN upper(display_name)) > 0
  LIMIT 2;
  ```

  - 恰好一个账号：在同一事务里把验证记录标记为已使用并记下 `user_id`；把验证码从昵称里删掉，并整理多余空格（删完为空时改成“华为用户”）；签发网页会话；清掉 `lottery_verify` Cookie。
  - 没有：返回“还没检测到验证码，请确认昵称已保存”，页面保持等待状态。
  - 多于一个：作废这条验证，让用户重新开始（正常不会出现）。
- 网页会话：随机令牌，只存哈希，存入 `lottery_web_sessions`，有效期 30 天，只能调用抽奖接口。Cookie `lottery_session` 设置 `HttpOnly; Secure; SameSite=Lax; Path=/lottery/api`。30 天内再来看券的状态不用重新验证。
- `POST /lottery/api/logout`：删除网页会话。

### 副作用

- 改过昵称后 `profile_customized` 会变成 `TRUE`，以后重新登录 App 不再用华为账号的昵称覆盖。原来没改过昵称的用户，验证完以后昵称不再跟着华为昵称变。这是 App 现有行为，验证码删除后昵称文字和原来一样，影响很小。
- App 里显示的昵称要等页面刷新账号信息后才会去掉验证码。页面上提示“验证码会自动从昵称里删掉，App 里重新进入「会员与账号」页即可看到”。
- 验证码在昵称里最多停留到用户点“我已修改”为止，期间可能出现在其他展示昵称的地方。验证码本身对别人没用，可以接受。
- 昵称已有 25 个字符以上的用户，加上验证码会超过 30 个字符。页面提示“昵称太长时可以先把昵称整个换成验证码”；这种情况删除验证码后昵称变成“华为用户”，页面再提示用户回 App 改回原昵称。

## 数据表

新增迁移 `server/migrations/026_lottery_coupons.sql`：

```sql
CREATE INDEX IF NOT EXISTS app_users_updated_idx ON app_users(updated_at);

CREATE TABLE lottery_web_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL,
  client_ip TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  user_id UUID REFERENCES app_users(id) ON DELETE CASCADE,  -- 验证成功后填入
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX lottery_web_verifications_code_idx ON lottery_web_verifications(code, expires_at);

CREATE TABLE lottery_web_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE lottery_campaigns (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  -- 只有在这个时间之前注册的账号能抽
  registered_before TIMESTAMPTZ NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT false,
  CHECK (ends_at > starts_at)
);

CREATE TABLE lottery_prizes (
  id TEXT PRIMARY KEY,
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  label TEXT NOT NULL,
  weight INTEGER NOT NULL CHECK (weight > 0),
  stock INTEGER CHECK (stock >= 0),   -- NULL 表示不限量
  issued INTEGER NOT NULL DEFAULT 0,
  -- 各会员档位的抵扣点数，例如 {"LIFETIME": 100, "SUPER_LIFETIME": 200}
  discounts JSONB NOT NULL,
  is_fallback BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL,
  CHECK (stock IS NULL OR issued <= stock)
);

CREATE TABLE membership_coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  prize_id TEXT NOT NULL REFERENCES lottery_prizes(id),
  discounts JSONB NOT NULL,          -- 发券时从奖品复制，奖品以后调整不影响已发的券
  -- 买终身超级会员时：COUPON 用券，CLOUD 不用券改送 5GB 云空间
  super_choice TEXT NOT NULL DEFAULT 'COUPON' CHECK (super_choice IN ('COUPON','CLOUD')),
  expires_at TIMESTAMPTZ,            -- NULL 表示永久有效
  status TEXT NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE','USED','REVOKED')),
  used_order_id UUID,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX membership_coupons_user_idx ON membership_coupons(user_id, status);

CREATE TABLE lottery_draws (
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  prize_id TEXT NOT NULL REFERENCES lottery_prizes(id),
  coupon_id UUID NOT NULL REFERENCES membership_coupons(id),
  client_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, user_id)   -- 每个账号每次活动只能抽一次
);

ALTER TABLE membership_orders
  ADD COLUMN IF NOT EXISTS coupon_id UUID REFERENCES membership_coupons(id),
  ADD COLUMN IF NOT EXISTS coupon_points BIGINT NOT NULL DEFAULT 0;

-- 活动期间不用券开通超级会员送的云空间额度；为空表示本活动不送
ALTER TABLE lottery_campaigns ADD COLUMN IF NOT EXISTS super_no_coupon_quota_bytes BIGINT;

CREATE TABLE cloud_quota_bonuses (
  user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
  quota_bytes BIGINT NOT NULL CHECK (quota_bytes > 0),   -- 总额度，不是增量
  campaign_id TEXT REFERENCES lottery_campaigns(id),
  order_id UUID REFERENCES membership_orders(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

过期的验证记录和网页会话由现有的 `maintenance.ts` 定期清理。

活动和奖品用单独的迁移 `027_double11_lottery.sql` 写入，做法和 `019_membership_launch_schedule.sql` 写首发促销一样：

```sql
INSERT INTO lottery_campaigns(id, title, starts_at, ends_at, registered_before, enabled,
    super_no_coupon_quota_bytes) VALUES
  ('double11-2026', '永久会员抵扣券抽奖',
    TIMESTAMPTZ '2026-10-30 00:00:00+08', TIMESTAMPTZ '2026-11-12 00:00:00+08',
    TIMESTAMPTZ '2026-11-11 00:00:00+08', false, 5368709120)  -- 5GB = 5 × 1024³ 字节
ON CONFLICT (id) DO NOTHING;

INSERT INTO lottery_prizes(id, campaign_id, label, weight, stock, discounts, is_fallback, sort_order) VALUES
  ('double11-2026-grand',  'double11-2026', '特等奖', 1,  20,   '{"LIFETIME":300,"SUPER_LIFETIME":600}', false, 1),
  ('double11-2026-first',  'double11-2026', '一等奖', 5,  100,  '{"LIFETIME":200,"SUPER_LIFETIME":400}', false, 2),
  ('double11-2026-second', 'double11-2026', '二等奖', 20, NULL, '{"LIFETIME":100,"SUPER_LIFETIME":200}', false, 3),
  ('double11-2026-third',  'double11-2026', '三等奖', 34, NULL, '{"LIFETIME":60,"SUPER_LIFETIME":120}',  false, 4),
  ('double11-2026-lucky',  'double11-2026', '幸运奖', 40, NULL, '{"LIFETIME":30,"SUPER_LIFETIME":60}',   true,  5)
ON CONFLICT (id) DO NOTHING;
```

“即刻开始”由 `enabled` 控制：迁移写入时关闭，线上验证通过后打开就算开始，`starts_at` 只是下限。

活动期间新注册的账号也能抽，开小号刷券的收益很低：券绑定账号、不能转让，只能用来抵扣这个账号自己用充值点购买会员。小号要用上券，得先往小号里充值。

## 抽奖接口

新文件 `server/src/lotteryService.ts`、`server/src/lotteryRoutes.ts`，挂在 `/lottery/api/` 下，验证码接口也放在这里：

- `GET /lottery/api/state`：活动时间、奖品列表和公示概率；已绑定账号时再返回昵称、资格、已抽结果、该账号的券、使用状态、`super_choice`，以及是否已拿到 5GB 云空间。
- `POST /lottery/api/draw`：抽奖。
- `POST /lottery/api/coupon/super-choice`：`{ choice: 'COUPON' | 'CLOUD' }`，只能改自己未使用的券。和报价、购买一样先取 `membership:<用户>` 咨询锁，保证不会出现“报价时用了券、购买时选择已经变了”的情况：购买时如果券的选择已变成 `CLOUD`，按“会员状态已变化”处理。

抽奖事务：

1. `pg_advisory_xact_lock(hashtextextended('lottery:<活动>:<用户>', 0))`。
2. 查 `lottery_draws`，已有记录就直接返回原结果（`duplicate: true`）。连点、重试、刷新都看到同一个奖品。
3. 校验活动 `enabled` 且当前时间在活动时间内，`app_users.created_at < registered_before`，账号没有退款欠款（`account_debts`）。
4. 用 `crypto.randomInt` 按 `weight` 抽出一个奖品。
5. `UPDATE lottery_prizes SET issued = issued + 1 WHERE id = $1 AND (stock IS NULL OR issued < stock) RETURNING *`。更新到 0 行说明库存已空，改发兜底的幸运奖。这样不需要锁住整张奖品表，也不会超发。
6. 写 `membership_coupons`（`expires_at` 为空），再写 `lottery_draws`。主键冲突说明有并发请求抢先写入，回滚后返回已有结果。

接口限流：每个 IP 每分钟 20 次，复用 `@fastify/rate-limit`。

限量奖品抽完时，这部分概率会转移到幸运奖，所以公示时要写明“特等奖、一等奖数量有限，发完即止”。

## 会员报价自动用券

改 `membershipPolicy.ts` 和 `membershipService.ts`：

- `MembershipPurchasePlan` 增加 `couponId: string | null` 和 `couponPoints: number`。旧报价里没有这两个字段，按没有券处理，不需要提升 `MEMBERSHIP_POLICY_VERSION`。
- `quoteMembership` 在算出促销价和升级抵扣之后选券：在这个账号 `AVAILABLE`、未过期（`expires_at` 为空或晚于现在）、`discounts` 里有本次档位的券中，对每张券计算实际抵扣 `min(discounts[sku], floor(应付 / 2), 应付 - 1)`，选实际抵扣最大的一张，相同时选最早发的。`payablePoints` 减去这个数。月度和年度会员的 `discounts` 里没有对应档位，不会用到券。买终身超级会员时跳过 `super_choice = 'CLOUD'` 的券。
- 有过期时间的券，报价有效期还要与券的过期时间取最小值。本次的券永久有效，不受影响。
- `purchaseMembership`：如果计划里有 `couponId`，`SELECT ... FOR UPDATE` 锁住这张券，确认仍然是 `AVAILABLE` 且未过期，否则抛 `MEMBERSHIP_OFFER_CHANGED`（“会员状态已变化，请重新查看价格”），App 现有的错误提示能处理。写订单时带上 `coupon_id`、`coupon_points`，同一事务里把券改成 `USED` 并记录 `used_order_id`、`used_at`。
- 终身档的 `permanentCreditPoints` 现在等于价格（含促销），要改成减去 `couponPoints`。这样以后从终身会员升级超级会员时，按实际花费抵扣，与促销价的处理一致。`purchaseMembership` 里新周期会重新调用 `planMembershipPurchase`，也要把券一起传进去。
- 不动 `/v1/membership/catalog`，商品卡片仍显示首发半价，券后价只出现在确认框。

## 不用券开通超级会员送 5GB 云空间

> 2026-10-30 起停用：抽奖页不再展示 5GB 相关内容，也不提供“用券 / 不用券”的选择；线上执行 `UPDATE lottery_campaigns SET super_no_coupon_quota_bytes = NULL WHERE id = 'double11-2026';` 后服务端也不再赠送。代码保留，以后的活动给这个字段设值即可重新启用；已写入 `cloud_quota_bonuses` 的赠送不受影响。

### 要解决的问题：用户怎么选“不用券”

报价时券是自动使用的，App 没法让用户选择不用。每次抽奖都中奖，所以抽过奖的人买超级会员时一定会自动用券，也就永远拿不到 5GB。因此“用券还是要 5GB”要在抽奖页上选：

- 券上增加一个选择 `super_choice`：`COUPON`（默认，买超级会员时用券）或 `CLOUD`（买超级会员时不用券，改为送 5GB）。
- 抽到奖后，页面显示两个选项：“立减 X 元”和“不用券，云空间升到 5GB”。购买超级会员前可以随时改。
- 选 `CLOUD` 只影响终身超级会员：报价跳过这张券，券仍可用于终身会员。不过买了超级会员以后就不会再买终身会员，这张券实际上就用不上了。页面上要写明这一点。
- 已经用掉的券不能再改选择。

### 服务端改动

云空间的 1GB 现在是写死的常量，分散在好几处，需要改成按账号读取：

| 位置 | 现在 | 改成 |
|---|---|---|
| `cloudFileService.ts` 的 `summary()` 返回的 `quotaBytes` | `CLOUD_QUOTA_BYTES` | 按账号的额度 |
| `cloudFileService.ts` 上传前的空间检查（`used + bytes > CLOUD_QUOTA_BYTES`） | 1GB | 按账号的额度 |
| `sync.ts` 书源与云文件共用空间的 `cloudRemaining` | `1024 ** 3 - …` | 按账号的额度 |
| `sync.ts` 空间满时的提示“书源与云文件共用的 1GB 空间已满” | 写死 1GB | 改成“书源与云文件共用的云空间已满” |
| `membershipSnapshot` 返回的 `benefits.cloudStorageBytes` | 超级会员 1GB | 按账号的额度 |

做法：

- 新表 `cloud_quota_bonuses` 记录额外额度，一个账号一行。新增函数 `cloudQuotaBytes(db, userId)`：有记录就返回记录里的额度，没有就返回 1GB。上面几处都改为调用它。
- `purchaseMembership` 在同一事务里判断：本单是终身超级会员、没有用券（`couponId` 为空），并且购买时间在活动时间内、活动开关打开。满足就写入 `cloud_quota_bonuses`（5GB，记下活动 id 和订单 id）。判断以付款时间为准，不以报价时间为准。
- 送的额度跟着超级会员资格走：会员因退款欠款被暂停时，云空间本来就整体不能用，不需要额外处理。
- 不变的部分：
  - 单个文件最大 1GB（App 端也限制了单个文件 1GB）。
  - 每月下载额度 1GB。
- 对象存储成本：每个拿到 5GB 的账号最多多占 4GB。

### App 现状下的显示

App 不做本地空间检查，上传是否超额完全由服务端判断，所以服务端改完就能真正用到 5GB。显示方面：

- 「我的云空间」页的总量和进度条读服务端返回的 `quotaBytes`，会显示 5GB。
- 有几处写死了“1GB”，改不了：
  - 云空间页的说明文字。
  - 会员权益页“已用 X / 1GB”。
  - 购买说明和权益对比表。

  活动页上要写“App 内部分说明仍显示 1GB，以「我的云空间」页显示的总量为准”。

### 活动页文案

> 活动期间（至 11 月 11 日）开通终身超级会员且不使用抵扣券，云空间从 1GB 提升到 5GB，永久有效。抽到券的用户可以在本页选择“购买超级会员时立减”或“不用券，云空间升到 5GB”。

## 用券时 App 确认框的显示

确认框文案来自 [AccountCenter.ets](../entry/src/main/ets/pages/AccountCenter.ets) 的 `buyMembership`。例如持二等奖券购买终身会员：

```
终身会员  645 点
本次扣除 545 充值点
当前充值点 700
```

没有单独的“优惠券”一行，原价和扣除之间的差额没有说明。网页上要写清楚“在 App 购买终身会员或终身超级会员时自动抵扣，确认框里的扣点数就是券后价格”。充值点不足的提示也是按券后价格计算的。订单列表会显示 `listPoints`、`creditPoints`、`pointsSpent`，三者对不上的差额就是券。

## 抽奖网页

单个静态 HTML，内联 CSS 和 JS，不依赖外部脚本，放在 `server/lottery-web/index.html`。

- 状态：
  - 未验证：显示“开始验证”。
  - 等待验证：显示验证码（大字号，可一键复制）、剩余时间、三步说明，以及“我已修改”按钮；同时每 5 秒自动查一次。
  - 不符合资格：注明“仅限 2026 年 11 月 11 日前注册的账号”。
  - 可以抽。
  - 已抽：显示档位、两档抵扣额、永久有效、是否已用。
  - 活动已结束 / 活动未开放。
- 已绑定时显示当前账号昵称，并提供“不是我的账号，重新验证”。
- 转盘只播放动画，结果以接口返回为准。动画结束前就算网络失败，刷新后也能看到结果。
- 页面写明活动规则：
  - 活动时间、参与条件、每人一次。
  - 奖品档位、抵扣额和中奖概率，特等奖、一等奖数量有限、发完即止。
  - 券只能用于终身会员和终身超级会员，可与首发半价同享，最多抵扣应付的一半。
  - 券永久有效，一张券只能用一次，不可转让、不可兑现。
  - 使用方法：在 App「会员与账号」页购买时自动抵扣。
  - App 内部分说明仍显示 1GB，以「我的云空间」页显示的总量为准。

## 合规

- 页面公示规则和概率。奖品是虚拟点数抵扣，金额很小，不涉及有奖销售的最高奖金额限制，但规则要完整写明。
- 活动链接如果在应用市场或 App 内推广，要先核对华为应用市场当前对抽奖活动的审核要求。

## 测试

- 单元测试（`node --test`）：
  - 选券：档位不符（月度、年度）不用券、取实际抵扣最大的一张、抵扣上限为应付一半、应付至少保留 1 点。
  - 永久有效的券（`expires_at` 为空）可用，已用和作废的券不可用。
  - 用券与首发半价、升级抵扣叠加。
  - 终身档 `permanentCreditPoints` 按实际花费计算。
  - 旧报价没有券字段时照常购买。
  - 从昵称中删除验证码：验证码在末尾、中间、整个昵称，大小写不同，删完为空。
  - 5GB 云空间：
    - 活动期间不用券买超级会员（新开和升级）会送；用了券、活动外、买其他档位都不送。
    - 选了 `CLOUD` 的券在超级会员报价中被跳过，在终身会员报价中仍可用。
    - 报价后改选择，购买报 `MEMBERSHIP_OFFER_CHANGED`。
    - 有赠送记录的账号，云空间概要、上传检查、书源同步的剩余空间都按 5GB 计算；没有记录的仍按 1GB。
- 验证码测试：
  - 过期、已使用、没有 Cookie、换浏览器都不能绑定。
  - 验证码生成前改的昵称不算。
  - 超过查询次数后作废。
- 抽奖服务测试：资格判断、重复抽返回原结果、限量奖品抽完后发幸运奖。
- `server/scripts/lottery-pg-concurrency.mjs`，在真实 PostgreSQL 上跑：
  - 同一账号并发 50 次抽奖，只产生 1 条抽奖记录和 1 张券。
  - 库存 5 的奖品、200 个账号并发抽，恰好发出 5 张该奖品的券。
  - 同一账号拿两份带同一张券的报价并发购买，只有一单用到券，另一单报 `MEMBERSHIP_OFFER_CHANGED`。
- 用真实 App 走一遍：改昵称、网页验证、确认昵称恢复、抽奖、购买会员时确认框扣点正确。

## 上线步骤

服务端用增量更新包部署：由 `node scripts/lottery-update/package.mjs` 生成 `server/release/qingye-lottery-20261030.zip`，安装和回滚见包内 README；下面第 2、3 步由包内 `update.sh` 完成。

1. 宝塔：
   - 建站点，开 HTTPS。
   - 把 `server/lottery-web/index.html` 上传到站点的 `/lottery/` 目录。
   - 按上面的 Nginx 片段反代 `/lottery/api/`。
2. 服务端：
   - 部署新版本，依次执行迁移 `026_lottery_coupons.sql`、`027_double11_lottery.sql`。
   - 026 会把订单表“实付 + 升级抵扣 = 标价”的检查改为把券也算进去。
   - 环境变量设 `LOTTERY_PAGE_ORIGIN=https://<抽奖页域名>`（不带路径和末尾斜杠）。没设时页面的所有提交都会被拒绝。
   - Nginx 不在本机时，`TRUSTED_PROXIES` 加上它的地址。
   - 活动 id 默认 `double11-2026`，可用 `LOTTERY_CAMPAIGN_ID` 改。
3. 按运行 `membership-pg-concurrency.mjs` 的方式，在服务器上运行 `scripts/lottery-pg-concurrency.mjs`。它只在新建的临时库里测试，不连正式库。
4. 开启活动：`UPDATE lottery_campaigns SET enabled = true WHERE id = 'double11-2026';`
5. 用自己的账号走一遍：
   1. 网页验证并抽奖。
   2. 在 App 报价，确认扣点变少（先不确认购买）。
   3. 在网页切换“不用券 / 用券”，再报价，确认扣点随之变化。

   如果要把自己的测试抽奖清掉重来：

   ```sql
   BEGIN;
   UPDATE lottery_prizes p SET issued = issued - 1 FROM lottery_draws d
     WHERE d.prize_id = p.id AND d.campaign_id = 'double11-2026' AND d.user_id = '<你的用户 id>';
   DELETE FROM lottery_draws WHERE campaign_id = 'double11-2026' AND user_id = '<你的用户 id>' RETURNING coupon_id;
   DELETE FROM membership_coupons WHERE campaign_id = 'double11-2026' AND user_id = '<你的用户 id>' AND status = 'AVAILABLE';
   COMMIT;
   ```

运营查询：

```sql
SELECT p.label, p.stock, p.issued,
  count(c.*) FILTER (WHERE c.status = 'USED') AS used,
  coalesce(sum(o.coupon_points), 0) AS discounted_points
FROM lottery_prizes p
LEFT JOIN membership_coupons c ON c.prize_id = p.id
LEFT JOIN membership_orders o ON o.coupon_id = c.id
WHERE p.campaign_id = 'double11-2026'
GROUP BY p.id ORDER BY p.sort_order;
```

拿到 5GB 的人数：

```sql
SELECT count(*) FROM cloud_quota_bonuses WHERE campaign_id = 'double11-2026';
```

出问题时把活动 `enabled` 设为 `false` 即可停止抽奖，已发的券不受影响；需要作废时把券改成 `REVOKED`。

## 时间安排

活动到 2026-11-11 结束，只有 12 天，晚一天上线就少一天。

- 不再依赖华为后台登记，服务端和抽奖页都可以马上开始写。
- 宝塔站点可以先建好、开好 HTTPS，抽奖页做完后再上传。
- 部署和测试都需要你在线上完成，所以要预留出时间。
