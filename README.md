# 武林风

单机武侠 ARPG 原型：程序生成的地图、点击走位、砍怪升级、接任务、开店买卖修装备。
纯 **Godot 4.7 + GDScript**，画面是 2.5D 等距：地面菱形与立绘贴图由本地烘焙（`tool/bake_art.gd`），
UI 图标与音效仍由代码生成。

目录按 [doc/project.md](doc/project.md) 的领域划分；架构、数据流与"怎么加内容"见
[doc/design.md](doc/design.md)。同一粒种子永远得到同一张世界与同一场战斗，回归基线是 `tool/selftest.gd` 的 473 项断言。

## 工程结构

```
project.godot  main.tscn  main.gd  icon.svg
autoload/   game / event / archive / audio / inventory(Kit) / skill   全局单例，只做归属与转发
entity/     会动的角色都归这一层
  player/   unit.gd                                                   玩家属性与成长
  enemy/    base.gd + monster/（模板类 + monsters.csv + database.gd）  敌人运行时与怪物表
  npc/      base.gd + unit.gd + database.gd + npcs.csv
combat/     damage/ + skill/ + status/                                命中伤害、招式表（skills.csv）、临时增益
item/       base.gd + instance.gd + items.csv + inventory/ + loot/
map/        map.gd generator.gd pathfinding.gd iso.gd view.gd renderer.gd + maps.csv + world/ transition/
quest/      base.gd state.gd database.gd + quests.csv
system/     session.gd（一局运行时）+ save/ economy/ dialogue/ fishing/ progression(待拆)
ui/         hud/ inventory/ shop/ skill/ dialogue/ menu/
shared/     enums naming rng grid unit event palette art_gen + art/（烘好的贴图） resource/ audio/ font/
tool/       selftest.gd sim.gd render.gd bake_art.gd preview.gd       开发期工具，游戏不加载
doc/        project.md（布局规范） design.md（设计文档）
```

表与表之间靠字符串互指（掉落写物品名、任务写怪名、NPC 写商店 id、地图写怪名与 NPC 名），
改名字要连引用它的表一起改，改坏会被加载期校验与自检拦下。[shared/naming.gd](shared/naming.gd)
只留代码要点名的那批 id（地图、招式、任务、五个城里 NPC、三间商店、四条鱼）。

## 数值怎么调

七张表全是 CSV，一行一条，用表格软件（Numbers / Excel / WPS）打开改就行，工程里已经没有一个 `.tres`：

| 表 | 位置 | 现有条数 |
| --- | --- | --- |
| 物品（武器/防具/首饰/药/材料/武谱） | [item/items.csv](item/items.csv) | 47 件 |
| 招式 | [combat/skill/skills.csv](combat/skill/skills.csv) | 10 招 |
| 怪物与 BOSS | [entity/enemy/monster/monsters.csv](entity/enemy/monster/monsters.csv) | 20 只 |
| NPC | [entity/npc/npcs.csv](entity/npc/npcs.csv) | 11 位 |
| 地图（含刷怪表、连线、NPC 站位） | [map/maps.csv](map/maps.csv) | 9 张 |
| 任务 | [quest/quests.csv](quest/quests.csv) | 11 条 |
| 商店（货架与收货） | [system/economy/shops.csv](system/economy/shops.csv) | 3 间 |

CSV 里的写法：枚举列（`type`/`kind`/`slot`/`theme`）写名字或序号都认；属性块 `bonus`/`base`/`buff`
用 `k=v;k=v`；复合列用 `|` 分组、`:` 分字段——掉落 `物品名:概率:最少:最多`、连线
`目标图:方位:门牌`、站位 `NPC名:dx:dy`、任务奖励 `物品:份数`；`monsters` 列用 `;` 分隔；
`#` 开头的行是注释。**文字里别用英文逗号**，中文标点是安全的。

