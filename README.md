# Usage counts

Written daily by `.github/workflows/collect-usage.yml` on `main`.
`usage.csv`: per day, workflow, outcome and channel, the total number of runs
so far (the download count of its file in the `usage-counter` release).
- outcome: `proposed` (files in the suggestion PR), `nothing`, `failed`;
- channel: `release` (a released version, `@vX`), `dev` (`@main` or a branch:
  development and testing).
The runs in a period are the difference between its last and first day.
