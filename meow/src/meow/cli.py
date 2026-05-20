"""CLI entry point for meow."""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="meow",
        description="Cat meow detector daemon",
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("run", help="Run the detector in the foreground")

    daemon_parser = sub.add_parser("daemon", help="Manage the macOS LaunchAgent")
    daemon_parser.add_argument(
        "action",
        choices=["install", "uninstall", "restart", "status", "log"],
    )

    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    if args.command == "run":
        from .daemon import run

        try:
            run()
        except KeyboardInterrupt:
            print("\n[meow] stopped")
    elif args.command == "daemon":
        from .launchagent import handle

        handle(args.action)


if __name__ == "__main__":
    main()
