"""Entry point. Kept at the project root so run_todo.ps1 and the desktop shortcut keep working.

    python main.py [--db PATH] [--title TEXT]
"""
import sys

from dailytodo.app import run

if __name__ == "__main__":
    sys.exit(run())
