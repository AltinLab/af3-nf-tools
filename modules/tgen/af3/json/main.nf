process COMPOSE_EMPTY_MSA_JSON {
    queue 'compute'
    executor "slurm"
    tag "${proteinType}_${seq}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path(fasta), emit: fasta
    tuple val(meta), path("*.json"), emit: json
    script:
    """
    module load singularity

    fname=\$(uuidgen)

    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        generate_single_JSON.py \\
            -s "$seq" \\
            -jn "\$fname" 
    """
 }


process COMPOSE_INFERENCE_JSON {
    queue 'compute'
    executor "slurm"
    tag "$job_name"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path(fasta), emit: fasta
    tuple val(meta), path("*.json"), emit: json

    script:
    def peptide_msa = params.no_peptide ? '' : "-pm"
    def seeds = params.seeds ? "--seeds ${params.seeds}" : ''
    def check_inf_exists = params.check_inf_exists ? """
    if [ -d "${params.out_dir}/inference/$job_name" ]; then
        echo "Skipping $job_name"
        exit 0
    fi
    """ : ''
    // this is to allow no B2M in class I
    def mhc_2_seq_arg = mhc_2_seq ? "-m2s '$mhc_2_seq'" : ''
    """
    module load singularity

    $check_inf_exists

    export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
    export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"

    singularity exec \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${workflow.projectDir}/modules/json/compose_inference_JSON.py \\
            -jn "$job_name" \\
            -p "$peptide" \\
            ${peptide_msa} \\
            -m1s "$mhc_1_seq" \\
            ${mhc_2_seq_arg} \\
            -t1s "$tcr_1_seq" \\
            -t2s "$tcr_2_seq" \\
            ${seeds} \\
            -db "$params.msa_db"
    """
 }