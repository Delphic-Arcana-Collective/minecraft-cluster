# Spec 01 — 镜像与部署方式

状态：草案。本篇只决定“用哪份镜像、它能怎么部署”。集群拓扑、存储、入口、以及要不要自建控制面，留到下一篇。

核对日期：2026-10-17。来源是上游仓库当前 `master` 文档，不是某一次固定 release。

## 结论

游戏进程用 [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server)。不自己做 Minecraft 服务端镜像。

镜像 tag 选的是 **Java 版本**，不是 Paper / Forge / Fabric。后端用环境变量 `TYPE`，游戏版本用 `VERSION`。同一份镜像可以跑这些后端。

官方 Kubernetes 支持是“示例清单 + 一个单实例 Helm Chart”，不是多实例控制器。Chart 每次安装只起 **一个** Minecraft Pod。多世界、用 API 随时加减实例，官方 Chart 和 Compose 都做不到。路由可以用 [itzg/mc-router](https://github.com/itzg/mc-router) 的 REST API 注册主机名，但它只改路由，不创建服务器。动态机群可以用 [Shulker](https://github.com/jeremylvln/Shulker)（底层仍是这份镜像，调度引擎是 Agones），不过它的服务器按设计是临时的，不带持久世界。

因此：镜像沿用 itzg；若目标是“集群里多个可持久化的实例，并能通过 API 添加”，控制面自己写。Shulker 只在要做小游戏网络、世界可以丢的时候再考虑。

## 镜像

| 项 | 值 |
| --- | --- |
| 镜像 | `itzg/minecraft-server` |
| 文档 | <https://docker-minecraft-server.readthedocs.io> |
| 仓库 | <https://github.com/itzg/docker-minecraft-server> |
| 数据目录 | 容器内 `/data`，世界、模组、插件都在这里 |
| 游戏端口 | TCP `25565` |
| 健康检查 | 镜像自带 `mc-monitor status` |

`latest` 和 `stable` 当前都是 Java 25（Ubuntu + Hotspot）。`latest` 会跟着 Mojang 最新版所需的 Java 一起变，集群里应固定 tag。

常用 tag（2026-10-17 文档）：

| Tag | Java | 系统 | 架构 | 用途 |
| --- | --- | --- | --- | --- |
| `java25` / `latest` / `stable` | 25 | Ubuntu | amd64, arm64, riscv64 | 当前默认 |
| `java25-alpine` | 25 | Alpine | amd64, arm64 | 更小的根文件系统 |
| `java21` | 21 | Ubuntu | amd64, arm64 | 1.20.5+ 原版，以及仍要求 Java 21 的模组 |
| `java17` | 17 | Ubuntu | amd64, arm64, armv7 | 1.18–1.20.4，以及部分 1.21 模组 |
| `java8` | 8 | Ubuntu | amd64, arm64, armv7 | Forge < 1.18 必须用这个 |

可锁定某次镜像构建：`itzg/minecraft-server:<release>-java21`，例如 `2024.4.0-java17`。也有 `stable-java21` 这类“最近一次正式发布”的浮动 tag。

GraalVM tag（`java21-graalvm`、`java25-graalvm`）基于 Oracle Linux。Forge 安装器在这些镜像上会因 zlib-ng 失败，安装和升级 Forge 时不用它们。

Java 与原版大致对应（模组可以更严）：

| 游戏版本 | 需要的 Java |
| --- | --- |
| 1.21+ | 21。当前 `latest` 已是 25，新版原版按镜像文档走 `java25` |
| 1.18 – 1.20.4 | 17 |
| 1.17 | 16 |
| ≤ 1.16.5 | 8 或 11。Paper 1.16.5 文档建议 Java 16 |

Forge < 1.18 必须 `java8`。部分一直到 1.21 的模组仍只能在 Java 17 上跑。选错 tag 的典型现象是 `UnsupportedClassVersionError`（class file 65.0 表示要 Java 21）或 Mixin 的 `ClassMetadataNotFoundException`（应退回 `java17`）。

## 后端

`TYPE` 在启动时决定下载并运行哪一种服务端。下面是本集群关心的四个，以及同镜像里相邻的选项。

| `TYPE` | 说明 | 版本怎么定 |
| --- | --- | --- |
| `VANILLA` | 默认。Mojang 原版 | `VERSION` |
| `PAPER` | PaperMC。插件服首选 | `VERSION` + 可选 `PAPER_BUILD`。实验构建设 `PAPER_CHANNEL=experimental` |
| `FORGE` | Forge。默认取该 MC 版本的 recommended | `VERSION` + 可选 `FORGE_VERSION`（具体号或 `latest`） |
| `FABRIC` | Fabric loader，走 meta.fabricmc.net | `VERSION` + 可选 `FABRIC_LOADER_VERSION`、`FABRIC_LAUNCHER_VERSION` |
| `SPIGOT` | Spigot / Bukkit | `VERSION`。上游已不推荐自动化下载，文档建议改用 Paper |
| `NEOFORGE` | Forge 1.20.1+ 的后继 | `VERSION` + `NEOFORGE_VERSION` |
| `FOLIA` / `PURPUR` / `LEAF` | Paper 系分支 | 与 Paper 类似，各有自己的 build 变量 |
| `QUILT` | 另一个 Fabric 系 loader | `VERSION` |
| `CUSTOM` | 自带 jar | `CUSTOM_SERVER` 或 `CUSTOM_JAR_EXEC` |

Paper、Forge、Fabric、Spigot 都支持，而且不是四个镜像，是同一个镜像加不同 `TYPE`。

Spigot 有两个实际限制：

- GetBukkit 不再稳定支持自动下载。itzg 文档明确建议插件服用 Paper。
- 版本字符串经常不是 `1.8` 这种短号，而要写成下载站上的完整名，例如 `1.8-R0.1-SNAPSHOT-latest`。也可以 `BUILD_FROM_SOURCE=true` 自己编译，或用 `SPIGOT_DOWNLOAD_URL` 指向自托管 jar。

Forge 还可以 `FORGE_INSTALLER` / `FORGE_INSTALLER_URL` 指向已有安装器，这时不必再设 `VERSION`。

## 游戏版本

`VERSION` 大小写敏感。原版取值：

- `LATEST`：最新正式版，默认。重启容器会在启动时检查并升级。
- `SNAPSHOT`：最新快照，同样靠重启升级。
- 具体版本：`1.21.4`、`1.7.9`、`25w35a`、`1.21.11-rc1`，以及新编号 `26.1`、`26.1-pre-1`。
- 部分远古版本（如 `b1.7.3`）只有对应服务端文件存在时才能用。

这是原版的能力上限。某个 `TYPE` 实际能跑的版本，取决于那个项目自己发布了什么：

- Paper 只提供它构建过的版本。新版本在默认 channel 没有构建时，需要 `PAPER_CHANNEL=experimental`，否则会报 `No build found`。
- Fabric 的 loader 必须在 Fabric meta 里有该 `VERSION`。
- Forge / NeoForge 必须有对应 Minecraft 版本的 installer。
- Spigot 经常比客户端自动更新慢一拍，短版本号还可能对不上下载名。

所以集群里每个实例要同时钉住三件事：镜像 tag（Java）、`TYPE`、`VERSION`（以及 loader/build 号）。不要依赖 `latest` 镜像配合 `VERSION=LATEST`。

## Kubernetes 上官方给了什么

itzg 自己维护的部署材料有三层，引擎都不是“一个 API 管理多台服务器”。

### 1. 仓库里的清单

路径：`itzg/docker-minecraft-server` 的 `examples/k8s/` 和 `kustomize/`。

- `examples/k8s/vanilla-deployment.yml`：一个 Deployment，`emptyDir` 挂到 `/data`，NodePort `30000`。数据随 Pod 删除。
- `examples/k8s/using-statefulset.yml`：`replicas: 1` 的 StatefulSet，`volumeClaimTemplates` 申请 1Gi，Service 为 NodePort。
- `kustomize/base`：用 ConfigMap 注入 `EULA`、`TYPE`，并用 annotation 把 Service 交给 mc-router。

探针是 exec：`mc-monitor status --host localhost --port 25565`。

### 2. Helm Chart

仓库：[itzg/minecraft-server-charts](https://github.com/itzg/minecraft-server-charts)。安装：

```bash
helm repo add itzg https://itzg.github.io/minecraft-server-charts/
helm install minecraft --set minecraftServer.eula=true itzg/minecraft
```

Chart 名 `minecraft`。Artifact Hub 上可见的版本到 5.2.0。它渲染的是 **一个 Deployment**，外加游戏 Service、RCON Service、数据 PVC。`values.yaml` 把字段映射成镜像的环境变量；Paper 的实验 channel 这类冷门变量走 `extraEnv`。

README 的原话是：this chart creates a single Minecraft Pod。多开的办法是多次 `helm install` 不同 release，没有“添加实例”的 API。同仓库还有 `mc-router`、`minecraft-proxy`、`minecraft-bedrock`、`rcon-web-admin`，彼此独立。

### 3. 文档点名的第三方

- [Shulker](https://github.com/jeremylvln/Shulker)：Kubernetes operator。CRD 是 `MinecraftCluster`、`ProxyFleet`、`MinecraftServerFleet`。游戏 Pod 交给 Agones 调度，进程镜像仍是 itzg。服务器被定义为临时的，不提供持久化存储；适合大厅 / 小游戏，不适合要留档的生存服。依赖 Kubernetes ≥ 1.27、Agones，以及默认为 LoadBalancer 的代理 Service。
- [mcsh/server-deployment](https://github.com/mcserverhosting-net/charts)：另一套 Helm，不是 itzg 的多实例引擎。

Compose 是镜像的一等公民（`environment: TYPE / VERSION`），适合本机试一个服。它不是 Kubernetes 的控制面，也不能在集群里按 API 增减实例。

## 多实例与 API

| 方式 | 能否多实例 | 能否用 API 添加 | 世界是否持久 | 适合什么 |
| --- | --- | --- | --- | --- |
| Helm `itzg/minecraft` | 一次安装一个 Pod。多开 = 多个 release | 否 | 可以，PVC 挂 `/data` | 固定的几台长期服 |
| 手写 StatefulSet | 每个世界一个 `replicas: 1` 的 StatefulSet | 否，除非再写控制器 | 可以，`volumeClaimTemplates` | 我们自己的清单基线 |
| mc-router | 不创建服，只转发 | 有。`POST /routes` 注册主机名到 `host:25565`；`DELETE /routes/{serverAddress}` 删除；也有 default route | 不涉及 | 一个公网端口按服务器名分流 |
| mc-router + K8s 发现 | 监听带 annotation 的 Service | annotation `mc-router.itzg.me/externalServerName`，可逗号分隔多个主机名 | 取决于后面的 Pod | 新服创建后自动挂上路由 |
| mc-router 自动伸缩 | 只在 0 和 1 之间伸缩已有 StatefulSet | 玩家连上时拉起，空闲时缩回 | 可以，前提是 PVC 还在 | 省一台空闲服的资源，不是水平扩成多副本 |
| Shulker + Agones | `MinecraftServerFleet.spec.replicas` | 对 CRD 做 kubectl / API，另有 Allocator 手动召唤 GameServer | 官方模型是不持久 | 代理网络、可丢弃的短命服 |
| Compose | 一个 compose 文件里写死若干 service | 否 | 可以，bind mount | 开发机 |

mc-router 的集群内用法是容器参数 `--in-kube-cluster`，并给它一个能 watch Service 的 ServiceAccount。游戏 Service 示例：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mc-forge
  annotations:
    mc-router.itzg.me/externalServerName: forge.example.com
```

玩家用主机名连接 mc-router 的 25565，由它转到对应后端。这解决“一个端口后面多台服”，不解决“创建一台服”。

Minecraft 进程本身几乎不能水平扩成同一个世界的多个副本：世界文件是单写者。`replicas > 1` 只在 Shulker 那种“每副本一份临时世界”里有意义。

## 建议

1. 服务端镜像固定为 `itzg/minecraft-server`，按实例选择 `java21` 或 `java25`（旧模组服再用 `java17` / `java8`）。不跟踪 `latest`。
2. 插件服默认 `TYPE=PAPER`。Forge、Fabric 按实例打开。Spigot 保留能力，但默认不作为推荐路径。
3. 每个实例钉住 `VERSION` 和对应的 build / loader 版本。
4. 持久世界用我们自己的 StatefulSet（或等价的一个副本 Deployment + 独立 PVC），探针沿用 `mc-monitor`。官方 Helm 可以当 values 到环境变量的对照，不作为多实例平台。
5. 玩家入口若要在同一个端口后挂接多台服，分流的区分依据只能来自 `Minecraft` 握手包中的 `Server Address`。该能力列入待办，后续由我们自己的网关插件负责转发；`mc-router` 仅作为这一行为的现成参照。
6. 不引入 Shulker / Agones，除非后续明确要临时小游戏舰队。
7. “通过 API 添加一台持久服”需要自己的控制面：收到请求后创建 StatefulSet、PVC、Service。这是下一篇要定的范围。

## 下一篇要定的事

- 控制面做到哪一步：只提交 Git 清单，还是一个创建/删除实例的 API。
- 第一批实例的 `TYPE`、`VERSION`、Java tag。
- 存储类、容量，以及 RCON / 备份是否进第一版。

## 待办

- 日后在自己的网关中实现插件，完成 `Minecraft` 协议转发。在同一个公网 `IP`、同一个端口上，`TCP` 和 `IP` 头部不包含主机名，只有目标 `IP` 与目标端口；要把连接分发到不同后端，插件必须读取握手包里的 `Server Address`，即玩家在客户端服务器地址栏中填写的原文。不同世界使用不同域名，统一解析到同一个网关地址。本篇暂不实现该插件。
