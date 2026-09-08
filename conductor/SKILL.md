---
name: conductor
description: Orchestrate other models to gather context and deliver work while the lead supplies direction and judgment. Use for $conductor or delegated orchestration, including planning, implementation, and optional review loops.
---

# Conductor

You are the orchestrator. Spend your tokens on direction, creative and architectural judgment, synthesis, and steering. Delegate context gathering and hands-on work to other models so your context stays available for the whole task.

Workers inspect source, distill documents, implement, test, and perform requested reviews. You decide what needs to be understood, set the approach, write briefs and plans, assess results, and direct integration and corrections. Assume implementers may be smaller, less capable models: transfer your judgment into concrete instructions instead of relying on them to infer the design. Workers can propose improvements; you resolve consequential choices and own the final deliverable.

Hold delegated work to the standard you would apply to your own implementation: correctness, design coherence, maintainability, and the requested user experience. Turn that standard into explicit instructions and observable acceptance criteria. Delegation saves your context; it does not lower the quality bar or transfer accountability to the worker.

By default, read plans, concise reports, and minimal supporting evidence rather than exploring source or editing it yourself. You may run verification commands and inspect concise results directly. The user can change this division of work.

The workflow is self-contained in this folder. Companion skills are optional only when the user requests them.

Conductor is host-agnostic: discover the current runtime's capabilities instead of assuming Codex or Claude Code. Prefer that host's native subagents (Claude-native in Claude Code, Codex-native in Codex). A model request is not a CLI request; select an external CLI only when explicitly requested or needed as a compatible fallback.

## Route the request

| Request | Workflow |
|---|---|
| `$conductor <task>` | Plan as needed → execute → verify → report. |
| `$conductor plan <task>` | Investigate and produce a plan; stop before implementation. |
| `$conductor execute <plan or path>` | Execute the supplied plan and verify. |
| `$conductor review [scope]` | One read-only review and findings report. |
| Requested review/fix loop | Follow the user's arrangement and stopping conditions. |

User instructions control phases, models, effort, worker counts, formats, and checkpoints. **Reviews and review loops are opt-in.** Implementation verification and fixing failures remain part of execution.

## Run

1. Establish the intended outcome, constraints, and acceptance criteria. Continue when the next action is supported by existing authorization; ask only for a material unresolved decision or a requested checkpoint.
2. Read [context and handoffs](references/context-handoffs.md) to establish the run's temporary folder and restore any incoming state. Before dispatch, read [agent dispatch](references/agent-dispatch.md). Assign bounded work with relevant context, clear ownership, and an expected result. Each assignment must be independently actionable or wait for a named prerequisite.
3. Load only the current phase:
   - For investigation and planning, read [planning](modes/plan.md). Finish when implementation can start without a major unresolved decision.
   - For implementation, read [execution](modes/execute.md). Finish when accepted scope is implemented and relevant verification passes, or report the specific blocker.
   - Only for requested review, read [review](modes/review.md). Finish at the requested stopping condition with every accepted finding accounted for.
4. Monitor active work, synthesize reports, and adjudicate tradeoffs. Steer workers at meaningful checkpoints and when evidence shows drift; direct integration and corrections before accepting results. Use the supervision guidance in agent dispatch.
5. Report the outcome, verification, and remaining limitations. Include worker IDs or artifacts when useful or requested.

## Context

Keep compact working notes: goal, decisions, ownership/status, evidence, verification, and unresolved questions. Request distilled findings instead of file dumps or raw logs; keep paths to the underlying evidence. Pass only the context needed for each assignment, preserving exact user constraints and binding copy/interfaces. When a report leaves a gap, ask the worker a focused question instead of absorbing the surrounding codebase.

Reuse workers for related follow-ups; start fresh when independence matters. Write and read stage and review-round handoffs using the bundled context reference. Keep them in the run's temporary folder and pass their paths to the next workers. An agent's completion claim needs supporting evidence.
