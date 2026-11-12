#!/bin/sh
# nginx start hook, mounted into /docker-entrypoint.d/: builds index.html from the decrypted secrets in
# /run/secrets/secret.env (KEY=value lines). The page is written to a tmpfs, so the secrets stay in memory.
# If the file is missing, this fails and nginx doesn't start.
set -eu

src=/run/secrets/secret.env
page=/usr/share/nginx/html/index.html
[ -f "$src" ] || { echo "render-page: $src is missing: the decrypt service did not run" >&2; exit 1; }

html() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

greeting="toy-deploy"
rows=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        '' | '#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    [ "$key" = GREETING ] && greeting="$value"
    rows="$rows      <tr><th>$(html "$key")</th><td><code>$(html "$value")</code></td></tr>
"
done <"$src"

cat >"$page" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>toy-deploy</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 44rem; margin: 3rem auto; padding: 0 1rem; color: #1d2433; }
    h1 { font-size: 2.4rem; margin-bottom: .2rem; }
    p { color: #5a6275; }
    table { border-collapse: collapse; margin-top: 1.5rem; width: 100%; }
    th, td { text-align: left; padding: .5rem .8rem; border-bottom: 1px solid #d8dce5; }
    th { width: 30%; font-weight: 600; }
    code { font-size: 1.05rem; }
  </style>
</head>
<body>
  <h1>$(html "$greeting")</h1>
  <p>These values come from <code>secret.env.cdoc2</code>, decrypted by <code>docker compose up</code>
     through the deployer's ssh-agent. Page built $(date -u '+%Y-%m-%d %H:%M:%S') UTC.</p>
  <table>
$rows  </table>
</body>
</html>
EOF
echo "render-page: index.html built from $src"
