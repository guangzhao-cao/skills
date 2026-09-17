[English](README.md) | [中文](README.zh-CN.md)

# graceful-handoff

A lightweight Agent Skill for handing work over across sessions, models, CLI tools, and IDE agents. The departing agent saves useful context; the receiving agent checks it against the current workspace before taking over.

## Install

Once this skill is published to the repository, install it with the [Skills CLI](https://skills.sh/docs/cli):

```bash
npx skills add guangzhao-cao/skills --skill graceful-handoff
```

## Usage

Command format:

```text
/graceful-handoff <mode> ["focus"]
```

- `mode` is required: `handoff` saves the current work for another agent, while `takeover` picks up an existing handoff.
- `focus` is optional: a short description of what deserves particular attention. Omit it when unnecessary.

Replace the placeholders without typing the angle or square brackets. For example:

Save a handoff before ending a session:

```text
/graceful-handoff handoff
/graceful-handoff handoff "Continue implementing the login feature next session"
```

Take over in a new session:

```text
/graceful-handoff takeover
/graceful-handoff takeover "Focus on reviewing the login feature"
```

In these examples, `handoff` and `takeover` are the modes; the quoted text is the focus. Focusing on the login feature means reviewing it first while still checking other necessary project context and state.

You can also ask: “Use the graceful-handoff skill to take over this project, focusing on the login feature.”

Calling `/graceful-handoff` alone prompts you to choose between handing off and taking over.

Takeover reads, checks, and reports, then stops. To authorize implementation too, ask: “Use graceful-handoff to take over and continue.” If no handoff exists, takeover reports that and creates nothing.

## What gets saved

Handoffs are saved as Markdown files in `.handoff/` at the project root:

```text
.handoff/
├── handoff-1.md
├── handoff-2.md
└── handoff-3.md
```

Each handoff creates a new file with an increasing number, preserving previous handoffs. Takeover automatically reads the file with the highest number.

A handoff captures the task goal, current progress, confirmed decisions, open issues, and next steps, with references to the files and documents needed to continue.

## What to expect

- **Verified vs. reported:** distinguish facts checked in the current session from claims that have not been reverified.
- **Drift detection:** compare the latest handoff with the workspace; report changes and gaps in evidence. An old passing test is not a current passing test.
- **Targeted checks:** no mandatory build, test, lint, or typecheck just to produce a handoff.
- **Saving and sharing:** sensitive information is redacted when creating a handoff. You can commit `.handoff/` with your project; the skill does not automatically commit or push.

## References and acknowledgements

This design draws on two projects:

- [Matt Pocock — handoff](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md): context for a fresh agent, references instead of duplicated artifacts, a next-session focus, redaction, and suggested skills.
- [xiaomaimuchanyiyiba — agent-handoff](https://github.com/xiaomaimuchanyiyiba/agent-handoff): persistent project handoffs, historical snapshots, practical startup information, and reading and reporting before continuing.

## License

[MIT](LICENSE) © 2026 Guangzhao Cao.
