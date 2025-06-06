include from '../../../modules/tgen/af3'


workflow MSA_WORKFLOW {
    take:
    meta_fasta

    main:
    FILTER_MISSING_MSA(meta_fasta)
    COMPOSE_EMPTY_MSA_JSON(FILTER_MISSING_MSA.out)
    RUN_MSA(FILTER_MISSING_MSA.out)
    STORE_MSA(RUN_MSA.out)

    emit:
    new_msa = store
}

workflow INFERENCE_WORKFLOW {
    take:
    meta_fasta, msa_ready

    main:
    
    json = COMPOSE_INFERENCE_JSON(meta_fasta)

    inference = RUN_INFERENCE(json)

    // Clean up inference directory
    clean_inference = CLEAN_INFERENCE_DIR(inference)

    emit:
    new_inference = clean_inference
}