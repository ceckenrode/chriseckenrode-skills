---
name: ce-plan
description: Use when the user requests a detailed written plan. Do not use for casual mentions of planning, quick outlines, or requests to implement an existing plan.
---

# Detailed Plan Authoring

Create a complete, implementation-ready written plan when the user asks for a
detailed plan. The plan must let an implementer work from one task at a time
without making product, architecture, interface, or testing-design decisions.
Keep the plan focused on the requested outcome and on the repository facts that
make that outcome safe to implement.

## Decide whether this skill applies

Use this skill for a request for a detailed written implementation plan or a
saved detailed plan. Do not use it for a casual statement that someone is
planning, a quick outline, or a request to carry out a plan that already exists.

## Establish the facts and clarify blockers

Read applicable repository instruction files and inspect the relevant code,
tests, documentation, configuration, and architecture before deciding how the
work should be divided. Use repository evidence to answer questions about
current behavior, interfaces, conventions, persistence, lifecycle, errors,
empty inputs, boundaries, compatibility, and existing validation. Distinguish
what exists now from what the requested change should produce.

Map each requirement to an owned file responsibility and to an observable
acceptance check. Settle public interfaces, inputs and outputs, failure and
empty cases, migration or compatibility behavior, and ordering constraints in
the plan. Give exact paths, symbols, signatures, schemas, representative code,
or concrete before/after content whenever prose could allow incompatible
implementations.

Ask at most one batch of up to three questions, and only for consequential
decisions that cannot be discovered and whose absence blocks correctness. Put
reasonable nonblocking defaults and their rationale in Assumptions. Never hide
an unresolved consequential choice: mark the plan `PARTIAL`, name the blocker,
and identify the tasks it prevents. A `SUCCESS` plan has no such blocker.

## Save or return the plan

For every detailed written plan request, use the current local date and save by
default at `docs/plans/YYYY-MM-DD-NN-kebab-slug.md`. Create that directory when
needed. Start the two-digit per-date sequence at `01`, choose the first unused
number, and never overwrite an existing plan. Use a concise lowercase ASCII
hyphenated slug. An explicit user path takes precedence. If the user explicitly
asks to keep the plan in chat or not to save it, do so instead of saving it.
When saving, report the exact path and a concise outcome. Do not begin
implementation or offer a separate execution workflow after authoring the plan.

## Design phases and tasks

Start with the smallest useful end-to-end increment. Establish shared
interfaces before consumers. Organize work into sequential phases unless
independent tasks truly have disjoint writes and resources. State prerequisites,
gate conditions, protected paths, and safe parallel groups explicitly; check
for cycles and missing prerequisites.

Every task must be narrow, independently understandable, decision-complete,
and implementable cold. Repeat essential context in the task itself. Give each
task exact write ownership, dependencies, concrete implementation steps,
required validation, and observable done criteria. Each task ends with passing
validation and leaves the repository working. Do not use placeholders such as
`TBD`, `TODO`, “same as above,” undefined symbols, or “add appropriate tests.”

For behavior changes, keep RED/GREEN/REFACTOR inside the same task boundary:
write the smallest meaningful regression check, run the exact minimal command
and observe the intended behavioral failure, distinguish that failure from a
fixture or tool failure, implement the smallest change, run the same command to
green, then refactor only while green and rerun the check. No intentionally
failing enforced check may cross a task boundary. Documentation, configuration,
and test-only work use appropriate passing validation without manufacturing a
RED step. Investigation-only reproduction has a separate passing evidence
check and does not enforce a known failure.

Plans specify exact validation commands, working directories, prerequisites,
fixtures, and expected results. Commands that verify the implementation are
required; commands that select an implementation runner, coordinate workers,
publish commits, or otherwise describe execution mechanics do not belong in
the generated plan. Generated plans also exclude required companion skill lists,
agent, model, or backend assignments, participant or reviewer roles, and
review/fix iteration processes.

## Required output

Use the following complete structure. Replace every angle-bracket placeholder
in an actual plan; placeholders below are part of the format only. Do not add
an eleventh execution-notes section. The final checklist is a list of
content/result checks only: it has no participants, stages, loops, fix cycles,
or handoffs.

