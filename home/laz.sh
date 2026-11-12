# laz: run lazarus in this terminal and reach it from the host.
#   laz            start it here (resumes a kept VM); the background darkens until poweroff
#   laz -p 3d      keep the whole VM for 3 days (or 12h): starts it, or extends the time
#   laz sh [cmd]   another shell in the running VM, e.g. in a new tab
#   laz drop       delete the kept VM now
# Waybar and a timer also use: laz bar, laz open, laz copy-ip, laz gc
# $ghostty is set by basement.nix.
base=$HOME/oasis/basement
state=$base/.lazarus       # host only: the SSH key, the kept disk and its end time
shared=$base/work/.lazarus # the VM sees this as /work/.lazarus
key=$state/id_ed25519
img=$state/state.img
until_file=$state/kept-until
keep=""
shade=50 # percent of the normal background brightness while inside lazarus

# The VM gets new host keys on every throwaway boot and the port only
# listens on 127.0.0.1, so host key checks would only get in the way.
# -F /dev/null skips ~/.ssh/config: its CERN GSSAPI options are unknown to this ssh,
# and none of the host's SSH settings should reach the VM.
ssh_opts=(-F /dev/null -i "$key" -p 2222 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# microvm.nix names the QEMU process microvm@lazarus
running() { pgrep -f '^microvm@lazarus ' >/dev/null; }

# Darkens this terminal's background while you're in lazarus. The theme and
# the see-through wallpaper stay; the normal background comes back on exit.
dim() {
  if [ ! -t 0 ] || [ ! -t 1 ]; then return 0; fi
  local old reply r g b
  old=$(stty -g)
  stty raw -echo min 0 time 5
  printf '\e]11;?\a' >/dev/tty
  IFS= read -r -d $'\a' reply </dev/tty || true
  stty "$old"
  # The reply looks like ESC]11;rgb:1212/0a0a/1616 BEL
  if [[ $reply =~ rgb:([0-9a-fA-F]{2})[0-9a-fA-F]*/([0-9a-fA-F]{2})[0-9a-fA-F]*/([0-9a-fA-F]{2}) ]]; then
    r=$((16#${BASH_REMATCH[1]} * shade / 100))
    g=$((16#${BASH_REMATCH[2]} * shade / 100))
    b=$((16#${BASH_REMATCH[3]} * shade / 100))
    printf '\e]11;#%02x%02x%02x\a' "$r" "$g" "$b" >/dev/tty
    trap 'printf "\e]111\a" >/dev/tty' EXIT
  fi
}

# The kept VM's end time in seconds, or nothing
kept_until() {
  local t
  t=$(cat "$until_file" 2>/dev/null || true)
  if [[ $t =~ ^[0-9]+$ ]]; then echo "$t"; fi
}

set_until() {
  local t=$(($(date +%s) + keep))
  echo "$t" >"$until_file"
  date -d "@$t" '+%a %d %b %H:%M' >"$shared/kept-until"
}

# Deletes the kept VM once its time is up. It waits while the VM runs.
gc() {
  local t
  t=$(kept_until)
  if [ ! -e "$img" ] && [ -z "$t" ]; then return 0; fi
  if [ -n "$t" ] && [ "$(date +%s)" -lt "$t" ]; then return 0; fi
  if running; then return 0; fi
  rm -f "$img" "$until_file" "$shared/kept-until"
  echo "lazarus: the kept time ran out, so the kept VM is deleted"
}

start() {
  mkdir -p "$state" "$shared"
  chmod 700 "$state"
  if running; then
    if [ -n "$keep" ] && [ -n "$(kept_until)" ]; then
      set_until
      echo "lazarus: kept until $(cat "$shared/kept-until")"
      exit 0
    fi
    echo "lazarus is already running. laz sh opens another shell in it." >&2
    [ -n "$keep" ] && echo "To keep it, power it off and start it with laz -p." >&2
    exit 1
  fi
  gc

  if [ ! -f "$key" ]; then ssh-keygen -q -t ed25519 -N '' -C lazarus -f "$key"; fi
  cp "$key.pub" "$shared/authorized_keys"

  [ -n "$keep" ] && set_until
  if [ -n "$(kept_until)" ]; then
    vm=lazarus-kept
    echo "lazarus: starting, kept until $(cat "$shared/kept-until")"
  else
    vm=lazarus
    rm -f "$shared/kept-until"
    echo "lazarus: starting (throwaway)"
  fi

  dim
  cd "$base"
  nix run "$HOME/nixos#$vm"
}

shell() {
  if [ ! -f "$key" ]; then
    echo "lazarus has no SSH key yet. Start it with laz." >&2
    exit 1
  fi
  for i in $(seq 90); do
    if ! running; then
      echo "lazarus isn't running. Start it with laz." >&2
      exit 1
    fi
    if ssh "${ssh_opts[@]}" -o BatchMode=yes -o ConnectTimeout=2 root@127.0.0.1 true 2>/dev/null; then
      # Only an interactive shell gets the darker background; `laz sh htb ip` just prints
      [ $# -eq 0 ] && dim
      # shellcheck disable=SC2029 # the command is meant to run in the VM
      ssh "${ssh_opts[@]}" root@127.0.0.1 "$@"
      return
    fi
    [ "$i" = 1 ] && echo "Waiting for lazarus to boot…"
    sleep 1
  done
  echo "lazarus doesn't answer on SSH." >&2
  exit 1
}

drop() {
  if running; then
    echo "Power lazarus off first (poweroff in the VM)." >&2
    exit 1
  fi
  if [ -e "$img" ] || [ -e "$until_file" ]; then
    rm -f "$img" "$until_file" "$shared/kept-until"
    echo "lazarus: kept VM deleted"
  else
    echo "lazarus: nothing is kept"
  fi
}

# The lab IP from htb in the VM. The VM writes that file, so only an IP gets through.
lab_ip() {
  local ip
  ip=$(cat "$shared/lab-ip" 2>/dev/null || true)
  if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then echo "$ip"; fi
}

# Waybar label: LAZ while the VM runs, LAZ 10.10.14.7 while the HTB VPN is up
bar() {
  if ! running; then
    echo '{"text": ""}'
    return
  fi
  local ip t life
  ip=$(lab_ip)
  t=$(kept_until)
  if [ -n "$t" ]; then life="kept until $(date -d "@$t" '+%a %d %b %H:%M')"; else life=throwaway; fi
  if [ -n "$ip" ]; then
    printf '{"text": "LAZ %s", "tooltip": "lazarus, %s\\nLab IP %s. Click for a shell, right-click to copy the IP.", "class": "lab"}\n' "$ip" "$life" "$ip"
  else
    printf '{"text": "LAZ", "tooltip": "lazarus, %s\\nHTB VPN down. Click for a shell.", "class": "on"}\n' "$life"
  fi
}

# Waybar click: a new terminal with another lazarus shell
open() {
  setsid -f "$ghostty" -e "$0" sh >/dev/null 2>&1
}

copy_ip() {
  local ip
  ip=$(lab_ip)
  [ -n "$ip" ] || exit 0
  printf '%s' "$ip" | wl-copy
  notify-send -t 2000 lazarus "Copied $ip"
}

case "${1:-}" in
  "") start ;;
  -p)
    if [[ ${2:-} =~ ^([0-9]+)([dh])$ ]]; then
      n=${BASH_REMATCH[1]}
      if [ "${BASH_REMATCH[2]}" = d ]; then keep=$((n * 86400)); else keep=$((n * 3600)); fi
    fi
    if [ -z "$keep" ] || [ "$keep" -eq 0 ]; then
      echo "laz: -p takes a time like 3d or 12h" >&2
      exit 1
    fi
    start
    ;;
  sh)
    shift
    shell "$@"
    ;;
  drop) drop ;;
  bar) bar ;;
  open) open ;;
  copy-ip) copy_ip ;;
  gc) gc ;;
  *)
    echo "usage: laz | laz -p 3d | laz sh [cmd] | laz drop" >&2
    exit 1
    ;;
esac
