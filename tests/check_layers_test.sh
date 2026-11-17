#!/usr/bin/env bash
# Tests for scripts/check-layers.sh against a scratch Go module.
# usage: tests/check_layers_test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
script=${CHECK_LAYERS:-$here/scripts/check-layers.sh}
failures=0

# scratch_module: a module "example.invalid/m" with core, adapters/disk and app packages.
# core imports nothing; adapters/disk imports core; app imports both. Prints the directory.
scratch_module() {
	local dir
	dir=$(mktemp -d)
	mkdir -p "$dir/core" "$dir/adapters/disk" "$dir/adapters/net" "$dir/app" "$dir/.harness"
	printf 'module example.invalid/m\n\ngo 1.21\n' >"$dir/go.mod"
	printf 'package core\n\nconst Name = "core"\n' >"$dir/core/core.go"
	printf 'package disk\n\nimport "example.invalid/m/core"\n\nvar _ = core.Name\n' >"$dir/adapters/disk/disk.go"
	printf 'package net\n\nconst Name = "net"\n' >"$dir/adapters/net/net.go"
	printf 'package app\n\nimport (\n\t"example.invalid/m/adapters/disk"\n\t"example.invalid/m/core"\n)\n\nvar _ = disk.X\nvar _ = core.Name\n' >"$dir/app/app.go"
	sed -i 's/var _ = disk.X/var _ = disk.Name/' "$dir/app/app.go"
	printf 'package disk\n\nconst Name = "disk"\n' >"$dir/adapters/disk/name.go"
	cat >"$dir/.harness/layers.txt" <<'TABLE'
# zone patterns may-import
core     ./core/...        -
adapters ./adapters/...    core
app      ./app/...         core,adapters
TABLE
	echo "$dir"
}

# check <name> <dir> <want exit> [want output fragment]
check() {
	local name=$1 dir=$2 want=$3 fragment=${4:-} output status=0
	output=$(cd "$dir" && "$script" 2>&1) || status=$?
	if [[ $status != "$want" || $output != *"$fragment"* ]]; then
		echo "FAIL $name: exit $status (want $want), output: $output"
		failures=$((failures + 1))
		return
	fi
	echo "ok   $name"
}

dir=$(scratch_module)
check allowed_imports_pass "$dir" 0

dir=$(scratch_module)
printf 'package core\n\nimport "example.invalid/m/adapters/net"\n\nvar _ = net.Name\n' >"$dir/core/bad.go"
check core_importing_adapter_fails "$dir" 1 "layer violation"
dir=$(scratch_module)
printf 'package core\n\nimport "example.invalid/m/adapters/net"\n\nvar _ = net.Name\n' >"$dir/core/bad.go"
check violation_names_both_zones "$dir" 1 "core (core) imports adapters/net (adapters)"

dir=$(scratch_module)
printf 'package net\n\nimport "example.invalid/m/adapters/disk"\n\nvar _ = disk.Name\n' >"$dir/adapters/net/bad.go"
check same_zone_import_passes "$dir" 0

dir=$(scratch_module)
printf 'package core\n\nimport (\n\t"testing"\n\n\t"example.invalid/m/adapters/net"\n)\n\nfunc TestX(t *testing.T) { _ = net.Name }\n' >"$dir/core/x_test.go"
check test_files_count "$dir" 1 "core (core) imports adapters/net (adapters)"

# The longest pattern wins: ./adapters/net sits in its own stricter zone.
dir=$(scratch_module)
printf 'netzone ./adapters/net  core\n' >>"$dir/.harness/layers.txt"
printf 'package net\n\nimport "example.invalid/m/adapters/disk"\n\nvar _ = disk.Name\n' >"$dir/adapters/net/bad.go"
check longest_pattern_wins "$dir" 1 "adapters/net (netzone) imports adapters/disk (adapters)"

dir=$(scratch_module)
rm "$dir/.harness/layers.txt"
check missing_table_is_an_error "$dir" 2 "no table"
exit $((failures > 0))
