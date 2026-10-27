{ config, pkgs, ... }:
{
  stylix = {
    enable = true;
    polarity = "dark";

    # ── Wallpaper ─────────────────────────────────────
    # Plain bg for testing
    # Then: save it as ~/nixos/wallpapers/wall.jpg, git add it, and use this line instead
    image = ../../wallpapers/wall.jpg;

    # ── Palette (the table above) ─────────────────────
    base16Scheme = {
      scheme = "Blade Runner 2049";
      author = "drquark";
      base00 = "0b0806";  # background
      base01 = "17110c";  # bar, panels
      base02 = "2b1d13";  # selection
      base03 = "5c4532";  # inactive borders, comments
      base04 = "a0805e";  # dim text
      base05 = "e9d5bb";  # main text
      base06 = "f4e6d2";  # light text
      base07 = "fff4e6";  # brightest text
      base08 = "e2553d";  # errors
      base09 = "f59d3d";  # urgent
      base0A = "f7c04a";  # warnings
      base0B = "a5b46d";  # success
      base0C = "3fc1c9";  # teal neon
      base0D = "ff7a1a";  # main accent: orange
      base0E = "d94f9a";  # magenta neon
      base0F = "9a5b33";  # rust
    };

    # ── Fonts ─────────────────────────────────────────
    fonts = {
      monospace = { package = pkgs.nerd-fonts.jetbrains-mono; name = "JetBrainsMono Nerd Font"; };
      sansSerif = { package = pkgs.inter; name = "Inter"; };
      serif = config.stylix.fonts.sansSerif;
      emoji = { package = pkgs.noto-fonts-color-emoji; name = "Noto Color Emoji"; };
      sizes = { applications = 11; desktop = 11; popups = 11; terminal = 12; };
    };

    # ── Cursor ────────────────────────────────────────
    cursor = { package = pkgs.bibata-cursors; name = "Bibata-Modern-Amber"; size = 24; };

    # ── Slightly see-through terminal ─────────────────
    opacity.terminal = 0.92;

    # ── Keep Plasma's look untouched ──────────────────
    targets.qt.enable = false;
  };

  # The same idea for your user's apps (Home Manager side)
  home-manager.sharedModules = [
    {
      stylix.targets.kde.enable = false;   # Plasma keeps its own theme
      stylix.targets.qt.enable = false;    # Qt apps keep Breeze

      gtk.enable = true;
      gtk.iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme.override { color = "orange"; };
      };
    }
  ];
}