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
    odin-macos-override = (pkgs.odin.override
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
    ols-macos-override = pkgs.ols.override {
      odin = odin-macos-override;
    };
    odin-override =
      if pkgs.stdenv.hostPlatform.isDarwin
      then odin-macos-override
      else pkgs.odin;
    ols-override =
      if pkgs.stdenv.hostPlatform.isDarwin
      then ols-macos-override
      else pkgs.ols;
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
      in
        [
          ols-override
          odin-override
          vulkan-headers
          vulkan-loader
          vulkan-validation-layers
          vulkan-tools
          vulkan-utility-libraries
          shaderc
        ]
        ++ (
          lib.optionals (pkgs.stdenv.hostPlatform.isDarwin) [
            moltenvk
            glfw-vulkan-macos-fix
          ]
        )
        ++ (
          lib.optionals (pkgs.stdenv.hostPlatform.isLinux) [
            glfw
          ]
        );

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
              vulkan-tools-lunarg
            ]
            ++ (with llvmPackages_17; [
              clang-manpages
              llvm-manpages
            ]);

          VK_LAYER_PATH = "${vulkan-validation-layers}/share/vulkan/explicit_layer.d";
          # VULKAN_SDK = "${vulkan-validation-layers}/share/vulkan/explicit_layer.d";
          # LD_LIBRARY_PATH = "${glfw}/lib:${freetype}/lib:${vulkan-loader}/lib:${vulkan-validation-layers}/lib";
          VK_ICD_FILENAMES =
            if pkgs.stdenv.hostPlatform.isDarwin == true
            then "${moltenvk}/share/vulkan/icd.d/MoltenVK_icd.json"
            else null;
        };
      };
    }));
}
