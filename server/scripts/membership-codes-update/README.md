# 会员兑换码与发卡工具 · 服务端增量更新包 · 2026-11-23

安卓版的兑换码新增**会员码**：输入后直接开通月度 / 年度 / 终身 / 终身超级会员，不用先充值点数。
原来的点数码照常可用，两种码用同一个输入框。服务器上新增发卡命令 `qingye-codes`。
**要先装好 `qingye-recharge-20261123`**（本包替换它装上的两个文件）。安卓新包要在本更新装好之后再发布，
否则会员码会被旧服务端当成点数码（到账与会员价等额的充值点）。

- 兑换规则：服务端在同一个事务里按码面值记入充值点、再按应用内购买的规则开通该会员（续费叠加、升级抵扣、
  促销价、自动用券都一样）。实付少于面值时差额留作充值点；涨价后旧码照样能开通该档。
  已有终身权益又兑换低档或同档的码、账号有退款欠款、该档未开售时拒绝，**码不作废**，可以转给别人。
- 迁移 035：`redeem_codes` 增加可空列 `membership_sku`（034 的表级授权已覆盖）。
- 替换 `rechargeRoutes.js`（兑换接口支持会员码）和 `redeem-codes.mjs`（发卡工具），新增 `/usr/local/bin/qingye-codes`。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。不修改环境文件。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-membership-codes.XXXXXX)
unzip -q /root/qingye-membership-codes-20261123.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: membership redeem codes installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 线上两个文件必须正好是充值更新装上的版本（或已经是本版本），否则提示 `BASELINE_MISMATCH` 并退出。
  - 以服务用户、带服务环境在临时副本里加载新的 `rechargeRoutes.js`：和线上会员模块一起能加载、兑换接口已挂上、
    会员价目与发卡工具的面值一致、发卡工具能拒绝错误参数。
  - 在新建的临时数据库里用真实 PostgreSQL 检查：035 能在已有兑换码上执行并可重复执行、拒绝未知档位、服务账号可读写新列；
    用发卡工具在临时库里建批次、查列表、查单个码、作废；8 个账号抢同一个会员码只有一个开通（一笔订单、一加一扣两条流水）；
    作废的码被拒、点数码照常到账；终身会员兑换低档码被拒且码仍可用、换个账号能兑换。跑完即删库删角色。
- 文件替换或健康检查失败时，脚本会恢复原来的两个文件、删掉 `qingye-codes` 并启动服务，数据库保留。
- 装好后检查：服务健康、兑换接口未登录返回 401、`qingye-codes list` 能连上数据库、公网健康检查。

## 发卡

```bash
qingye-codes create --batch afdian-2611-annual --sku ANNUAL --count 20 --expires 2027-12-31   # 会员码
qingye-codes create --batch afdian-2611-p300 --points 300 --count 50                           # 点数码
qingye-codes list                                   # 各批次：种类、总数、已用、可用、作废、过期
qingye-codes status ABCD-EFGH-JKLM-NPQR             # 查一个码：批次、种类、是否用过、谁在何时用的
qingye-codes revoke --code ABCD-EFGH-JKLM-NPQR      # 作废一个未用的码
qingye-codes revoke --batch afdian-2611-p300 --yes  # 作废整批里未用的码
```

- `--sku`：`MONTHLY`（月度）、`ANNUAL`（年度）、`LIFETIME`（终身）、`SUPER_LIFETIME`（终身超级）。
  `--points`：10/60/100/300/500/1000。二者选一。`--expires` 是北京时间当天结束，不写则不过期。
- 明文写在 `/root/qingye-codes/<批次>.txt`（权限 600，每行一个），可直接导入发卡平台的卡密列表；
  导入后删掉这个文件。数据库只存哈希，丢了文件就找不回明文，只能作废整批重发。
- 批次名不能重复；一个批次只放一种码，建议按“渠道-日期-档位”命名，方便对账。
- 加 `--dry-run` 只生成文件、不写库（文件名带 `.dry-run`），用来演练。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-membership-codes-backup.XXXXXX
```

回滚恢复充值更新装上的两个文件，删掉 `qingye-codes`。数据库的新列和已发的码保留。
**注意**：回滚后旧服务端会把还没用的会员码当成点数码（到账与会员价等额的充值点）。如果要长期回滚，
先作废没用的会员码批次：`UPDATE redeem_codes SET revoked_at = now() WHERE membership_sku IS NOT NULL AND redeemed_by IS NULL;`

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`check.mjs` 预检、
`membership-codes-pg-check.mjs` 真实数据库检查、`qingye-codes` 命令、`runtime/` 新文件（`runtime/previous/` 是被替换的旧版本）、
`src/` 源码、`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、`RELEASE.json`、`SHA256SUMS`。
