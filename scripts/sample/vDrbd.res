resource vDrbd
{
  protocol    C;
  meta-disk   internal;

  on server4
  {
    device    /dev/drbd0;
    disk      /dev/sda3;
    address   192.168.11.100:7789;
  }

  on server7
  {
    device    /dev/drbd0;
    disk      /dev/sda4;
    address   192.168.11.200:7789;
  }

  net
  {
    verify-alg            sha1;
    csums-alg             sha1;
    allow-two-primaries   yes;
    after-sb-0pri         discard-zero-changes;
    after-sb-1pri         discard-secondary;
    after-sb-2pri         disconnect;
  }

  disk
  {
    resync-rate   100M;
  }
}
