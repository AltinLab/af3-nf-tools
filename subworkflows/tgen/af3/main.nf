// defaults
params.compress_inf = params.compress_inf ?: true
params.seeds = params.seeds ?: "1"
params.collate_inf_size = params.collate_inf_size ?: 50
params.check_inf_exists = params.check_inf_exists ?: true
params.skip_msa = params.skip_msa ?: false

include { FILTER_MISSING_MSA; 
            COMPOSE_EMPTY_MSA_JSON; 
            RUN_MSA;
            STORE_MSA;
            COMPOSE_INFERENCE_JSON;
            BATCHED_INFERENCE;
            CLEAN_INFERENCE_DIR} from '../../../modules/tgen/af3'


workflow MSA_WORKFLOW {
    take:
    meta_fasta

    main:
    FILTER_MISSING_MSA(meta_fasta)
    COMPOSE_EMPTY_MSA_JSON(FILTER_MISSING_MSA.out)
    RUN_MSA(COMPOSE_EMPTY_MSA_JSON.out)
    STORE_MSA(RUN_MSA.out)

    emit:
    new_msa = STORE_MSA.out
}

workflow INFERENCE_WORKFLOW {
    take:
    meta_fasta
    msa_ready

    main:
    
    json = COMPOSE_INFERENCE_JSON(meta_fasta)

    batched_json = json.collate(params.collate_inf_size)

    inference = BATCHED_INFERENCE(batched_json)

    if (params.compress_inf == true) {
        // Clean up inference directory
        inference = CLEAN_INFERENCE_DIR(inference)
    }

    emit:
    new_inference = inference
}