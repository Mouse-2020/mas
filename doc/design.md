# 武林风 · 设计文档

工程布局遵循 [project.md](project.md)（按领域分顶层目录）。这份文档讲三件事：
每个领域现在装了什么、一帧里数据怎么流、以及**怎么加内容**（加物品/怪/任务不用改代码）。

## 一、领域与职责

| 目录 | 装什么 | 关键文件 |
| --- | --- | --- |
| `autoload/` | 六个全局单例，只做归属与转发，不写玩法数值 | `game.gd` 持有一局并驱动推进、`event.gd` 信号总线、`archive.gd` 存读档、`audio.gd` 发声、`inventory.gd`（单例名 `Kit`）背包与装备、`skill.gd`（`Skill`）招式学习与冷却 |
| `system/` | 与引擎无关的玩法本体 | `session.gd` 一局运行时（移动/战斗/任务/商店/每帧推进都在这），`save/`、`economy/`、`dialogue/` |
| `entity/player/` | 玩家 | `unit.gd`（`PlayerUnit`：基础属性、经验升级、增益列表） |
| `entity/enemy/` | 敌人 | `base.gd`（`MonsterUnit` 运行时）、`monster/`（模板类 + `monsters.csv` + `database.gd`） |
| `entity/npc/` | 站桩角色 | `base.gd`（`NpcDef`）、`unit.gd`（`NpcUnit`，占格但砍不了）、`database.gd` + `npcs.csv` |
| `combat/` | 战斗 | `damage/`（命中与伤害算法）、`skill/`（招式表 `skills.csv` 与施放结果）、`status/`（临时增益） |
| `item/` | 物品 | `base.gd`（`ItemDef` 模板）、`items.csv`＋`database.gd`、`instance.gd`（带耐久的一件）、`inventory/`（背包＋装备栏）、`loot/`（地上掉落与掉落条目） |
| `map/` | 地图 | `map.gd`（格子世界）、`generator.gd`（按种子生成）、`pathfinding.gd`（8 向 A*）、`maps.csv`＋`world/database.gd`（`WorldDatabase`）、`transition/`（门与连线）、`view.gd`（画面绘制与飘字）、`renderer.gd`（无头出图） |
| `quest/` | 任务 | `base.gd`（模板）、`state.gd`（玩家进度）、`quests.csv` 十一条 |
| `ui/` | 界面 | `hud/`、`inventory/`（背包＋装备两块）、`shop/`、`skill/`（技能栏）、`dialogue/`、`menu/`（任务簿） |
| `shared/` | 跨领域共用 | `enums.gd`、`naming.gd`（代码要点名的 id）、`rng.gd`、`grid.gd`、`unit.gd`（`Unit` 基类）、`event.gd`（`GameEvent`）、`palette.gd`、`art_gen.gd`（占位贴图）、`audio/`（程序化音效合成）、`resource/`（`StatBlock`、`csv_table.gd` 读表） |
| `tool/` | 开发期无头工具（没有 `class_name`，主场景与 autoload 都不引用，运行时零加载；出包时可在导出预设 Excludes 里排掉） | `selftest.gd`（54 段 465 项）、`sim.gd`（机器人跑台）、`render.gd`（九张图出图）、`bake_art.gd`、`preview.gd` |

规范里还没落地的目录（`entity/player/sprite`、`entity/player/animation`、`combat/hitbox`、`combat/hurtbox`、
`map/tileset`、`ui/character`、`ui/common`、`system/progression`、`shared/shader`、
`shared/audio/bgm|sfx`、`addon/`）**故意不建空目录**——git 不跟踪空目录，等有真内容时再建。
其中 `ui/character`（角色属性面板）现在合并在 `ui/inventory/panels.gd` 里，
`system/progression`（成长曲线）现在就是 `entity/player/unit.gd` 的 `experience_to_next` 与 `recompute_base()`。

