#!/bin/bash
# Assemble docs/ (what GitHub Pages serves) from site/.
#
# Five pages sharing a nav and a footer will drift apart if each keeps its own
# copy, so they are stitched from partials here instead.
set -euo pipefail
cd "$(dirname "$0")/.."

# Stamp the stylesheet link with the content hash. Without it browsers keep
# serving the previous CSS after a deploy, which looks exactly like the change
# never shipped — it cost an afternoon once.
VERSION=$(shasum -a 1 site/style.css | cut -c1-10)
HEAD=$(sed "s/__VERSION__/$VERSION/" site/partials/head.html)
NAV=$(cat site/partials/nav.html)
FOOT=$(cat site/partials/foot.html)

cp site/style.css docs/style.css
: > docs/.nojekyll          # serve the files as written, no Jekyll pass

for page in site/pages/*.html; do
  name=$(basename "$page" .html)
  title=$(sed -n '1s/^<!--title:\(.*\)-->$/\1/p' "$page")
  desc=$(sed -n '2s/^<!--desc:\(.*\)-->$/\1/p' "$page")
  body=$(tail -n +3 "$page")

  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n'
    printf '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>%s</title>\n<meta name="description" content="%s">\n' "$title" "$desc"
    printf '<meta property="og:title" content="%s">\n<meta property="og:description" content="%s">\n' "$title" "$desc"
    printf '<meta property="og:image" content="images/icon-256.png">\n<meta name="twitter:card" content="summary_large_image">\n'
    printf '%s\n</head>\n<body data-page="%s">\n' "$HEAD" "$name"
    printf '%s\n' "$NAV"
    printf '%s\n' "$body"
    printf '%s\n</body>\n</html>\n' "$FOOT"
  } > "docs/$name.html"
  echo "  built docs/$name.html"
done
