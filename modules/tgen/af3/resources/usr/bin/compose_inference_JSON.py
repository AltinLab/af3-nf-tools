#!/usr/bin/env python3
import argparse
import sqlite3
import json
import sys
import os
import vastdb
import fcntl
from contextlib import contextmanager

import time

VAST_S3_ACCESS_KEY_ID = os.getenv("VAST_S3_ACCESS_KEY_ID")
VAST_S3_SECRET_ACCESS_KEY = os.getenv("VAST_S3_SECRET_ACCESS_KEY")
MAX_RETRY_ATTEMPT = 10


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


def get_msa(session, protein_type, seq):
    """
    Query the specified table for the msa JSON corresponding to the given name.
    Returns the parsed JSON object if found, otherwise None.
    """

    with session.transaction() as tx:
        bucket = tx.bucket("altindbs3")
        schema = bucket.schema("alphafold-3")

        if protein_type == "tcr":
            table = schema.table("tcr_chain_msa")
            predicate = table["tcr_chain_msa_id"] == seq

        elif protein_type == "mhc":
            table = schema.table("mhc_chain_msa")
            predicate = table["mhc_chain_msa_id"] == seq

        elif protein_type == "peptide":
            table = schema.table("peptide_msa")
            predicate = table["peptide_msa_id"] == seq

        elif protein_type == "any":
            table = schema.table("any_msa")
            predicate = table["any_msa_id"] == seq

        else:
            raise ValueError

        result = table.select(
            columns=["msa_path"], predicate=predicate
        ).read_all()

        if result.shape[0] != 1:
            raise ValueError(
                f"Error fetching MSA for {protein_type} {seq}. "
                f"Expected 1 row, got {result.shape[0]}"
            )

        # if currently being rewritten, wait to avoid
        # reading incomplete data
        with open(result["msa_path"][0].as_py(), "r") as f:
            msa = json.load(f)

        return msa


def main():
    parser = argparse.ArgumentParser(
        description="Compose Alphafold3 input JSON by querying VAST for chain MSA information."
    )
    parser.add_argument(
        "-jn", "--job_name", type=str, required=True, help="Job name"
    )
    parser.add_argument(
        "-f",
        "--fasta_path",
        type=str,
        required=True,
        help="Path to fasta file",
    )
    parser.add_argument(
        "--skip_msa",
        type=str,
        help="Skip MSA for sequence at index i",
    )
    parser.add_argument(
        "-pt",
        "--protein_type",
        type=str,
        required=True,
        help="Protein types",
    )
    parser.add_argument(
        "-s",
        "--seeds",
        type=str,
        required=False,
        default="42",
        help="Comma separated list of model seeds",
    )

    args = parser.parse_args()

    if args.skip_msa:
        skip_msa = set([int(i) for i in args.skip_msa.split(",")])

    protein_type = list(args.protein_type.split(","))

    seeds = [int(seed) for seed in args.seeds.split(",")]

    database = "https://pub-vscratch.vast.rc.tgen.org"

    delay = 1

    for attempt in range(1, MAX_RETRY_ATTEMPT + 1):
        try:
            session = vastdb.connect(
                endpoint=database,
                access=VAST_S3_ACCESS_KEY_ID,
                secret=VAST_S3_SECRET_ACCESS_KEY,
                ssl_verify=False,
            )
            break
        except Exception as e:
            if attempt == MAX_RETRY_ATTEMPT:
                raise
            time.sleep(delay)
            delay = delay * 2
    msas = []

    seqs = read_fasta_seqs(args.fasta_path)

    for i, seq in enumerate(seqs):

        if args.skip_msa and i in skip_msa:
            msa = {
                "protein": {
                    "id": chr(65 + i),
                    "sequence": seq,
                    "unpairedMsa": f">query\n{seq}\n",
                    "pairedMsa": f">query\n{seq}\n",
                    "templates": [],
                },
            }
        else:
            msa = get_msa(session, protein_type[i], seq)
            msa["id"] = chr(65 + i)
            msa = {"protein": msa}
        msas.append(msa)

    final_json = {
        "name": args.job_name,
        "modelSeeds": seeds,
        "sequences": msas,
        "dialect": "alphafold3",
        "version": 1,
    }
    with open(args.job_name + ".json", "w") as f:
        json.dump(final_json, f, indent=2)


if __name__ == "__main__":
    main()
