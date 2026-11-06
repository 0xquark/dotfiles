{ lib, pkgs, ... }:
{
  # Name of the active theme, for things that remember settings per theme (home/zen-spaces.nix)
  options.theme.name = lib.mkOption {
    type = lib.types.str;
    default = "blade-runner";
  };

  # Border of the focused window (home/sway.nix); each theme picks a soft version of its accent
  options.theme.focusedBorder = lib.mkOption {
    type = lib.types.str;
    default = "#b05e24"; # Blade Runner: burnt orange
  };

  # Cursor's colour theme (home/apps.nix); "Stylix" follows the active palette
  options.theme.cursorTheme = lib.mkOption {
    type = lib.types.str;
    default = "Eclipse: Solar"; # Blade Runner
  };

  # Extra themes, built next to the default (theme.nix). Switch with `nh os switch -s blues`,
  # back with `nh os switch -S`. Each one also gets its own entry in the boot menu.
  config.specialisation.blues.configuration = {
    environment.etc.specialisation.text = "blues"; # so `nh os switch` stays on it
    theme.name = "blues";
    theme.focusedBorder = "#4e6ea8";
    theme.cursorTheme = "Stylix";

    stylix = {
      image = lib.mkForce ../../wallpapers/blue_air.jpg;
      cursor.name = lib.mkForce "Bibata-Modern-Ice"; # white instead of amber

      # Night sky from the wallpaper: navy background, sky-blue accent, peach cloud edges
      base16Scheme = lib.mkForce {
        scheme = "Blues";
        author = "drquark";
        base00 = "0d1526"; # background: deep navy
        base01 = "131d33"; # bar, panels
        base02 = "1c2b47"; # selection
        base03 = "3a5079"; # inactive borders, comments
        base04 = "8395bb"; # dim text
        base05 = "d5dbeb"; # main text
        base06 = "e6e9f3"; # light text
        base07 = "f4f1ec"; # brightest text: cloud white
        base08 = "d9665e"; # errors: the plane's red stripe
        base09 = "e3a07c"; # urgent: deep peach
        base0A = "ebc8b0"; # warnings: lit cloud edge
        base0B = "93b98f"; # success: muted green
        base0C = "7cb2d4"; # pale sky
        base0D = "638bd3"; # main accent: sky blue
        base0E = "a596d0"; # lavender
        base0F = "4c72b1"; # deep blue
      };
    };

    # Blue folder icons instead of orange
    home-manager.sharedModules = [
      {
        stylix.icons.package = lib.mkForce (pkgs.papirus-icon-theme.override { color = "blue"; });
      }
    ];
  };
}
