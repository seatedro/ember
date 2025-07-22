# flake needed to make ember run on nixOS
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      zig-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        zig = pkgs.zigpkgs."0.14.1";

        sdlRuntimeDeps = with pkgs; [
          wayland
          libdecor
          libxkbcommon
          dbus
          vulkan-loader
          mesa
        ];

        ember = pkgs.stdenv.mkDerivation {
          pname = "ember";
          version = "0.1.0";

          src = self; # root of this flake

          nativeBuildInputs = [
            zig
            pkgs.pkg-config
            pkgs.makeWrapper
          ];
          buildInputs = [
            pkgs.sdl3
            pkgs.sdl3-image
            pkgs.libGL
          ] ++ sdlRuntimeDeps;

          buildPhase = ''
            zig build
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/ember $out/bin/

            wrapProgram $out/bin/ember \
              --prefix LD_LIBRARY_PATH : "${
                pkgs.lib.makeLibraryPath (
                  [
                    pkgs.sdl3
                    pkgs.sdl3-image
                    pkgs.libGL
                  ]
                  ++ sdlRuntimeDeps
                )
              }"
          '';
        };
      in
      {
        packages.default = ember;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ ember ];
          packages = [
            zig
            pkgs.sdl3
            pkgs.sdl3-image
            pkgs.libGL
          ] ++ sdlRuntimeDeps;
          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (
            [
              pkgs.sdl3
              pkgs.sdl3-image
              pkgs.libGL
            ]
            ++ sdlRuntimeDeps
          )}";
        };
      }
    );
}

