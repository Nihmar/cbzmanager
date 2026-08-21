"""CLI entry point for cbz-manager."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from cbz_manager import __version__
from cbz_manager.convert import convert_webp
from cbz_manager.delete_by_id import delete_pages_by_id
from cbz_manager.delete_pages import delete_pages
from cbz_manager.find_similar import find_similar
from cbz_manager.merge import merge
from cbz_manager.validate import validate


def main(argv: list[str] | None = None) -> int:
    """Main entry point for cbz-manager CLI."""
    parser = argparse.ArgumentParser(
        prog="cbz-manager",
        description="CLI utility for managing manga CBZ files",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    subparsers = parser.add_subparsers(dest="operation", help="Operation to perform")

    # Common arguments for all operations
    for name, help_text in [
        ("validate", "Verify CBZ files are valid and images are not corrupted"),
        ("convert-webp", "Convert images to WebP format (quality 75%)"),
    ]:
        sub = subparsers.add_parser(name, help=help_text)
        sub.add_argument("directory", help="Directory containing CBZ files")
        sub.add_argument(
            "--delete",
            action="store_true",
            default=False,
            help="Delete original files after processing (default: rename to _OLD.cbz)",
        )

    # Merge has extra flags
    sub_merge = subparsers.add_parser("merge", help="Merge chapter CBZ files into volumes")
    sub_merge.add_argument("directory", help="Directory containing CBZ files")
    sub_merge.add_argument(
        "--delete",
        action="store_true",
        default=False,
        help="Delete original files after processing (default: rename to _OLD.cbz)",
    )
    sub_merge.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="Append remaining chapters to the last volume instead of skipping them",
    )
    sub_merge.add_argument(
        "--chapters",
        type=str,
        default=None,
        metavar="N1,N2,N3,...",
        help="Exact chapter counts per volume, comma-separated (e.g. '5,6,3')",
    )
    sub_merge.add_argument(
        "--chapters-per-volume",
        type=int,
        default=None,
        metavar="N",
        help="Override default chapters-per-volume with a fixed integer",
    )

    # delete-pages
    sub_del = subparsers.add_parser("delete-pages", help="Delete pages by position from CBZ files")
    sub_del.add_argument("directory", help="Directory containing CBZ files")
    sub_del.add_argument(
        "--pages",
        type=str,
        required=True,
        metavar="PAGES",
        help="Page numbers to delete, e.g. '3,5-20,22' (1-indexed, sorted by filename)",
    )
    sub_del.add_argument(
        "--delete",
        action="store_true",
        default=False,
        help="Delete original files after processing (default: rename to _OLD.cbz)",
    )

    # find-similar
    sub_sim = subparsers.add_parser(
        "find-similar", help="Find similar pages across CBZ files using difference hashing"
    )
    sub_sim.add_argument("directory", help="Directory containing CBZ files")
    sub_sim.add_argument(
        "--output",
        type=str,
        required=True,
        metavar="DIR",
        help="Output directory for extracted similar page groups",
    )
    sub_sim.add_argument(
        "--threshold",
        type=int,
        default=10,
        metavar="N",
        help="Hamming distance threshold for similarity (default: 10)",
    )

    # delete-pages-by-id
    sub_del_id = subparsers.add_parser(
        "delete-pages-by-id", help="Delete specific page entries by ID (filename:entry_name)"
    )
    sub_del_id.add_argument("directory", help="Directory containing CBZ files")
    sub_del_id.add_argument(
        "--ids",
        type=str,
        default=None,
        metavar="IDS",
        help="Comma-separated page IDs, e.g. 'ch01.cbz:page_003.png,ch02.cbz:page_001.jpg'",
    )
    sub_del_id.add_argument(
        "--ids-file",
        type=str,
        default=None,
        metavar="FILE",
        help="Path to file with one page ID per line",
    )
    sub_del_id.add_argument(
        "--delete",
        action="store_true",
        default=False,
        help="Delete original files after processing (default: rename to _OLD.cbz)",
    )

    args = parser.parse_args(argv)

    if args.operation is None:
        parser.print_help()
        return 1

    directory = Path(args.directory)
    if not directory.is_dir():
        print(f"Error: '{directory}' is not a valid directory", file=sys.stderr)
        return 1

    if args.operation in ("validate", "convert-webp"):
        delete = args.delete
    elif args.operation in ("delete-pages", "delete-pages-by-id"):
        delete = args.delete
    else:
        delete = False

    if args.operation == "validate":
        return validate(directory)
    elif args.operation == "convert-webp":
        return convert_webp(directory, delete=delete)
    elif args.operation == "merge":
        if args.chapters is not None and args.chapters_per_volume is not None:
            print(
                "Error: --chapters and --chapters-per-volume are mutually exclusive",
                file=sys.stderr,
            )
            return 1

        chapters_list = None
        if args.chapters is not None:
            chapters_list = [int(x.strip()) for x in args.chapters.split(",")]

        return merge(
            directory,
            delete=args.delete,
            force=args.force,
            chapters_list=chapters_list,
            chapters_per_volume_int=args.chapters_per_volume,
        )
    elif args.operation == "delete-pages":
        return delete_pages(directory, pages_str=args.pages, delete=delete)
    elif args.operation == "find-similar":
        return find_similar(
            directory,
            output_dir=Path(args.output),
            threshold=args.threshold,
        )
    elif args.operation == "delete-pages-by-id":
        if args.ids is None and args.ids_file is None:
            print("Error: --ids or --ids-file must be provided", file=sys.stderr)
            return 1
        return delete_pages_by_id(
            directory,
            ids_str=args.ids,
            ids_file=args.ids_file,
            delete=delete,
        )

    return 1


if __name__ == "__main__":
    sys.exit(main())
