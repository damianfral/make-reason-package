{
  description = "Helper to package reason apps.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.yarn2nix-src.url = "github:moretea/yarn2nix";
  inputs.yarn2nix-src.flake = false;

  outputs = { self, nixpkgs, yarn2nix-src }@inputs:

  let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # overlays = [ self.overlay ];
      };

      yarn2nix-pkgs = import yarn2nix-src { pkgs = pkgs; };
      makeReasonDrv = import ./make-reason-drv.nix;
      makeReasonPackage = { name, src } :
        pkgs.callPackage ( makeReasonDrv { inherit name src;} ) {};

  in
    {
      lib = { inherit makeReasonPackage; };
    };

}
