#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
variants_file="$repo_dir/variants.yaml"

usage() {
	cat <<EOF
Usage: $(basename "$0")

Render recipes with the shared variants and verify their generated metadata.
HEASoft, HEASoft tests, XSPEC, and xspec-compilers are checked for linux-64,
linux-aarch64, osx-64, and osx-arm64. The noarch xstar-data recipe is checked
once with linux-64. This script does not build packages or solve dependencies.
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

if ! command -v rattler-build >/dev/null 2>&1; then
	printf 'Error: rattler-build is required.\n' >&2
	exit 1
fi

variant_value() {
	local key=$1

	awk -v key="$key" '
		$0 == key ":" { in_key = 1; next }
		in_key && /^[^ ]/ { exit }
		in_key && $1 == "-" {
			gsub(/"/, "", $2)
			print $2
			exit
		}
	' "$variants_file"
}

conditional_variant_value() {
	local key=$1
	local selector=$2

	awk -v key="$key" -v selector="$selector" '
		$0 == key ":" { in_key = 1; next }
		in_key && /^[^ ]/ { exit }
		in_key && $1 == "-" && $2 == "if:" {
			selected = ($3 == selector)
			next
		}
		in_key && selected && $1 == "then:" {
			gsub(/"/, "", $2)
			print $2
			exit
		}
	' "$variants_file"
}

assert_contains() {
	local output=$1
	local expected=$2
	local description=$3

	if ! grep -Fq "$expected" <<<"$output"; then
		printf 'Error: %s is missing %s.\n' "$description" "$expected" >&2
		exit 1
	fi
}

render_recipe() {
	local package=$1
	local platform=$2

	rattler-build build \
		-r "$repo_dir/$package" \
		--render-only \
		--target-platform "$platform" \
		--variant-config "$variants_file" \
		--no-include-recipe \
		--log-style plain 2>&1
}

heasoft_version=$(variant_value heasoft_version)
xspec_version=$(variant_value xspec_version)
fortran_version=$(variant_value fortran_compiler_version)

if [[ -z "$heasoft_version" || -z "$xspec_version" || -z "$fortran_version" ]]; then
	printf 'Error: a required shared variant is empty.\n' >&2
	exit 1
fi

platforms=(linux-64 linux-aarch64 osx-64 osx-arm64)
packages=(heasoft heasoft-tests xspec xspec-compilers)

for platform in "${platforms[@]}"; do
	case "$platform" in
		linux-*)
			selector=linux
			c_package="gcc_$platform"
			cxx_package="gxx_$platform"
			;;
		osx-*)
			selector=osx
			c_package="clang_$platform"
			cxx_package="clangxx_$platform"
			;;
	esac
	c_version=$(conditional_variant_value c_compiler_version "$selector")
	cxx_version=$(conditional_variant_value cxx_compiler_version "$selector")
	fortran_package="gfortran_$platform"

	for package in "${packages[@]}"; do
		output=$(render_recipe "$package" "$platform")
		case "$package" in
			heasoft|heasoft-tests)
				assert_contains "$output" "\"version\": \"$heasoft_version\"" "$package $platform"
				;;
			xspec|xspec-compilers)
				assert_contains "$output" "\"version\": \"$xspec_version\"" "$package $platform"
				;;
		esac
		assert_contains "$output" "$c_package $c_version.*" "$package $platform"
		assert_contains "$output" "$cxx_package $cxx_version.*" "$package $platform"
		assert_contains "$output" "$fortran_package $fortran_version.*" "$package $platform"

		if [[ "$package" == heasoft || "$package" == xspec ]]; then
			assert_contains "$output" "xspec-compilers ==$xspec_version" "$package $platform"
		fi

		if [[ "$package" == xspec ]]; then
			assert_contains "$output" "heasoft-$heasoft_version.tar.gz" "$package $platform"
		fi

		printf 'PASS: %s %s\n' "$package" "$platform"
	done
done

output=$(render_recipe xstar-data linux-64)
assert_contains "$output" "\"version\": \"$heasoft_version\"" 'xstar-data linux-64'
assert_contains "$output" "xstar-data-$heasoft_version.tar.gz" 'xstar-data linux-64'
printf 'PASS: xstar-data linux-64\n'