## 二、一帧里发生了什么

```
Main._process            读键盘 → 翻译成 Game.session.step_player(...)
Game._process (priority 100，排在 Main 之后)
                         session.tick(delta) → session.drain_events()
                         每条事件 Event.raised.emit(...)
订阅者各自反应            Hud 追加日志并重绘 / Panels·QuestPanel·ShopPanel 标脏
                         WorldView 把事件翻成头顶飘字 / Audio 按事件表发声
```

拆单例前这些都在 `main.gd` 里居中转发（467 行）；现在 `main.gd` 只剩装配与输入（395 行），
新增一块界面只要自己订阅 `Event.raised` 就能拿到事件，不用改场景根。

### 画面为什么比格子滑

玩法世界里只有整数格：占用、判定、存档一律 `Vector2i`。但 `_advance_player_path` 每帧都在攒
`_move_progress`（这一格走了几成），以前画面直接拿 `player.position` 画，人就变成一格一格瞬移。
现在 `session.player_render_cell()` / `monster_render_cell()` 把"已站定的那格"和"正在走进去的那格"
按进度插成浮点坐标，`map/view.gd` 只拿它画人画怪，并用同一个相位做 2 像素的上下步态（落回格子上
正好归零，停下不留抖）；相机也改成跟浮点位置、按 `1 - exp(-k·delta)` 收敛，帧率变了跟随速度不变。
插值不参与任何判定。

还有一处只有量才看得出来：进度原来按"格"攒，可斜格路程是 √2 格，于是斜走比直走快四成，
而 8 向寻路必然直斜混排——观感就是"一冲一顿"。现在 `_step_scale()` 按路程给进度加成
（玩家与怪共用一条规则），世界速度恒定；`_measure_step_speed()` 分别量直步与斜步的每帧位移，
比值偏离 5% 就报红（修好前实测是直 0.0533 / 斜 0.0754，正好差 √2）。
`_movement_renders_between_cells` 一共钉住五件事：静止时渲染位置严格等于脚下那格、走起来确实落在
两格之间、到站立刻归位、滑到半格时占用查询仍只认整数格、斜走不比直走快。

`Game.start()` / `Game.adopt()`（读档后接管）/ `Game.new_world()`（F2 换图）都会发
`Event.session_ready`，由 `Main._attach()` 统一重绑所有面板。

## 三、数值表就是 CSV

七张表全是 CSV，一行一条，用表格软件直接改；工程里已经没有一个 `.tres`：

| 表 | 位置 | 模板类 |
| --- | --- | --- |
| 物品 | `item/items.csv`（47 件） | `item/base.gd` `ItemDef` |
| 招式 | `combat/skill/skills.csv`（10 招） | `combat/skill/def.gd` `SkillDef` |
| 怪物 | `entity/enemy/monster/monsters.csv`（20 只） | `entity/enemy/monster/def.gd` `MonsterDef`（掉落条目 `item/loot/drop_roll.gd`） |
| NPC | `entity/npc/npcs.csv`（11 位） | `entity/npc/base.gd` `NpcDef` |
| 地图 | `map/maps.csv`（9 张） | `map/def.gd` `MapDef`（连线 `map/transition/link.gd`、站位 `map/npc_spot.gd`） |
| 任务 | `quest/quests.csv`（11 条） | `quest/base.gd` `QuestDef`（奖励 `quest/reward.gd`） |
| 商店 | `system/economy/shops.csv`（3 间） | `system/economy/shop.gd` `ShopDef` |

CSV 由 `shared/resource/csv_table.gd` 读成上面这些带类型的 Resource，所以调用方一行没改：
枚举列写名字或序号都认，属性块写 `k=v;k=v`，复合列用 `|` 分组、`:` 分字段——掉落
`物品:概率:最少:最多`、连线 `目标图:方位:门牌`、站位 `NPC:dx:dy`、奖励 `物品:份数`，
`monsters`/`stock` 用 `;` 分隔，`#` 开头是注释。表头就是字段名，缺列取代码里的默认值；
**文字里出现英文逗号会串列**，所以描述一律用中文标点。

