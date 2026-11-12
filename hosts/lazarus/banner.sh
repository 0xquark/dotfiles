# Startup banner for lazarus: Gargantua, the mission name, and the few things worth remembering
art=(
  '                  ·          .      *         ·'
  '       *     .        ▁▂▄▅▆▇█████████▇▆▅▄▂▁        .        ·'
  '          ·       ▗▄▆██▀▀▀▔           ▔▀▀▀██▆▄▖       *'
  '     .          ▗▟█▀▘                       ▝▀█▙▖           .'
  '            ·  ▐█▌                             ▐█▌    ·'
  '  ░░▒▒▓▓█████████████████████████████████████████████████▓▓▒▒░░'
  '            .  ▐█▌                             ▐█▌        *'
  '     *          ▝▜█▄▖                       ▗▄█▛▘    .'
  '          .       ▝▀▜██▄▄▄▁           ▁▄▄▄██▛▀▘       ·       .'
  '       ·      *       ▔▀▀▀▀▀█████████▀▀▀▀▀▔       .'
  '                  .          ·      *         ·'
)
# Ring colours per row: steel grey, brightest on the disk
ring=(240 252 249 246 246 255 246 246 249 252 240)

title=(
  '██╗      █████╗ ███████╗ █████╗ ██████╗ ██╗   ██╗███████╗'
  '██║     ██╔══██╗╚══███╔╝██╔══██╗██╔══██╗██║   ██║██╔════╝'
  '██║     ███████║  ███╔╝ ███████║██████╔╝██║   ██║███████╗'
  '██║     ██╔══██║ ███╔╝  ██╔══██║██╔══██╗██║   ██║╚════██║'
  '███████╗██║  ██║███████╗██║  ██║██║  ██║╚██████╔╝███████║'
  '╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝'
)
heat=(255 253 251 249 246 243)

c() { printf '\e[38;5;%sm' "$1"; }
star=$(c 240)
reset=$'\e[0m'

echo
for i in "${!art[@]}"; do
  col=$(c "${ring[$i]}")
  line=${art[$i]}
  # Stars stay dim; everything else takes the row's colour
  for s in '·' '.' '*'; do line=${line//"$s"/$star$s$col}; done
  printf '%s%s%s\n' "$col" "$line" "$reset"
done
echo
for i in "${!title[@]}"; do
  printf '    %s%s%s\n' "$(c "${heat[$i]}")" "${title[$i]}" "$reset"
done

dim=$(c 244)
key=$(c 252)
echo
row() { printf '    %s%-9s%s%s%s%s\n' "$key" "$1" "$reset" "$dim" "$2" "$reset"; }
row /work "~/oasis/basement/work on the host"
row vpn "htb up · htb ip · htb down · htb log"
row boxes "scan <ip> · addhost <ip> <name> · serve"
row shells "laz sh in another tab on the host"
row burp "SOCKS proxy 127.0.0.1:1080 on the host"
if [ -d /work/.history ]; then
  row history "kept in /work/.history (rm -r it to stop)"
else
  row history "off · mkdir /work/.history to keep it"
fi
if [ "$(findmnt -no FSTYPE /)" = tmpfs ]; then
  row state "throwaway · laz -p 3d to keep it"
else
  row state "kept until $(cat /work/.lazarus/kept-until 2>/dev/null) · laz drop to wipe it"
fi
row leave poweroff
echo
printf '    %s"Do not go gentle into that good night."%s\n\n' "$(c 240)" "$reset"
