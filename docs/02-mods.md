# Spec 02 — 自定义 mods

状态：草案。本篇只说明用户自己的 mods 列表怎么进 `itzg/minecraft-server`。

核对日期：2026-10-17。来源是上游仓库当前 `master` 的 `docs/mods-and-plugins/`，并非某一次固定 release。

## 落点

- 用户的列表不烘进镜像。镜像里没有这份列表。
- 容器启动时，启动脚本把挂载内容同步进去，或按环境变量下载，写进数据目录 `/data`。
- 目录取决于 `TYPE` 这一类服务端用 `mods` 还是 `plugins`。Forge、Fabric、NeoForge、Quilt 写进 `/data/mods`。Paper、Bukkit、Spigot 写进 `/data/plugins`。混合类型两边都有。模组端若还要插件，设 `USES_PLUGINS`，启动时也会处理插件挂载。
- 只用模组或只用插件时，`MODS` 和 `PLUGINS` 这两个列表都写进那一个目录：只用插件则是 `/data/plugins`，只用模组则是 `/data/mods`。两边都用时，`MODS` 进 `/data/mods`，`PLUGINS` 进 `/data/plugins`。这是 `master` 上 `scripts/start-setupModpack` 的行为，与文档里「按服务端类型写进 `mods` 或 `plugins`」一致。

## 装法

| 方式 | 怎么交 | 启动时写到哪 |
| --- | --- | --- |
| 挂载目录 | 容器内 `/mods` 或 `/plugins`。源目录可用 `COPY_MODS_SRC`、`COPY_PLUGINS_SRC` 改，目的目录可用 `COPY_MODS_DEST`、`COPY_PLUGINS_DEST` 改。多个源目录用逗号或换行分开。 | `/mods` 同步到 `/data/mods`（仅当该 `TYPE` 使用 `mods`）；`/plugins` 同步到 `/data/plugins`（仅当该 `TYPE` 使用 `plugins`）。 |
| Modrinth | 环境变量 `MODRINTH_PROJECTS`，逗号或换行分开的项目列表。项目可以是 slug 或项目 ID，也可以是 `@` 加上容器内清单文件路径（清单里一行一个项目，空行和 `#` 开头的行忽略）。 | 按当前 `TYPE` 和 `VERSION` 下载，写入 `/data` 下的 `mods` 或 `plugins` 目录。没写版本时取该服务端对应的最新 release。从列表里拿掉的项会从 `mods` 或 `plugins` 目录删掉。 |
| CurseForge | 环境变量 `CURSEFORGE_FILES`，逗号或空格分开的项目或文件引用。可以是项目页 URL、文件页 URL、项目 slug、项目 ID，或 `@` 加上容器内清单文件路径。Java 17 及更新的镜像自带 CurseForge API key；`java8` 镜像没有，要自己设 `CF_API_KEY`。 | 没有指定文件时，按 `VERSION` 和 `TYPE` 选最新适用文件写进目标目录。从声明里拿掉的引用会被清掉。 |
| 通用 URL 列表 | `MODS` 或 `PLUGINS`：逗号或换行分开，每项是 jar 的 URL、容器内 jar 路径，或放着 jar 的容器内目录。`MODS_FILE` 或 `PLUGINS_FILE`：容器路径或 URL，指向一个文本文件，一行一个 URL，空行和 `#` 开头的行忽略。 | 下载或复制到 `/data/mods` 或 `/data/plugins`。从列表里拿掉的项会从目标目录删掉。 |

这些都是启动时处理，不在构建镜像时写进层里。

来源：

- <https://github.com/itzg/docker-minecraft-server/blob/master/docs/mods-and-plugins/index.md>
- <https://github.com/itzg/docker-minecraft-server/blob/master/docs/mods-and-plugins/modrinth.md>
- <https://github.com/itzg/docker-minecraft-server/blob/master/docs/mods-and-plugins/curseforge-files.md>

## 钉住文件或版本

只写项目名、不写文件或版本，启动时会按当时的 `TYPE` 和 `VERSION` 取最新适用文件，列表不可重复。要可重复，必须指到具体文件或版本。

| 列表 | 怎么钉 |
| --- | --- |
| 挂载目录 | 放进去的就是那一份 jar，文件本身就是钉。 |
| `MODRINTH_PROJECTS` | 写成「项目:版本」。版本可以是 version ID，例如 `fabric-api:bQZpGIz0`；也可以是版本号，例如 `fabric-api:0.119.2+1.21.4`。version ID 会跳过 Minecraft 与 loader 的兼容检查。只写 `release`、`beta`、`alpha` 仍然是该通道的最新一个，起不到钉死某一个文件的作用。 |
| `CURSEFORGE_FILES` | 文件页 URL，或 `slug:文件 ID`（例如 `jei:4593548`），或 `slug@文件名片段`（例如 `jei@10.2.1.1005`）。只写项目页或 slug 会选最新适用文件。 |
| `MODS`、`PLUGINS`、`MODS_FILE`、`PLUGINS_FILE` | URL 或容器路径要指到那一个 jar。路径里带 `latest` 的地址起不到钉死作用。 |

## tag、VERSION、TYPE

| 项 | 管什么 | 不管什么 |
| --- | --- | --- |
| 镜像 tag | 选 Java 运行时，例如 `java25`、`java21`、`java17`、`java8`。 | 不选游戏版本，也不选 Paper、Forge、Fabric。 |
| `VERSION` | Minecraft 游戏版本，例如 `1.21.4`，或 `LATEST`、`SNAPSHOT`（大小写敏感）。 | 不选 Java 运行时，也不选服务端类型。 |
| `TYPE` | 服务端类型，即 mod loader 或插件端，例如 `FORGE`、`FABRIC`、`NEOFORGE`、`PAPER`。决定启动时下载哪一种服务端，也决定 mods 列表写进 `/data/mods` 还是 `/data/plugins`。 | 不选 Java 运行时，也不选 Minecraft 游戏版本。 |

三者要一起钉住。Modrinth 和 CurseForge 在没有指定文件时，用 `TYPE` 和 `VERSION` 选文件。

同一份镜像靠 `TYPE` 切换后端，不是靠 tag。

<https://github.com/itzg/docker-minecraft-server/blob/master/docs/mods-and-plugins/index.md>
