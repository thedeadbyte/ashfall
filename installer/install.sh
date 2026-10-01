# ashfall installer. Run from the NixOS live USB:
#   sudo nix --extra-experimental-features 'nix-command flakes' run github:thedeadbyte/ashfall
#
# Asks a few questions, writes your machine config, erases and encrypts the
# chosen disk, optionally enrolls YubiKeys, and installs.
#
# Reinstall from a config you already have (skips the questions):
#   ... run github:thedeadbyte/ashfall -- --config /path/to/clone --host NAME
#
# Environment (mostly for testing):
#   ASHFALL_DRY_RUN=1   only generate the config folder; touch no disks
#   ASHFALL_OUT=DIR     where to write the config (default /tmp/ashfall-config)
#   ASHFALL_FLAKE=REF   flake the generated config uses for ashfall

: "${ASHFALL_FLAKE:=github:thedeadbyte/ashfall}"
: "${DISKO:=disko}"
: "${STATE_VERSION:=26.05}"
DRY_RUN="${ASHFALL_DRY_RUN:-0}"
OUT="${ASHFALL_OUT:-/tmp/ashfall-config}"
PASSFILE=/tmp/luks-recovery.pass
# Answers, filled in by the prompts below
USERNAME="" FULLNAME="" HOST="" TZONE="" KBD="" LOCALE="" DISK="" SWAP=""
JS_SITES="" LUKS_PASS="" USER_PASS="" pick="" confirm=""
export NIX_CONFIG="experimental-features = nix-command flakes"
EXISTING="" EXISTING_HOST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) EXISTING=$(cd "${2:?--config needs a folder}" && pwd); shift 2 ;;
    --host) EXISTING_HOST=${2:?--host needs a name}; shift 2 ;;
    -h|--help)
      echo "Usage: ashfall-install                          (guided install)"
      echo "       ashfall-install --config DIR --host NAME (install an existing config)"
      exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 1 ;;
  esac
done
if [ -n "$EXISTING" ] && [ -z "$EXISTING_HOST" ]; then
  echo "--config also needs --host NAME (the nixosConfigurations name)" >&2; exit 1
fi
PERSIST_CONFIG=1

# ---------- output helpers ----------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
else
  B=""; DIM=""; RED=""; GRN=""; YLW=""; RST=""
fi
step=0
if [ -n "$EXISTING" ]; then TOTAL=5; else TOTAL=9; fi
section() { step=$((step + 1)); printf '\n%s==> [%d/%d] %s%s\n' "$B" "$step" "$TOTAL" "$*" "$RST"; }
info()    { printf '  %s\n' "$*"; }
note()    { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
ok()      { printf '  %s✔%s %s\n' "$GRN" "$RST" "$*"; }
warn()    { printf '  %s!%s %s\n' "$YLW" "$RST" "$*"; }
die()     { printf '\n%sERROR:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

cleanup() {
  if [ -f "$PASSFILE" ]; then shred -u "$PASSFILE" 2>/dev/null || rm -f "$PASSFILE"; fi
}
trap cleanup EXIT

# ask VAR "Question" "default"
ask() {
  local __var=$1 __q=$2 __def=${3:-} __ans
  if [ -n "$__def" ]; then
    read -rp "  $__q [$__def]: " __ans || true
    __ans=${__ans:-$__def}
  else
    read -rp "  $__q: " __ans || true
  fi
  printf -v "$__var" '%s' "$__ans"
}

# yesno "Question" y|n  -> exit status 0 for yes
yesno() {
  local q=$1 def=$2 hint ans
  if [ "$def" = y ]; then hint="Y/n"; else hint="y/N"; fi
  while true; do
    read -rp "  $q [$hint]: " ans || true
    ans=${ans:-$def}
    case "$ans" in
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]) return 1 ;;
      *) echo "  please answer y or n" ;;
    esac
  done
}

# ask_secret VAR "Label" minlen
ask_secret() {
  local __var=$1 __label=$2 __min=$3 __a __b
  while true; do
    read -rsp "  $__label: " __a || true; echo
    read -rsp "  Confirm: " __b || true; echo
    if [ "$__a" != "$__b" ]; then echo "  did not match, try again"; continue; fi
    if [ "${#__a}" -lt "$__min" ]; then echo "  must be at least $__min characters"; continue; fi
    break
  done
  printf -v "$__var" '%s' "$__a"
}

