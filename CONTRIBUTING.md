# Contributing

Use a feature branch and open a pull request against `main`. Do not commit
credentials, customer identifiers, local parameter files, logs, or deployment
outputs.

Before opening a pull request, run:

```bash
./scripts/validate.sh
```

Changes to networking, IAM, encryption, persistence, backup, image access, or
deletion behavior must also update `README.md`.

