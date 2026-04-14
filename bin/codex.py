import json
import os
import sys
from pathlib import Path


def main() -> None:
    # https://github.com/openai/codex/issues/16088#issuecomment-4246416434
    dot_codex = Path(".codex")
    if not dot_codex.exists() and Path(".git").exists():
        dot_codex.mkdir()
        (dot_codex / ".gitignore").write_text("*\n")
    project = json.dumps(str(Path.cwd()))
    # https://github.com/openai/codex/issues/14599#issuecomment-4091089485
    config = f'projects={{{project}={{trust_level="untrusted"}}}}'
    os.execvp("codex", ["codex", "-c", config, *sys.argv[1:]])


if __name__ == "__main__":
    main()
