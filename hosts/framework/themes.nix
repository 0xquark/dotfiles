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

  # Extra themes, built next to the default (theme.nix). Switch with `nh os switch -s blues` (or v, joi),
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

  # Edgerunners on the moon: black space, David's yellow jacket, Lucy's pastel hair
  config.specialisation.v.configuration = {
    environment.etc.specialisation.text = "v";
    theme.name = "v";
    theme.focusedBorder = "#bdb524";
    theme.cursorTheme = "Stylix";

    stylix = {
      image = lib.mkForce ../../wallpapers/CyberRunners/cyber-edgerunner.png;
      cursor.name = lib.mkForce "Bibata-Modern-Classic"; # black, like the sky around the planet

      base16Scheme = lib.mkForce {
        scheme = "V";
        author = "drquark";
        base00 = "07080d"; # background: space black with a hint of blue
        base01 = "0e111b"; # bar, panels
        base02 = "1b2133"; # selection: Lucy's navy suit
        base03 = "3f4f72"; # inactive borders, comments: the suit's highlight
        base04 = "9a9a8e"; # dim text: moon dust
        base05 = "e6dcc8"; # main text: lit cloud cream
        base06 = "f2ead9"; # light text
        base07 = "fdf6e3"; # brightest text: sunlit cloud
        base08 = "e5484d"; # errors: Lucy's red plug
        base09 = "eb9a4a"; # urgent: sunset over the continents
        base0A = "e8b84a"; # warnings: city lights gold
        base0B = "a3c43c"; # success: the jacket's green shadow
        base0C = "6cd3cf"; # cyan: sleeve stripes and the atmosphere
        base0D = "f5ec2e"; # main accent: David's jacket yellow
        base0E = "e3a9f2"; # pink-lavender: Lucy's hair
        base0F = "3d7bb0"; # deep atmosphere blue
      };
    };

    # Yellow folder icons
    home-manager.sharedModules = [
      {
        stylix.icons.package = lib.mkForce (pkgs.papirus-icon-theme.override { color = "yellow"; });
      }
    ];
  };

  # Joi's hologram over K: violet smog, magenta neon, blue-violet hair
  config.specialisation.joi.configuration = {
    environment.etc.specialisation.text = "joi";
    theme.name = "joi";
    theme.focusedBorder = "#a8479a";
    theme.cursorTheme = "Stylix";

    stylix = {
      image = lib.mkForce ../../wallpapers/Blade_Runner/blade_runner_purple.png;
      cursor.name = lib.mkForce "Bibata-Modern-Ice"; # white, like the lamps in the fog

      base16Scheme = lib.mkForce {
        scheme = "Joi";
        author = "drquark";
        base00 = "120a17"; # background: violet night
        base01 = "1b1022"; # bar, panels
        base02 = "2e1a3c"; # selection
        base03 = "553a6e"; # inactive borders, comments: smog
        base04 = "a48fbf"; # dim text
        base05 = "e6d6ee"; # main text
        base06 = "f1e6f6"; # light text
        base07 = "fbf4fd"; # brightest text
        base08 = "e2506e"; # errors: rose red
        base09 = "e88aa8"; # urgent: Joi's lips
        base0A = "e6c477"; # warnings: warm gold
        base0B = "8fc7a0"; # success: muted green
        base0C = "5fb8d8"; # cyan: the lamp in the fog
        base0D = "e05cc4"; # main accent: hologram magenta
        base0E = "8a62e6"; # violet: Joi's hair
        base0F = "4a35a8"; # deep blue: the hair's shadow
      };
    };

    # Magenta folder icons
    home-manager.sharedModules = [
      {
        stylix.icons.package = lib.mkForce (pkgs.papirus-icon-theme.override { color = "magenta"; });
      }
    ];
  };
}
