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

Start with the smallest useful end-to-end increment. Split independent work
into parallelizable chunks wherever write sets, resources, and shared contracts
genuinely allow: parallelism is the goal whenever it is safe, not an exception
that needs justifying. Establish shared interfaces, types, schemas, and
migrations as their own earlier tasks so their consumers can then run
concurrently. Keep tasks sequential when they touch the same files, the same
types, the same migration, or the same core behavior; a shared write is a hard
serialization, not a risk to weigh. Name each safe parallel group and the exact
write-set boundary that makes it safe. Phases run in order; inside a phase, fan
out every group that qualifies. State prerequisites, gate conditions, and
protected paths explicitly; check for cycles and missing prerequisites.

Every task must be narrow, independently understandable, decision-complete,
and implementable cold. Repeat essential context in the task itself at the
depth described in "Write for a less capable implementer" below. Give each task
exact write ownership, dependencies, approach rationale, concrete
implementation steps carrying the real code or content they write, required
validation, and observable done criteria. Each task ends with passing
validation and leaves the repository working. Do not use placeholders such as
`TBD`, `TODO`, “same as above,” undefined symbols, or “add appropriate tests.”

For behavior changes, keep RED/GREEN/REFACTOR inside the same task boundary:
write the smallest meaningful regression check, run the exact minimal command
and observe the named expected failure, quoting the error text or failure
reason so the implementer can tell an intended RED from a fixture, path, or
tooling failure, implement the smallest change, run the same command to green,
then refactor only while green and rerun the check. No intentionally
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

## Write for a less capable implementer

Set the detail bar here: a less capable model must be able to implement any
single task cold, from that task's text alone, making zero design decisions and
rediscovering no repository facts beyond the context that task states. Every
guideline below serves that bar.

Give reasoning, not only steps. Each task states why the change takes this
shape: the approach and the alternative it rules out, the existing pattern,
interface, or convention it copies, and the specific failure modes to avoid. An
implementer that understands intent adapts correctly; one that only
pattern-matches the surface text produces plausible wrong code.

Show code and content instead of describing them. Every code-touching step
carries a representative block — exact signatures, types, schemas, test bodies,
config keys, or before/after content — complete enough to adapt directly rather
than reinvent. Mark a block illustrative when it is a shape to follow and exact
when it must be written verbatim. Use exact paths, symbols, and command lines
everywhere. Prose such as "add appropriate error handling," "validate the
input," or "write tests for the above" is a defect: name the errors, the
validation rules, and the test cases instead. Include concrete examples of
expected behavior — real inputs with their exact outputs, including empty,
boundary, and error cases — wherever behavior could be read more than one way.

Make every task readable cold and out of order. Restate inside the task the
repository facts and shared-contract details it depends on: the signature or
schema an earlier task introduces, the current relevant content of a file being
modified, the convention being followed, the working directory a command needs.
Never point at another task's body for content; repeat it. "Same as above,"
"similar to Task N," and symbols defined nowhere in the plan are defects.

State the expected failure observation for every RED step: the exact command,
the named test, and the error text or failure reason to expect before
implementing, plus what a different failure means — a setup, path, or fixture
problem rather than the behavior under test.

None of this detail is execution mechanics. It describes what to build and why;
it never says who implements a task, with which agent, model, or backend, or
how the work is coordinated, reviewed, or committed.

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
<sequential phases; each named safe parallel group with the disjoint write set that makes it safe, or none with the reason; contract-establishing tasks that unlock fan-out; shared resources and protected paths; the exact shared file, type, migration, or behavior forcing each serialized dependency>

### 5. Phases
<for each phase: goal, included task IDs, prerequisites, observable working increment, validation gate and parallel safety>

### 6. Task Breakdown

#### Phase 1 Tasks: <phase name>

##### Task 1.1: <specific outcome; label docs-only/test-only/investigation-only when applicable>

Touches: `<exact write path>`, `<exact write path>`

**Goal:** <one observable outcome>

**Approach:** <why the change takes this shape: the existing pattern, interface, or convention it follows, the alternative ruled out, and the failure modes to avoid>

**Parallelization:** <exact task IDs this may run beside plus the disjoint write sets and resources that make that safe, or sequential naming the exact shared file, type, migration, or behavior that forces serialization>

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
- [ ] <one concrete action per step, carrying the actual code, schema, or content it writes — labeled illustrative or exact — plus the restated repo facts it relies on>
- [ ] <for behavior changes: add the specified regression test with its body, run the exact minimal command and observe the named expected failure quoting its error text, note that any other failure is a setup problem, implement, rerun the same command to green, then refactor while green; each action gets its own checkbox>
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
- [ ] Every task is implementable cold: stated approach rationale, real code/content, restated dependencies, and expected RED failure text.
- [ ] Independent work is parallelized wherever safe, with named groups and disjoint write sets.
- [ ] Phase/task grammar, unique IDs, dependency order and parallel safety are consistent.
- [ ] No placeholders, unresolved implementation decisions or execution-process instructions remain.

### 10. Risks, Tradeoffs, And Follow-Ups
<real risks, chosen tradeoffs and rationale, bounded deferred work that does not block acceptance>
````

## Final authoring gate

Before returning the plan, confirm that it covers the requested scope and
exclusions; names concrete interfaces, paths, content, and commands; maps every
requirement to a task and acceptance check; and resolves all consequential
choices in a `SUCCESS` plan. Confirm that every task carries its approach
rationale, the real code or content its steps write, the restated context it
depends on, and the expected failure text for each RED step, so a less capable
implementer could complete it cold. Confirm task nesting and unique IDs,
passing task boundaries, dependency and resource consistency, parallel groups
named with the disjoint write sets that make them safe, and exact
test-to-requirement mapping. Confirm that no runtime state, secrets, generated
artifacts, vague steps, unbounded scope, or execution mechanics leaked into the
plan. Confirm that the ten numbered sections and required phase/task heading
grammar are intact.
