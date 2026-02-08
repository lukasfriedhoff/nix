{
  ceph,
  fuse,
  kmod,
  lib,
  lvm2,
  makeWrapper,
  smartmontools,
  symlinkJoin,
  util-linux,
}:

let
  runtimePath = lib.makeBinPath [
    kmod
    util-linux
    lvm2
    fuse
    smartmontools
  ];
in
symlinkJoin {
  name = "${ceph.name}-runtime";
  paths = [ ceph ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrap_if_exists() {
      shift
      for dir in bin sbin; do
        local target="$out/$dir/$1"
        if [ -x "$target" ]; then
          wrapProgram "$target" "$@"
        fi
      done
    }

    # Work around missing runtime PATH deps in the upstream ceph package.
    wrap_if_exists mount.ceph --prefix PATH : "${runtimePath}"
    wrap_if_exists ceph-fuse --prefix PATH : "${runtimePath}"
    wrap_if_exists ceph-volume --prefix PATH : "${runtimePath}"
  '';
}
