# CE Plan

Use this skill when you request a detailed written implementation plan. It produces self-contained phases and tasks with concrete dependencies, file changes, and validation criteria so each task can be implemented without inventing missing design decisions.

Plans open with a tracer bullet — one thin slice wired end to end — and every phase after it leaves software running rather than groundwork. Interfaces are settled as contracts with preconditions, postconditions, and invariants, and expected behavior appears as concrete input/output examples that become the named test cases.

Tasks are written to a deliberate bar: a less capable model should be able to implement any single task cold, so each one states its approach rationale, shows the real code or content it writes, restates the context it depends on, and names the failure to expect before implementing. Independent work is split into parallel groups wherever write sets and shared contracts allow, with the boundary that makes each group safe stated explicitly.

## Use

Ask: `Write a detailed written plan for [change].`

Plans are saved by default to `docs/plans/YYYY-MM-DD-NN-kebab-slug.md`. Give an explicit path when you want the plan saved elsewhere, or explicitly ask to keep it in chat.

The [skill instructions](SKILL.md) define the complete authoring contract.
