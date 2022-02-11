{
  description = "Build a cargo project with a custom toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, crane, fenix, nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (localSystem:
      let
        crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform-musl // { useLLVM = true;  };

        pkgs = import nixpkgs {
          inherit localSystem crossSystem;
          overlays = [ fenix.overlay ];
        };

        inherit (pkgs) pkgsBuildBuild pkgsBuildHost;

        llvmToolchain = pkgsBuildHost.llvmPackages_13;

        rustToolchain = with pkgsBuildHost.fenix; combine [
          stable.rustc
          stable.cargo
          stable.rustfmt
          stable.clippy
          targets.${crossSystem.config}.stable.rust-std
        ];

        craneLib = (crane.mkLib pkgs).overrideScope' (final: prev: {
          cargo = rustToolchain;
          clippy = rustToolchain;
          rustc = rustToolchain;
          rustfmt = rustToolchain;
        });

        args = {
          src = ./.;

          nativeBuildInputs = [
            llvmToolchain.stdenv.cc
            llvmToolchain.lld
          ];

          cargoExtraArgs = "--target aarch64-unknown-linux-musl";
          RUSTFLAGS = "-C linker-flavor=ld.lld -C target-feature=+crt-static";
        };

        cargoArtifacts = craneLib.buildDepsOnly args;

        crateClippy = craneLib.cargoClippy (args // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "-- --deny warnings";
        });

        crate = craneLib.buildPackage (args // {
          cargoArtifacts = crateClippy;
        });
      in
      {
        checks = {
          inherit crate crateClippy;
        };

        defaultPackage = self.packages.${localSystem}.crate;
        packages = { inherit cargoArtifacts crateClippy crate; };

        devShell = pkgs.mkShell {
          name = "crane-cross-example";

          inputsFrom = builtins.attrValues self.checks.${localSystem};

          nativeBuildInputs = with pkgsBuildBuild; [
            rust-analyzer-nightly
          ];
        };
      });
}
