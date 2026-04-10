{
  description = "Conway's Game of Life on ESP32-S3 + Elecrow 5\" display (Nim)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-esp-dev,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Use nixpkgs-esp-dev's own pinned nixpkgs for ESP-IDF compatibility
        espPkgs = import nixpkgs-esp-dev.inputs.nixpkgs {
          inherit system;
          overlays = [ nixpkgs-esp-dev.overlays.default ];
          config.permittedInsecurePackages = [
            "python3.13-ecdsa-0.19.1"
          ];
        };

        nuConfig = pkgs.writeText "gol-config.nu" ''
          def compile [] {
            cd main; nim c main.nim; cd ..
          }

          def build [] {
            compile
            cmake -B build -G Ninja
            cmake --build build
          }

          def flash [] {
            espflash flash build/game_of_life.elf
            espflash monitor
          }

          def clean [] {
            rm -rf main/nimcache build sdkconfig sdkconfig.old
          }

          print ""
          print "🧬 Game of Life — ESP32-S3 Development Environment (Nim)"
          print ""
          print "  compile  Compile Nim to C (main/nimcache/)"
          print "  build    Compile Nim + cmake build"
          print "  flash    Flash and monitor"
          print "  clean    Remove build artifacts"
          print ""
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            espPkgs.esp-idf-full
            cmake
            ninja
            nim
            espflash
            nushell
          ];

          shellHook = ''
            export IDF_TARGET="esp32s3"
            exec nu --config ${nuConfig}
          '';
        };
      }
    );
}
