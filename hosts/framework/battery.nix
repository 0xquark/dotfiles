{ pkgs, ... }:

{
  # Kernel driver for the battery charge limit; Framework laptops load it with this option
  boot.extraModprobeConfig = ''
    options cros_charge_control probe_with_fwk_charge_control=1
  '';

  # Charge to 80% by default. User can change it (the bottom bar's LIM button).
  systemd.services.battery-charge-limit = {
    description = "Battery charge limit: 80%";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      limit=/sys/class/power_supply/BAT1/charge_control_end_threshold
      # The driver can show up a little after boot
      for _ in $(seq 30); do
        [ -e "$limit" ] && break
        sleep 1
      done
      echo 80 > "$limit"
      chgrp wheel "$limit"
      chmod g+w "$limit"
    '';
  };
}
