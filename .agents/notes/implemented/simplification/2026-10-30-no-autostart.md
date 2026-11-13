# Agent Note: 不做开机自启

Status: implemented

## Problem

早期需求里有一条开机自启（原 R3）。实现它要一条写 autostart 的补丁，加上 `%post` 往用户配置目录落文件，还要处理「用户禁用了怎么办」。

## Decision

不做。需求表里删掉该条，补丁与 `%post` 都不写。

## Alternatives considered

**用 systemd user unit 实现。** 服务化会引入启动顺序、会话总线可用性与日志归集的额外问题，而用户并不需要它。

**默认关闭但保留开关。** 多一条设置项、一条补丁与一份文档，收益是零。

## Consequences

省掉一条补丁与一段写系统目录的逻辑，验收口径只剩可启动与托盘常驻。用户若要自启，自己放一份 desktop 文件即可，不在本项目范围内。
