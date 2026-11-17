#!/usr/bin/env bash
# Tests for scripts/loop.sh against a scratch git repo and a fake claude.
# The fake reads FAKE_DIR: design.txt (reply of the plan phase), action.<n> (shell run in the working
# directory on the n-th implement call, default none), reply.txt (final text of an implement call).
# usage: tests/loop_test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_fake_claude() {
	cat >"$1" <<'FAKE'
#!/usr/bin/env bash
# Fake claude: prints the JSON result a headless run would.
set -euo pipefail
cat >/dev/null # prompt on stdin
plan=false
for arg in "$@"; do [[ $arg == plan ]] && plan=true; done
if $plan; then
	text=$(cat "$FAKE_DIR/design.txt" 2>/dev/null || printf '## Model\nModel: unchanged')
else
	count=$(($(cat "$FAKE_DIR/count" 2>/dev/null || echo 0) + 1))
	echo "$count" >"$FAKE_DIR/count"
	if [[ -f $FAKE_DIR/action.$count ]]; then bash "$FAKE_DIR/action.$count"; fi
	text=$(cat "$FAKE_DIR/reply.txt" 2>/dev/null || printf 'did it\nRESULT: done')
fi
jq -n --arg text "$text" '{session_id: "session-1", is_error: false, result: $text}'
FAKE
	chmod +x "$1"
}

# new_repo sets globals: repo (a scratch repo) and fake_dir (state of the fake claude).
new_repo() {
	local dir
	dir=$(mktemp -d -p "$tmp")
	dir="$dir/repo"
	mkdir -p "$dir/.harness/tasks" "$dir/src" "$dir/docs"
	git init -q -b main "$dir"
	git -C "$dir" config user.email test@example.invalid
	git -C "$dir" config user.name test
	printf 'logs/\n' >"$dir/.gitignore"
	touch "$dir/.harness/tasks/.gitkeep" "$dir/src/.gitkeep" "$dir/docs/.gitkeep"
	git -C "$dir" add -A
	git -C "$dir" commit -q -m "chore: init"
	fake_dir=$(mktemp -d -p "$tmp")
	make_fake_claude "$fake_dir/claude"
	repo=$dir
}

# add_task <repo> <name> [header lines...]: body is "# Title <name>". status: todo is added first.
add_task() {
	local dir=$1 name=$2
	shift 2
	{
		echo "status: todo"
		for line in "$@"; do echo "$line"; done
		printf '\n# Title %s\n\nGoal: test.\nModel: unchanged\n' "$name"
	} >"$dir/.harness/tasks/$name.md"
	git -C "$dir" add -A
	git -C "$dir" commit -q -m "chore: add $name"
}

# loop <repo> [args]: runs loop.sh in the repo; output in $output, status in $status.
loop() {
	local dir=$1
	shift
	status=0
	output=$(cd "$dir" && FAKE_DIR=$fake_dir CLAUDE=$fake_dir/claude VERIFY_CMD=${VERIFY_CMD:-true} \
		"$here/scripts/loop.sh" "$@" 2>&1) || status=$?
}

pass() { echo "ok   $1"; }
fail() {
	echo "FAIL $1: $2"
	echo "$output" | sed 's/^/     | /'
	failures=$((failures + 1))
}
# expect <test name> <description> <condition command...>
expect() {
	local name=$1 what=$2
	shift 2
	if ! "$@" >/dev/null 2>&1; then
		fail "$name" "$what"
		return 1
	fi
}
subject() { git -C "$1" log -1 --format=%s "$2"; }
body() { git -C "$1" log -1 --format=%B "$2"; }
ahead() { git -C "$1" rev-list --count "main..$2"; }
has_branch() { git -C "$1" show-ref -q --verify "refs/heads/$2"; }
branch_has_file() { git -C "$1" cat-file -e "$2:$3"; }

