#!/usr/bin/env python
"""
Copy an inference directory to a new directory and then compress the copy
"""

import argparse
from af3models.common.AF3OutputParser import AF3Output
from pathlib import Path
import shutil, errno


def copyanything(src, dst):
    try:
        shutil.copytree(src, dst)
    except OSError as exc:
        if exc.errno in (errno.ENOTDIR, errno.EINVAL):
            shutil.copy(src, dst)
        else:
            raise


def main():
    parser = argparse.ArgumentParser(
        description="Clean an AF3 inference directory."
    )
    parser.add_argument(
        "-i", "--inf_dir", type=str, required=True, help="Inference directory"
    )
    parser.add_argument(
        "-o",
        "--out_dir",
        type=str,
        required=True,
        help="Output directory",
    )

    args = parser.parse_args()
    inf_dir = Path(args.inf_dir)
    out_dir = Path(args.out_dir)

    dest = out_dir / inf_dir.name

    copyanything(inf_dir, dest)

    af3_out = AF3Output(dest)

    af3_out.compress()


if __name__ == "__main__":
    main()
