---
name: ui-brand
description: Org UI conventions — apply when designing or implementing any user-facing screen.
---

# UI brand

1. **Naming**: user-facing copy names things by what people recognize (a person manages *tasks* and *lists*, not *records* or *entities*). Controls say exactly what happens ("Add task", not "Submit").
2. **States**: every list view designs its empty, loading, and error states explicitly. Errors say what went wrong and what to do next — no bare "Something went wrong".
3. **Feedback**: every mutation gives immediate visible feedback (optimistic update or spinner + toast).
4. **Accessibility**: all interactive elements keyboard-reachable with visible focus; form fields have labels; color is never the only carrier of state.
5. **Layout**: one primary action per view; destructive actions require confirmation and are never the default button.
6. **Theme**: respect the user's light/dark preference; test both.
