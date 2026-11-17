#!/usr/bin/env bash
# Autonomous agent loop: works through .harness/tasks/*.md marked `status: todo`.
# Per task, in its own git worktree (branch loop/<task>): design (feature and bug tasks), implement,
# gates (scope, test present, verify command), one retry with the failure, then commit.
# Runs in the consuming repo (the git toplevel of the current directory).
#
# usage: loop.sh [--dry-run | --lint | --clean] [--once] [--ff] [--in-place]
#   --dry-run   list the eligible tasks         --lint   validate the task headers
#   --clean     remove worktrees and branches of merged loop/* branches
#   --once      do the next task only           --ff     fast-forward the current branch after a task
#   --in-place  legacy: work in this checkout (needs a clean tree) instead of a worktree
# env:   VERIFY_CMD (default "make check"), MAX_TURNS (50), MAX_ATTEMPTS (2), MAX_BUDGET_USD (none),
#        ALLOWED_TOOLS (default list), CLAUDE (binary, default claude), COMMIT_TRAILER
#
# Task file: header lines `key: value` (first line `status: todo`), a blank line, then `# Title` and
# the body. Optional keys: kind (feature|bug|chore|docs, default chore), commit (conventional subject),
# scope (comma-separated globs the change may touch), not_before (YYYY-MM-DD), depends_on (task names,
# eligible once their files are gone from this checkout). Tasks must be committed. Feature and bug tasks need a `## Model`
# section or `Model: unchanged`. Reports: <git common dir>/harness/runs/<task>-<time>/.
set -euo pipefail
shopt -s nullglob
here=$(dirname "$(readlink -f "$0")")
cd "$(git rev-parse --show-toplevel)"
origin=$PWD
mode=run once=false ff=false in_place=false
for arg in "$@"; do
	case $arg in
	--dry-run) mode=dry-run ;;
	--lint) mode=lint ;;
	--clean) mode=clean ;;
	--once) once=true ;;
	--ff) ff=true ;;
	--in-place) in_place=true ;;
	*) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
	esac
done
verify_cmd=${VERIFY_CMD:-make check}
max_turns=${MAX_TURNS:-50}
max_attempts=${MAX_ATTEMPTS:-2}
claude_bin=${CLAUDE:-claude}
trailer=${COMMIT_TRAILER:-Co-Authored-By: Claude <noreply@anthropic.com>}
allowed=${ALLOWED_TOOLS:-"Read,Glob,Grep,Edit,Write,Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(${verify_cmd%% *} *)"}
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
repo_root=$(dirname "$common_dir")
today=$(date +%F)
commit_pattern='^(feat|fix|docs|test|refactor|build|ci|chore|release)(\([a-z0-9._-]+\))?: .+$'
test_pattern='(_test\.|\.test\.|\.spec\.|_spec\.|(^|/)tests?/|(^|/)test_)'

# header <file> <key>: value of a header key (the header ends at the first blank line).
header() {
	awk -v key="$2" 'NF == 0 { exit } { i = index($0, ":"); if (i && substr($0, 1, i - 1) == key) { v = substr($0, i + 1); sub(/^ +/, "", v); print v; exit } }' "$1"
}
title_of() { awk '/^# / { sub(/^# /, ""); print; exit }' "$1"; }

# eligible <file>: todo, not before its date, and every dependency already gone from this checkout.
eligible() {
	local file=$1 not_before dep
	[[ $(head -1 "$file") == "status: todo" ]] || return 1
	git cat-file -e "HEAD:$file" 2>/dev/null || return 1 # a worktree starts from HEAD: the file must be in it
	not_before=$(header "$file" not_before)
	if [[ -n $not_before && $not_before > $today ]]; then return 1; fi
	for dep in $(header "$file" depends_on | tr ',' ' '); do
		if [[ -e .harness/tasks/$dep.md ]]; then return 1; fi
	done
	return 0
}

