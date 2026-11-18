# MSEdit MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[Microsoft Edit](https://github.com/microsoft/edit)（命令名 `msedit`）的插件实现仓库。

- Hub 索引条目在：[hustyanzu-mos/mos-templates](https://github.com/hustyanzu-mos/mos-templates)
- 本仓库只负责插件实现和架构对应的 release `.deb`

---

## 它做什么

- 构建时把官方 `msedit` 二进制打进插件 `.deb`
- `.deb` 安装二进制到 `/usr/lib/msedit/msedit`
- 安装 `/usr/bin/msedit` 包装脚本；如果系统没有 `edit`，创建 `edit` 别名
- MOS 启动时重新安装 `.deb`，恢复 `/usr/lib` 和 `/usr/bin`
- `/boot` 只存 `.deb` 和插件数据，不存编辑器二进制
- 提供 MOS 插件页面：状态和命令

更新通过新的插件 Release（和 `mos-vim` 一样）。

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

本地（当前架构）：

```bash
./build.sh 0.2.0
```

输出：

```text
build/msedit-0.2.0-1+mos-plugin_amd64.deb
build/msedit-0.2.0-1+mos-plugin_amd64.deb.md5
```

GitHub Actions 会同时构建：

```text
msedit-0.2.0-1+mos-plugin_amd64.deb
msedit-0.2.0-1+mos-plugin_arm64.deb
```

Hub 会根据机器架构选择对应的 `.deb`。

---

## 发布与安装

```bash
git tag 0.2.0
git push origin 0.2.0
```

在 MOS 添加索引仓库：

```text
https://github.com/hustyanzu-mos/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **MSEdit**。

安装后：

- `/usr/lib/msedit/msedit`：真实二进制
- `/usr/bin/msedit`：包装脚本
- `/usr/bin/edit`：仅当系统没有 `edit` 时创建的别名

---

## 持久化

Hub 安装器会把 `.deb` 和 `functions` 放到：

```text
/boot/optional/plugins/msedit/<version>/
```

启动时 `installplugins-mos` 重新安装该 `.deb`，恢复 `/usr/lib/msedit` 和
`/usr/bin/msedit`。

- `/boot` 只放 `.deb`、`functions` 和插件数据
- 插件设置：`/boot/optional/plugins/msedit/settings.json`
- 可选系统包清单：`/boot/optional/plugins/msedit/packages/packages`

如果手动 `dpkg -i`，插件只对当前运行有效；要让它重启后仍然存在，请使用
MOS Hub。

---

## 使用

```bash
msedit
msedit /mnt/cache/some-file.txt
edit some-file.txt          # 仅当系统没有 edit 时创建别名
```

---

## 升级 / 卸载

**升级**：MOS Hub 里刷新并更新 MSEdit 插件，或安装新的插件 Release。

**卸载**：卸载插件会移除 `/usr/lib/msedit`、`/usr/bin/msedit` 和 `edit` 别名；
`/boot/optional/plugins/msedit` 里的设置会保留。

---

## 排错

```bash
/usr/bin/plugins/msedit status
/usr/bin/plugins/msedit version
ls -la /usr/lib/msedit/msedit
```

`msedit: command not found` 时重新安装 MSEdit 插件，让 MOS 重新安装 `.deb`。

---

## 许可证

插件代码使用 MIT License。msedit 由 Microsoft 的官方 release 提供，遵循其 MIT 许可。