# Bug: pending() ended with `[[ ... ]] && echo`, so under set -e the script exited 1 silently
# whenever the last task file (sorted) was not `status: todo`.
test_dry_run_lists_todo_when_last_task_is_not_todo() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-first
	printf 'status: blocked\n\n# second\n' >"$dir/.harness/tasks/002-second.md"
	loop "$dir" --dry-run
	[[ $status == 0 && $output == *001-first.md* && $output != *002-second.md* ]] && pass "$n" || fail "$n" "status=$status"
}

test_dry_run_skips_future_and_blocked_dependencies() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-now "not_before: 2000-01-01"
	add_task "$dir" 002-later "not_before: 2999-01-01"
	add_task "$dir" 003-after "depends_on: 001-now"
	loop "$dir" --dry-run
	[[ $status == 0 && $output == *001-now.md* && $output != *002-later* && $output != *003-after* ]] \
		&& pass "$n" || fail "$n" "status=$status"
}

test_task_runs_in_a_worktree_and_leaves_the_checkout_alone() {
	local n=${FUNCNAME[0]} dir head
	new_repo; dir=$repo
	add_task "$dir" 001-one "commit: feat(core): add the thing" "scope: src/**"
	echo "touch src/thing.go" >"$fake_dir/action.1"
	head=$(git -C "$dir" rev-parse HEAD)
	loop "$dir"
	expect "$n" "exit 0 (status=$status)" test "$status" == 0 || return
	expect "$n" "branch loop/001-one has one commit" test "$(ahead "$dir" loop/001-one)" == 1 || return
	expect "$n" "subject from commit header" test "$(subject "$dir" loop/001-one)" == "feat(core): add the thing" || return
	expect "$n" "trailer" grep -q '^Co-Authored-By: ' <(body "$dir" loop/001-one) || return
	expect "$n" "body names the task" grep -q '^Task: 001-one$' <(body "$dir" loop/001-one) || return
	expect "$n" "file committed" branch_has_file "$dir" loop/001-one src/thing.go || return
	expect "$n" "task file deleted on the branch" bash -c "! git -C '$dir' cat-file -e loop/001-one:.harness/tasks/001-one.md" || return
	expect "$n" "invoking checkout HEAD unchanged" test "$(git -C "$dir" rev-parse HEAD)" == "$head" || return
	expect "$n" "invoking checkout clean" test -z "$(git -C "$dir" status --porcelain)" || return
	expect "$n" "worktree removed" test ! -d "$dir-loop-001-one" || return
	pass "$n"
}

test_blocked_result_commits_nothing_and_keeps_the_worktree() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one
	printf 'cannot\nRESULT: blocked needs a core change' >"$fake_dir/reply.txt"
	echo "touch src/half.go" >"$fake_dir/action.1"
	loop "$dir"
	expect "$n" "exit 1" test "$status" == 1 || return
	expect "$n" "no commit on the branch" test "$(ahead "$dir" loop/001-one)" == 0 || return
	expect "$n" "worktree kept" test -d "$dir-loop-001-one" || return
	expect "$n" "reason printed" grep -q 'needs a core change' <<<"$output" || return
	pass "$n"
}

test_verify_failure_retries_once_with_the_session() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one
	echo "true" >"$fake_dir/action.1"
	echo "touch fixed.txt" >"$fake_dir/action.2"
	VERIFY_CMD="test -f fixed.txt" loop "$dir"
	expect "$n" "exit 0 (status=$status)" test "$status" == 0 || return
	expect "$n" "second attempt fixed it" branch_has_file "$dir" loop/001-one fixed.txt || return
	pass "$n"
}

test_two_verify_failures_fail_the_task_and_the_loop_goes_on() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-bad
	add_task "$dir" 002-good
	echo "touch only-good.txt" >"$fake_dir/action.3" # calls 1 and 2 serve 001-bad, call 3 serves 002-good
	VERIFY_CMD="test -f only-good.txt" loop "$dir"
	expect "$n" "exit 1 (a task failed)" test "$status" == 1 || return
	expect "$n" "failed task: no commit" test "$(ahead "$dir" loop/001-bad)" == 0 || return
	expect "$n" "failed task: worktree kept" test -d "$dir-loop-001-bad" || return
	expect "$n" "next task committed" test "$(ahead "$dir" loop/002-good)" == 1 || return
	pass "$n"
}

