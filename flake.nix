{
  description = "Conway's Game of Life on ESP32-S3 + Elecrow 5\" display (Nim)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        idf = pkgs.writeShellScriptBin "idf" ''
          IDF_PATH="''${IDF_PATH:-$HOME/.esp-idf/esp-idf}"
          export IDF_PATH

          # Source export.sh to get toolchain PATH + Python venv.
          # Ignore non-zero exit (openocd warnings) but still eval its output.
          idf_exports="$(python3 "$IDF_PATH/tools/idf_tools.py" export 2>/dev/null)" || true
          eval "$idf_exports"

          # Fallback: add venv site-packages if export.sh didn't fully activate
          VENV_DIR="$(ls -d "$HOME"/.espressif/python_env/idf*_py3.*_env 2>/dev/null | tail -1)"
          if [ -n "$VENV_DIR" ]; then
            SITE_PKG="$(ls -d "$VENV_DIR"/lib/python*/site-packages 2>/dev/null | tail -1)"
            [ -n "$SITE_PKG" ] && export PYTHONPATH="$SITE_PKG''${PYTHONPATH:+:$PYTHONPATH}"
          fi

          python3 "$IDF_PATH/tools/idf.py" "$@"
        '';

        nuConfig = pkgs.writeText "gol-config.nu" ''
          def compile [] {
            cd main; nim c main.nim; cd ..
          }

          def build [] {
            compile
            idf build
          }

          def flash [] {
            idf -p /dev/ttyUSB0 flash monitor
          }

          def clean [] {
            rm -rf main/nimcache build sdkconfig sdkconfig.old
          }

          print ""
          print "🧬 Game of Life — ESP32-S3 Development Environment (Nim)"
          print ""
          print "  compile  Compile Nim to C (main/nimcache/)"
          print "  build    Compile Nim + idf build"
          print "  flash    Flash and monitor"
          print "  clean    Remove build artifacts"
          print ""
        '';

        fhs = pkgs.buildFHSEnv {
          name = "gol-dev";
          targetPkgs =
            pkgs: with pkgs; [
              # Build tools
              cmake
              ninja
              pkg-config
              gnumake
              gcc
              flex
              bison
              gperf
              gettext
              ccache
              git
              curl
              wget

              # Python (ESP-IDF dependency)
              python3
              python3Packages.pip
              python3Packages.virtualenv

              # Nim
              nim

              # ESP tooling
              espflash
              idf

              # Serial monitor
              picocom
              nushell

              # Libraries
              openssl
              openssl.dev
              zlib
              libxml2_13
              ncurses
              stdenv.cc.cc.lib
              patchelf
              file
              systemd  # provides libudev.so.1 for openocd
              libusb1  # provides libusb-1.0.so.0 for openocd
            ];

          profile = ''
            export ESP_IDF_VERSION="v5.2"
            export IDF_TARGET="esp32s3"

            IDF_PATH="$HOME/.esp-idf/esp-idf"
            if [ ! -d "$IDF_PATH" ]; then
              echo "📦 Cloning ESP-IDF $ESP_IDF_VERSION..."
              mkdir -p "$HOME/.esp-idf"
              git clone -b "release/$ESP_IDF_VERSION" --recursive \
                https://github.com/espressif/esp-idf.git "$IDF_PATH"
              "$IDF_PATH/install.sh" esp32s3
            fi

            export IDF_PATH
            source "$IDF_PATH/export.sh" > /dev/null 2>&1
          '';

          runScript = "nu --config ${nuConfig}";
        };
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ fhs ];
          shellHook = ''
            echo "Entering FHS environment..."
            exec ${fhs}/bin/gol-dev
          '';
        };

        packages.default = fhs;
      }
    );
}
