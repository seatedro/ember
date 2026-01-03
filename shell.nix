{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
  nativeBuildInputs = with pkgs; [
    clang-tools
    bear
    pkg-config
  ];
  buildInputs = with pkgs; [
    glfw
    libGL
  ];
  LD_LIBRARY_PATH = "/run/opengl-driver/lib";
  hardeningDisable = [ "fortify" ];
}