test_out_of_scope_change_fails_the_task() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "scope: docs/**"
	echo "touch src/stray.go" >"$fake_dir/action.1"
	loop "$dir"
	expect "$n" "exit 1" test "$status" == 1 || return
	expect "$n" "no commit" test "$(ahead "$dir" loop/001-one)" == 0 || return
	expect "$n" "message names the file" grep -q 'src/stray.go' <<<"$output" || return
	pass "$n"
}

test_feature_task_without_a_test_in_the_diff_fails() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "kind: feature"
	echo "touch src/thing.go" >"$fake_dir/action.1"
	loop "$dir"
	expect "$n" "exit 1" test "$status" == 1 || return
	expect "$n" "no commit" test "$(ahead "$dir" loop/001-one)" == 0 || return
	expect "$n" "says why" grep -q 'no test' <<<"$output" || return
	pass "$n"
}

test_feature_task_with_a_test_passes() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "kind: feature"
	echo "touch src/thing.go src/thing_test.go" >"$fake_dir/action.1"
	loop "$dir"
	expect "$n" "exit 0 (status=$status)" test "$status" == 0 || return
	expect "$n" "committed" test "$(ahead "$dir" loop/001-one)" == 1 || return
	pass "$n"
}

test_design_without_a_model_section_fails_before_implementation() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "kind: feature"
	printf 'just some thoughts' >"$fake_dir/design.txt"
	loop "$dir"
	expect "$n" "exit 1" test "$status" == 1 || return
	expect "$n" "implement never ran" test ! -f "$fake_dir/count" || return
	pass "$n"
}

test_missing_commit_header_falls_back_to_a_conventional_subject() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one
	echo "touch src/x.go" >"$fake_dir/action.1"
	loop "$dir"
	expect "$n" "conventional fallback" test "$(subject "$dir" loop/001-one)" == "chore: Title 001-one" || return
	pass "$n"
}

test_lint_rejects_bad_headers() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-bad-commit "commit: Updated stuff."
	add_task "$dir" 002-bad-date "not_before: tomorrow"
	add_task "$dir" 003-bad-kind "kind: wizardry"
	loop "$dir" --lint
	expect "$n" "exit 1" test "$status" == 1 || return
	expect "$n" "commit flagged" grep -q '001-bad-commit.*commit' <<<"$output" || return
	expect "$n" "date flagged" grep -q '002-bad-date.*not_before' <<<"$output" || return
	expect "$n" "kind flagged" grep -q '003-bad-kind.*kind' <<<"$output" || return
	pass "$n"
}

test_in_place_commits_on_the_current_branch() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "commit: fix(x): repair it"
	echo "touch src/x.go" >"$fake_dir/action.1"
	loop "$dir" --in-place
	expect "$n" "exit 0 (status=$status)" test "$status" == 0 || return
	expect "$n" "commit on main" test "$(subject "$dir" main)" == "fix(x): repair it" || return
	pass "$n"
}

test_ff_merges_into_the_base_branch_and_clean_removes_leftovers() {
	local n=${FUNCNAME[0]} dir
	new_repo; dir=$repo
	add_task "$dir" 001-one "commit: fix(x): repair it"
	echo "touch src/x.go" >"$fake_dir/action.1"
	loop "$dir" --ff
	expect "$n" "exit 0 (status=$status)" test "$status" == 0 || return
	expect "$n" "main has the commit" test "$(subject "$dir" main)" == "fix(x): repair it" || return
	loop "$dir" --clean
	expect "$n" "merged branch removed" bash -c "! git -C '$dir' show-ref -q --verify refs/heads/loop/001-one" || return
	pass "$n"
}

command -v jq >/dev/null || { echo "tests need jq" >&2; exit 2; }
for test in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$test" || true; done
exit $((failures > 0))
