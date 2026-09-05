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
        opam
        gmp
        autoconf
        which
        libffi
        pkg-config

        SDL2

        vulkan-loader
        vulkan-headers
        vulkan-tools
        vulkan-validation-layers

        shaderc
        glslang
      ];

      shellHook = ''
        export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
          pkgs.vulkan-loader
          pkgs.SDL2
        ]}:$LD_LIBRARY_PATH"
        echo "OCaml Vulkan dev shell"
        echo "Vulkan:"
        vulkaninfo --summary 2>/dev/null | head -n 20 || true
        echo
      '';
    };
  };
}
