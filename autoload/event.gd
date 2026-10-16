extends Node

# 全局信号总线：system/session.gd 攒的事件流在这里散出去，UI 各自订阅，不用谁居中转发。

## 每帧推进后，GameSession 产生的事件逐条广播（GameEvent）。
signal raised(event: GameEvent)

## 换了一局/读档/重开世界：所有面板要重新绑定并重绘。
signal session_ready(session: GameSession)
