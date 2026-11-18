# MSEdit MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[Microsoft Edit](https://github.com/microsoft/edit)（命令名 `msedit`）的插件实现仓库。

- Hub 索引条目在：[hustyanzu-mos/mos-templates](https://github.com/hustyanzu-mos/mos-templates)
- 本仓库只负责插件实现和 release `.deb`

---

## 它做什么

- 从 Microsoft 官方 GitHub Releases 下载 `msedit` 二进制（`amd64` / `arm64`）
- 安装到 `/boot/optional/plugins/msedit/bin/msedit`
- 复制运行副本到 `/usr/bin/msedit.real`，避免 `/boot` noexec
- 安装 `/usr/bin/msedit` 包装脚本；如果系统没有 `edit`，创建 `edit` 别名
- 提供 MOS 插件页面：安装 / 更新 / 状态

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
./build.sh 0.1.1
```

输出：

```text
build/msedit-0.1.1-1+mos-plugin_all.deb
build/msedit-0.1.1-1+mos-plugin_all.deb.md5
```

---

## 发布与安装

```bash
git tag 0.1.1
git push origin 0.1.1
```

GitHub Actions 构建 `.deb` + `.md5` 并创建 Release。

在 MOS 添加索引仓库：

**Settings → System Configuration → MOS Hub Settings → Add Repository**

```text
https://github.com/hustyanzu-mos/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **MSEdit**，然后在插件页
点击 **Install**。

也可以手动安装：

```bash
dpkg -i msedit-0.1.1-1+mos-plugin_all.deb
/usr/bin/plugins/msedit install_binary
```

---

## 使用

```bash
msedit
msedit /mnt/cache/some-file.txt
edit some-file.txt          # 仅当系统没有 edit 时创建别名
```

---

## 持久化

MOS 的 Hub 安装器会把 `.deb` 和 `functions` 放到：

```text
/boot/optional/plugins/msedit/<version>/
```

并在插件根目录写 `template.json`。启动时 `installplugins-mos` 会重新安装该
`.deb`，并执行 `functions mos_start`。

- 二进制：`/boot/optional/plugins/msedit/bin/msedit`
- 运行时副本：`/usr/bin/msedit.real`（RAM）
- 插件设置：`/boot/optional/plugins/msedit/settings.json`

如果手动 `dpkg -i`，插件只对当前运行有效；要让它重启后仍然存在，请使用
MOS Hub，或把 `.deb`/`functions` 放到版本目录并补上 `template.json`。

---

## 设置

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `auto_install` | `true` | 二进制缺失时自动下载 |
| `pin_version` | `""` | 固定版本，例如 `2.0.0`；空为最新 |
| `version` | `""` | 已安装版本，由插件维护 |

---

## 升级 / 卸载

**升级**：插件页 **Check updates** → **Update**。
后端会下载新的 msedit、校验 sha256、替换持久化二进制和运行副本。

**卸载**：卸载插件会移除 `/usr/bin/msedit`、`/usr/bin/msedit.real` 和
`edit` 别名；`/boot/optional/plugins/msedit` 里的二进制和设置会保留。

---

## 排错

```bash
/usr/bin/plugins/msedit status
/usr/bin/plugins/msedit install_binary latest
```

- `msedit: command not found`：确认 `/usr/bin/msedit` 存在；`mos_start` 会恢复。
- 确认架构：`uname -m`（`x86_64` / `aarch64`）。

---

## 许可证

插件代码使用 MIT License。msedit 由 Microsoft 的官方 release 提供，遵循其 MIT 许可。