# Escape a value for a Nix double-quoted string
nixstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g'; }
nixbool() { if [ "$1" = 1 ]; then echo true; else echo false; fi; }

cat <<EOF

${B}ashfall installer${RST}
A NixOS laptop that wipes itself back to a clean system on every boot.

This will ${B}erase one whole disk${RST}. You'll be asked a few questions first;
nothing is touched until you confirm at the end. Ctrl+C quits at any time.
EOF
[ "$DRY_RUN" = 1 ] && printf '\n  %sDRY RUN: only the config folder will be written.%s\n' "$YLW" "$RST"

# ---------- 1. preflight ----------
section "Checking the environment"
if [ "$DRY_RUN" != 1 ]; then
  [ "$(id -u)" -eq 0 ] || die "run as root: sudo nix run github:thedeadbyte/ashfall"
  [ -d /sys/firmware/efi ] || die "booted in legacy BIOS mode; ashfall needs UEFI (check your firmware boot menu)"
  for t in nixos-install nixos-generate-config systemd-cryptenroll systemd-id128 lsblk findmnt; do
    command -v "$t" >/dev/null || die "missing $t; run this from the NixOS installer USB"
  done
  curl -fsS -o /dev/null https://cache.nixos.org/nix-cache-info 2>/dev/null \
    || die "no internet connection (connect Wi-Fi from the top-right menu, then rerun)"
  ok "UEFI, installer tools, and network OK"
else
  ok "skipped (dry run)"
fi

