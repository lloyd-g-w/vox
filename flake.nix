{
  description = "OCaml Vulkan voxel game dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        # OCaml / opam tooling
        opam
        pkg-config

        # SDL
        SDL2

        # Vulkan
        vulkan-loader
        vulkan-headers
        vulkan-tools
        vulkan-validation-layers

        # GLSL -> SPIR-V
        shaderc
        glslang
      ];

      shellHook = ''
        echo "OCaml Vulkan dev shell"
        echo "Vulkan:"
        vulkaninfo --summary 2>/dev/null | head -n 20 || true
        echo
      '';
    };
  };
}
