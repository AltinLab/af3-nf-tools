#!/usr/bin/env python3
import argparse
import os
import json
import vastdb
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


def is_msa_stored(protein_type, seq, db_url):
    """Checks if the name exists in the VAST database."""

    delay = 1

    for attempt in range(1, MAX_RETRY_ATTEMPT + 1):
        try:
            session = vastdb.connect(
                endpoint=db_url,
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

    with session.transaction() as tx:

        bucket = tx.bucket("altindbs3")
        schema = bucket.schema("alphafold-3")

        if protein_type == "tcr":
            table = schema.table("tcr_chain_msa")
            predicate = table["tcr_chain_msa_id"] == seq
            primary_key_name = "tcr_chain_msa_id"

        elif protein_type == "mhc":
            table = schema.table("mhc_chain_msa")
            predicate = table["mhc_chain_msa_id"] == seq
            primary_key_name = "mhc_chain_msa_id"
        elif protein_type == "peptide":
            table = schema.table("peptide_msa")
            predicate = table["peptide_msa_id"] == seq
            primary_key_name = "peptide_msa_id"
        elif protein_type == "any":
            table = schema.table("any_msa")
            predicate = table["any_msa_id"] == seq
            primary_key_name = "any_msa_id"
        else:
            raise ValueError

        result = table.select(
            columns=[primary_key_name], predicate=predicate
        ).read_all()

        if result.shape[0] == 0:
            return False
        return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Check if an MSA entry is missing from SQLite DB."
    )
    parser.add_argument(
        "-t", "--protein_type", type=str, required=True, help="Protein type"
    )
    parser.add_argument(
        "-f", "--fasta", type=str, required=True, help="Protein sequence"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        required=True,
        help="Output file",
    )
    args = parser.parse_args()
    seq = read_fasta_seqs(args.fasta)[0]

    database = "https://pub-vscratch.vast.rc.tgen.org"

    if not is_msa_stored(args.protein_type, seq, database):

        with open(args.output, "w") as f:
            json_dict = {
                "name": "af3-single-chain-msa",
                "modelSeeds": [42],
                "sequences": [{"protein": {"id": "A", "sequence": seq}}],
                "dialect": "alphafold3",
                "version": 1,
            }
            json.dump(json_dict, f, indent=2)
