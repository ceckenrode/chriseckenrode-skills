---
name: ce-plan
description: Use when the user requests a detailed written plan. Do not use for casual mentions of planning, quick outlines, or requests to implement an existing plan.
---

# Detailed Plan Authoring

Create a complete, implementation-ready written plan when the user asks for a
detailed plan, focused on the requested outcome and on the repository facts
that make it safe to implement.

## Establish the facts and clarify blockers

When the repository states product intent — a requirements or product document,
a spec, or the issue this change implements — read it first and anchor goals,
non-goals, and public contracts to it. Name any intentional divergence and mark
the plan `PARTIAL` unless the user asked to change product behavior; when the
change alters product behavior, include a task updating it.

Read applicable repository instruction files and inspect the relevant code,
tests, documentation, configuration, and architecture. Answer from repository
evidence how current behavior, interfaces, conventions, persistence, lifecycle,
errors, boundaries, compatibility, and existing validation work today, and
distinguish that from what the requested change should produce.

Map each requirement to an owned file responsibility and to an observable
acceptance check. Settle every interface the plan defines as a contract —
preconditions, postconditions, and invariants in the project's own type and
validation vocabulary — along with inputs and outputs, failure and empty cases,
migration or compatibility behavior, and ordering constraints. Make invalid
states unrepresentable: discriminated unions over optional fields, validation
pushed to the boundary so interior code trusts its inputs, interfaces kept
simple even when the implementation absorbs the complexity. Give exact
repo-relative paths, symbols, signatures, schemas,
representative code, or concrete before/after content whenever prose could
allow incompatible implementations.

Resolve an uncertain approach before the plan commits to it. A spike is bounded
and throwaway, never promoted, and its only output is the decision the plan
then states; this skill authors plans rather than code, so an approach that
cannot be settled from repository evidence becomes an explicitly labeled
investigation-only task, or a `PARTIAL` blocker when consequential.

Ask at most one batch of up to three questions, and only for consequential
decisions that cannot be discovered and whose absence blocks correctness; put
reasonable nonblocking defaults and their rationale in Assumptions. Never hide
an unresolved consequential choice: a `SUCCESS` plan has none, a `PARTIAL` plan
names the blocker and the tasks it prevents, and a request carrying no usable
description of a change returns `ERROR`.

## Save or return the plan

Save every plan by default at `docs/plans/YYYY-MM-DD-NN-kebab-slug.md`, using
the current local date, a lowercase ASCII hyphenated slug, and the first unused
two-digit sequence from `01`; create the directory when needed and never
overwrite an existing plan. An explicit user path takes precedence, an explicit
request to keep the plan in chat replaces saving, and saving reports the exact
path and a concise outcome. Do not begin implementation or offer a separate
execution workflow after authoring the plan.

## Design phases and tasks

Start with a tracer bullet: one entity, one route, one surface wired end to end
through every layer, deployable and demonstrable however thin. Expand
horizontally only after that vertical slice runs, and end every phase with
software that runs rather than groundwork alone. Plan the correct design rather
than the fastest patch — a plan that encodes a shortcut hands the implementer
debt they cannot see — while adding no speculative abstraction or unrelated
refactor.

Split independent work into parallel groups wherever write sets, resources, and
shared contracts genuinely allow: parallelism is the goal whenever it is safe,
not an exception that needs justifying. Establish shared interfaces, types,
schemas, and migrations as their own earlier tasks so their consumers can then
run concurrently. A shared file, type, migration, or core behavior is a hard
serialization, not a risk to weigh. Phases run in order; inside a phase, fan
out every group that qualifies, naming the exact write-set boundary that makes
each one safe, stating prerequisites, gates, and protected paths, and checking
for cycles and missing prerequisites.

Every task must be atomic and committable, independently understandable,
decision-complete, and implementable cold: one responsibility, one narrow write
set, and one validation that independently proves it done. A task whose
completion cannot be proven by its own check is too vague — split it or sharpen
it. Each task ends with passing validation and leaves the repository
working.

For behavior changes, keep RED/GREEN/REFACTOR inside the same task boundary:
write the smallest meaningful regression check, run the exact minimal command
and observe the named expected failure of the named test — quoting the error
text so the implementer can tell an intended RED from a fixture, path, or
tooling failure — implement the smallest change, run the same command to green,
then refactor only while green and rerun the check. No intentionally failing
enforced check may cross a task boundary: a task that establishes a shared
contract ahead of dependent work reaches green inside its own boundary through
passing characterization tests, pending or skipped tests where repository
convention supports them, or a minimal compatible implementation. Documentation,
configuration, and test-only work use appropriate passing validation without
manufacturing a RED step: a build that succeeds, a script that runs, or a
command whose exact expected output is named; investigation-only reproduction
has a separate passing evidence check and does not enforce a known failure.

