# msedit MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[Microsoft Edit](https://github.com/microsoft/edit)（`msedit`）的插件实现仓库。

- Hub 索引条目在：[hustyanzu/mos-templates](https://github.com/hustyanzu/mos-templates)
- 本仓库只负责插件实现和 release `.deb`

---

## 它做什么

- 从 Microsoft 官方 GitHub Releases 下载 `msedit` 二进制（`amd64` / `arm64`）
- 安装到 `/boot/optional/plugins/msedit/bin/msedit`
- 复制运行副本到 `/usr/bin/msedit.real`，避免 `/boot` noexec
- 安装 `/usr/bin/msedit` 包装脚本；如果系统没有 `edit`，创建 `edit` 别名
- 自动处理 ICU：
  - 优先使用系统已有的 ICU
  - 缺失时从 Devuan 仓库下载 `libicu*`（excalibur 上是 `libicu76`）
  - 解压到 `/boot/optional/plugins/msedit/lib`，创建 unversioned symlink
  - 包装脚本设置 `LD_LIBRARY_PATH`，供 msedit 的搜索/替换功能使用
- 提供 MOS 插件页面：安装 / 更新 / ICU 状态 / 安装 ICU

ICU 对 msedit 是可选依赖：没有 ICU 时编辑器仍能运行，只是搜索/替换功能受限。
插件会尽量把 ICU 装好，页面会显示 `System` / `Bundled` / `Missing`。

---

## 仓库结构

```text
mos-msedit/
├── functions
├── settings.json
├── msedit-backend                 # /usr/bin/plugins/msedit
├── msedit-wrapper                 # /usr/bin/msedit
├── images/
│   └── msedit.png
├── page/                          # Vue 插件页面
├── build.sh
└── .github/workflows/build-plugin.yml
```

---

## 构建

```bash
./build.sh 0.1.0
```

输出：

```text
build/msedit-0.1.0-1+mos-plugin_all.deb
build/msedit-0.1.0-1+mos-plugin_all.deb.md5
```

---

## 发布与安装

```bash
git tag 0.1.0
git push origin 0.1.0
```

GitHub Actions 构建 `.deb` + `.md5` 并创建 Release。

在 MOS 添加索引仓库：

**Settings → System Configuration → MOS Hub Settings → Add Repository**

```text
https://github.com/hustyanzu/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **msedit**，然后在插件页
点击 **Install**。

也可以手动安装：

```bash
dpkg -i msedit-0.1.0-1+mos-plugin_all.deb
/usr/bin/plugins/msedit install_binary
/usr/bin/plugins/msedit install_icu
```

---

## 使用

```bash
msedit
msedit /mnt/cache/some-file.txt
edit some-file.txt          # 仅当系统没有 edit 时创建别名
```

包装脚本：

```text
LD_LIBRARY_PATH=/boot/optional/plugins/msedit/lib:...
```

插件页会显示 ICU 来源：

- `System`：系统已有 ICU
- `Bundled`：插件目录里有 ICU
- `Missing`：尚未安装，可点 **Install ICU**

---

## ICU 说明

Devuan excalibur 的 ICU runtime 包是 `libicu76`。插件优先走 **MOS 官方的
附加包机制**：

1. 在 `/boot/optional/plugins/msedit/packages/packages` 写入包名（例如 `libicu76`）
2. 把 `.deb` 下载到 `/boot/optional/plugins/msedit/packages/`
3. 立即执行 `dpkg -i packages/*.deb`（如果可用）
4. MOS 启动时 `installplugins-mos` 会再次确保这些包已安装

如果 `dpkg` 不可用或安装失败，插件会回退到把 `libicu*.so.*` 解压到
`/boot/optional/plugins/msedit/lib`，并由包装脚本设置 `LD_LIBRARY_PATH`。
这样即使系统包安装失败，msedit 的搜索/替换仍然可用。

离线环境可以预先放置 `libicu76` 的 `.deb` 并设置：

```bash
MSEDIT_ICU_DEB=/path/to/libicu76_*.deb /usr/bin/plugins/msedit install_icu
```

---

## 持久化

MOS 的 Hub 安装器会把 `.deb` 和 `functions` 放到：

```text
/boot/optional/plugins/msedit/<version>/
```

并在插件根目录写 `template.json`。启动时 `installplugins-mos` 会重新安装该
`.deb`，然后处理 `packages/packages` 里的附加包。

- 二进制：`/boot/optional/plugins/msedit/bin/msedit`
- ICU 包：`/boot/optional/plugins/msedit/packages/`
- ICU 回退库：`/boot/optional/plugins/msedit/lib/`
- 运行时副本：`/usr/bin/msedit.real`（RAM）

如果手动 `dpkg -i`，插件只对当前运行有效；要让它重启后仍然存在，请使用
MOS Hub，或把 `.deb`/`functions` 放到版本目录并补上 `template.json`。

---

## 升级 / 卸载

**升级**：插件页 **Check updates** → **Update**。
后端会下载新的 msedit、校验 sha256、替换持久化二进制和运行副本。

**卸载**：卸载插件会移除 `/usr/bin/msedit`、`/usr/bin/msedit.real` 和
`edit` 别名；`/boot/optional/plugins/msedit` 里的二进制、ICU 库和设置会保留。

---

## 排错

```bash
/usr/bin/plugins/msedit status
/usr/bin/plugins/msedit install_binary latest
/usr/bin/plugins/msedit install_icu
```

- ICU 下载失败：检查 MOS 的 apt 源和网络；也可以手动把
  `/boot/optional/plugins/msedit/lib` 里放好 `libicu*.so.*` 并创建 symlink。
- `msedit: command not found`：确认 `/usr/bin/msedit` 存在；`mos_start` 会恢复。
- 确认架构：`uname -m`（`x86_64` / `aarch64`）。

---

## 许可证

插件代码使用 MIT License。msedit 由 Microsoft 的官方 release 提供，遵循其 MIT 许可。