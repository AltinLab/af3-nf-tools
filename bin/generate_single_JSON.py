#!/usr/bin/env python3
import argparse
import json


def get_arguments():
    parser = argparse.ArgumentParser(description="Commands to pass to scripts")
    parser.add_argument(
        "-jn", "--job_name", type=str, required=True, help="Job name"
    )
    parser.add_argument(
        "-s", "--seq", type=str, required=True, help="Protein sequence"
    )
    parser.add_argument(
        "-id",
        "--protein_id",
        type=str,
        required=False,
        help="Protein sequence",
        default="A",
    )

    return parser.parse_args()


args = get_arguments()
job_name = args.job_name
sequence = args.seq
id = args.protein_id

json_dict = {
    "name": job_name,
    "modelSeeds": [42],
    "sequences": [{"protein": {"id": id, "sequence": sequence}}],
    "dialect": "alphafold3",
    "version": 1,
}


with open(job_name + ".json", "w") as f:
    json.dump(json_dict, f, indent=2)
