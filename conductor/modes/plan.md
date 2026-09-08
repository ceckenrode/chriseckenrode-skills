# Planning

When neither the new request nor the inherited configuration selects a planning
model or worker, the lead/orchestrator plans with its current model and reasoning
effort. Do not ask the user to configure that default. An explicitly named model
is honored even when it matches the current model, and an explicit effort is
preserved. When a planning worker is selected, that worker owns architectural
decisions and synthesis within the accepted scope; the lead
steers scope and accepts or corrects the resulting plan.

## Plan detail

Honor an explicit `lite` or `detailed` request. Otherwise choose the appropriate
detail from complexity, risk, and dependencies, and record that choice. A lite
plan remains actionable: state the outcome, scope and exclusions, ordered steps,
material dependencies, and verification checks with pass criteria. It may omit a
full dependency graph, exhaustive signatures, and tracer-bullet slices when those
would add no value for a small, low-risk task. A detailed plan keeps the rigor
below where it helps implementation correctness.

Plan for an implementer with less capability and context than the orchestrator. Make design decisions explicit enough that correct execution depends on following the plan, not reconstructing your reasoning. Use the user's format or project conventions; scale detail to uncertainty and risk rather than adding boilerplate.

1. Identify intended behavior, constraints, existing decisions, and acceptance criteria.
2. For an authorized planning or exploration run, apply the bounded internal-exploration guidance in [exploration](../references/exploration.md): automatically select focused, read-only small-model workers to navigate and absorb raw context, then return distilled, anchored findings and material risks. A selected planning worker may use those findings to make architectural decisions; follow up only on unknowns that affect the plan. Help and bare usage remain non-dispatching.
3. Synthesize findings into a direction. The planning owner weighs proposed approaches, makes creative and architectural decisions, and distinguishes current behavior from intended behavior. The lead steers scope and accepts the result. Resolve contradictions through targeted worker questions or a user decision; record assumptions and rationale.
4. For detailed plans, decompose the work into a dependency graph and
   implementation-ready tasks using the contracts below. For lite plans, use an
   ordered actionable task sequence and record material dependencies. Resolve
   consequential choices before dispatch and record why the selected approach
   fits the evidence.
5. Check the complete selected configuration and approval checkpoints against
   [workflow setup](../references/workflow.md) before handing off the plan. Do
   not begin a later stage with unresolved settings.

If plan review is selected, send the plan to that stage after this gate; do not
skip it merely because implementation is ready. In plan-only mode, verify the
plan and leave the next selected stage explicit in the handoff.

## Tracer-bullet slices

For detailed plans, organize implementation as thin end-to-end vertical slices
that connect the relevant layers and produce observable working behavior after
each slice. The first slice proves the minimal real path; later slices expand
capability. Do not call a horizontal service/UI split a slice. Add shared
scaffolding first only when truly necessary. Each slice names its observable
outcome, write ownership, off-limits scope, dependencies, and meaningful
same-task red → green check where applicable, and leaves the repository working.
For lite plans, use a compact ordered task sequence when full slices would add no
useful precision, while retaining boundaries and checks.

Independent slices may run in parallel when their writes and resources are
disjoint; coupled slices remain ordered.

## Parallel task graph

For detailed plans, design the slice dependency graph and define shared
interfaces before assigning consumers. Put required shared scaffolding or schema
changes in prerequisite tasks; avoid concurrent edits to the same files or
shared generated artifacts. A lite plan still names any material dependency and
the owner of shared contracts.

In detailed plans, give every slice/task a stable ID and record `depends_on`,
`blocks`, write ownership, and the verification gate that releases its
dependents. Include an ordered slice table and parallel waves, for example:
`S1 (submit → persist → display) → [S2 (edit), S3 (history)] → S4 (sync)`.
Explain why each dependency exists; `blocks` must agree with downstream
`depends_on` entries.

For detailed plans, check the graph for cycles, missing prerequisites, overlapping
writes within a wave, and shared test/build resources that need isolation or
serialization. Identify the critical path and tasks ready at the start. Waves
describe valid ordering, not a requirement to wait for unrelated work before
starting a newly ready independent slice.

## Task contract

For detailed plans, include each applicable item; mark an item inapplicable when
its omission could be mistaken for missing work. Lite plans may use a compact
version of this contract, but must still cover outcome, boundaries, ordered
implementation, material behavior, and verification:

- **Outcome and boundaries:** intended behavior, acceptance criteria, exclusions, dependencies, and owned files/modules with known extension points.
- **Design:** chosen architecture, exact names and type/function signatures, data shapes, validation, state transitions, and persistence/migration behavior. Name existing components and patterns to reuse. Explain non-obvious tradeoffs.
- **Behavior:** concrete inputs/outputs, error and edge cases, compatibility requirements, and relevant concurrency or lifecycle rules. For UI, specify layout/components, exact copy, loading/empty/error states, and accessibility behavior.
- **Implementation:** ordered changes, representative code, call sites, or before/after examples wherever prose leaves room for incompatible interpretations. Keep examples consistent with discovered APIs; label pseudocode and unverified assumptions clearly.
- **Ownership and integration:** explicit owner for shared contracts and explicit integration owner for combining work, resolving conflicts, and judging the combined state. Name off-limits paths and preserve unrelated changes.
- **Verification gates:** exact commands, working directory, prerequisites/fixtures, and observable pass criteria for task checks and combined acceptance. Include required project checks and relevant behavioral tests. State which dependencies remain blocked until each gate passes; individual task passes do not replace the combined-state gate.

For example, a boundary requirement should be as concrete as: "Add `parseCount(input: string): number | null`; accept integers 1–100, return `null` for blank, decimal, or out-of-range input; cover `1`, `100`, `0`, `101`, `1.5`, and an empty string." Use the actual task's signatures and cases, not this illustrative API.

## Resolve risky assumptions

When an uncertain API, interaction, or architecture choice could invalidate the plan, delegate a small prototype or experiment before finalizing that choice. Define the question and pass criterion, bound the experiment to scratch artifacts, and request results plus the artifact path. Distinguish tested prototype behavior from illustrative code; production implementation remains a separate authorized phase.

A worker returning `NEEDS_DECISION` should supply the missing fact or choice and its consequences. Resolve it through targeted investigation or lead judgment; ask the user only when it changes their intended scope or requires their preference.

Save the plan using the location precedence in the bundled context reference: explicit path, the user's established plan location, then the run's temporary folder. A small plan can remain short, but it still records ordering, gates, and the tasks that can run together.

Planning is complete when every task has an actionable design or compact step,
acceptance criteria, and runnable or explicitly blocked verification gates. Check
that no consequential choice is left for an implementer to invent. Delegate
investigation only for gaps that prevent that. Write a handoff naming the actual
next selected stage, with the initial ready tasks and blockers. If plan review is
selected, continue there; otherwise, when no implementation is selected, verify
and report the plan, and when implementation is selected, continue to execution
under the main workflow's checkpoint policy.
