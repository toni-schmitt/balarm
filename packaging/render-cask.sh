#!/usr/bin/env bash
# Renders the Homebrew cask from balarm.rb.tmpl to stdout.
set -euo pipefail
# Bracket ranges such as [A-Za-z] match exactly ASCII letters only in the C
# locale; in others they can also match accented letters.
export LC_ALL=C

usage() {
	echo "usage: $0 <version> <sha256 of the release's app archive>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage
version="$1"
sha="$2"

# The version ends up in the cask's URL and in a sed expression delimited by
# "|", so its shape is constrained rather than trusted.
case "$version" in
'' | *[!0-9A-Za-z.+-]*)
	echo "refusing to render a cask for version '$version'" >&2
	exit 1
	;;
esac
if [ "${#sha}" -ne 64 ] || [ -n "$(printf '%s' "$sha" | tr -d '0-9a-f')" ]; then
	echo "not a sha256 digest: '$sha'" >&2
	exit 1
fi

cask="$(sed \
	-e "s|@@VERSION@@|${version}|g" \
	-e "s|@@SHA_APP@@|${sha}|g" \
	"$(dirname "${BASH_SOURCE[0]}")/balarm.rb.tmpl")"
if grep -qE '@@[A-Z_]+@@' <<<"$cask"; then
	echo "the cask still contains unreplaced placeholders:" >&2
	grep -nE '@@[A-Z_]+@@' <<<"$cask" >&2
	exit 1
fi
printf '%s\n' "$cask"
