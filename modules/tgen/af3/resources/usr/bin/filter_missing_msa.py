#!/usr/bin/env python3
import argparse
import os

import vastdb

VAST_S3_ACCESS_KEY_ID = os.getenv("VAST_S3_ACCESS_KEY_ID")
VAST_S3_SECRET_ACCESS_KEY = os.getenv("VAST_S3_SECRET_ACCESS_KEY")


def is_msa_stored(protein_type, seq, db_url):
    """Checks if the name exists in the VAST database."""
    try:

        session = vastdb.connect(
            endpoint=db_url,
            access=VAST_S3_ACCESS_KEY_ID,
            secret=VAST_S3_SECRET_ACCESS_KEY,
            ssl_verify=False,
        )

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
    except Exception as e:
        raise ConnectionError(f"Error connecting to database: {e}")


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

    database = "https://pub-vscratch.vast.rc.tgen.org"

    if not is_msa_stored(args.protein_type, args.seq, database):
        with open(args.fasta) as f:
            content = f.read()
        with open(args.output, "w") as f:
            f.write(content)
