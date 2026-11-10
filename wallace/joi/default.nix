# Joi, the voice assistant in the bar, and the other characters (Darlene,
# Caitlyn, TARS): Hermes profiles on a local model. Docs in docs/assistant.
{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.hermes-agent.homeManagerModules.default
    ./model.nix
    ./hermes.nix
    ./voice.nix
    ./desktop.nix
  ];

  options.wallace.joi = {
    sleepAfter = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "Minutes with nothing asked of Joi before she falls asleep and frees the memory.";
    };
    notesFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Documents/notes.md";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Documents/notes.md"'';
      description = "The markdown list her add_note, read_notes and cross_off tools keep.";
    };
    chargeLimitCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A command that takes `toggle` and switches the battery charge limit
        between 80% and 100%. Joi's battery tool uses it for "charge to full";
        without one, she can only read the battery.
      '';
    };
  };
}
