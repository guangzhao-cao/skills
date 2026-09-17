[English](README.md) | [中文](README.zh-CN.md)

# graceful-handoff

一个用于跨会话、跨模型、跨 CLI 和 IDE Agent 交接工作的轻量 Skill。离开的 Agent 保存必要上下文；接手的 Agent 将交接内容与当前工作区核对后完成接管。

## 安装

此 Skill 发布到仓库后，可以通过 [Skills CLI](https://skills.sh/docs/cli) 安装：

```bash
npx skills add guangzhao-cao/skills --skill graceful-handoff
```

## 使用

命令格式：

```text
/graceful-handoff <mode> ["focus"]
```

- `mode` 是必填的模式：`handoff` 表示交出当前工作，`takeover` 表示接管已有交接。
- `focus` 是可选的重点，用一句话说明希望特别关注什么，不需要填写时直接省略。

使用时替换占位内容，不要输入尖括号或方括号。例如：

结束当前会话前交接：

```text
/graceful-handoff handoff
/graceful-handoff handoff "下一位继续完善登录功能"
```

在新会话中接管：

```text
/graceful-handoff takeover
/graceful-handoff takeover "重点检查登录功能"
```

例子中的 `handoff` 和 `takeover` 就是模式，后面引号里的文字就是重点。指定“重点检查登录功能”后，Agent 会优先检查登录相关内容，同时仍会检查项目的其他必要背景和状态。

也可以直接说：“使用 graceful-handoff skill 接管当前项目，重点检查登录功能。”

只调用 `/graceful-handoff` 时，Agent 会先询问你要交接还是接管。

takeover 完成读取、核对和汇报后默认停止。如需同时授权继续实施，可以说：“使用 graceful-handoff 接管并继续工作。”如果没有交接文档，takeover 会明确告知，不创建任何文件。

## 保存内容

交接文件以 Markdown 格式保存在项目根目录的 `.handoff/` 中：

```text
.handoff/
├── handoff-1.md
├── handoff-2.md
└── handoff-3.md
```

每次交接会生成编号递增的新文件，保留历史记录；接管时自动读取编号最大的交接文件。

交接文档会整理任务目标、当前进度、已确定的决策、未解决问题和下一步，并附上必要的文件与文档引用。

## 使用时需要了解

- **已验证与据报分开**：区分本会话实际检查的事实与未重新确认的陈述。
- **检查状态漂移**：将最新交接与工作区对照，报告变化和证据不足之处；旧测试通过不代表现在仍通过。
- **按需核查**：不为生成交接而强制运行构建、测试、格式检查或类型检查。
- **保存与共享**：生成交接时会脱敏敏感信息。你可以将 `.handoff/` 随项目提交到 Git，Skill 不会自动提交或推送。

## 参考与致谢

本设计参考了以下两个项目：

- [Matt Pocock — handoff](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md)：面向全新 Agent 提供上下文、引用已有资料而非复制、下次会话重点、敏感信息脱敏和技能建议。
- [xiaomaimuchanyiyiba — agent-handoff](https://github.com/xiaomaimuchanyiyiba/agent-handoff)：持久化项目交接、历史快照、实用的启动信息，以及先读取和汇报再继续工作的接管思路。

## 许可证

[MIT](LICENSE) © 2026 Guangzhao Cao。
