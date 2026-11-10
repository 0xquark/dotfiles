# CERN VPN (eduVPN): shows it in the bar, and connects or disconnects on click
# eduVPN hands the tunnel to NetworkManager, so it stays up with no eduVPN window open.
# The first connect of the day opens the CERN login in the browser.
{ pkgs }:
pkgs.writeShellScript "vpn" ''
  nmcli=${pkgs.networkmanager}/bin/nmcli
  eduvpn=${pkgs.eduvpn-client}/bin/eduvpn-cli
  busy="$XDG_RUNTIME_DIR/vpn-busy"
  on() { $nmcli -t -f NAME connection show --active | grep -qx eduVPN; }

  if [ "$1" = toggle ]; then
    [ -e "$busy" ] && exit   # a click is already being handled
    touch "$busy"
    pkill -RTMIN+9 waybar
    if on; then
      $eduvpn disconnect
    else
      # Five minutes covers a browser login; then the bar is clickable again
      timeout 300 $eduvpn -y connect -n 1 \
        || ${pkgs.libnotify}/bin/notify-send "VPN" "Couldn't connect to CERN. Right-click VPN to open eduVPN."
    fi
    rm -f "$busy"
    pkill -RTMIN+9 waybar
    exit
  fi

  if [ -e "$busy" ]; then
    echo '{"text": "VPN", "tooltip": "Connecting or disconnecting…", "class": "busy"}'
  elif on; then
    # The session ends at a set time, after which CERN asks for a new login
    until=$(${pkgs.jq}/bin/jq -r '[.v2.server_list[].expire_time] | first // empty' "$HOME/.config/eduvpn/state.json" 2>/dev/null)
    [ -n "$until" ] && until=" until $(date -d "$until" +%H:%M)"
    echo "{\"text\": \"VPN\", \"tooltip\": \"CERN VPN on$until. Click to disconnect.\", \"class\": \"on\"}"
  else
    echo '{"text": "VPN", "tooltip": "CERN VPN off. Click to connect.", "class": "off"}'
  fi
''
