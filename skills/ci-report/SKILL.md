---
name: ci-report
description: Weekly report on where continuous-integration time goes. Use at least once a week, or when asked why CI is slow. Reports only; changes nothing.
---

# Continuous-integration report

1. Pull the last 150 runs: `gh run list --limit 150 --json databaseId,createdAt`, then
   `gh run view <id> --json jobs` for each.
2. Split every job's time into three parts, in seconds:
   - queue: waiting for a machine (job `startedAt` minus `createdAt`).
   - setup: checkout, installing dependencies, restoring the cache (the steps before the task).
   - task: the real work (build, test, lint).
3. Average each part per job name. Pick the 5 slowest jobs.
4. Report first, as a table: job, queue, setup, task, total. Add one plain sentence per job on
   where the time goes.

Never change a workflow, a cache or a runner in this skill. Proposals go in the report; the user
decides.