````markdown
# <Feature Name> Implementation Plan

**Goal:** <one sentence>

**Architecture:** <two or three sentences>

**Tech Stack:** <languages, frameworks, tools relevant to the change>

### 1. Summary
<requested outcome, user value, scope/exclusions, success criteria, relevant product constraints>
Status: SUCCESS — ready to implement.
<Use PARTIAL with specific blockers instead when correctness decisions remain unresolved.>

### 2. Assumptions
<specific defaults and their rationale; none if no assumptions>

### 3. Repo Context
<relevant paths, existing patterns/interfaces, project rules, known validation commands>

### 4. Plan Overview
<chosen design, important flow/integration points, dependency graph, critical path and initially ready tasks>

#### Parallel Execution Notes
<sequential phases, safe task groups or none, shared contracts/resources, protected paths, reasons for dependencies>

### 5. Phases
<for each phase: goal, included task IDs, prerequisites, observable working increment, validation gate and parallel safety>

### 6. Task Breakdown

#### Phase 1 Tasks: <phase name>

##### Task 1.1: <specific outcome; label docs-only/test-only/investigation-only when applicable>

Touches: `<exact write path>`, `<exact write path>`

**Goal:** <one observable outcome>

**Parallelization:** <sequential or exact safe companion task IDs and resource conditions>

**Dependencies:** <none or exact prerequisite task IDs and gate releasing this task>

**Files:**
- Create: <exact paths or none>
- Modify: <exact paths and extension points or none>
- Test: <exact paths or none with reason>

**Requirements Checklist:**
- [ ] <observable behavior with concrete inputs/outputs and boundaries>
- [ ] <owned scope and explicit exclusions>
- [ ] <exact task validation and passing acceptance requirement>

**Implementation Steps:**
- [ ] <one concrete action per step; include specific code/content where needed>
- [ ] <for behavior changes: add specified regression test, run exact minimal command and observe the named expected failure, implement, rerun the same command to green, then refactor while green; each action gets its own checkbox>
- [ ] <run the exact final task gate in the specified working directory, with prerequisites/fixtures and expected result>

**Acceptance Criteria:**
- <observable result mapped to a named check, including error/boundary cases>
- <all required task validation passes and the repository remains working>

**Notes/Risks:** <specific compatibility/order constraints or none>

<Repeat tasks under their matching phase heading; the next phase starts with #### Phase 2 Tasks: and its tasks use ##### Task 2.1:>.

### 7. File-Level Plan
<every created/modified/deleted path, responsibility, concrete interface/content change, change category and owning task ID; shared paths serialized>

### 8. Testing Plan
<map acceptance criteria to exact unit/integration/regression/manual checks, working directories, fixtures/prerequisites and expected results; label inapplicable categories>

### 9. Review And Verification Checklist
- [ ] Every requirement maps to an implemented task and an acceptance check.
- [ ] Each task has a concrete Requirements Checklist and explicit write scope.
- [ ] Behavior-changing tasks complete RED/GREEN/REFACTOR inside the same task.
- [ ] No task ends with an intentionally failing enforced check.
- [ ] Targeted and combined-state checks pass; applicable build/typecheck/lint passes.
- [ ] Documentation reflects changed behavior; no unrelated edits or sensitive/runtime artifacts are included.
- [ ] Phase/task grammar, unique IDs, dependency order and parallel safety are consistent.
- [ ] No placeholders, unresolved implementation decisions or execution-process instructions remain.

### 10. Risks, Tradeoffs, And Follow-Ups
<real risks, chosen tradeoffs and rationale, bounded deferred work that does not block acceptance>
````

## Final authoring gate

Before returning the plan, confirm that it covers the requested scope and
exclusions; names concrete interfaces, paths, content, and commands; maps every
requirement to a task and acceptance check; and resolves all consequential
choices in a `SUCCESS` plan. Confirm task nesting and unique IDs, passing task
boundaries, dependency and resource consistency, safe parallelism, and exact
test-to-requirement mapping. Confirm that no runtime state, secrets, generated
artifacts, vague steps, unbounded scope, or execution mechanics leaked into the
plan. Confirm that the ten numbered sections and required phase/task heading
grammar are intact.
