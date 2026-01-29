# Claude Vertex Flake
#
# A Nix flake that wraps Claude Code CLI with automatic Google Cloud Vertex AI
# authentication and configuration.
{
  description = "Claude Code CLI wrapper with Vertex AI integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
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

    # Development shell (use: nix develop)
    # Includes the Claude wrapper and formatting tools
    devShells = forAllSystems (_system: pkgs: {
      default = pkgs.mkShell {
        buildInputs = [
          pkgs.alejandra
          (self.lib.mkClaude {inherit pkgs;})
        ];
      };
    });

    # lib.mkClaude - Build a customized Claude Code wrapper
    #
    # Arguments:
    #   pkgs (required)
    #     Type: nixpkgs
    #     The nixpkgs instance to use for building
    #
    #   modelName (optional)
    #     Type: string
    #     Default: "claude-sonnet-4-5"
    #     The primary Claude model to use (ANTHROPIC_MODEL)
    #
    #   smallModelName (optional)
    #     Type: string
    #     Default: "claude-3-5-haiku"
    #     The fast model for lightweight tasks (ANTHROPIC_SMALL_FAST_MODEL)
    #
    #   vertexRegion (optional)
    #     Type: string
    #     Default: "europe-west1"
    #     Google Cloud region for Vertex AI (CLOUD_ML_REGION)
    #     See: https://cloud.google.com/vertex-ai/docs/general/locations
    #
    #   disablePromptCaching (optional)
    #     Type: bool
    #     Default: true
    #     Whether to disable prompt caching (DISABLE_PROMPT_CACHING)
    #
    #   projectId (optional)
    #     Type: string | null
    #     Default: null
    #     Hardcoded GCP project ID. Takes precedence over all other methods.
    #
    # Returns: derivation
    #   A wrapper script that configures and launches Claude Code
    #
    # Example:
    #   lib.mkClaude {
    #     inherit pkgs;
    #     modelName = "claude-sonnet-4-20250514";
    #     vertexRegion = "us-central1";
    #     disablePromptCaching = false;
    #   }
    lib.mkClaude = {
      pkgs,
      modelName ? "claude-sonnet-4-5",
      smallModelName ? "claude-3-5-haiku",
      vertexRegion ? "europe-west1",
      disablePromptCaching ? true,
      projectId ? null,
    }:
      pkgs.callPackage ./package.nix {
        inherit
          modelName
          smallModelName
          vertexRegion
          disablePromptCaching
          projectId
          ;
      };

    # Overlay for integrating into nixpkgs
    # Adds: pkgs.claude-vertex
    #
    # Usage in flake:
    #   nixpkgs.overlays = [ claude-vertex.overlays.default ];
    overlays.default = final: prev: {
      claude-vertex = self.lib.mkClaude {pkgs = final;};
    };

    # Home Manager module
    #
    # Usage in home.nix:
    #   imports = [ claude-vertex.homeManagerModules.default ];
    #   programs.claude-vertex = {
    #     enable = true;
    #     modelName = "claude-sonnet-4-20250514";
    #   };
    homeManagerModules.default = {
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
    checks = forAllSystems (system: pkgs: let
      checkScript = pkgs.writeShellScript "check-script" ''
        script="$1"
        shift
        for pattern in "$@"; do
          if echo "$script" | grep -q "$pattern"; then
            echo "PASS: Found $pattern"
          else
            echo "FAIL: Missing $pattern"
            exit 1
          fi
        done
      '';
    in {
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
        script = builtins.readFile "${pkg}/bin/claude";
      in
        pkgs.runCommand "check-custom-config" {} ''
          ${checkScript} '${script}' \
            "CLAUDE_CODE_USE_VERTEX" \
            "ANTHROPIC_VERTEX_PROJECT_ID" \
            "ANTHROPIC_MODEL=test-model" \
            "ANTHROPIC_SMALL_FAST_MODEL=test-small-model" \
            "CLOUD_ML_REGION=us-central1" \
            "test-project"

          if echo '${script}' | grep -q "DISABLE_PROMPT_CACHING"; then
            echo "FAIL: DISABLE_PROMPT_CACHING should not be set"
            exit 1
          fi
          echo "PASS: DISABLE_PROMPT_CACHING correctly omitted"

          echo "All checks passed" > $out
        '';

      default-config = let
        pkg = self.lib.mkClaude {inherit pkgs;};
        script = builtins.readFile "${pkg}/bin/claude";
      in
        pkgs.runCommand "check-default-config" {} ''
          ${checkScript} '${script}' \
            "CLAUDE_CODE_USE_VERTEX" \
            "ANTHROPIC_VERTEX_PROJECT_ID" \
            "ANTHROPIC_MODEL=claude-sonnet-4-5" \
            "ANTHROPIC_SMALL_FAST_MODEL=claude-3-5-haiku" \
            "CLOUD_ML_REGION=europe-west1" \
            "DISABLE_PROMPT_CACHING=1"

          echo "All checks passed" > $out
        '';
    });
  };
}
