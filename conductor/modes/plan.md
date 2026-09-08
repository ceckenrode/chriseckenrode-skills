# Planning

Plan for an implementer with less capability and context than the orchestrator. Make design decisions explicit enough that correct execution depends on following the plan, not reconstructing your reasoning. Use the user's format or project conventions; scale detail to uncertainty and risk rather than adding boilerplate.

1. Identify intended behavior, constraints, existing decisions, and acceptance criteria.
2. Delegate context gathering as focused questions about relevant documents, code, extension points, state, and tests. Request distilled, anchored findings and material risks. Follow up only on unknowns that affect the plan.
3. Synthesize findings into a direction. Weigh proposed approaches, make creative and architectural decisions, and distinguish current behavior from intended behavior. Resolve contradictions through targeted worker questions or a user decision; record assumptions and rationale.
4. Decompose the work into a dependency graph and implementation-ready tasks using the contracts below. Resolve consequential choices before dispatch and record why the selected approach fits the evidence.

## Parallel task graph

Design for concurrent implementation where the work permits it. Separate independent work by behavior/module and define shared interfaces before assigning their consumers. Put required shared scaffolding or schema changes in prerequisite tasks; avoid concurrent edits to the same files or shared generated artifacts. Keep coupled work together when splitting would create more coordination than useful parallelism.

Give every task a stable ID and record `depends_on`, `blocks`, write ownership, and the verification gate that releases its dependents. Include an ordered task table and parallel waves, for example: `T1 (shared contract) → [T2 (service), T3 (UI)] → T4 (integration)`. Explain why each dependency exists; `blocks` must agree with downstream `depends_on` entries.

Check the graph for cycles, missing prerequisites, overlapping writes within a wave, and shared test/build resources that need isolation or serialization. Identify the critical path and tasks ready at the start. Waves describe valid ordering, not a requirement to wait for unrelated work before starting a newly ready task.

## Task contract

Include each applicable item; mark an item inapplicable when its omission could be mistaken for missing work:

- **Outcome and boundaries:** intended behavior, acceptance criteria, exclusions, dependencies, and owned files/modules with known extension points.
- **Design:** chosen architecture, exact names and type/function signatures, data shapes, validation, state transitions, and persistence/migration behavior. Name existing components and patterns to reuse. Explain non-obvious tradeoffs.
- **Behavior:** concrete inputs/outputs, error and edge cases, compatibility requirements, and relevant concurrency or lifecycle rules. For UI, specify layout/components, exact copy, loading/empty/error states, and accessibility behavior.
- **Implementation:** ordered changes, representative code, call sites, or before/after examples wherever prose leaves room for incompatible interpretations. Keep examples consistent with discovered APIs; label pseudocode and unverified assumptions clearly.
- **Verification gates:** exact commands, working directory, prerequisites/fixtures, and observable pass criteria for task checks and combined acceptance. Include required project checks and relevant behavioral tests. State which dependencies remain blocked until each gate passes.

For example, a boundary requirement should be as concrete as: "Add `parseCount(input: string): number | null`; accept integers 1–100, return `null` for blank, decimal, or out-of-range input; cover `1`, `100`, `0`, `101`, `1.5`, and an empty string." Use the actual task's signatures and cases, not this illustrative API.

## Resolve risky assumptions

When an uncertain API, interaction, or architecture choice could invalidate the plan, delegate a small prototype or experiment before finalizing that choice. Define the question and pass criterion, bound the experiment to scratch artifacts, and request results plus the artifact path. Distinguish tested prototype behavior from illustrative code; production implementation remains a separate authorized phase.

A worker returning `NEEDS_DECISION` should supply the missing fact or choice and its consequences. Resolve it through targeted investigation or lead judgment; ask the user only when it changes their intended scope or requires their preference.

Save the plan using the location precedence in the bundled context reference: explicit path, the user's established plan location, then the run's temporary folder. A small plan can remain short, but it still records ordering, gates, and the tasks that can run together.

Planning is complete when every task has an actionable design, graph position, acceptance criteria, and runnable or explicitly blocked verification gates. Check that no consequential choice is left for the implementer to invent. Delegate investigation only for gaps that prevent that. Write the plan-to-execution handoff with the initial ready tasks and blockers. In plan-only mode, present the plan and handoff and stop; otherwise continue under the main workflow's checkpoint policy.
