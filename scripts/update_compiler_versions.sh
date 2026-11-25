#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
variants_file="$repo_dir/variants.yaml"

usage() {
	cat <<EOF
Usage: $(basename "$0")

Update variants.yaml to the latest compiler versions available on conda-forge.
Each selected version is available for every architecture governed by its
variant key. The update is atomic and does not build any packages.

Requirements: micromamba, jq, and network access to conda-forge.
EOF
}

if (( $# > 1 )); then
	usage >&2
	exit 2
fi

case "${1:-}" in
	-h|--help)
		usage
		exit 0
		;;
	"")
		;;
	*)
		usage >&2
		exit 2
		;;
esac

for command in micromamba jq; do
	if ! command -v "$command" >/dev/null 2>&1; then
		printf 'Error: %s is required to update compiler versions.\n' "$command" >&2
		exit 1
	fi
done

query_versions() {
	local package=$1
	local platform=$2

	micromamba repoquery search "$package" \
		--platform "$platform" \
		--channel conda-forge \
		--override-channels \
		--repodata-ttl 0 \
		--json |
		jq -ce --arg package "$package" --arg platform "$platform" '
			[.result.pkgs[].version] | unique |
			if length == 0 then
				error("No versions found for \($package) on \($platform)")
			else
				.
			end
		'
}

latest_common_version() {
	local common_versions=""
	local spec package platform available_versions

	for spec in "$@"; do
		package=${spec%:*}
		platform=${spec#*:}
		available_versions=$(query_versions "$package" "$platform")

		if [[ -z "$common_versions" ]]; then
			common_versions=$available_versions
		else
			common_versions=$(jq -cn \
				--argjson current "$common_versions" \
				--argjson available "$available_versions" \
				'$current | map(select(. as $version | $available | index($version)))')
		fi
	done

	jq -er '
		map(select(test("^[0-9]+(\\.[0-9]+)*$"))) |
		if length == 0 then
			error("No common numeric compiler version found")
		else
			sort_by(split(".") | map(tonumber)) | last
		end
	' <<<"$common_versions"
}

gnu_version=$(latest_common_version \
	"gcc_linux-64:linux-64" \
	"gcc_linux-aarch64:linux-aarch64" \
	"gxx_linux-64:linux-64" \
	"gxx_linux-aarch64:linux-aarch64")

clang_version=$(latest_common_version \
	"clang_osx-64:osx-64" \
	"clang_osx-arm64:osx-arm64" \
	"clangxx_osx-64:osx-64" \
	"clangxx_osx-arm64:osx-arm64")

fortran_version=$(latest_common_version \
	"gfortran_linux-64:linux-64" \
	"gfortran_linux-aarch64:linux-aarch64" \
	"gfortran_osx-64:osx-64" \
	"gfortran_osx-arm64:osx-arm64")

temp_file=$(mktemp "$variants_file.tmp.XXXXXX")
trap 'rm -f "$temp_file"' EXIT

cat >"$temp_file" <<EOF
c_compiler_version:
  - if: linux
    then: "$gnu_version"
  - if: osx
    then: "$clang_version"

cxx_compiler_version:
  - if: linux
    then: "$gnu_version"
  - if: osx
    then: "$clang_version"

fortran_compiler_version:
  - "$fortran_version"
EOF

mv "$temp_file" "$variants_file"

printf 'Updated compiler versions in %s:\n' "$variants_file"
printf '  Linux C/C++: %s\n' "$gnu_version"
printf '  macOS C/C++: %s\n' "$clang_version"
printf '  Fortran:     %s\n' "$fortran_version"