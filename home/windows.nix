{ lib, pkgs, ... }:
let
  hyper = "Mod4+Mod1+Control+Shift"; # Caps held, as in keys.nix
  jq = "${pkgs.jq}/bin/jq";

  # Every open window in one menu: pick one, then choose what to do with it
  windows = pkgs.writeShellScript "windows" ''
    # Opening it again while it's up closes it
    pkill -x fuzzel && exit

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

    # Shown as "3   title  · floating", with the app's icon
    pick=$(while IFS=$'\t' read -r id ws kind app title; do
        case $ws/$kind in
          hidden/*) ws=-; tag="  · hidden" ;;
          */floating) tag="  · floating" ;;
          *) tag="" ;;
        esac
        printf '%-3s %s%s\0icon\x1f%s\n' "$ws" "$title" "$tag" "$app"
      done <<<"$list" | fuzzel --dmenu --index --only-match --prompt "window: ") || exit
    IFS=$'\t' read -r id ws kind app title < <(sed -n "$((pick + 1))p" <<<"$list")
    on="[con_id=$id]"

    # Enter twice goes straight to the window
    action=$(printf '%s\n' "Go to" "Bring here" "Send to workspace…" "Float / tile" "Hide" "Close" \
      | fuzzel --dmenu --only-match --minimal-lines --placeholder "$title" --prompt "do: ") || exit

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
        to=$(seq 1 9 | fuzzel --dmenu --minimal-lines --prompt "workspace: ") || exit
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
  # Menus for the window picker and swayr; Stylix colours it
  programs.fuzzel = {
    enable = true;
    settings.main = {
      width = 70; # characters; room for long window titles
      lines = 12;
    };
  };

  # Swipe three fingers down (or Hyper+W) for the window list; swipe up closes it
  wayland.windowManager.sway = {
    extraConfig = ''
      bindgesture swipe:3:down exec ${windows}
      bindgesture swipe:3:up exec pkill -x fuzzel
    '';
    # mkOptionDefault adds to the other shortcuts, as in keys.nix
    config.keybindings = lib.mkOptionDefault { "${hyper}+w" = "exec ${windows}"; };
  };
}