装备表多一列 `shape`＝**外观号**（传奇2 的 `ItemInfo.Looks` 那个意思）：同一号共用一套造型，
43 件装备归到十几个号就画得完，加装备是填编号不是加图。画面上玩家按 本体 → 护甲 → 武器
叠三层，层与层同尺寸、同脚底锚点（`item/items.csv` 的 shape 为 0 表示只有数值、不参与外观）。

各领域 `database.gd` 首次访问时做跨表校验（id 重复、掉落指向不存在的物品、武谱指向不存在的招式、
地图连线不回程、任务派活人不在表里，都会 `push_error` 报出来）。加一条新内容＝表里加一行。

新加的东西要在游戏里露面还得配去处：怪物要进某张图的 `monsters` 并保证 `monster_count`
够分（每种至少三格），NPC 要写进某张图的 `npc_spots`，物品要挂在货架、掉落、任务奖励或鱼签上，
地图要从城里顺着门走得通。这几条 `tool/selftest.gd` 都反向查了（每种怪刷得出来、每种怪都进了
刷怪表、每位 NPC 都站着、每件物品都有来路（含钓上来的）、每张图从城里走得到、表里有几行就加载出几条），
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
godot --headless --path . --script res://tool/bake_art.gd -- --raw .artifacts/raw
godot --headless --path . --import                       # 改了文件后先重建 class 与贴图缓存
godot --headless --path . --script res://tool/selftest.gd
godot --headless --path . --script res://tool/sim.gd    -- --seed 808 --seconds 600
godot --headless --path . --script res://tool/render.gd -- --seed 808 --radius 14
godot             --path . --script res://tool/preview.gd -- --seed 808 --map forest
```

- `bake_art` 把 `.artifacts/raw/` 里的原图烘成 `shared/art/` 的运行时贴图。**烘完必须再跑一遍
  `--import`**：引擎加载的是导入缓存，不重导的话 PNG 换了、画面上却还是旧贴图。
- `selftest` 55 段 / 473 项断言，退出码 = 失败项数，CI 里 `$?` 直接可用。
- `sim` 用一个会找怪、喝药、穿装备、读书、接任务、走图、进店的机器人压逻辑路径，
  输出等级/击杀/死亡/掉落统计，并把世界渲染成 PNG。
- `render` 九张图各出一张全图 + 玩家视野特写（俯视示意图，看刷怪与通路用，不是等距画面）。
- `preview` 等距画面的取样台：`_draw` 画的是 CanvasItem，无头模式没有光栅化器，所以这条
  **不能加 `--headless`**。挂几帧等相机收敛再把视口存成 `.artifacts/iso-<图>-<种子>.png`。
- 产物统一落在 `.artifacts/`（已 gitignore）。
- `tool/` 只是开发期工具：五个脚本都没有 `class_name`，主场景与六个 autoload 都不引用它们，
  游戏运行时一行也不会执行。将来出包时在导出预设的 *Resources → Excludes* 里加一行 `tool/*.gd`，
  这一百多 K 就不用带进包里。

想在不点鼠标的情况下确认"画面真的画出来了"，用截图模式（跑 N 帧后自己走路、开面板、存图、
顺手存一次档再读回来）——这条需要真实渲染，不能用 `--headless`：

```
godot --path . -- --shot 260 --seed 808 --png .artifacts/shot.png
```

## 画面是 2.5D 等距

世界仍然是一堆整数格子，寻路、战斗、存档的判定口径没变，改的是"怎么画"，外加"城里得盖起房子"：
[map/iso.gd](map/iso.gd) 是投影的唯一算法，[map/view.gd](map/view.gd) 用一张即时模式画布画完整屏。

- **投影**：2:1 菱形，格 (x,y) 的中心在 `((x-y)*32, (x+y)*16)`，一格铺成 64x32。变换是线性的，
  所以"点了屏幕上哪儿"能闭式逆回格子（`Iso.to_grid`），不用试。这条由自检钉住：格心投影再逆回来
  还是这一格、菱形四角正好落在 (x±½, y±½)。
- **前后遮挡**：画家算法，按脚底所在的斜排 `x+y` 分桶，从远到近画。同桶里先塞地形再塞单位，
  所以站在同一排上的树永远在人后面。
- **厚度**：墙与岩石把顶面抬高 `TILE_H`（正好等于菱形高，前后两块墙才互相补缝），再挤出朝左下、
  朝右下两面侧墙，一明一暗——光从左上来。
- **站立物**：人、怪、竹、松、石笋都是一张立绘，脚底踩在菱形中心，底下压一张椭圆接触阴影；
  走路时按"离整数格多远"整体上下起伏，血条与怪名摆在头顶。
- **走路帧**：玩家四向 × 四帧真帧（`unit_player_f/b/r0..3`），左侧借右侧翻面——引擎的
  `draw_texture_rect` 没有翻转参数，所以镜像是反过来喂 UV 做的。帧号按"累加走过多少格"来定，
  不按秒数：按键走、点击寻路、被击退的节奏因此自动同步，不会出现脚比人快。朝向由这一步在屏幕上的
  主次决定（斜一步是横 32 竖 16，更接近横移，所以归左右）。
- **程序化步态**：怪没有逐帧素材，用钟摆式前后倾 4° + 落脚压扁 5%（都绕脚底发生，头顶在晃、脚跟钉住）
  和朝屏幕左走时镜像顶上；站定时三项全归零，免得没人动的怪在轻微抽动。
- **建筑**：县城那 60 来栋屋由 [map/generator.gd](map/generator.gd) 按地块摆出来，一条硬规矩撑起整段
  逻辑——占地和它的整圈外圈在落笔前必须全可走。于是"绕着房子走一圈"正好是原来那条路，连通性由规矩本身
  保证（不回溯、不洪水填充），顺带逼出任意两栋之间至少隔一格。占地一律是**正方形**：只有正方形的投影菱形，
  最靠镜头的那个角才正好落在水平正中，整栋一张立绘（一格一画会把屋顶切成一排台阶）的底边中心对齐它才不
  会左右偏。房型按权重抽签，民居柴房多、望楼门楼稀；武馆大殿四格见方几乎抽不中，点名摆到广场外侧。
  屋子占的那几格刷成 `HOUSE` 地形（不可走，只往枚举末尾追加），存档里不落地形，所以旧档不必迁移。
  加一栋房要三处点名：`ArtGen.HOUSE_ART` 的占地边长、`ART_SIZES` 的烘焙高度、`HOUSE_LOTTERY` 里的签。
  边长和高度不是各写各的——立绘宽度得落在"占地菱形 ~ 屋檐外探半格"这条带子里，宽度靠烘出来的高度
  等比缩放，自检会拦下配不上的那张。
- **县城那口塘**：位置与半径都钉死在 `POND_OFFSET`/`POND_RADIUS`，不进随机。塘必须躲开穿城的
  南北大街与沿中线的东西主干道——开路步骤会把路上的水当成空地刷平；半径一漂，渔夫 老姜 的固定
  偏移站位就会把他送进水里。水面不可走，所以塘边那一圈沙就是钓位。
- **贴图**：`shared/art/` 那 61 张 PNG 由 [tool/bake_art.gd](tool/bake_art.gd) 从 `.artifacts/raw/`
  烘出来，烘焙尺寸 == 画面尺寸，运行时不缩放。地面菱形就是"俯视无缝图压扁一半"
  （为什么压扁即逆变换，见 `_bake_diamond`），接缝由数学闭死，不祈祷模型画得准；每张地形再按
  "离均值的偏差"压掉一半对比度，否则铺石花纹会和菱形网格咬成一张大棋盘。
- **贴图取不到时**：[shared/art_gen.gd](shared/art_gen.gd) 里那套程序化画法顶上——素材没导入、
  导出预设漏文件、或者干脆裸跑工程，画面都不该是空的。UI 图标（47 件物品、10 招、NPC 头像）
  一直是代码画的，小尺寸下比贴图清楚，这部分不换。
- **气象**：`THEME_TINT` 给地面一层色温，`THEME_FIGURE_TINT` 给立绘吃一半，
  同一套贴图跑出城里偏暖、竹林发绿、洞窟发青。

## 键位

移动/攻击：左键 走路/砍人/找人说话（点怪优先攻击，点地面寻路，点 NPC 会先走过去再开口）
右键 拾取脚下　WASD/方向键 沿屏幕四向走（等距下一步是斜的一格，所以 W 直着往上走）　空格 攻击最近的怪
招式：技能栏十格对应 1..9 与 0（小键盘也行），鼠标指哪儿打哪儿，调息/金钟罩不挑目标
其他：Q 喝最好的血药　F 和最近的人说话　T 走脚下的传送门　G 抛竿/收竿（站在水边才有得钓）
面板：B 背包　E 装备　J 任务簿　Esc 逐层关闭/退出
存档：F5 存档　F9 读档　F2 换一张新地图　M 静音

## 六条玩法线

| 线 | 规则在哪 | 界面 |
| --- | --- | --- |
| 多地图与传送 | `map/generator.gd` + `map/map.gd`（门格/落点）+ `system/session.gd` 每图运行时 | 踩门或传送 NPC 换图、小地图换图重烘、门格高亮与"回武馆"标签 |
| 招式与内力 | `combat/skill/skills.csv` 十招（入门剑法/调息术/崩拳/回风扫叶/穿云掌/追风腿/金钟罩/铁布衫/燎原剑/狮子吼）+ 冷却、内力耗、武谱 | 技能栏十格、冷却暗罩与倒计时、落点方框闪光 |
| NPC 与任务 | `entity/npc/npcs.csv` 对话选项由 `talk_to` 算 + `quest/quests.csv` 十一条 | 对话面板按钮、左侧任务追踪、J 任务簿、任务怪头顶标记 |
| 钓鱼 | [system/fishing/fishing.gd](system/fishing/fishing.gd)（哪儿能下竿、咬钩节奏、按图换鱼签）+ `system/session.gd` 的站桩状态机 | 站在水边按 G 抛竿，0.9~2.6 秒后浮漂下沉，画面正中喊"按 G 收竿"，只有 0.6 秒可收 |
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
- **回归基线是 `tool/selftest.gd` 的 473 项断言，不是 `sim` 的统计数字。**
  时间是 `double` 累加、A* 同分节点的出队次序按 `(f 值, 入队序号)` 固定，
  机器人每 30 秒的位置就会漂；`sim` 只做**量级对照**（跑得动、事件类型齐全、存读档对得上），
  别拿它的击杀数当基线——换一粒种子机器人可能多死十几次。
- 等刷新那段断言（`怪会按时刷新`）在等待期间每帧把玩家血顶满：人一死就回城、本图刷新计时冻住，
  这条断言只剩十几帧余量，不顶血必挂。断言本身没有放宽。
- 存档遇到未知物品 id 时，记一条错误后跳过那一件，其余照常还原（不中断整份读档）。

## 还没做

配音与 BGM 素材（音效仍是 `shared/audio/` 程序化合成的 PCM）、怪物与 NPC 的逐帧动作（玩家已经有
四向 × 四帧，怪只有一套程序化步态，而且游荡时仍是一格一跳——那是 `session.gd` 的 `_move_unit_to`
直接改位置，不在渲染层能解决的范围里）、实体场景化（`entity/player/player.tscn`、`entity/enemy/base.tscn`、`combat/hitbox`
这些规范里预留的位置）、更深的任务分支与 BOSS 战、怪物远程攻击与掉落表调平。
