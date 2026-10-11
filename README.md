# Dave Save Importer · 潜水员戴夫存档导入工具

macOS 原生 Swift / AppKit 小工具，将 SData ZIP 压缩包中的存档导入本机《潜水员戴夫》，并在每次替换前保存完整历史备份。当前版本：**1.1**。

## 功能

- 拖入 ZIP 或通过文件选择器选择压缩包，一键导入。
- 自动查找已有的 Mac 存档目录；存在多个账号时可选择目标。
- 首次启动选择默认备份目录或自定义目录，之后自动记住，可随时修改。
- 每次导入前完整备份，以北京时间和唯一编号命名；不会自动删除或覆盖历史备份。
- 备份文件逐字节校验；备份失败则停止导入。
- 游戏运行时禁止导入；替换失败时尝试从备份恢复。

## 编译与启动

需要 macOS 11+ 和 Xcode Command Line Tools（`xcode-select --install`）。在 Apple Silicon Mac 上开发和验证；构建脚本编译为当前机器架构。

```sh
./scripts/build.sh
open 'build/Dave Save Importer.app'
```

可把生成的 App 拖到“应用程序”文件夹。无第三方运行时依赖，使用系统 `/usr/bin/unzip`。构建采用本地临时签名，未经过 Apple 公证。

## 使用方法

1. 完全退出游戏。
2. 打开 App，首次运行选择默认或自定义备份位置。
3. 拖入 `SData.zip`，或者点击“选择 ZIP 压缩包”。
4. 确认目标存档目录，点击“导入并替换存档”。
5. 成功后启动游戏，在“载入游戏”里检查进度。

压缩包中可直接放主存档，也可放在一个 SData 文件夹内。仅支持 ZIP；不支持 RAR、7z。

导入 `GameSave_数字_GD.sav`、`GameSave_数字_PZ.sav` 和 `GameSave_数字_UO.sav`；GD/PZ 必须成对。忽略 `m_`、`_o` 和 `_BackUp` 副本。替换时清除目标目录旧 `.sav` 和 `_BackUp`，保留其他文件，避免混用进度。

## 历史备份与恢复

默认位置：

```text
~/Library/Application Support/DaveSaveImporter/Backups
```

点击“设置备份位置…”更改位置，或“打开备份文件夹”查看。更改位置后，旧备份仍保留在原位置。

每个时间目录包含完整旧存档、`原始路径.txt` 和 `备份说明.txt`。`0-…` 是主目录备份，后续编号为同步副本。恢复时完全退出游戏，按 `原始路径.txt` 的顺序把相应备份目录整体恢复到原位置。恢复前可保留当前存档副本。

## 支持的目标路径

- `~/Library/Application Support/com.nexon.dave/SteamSData/<账号>/`
- `~/Library/Application Support/nexon/DAVE THE DIVER/SteamSData/<账号>/`
- 上述游戏目录内已存在的 `SData/`

若检测到 `NemirtingasSteamEmu/<账号>/1868140/remote` 中已有戴夫存档，也会备份并更新这些同步副本。当前实现会更新所有检测到的此类副本。

工具按原始字节迁移，不转换存档格式或游戏版本。不同平台、不同游戏版本的兼容性需要进入游戏确认。使用 Steam 云同步时，应避免旧云存档覆盖导入结果。

## 验证

```sh
./scripts/test.sh
```

测试使用临时目录，覆盖自定义位置、连续历史备份、文件内容一致性、无效备份位置与失败保护，不修改真实游戏存档。

源码入口：`Sources/main.swift`；App 元数据：`Resources/Info.plist`。仓库不包含游戏、用户存档或本地备份。本项目与游戏开发商无关联。
