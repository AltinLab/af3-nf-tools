#!/usr/bin/env python3
import argparse
import json


def get_arguments():
    parser = argparse.ArgumentParser(description="Commands to pass to scripts")
    parser.add_argument(
        "-jn", "--job_name", type=str, required=True, help="Job name"
    )
    parser.add_argument(
        "-f",
        "--fasta_path",
        type=str,
        required=True,
        help="Fasta file path containing protein sequence",
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
fasta_path = args.fasta_path
id = args.protein_id

with open(fasta_path) as f:
    lines = f.readlines()
    sequence = "".join(line.strip() for line in lines[1:])

json_dict = {
    "name": job_name,
    "modelSeeds": [42],
    "sequences": [{"protein": {"id": id, "sequence": sequence}}],
    "dialect": "alphafold3",
    "version": 1,
}


with open(job_name + ".json", "w") as f:
    json.dump(json_dict, f, indent=2)
