# 武林风

单机武侠 ARPG 原型：程序生成的地图、点击走位、砍怪升级、接任务、开店买卖修装备。
纯 **Godot 4.7 + GDScript**，画面与音效全部由代码生成，不依赖任何外部素材。

目录按 [doc/project.md](doc/project.md) 的领域划分；架构、数据流与"怎么加内容"见
[doc/design.md](doc/design.md)。同一粒种子永远得到同一张世界与同一场战斗，回归基线是 `tool/selftest.gd` 的 409 项断言。

## 工程结构

```
project.godot  main.tscn  main.gd  icon.svg
autoload/   game / event / archive / audio / inventory(Kit) / skill   全局单例，只做归属与转发
player/     unit.gd                                                   玩家属性与成长
enemy/      base.gd + monster/（模板类 + monsters.csv + database.gd）  敌人运行时与怪物表
npc/        base.gd + unit.gd + database.gd + npcs.csv
combat/     damage/ + skill/ + status/                                命中伤害、招式表（skills.csv）、临时增益
item/       base.gd + instance.gd + items.csv + inventory/ + loot/
map/        map.gd generator.gd pathfinding.gd renderer.gd view.gd + maps.csv + world/ transition/
quest/      base.gd state.gd database.gd + quests.csv
system/     session.gd（一局运行时）+ save/ economy/ dialogue/ progression(待拆)
ui/         hud/ inventory/ shop/ skill/ dialogue/ menu/
shared/     enums naming rng grid unit event palette art_gen + resource/ audio/ font/
tool/       selftest.gd sim.gd render.gd                              开发期无头工具，游戏不加载
doc/        project.md（布局规范） design.md（设计文档）
```

表与表之间靠字符串互指（掉落写物品名、任务写怪名、NPC 写商店 id、地图写怪名与 NPC 名），
改名字要连引用它的表一起改，改坏会被加载期校验与自检拦下。[shared/naming.gd](shared/naming.gd)
只留代码要点名的那批 id（地图、招式、任务、四个城里 NPC、两间商店）。

## 数值怎么调

七张表全是 CSV，一行一条，用表格软件（Numbers / Excel / WPS）打开改就行，工程里已经没有一个 `.tres`：

| 表 | 位置 | 现有条数 |
| --- | --- | --- |
| 物品（武器/防具/首饰/药/材料/武谱） | [item/items.csv](item/items.csv) | 43 件 |
| 招式 | [combat/skill/skills.csv](combat/skill/skills.csv) | 10 招 |
| 怪物与 BOSS | [enemy/monster/monsters.csv](enemy/monster/monsters.csv) | 20 只 |
| NPC | [npc/npcs.csv](npc/npcs.csv) | 10 位 |
| 地图（含刷怪表、连线、NPC 站位） | [map/maps.csv](map/maps.csv) | 9 张 |
| 任务 | [quest/quests.csv](quest/quests.csv) | 10 条 |
| 商店（货架与收货） | [system/economy/shops.csv](system/economy/shops.csv) | 2 间 |

CSV 里的写法：枚举列（`type`/`kind`/`slot`/`theme`）写名字或序号都认；属性块 `bonus`/`base`/`buff`
用 `k=v;k=v`；复合列用 `|` 分组、`:` 分字段——掉落 `物品名:概率:最少:最多`、连线
`目标图:方位:门牌`、站位 `NPC名:dx:dy`、任务奖励 `物品:份数`；`monsters` 列用 `;` 分隔；
`#` 开头的行是注释。**文字里别用英文逗号**，中文标点是安全的。

各领域 `database.gd` 首次访问时做跨表校验（id 重复、掉落指向不存在的物品、武谱指向不存在的招式、
地图连线不回程、任务派活人不在表里，都会 `push_error` 报出来）。加一条新内容＝表里加一行。

新加的东西要在游戏里露面还得配去处：怪物要进某张图的 `monsters` 并保证 `monster_count`
够分（每种至少三格），NPC 要写进某张图的 `npc_spots`，物品要挂在货架、掉落或任务奖励上，
地图要从城里顺着门走得通。这几条 `tool/selftest.gd` 都反向查了（每种怪刷得出来、每种怪都进了
刷怪表、每位 NPC 都站着、每件物品都有来路、每张图从城里走得到、表里有几行就加载出几条），
漏配会被断言拦下。


## 怎么跑

用 Godot 4.7 标准版（不需要 .NET）打开工程根目录即可。命令行：

