{ inputs, pkgs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.beta inputs.spicetify-nix.homeManagerModules.spicetify ];
  
 # Keyroost (Token2 key manager): shows up in Vicinae and app menus
  xdg.desktopEntries.keyroost = {
    name = "Keyroost";
    comment = "Manage Token2 and other security keys";
    exec = "/home/drquark/Applications/keyroost.AppImage";
    icon = "security-high";
    categories = [ "Utility" "Security" ];
  };
  # ── Browser ──────────────────────────
  programs.zen-browser.enable = true;

  # Spotify, coloured by Stylix
  programs.spicetify.enable = true;
  
  # ── Terminal ─────────────────────────
  programs.ghostty = {
    enable = true;
    settings = {
      window-padding-x = 12;
      window-padding-y = 12;
      cursor-style = "bar";
      confirm-close-surface = false;   # close without asking
      keybind = [
        "ctrl+insert=copy_to_clipboard"
        "shift+insert=paste_from_clipboard"
        "ctrl+a=select_all"            # Alt+A (via keyd) selects everything
      ];
    };
  };

  # ── Editor ───────────────────────────
  programs.neovim = {
    enable = true;
    defaultEditor = true;              # used by git commit, sudoedit, etc.
    viAlias = true;                    # alias for vi
  };

  # ── Other Applications ───────────────
  home.packages = with pkgs; [
    discord
    zoom-us
    obsidian
    pkgs.element-desktop
  ];
}