Plans specify exact validation commands, working directories, prerequisites,
fixtures, and expected results; commands that verify the implementation are
required, while commands that select an implementation runner, coordinate
workers, publish commits, or otherwise describe execution mechanics do not
belong in the generated plan, nor do companion skill lists, agent, model, or
backend assignments, participant or reviewer roles, or review/fix processes.
Detail about what to build and why is never execution mechanics: the exclusion
covers only who implements a task and how work is coordinated, reviewed, or
committed.

## Write for a less capable implementer

Set the detail bar here: a less capable model must be able to implement any
single task cold, from that task's text alone, making zero design decisions and
rediscovering no repository facts beyond the context that task states.

Give reasoning, not only steps. Each task states why the change takes this
shape: the approach and the alternative it rules out, the existing pattern,
interface, or convention it copies, and the specific failure modes to avoid. An
implementer that understands intent adapts correctly; one that only
pattern-matches the surface text produces plausible wrong code.

Show code and content instead of describing them. Every code-touching step
carries a representative block — exact signatures, types, schemas, test bodies,
config keys, or before/after content — complete enough to adapt directly,
labeled illustrative when it is a shape to follow and exact when it must be
written verbatim. Prose such as "add appropriate error handling," "validate
the input," or "write tests for the above" leaves the work implicit and is a
defect: name the errors, the validation rules, and the test cases instead.
State expected behavior as examples — real inputs with the exact values they
return, empty, boundary, and error cases included — and reuse those examples as
the named test cases in the Testing Plan.

Make every task readable cold and out of order. Restate inside the task the
repository facts and shared-contract details it depends on — the signature or
schema an earlier task introduces, the current relevant content of a file being
modified, the convention being followed, the working directory a command needs,
the error text to expect before implementing and what a different failure would
mean — and leave out what it does not depend on; task context is scoped, never
a codebase dump. Never point at another task's body for content; repeat it.
"Same as above," "similar to Task N," `TBD`, `TODO`, and undefined symbols are
defects.

## Required output

Use the following structure, replacing every angle-bracket placeholder; they
are part of the format only. Do not add an eleventh execution-notes section,
and keep the final checklist to content and result checks — no participants,
stages, loops, fix cycles, or handoffs.

````markdown
# <Feature Name> Implementation Plan

**Goal:** <one sentence>

**Architecture:** <two or three sentences>

**Tech Stack:** <languages, frameworks, tools relevant to the change>

### 1. Summary
<requested outcome, user value, scope/exclusions, success criteria, product source of truth and the constraints it imposes>
Status: SUCCESS — ready to implement.
<Use PARTIAL with specific blockers when correctness decisions remain unresolved, or ERROR when the request carries no usable description of a change.>

### 2. Assumptions
<specific defaults and their rationale; none if no assumptions>

### 3. Repo Context
<only the context this change needs, not a repository survey: relevant paths, existing patterns/interfaces, project rules, known validation commands>

### 4. Plan Overview
<chosen design, important flow/integration points, dependency graph, critical path and initially ready tasks>

#### Parallel Execution Notes
<sequential phases; each named safe parallel group with the disjoint write set that makes it safe, or none with the reason; contract-establishing tasks that unlock fan-out; shared resources and protected paths; the exact shared file, type, migration, or behavior forcing each serialized dependency>

### 5. Phases
<for each phase: goal, included task IDs, prerequisites, the demoable working increment it leaves running, validation gate and parallel safety>

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
- [ ] <observable behavior as concrete input/output examples, with preconditions, postconditions, invariants and boundaries>
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
<every created/modified/deleted path, responsibility, concrete interface/content change with its preconditions, postconditions and invariants, change category and owning task ID; shared paths serialized>

### 8. Testing Plan
<map acceptance criteria to exact unit/integration/regression/manual checks, reusing the plan's behavior examples as named cases, with working directories, fixtures/prerequisites and expected results; label inapplicable categories>

### 9. Review And Verification Checklist
- [ ] Every requirement maps to an implemented task and an acceptance check; each task has a concrete Requirements Checklist and explicit write scope.
- [ ] Each phase leaves running, demonstrable software rather than groundwork.
- [ ] Interfaces state preconditions, postconditions and invariants; expected behavior appears as concrete input/output examples.
- [ ] Behavior-changing tasks complete RED/GREEN/REFACTOR inside the same task, and no task ends with an intentionally failing enforced check.
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

Before returning the plan, confirm it satisfies its own Review And Verification
Checklist, that the ten numbered sections and phase/task heading grammar are
intact, and that no runtime state, secrets, generated artifacts, vague steps,
unbounded scope, or execution mechanics leaked into it.

Then read the draft adversarially, as a hostile senior engineer would: hunt
unhandled edge cases, failure and error paths, boundary and compatibility gaps,
examples that contradict the stated contracts, and any task that still hides a
design decision. Fix what that pass finds before returning. This critique
belongs to authoring alone; the returned plan carries no review or fix process
of its own.
