{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  # Runtime shared libraries
  acl,
  alsa-lib,
  brotli,
  dbus,
  fontconfig,
  freetype,
  glib,
  harfbuzz,
  libcap_ng,
  libdrm,
  libglvnd,
  libnl,
  libpulseaudio,
  libx11,
  libxcb,
  libxcb-cursor,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libxcb-util,
  libxcb-wm,
  libxkbcommon,
  nftables,
  pcre2,
  systemd,
  wayland,
  zstd,
  # Runtime CLI tools used by helper & scripts
  bash,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  iproute2,
  iptables,
  iputils,
  iw,
  nettools,
  networkmanager,
  openresolv,
  procps,
  psmisc,
  util-linux,
  wireguard-tools,
  xdg-utils,
}:

let
  version = "2.25.8";

  runtimePath = lib.makeBinPath [
    bash
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    iproute2
    iptables
    iputils
    iw
    nettools
    networkmanager
    nftables
    openresolv
    procps
    psmisc
    systemd
    util-linux
    wireguard-tools
    xdg-utils
  ];
in
stdenv.mkDerivation {
  pname = "windscribe-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Windscribe/Desktop-App/releases/download/v${version}/windscribe_${version}_amd64.deb";
    hash = "sha256-JYkLk1dsdTOF5UlUj2DdJ9Jwdo0EfRzSwPpVBhnQ5ks=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    acl
    brotli
    fontconfig
    freetype
    glib
    harfbuzz
    libcap_ng
    libdrm
    libglvnd
    libnl
    libxkbcommon
    nftables
    pcre2
    systemd
    wayland
    zstd
    libx11
    libxcb
    libxcb-util
    libxcb-cursor
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-wm
  ];

  # Libraries loaded via dlopen() at runtime by static Qt6 (DBus tray, audio, udev/systemd)
  runtimeDependencies = [
    (lib.getLib alsa-lib)
    (lib.getLib dbus)
    (lib.getLib libpulseaudio)
    (lib.getLib systemd)
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/opt" "$out/share"
    cp -r opt/windscribe "$out/opt/windscribe"
    cp -r usr/share/applications "$out/share/applications"
    cp -r usr/share/icons "$out/share/icons"

    # Let autoPatchelfHook find bundled libwsnet.so, libssl.so.4, libcrypto.so.4
    addAutoPatchelfSearchPath "$out/opt/windscribe/lib"

    # Fix hardcoded FHS PATH in helper scripts so Nix tools resolve
    for script in "$out"/opt/windscribe/scripts/*; do
      if [ -f "$script" ]; then
        substituteInPlace "$script" \
          --replace-quiet "PATH=/usr/sbin:/usr/bin:/sbin:/bin" "PATH=${runtimePath}:\$PATH"
      fi
    done
    patchShebangs "$out/opt/windscribe/scripts"

    # Fix desktop entry Exec path
    substituteInPlace "$out/share/applications/windscribe.desktop" \
      --replace-fail "Exec=/opt/windscribe/Windscribe" "Exec=$out/bin/windscribe"

    runHook postInstall
  '';

  postFixup = ''
    # Wrap helper and scripts with full Nix runtime PATH
    wrapProgram "$out/opt/windscribe/helper" \
      --prefix PATH : "${runtimePath}"

    for script in "$out"/opt/windscribe/scripts/*; do
      if [ -f "$script" ] && [ -x "$script" ]; then
        wrapProgram "$script" \
          --prefix PATH : "${runtimePath}"
      fi
    done

    # Expose GUI and CLI in $out/bin (include /run/opengl-driver/lib for NixOS Mesa/NVIDIA EGL/GLX)
    makeWrapper "$out/opt/windscribe/Windscribe" "$out/bin/windscribe" \
      --prefix PATH : "${runtimePath}" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib"

    makeWrapper "$out/opt/windscribe/windscribe-cli" "$out/bin/windscribe-cli" \
      --prefix PATH : "${runtimePath}"
  '';

  meta = {
    description = "Windscribe VPN desktop client (official .deb repack with full wsnet failovers)";
    homepage = "https://windscribe.com";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "windscribe";
  };
}
