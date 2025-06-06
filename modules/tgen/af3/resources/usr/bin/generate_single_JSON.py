#!/usr/bin/env python3
import argparse
import json


def read_fasta_seqs(path):
    """
    Read a FASTA file and return a list of sequences (strings),
    concatenating multi-line records correctly.
    """
    seqs = []
    current_seq = []

    with open(path) as f:
        for line in f:
            line = line.rstrip()
            if not line:
                continue
            if line.startswith(">"):
                # If we were in the middle of a sequence, save it.
                if current_seq:
                    seqs.append("".join(current_seq))
                    current_seq = []
                # (We skip the header itself; if you need headers, collect them here.)
            else:
                # Append this line to the current sequence buffer
                current_seq.append(line)

        # After the loop, make sure to save the last sequence
        if current_seq:
            seqs.append("".join(current_seq))

    return seqs


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

sequence = read_fasta_seqs(fasta_path)[0]

json_dict = {
    "name": job_name,
    "modelSeeds": [42],
    "sequences": [{"protein": {"id": id, "sequence": sequence}}],
    "dialect": "alphafold3",
    "version": 1,
}


with open(job_name + ".json", "w") as f:
    json.dump(json_dict, f, indent=2)
