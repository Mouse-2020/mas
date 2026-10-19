├── project.godot                    # 项目配置文件
├── icon.svg                         # 项目图标
│
├── addon/                           # 第三方插件
│
├── autoload/                        # 全局自动加载脚本
│   ├── game.gd                      # 游戏总管理
│   ├── event.gd                     # 全局信号总线
│   ├── archive.gd                   # 存档与读档
│   ├── audio.gd                     # 音乐和音效管理
│   ├── inventory.gd                 # 背包与装备管理
│   └── skill.gd                     # 技能学习、冷却、释放管理
│
├── entity/                          # 会动的角色都归这一层
│   ├── player/                      # 玩家相关所有内容
│   │   ├── player.tscn              # 玩家主场景
│   │   ├── player.gd                # 玩家主脚本
│   │   ├── stats.gd                 # 玩家属性
│   │   ├── sprite/                  # 玩家图片资源
│   │   ├── animation/               # 玩家动画
│   │   └── component/               # 玩家功能组件
│   │
│   ├── enemy/                       # 所有敌人
│   │   ├── base.tscn                # 敌人基类场景
│   │   ├── base.gd                  # 敌人基类脚本
│   │   ├── monster/                 # 怪物
│   │   └── boss/                    # Boss
│   │
│   └── npc/                         # 所有 NPC
│       ├── base.tscn                # NPC 基类场景
│       ├── base.gd                  # NPC 基类脚本
│       ├── merchant/                # 商人
│       └── quest/                   # 任务相关 NPC
│
├── combat/                          # 战斗相关系统
│   ├── skill/                       # 技能
│   ├── hitbox/                      # 攻击判定盒
│   ├── hurtbox/                     # 受击判定盒
│   ├── damage/                      # 伤害计算
│   └── status/                      # 状态效果
│
├── item/                            # 道具与装备
│   ├── base.gd                      # 物品基类
│   ├── weapon/                      # 武器
│   ├── armor/                       # 防具
│   ├── consumable/                  # 消耗品
│   ├── loot/                        # 掉落物
│   └── inventory/                   # 背包
│       ├── inventory.tscn           # 背包场景
│       └── inventory.gd             # 背包逻辑
│
├── map/                             # 地图与关卡
│   ├── world/                       # 大世界
│   ├── dungeon/                     # 副本/秘境
│   ├── tileset/                     # 瓦片资源
│   └── transition/                  # 场景切换、传送点
│
├── ui/                              # 所有用户界面
│   ├── hud/                         # 游戏内 HUD
│   ├── inventory/                   # 背包界面
│   ├── skill/                       # 技能界面
│   ├── character/                   # 角色属性界面
│   ├── dialogue/                    # 对话界面
│   ├── menu/                        # 菜单
│   └── common/                      # 通用 UI 组件
│
├── quest/                           # 任务系统
│   ├── base.gd                      # 任务基类
│   ├── main/                        # 主线任务
│   └── side/                        # 支线任务
│
├── system/                          # 其他系统
│   ├── fishing/                     # 钓鱼：钓点、咬钩节奏、按图换鱼签（规则在 fishing.gd）
│   ├── dialogue/                    # 对话逻辑
│   ├── economy/                     # 经济
│   ├── progression/                 # 成长
│   └── save/                        # 存档额外逻辑
│
├── shared/                          # 跨系统共享资源
│   ├── font/                        # 字体
│   ├── shader/                      # 着色器
│   ├── audio/                       # 音频
│   │   ├── bgm/                     # 背景音乐
│   │   └── sfx/                     # 音效
│   ├── effect/                      # 通用特效
│   └── resource/                    # 通用自定义 Resource
│
├── tool/                            # 开发期工具
│   ├── selftest.gd                  # 自检台
│   ├── sim.gd                       # 机器人跑台
│   └── render.gd                    # 无头出图
│
└── doc/                             # 项目文档
    └── design.md                    # 设计文档
