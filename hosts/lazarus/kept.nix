# Lazarus with a disk, for `laz -p 3d`: the whole VM survives poweroff
# until the time runs out, then laz deletes the disk.
{
  microvm.volumes = [
    {
      image = "/home/drquark/oasis/basement/.lazarus/state.img";
      mountPoint = "/";
      label = "lazarus";
      size = 20480; # MiB; the file only grows as the VM writes
    }
  ];

  # Same fresh /tmp on every boot as the throwaway VM
  boot.tmp.cleanOnBoot = true;
}
