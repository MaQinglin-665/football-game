# 依赖、版本与署名

本地开发使用 Godot **4.6.3.stable.official.7d41c59c4** 标准版、GDScript、Jolt Physics 和 OpenGL Compatibility。没有执行外部安装脚本。

| 基础 | 固定版本 | 用途 | 许可 |
| --- | --- | --- | --- |
| [Whimfoome/godot-FirstPersonStarter](https://github.com/Whimfoome/godot-FirstPersonStarter) | `893db99a10eedadbd8189c040fb4d41fdf6ca46a` | 实际复用完整 `Player` 场景、MovementController、Head、Sprint；增加比赛输入开关，调整速度、胶囊与镜头参数，关闭冲刺 FOV 变化 | MIT，Dimitar “Whimfoome” Dimitrov；全文在 `licenses/Whimfoome-MIT.txt` |
| [nicolasbize/soccer-course](https://github.com/nicolasbize/soccer-course) | `c28147f5e5a37e0fa9ecd3157d80352dc1109f70` | 参考 2D AI 的持球前进、岗位追球、队友接应、回位与密度分散思路，重新实现 3D XZ 岗位与 200ms 决策；未使用独立素材库 | MIT，Nicolas Bize；全文在 `licenses/NicolasBize-MIT.txt` |
| [Godot Engine](https://godotengine.org/download/archive/4.6.3-stable/) | 4.6.3 stable | 引擎与官方 Windows x64 导出模板 | MIT 及内置组件许可，完整通知由该引擎 API 导出到 `licenses/Godot-and-components.txt` |

球场、人物、足球纹理、图标、HUD 和音效均由本项目代码创建。中文使用 Windows 系统字体，未分发微软字体文件。

官方导出模板来自 `godotengine/godot-builds` 的 `4.6.3-stable` 发布。由于整包下载停滞，只通过官方 HTTPS byte ranges 获取 Windows ZIP 条目，并校验 Content-Range、解压长度、CRC32。文件 SHA256 与来源记录在交付目录 `tools/godot-4.6.3/provenance.json`。这不是对完整 1.25GB 压缩包 SHA512 的验证。

| [romdi/iosoccer-game](https://github.com/romdi/iosoccer-game/blob/f572c993c8c551cb87facfc68388f3dd368d1d9f/game/server/sdk/ball.cpp) | `f572c993c8c551cb87facfc68388f3dd368d1d9f` | 参考球侧移/后拉、触球冷却、主动动作优先于被动碰撞及同速分离时不重复加速的政策；在现有 Godot 实际鞋面接触系统内实现；未搬入 Source SDK、其数值单位或资产 | 根许可 MIT，Mark “routetwo” Gornall / IOS Development Team；全文 `licenses/IOSoccer-policy-MIT.txt` |
