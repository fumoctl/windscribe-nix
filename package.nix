{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  buildEnv,
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
  # Runtime CLI tools used by helper, GUI & scripts
  bash,
  coreutils,
  e2fsprogs,
  ethtool,
  findutils,
  gawk,
  gnugrep,
  gnused,
  iproute2,
  iptables,
  iputils,
  iw,
  kmod,
  nettools,
  networkmanager,
  openresolv,
  procps,
  psmisc,
  util-linux,
  which,
  wireguard-tools,
  xdg-utils,
}:

let
  version = "2.25.8";

  runtimeTools = [
    acl
    bash
    coreutils
    dbus
    e2fsprogs
    ethtool
    findutils
    gawk
    gnugrep
    gnused
    iproute2
    iptables
    iputils
    iw
    kmod
    nettools
    networkmanager
    nftables
    openresolv
    procps
    psmisc
    systemd
    util-linux
    which
    wireguard-tools
    xdg-utils
  ];

  runtimePath = lib.makeBinPath runtimeTools;

  helperToolsEnv = buildEnv {
    name = "windscribe-helper-tools";
    paths = runtimeTools;
    pathsToLink = [
      "/bin"
      "/sbin"
    ];
    ignoreCollisions = true;
  };
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

  passthru = {
    inherit helperToolsEnv runtimePath;
  };

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

    # Launch via /opt/windscribe/Windscribe when bind-mounted so QCoreApplication::applicationDirPath()
    # and helper's realpath() check both resolve to /opt/windscribe.
    cat > "$out/bin/windscribe" <<EOF
    #!${bash}/bin/bash
    export PATH="${runtimePath}\''${PATH:+:\$PATH}"
    export LD_LIBRARY_PATH="/run/opengl-driver/lib\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    if [ -x /opt/windscribe/Windscribe ]; then
      exec /opt/windscribe/Windscribe "\$@"
    else
      exec "$out/opt/windscribe/Windscribe" "\$@"
    fi
    EOF
    chmod +x "$out/bin/windscribe"

    cat > "$out/bin/windscribe-cli" <<EOF
    #!${bash}/bin/bash
    export PATH="${runtimePath}\''${PATH:+:\$PATH}"
    if [ -x /opt/windscribe/windscribe-cli ]; then
      exec /opt/windscribe/windscribe-cli "\$@"
    else
      exec "$out/opt/windscribe/windscribe-cli" "\$@"
    fi
    EOF
    chmod +x "$out/bin/windscribe-cli"

    # Fix desktop entry Exec path
    substituteInPlace "$out/share/applications/windscribe.desktop" \
      --replace-fail "Exec=/opt/windscribe/Windscribe" "Exec=$out/bin/windscribe"

    runHook postInstall
  '';

  meta = {
    description = "Windscribe VPN desktop client (official .deb repack with full wsnet failovers)";
    homepage = "https://windscribe.com";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "windscribe";
  };
}
