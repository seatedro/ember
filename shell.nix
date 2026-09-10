{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    odin
  ];
  buildInputs = with pkgs; [
    glfw
    libGL
  ];
  LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
