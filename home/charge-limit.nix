# Battery charge limit: shows it in the bar, and switches between 80% and 100% on click
# The laptop's controller keeps the limit; framework_tool sets it (sudo rule in battery.nix).
# Reading it needs root too, so the last value set is kept in a file; every boot starts at 80.
{ pkgs }:
pkgs.writeShellScript "charge-limit" ''
  state="$XDG_RUNTIME_DIR/charge-limit"
  now=$(cat "$state" 2>/dev/null || echo 80)
  if [ "$1" = toggle ]; then
    if [ "$now" -le 80 ]; then new=100; else new=80; fi
    /run/wrappers/bin/sudo -n ${pkgs.framework-tool}/bin/framework_tool --charge-limit "$new" >/dev/null \
      && echo "$new" > "$state"
    pkill -RTMIN+8 waybar   # refresh the bar right away
    exit
  fi
  if [ "$now" -le 80 ]; then
    echo '{"text": "LIM 80%", "tooltip": "Battery stops at 80%. Click to charge to 100%.", "class": "limited"}'
  else
    echo '{"text": "LIM", "tooltip": "Charging to 100%. Click to stop at 80%.", "class": "full"}'
  fi
''