if [ -n "$EXISTING" ]; then
# ---------- 2'. read an existing config ----------
section "Reading $EXISTING#$EXISTING_HOST"
[ -f "$EXISTING/flake.nix" ] || die "no flake.nix in $EXISTING"
git -C "$EXISTING" rev-parse >/dev/null 2>&1 || die "$EXISTING must be a git clone (flakes only see tracked files)"
opt() { nix eval --raw "$EXISTING#nixosConfigurations.$EXISTING_HOST.config.$1" 2>/dev/null; }
optb() { if [ "$(nix eval --json "$EXISTING#nixosConfigurations.$EXISTING_HOST.config.$1" 2>/dev/null)" = true ]; then echo 1; else echo 0; fi; }
info "evaluating (downloads sources on first run)..."
USERNAME=$(opt ashfall.user.name) || die "could not evaluate $EXISTING_HOST; is it an ashfall config?"
FULLNAME=$(opt ashfall.user.description)
HOST=$(opt networking.hostName)
TZONE=$(opt time.timeZone || echo "?")
KBD=$(opt services.xserver.xkb.layout || echo "?")
DISK=$(opt ashfall.disk.device)
SWAP=$(opt ashfall.disk.swapSize || echo none)
WIPE_HOME=$(optb ashfall.wipeHome)
YUBI=$(optb ashfall.yubikey.luksUnlock)
FIREFOX=$(optb ashfall.firefox.enable)
JSBLOCK=$(optb ashfall.firefox.blockJavaScript)
PWMGR=$(opt ashfall.firefox.passwordManager)
CLAM=$(optb ashfall.clamav.enable)
TS=$(optb ashfall.tailscale.enable)
DEV=$(optb ashfall.dev.enable)
PERSIST_CONFIG=$(optb ashfall.persistConfig)
[ "$HOST" = "$EXISTING_HOST" ] || warn "hostName is $HOST but you asked for $EXISTING_HOST"
if [ "$DRY_RUN" != 1 ]; then
  [ -b "$DISK" ] || die "config says disk $DISK, which does not exist on this machine"
fi
ok "user $USERNAME, disk $DISK"
else

# ---------- 2. you ----------
section "About you and this machine"
while true; do
  ask USERNAME "Username (lowercase)" ""
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$USERNAME" != root ] && break
  echo "  use lowercase letters, digits, - or _, starting with a letter"
done
ask FULLNAME "Full name (shown at login)" "$USERNAME"
while true; do
  ask HOST "Computer name" "ashfall"
  [[ "$HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
  echo "  use letters, digits and -"
done
detected_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
while true; do
  ask TZONE "Time zone (e.g. America/New_York)" "${detected_tz:-UTC}"
  if [ "$TZONE" = UTC ] || [ ! -d /etc/zoneinfo ] || [ -f "/etc/zoneinfo/$TZONE" ]; then break; fi
  echo "  unknown time zone; examples: America/Chicago, Europe/Berlin, Asia/Tokyo"
done
ask KBD "Keyboard layout" "us"
ask LOCALE "Language/locale" "en_US.UTF-8"

# ---------- 3. disk ----------
section "Disk"
live_disk=""
if src=$(findmnt -no SOURCE /iso 2>/dev/null); then
  live_disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
fi
mapfile -t disks < <(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}' \
  | grep -Ev '/(loop|zram|sr|ram)' | grep -vx "/dev/${live_disk:-none}" || true)
i=0
for d in "${disks[@]}"; do
  i=$((i + 1))
  printf '  %d) %-14s %8s  %s\n' "$i" "$d" "$(lsblk -dno SIZE "$d")" "$(lsblk -dno MODEL "$d" | xargs)"
done
manual=$((i + 1))
printf '  %d) type a device path\n' "$manual"
while true; do
  ask pick "Install to which disk? (number)" ""
  if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ]; then
    DISK=${disks[$((pick - 1))]}; break
  elif [ "$pick" = "$manual" ]; then
    ask DISK "Device path (e.g. /dev/nvme0n1)" ""
    if [ "$DRY_RUN" = 1 ] || [ -b "$DISK" ]; then break; fi
    echo "  $DISK is not a block device"
  else
    echo "  pick a number from the list"
  fi
done
ok "target: $DISK"

note "Swap lets the system move idle memory to disk (in addition to compressed RAM)."
while true; do
  ask SWAP "Swapfile size (e.g. 8G), or none" "8G"
  if [[ "$SWAP" =~ ^[0-9]+[GM]$ ]] || [ "$SWAP" = none ]; then break; fi
  echo "  use a size like 8G or 512M, or none"
done

# ---------- 4. security ----------
section "Security"
note "Every boot wipes the system back to its declared state. Wiping your home"
note "folder too means downloads, browser data, and anything malware left behind"
note "are gone after a reboot. Keep important files in a cloud service or USB."
WIPE_HOME=0; yesno "Wipe your home folder on every boot? (recommended)" y && WIPE_HOME=1
echo
note "The disk is always encrypted. A YubiKey 5 (FIDO2) can unlock it at boot with"
note "a PIN and a touch instead of typing the passphrase."
YUBI=0; yesno "Unlock the disk with a YubiKey?" n && YUBI=1

# ---------- 5. extras ----------
section "Optional features"
note "Each group can be turned on or off later in configuration.nix."
echo
info "${B}Hardened Firefox${RST}: uBlock Origin, telemetry off, JavaScript off by default"
info "(you allow it per site), Firefox as default browser with vertical tabs."
FIREFOX=0; JSBLOCK=1; PWMGR=none; JS_SITES=""
if yesno "Install hardened Firefox?" y; then
  FIREFOX=1
  yesno "Block JavaScript by default? (strongest, some sites need allowing)" y || JSBLOCK=0
  yesno "Install the Proton Pass extension?" n && PWMGR=proton-pass
  if [ "$JSBLOCK" = 1 ]; then
    ask JS_SITES "Sites to allow JavaScript on, space separated (optional)" ""
  fi
fi
echo
info "${B}Malware scanning${RST}: ClamAV checks every file that lands in Downloads and"
info "quarantines anything infected."
CLAM=0; yesno "Install malware scanning?" y && CLAM=1
echo
info "${B}Tailscale${RST}: private network to your other devices. Runs as an ephemeral"
info "device that removes itself when offline; sign in each boot with 'tsup'."
TS=0; yesno "Install Tailscale?" n && TS=1
echo
info "${B}Developer setup${RST}: Neovim with LazyVim, the Ghostty terminal (Ctrl+Alt+T),"
info "and their tools."
DEV=0; yesno "Install the developer setup?" n && DEV=1

fi # end of guided questions

# ---------- 6. passwords ----------
section "Passwords"
note "Disk passphrase: needed at boot$( [ "$YUBI" = 1 ] && echo " if no YubiKey is present" ). If you lose it"
note "$( [ "$YUBI" = 1 ] && echo "and your keys, " )the data is unrecoverable. Write it down somewhere safe."
ask_secret LUKS_PASS "Disk passphrase (12+ characters)" 12
echo
note "Login password for $USERNAME (login screen and sudo)."
ask_secret USER_PASS "Login password" 1
USER_HASH=$(printf '%s\n' "$USER_PASS" | mkpasswd -m yescrypt --stdin)
unset USER_PASS
ok "passwords set"

# ---------- 7. confirm ----------
section "Review"
yn() { if [ "$1" = 1 ]; then echo yes; else echo no; fi; }
cat <<EOF
  User            $USERNAME ($FULLNAME)
  Computer name   $HOST
  Time zone       $TZONE
  Keyboard        $KBD
  Disk            $DISK  ${RED}(will be erased)${RST}
  Swapfile        $SWAP
  Wipe home       $(yn "$WIPE_HOME")
  YubiKey unlock  $(yn "$YUBI")
  Firefox         $(yn "$FIREFOX")$( [ "$FIREFOX" = 1 ] && echo " (JS blocked: $(yn "$JSBLOCK"), password manager: $PWMGR)")
  ClamAV          $(yn "$CLAM")
  Tailscale       $(yn "$TS")
  Developer       $(yn "$DEV")
EOF
echo
if [ "$DRY_RUN" != 1 ]; then
  dname=$(basename "$DISK")
  ask confirm "Type ${B}$dname${RST} to erase it and install" ""
  [ "$confirm" = "$dname" ] || die "not confirmed; nothing was changed"
fi

if [ -n "$EXISTING" ]; then
  OUT=$EXISTING
  HOST=$EXISTING_HOST
  [ "$DRY_RUN" = 1 ] && { ok "dry run complete (existing config read OK)"; exit 0; }
else
# ---------- 8. config ----------
section "Writing your configuration to $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

sites_nix=""
for s in $JS_SITES; do sites_nix="$sites_nix\"$(nixstr "$s")\" "; done
if [ "$SWAP" = none ]; then swap_nix=null; else swap_nix="\"$SWAP\""; fi

cat > "$OUT/flake.nix" <<EOF
{
  description = "$(nixstr "$HOST"): built on ashfall";

  inputs = {
    ashfall.url = "$(nixstr "$ASHFALL_FLAKE")";
    nixpkgs.follows = "ashfall/nixpkgs";
  };

  outputs = { ashfall, nixpkgs, ... }: {
    nixosConfigurations."$(nixstr "$HOST")" = nixpkgs.lib.nixosSystem {
      modules = [
        ashfall.nixosModules.default
        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
EOF

cat > "$OUT/configuration.nix" <<EOF
# Written by the ashfall installer on $(date +%Y-%m-%d). Edit freely, then apply:
#   sudo nixos-rebuild switch
# Every option is documented at https://github.com/thedeadbyte/ashfall
{ pkgs, ... }:

{
  networking.hostName = "$(nixstr "$HOST")";
  time.timeZone = "$(nixstr "$TZONE")";
  i18n.defaultLocale = "$(nixstr "$LOCALE")";
  services.xserver.xkb.layout = "$(nixstr "$KBD")";
  console.useXkbConfig = true; # same layout at the disk-unlock prompt

  ashfall = {
    user.name = "$USERNAME";
    user.description = "$(nixstr "$FULLNAME")";
    disk.device = "$(nixstr "$DISK")";
    disk.swapSize = $swap_nix;

    wipeHome = $(nixbool "$WIPE_HOME");
    persistConfig = true; # keeps /etc/nixos across reboots

    yubikey.enable = $(nixbool "$YUBI");

    firefox = {
      enable = $(nixbool "$FIREFOX");
      blockJavaScript = $(nixbool "$JSBLOCK");
      jsAllowedSites = [ ${sites_nix}];
      passwordManager = "$PWMGR";
    };

    clamav.enable = $(nixbool "$CLAM");
    tailscale.enable = $(nixbool "$TS");
    dev.enable = $(nixbool "$DEV");

    # Anything else you want to survive reboots, for example:
    #   persist.userDirectories = [ "Documents" ];
    persist.directories = [ ];
    persist.userDirectories = [ ];
  };

  # Your packages (search: https://search.nixos.org/packages)
  environment.systemPackages = with pkgs; [ ];

  system.stateVersion = "$STATE_VERSION"; # Do not change after install
}
EOF

if [ "$DRY_RUN" = 1 ]; then
  printf '{ lib, ... }: { nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"; }\n' > "$OUT/hardware.nix"
else
  nixos-generate-config --no-filesystems --show-hardware-config > "$OUT/hardware.nix" 2>/dev/null
fi
ok "wrote flake.nix, configuration.nix, hardware.nix"

git -C "$OUT" init -q
git -C "$OUT" add -A
if [ "$DRY_RUN" = 1 ]; then
  ok "dry run complete: $OUT"
  exit 0
fi
info "pinning versions (flake.lock)..."
nix flake lock "$OUT"
git -C "$OUT" add -A
ok "config ready"
fi

# ---------- 9. install ----------
section "Installing (this takes a while: partition, encrypt, download, build)"
( umask 077; printf '%s' "$LUKS_PASS" > "$PASSFILE" )
unset LUKS_PASS

info "partitioning and encrypting $DISK..."
"$DISKO" --mode destroy,format,mount --yes-wipe-all-disks --flake "$OUT#$HOST"
findmnt /mnt >/dev/null || die "disk setup did not mount /mnt"
ok "disk encrypted and mounted"

if [ "$YUBI" = 1 ]; then
  luks_part=/dev/disk/by-partlabel/disk-main-luks
  enrolled=0
  while true; do
    echo
    info "Plug in ONE YubiKey to enroll (remove any others)."
    note "Grip a Nano by its sides; touching it types a code."
    read -rp "  Press Enter when ready, or type 'done' to finish: " ans || true
    [ "$ans" = "done" ] && break
    count=$(systemd-cryptenroll --fido2-device=list 2>/dev/null | grep -c '^/dev/' || true)
    if [ "$count" -ne 1 ]; then
      warn "expected exactly 1 key, found $count"
      continue
    fi
    info "enter the key's FIDO2 PIN, then touch it when it blinks"
    if systemd-cryptenroll --unlock-key-file="$PASSFILE" --fido2-device=auto \
         --fido2-with-client-pin=yes --fido2-with-user-presence=yes "$luks_part"; then
      enrolled=$((enrolled + 1))
      ok "key $enrolled enrolled"
      yesno "Enroll another key? (a spare is strongly recommended)" y || break
    else
      warn "enrollment failed (wrong PIN? no FIDO2 PIN set? set one with: ykman fido access change-pin)"
    fi
  done
  if [ "$enrolled" -eq 0 ]; then
    warn "no keys enrolled; the disk passphrase will be asked at boot"
  fi
fi

info "saving persistent state..."
mkdir -p /mnt/persist/etc /mnt/persist/secrets
chmod 700 /mnt/persist/secrets
systemd-id128 new > /mnt/persist/etc/machine-id
chmod 444 /mnt/persist/etc/machine-id
( umask 077; printf '%s\n' "$USER_HASH" > "/mnt/persist/secrets/$USERNAME.hash" )
unset USER_HASH
if [ "$PERSIST_CONFIG" = 1 ]; then
  mkdir -p /mnt/persist/etc/nixos
  cp -a "$OUT/." /mnt/persist/etc/nixos/
  ok "machine id, password hash, and config saved to /persist"
else
  ok "machine id and password hash saved to /persist (config not kept: persistConfig = false)"
fi

info "installing NixOS..."
nixos-install --root /mnt --flake "$OUT#$HOST" --no-root-passwd --no-channel-copy
ok "installed"

swapoff /mnt/.swapvol/swapfile 2>/dev/null || true
umount -R /mnt
cryptsetup close cryptroot 2>/dev/null || true

cat <<EOF

${GRN}${B}Done.${RST} Remove the USB stick and reboot.

  At boot:  $( [ "$YUBI" = 1 ] && echo "plug in a YubiKey, enter its PIN, touch it (or type the passphrase)" || echo "type your disk passphrase" )
  Log in:   $USERNAME
  Config:   $( [ "$PERSIST_CONFIG" = 1 ] && echo "/etc/nixos   (edit, then: sudo nixos-rebuild switch)" || echo "not kept on disk; clone your repo to edit and rebuild" )
  Keep it:  push your config to a private git repo so you can rebuild anywhere

Everything outside /etc/nixos and the persist list resets on every reboot.
EOF
