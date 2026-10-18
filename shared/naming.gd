class_name Naming
extends RefCounted

# 武林风（武侠门派）词表：只收代码还要按名字引用的 id。
# 物品/技能/怪物/NPC 四张批量表现在是 CSV（item/items.csv 等），名字直接写在表里；
# 七张表都在 CSV 里，名字直接写在表内；这里留的是 main/selftest/UI 会点名的那批。
# 玩法里地图刷怪表、任务目标、商店货架、NPC 对话全靠字符串互指，
# 任何一侧漏改会在加载期被各 Database 的自检拦下。

# ---- 地图（id 落进存档，保持 ASCII 且不要改） ----
const MAP_TOWN := "town"
const MAP_SUBURB := "suburb"
const MAP_FOREST := "forest"
const MAP_CAVE := "cave"

const MAP_TOWN_NAME := "青云武馆"
const MAP_SUBURB_NAME := "武馆后山"
const MAP_FOREST_NAME := "迷雾竹林"
const MAP_CAVE_NAME := "枯骨密洞"

# ---- 主角 ----
const PLAYER_NAME := "侠客"

# ---- 怪物（id 即显示名，掉落表与任务目标按它比对） ----
const MONSTER_CHICKEN := "山鸡"
const MONSTER_DEER := "野鹿"
const MONSTER_DUMMY := "木人桩"
const MONSTER_WOLF := "竹林狼"
const MONSTER_BANDIT := "蒙面匪"
const MONSTER_BAT := "洞蝠"
const MONSTER_BONE_SLAVE := "枯骨武奴"
const MONSTER_BONE_MASTER := "白骨宗师"

# ---- NPC ----
const NPC_TEACHER := "武馆教头"
const NPC_SMITH := "铁匠王二"
const NPC_HERBALIST := "药婆孙氏"
const NPC_GUIDE := "引路人玄子"

const NPC_TEACHER_NAME := "武馆教头"
const NPC_SMITH_NAME := "铁匠 王二"
const NPC_HERBALIST_NAME := "药师 孙氏"
const NPC_GUIDE_NAME := "引路人 玄子"

# 后山、竹林、密洞各处新增的站桩人；只被地图站位表引用，所以留在这里。
const NPC_ESCORT := "镖师老周"
const NPC_HUNTER := "猎户阿秀"
const NPC_ACCOUNT := "账房钱九"
const NPC_PRIEST := "云游道人"
const NPC_KEEPER := "守洞人哑伯"
const NPC_STORYTELLER := "说书柳三"
const NPC_FISHERMAN := "渔夫老姜"

# ---- 商店（id 落进存档） ----
const SHOP_WEAPON := "weapon"
const SHOP_MEDICINE := "medicine"
const SHOP_FISH := "fish"
const SHOP_WEAPON_NAME := "王二铁匠铺"
const SHOP_MEDICINE_NAME := "孙氏药庐"
const SHOP_FISH_NAME := "老姜鱼摊"

# ---- 技能（id 落进存档） ----
const SKILL_SLASH := "slash"
const SKILL_HEAL := "heal"
const SKILL_MOON := "moon"
const SKILL_BOLT := "bolt"
const SKILL_SHIELD := "shield"
const SKILL_FIRE := "fire"

const SKILL_SLASH_NAME := "入门剑法"
const SKILL_HEAL_NAME := "调息术"
const SKILL_MOON_NAME := "回风扫叶"
const SKILL_BOLT_NAME := "穿云掌"
const SKILL_SHIELD_NAME := "金钟罩"
const SKILL_FIRE_NAME := "燎原剑"

# ---- 任务（id 落进存档） ----
const QUEST_CHICKEN := "q_chicken"
const QUEST_HIDE := "q_hide"
const QUEST_WOLF := "q_wolf"
const QUEST_BONES := "q_skeleton"
const QUEST_MASTER := "q_king"
const QUEST_FISH := "q_fish"

# ---- 物品 ----
const ITEM_GOLD := "金币"

const ITEM_POTION_HP_SMALL := "活血散"
const ITEM_POTION_HP_LARGE := "大活血丹"
const ITEM_POTION_MP := "内力丹"
const ITEM_POTION_MIXED := "两仪丹"

const ITEM_WOOD_SWORD := "木剑"
const ITEM_BRONZE_SWORD := "青铜剑"
const ITEM_FLAME_BLADE := "赤炎刀"
const ITEM_WIND_BLADE := "回风刀"
const ITEM_JUSTICE_STAFF := "紫竹杖"

const ITEM_CLOTH := "布衣"
const ITEM_LIGHT_ARMOR := "软甲"
const ITEM_HEAVY_ARMOR := "铁重甲"
const ITEM_DEMON_ARMOR := "玄武甲"

const ITEM_IRON_HELMET := "铁头盔"
const ITEM_WAR_HELMET := "虎头盔"
const ITEM_NOVICE_NECKLACE := "护心镜"
const ITEM_POWER_RING := "铁扳指"
const ITEM_STEALTH_RING := "云纹扳指"
const ITEM_LIGHT_BOOTS := "快靴"
const ITEM_HIDE_BELT := "皮腰带"

const ITEM_IRON_ORE := "铁矿石"
const ITEM_HIDE := "兽皮"
const ITEM_SNAKE_GALL := "蛇胆"
const ITEM_WOLF_FANG := "狼牙"
const ITEM_BAT_WING := "洞蝠翼"

const ITEM_BOOK_MOON := "武谱·回风扫叶"
const ITEM_BOOK_BOLT := "武谱·穿云掌"
const ITEM_BOOK_SHIELD := "武谱·金钟罩"
const ITEM_BOOK_FIRE := "武谱·燎原剑"

# 钓鱼上来的四样。系统层按 theme 抽签时要点名，所以不能只活在 CSV 里。
const ITEM_FISH_CRUCIAN := "鲫鱼"
const ITEM_FISH_CARP := "鲤鱼"
const ITEM_FISH_GRASS := "草鱼"
const ITEM_FISH_BLACK := "黑鱼"
