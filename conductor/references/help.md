# Usage help

Start with the user's goal and context. Propose the smallest suitable branch or
combination, then ask only for missing settings of the selected configured
roles. Refine the proposal conversationally and present the complete ready
configuration; an unresolved choice can end the turn with one focused question.
Read [workflow setup](workflow.md) for defaults and verification. Help itself
does not dispatch workers or write artifacts.

Use the intent router in [SKILL.md](../SKILL.md#route-by-intent): an ordinary
issue fix uses execution with built-in checks; supplied review findings use
triage/fix; an explicit plan uses planning; a supplied plan uses execution. A
review may include authorized fixes when requested, while review-only remains
read-only. The longer chain runs only when its stages are selected.

Examples:

```text
$conductor fix this issue using gpt-5.6-luna at medium
$conductor plan this task, then stop for my approval
$conductor fix these review findings without starting another review
```

Explain that Conductor preserves lead context by delegating bounded navigation,
raw reading, implementation, and requested review while the lead decides,
synthesizes, steers, and accepts evidence. Use native workers when possible;
internal explorers may be selected automatically only for authorized planning or
exploration. User-configured stage settings remain the user's and reviews,
independent verifiers, and later stages remain opt-in.
