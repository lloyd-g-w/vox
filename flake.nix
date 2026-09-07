{
  description = "OCaml WebGPU (wgpu-native) voxel game dev shell";

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

        # wgpu-ocaml's fetch script downloads the pinned libwgpu_native with these
        curl
        unzip

        SDL2

        # wgpu-native uses Vulkan on Linux; the hardware driver comes from the host
        vulkan-loader
        vulkan-tools
      ];

      shellHook = ''
        export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
          pkgs.libffi
          pkgs.vulkan-loader
          pkgs.SDL2
          pkgs.stdenv.cc.cc.lib
        ]}:$LD_LIBRARY_PATH"
        echo "OCaml wgpu dev shell"
        echo "Vulkan (used by wgpu-native's Linux backend):"
        vulkaninfo --summary 2>/dev/null | head -n 20 || true
        echo
      '';
    };
  };
}
