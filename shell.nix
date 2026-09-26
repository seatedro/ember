{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    glslang
    odin
    spirv-cross
  ];
  buildInputs = with pkgs; [
    glfw
    libGL
  ];
  LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
