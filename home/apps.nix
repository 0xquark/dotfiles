{ inputs, pkgs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.beta inputs.spicetify-nix.homeManagerModules.spicetify ];

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
  ];
}