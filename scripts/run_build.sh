#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)

usage() {
	printf 'Usage: %s [--resolve-only] [--target-platform <platform>]\n' \
		"$(basename "$0")"
}

resolve_only=false
target_platform=""

while (( $# > 0 )); do
	case "$1" in
		--resolve-only)
			resolve_only=true
			shift
			;;
		--target-platform)
			if (( $# < 2 )) || [[ "$2" == -* ]] || [[ -n "$target_platform" ]]; then
				usage >&2
				exit 2
			fi
			target_platform=$2
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
done


rattler_command=(
	rattler-build build
	--variant-config "$repo_dir/variants.yaml"
	--no-include-recipe
	--output-dir ../output
)

if $resolve_only; then
	rattler_command+=(--render-only --with-solve)
fi

if [[ -n "$target_platform" ]]; then
	rattler_command+=(--target-platform "$target_platform")
fi

"${rattler_command[@]}"
