{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system;
      config = {
        # https://github.com/NixOS/nixpkgs/issues/342876
        allowUnsupportedSystem = true;
      };
    };
    odin-override =
      (pkgs.odin.override
        {
          MacOSX-SDK = "${pkgs.apple-sdk_14.sdkroot}";
        })
      .overrideAttrs rec {
        version = "dev-2025-04";
        src = pkgs.fetchFromGitHub {
          owner = "odin-lang";
          repo = "Odin";
          rev = version;
          hash = "sha256-dVC7MgaNdgKy3X9OE5ZcNCPnuDwqXszX9iAoUglfz2k=";
        };
      };
    ols-override = pkgs.ols.override {
      odin = odin-override;
    };
  in
    with pkgs; let
      pname = "vulkan-tutorial-odin";
      version = "git";

      buildInputs = let
        glfw-vulkan-macos-fix = glfw.overrideAttrs (oldAttrs: {
          env = {
            NIX_CFLAGS_COMPILE = toString [
              "-D_GLFW_VULKAN_LIBRARY=\"${lib.getLib vulkan-loader}/lib/libvulkan.1.dylib\""
            ];
          };
        });
      in [
        odin-override
        vulkan-headers
        vulkan-loader
        vulkan-validation-layers
        moltenvk
        vulkan-tools
        vulkan-utility-libraries
        glfw-vulkan-macos-fix
        shaderc
      ];

      nativeBuildInputs = [
        pkg-config
      ];
    in {
      packages = {
        default = stdenv.mkDerivation {
          inherit pname version buildInputs nativeBuildInputs;

          src = ./.;

          buildPhase = ''
            mkdir -p build/bin
            ${lib.getExe odin-override} build . -minimum-os-version=14.0 -out=build/bin/${pname}
          '';

          installPhase = ''
            cp -r build $out
          '';

          meta = {
            mainProgram = pname;
          };
        };
      };
      devShells = {
        default = mkShell {
          inherit buildInputs nativeBuildInputs;

          packages =
            [
              clang
              ols-override
              odin-override
              clang-tools
              llvm_17
              lldb_17
              bear
              stdmanpages
            ]
            ++ (with llvmPackages_17; [
              clang-manpages
              llvm-manpages
            ]);

          VK_LAYER_PATH = "${vulkan-validation-layers}/share/vulkan/explicit_layer.d";
          VK_ICD_FILENAMES = "${moltenvk}/share/vulkan/icd.d/MoltenVK_icd.json";
        };
      };
    }));
}
