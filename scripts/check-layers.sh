#!/usr/bin/env bash
# Layer guard: fails when a Go package imports a package of a zone it may not import.
# Runs in the repo's go module root. Zones come from a table, one row per zone:
#
#   zone  patterns  may-import
#   core      ./core/...,./model     -
#   adapters  ./adapters/...         core
#
# patterns: comma-separated; `./dir/...` matches the directory and below, `./dir` matches only it.
# The most specific (longest) pattern wins, so `./internal/config` can sit in a stricter zone than
# `./internal/...`. may-import: comma-separated zone names, `-` for none. A zone may always import
# itself. Packages in no zone are unchecked. Test files count.
#
# usage: check-layers.sh [table]   (default .harness/layers.txt)
set -euo pipefail
table=${1:-.harness/layers.txt}
[[ -f $table ]] || { echo "check-layers: no table at $table" >&2; exit 2; }

module=$(go list -m)
declare -A zone_of_prefix exact_of_pattern allowed
prefixes=()
while read -r zone patterns may_import; do
	[[ -z $zone || $zone == \#* ]] && continue
	allowed[$zone]=",$may_import,"
	IFS=, read -ra list <<<"$patterns"
	for pattern in "${list[@]}"; do
		path=${pattern#./}
		if [[ $path == *"/..." ]]; then
			path=${path%/...}
			exact_of_pattern[$path]=prefix
		elif [[ $path == "..." ]]; then
			path=""
			exact_of_pattern[$path]=prefix
		else
			exact_of_pattern[$path]=exact
		fi
		zone_of_prefix[$path]=$zone
		prefixes+=("$path")
	done
done <"$table"

# zone_of <path relative to the module>: prints the zone of the longest matching pattern.
zone_of() {
	local rel=$1 best="" best_len=-1 prefix
	for prefix in "${prefixes[@]}"; do
		if [[ ${exact_of_pattern[$prefix]} == exact ]]; then
			[[ $rel == "$prefix" ]] || continue
		else
			[[ -z $prefix || $rel == "$prefix" || $rel == "$prefix"/* ]] || continue
		fi
		if ((${#prefix} > best_len)); then
			best=${zone_of_prefix[$prefix]}
			best_len=${#prefix}
		fi
	done
	echo "$best"
}

violations=0
while read -r package imports; do
	from_rel=${package#"$module"}
	from_rel=${from_rel#/}
	from_zone=$(zone_of "$from_rel")
	[[ -n $from_zone ]] || continue
	for import in $imports; do
		[[ $import == "$module" || $import == "$module"/* ]] || continue
		to_rel=${import#"$module"}
		to_rel=${to_rel#/}
		to_zone=$(zone_of "$to_rel")
		[[ -n $to_zone && $to_zone != "$from_zone" ]] || continue
		if [[ ${allowed[$from_zone]} != *",$to_zone,"* ]]; then
			echo "layer violation: $from_rel ($from_zone) imports $to_rel ($to_zone); $from_zone may import: ${allowed[$from_zone]//,/ }" >&2
			violations=$((violations + 1))
		fi
	done
done < <(go list -f '{{.ImportPath}} {{join .Imports " "}} {{join .TestImports " "}} {{join .XTestImports " "}}' ./...)
((violations == 0)) || exit 1
