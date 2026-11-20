#!/bin/sh
# Build the pinned Doona sources with package-local patches for embedding.
set -eu

package_dir="$(cd "$(dirname "$0")" && pwd)"
honk_src="${HONK_SRC:?HONK_SRC is not set}"
archive="${HONK_DOONA_SOURCE:?HONK_DOONA_SOURCE is not set}"
revision="$(sed -n 's/^DOONA_REVISION=//p' "${honk_src}/.github/ci/pins.env")"
if [ -z "${revision}" ] || [ "${archive##*/}" != "doona-${revision}.tar.gz" ]; then
  echo "honk: Doona source archive does not match Honk's DOONA_REVISION" >&2
  exit 1
fi

stage="$(mktemp -d "${honk_src}/.doona-build.XXXXXX")"
trap 'rm -rf "${stage}"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "${stage}/src"
tar -xzf "${archive}" -C "${stage}/src" --strip-components=1
cd "${stage}/src"
for patch in "${package_dir}"/doona-patches/*.patch; do
  patch --batch --fuzz=0 -p1 < "${patch}"
done

# The source declares the pnpm version. Standard and Lite have separate
# lockfiles and are built with the same commands as the Doona release.
export npm_config_cache="${npm_config_cache:-${honk_src}/.npm-cache}"
package_manager="$(node -p "require('./package.json').packageManager")"
pnpm() {
  npm exec --yes --package="${package_manager}" -- pnpm "$@"
}
pnpm install --frozen-lockfile --store-dir "${honk_src}/.pnpm-store"
pnpm -C apps/lite install --frozen-lockfile --store-dir "${honk_src}/.pnpm-store"
pnpm build
pnpm -C apps/lite build

stage_assets() {
  build="$1"
  output="$2"
  test -f "${build}/index.html"
  cp LICENSE NOTICE README.md README.en.md "${build}/"
  node tools/notices.mjs "${build}" "${build}/.vite/bundled-packages.json"
  # Keep the release's program assets and omit optional fonts and Vite metadata.
  rm -rf "${build}/fonts" "${build}/.vite"
  mv "${build}" "${output}"
}
stage_assets dist "${stage}/program"
stage_assets apps/lite/dist "${stage}/lite"
for edition in program lite; do
  case "${edition}" in
    program) output="${honk_src}/.doona-patched" ;;
    lite) output="${honk_src}/.doona-patched-lite" ;;
  esac
  rm -rf "${output}"
  mv "${stage}/${edition}" "${output}"
done
