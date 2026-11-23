{
  description = "Windscribe VPN desktop client (official .deb repack) for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        rec {
          windscribe = pkgs.callPackage ./package.nix { };
          default = windscribe;
        }
      );

      overlays.default = final: _prev: {
        windscribe = final.callPackage ./package.nix { };
      };

      nixosModules = rec {
        windscribe = import ./module.nix;
        default = windscribe;
      };
    };
}
