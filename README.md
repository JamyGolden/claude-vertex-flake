# claude-vertex flake

One-click AI agent setup through Google Vertex AI Platform. This launches **Claude Code** using your Google login[^cc] configured to use the **Claude Sonnet 4.5** model by default.

## Quick Start

### macOS / Linux

1. Install Nix [using these instructions][nix-install]
2. Run:
   ```sh
   nix run github:JamyGolden/claude-vertex-flake
   ```

## Installation

### NixOS / Home Manager

Add to your `flake.nix` inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-vertex.url = "github:JamyGolden/claude-vertex-flake";
  };
}
```

Then use one of the following methods:

#### Option 1: Home Manager Module

```nix
{
  imports = [ claude-vertex.homeManagerModules.default ];
  
  programs.claude-vertex = {
    enable = true;
    # Optional customization:
    # modelName = "claude-sonnet-4-5";
    # smallModelName = "claude-3-5-haiku";
    # vertexRegion = "us-central1";
    # projectId = "my-gcp-project";
    # disablePromptCaching = false;
  };
}
```

#### Option 2: Direct Package

```nix
{ pkgs, claude-vertex, ... }: {
  home.packages = [
    claude-vertex.packages.${pkgs.system}.default
  ];
}
```

#### Option 3: Overlay

```nix
{
  nixpkgs.overlays = [ claude-vertex.overlays.default ];
}
```

Then use `pkgs.claude-vertex` in your configuration.

#### Option 4: lib.mkClaude (Custom Configuration)

```nix
{ pkgs, claude-vertex, ... }: {
  home.packages = [
    (claude-vertex.lib.mkClaude {
      inherit pkgs;
      modelName = "claude-sonnet-4-5";
      smallModelName = "claude-3-5-haiku";
      vertexRegion = "us-central1";
      projectId = "my-gcp-project";
      disablePromptCaching = false;
    })
  ];
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `modelName` | string | `"claude-sonnet-4-5"` | Primary Claude model (`$ANTHROPIC_MODEL`) |
| `smallModelName` | string | `"claude-3-5-haiku"` | Fast model for lightweight tasks (`$ANTHROPIC_SMALL_FAST_MODEL`) |
| `vertexRegion` | string | `"europe-west1"` | Google Cloud region for Vertex AI (`$CLOUD_ML_REGION`) |
| `projectId` | string \| null | `null` | Hardcoded GCP project ID (takes precedence over env/interactive. `$ANTHROPIC_VERTEX_PROJECT_ID`) |
| `disablePromptCaching` | bool | `true` | Disable prompt caching (`$DISABLE_PROMPT_CACHING`) |

### Secrets with agenix

For potentially sensitive values like `projectId`, you can use [agenix][agenix] to manage secrets as environment variables. Since Nix evaluation happens at build time before secrets are decrypted, you cannot directly pass agenix secrets to `projectId`. Instead, use the `ANTHROPIC_VERTEX_PROJECT_ID` environment variable:

```nix
{ config, ... }: {
  programs.claude-vertex.enable = true;

  age.secrets.gcp-project-id.file = ./secrets/gcp-project-id.age;

  home.sessionVariables.ANTHROPIC_VERTEX_PROJECT_ID = "$(cat ${config.age.secrets.gcp-project-id.path})";
}
```

## Usage

Running `claude` (or `nix run github:JamyGolden/claude-vertex-flake`) launches Claude Code after authenticating with your Google account. Pass custom arguments:

```sh
claude --dangerously-skip-permissions

# Or via nix run:
nix run github:JamyGolden/claude-vertex-flake -- --dangerously-skip-permissions
```

> [!NOTE]
> When you run `claude`, it will automatically:
> - Use your only project if you have exactly one
> - Let you choose interactively if you have multiple projects

> [!TIP]
> Google authentication issues? Reset your gcloud config (`rm -rf ~/.config/gcloud`) and try again.

## Editor Support

### Zed

Zed [supports][zed-claude] Claude Code. To use with claude-vertex:

1. Successfully run `claude` using the instructions above
2. Export these environment variables:
   ```sh
   export ANTHROPIC_VERTEX_PROJECT_ID=your-project-id
   export CLAUDE_CODE_USE_VERTEX=1
   ```
3. Open Zed from the same terminal. On macOS: `open -a Zed`

## Development

```sh
nix develop # Enter dev shell with claude and alejandra
nix flake check # Run tests
nix fmt # Format Nix files
```

## Acknowledgements

Thanks to [juspay/vertex] for the original implementation. This fork adds more flexibility with configurable models, regions, and integration options like Home Manager modules and overlays.

[^cc]: See [Claude Code on Google Vertex AI][claude-vertex-docs]

[nix-install]: https://nixos.asia/en/install
[claude-vertex-docs]: https://docs.anthropic.com/en/docs/claude-code/google-vertex-ai
[agenix]: https://github.com/ryantm/agenix
[zed-claude]: https://zed.dev/blog/claude-code-via-acp
[juspay/vertex]: https://github.com/juspay/vertex
