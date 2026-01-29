# Claude Code Vertex AI Wrapper
#
# Builds a shell wrapper that:
# 1. Handles Google Cloud authentication (interactive login if needed)
# 2. Configures the GCP project (from args, file, env, or interactive selection)
# 3. Sets up Vertex AI environment variables
# 4. Launches Claude Code CLI
{
  # Configuration options (passed from lib.mkClaude)
  modelName ? null,
  smallModelName ? null,
  vertexRegion ? null,
  disablePromptCaching ? true,
  projectId ? null,
  # Dependencies (injected by callPackage)
  claude-code,
  fzf,
  google-cloud-sdk,
  jaq,
  lib,
  writeShellApplication,
}: let
  # Interactive GCP project selector using fzf
  # Fetches available projects and lets user choose
  # Returns the selected project ID on stdout
  selectGcloudProject = writeShellApplication {
    name = "select-gcloud-project";
    runtimeInputs = [fzf google-cloud-sdk jaq];
    text = ''
      set -euo pipefail

      echo "Fetching available Google Cloud projects..." >&2
      if ! PROJECTS_JSON=$(gcloud projects list --format=json); then
        echo "Error: Failed to fetch projects. Please check your gcloud authentication and permissions." >&2
        exit 1
      fi

      PROJECT_LIST=$(echo "$PROJECTS_JSON" | jaq -r '.[] | "\(.projectId) - \(.name)"')
      PROJECT_COUNT=$(echo "$PROJECT_LIST" | wc -l | tr -d ' ')

      if [ -z "$PROJECT_LIST" ] || [ "$PROJECT_COUNT" -eq 0 ]; then
        echo "Error: No Google Cloud projects found. Please create a project first." >&2
        exit 1
      elif [ "$PROJECT_COUNT" -eq 1 ]; then
        PROJECT_ID=$(echo "$PROJECT_LIST" | cut -d' ' -f1)
        echo "Using only available project: $PROJECT_ID" >&2
        echo "$PROJECT_ID"
      else
        echo "Select a Google Cloud project:" >&2
        SELECTED_PROJECT=$(echo "$PROJECT_LIST" | fzf)
        PROJECT_ID=$(echo "$SELECTED_PROJECT" | cut -d' ' -f1)
        echo "Selected project: $PROJECT_ID" >&2
        echo "$PROJECT_ID"
      fi
    '';
  };
in
  writeShellApplication {
    name = "claude";
    meta = {
      description = "Vend Claude Code CLI wrapper with Vertex AI integration";
      license = lib.licenses.unfree;
      platforms = lib.platforms.unix;
      mainProgram = "claude";
    };
    runtimeInputs = [google-cloud-sdk claude-code selectGcloudProject];
    text = ''
      set -euo pipefail

      GOOGLE_CLOUD_PROJECT=""

      ${
        if projectId != null
        then ''
          GOOGLE_CLOUD_PROJECT="${projectId}"
        ''
        else ""
      }

      if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
        GOOGLE_CLOUD_PROJECT="''${ANTHROPIC_VERTEX_PROJECT_ID:-}"
      fi

      # Check if already authenticated
      if ! gcloud auth application-default print-access-token &>/dev/null; then
        echo "Authentication required. Opening browser..."
        gcloud auth login

        # For some reason, we must re-auth
        # cf. https://stackoverflow.com/a/42059661/55246
        gcloud auth application-default login

        # Project selection
        GOOGLE_CLOUD_PROJECT="$(select-gcloud-project)"

        gcloud config set project "$GOOGLE_CLOUD_PROJECT"
        gcloud services enable aiplatform.googleapis.com
      elif [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
        echo "Already authenticated with Google Cloud."
        # Get current project
        GOOGLE_CLOUD_PROJECT="$(gcloud config get-value project)"
        if [ -z "$GOOGLE_CLOUD_PROJECT" ] || [ "$GOOGLE_CLOUD_PROJECT" = "(unset)" ]; then
          GOOGLE_CLOUD_PROJECT="$(select-gcloud-project)"
        else
          echo "Using configured project: $GOOGLE_CLOUD_PROJECT"
        fi
      fi

      if [ -z "$GOOGLE_CLOUD_PROJECT" ] || [ "$GOOGLE_CLOUD_PROJECT" = "(unset)" ]; then
        echo "Error: No project configured. Please reset your gcloud config and try again." >&2
        exit 1
      fi

      # Enable Vertex AI integration
      export CLAUDE_CODE_USE_VERTEX="1"
      export ANTHROPIC_VERTEX_PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
      ${
        if vertexRegion != null
        then "export CLOUD_ML_REGION=${vertexRegion}"
        else ""
      }

      ${
        if modelName != null
        then "export ANTHROPIC_MODEL=${modelName}"
        else ""
      }

      ${
        if smallModelName != null
        then "export ANTHROPIC_SMALL_FAST_MODEL=${smallModelName}"
        else ""
      }

      ${
        if disablePromptCaching
        then "export DISABLE_PROMPT_CACHING=1"
        else ""
      }

      if \
        [ -z "$ANTHROPIC_MODEL" ] || \
        [ -z "$ANTHROPIC_SMALL_FAST_MODEL" ] || \
        [ -z "$CLOUD_ML_REGION" ]; then
        echo "Missing the model, smallModel or region"
      fi

      echo "Launching Claude Code..."
      exec claude "$@"
    '';
  }