```
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

首次打开会导入字体与图标并生成 `.godot/` 缓存。想换地图种子加 `-- --seed 808`
（`--` 之后的参数才归游戏）。

## 不开窗口也能验

```
godot --headless --path . --import                       # 改了文件后先重建 class 缓存
godot --headless --path . --script res://tool/selftest.gd
godot --headless --path . --script res://tool/sim.gd    -- --seed 808 --seconds 600
godot --headless --path . --script res://tool/render.gd -- --seed 808 --radius 14
```

- `selftest` 49 段 / 409 项断言，退出码 = 失败项数，CI 里 `$?` 直接可用。
- `sim` 用一个会找怪、喝药、穿装备、读书、接任务、走图、进店的机器人压逻辑路径，
  输出等级/击杀/死亡/掉落统计，并把世界渲染成 PNG。
- `render` 九张图各出一张全图 + 玩家视野特写。
- 产物统一落在 `.artifacts/`（已 gitignore）。
- `tool/` 只是开发期工具：三个脚本都没有 `class_name`，主场景与六个 autoload 都不引用它们，
  游戏运行时一行也不会执行。将来出包时在导出预设的 *Resources → Excludes* 里加一行 `tool/*.gd`，
  这一百多 K 就不用带进包里。

想在不点鼠标的情况下确认"画面真的画出来了"，用截图模式（跑 N 帧后自己走路、开面板、存图、
顺手存一次档再读回来）——这条需要真实渲染，不能用 `--headless`：

```
godot --path . -- --shot 260 --seed 808 --png .artifacts/shot.png
```

## 键位

移动/攻击：左键 走路/砍人/找人说话（点怪优先攻击，点地面寻路，点 NPC 会先走过去再开口）
右键 拾取脚下　WASD/方向键 走格子　空格 攻击最近的怪
招式：技能栏十格对应 1..9 与 0（小键盘也行），鼠标指哪儿打哪儿，调息/金钟罩不挑目标
其他：Q 喝最好的血药　F 和最近的人说话　T 走脚下的传送门
面板：B 背包　E 装备　J 任务簿　Esc 逐层关闭/退出
存档：F5 存档　F9 读档　F2 换一张新地图　M 静音

## 五条玩法线

| 线 | 规则在哪 | 界面 |
| --- | --- | --- |
| 多地图与传送 | `map/generator.gd` + `map/map.gd`（门格/落点）+ `system/session.gd` 每图运行时 | 踩门或传送 NPC 换图、小地图换图重烘、门格高亮与"回武馆"标签 |
| 招式与内力 | `combat/skill/skills.csv` 十招（入门剑法/调息术/崩拳/回风扫叶/穿云掌/追风腿/金钟罩/铁布衫/燎原剑/狮子吼）+ 冷却、内力耗、武谱 | 技能栏十格、冷却暗罩与倒计时、落点方框闪光 |
| NPC 与任务 | `npc/npcs.csv` 对话选项由 `talk_to` 算 + `quest/quests.csv` 十条 | 对话面板按钮、左侧任务追踪、J 任务簿、任务怪头顶标记 |
| 商店 | `system/economy/trade.gd`（买价照表、卖价对折、耐久折算、修理按缺失条数） | 买卖两栏面板、站在老板跟前才解锁、修理按钮实时报价 |
| 音效 | `shared/audio/sfx_bank.gd`（程序化合成 PCM + 事件到音效映射表） | `autoload/audio.gd` 转 `AudioStreamWAV`、8 路发声通道、循环 BGM、M 静音 |

九张图（`map/maps.csv`）：青云武馆（安全区）→ 武馆后山，往后分三条线——
东去迷雾竹林 → 枯骨密洞 → 藏经石室，竹林南折进前朝废墟 → 毒沼，废墟东上试剑崖；
后山往南是药王谷。越远越凶，BOSS 白骨宗师在密洞深处，石室里守着血刀僧。

字体是 `shared/font/puhuiti.ttf`（阿里巴巴普惠体），有两个入口：`project.godot` 的
`gui/theme/custom_font` 管面板与按钮，`shared/art_gen.gd` 的 `FONT_PATH` 管地图上直接画的
怪名、门牌与飘字。换字体时两处一起改，`selftest` 会核对两处是不是同一个文件、字体加载得出来、
"武"字画得出来。
**换中文字体要留意全角空格（U+3000）**：普惠体的 U+3000 零宽，界面里的分隔符会整体塌掉
（"背包1/40 格负重…"就是这么来的），所以 UI 文案的分隔一律用两个普通空格，别再写全角空格。

## 存档

`~/Library/Application Support/Godot/app_userdata/武林风/wulin-<种子>.json`
（Windows 是 `%APPDATA%\Godot\app_userdata\武林风\`）。
只存随机种子 + 单位/物品状态，地图按种子重新生成，所以存档不会因为地图漂移而坏掉。
JSON 键名 snake_case，格式版本 `FORMAT_VERSION = 3`；版本不符的存档会被直接顶回来。

## 可复现性与回归基线

- `shared/rng.gd` 是 uint32 xorshift：同一粒种子永远得到同一张地图、同一批怪、同一场战斗。
  改任何一处掩码都会改变结果，所以它属于回归基线的一部分，不是可以顺手"优化"的代码。
- 地形不进存档：每张图按 `(地图定义, 种子)` 重生成，存档只记动态内容，所以不会因地图漂移而坏。
- **回归基线是 `tool/selftest.gd` 的 409 项断言，不是 `sim` 的统计数字。**
  时间是 `double` 累加、A* 同分节点的出队次序按 `(f 值, 入队序号)` 固定，
  机器人每 30 秒的位置就会漂；`sim` 只做**量级对照**（跑得动、事件类型齐全、存读档对得上），
  别拿它的击杀数当基线——换一粒种子机器人可能多死十几次。
- 等刷新那段断言（`怪会按时刷新`）在等待期间每帧把玩家血顶满：人一死就回城、本图刷新计时冻住，
  这条断言只剩十几帧余量，不顶血必挂。断言本身没有放宽。
- 存档遇到未知物品 id 时，记一条错误后跳过那一件，其余照常还原（不中断整份读档）。

## 还没做

正式贴图与配音素材（现在全是代码生成的占位图与合成音）、实体场景化（`player/player.tscn`、`enemy/base.tscn`、`combat/hitbox` 这些规范里预留的位置）
更深的任务分支与 BOSS 战、怪物远程攻击与掉落表调平。
