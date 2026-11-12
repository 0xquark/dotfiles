# htb: the HTB VPN in one word.
#   htb up [file.ovpn]   connect with the .ovpn in /work (asks if there are several)
#   htb ip               your lab IP, for reverse shells
#   htb down             disconnect
#   htb log              follow the OpenVPN log
pidfile=/run/htb.pid
log=/tmp/htb-vpn.log
shown=/work/.lazarus/lab-ip # read by the lazarus label in Waybar on the host

lab_ip() {
  ip -4 -o addr show tun0 2>/dev/null | awk '{ split($4, a, "/"); print a[1] }' || true
}

stop() {
  if [ -f "$pidfile" ]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
    sleep 1
  fi
  rm -f "$shown"
}

case "${1:-ip}" in
  up)
    if [ -n "${2:-}" ]; then
      ovpn=$2
    else
      mapfile -t files < <(find /work -maxdepth 2 -name '*.ovpn' | sort)
      case ${#files[@]} in
        0)
          echo "No .ovpn file in /work. Put one in ~/oasis/basement/work on the host." >&2
          exit 1
          ;;
        1) ovpn=${files[0]} ;;
        *) ovpn=$(printf '%s\n' "${files[@]}" | fzf --prompt 'vpn> ' --height 10) ;;
      esac
    fi
    stop # one tunnel at a time
    openvpn --config "$ovpn" --daemon --writepid "$pidfile" --log "$log"
    ip=""
    for _ in $(seq 30); do
      ip=$(lab_ip)
      [ -n "$ip" ] && break
      sleep 1
    done
    if [ -n "$ip" ]; then
      echo "$ip" > "$shown"
      echo "connected · $(basename "$ovpn") · $ip"
    else
      echo "No tunnel after 30 s. Check the log with: htb log" >&2
      exit 1
    fi
    ;;
  down)
    stop
    echo "disconnected"
    ;;
  ip)
    ip=$(lab_ip)
    if [ -n "$ip" ]; then echo "$ip"; else
      echo "not connected (htb up)" >&2
      exit 1
    fi
    ;;
  log) tail -f "$log" ;;
  *)
    echo "usage: htb up [file.ovpn] | ip | down | log" >&2
    exit 1
    ;;
esac
