# Claude Vertex Flake
#
# A Nix flake that wraps Claude Code CLI with automatic Google Cloud Vertex AI
# authentication and configuration.
{
  description = "Claude Code CLI wrapper with Vertex AI integration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-code-src = {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.92.tgz";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    claude-code-src,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f system (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }));

    mkClaudeCode = pkgs:
      pkgs.stdenv.mkDerivation {
        pname = "claude-code";
        version = "2.1.92";

        src = claude-code-src;
        dontUnpack = true;

        nativeBuildInputs = [pkgs.makeWrapper pkgs.gnutar pkgs.gzip];
        buildInputs = [pkgs.nodejs];

        installPhase = ''
          runHook preInstall

          mkdir -p temp_extract
          if [ -d "$src" ]; then
            cp -r "$src/." temp_extract/
          else
            tar -xzf "$src" -C temp_extract/
          fi

          if [ -d "temp_extract/package" ]; then
            cd temp_extract/package
          else
            cd temp_extract
          fi

          # 1. Copy files to the output
          mkdir -p $out/lib/node_modules/@anthropic-ai/claude-code
          cp -r . $out/lib/node_modules/@anthropic-ai/claude-code/

          # 2. Dynamically find the CLI entry point
          # Anthropic usually ships 'cli.js' in the root for the NPM version
          CLI_JS=""
          for path in "cli.js" "dist/cli.js" "bin/cli.js"; do
            if [ -f "$out/lib/node_modules/@anthropic-ai/claude-code/$path" ]; then
              CLI_JS="$out/lib/node_modules/@anthropic-ai/claude-code/$path"
              break
            fi
          done

          if [ -z "$CLI_JS" ]; then
            echo "ERROR: Could not find cli.js in package root, dist/, or bin/"
            ls -R $out/lib/node_modules/@anthropic-ai/claude-code/
            exit 1
          fi

          echo "Found CLI entry point at: $CLI_JS"

          # 3. Create the binary wrapper
          mkdir -p $out/bin
          makeWrapper ${pkgs.nodejs}/bin/node $out/bin/claude \
            --add-flags "$CLI_JS"

          runHook postInstall
        '';
      };
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
    }: let
      claude-code = mkClaudeCode pkgs;
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
