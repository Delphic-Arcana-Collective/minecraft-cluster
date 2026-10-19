# Simple Backups 安装

给当前 Forge 1.20.1 服加个自动备份模组 Simple Backups（作者 MelanX），版本 `SimpleBackups-1.20.1-3.1.18.jar`。

CurseForge 主页：<https://www.curseforge.com/minecraft/mc-mods/simple-backups>
该版本文件页：<https://www.curseforge.com/minecraft/mc-mods/simple-backups/files/7151898>

不用额外脚本，也不用动 Helm chart。装法就是把 jar 丢进服务端 `/data/mods`，重启 Pod 让 Forge 加载。

环境：游戏机 `azusaing@192.168.1.114`，k3s 命名空间 `minecraft`，Pod `forge-1201-0`，镜像 itzg/minecraft-server，数据在 PVC 挂到的 `/data`。

## 装法

1. 本机下载 jar（走代理）：

   ```
   https://mediafilez.forgecdn.net/files/7151/898/SimpleBackups-1.20.1-3.1.18.jar
   ```

2. `scp` 到游戏机，然后在游戏机上 `kubectl cp` 拷进 Pod：

   ```bash
   scp SimpleBackups-1.20.1-3.1.18.jar azusaing@192.168.1.114:~/
   ssh azusaing@192.168.1.114
   kubectl -n minecraft cp SimpleBackups-1.20.1-3.1.18.jar forge-1201-0:/data/mods/
   ```

3. 仍在游戏机上删 Pod，让 StatefulSet 拉起新的，Forge 启动时自动加载 mods：

   ```bash
   kubectl -n minecraft delete pod forge-1201-0
   ```

## 装完后默认配置

首次启动模组会生成默认配置文件：

- 主配置：`/data/config/simplebackups-common.toml`
- 世界侧：`/data/world/serverconfig/simplebackups-server.toml`

默认值大致是：

- `enabled = true`
- `timer = 120`（现实时间每 120 分钟一次）
- `backupType = FULL_BACKUPS`
- `backupsToKeep = 10`
- `maxDiskSize = "25 GB"`
- `outputPath = "simplebackups"`
- `noPlayerBackups = false`（没人在线时不备份）

备份输出目录：`/data/simplebackups`。

## 计时怎么算

`timer = 120` 是墙上时钟，从上次备份时间起算 120 分钟，不是「有人在线累计满 120 分钟」。

没人在线时跳过本次备份，但时钟照样走。之后只要有人上线、且距离上次备份已过间隔，就会立刻补做一次，然后再按 120 分钟重新计时。
