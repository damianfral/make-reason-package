{
  description = "Helper to package reason apps.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.yarn2nix-src.url =
    "github:moretea/yarn2nix/841b6c67a989952f990e0856da9bb00fe5a60de8";
  inputs.yarn2nix-src.flake = false;

  outputs = { self, nixpkgs, yarn2nix-src }@inputs:

    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };

    in {
      overlay = final: prev: rec {
        inherit (import yarn2nix-src { pkgs = final; })
          yarn2nix mkYarnPackage mkYarnModules mkYarnNix;
        makeReasonDrv = import ./make-reason-drv.nix;
        makeReasonPackage = { name, src }:
          prev.callPackage (makeReasonDrv { inherit name src; }) { };
      };
    };

}
