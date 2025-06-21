process SEQ_LIST_TO_FASTA {
    label "process_local"

    input:
      tuple val(meta), val(seq_list)

    output:
      tuple val(meta), path("${meta.id}.fasta")

    script:
    """
    filename="${meta.id}.fasta"
    : > "\$filename"

    i=1
    for seq in ${seq_list.join(' ')}; do
        echo ">\$i"   >> "\$filename"
        echo "\$seq"  >> "\$filename"
        i=\$(( i + 1 ))
    done
    """
}

// process FILTER_MISSING_MSA {
//     label "process_local"
//     tag "${meta.protein_type}-${meta.id}"

//     input:
//     tuple val(meta), path(fasta)

//     output:
//     tuple val(meta), path("*.fasta"), optional: true


//     script:
//     """
//     module load singularity

//     fname=\$(uuidgen).csv

//     export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
//     export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"

//     singularity exec --nv \\
//         -B /home,/scratch,/tgen_labs --cleanenv \\
//         /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
//         python ${moduleDir}/resources/usr/bin/filter_missing_msa.py \\
//             -t "${meta.protein_type}" \\
//             -f "$fasta" \\
//             -o "${fasta.getSimpleName()}.filt.json"
//     """
// }

process COMPOSE_EMPTY_MSA_JSON {
    label "process_local"
    tag "${meta.protein_type}-${meta.id}"

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

process FILT_FORMAT_MSA {
    label "process_local"
    tag "${meta.protein_type}-${meta.id}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.json"), optional: true


    script:
    def force = params.force_update_msa ? "--force" : ''
    """
    module load singularity

    export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
    export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"

    singularity exec --nv \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${moduleDir}/resources/usr/bin/filt_format_msa.py \\
            -t "${meta.protein_type}" \\
            -f "$fasta" \\
            -o "${fasta.getSimpleName()}.filt.json" \\
            ${force} 
    """
}

process RUN_MSA {
    queue 'compute'
    cpus '8'
    memory { "${ Math.min(256, 64 * Math.pow(2, task.attempt - 1)) }GB" }
    executor "slurm"
    clusterOptions '--time=8:00:00'
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5
    tag "${meta.protein_type}-${meta.id}"

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
    label "process_local"
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5
    tag "${meta.protein_type}-${meta.id}"
    
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
    label "process_local"
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5
    tag "${meta.id}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.json"), optional: true


    script:
    def seeds = params.seeds ? "--seeds ${params.seeds}" : ''
    def check_inf_exists = params.check_inf_exists ? """
    if [ -d "${params.outdir}/inference/${meta.id}" ]; then
        echo "Skipping ${meta.id}"
        exit 0
    fi
    """ : ''
    def skip_msa_arg = params.skip_msa ? "--skip_msa ${params.skip_msa}" : ''
    """
    module load singularity

    $check_inf_exists

    export SINGULARITYENV_VAST_S3_ACCESS_KEY_ID="\$VAST_S3_ACCESS_KEY_ID"
    export SINGULARITYENV_VAST_S3_SECRET_ACCESS_KEY="\$VAST_S3_SECRET_ACCESS_KEY"

    singularity exec \\
        -B /home,/scratch,/tgen_labs --cleanenv \\
        /tgen_labs/altin/alphafold3/containers/msa-db.sif \\
        python ${moduleDir}/resources/usr/bin/compose_inference_JSON.py \\
            -jn "${meta.id}" \\
            -f "$fasta" \\
            -pt "${meta.protein_types.join(' ')}" \\
            ${skip_msa_arg} \\
            ${seeds} 
    """
 }

process BATCHED_INFERENCE {
    queue 'gpu-a100'
    cpus '8'
    clusterOptions '--nodes=1 --ntasks=1 --gres=gpu:1 --time=24:00:00'
    memory '64GB'
    executor "slurm"
    tag "batched_inference"

    if (params.compress_inf == false) {
        publishDir "${params.outdir}", mode: 'copy'
    }

    input:
    tuple val(batched_meta), path(batched_json)

    output:
    tuple val(batched_meta), path("inference/*")
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
    label "process_local"
    tag "clean_inference"
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5
    publishDir "${params.outdir}", mode: 'copy'

    input:
    tuple val(meta), path(inference_dir)

    output:
    tuple val(meta), path("inference/*")

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

