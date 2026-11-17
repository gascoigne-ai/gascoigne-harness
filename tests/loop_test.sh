#!/usr/bin/env bash
# Tests for scripts/loop.sh, run against a scratch git repo with a fake claude.
# usage: tests/loop_test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
failures=0

# Each test gets a clean repo with one commit and a fake claude that does nothing.
scratch_repo() {
	local dir
	dir=$(mktemp -d)
	git -C "$dir" init -q
	git -C "$dir" config user.email test@example.invalid
	git -C "$dir" config user.name test
	mkdir -p "$dir/.harness/tasks" "$dir/bin"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/bin/claude"
	chmod +x "$dir/bin/claude"
	echo logs/ >"$dir/.gitignore"
	touch "$dir/.harness/tasks/.gitkeep"
	git -C "$dir" add -A
	git -C "$dir" commit -q -m "chore: init"
	echo "$dir"
}

run_loop() {
	local dir=$1
	shift
	(cd "$dir" && CLAUDE="$dir/bin/claude" VERIFY_CMD=true "$here/scripts/loop.sh" "$@" 2>&1)
}

# Bug: pending() ended with `[[ ... ]] && echo`, so under set -e the script exited 1 silently
# whenever the last task file (sorted) was not `status: todo`.
test_dry_run_lists_todo_when_last_task_is_not_todo() {
	local dir output
	dir=$(scratch_repo)
	printf 'status: todo\n\n# first\n' >"$dir/.harness/tasks/001-first.md"
	printf 'status: blocked\n\n# second\n' >"$dir/.harness/tasks/002-second.md"
	output=$(run_loop "$dir" --dry-run) || {
		echo "FAIL ${FUNCNAME[0]}: exit $?: $output"
		failures=$((failures + 1))
		return
	}
	[[ $output == *001-first.md* && $output != *002-second.md* ]] || {
		echo "FAIL ${FUNCNAME[0]}: unexpected output: $output"
		failures=$((failures + 1))
		return
	}
	echo "ok   ${FUNCNAME[0]}"
}

test_dry_run_reports_no_pending_when_none_are_todo() {
	local dir output
	dir=$(scratch_repo)
	printf 'status: blocked\n\n# only\n' >"$dir/.harness/tasks/001-only.md"
	output=$(run_loop "$dir" --dry-run) || {
		echo "FAIL ${FUNCNAME[0]}: exit $?: $output"
		failures=$((failures + 1))
		return
	}
	[[ $output == "no pending tasks" ]] || {
		echo "FAIL ${FUNCNAME[0]}: unexpected output: $output"
		failures=$((failures + 1))
		return
	}
	echo "ok   ${FUNCNAME[0]}"
}

test_dry_run_lists_todo_when_last_task_is_not_todo
test_dry_run_reports_no_pending_when_none_are_todo
exit $((failures > 0))
