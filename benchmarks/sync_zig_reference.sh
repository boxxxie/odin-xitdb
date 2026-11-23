#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PINNED_ZIG_REF="274418f6ac1c37bccbe7e8e6f212dc123bca4843"
PINNED_PATCHED_REF="dd7f331942a3bf3b7f9ea14a3fdbdb981a94794c"

ZIG_URL="${XITDB_ZIG_URL:-https://github.com/xit-vcs/xitdb.git}"
PATCHED_URL="${XITDB_PATCHED_URL:-https://github.com/boxxxie/xitdb.git}"

LATEST=0
FORCE=0

usage() {
	cat <<'EOF'
Usage: benchmarks/sync_zig_reference.sh [--latest] [--force] [-h|--help]

Fetch or update the on-demand Zig reference checkouts used by build.zig and
benchmarks/compare_1v1.py:
  - reference/xitdb-zig
  - reference/xitdb-zig-patched

Options:
  --latest   Check out origin/master and origin/patched instead of pinned SHAs.
  --force    Discard uncommitted/untracked changes in existing checkouts.
  -h, --help Show this help text.

Environment overrides:
  XITDB_ZIG_URL       Remote URL for reference/xitdb-zig
  XITDB_PATCHED_URL   Remote URL for reference/xitdb-zig-patched
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--latest)
		LATEST=1
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

sync_repo() {
	local rel_path="$1"
	local url="$2"
	local pinned_sha="$3"
	local latest_ref="$4"
	local target="${REPO_ROOT}/${rel_path}"

	if [[ -e "$target" && ! -e "$target/.git" ]]; then
		if [[ -d "$target" && -z "$(ls -A "$target" 2>/dev/null || true)" ]]; then
			rmdir "$target"
		elif [[ $FORCE -eq 1 ]]; then
			rm -rf "$target"
		else
			echo "Error: '${rel_path}' exists and is not a git repository (re-run with --force to replace)." >&2
			exit 1
		fi
	fi

	mkdir -p "$(dirname "$target")"
	if [[ ! -e "$target/.git" ]]; then
		echo "Cloning ${rel_path} from ${url}..."
		git clone "$url" "$target"
	else
		local dirty
		dirty="$(git -C "$target" status --porcelain -uall)"
		if [[ -n "$dirty" ]]; then
			if [[ $FORCE -eq 1 ]]; then
				echo "Resetting dirty working tree in ${rel_path} (--force)..."
				git -C "$target" reset --hard
				git -C "$target" clean -fdx
			else
				echo "Error: '${rel_path}' has uncommitted changes (commit/stash them or re-run with --force)." >&2
				exit 1
			fi
		fi
		git -C "$target" remote set-url origin "$url"
		git -C "$target" fetch --tags origin
	fi

	local want_ref="$pinned_sha"
	if [[ $LATEST -eq 1 ]]; then
		want_ref="$latest_ref"
	fi
	git -C "$target" checkout --detach "$want_ref"
	echo "Synced ${rel_path} -> $(git -C "$target" rev-parse --short HEAD) (${want_ref})"
}

sync_repo "reference/xitdb-zig" "$ZIG_URL" "$PINNED_ZIG_REF" "origin/master"
sync_repo "reference/xitdb-zig-patched" "$PATCHED_URL" "$PINNED_PATCHED_REF" "origin/patched"
