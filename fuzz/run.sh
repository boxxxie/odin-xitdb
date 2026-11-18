#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
	cat <<'EOF'
Usage: ./fuzz/run.sh <target> [libfuzzer_args...]

Targets:
  dsl     Build and fuzz DSL / selector / Pull / Datalog / script parsers
  wire    Build and fuzz corrupted .xit wire format & compaction
  lua     Build and fuzz sandboxed LuaJIT xitdb bridge
  all     Build and fuzz all targets sequentially (default: -max_total_time=30 each)
  build   Check and compile all targets without running campaigns
EOF
}

if [[ $# -lt 1 ]]; then
	usage
	exit 1
fi

TARGET="$1"
shift
EXTRA_ARGS=("$@")

has_budget_flag() {
	for arg in "${EXTRA_ARGS[@]}"; do
		if [[ "$arg" == -runs=* || "$arg" == -max_total_time=* ]]; then
			return 0
		fi
	done
	return 1
}

build_target() {
	local t="$1"
	local src="fuzz/fuzz_${t}.odin"
	local ir_dir=".tmp/fuzz/ir_${t}"
	local work_dir=".tmp/fuzz/work_${t}"
	local art_dir=".tmp/fuzz/artifacts_${t}"
	local bin=".tmp/fuzz/fuzz_${t}"

	echo "==> Checking ${src}"
	odin check "$src" -file -collection:xitdb=./xitdb -no-entry-point -vet -vet-packages:"fuzz_${t}" -vet-tabs -warnings-as-errors

	echo "==> Building LLVM IR for ${src}"
	rm -rf "$ir_dir"
	mkdir -p "$ir_dir" "$work_dir" "$art_dir"
	odin build "$src" -file -collection:xitdb=./xitdb -build-mode:llvm-ir -no-entry-point -out:"$ir_dir"

	echo "==> Linking ${bin} with libFuzzer + ASan"
	clang -O1 -g -fsanitize=fuzzer,address -Wno-override-module "$ir_dir"/*.ll \
		-o "$bin" -lm -lpthread -ldl -lluajit-5.1
}

run_target() {
	local t="$1"
	local bin=".tmp/fuzz/fuzz_${t}"
	local work_dir=".tmp/fuzz/work_${t}"
	local seed_dir="fuzz/corpus/${t}"
	local art_dir=".tmp/fuzz/artifacts_${t}"

	build_target "$t"

	local cmd=(
		"$bin"
		-timeout=2
		"-artifact_prefix=${art_dir}/"
	)

	case "$t" in
		dsl)
			cmd+=(-max_len=2048 "-dict=fuzz/corpus/dsl.dict")
			;;
		wire)
			cmd+=(-max_len=16384)
			;;
		lua)
			cmd+=(-max_len=2048 "-dict=fuzz/corpus/lua.dict")
			;;
	esac

	if ! has_budget_flag; then
		cmd+=(-max_total_time=30)
	fi

	cmd+=("${EXTRA_ARGS[@]}")
	cmd+=("$work_dir")
	if [[ -d "$seed_dir" ]]; then
		cmd+=("$seed_dir")
	fi

	echo "==> Running libFuzzer (${t})"
	"${cmd[@]}"
}

case "$TARGET" in
	dsl|wire|lua)
		run_target "$TARGET"
		;;
	all)
		for t in dsl wire lua; do
			run_target "$t"
		done
		;;
	build)
		for t in dsl wire lua; do
			build_target "$t"
		done
		;;
	-h|--help|help)
		usage
		;;
	*)
		echo "Unknown target: $TARGET" >&2
		usage
		exit 1
		;;
esac
