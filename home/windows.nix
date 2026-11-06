{ lib, pkgs, ... }:
let
  hyper = "Mod4+Mod1+Control+Shift"; # Caps held, as in keys.nix
  jq = "${pkgs.jq}/bin/jq";

  # Every open window in a Vicinae list: pick one, then choose what to do with it
  windows = pkgs.writeShellScript "windows" ''
    # Opening it again while it's up closes it
    if pgrep -f "vicinae dmenu" >/dev/null; then
      vicinae close
      exit
    fi

    pick() { vicinae dmenu --no-quick-look "$@"; }

    # App name from its .desktop file, e.g. com.mitchellh.ghostty → Ghostty
    declare -A names
    name() {
      if [ -z "''${names[$1]}" ]; then
        local dir file
        names[$1]=$1
        IFS=: read -ra dirs <<<"''${XDG_DATA_HOME:-$HOME/.local/share}:$XDG_DATA_DIRS"
        for dir in "''${dirs[@]}"; do
          file=$dir/applications/$1.desktop
          if [ -f "$file" ]; then
            names[$1]=$(sed -n 's/^Name=//p' "$file" | head -n1)
            break
          fi
        done
      fi
      echo "''${names[$1]}"
    }

    # One line per window: id, workspace, tiled/floating, app, title
    list=$(swaymsg -t get_tree | ${jq} -r '
      .. | select(.type? == "workspace") | .name as $ws
      | .. | select((.type? == "con" or .type? == "floating_con") and .pid != null)
      | [ .id,
          (if $ws == "__i3_scratch" then "hidden" else $ws end),
          (if .type == "floating_con" then "floating" else "tiled" end),
          (.app_id // .window_properties.class // "unknown"),
          (.name // "untitled") ]
      | @tsv')
    [ -n "$list" ] || exit

    # Shown as "Ghostty — ~/nixos   (workspace 1)"; Vicinae hands back that text
    declare -A ids wss kinds titles
    lines=()
    while IFS=$'\t' read -r id ws kind app title; do
      case $ws/$kind in
        hidden/*) where="hidden" ;;
        */floating) where="workspace $ws, floating" ;;
        *) where="workspace $ws" ;;
      esac
      app=$(name "$app")
      # Drop the app's name from the end of the title: "notes.md - Cursor" → "notes.md"
      short=''${title% [-—] "''${app%% *}"*}
      label="$app — ''${short:-$title}   ($where)"
      # Two windows with the same title still need different lines
      base=$label n=2
      while [ -n "''${ids["$label"]}" ]; do label="$base #$n"; n=$((n + 1)); done
      ids["$label"]=$id wss[$id]=$ws kinds[$id]=$kind titles[$id]=$title
      lines+=("$label")
    done <<<"$list"

    chosen=$(printf '%s\n' "''${lines[@]}" \
      | pick -n Windows -s "Open windows ({count})" -p "Search windows…") || exit
    id=''${ids["$chosen"]}
    [ -n "$id" ] || exit
    ws=''${wss[$id]} kind=''${kinds[$id]} title=''${titles[$id]}
    on="[con_id=$id]"

    # Enter twice goes straight to the window
    action=$(printf '%s\n' "Go to" "Bring here" "Send to workspace…" "Float / tile" "Hide" "Close" \
      | pick -n "$title" -s Actions -p "What should this window do?") || exit

    case $action in
      "Go to" | "Bring here")
        if [ "$ws" = hidden ]; then
          swaymsg "$on scratchpad show"
        elif [ "$action" = "Go to" ]; then
          swaymsg "$on focus"
        else
          here=$(swaymsg -t get_workspaces | ${jq} -r '.[] | select(.focused).name')
          swaymsg "$on move container to workspace \"$here\", focus"
          # A floating window from the other screen could land off to one side
          [ "$kind" = floating ] && swaymsg "$on move position center"
        fi
        ;;
      "Send to workspace…")
        to=$(seq 1 9 | pick -n "$title" -s "Send to workspace" -p "Workspace…") || exit
        [ "$ws" = hidden ] && swaymsg "$on scratchpad show"
        swaymsg "$on move container to workspace \"$to\""
        ;;
      "Float / tile") swaymsg "$on floating toggle" ;;
      "Hide") swaymsg "$on move scratchpad" ;;
      "Close") swaymsg "$on kill" ;;
    esac
  '';
in
{
  # Swipe three fingers down (or Hyper+W) for the window list; swipe up closes it
  wayland.windowManager.sway = {
    extraConfig = ''
      bindgesture swipe:3:down exec ${windows}
      bindgesture swipe:3:up exec vicinae close
    '';
    # mkOptionDefault adds to the other shortcuts, as in keys.nix
    config.keybindings = lib.mkOptionDefault { "${hyper}+w" = "exec ${windows}"; };
  };
}
