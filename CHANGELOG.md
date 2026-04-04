## [1.0.0] - 2026-04-05

### Features

- add logging and message field to RestoreSubscriptionResponse (account)
- block disposable email providers on signup (account)
- normalize email on signup to prevent trial abuse via aliases (account)

### Refactoring

- replace print logs with RpcLogger, disable in production (obsidian)
- replace inline styles with CSS classes via bootstrapPlugin extraCss (obsidian)
- centralize collection names and improve restore subscription UX (account)
