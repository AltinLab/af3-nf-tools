process SEQ_LIST_TO_FASTA {
    queue       'compute'
    executor    "slurm"
    cpus        1
    memory      '1GB'
    clusterOptions '--nodes=1 --ntasks=1 --time=00:10:00'

    input:
      tuple val(meta), val(seq_list)

    output:
      tuple val(meta), path("${meta.id}.fasta")

    script:
    """
    filename="${meta.id}.fasta"
    : > "\$filename"

    i=1
    for seq in ${seq_list}; do
        echo ">\$i"   >> "\$filename"
        echo "\$seq"  >> "\$filename"
        i=\$(( i + 1 ))
    done
    """
}

process FILTER_MISSING_MSA {
    queue 'compute'
    executor "slurm"
    tag "${proteinType}_${seq}"
    debug true

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.fasta"), optional: true


    script:
    """
    module load singularity

    fname=\$(uuidgen).csv

    export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
    export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"

    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${moduleDir}/resources/usr/bin/filter_missing_msa.py \\
            -t "${meta.protein_type}" \\
            -f "$fasta" \\
            -o "${fasta.getSimpleName()}.filt.fasta"
    """
}

process COMPOSE_EMPTY_MSA_JSON {
    queue 'compute'
    executor "slurm"
    tag "${meta.id}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.json")

    script:
    """
    module load singularity

    # name doesn't matter here
    fname=\$(uuidgen)

    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${moduleDir}/resources/usr/bin/generate_single_JSON.py \\
            -f "$fasta" \\
            -jn "\$fname" 
    """
 }

process RUN_MSA {
    queue 'compute'
    cpus '8'
    memory '64GB'
    executor "slurm"
    clusterOptions '--time=4:00:00'
    tag "${proteinType}_${seq}"

    input:
    tuple val(meta), path(json)

    output:
    tuple val(meta), path("*/*.json")

    script:
    """
    module load singularity

    singularity exec \\
        -B /home,/scratch,/tgen_labs,/ref_genomes \\
        --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/alphafold_3.0.1.sif \\
        python /app/alphafold/run_alphafold.py \\
            --json_path=$json \\
            --model_dir=/ref_genomes/alphafold/alphafold3/models \\
            --db_dir=/ref_genomes/alphafold/alphafold3/ \\
            --output_dir=. \\
            --norun_inference
    """
}



process STORE_MSA {
    queue 'compute'
    executor "slurm"
    tag "${proteinType}_${seq}"
    
    input:
    tuple val(meta), path(json)

    output:
    tuple val(meta), path(json)

    script:
    """
    module load singularity

    export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
    export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"
    
    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${moduleDir}/resources/usr/bin/store_msa.py \\
            -t "${meta.protein_type}" \\
            -j "$json"
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
        python ${moduleDir}/resources/usr/bin/compose_inference_JSON.py \\
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

process BATCHED_INFERENCE {
    queue 'gpu-a100'
    cpus '8'
    clusterOptions '--nodes=1 --ntasks=1 --gres=gpu:1 --time=24:00:00'
    memory '64GB'
    executor "slurm"
    tag "batched_inference"
    if (params.compress == false) {
        publishDir "${params.out_dir}", mode: 'copy'
    }

    input:
    tuple val(batched_meta), path(batched_json)

    output:
    tuple val(batched_meta), path("inference/*"), emit: inference

    script:
    """
    module load singularity

    mkdir -p tmp

    for f in ${batched_json}; do
         cp \$f tmp/
    done

    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs,/ref_genomes --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/alphafold_3.0.1.sif \\
        python /app/alphafold/run_alphafold.py \\
            --input_dir=tmp \\
            --model_dir=/ref_genomes/alphafold/alphafold3/models \\
            --db_dir=/ref_genomes/alphafold/alphafold3/ \\
            --output_dir=inference \\
            --norun_data_pipeline \\
            --num_diffusion_samples=1
        """
}

process CLEAN_INFERENCE_DIR {
    queue 'compute'
    executor "slurm"
    tag "clean_inference"
    publishDir "${params.out_dir}", mode: 'copy'

    input:
    tuple val(meta), path(inference_dir)

    output:
    tuple val(meta), path("inference/*"), emit: inference

    script:
    """
    module load singularity

    mkdir -p inference

    singularity exec \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/af3-models.sif \\
        python ${moduleDir}/resources/usr/bin/clean_inference_dir.py \\
            -i $inference_dir \\
            -o inference
    """
}

