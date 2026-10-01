# ashfall-secret: create YubiKey-locked secrets for ashfall.yubikey.clipSecrets.
#
#   ashfall-secret init [dir]        set up an age identity on each plugged-in key
#   ashfall-secret add NAME [dir]    encrypt a secret to all enrolled keys
#
# dir defaults to ./secrets (run it from your config folder, e.g. /etc/nixos).
# Identity stubs and .age files are safe to commit: they decrypt nothing
# without a physical YubiKey and its PIV PIN.

SLOT=1

step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ashfall-secret init [dir]       Create an age identity on every plugged-in YubiKey
  ashfall-secret add NAME [dir]   Encrypt a secret (prompted) to all enrolled keys

dir defaults to ./secrets
EOF
}

cmd_init() {
  local dir=$1
  local ids="$dir/identities"
  step "[1/3] Looking for YubiKeys"
  local serials
  serials=$(ykman list --serials 2>/dev/null || true)
  [ -n "$serials" ] || die "no YubiKey detected (is pcscd running? try replugging)"
  printf '  found: %s\n' "$(echo "$serials" | tr '\n' ' ')"
  mkdir -p "$ids"

  step "[2/3] Creating identities (PIV PIN and a touch per key)"
  local serial
  for serial in $serials; do
    if age-plugin-yubikey --identity --serial "$serial" --slot "$SLOT" >/dev/null 2>&1; then
      echo "  $serial: existing identity in slot $SLOT, reusing it"
    else
      echo "  $serial: generating (set the PIV PIN/PUK first if prompted; touch when it blinks)"
      age-plugin-yubikey --generate --serial "$serial" --slot "$SLOT" \
        --name "ashfall-$serial" --pin-policy once --touch-policy always >/dev/null
    fi
    age-plugin-yubikey --identity --serial "$serial" --slot "$SLOT" > "$ids/$serial.txt"
    echo "  wrote $ids/$serial.txt"
  done

  step "[3/3] Updating recipients"
  local tmp
  tmp=$(mktemp)
  [ -f "$dir/recipients.txt" ] && cat "$dir/recipients.txt" >> "$tmp"
  grep -ho 'age1yubikey1[0-9a-z]*' "$ids"/*.txt >> "$tmp"
  sort -u "$tmp" > "$dir/recipients.txt"
  rm -f "$tmp"
  echo "  $(wc -l < "$dir/recipients.txt") recipient(s) in $dir/recipients.txt"
  cat <<EOF

Done. Add to your configuration.nix:
  ashfall.yubikey.identities = ./$(basename "$dir")/identities;
Then create a secret with: ashfall-secret add NAME $dir
Secrets made before adding a key are not readable by that key; re-run add.
EOF
}

cmd_add() {
  local name=$1 dir=$2
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "NAME must be letters, digits, - or _ (it becomes a command)"
  [ -s "$dir/recipients.txt" ] || die "no recipients in $dir; run: ashfall-secret init $dir"
  local out="$dir/$name.age"

  step "[1/3] Reading secret"
  local s1 s2
  read -rsp "  Secret for '$name': " s1; echo
  read -rsp "  Confirm: " s2; echo
  [ "$s1" = "$s2" ] || die "did not match"
  [ -n "$s1" ] || die "empty secret"

  step "[2/3] Encrypting to $(wc -l < "$dir/recipients.txt") key(s)"
  printf '%s' "$s1" | age -R "$dir/recipients.txt" -o "$out.tmp"
  unset s1 s2
  mv "$out.tmp" "$out"
  echo "  wrote $out"

  step "[3/3] Test decrypt with a plugged-in key (PIN + touch)"
  local f serial ok=0
  for f in "$dir"/identities/*.txt; do
    serial=$(grep -o 'Serial: [0-9]*' "$f" | grep -o '[0-9]*' | head -n1)
    if ykman list --serials 2>/dev/null | grep -qx "$serial"; then
      age -d -i "$f" "$out" >/dev/null && ok=1
      break
    fi
  done
  if [ "$ok" -eq 1 ]; then echo "  OK"; else echo "  skipped: no enrolled key plugged in"; fi

  cat <<EOF

Done. Add to your configuration.nix:
  ashfall.yubikey.clipSecrets.$name.file = ./$(basename "$dir")/$name.age;
then track the new file and rebuild:
  git add -A && sudo nixos-rebuild switch
Running '$name' will then copy it to the clipboard for one paste.
EOF
}

case "${1:-}" in
  init) cmd_init "${2:-./secrets}" ;;
  add)
    [ -n "${2:-}" ] || { usage; exit 1; }
    cmd_add "$2" "${3:-./secrets}"
    ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 1 ;;
esac
