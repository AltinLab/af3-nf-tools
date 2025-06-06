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
        clean_inference_dir.py \\
            -i $inference_dir \\
            -o inference
    """
}

