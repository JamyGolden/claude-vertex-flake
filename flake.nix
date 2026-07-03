{
  description = "Claude Code CLI wrapper with Vertex AI integration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude-code = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nix-claude-code,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f system (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }));
  in {
    formatter = forAllSystems (_system: pkgs: pkgs.alejandra);

    packages = forAllSystems (_system: pkgs: {
      default = self.lib.mkClaude {inherit pkgs;};
    });

    devShells = forAllSystems (_system: pkgs: {
      default = pkgs.mkShell {
        buildInputs = [
          pkgs.alejandra
          (self.lib.mkClaude {inherit pkgs;})
        ];
      };
    });

    lib.mkClaude = {
      pkgs,
      modelName ? "claude-sonnet-4-5",
      smallModelName ? "claude-3-5-haiku",
      vertexRegion ? "europe-west1",
      disablePromptCaching ? true,
      projectId ? null,
    }: let
      system = pkgs.stdenv.hostPlatform.system;
      claude-code = nix-claude-code.packages.${system}.claude;
    in
      pkgs.callPackage ./package.nix {
        inherit
          modelName
          smallModelName
          vertexRegion
          disablePromptCaching
          projectId
          claude-code
          ;
        fzf = pkgs.fzf;
        google-cloud-sdk = pkgs.google-cloud-sdk;
        jaq = pkgs.jaq;
      };

    overlays.default = final: prev: {
      claude-vertex = self.lib.mkClaude {pkgs = final;};
    };

    homeModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.programs.claude-vertex;
    in {
      options.programs.claude-vertex = {
        enable = lib.mkEnableOption "Claude Code with Vertex AI";
        modelName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "claude-sonnet-4-5";
          description = "The primary Claude model to use (ANTHROPIC_MODEL)";
        };
        smallModelName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "claude-3-5-haiku";
          description = "The fast model for lightweight tasks (ANTHROPIC_SMALL_FAST_MODEL)";
        };
        vertexRegion = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "europe-west1";
          description = "Google Cloud region for Vertex AI (CLOUD_ML_REGION)";
        };
        disablePromptCaching = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to disable prompt caching (DISABLE_PROMPT_CACHING)";
        };
        projectId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Hardcoded GCP project ID. Takes precedence over all other methods.";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [
          (self.lib.mkClaude {
            inherit pkgs;
            inherit (cfg) modelName smallModelName vertexRegion disablePromptCaching projectId;
          })
        ];
      };
    };

    # CI checks (use: nix flake check)
    #
    # - default: Verifies the package builds
    # - formatting: Verifies Nix files are formatted with alejandra
    # - custom-config: Verifies custom configuration options work
    checks = forAllSystems (system: pkgs: {
      default = self.packages.${system}.default;

      formatting = pkgs.runCommand "check-formatting" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${self} > $out
      '';

      custom-config = let
        pkg = self.lib.mkClaude {
          inherit pkgs;
          modelName = "test-model";
          smallModelName = "test-small-model";
          vertexRegion = "us-central1";
          projectId = "test-project";
          disablePromptCaching = false;
        };
      in
        pkgs.runCommand "check-custom-config" {
          nativeBuildInputs = [pkgs.ripgrep];
        } ''
          TARGET="${pkg}/bin/claude"

          # Check for expected environment variables
          grep -q "CLAUDE_CODE_USE_VERTEX" "$TARGET"
          grep -q "ANTHROPIC_VERTEX_PROJECT_ID" "$TARGET"
          grep -q "ANTHROPIC_MODEL=test-model" "$TARGET"
          grep -q "ANTHROPIC_SMALL_FAST_MODEL=test-small-model" "$TARGET"
          grep -q "CLOUD_ML_REGION=us-central1" "$TARGET"
          grep -q "test-project" "$TARGET"

          # Check for the OMISSION of prompt caching
          if grep -q "DISABLE_PROMPT_CACHING" "$TARGET"; then
            echo "FAIL: DISABLE_PROMPT_CACHING should not be set"
            exit 1
          fi

          echo "All checks passed" > $out
        '';

      default-config = let
        pkg = self.lib.mkClaude {inherit pkgs;};
      in
        pkgs.runCommand "check-default-config" {
          nativeBuildInputs = [pkgs.gnugrep];
        } ''
          TARGET="${pkg}/bin/claude"

          grep -q "ANTHROPIC_MODEL=claude-sonnet-4-5" "$TARGET"
          grep -q "CLOUD_ML_REGION=europe-west1" "$TARGET"
          grep -q "DISABLE_PROMPT_CACHING=1" "$TARGET"

          echo "All checks passed" > $out
        '';
    });
  };
}