各领域的 `database.gd` 首次访问时按 `id` 建索引并做**跨表校验**：id 重复、武谱指向不存在的招式、
商店卖了不存在的物品、任务打的怪/收的物品/NPC 不存在、前置任务缺失、地图引用的怪与 NPC 不存在——
都 `push_error` 报出来。反向也查（漏配去处比配错更难发现）：每种怪刷得出来、每种怪都进了某张图的
刷怪表、每位 NPC 都站在某张图上、每件物品都有来路（货架／掉落／任务奖励）、每张图从城里走得到、
七张表各自"表里几行就加载出几条"。

**加一件新东西＝表里加一行**，不用改任何代码；但新怪物要进某张图的 `monster_ids`（且
`monster_count` 每种至少分三格，`_populate_monsters` 是按等级一段一种铺的），新 NPC 要在某张图的
`npc_spots` 里写站位，地图得能从城里顺着门走到（连线还必须成对，单向门会把人困住）。

表与表之间仍然全靠字符串互指：掉落写物品名、任务写怪或物品名、武谱写招式名、NPC 写商店 id、
地图写怪名与 NPC 名。所以**改名字要连引用它的那些表一起改**——改完自检会替你把关。
`shared/naming.gd` 只留代码（`main.gd`、UI、selftest）要点名的那批 id，表内的名字直接写在表里。

## 四、可复现性与验收

- `shared/rng.gd` 是 uint32 xorshift 的逐位复刻：同一粒种子永远得到同一张地图、同一批怪、同一场战斗。
- 地形不进存档：每张图按 `(地图定义, 种子)` 重生成，所以存档不会因地图漂移而坏。
- 无头验收：`tool/selftest.gd` 54 段 465 项断言，退出码＝失败数；`tool/sim.gd` 用机器人压玩法主线；
  `tool/render.gd` 出整图与视野特写。产物落 `.artifacts/`。
- 画面验收必须开窗口（无头是 dummy 渲染器，取不到视口纹理）：
  `godot --path . -- --shot 260 --seed 808 --png .artifacts/shot.png`，它还会顺手存一次档再读回来。
- `sim` 只做量级对照，不是回归基线（double 计时 + A* 同分次序会让机器人路线随帧序漂移）；
  回归基线只有 `selftest` 的 465 项断言。详见 `README.md` 的"可复现性与回归基线"。

## 五、六条玩法线现在的落点

| 线 | 数据 | 规则 | 界面 |
| --- | --- | --- | --- |
| 多地图与传送 | `map/maps.csv` | `map/generator.gd`、`map/map.gd`（门格与落点）、`system/session.gd` | `map/view.gd`、`ui/hud/minimap.gd` |
| 招式与内力 | `combat/skill/` | `system/session.gd` 的施放段、`combat/damage/combat.gd` | `ui/skill/skill_bar.gd` |
| NPC 与任务 | `entity/npc/npcs.csv`、`quest/quests.csv` | `system/session.gd` 的对话与任务段 | `ui/dialogue/dialogue_panel.gd`、`ui/menu/quest_panel.gd` |
| 商店与经济 | `system/economy/shops.csv` | `system/economy/trade.gd`（买价照表、卖价对折、耐久折算、修理按缺失条数） | `ui/shop/shop_panel.gd` |
| 钓鱼 | `system/fishing.gd` 的鱼签与节奏常量 | `system/session.gd` 的钓鱼段（站桩状态机，单独一路 `Rng`） | `ui/hud/hud.gd` 画面正中的咬钩提示 |
| 音效 | `shared/audio/sfx_bank.gd` 的配方与事件表 | 同左（程序化合成 PCM） | `autoload/audio.gd` |
