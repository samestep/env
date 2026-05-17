import argparse
import sys


def main() -> None:
    description = "set the title of the terminal"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("title")
    args = parser.parse_args()

    sys.stdout.write(f"\033]0;{args.title}\a")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