lint() {
	local file name value kind problems=0
	for file in .harness/tasks/*.md; do
		name=$(basename "$file")
		problem() { echo "$name: $1" >&2; problems=$((problems + 1)); }
		[[ $(head -1 "$file") =~ ^status:\ (todo|blocked|failed)$ ]] || problem "status: first line must be 'status: todo', 'blocked' or 'failed'"
		if [[ $(head -1 "$file") == "status: todo" ]] && ! git cat-file -e "HEAD:$file" 2>/dev/null; then
			problem "not committed: commit the task first, the worktree starts from HEAD"
		fi
		kind=$(header "$file" kind)
		kind=${kind:-chore}
		[[ $kind =~ ^(feature|bug|chore|docs)$ ]] || problem "kind: '$kind' is not feature, bug, chore or docs"
		value=$(header "$file" commit)
		if [[ -n $value ]]; then
			[[ $value =~ $commit_pattern && ${#value} -le 72 ]] || problem "commit: '$value' is not 'type(scope): subject' within 72 characters"
		fi
		value=$(header "$file" not_before)
		if [[ -n $value ]]; then
			[[ $value =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || problem "not_before: '$value' is not YYYY-MM-DD"
		fi
		if [[ $kind == feature || $kind == bug ]]; then
			grep -Eq '^(## Model|Model: unchanged)' "$file" || problem "model: $kind tasks need a '## Model' section or 'Model: unchanged'"
		fi
	done
	((problems == 0))
}

clean() {
	local branch
	while read -r branch; do
		[[ -n $branch ]] || continue
		git merge-base --is-ancestor "$branch" HEAD || continue
		"$here/wt" rm "$repo_root" "$branch" 2>/dev/null || true
		git branch -q -d "$branch"
		echo "removed $branch"
	done < <(git for-each-ref --format='%(refname:short)' refs/heads/loop/)
}

case $mode in
lint) lint; exit $? ;;
clean) clean; exit 0 ;;
esac

pending() {
	local file
	for file in .harness/tasks/*.md; do
		if eligible "$file"; then
			echo "$file"
		fi
	done
}

if [[ $mode == dry-run ]]; then
	tasks=$(pending)
	if [[ -z $tasks ]]; then
		echo "no pending tasks"
	else
		echo "pending tasks:"
		printf '  %s\n' $tasks
	fi
	exit 0
fi

command -v jq >/dev/null || { echo "loop.sh needs jq" >&2; exit 1; }
if $in_place && [[ -n $(git status --porcelain) ]]; then
	echo "working tree dirty; commit or stash first" >&2
	exit 1
fi
if [[ -z $(pending) ]]; then
	echo "no pending tasks"
	exit 0
fi
lint || { echo "fix the task headers first (loop.sh --lint)" >&2; exit 1; }

# agent <phase> <prompt> [session]: runs claude in $workdir; sets $reply and $session.
agent() {
	local phase=$1 prompt=$2 resume=${3:-}
	local out="$run/$phase-$((++calls)).json"
	local args=(-p --output-format json --max-turns "$max_turns")
	if [[ $phase == design ]]; then
		args+=(--permission-mode plan --allowedTools "Read,Glob,Grep")
	else
		args+=(--permission-mode acceptEdits --allowedTools "$allowed")
	fi
	[[ -z $resume ]] || args+=(--resume "$resume")
	[[ -z ${MAX_BUDGET_USD:-} ]] || args+=(--max-budget-usd "$MAX_BUDGET_USD")
	(cd "$workdir" && printf '%s' "$prompt" | "$claude_bin" "${args[@]}" >"$out" 2>"$out.err") || return 1
	[[ $(jq -r '.is_error // false' "$out") == false ]] || return 1
	reply=$(jq -r '.result // ""' "$out")
	session=$(jq -r '.session_id // ""' "$out")
}

changed_files() {
	{
		git -C "$workdir" diff --name-only HEAD
		git -C "$workdir" ls-files -o --exclude-standard
	} | sort -u
}

# problems_of <task file> <kind> <scope>: what is wrong with the work so far, empty when nothing.
problems_of() {
	local file=$1 kind=$2 scope=$3 changed path glob inside stray="" log globs=()
	changed=$(changed_files)
	if [[ -n $scope ]]; then
		IFS=', ' read -ra globs <<<"$scope" # an array: an unquoted expansion would glob against the checkout
		while read -r path; do
			[[ -n $path ]] || continue
			inside=false
			for glob in "${globs[@]}"; do
				# shellcheck disable=SC2053
				if [[ $path == $glob ]]; then inside=true; fi
			done
			$inside || stray+=" $path"
		done <<<"$changed"
		[[ -z $stray ]] || { echo "changed files outside scope ($scope):$stray"; return; }
	fi
	if [[ $kind == feature || $kind == bug ]] && ! grep -Eq "$test_pattern" <<<"$changed"; then
		echo "no test in the change: write the test first and keep it in the diff"
		return
	fi
	log="$run/verify-$attempt.log"
	if ! (cd "$workdir" && bash -c "$verify_cmd") >"$log" 2>&1; then
		echo "verification failed ($verify_cmd); last output:"
		tail -n 60 "$log"
	fi
}

implement_prompt() { # <task file> <design>
	cat <<PROMPT
You are working autonomously on gascoigne. Follow CLAUDE.md and the .harness rules strictly; read the
architecture docs under .harness for your area before changing code. Model first, test first.
Complete this task fully, then run the verify skill ($verify_cmd). Do not commit and do not edit the
task file; the harness does both. If the task is blocked or needs a different data model or a core
change, stop and explain why. End your final message with exactly one line: \`RESULT: done\` or
\`RESULT: blocked <reason>\`.
Task file: $1
---
$(tail -n +2 "$1")
${2:+---
Design to implement:
$2}
PROMPT
}

design_prompt() {
	cat <<PROMPT
You are designing a change for gascoigne. Do not edit anything. Use the data-model skill
(.harness/common/skills/data-model/SKILL.md) and .harness/common/data-structures.md. Reply with the
design note in markdown: a '## Model' section (types, invariants; per collection the access pattern,
structure chosen, alternative rejected, revisit signal) or the line 'Model: unchanged', then the zone
of each type, ports touched, and the test list.
Task file: $1
---
$(tail -n +2 "$1")
PROMPT
}

# commit_task <task file> <name> <scope>: stage and commit the work and the task deletion.
commit_task() {
	local file=$1 name=$2 scope=$3 subject
	subject=$(header "$file" commit)
	if [[ -z $subject ]]; then
		subject="chore: $(title_of "$file")"
		subject=${subject:0:72}
	fi
	if [[ -n $scope ]]; then
		changed_files | while read -r path; do [[ -z $path ]] || git -C "$workdir" add -- "$path"; done
	else
		git -C "$workdir" add -A
	fi
	git -C "$workdir" rm -q -f "$file"
	git -C "$workdir" commit -q -m "$subject" -m "Task: $name" -m "$trailer"
}

# run_task <task file>: sets $outcome (done|blocked|failed) and $detail.
run_task() {
	local file=$1 name kind scope branch base design="" problem result
	name=$(basename "$file" .md)
	kind=$(header "$file" kind)
	kind=${kind:-chore}
	scope=$(header "$file" scope)
	run=$common_dir/harness/runs/$name-$(date +%Y%m%d-%H%M%S)
	mkdir -p "$run"
	calls=0 attempt=1 outcome=failed detail=""
	if $in_place; then
		workdir=$origin
	else
		branch=loop/$name
		if git show-ref -q --verify "refs/heads/$branch"; then
			detail="branch $branch exists; merge it, or remove it and its worktree"
			return
		fi
		base=$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)
		workdir=$("$here/wt" new "$repo_root" "$branch" "$base")
	fi
	if [[ $kind == feature || $kind == bug ]]; then
		if ! agent design "$(design_prompt "$file")"; then
			detail="design phase failed (see $run)"
			return
		fi
		printf '%s\n' "$reply" >"$run/design.md"
		if ! grep -Eq '^(## Model|Model: unchanged)' "$run/design.md"; then
			detail="design has no '## Model' section or 'Model: unchanged' (see $run/design.md)"
			return
		fi
		design=$reply
	fi
	if ! agent implement "$(implement_prompt "$file" "$design")"; then
		detail="claude failed (see $run)"
		return
	fi
	while true; do
		result=$(printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }')
		if [[ $result == "RESULT: blocked"* ]]; then
			outcome=blocked detail=${result#RESULT: blocked }
			return
		fi
		if [[ $result == "RESULT: done" ]]; then
			problem=$(problems_of "$file" "$kind" "$scope")
		else
			problem="the final line must be 'RESULT: done' or 'RESULT: blocked <reason>'"
		fi
		if [[ -z $problem ]]; then
			commit_task "$file" "$name" "$scope"
			outcome=done detail=$(git -C "$workdir" log -1 --format=%h)
			return
		fi
		if ((attempt >= max_attempts)); then
			detail=$problem
			return
		fi
		attempt=$((attempt + 1))
		if ! agent implement "Fix this and finish the task; end with RESULT: done or RESULT: blocked <reason>. Problem: $problem" "$session"; then
			detail="claude failed on retry (see $run)"
			return
		fi
	done
}

attempted=" "
failures=0
while true; do
	next=""
	for file in $(pending); do
		[[ $attempted == *" $file "* ]] || { next=$file; break; }
	done
	[[ -n $next ]] || break
	attempted+="$next "
	name=$(basename "$next" .md)
	echo "==> $name"
	run_task "$next"
	echo "$outcome $detail" >"${run:-/dev/null}/outcome" 2>/dev/null || true
	case $outcome in
	done)
		if $in_place; then
			echo "    done: $detail"
		else
			echo "    done: $detail on loop/$name"
			if $ff && git merge --ff-only -q "loop/$name"; then
				echo "    merged (fast-forward)"
			else
				$ff && echo "    could not fast-forward; merge it: git merge loop/$name"
				$ff || echo "    merge it: git merge --ff-only loop/$name"
			fi
			"$here/wt" rm "$repo_root" "loop/$name"
		fi
		;;
	blocked)
		echo "    blocked: $detail (worktree kept; run: $run)" >&2
		failures=$((failures + 1))
		;;
	*)
		echo "    failed: $detail" >&2
		echo "    (worktree kept; run: $run)" >&2
		failures=$((failures + 1))
		;;
	esac
	if $once; then break; fi
done
((failures == 0))
