#!/usr/bin/env python3

import argparse
import json
import os
import vastdb
import pyarrow as pa
from datetime import date
from pathlib import Path
import hashlib
from contextlib import contextmanager
import time

VAST_S3_ACCESS_KEY_ID = os.getenv("VAST_S3_ACCESS_KEY_ID")
VAST_S3_SECRET_ACCESS_KEY = os.getenv("VAST_S3_SECRET_ACCESS_KEY")

EPOCH = date(1970, 1, 1)

MAX_RETRY_ATTEMPT = 10


def read_json(json_path):
    """Reads the JSON file and extracts relevant data."""
    try:
        with open(json_path, "r") as f:
            data = json.load(f)

        msa_data = data.get("sequences", None)[0].get("protein", None)
        del msa_data["id"]

        seq = msa_data["sequence"]
        empty_query = f">query\n{seq}\n"

        if (
            msa_data["unpairedMsa"] == empty_query
            and msa_data["pairedMsa"] == empty_query
        ):
            is_empty = True
        else:
            is_empty = False

        return json.dumps(msa_data), is_empty, seq
    except Exception as e:
        print(f"Error processing JSON: {e}")
        return None


def store_in_database(
    protein_type,
    seq,
    db_url,
    msa_json,
    is_empty,
):
    """Stores the JSON directly into the VAST database."""

    date_val = (date.today() - EPOCH).days

    h = hashlib.sha256()

    if protein_type == "peptide":
        fname = seq + ".json"
    else:
        h.update(seq.encode("utf-8"))
        fname = h.hexdigest() + ".json"

    filepath = Path("/tgen_labs/altin/alphafold3/msa") / protein_type / fname

    with open(filepath, "w+") as f:

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

        # manually perform an UPSERT
        with session.transaction() as tx:
            bucket = tx.bucket("altindbs3")
            schema = bucket.schema("alphafold-3")

            if protein_type == "tcr":
                table = schema.table("tcr_chain_msa")
                primary_key_name = "tcr_chain_msa_id"
                predicate = table["tcr_chain_msa_id"] == seq

                data = [
                    [seq],
                    [None],
                    [filepath.as_posix()],
                    [is_empty],
                    [date_val],
                ]

                new_row = pa.table(schema=table.arrow_schema, data=data)

            elif protein_type == "mhc":
                table = schema.table("mhc_chain_msa")
                primary_key_name = "mhc_chain_msa_id"
                predicate = table["mhc_chain_msa_id"] == seq
                data = [
                    [seq],
                    [None],
                    [None],
                    [None],
                    [None],
                    [filepath.as_posix()],
                    [is_empty],
                    [date_val],
                ]
                new_row = pa.table(schema=table.arrow_schema, data=data)

            elif protein_type == "peptide":
                table = schema.table("peptide_msa")
                primary_key_name = "peptide_msa_id"
                predicate = table["peptide_msa_id"] == seq
                data = [
                    [seq],
                    [filepath.as_posix()],
                    [is_empty],
                    [date_val],
                ]
                new_row = pa.table(
                    schema=table.arrow_schema,
                    data=data,
                )
            elif protein_type == "any":
                table = schema.table("any_msa")
                primary_key_name = "any_msa_id"
                predicate = table["any_msa_id"] == seq
                data = [
                    [seq],
                    [filepath.as_posix()],
                    [is_empty],
                    [date_val],
                ]
                new_row = pa.table(
                    schema=table.arrow_schema,
                    data=data,
                )
            else:
                raise ValueError

            # first SELECT
            result = table.select(
                columns=[primary_key_name],
                predicate=predicate,
                internal_row_id=True,
            ).read_all()

            # either insert or update
            if result.shape[0] == 0:
                table.insert(new_row)
            else:

                schema = pa.schema(
                    [pa.field("$row_id", pa.uint64())]
                    + list(table.arrow_schema)
                )
                data = [[result["$row_id"][0]]] + data
                updated_row = pa.table(schema=schema, data=data)
                table.update(updated_row)

        f.write(msa_json)
        f.flush()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Store MSA JSON into SQLite DB."
    )

    parser.add_argument(
        "-t", "--protein_type", type=str, required=True, help="Protein type"
    )

    parser.add_argument(
        "-j",
        "--json_msa_path",
        type=str,
        required=True,
        help="Path to JSON MSA",
    )

    args = parser.parse_args()

    database = "https://pub-vscratch.vast.rc.tgen.org"

    # if not os.path.exists(args.json_msa_path):
    #     print(f"Error: JSON file {args.json_msa_path} not found.")
    #     exit(1)

    msa_json, is_empty, seq = read_json(args.json_msa_path)

    store_in_database(
        args.protein_type,
        seq,
        database,
        msa_json,
        is_empty,
    )
