# The local model every character runs on, warmed up when she wakes and put
# away again when she's idle
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./shared.nix { inherit config pkgs; })
    cfg
    modelPort
    gatewayPort
    awakeFile
    handoffs
    keyFile
    joiPower
    ;

  # Qwen3.5 4B: small, fast on the Arc GPU, and calls tools reliably
  model = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf";
    sha256 = "190ixxlzpl8012kkhfb02f9nzns9c0a22n25c8z4csszzy37kzh0";
  };

  # Its eyes: lets the same model read images, for the screen and the clipboard
  vision = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf";
    sha256 = "0r7qj4ld202sjb7ggf82xvmsdzp1nywwbjdh1fb98603ip7yv26d";
  };

  # Two throwaway chats once she's up, so the model has her prompt cached and
  # the first real question is as quick as the rest. The second one is what
  # settles the cache for this model. The laptop plugin blocks their tools.
  joiWarmup = pkgs.writeShellApplication {
    name = "joi-warmup";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      for _ in $(seq 240); do
        curl -sf http://127.0.0.1:${toString modelPort}/health >/dev/null &&
          curl -sf http://127.0.0.1:${toString gatewayPort}/health >/dev/null && break
        sleep 0.5
      done
      key=$(sed -n 's/^API_SERVER_KEY=//p' ${keyFile})
      for n in 1 2; do
        id="warmup-$(date +%s)-$n"
        curl -sf -m 120 -o /dev/null \
          -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
          -H "X-Hermes-Session-Id: $id" \
          -d '{"model": "joi", "messages": [{"role": "user", "content": "What is 2 plus 2?"}]}' \
          http://127.0.0.1:${toString gatewayPort}/p/joi/v1/chat/completions || true
        # Keep them out of her history
        ${config.services.hermes-agent.package}/bin/hermes -p joi sessions delete --yes "$id" >/dev/null || true
      done
    '';
  };

  # Runs every minute while she's awake. The model's task counter moving means
  # someone used her: Joi, a terminal chat, or Darlene on a handoff.
  joiAutosleep = pkgs.writeShellApplication {
    name = "joi-autosleep";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.procps
    ];
    text = ''
      used="$XDG_RUNTIME_DIR/joi/used"
      mkdir -p "$(dirname "$used")"
      slots=$(curl -sf -m 5 http://127.0.0.1:${toString modelPort}/slots) || exit 0
      tasks=$(jq '[.[].id_task // 0] | max' <<<"$slots")
      if jq -e 'any(.[]; .is_processing)' <<<"$slots" >/dev/null ||
        [ "$tasks" != "$(cat "$used" 2>/dev/null)" ]; then
        echo "$tasks" > "$used"
        exit 0
      fi
      # Stay up for a job she handed off, or a terminal chat with one of them
      if ls "${handoffs}"/*.running >/dev/null 2>&1 ||
        pgrep -u "$(id -u)" -f '/bin/hermes( -p [a-z]+)?$' >/dev/null; then
        exit 0
      fi
      # Time passes during suspend too, so after a long one she sleeps within a minute
      last=$({ stat -c %Y "$used" "$XDG_RUNTIME_DIR/joi/activity" ${awakeFile} 2>/dev/null || true; } | sort -n | tail -1)
      if [ $(( $(date +%s) - last )) -ge ${toString (cfg.sleepAfter * 60)} ]; then
        exec ${joiPower}/bin/joi-power off
      fi
    '';
  };
in
{
  # The local model, loaded while Joi is on
  systemd.user.services.llama-server = {
    Unit = {
      Description = "Local model for Hermes";
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = lib.escapeShellArgs [
        "${pkgs.unstable.llama-cpp-vulkan}/bin/llama-server"
        "--model"
        model
        "--mmproj"
        vision
        # A full-resolution screenshot would be ~5000 tokens; this keeps a look under ~10s
        "--image-max-tokens"
        "1280"
        "--alias"
        "local"
        "--host"
        "127.0.0.1"
        "--port"
        (toString modelPort)
        "--jinja" # tool calling
        "--flash-attn"
        "on"
        "--n-gpu-layers"
        "99"
        # Two conversations at once, so a job handed to Darlene doesn't hold Joi up.
        # Hermes wants at least 64k of context for each.
        "--ctx-size"
        "131072"
        "--parallel"
        "2"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        # This model's cache only resumes from saved points. Saving one wherever it's
        # useful lets a new chat pick up right before its first message (1.8s
        # instead of 3.7s); each point is ~50MB, so keep a few.
        "--checkpoint-min-step"
        "0"
        "--ctx-checkpoints"
        "8"
        # Answer straight away, without a thinking pass
        "--chat-template-kwargs"
        ''{"enable_thinking":false}''
        # Qwen's settings for that mode
        "--temp"
        "0.7"
        "--top-p"
        "0.8"
        "--top-k"
        "20"
      ];
      Restart = "on-failure";
    };
  };

  # Each time the gateway starts, so her first answer comes quickly
  systemd.user.services.joi-warmup = {
    Unit = {
      Description = "Get Joi's first answer ready";
      After = [
        "hermes-agent.service"
        "llama-server.service"
      ];
      PartOf = [ "hermes-agent.service" ];
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "hermes-agent.service" ];
    # Started counts as done right away, so waking her never waits on it
    Service = {
      Type = "exec";
      ExecStart = "${joiWarmup}/bin/joi-warmup";
    };
  };

  # She falls asleep after a while with nothing to do, to give the memory back
  systemd.user.services.joi-autosleep = {
    Unit.Description = "Put Joi to sleep when she's idle";
    Service = {
      Type = "oneshot";
      ExecStart = "${joiAutosleep}/bin/joi-autosleep";
    };
  };
  systemd.user.timers.joi-autosleep = {
    Unit = {
      Description = "Check whether Joi is idle";
      PartOf = [ "hermes-agent.service" ];
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "hermes-agent.service" ];
    Timer = {
      OnCalendar = "minutely";
      AccuracySec = "10s";
    };
  };
}
