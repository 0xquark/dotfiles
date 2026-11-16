{ pkgs, ... }:

{
  # Layout on the login screen and text consoles (Sway sets its own in sway.nix)
  services.xserver.xkb = {
    layout = "us";
    variant = "mac";
  };
  console.useXkbConfig = true;

  # Mac-style copy and paste: Alt (where Cmd sits on a Mac) + C / V, in every app
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          capslock = "overload(hyper, capslock)"; # hold = Hyper, tap = Caps Lock
        };
        alt = {
          c = "C-insert"; # copy   = Ctrl+Insert (works even in terminals)
          v = "S-insert"; # paste  = Shift+Insert
          a = "C-a"; # select all
        };
        # Leave Alt+Shift+V alone: it's Vicinae's clipboard history
        "alt+shift" = {
          v = "A-S-v";
        };
      };
      # The Hyper layer: while Caps is held, it acts as Ctrl+Alt+Super+Shift
      extraConfig = ''
        [hyper:C-A-M-S]
      '';
    };

    # Logi POP Mouse: the middle button goes back, like a side button.
    # keyd only takes over mice listed by id (find it with: keyd monitor).
    keyboards.popmouse = {
      ids = [ "m:046d:b030" ];
      settings.main.middlemouse = "mouse1";
    };
  };

  # Logi POP Mouse: the Emoji button behind the wheel closes the tab (Alt+W).
  # The mouse can only remap it to a click by itself, so logid takes it over.
  # Button ids come from: solaar show "Logi POP Mouse"
  services.logiops =
    let
      libconfig = (pkgs.formats.libconfig { }).lib;
    in
    {
      enable = true;
      config.devices = [
        {
          name = "Logi POP Mouse";
          buttons = [
            {
              cid = 264; # 0x108, Emoji
              action = {
                type = "Keypress";
                keys = libconfig.mkArray [
                  "KEY_LEFTALT"
                  "KEY_W"
                ];
              };
            }
          ];
        }
      ];
    };

  # keyd appears as a new keyboard; this keeps "ignore touchpad while typing" working
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Serial Keyboards]
    MatchUdevType=keyboard
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
  '';
}
