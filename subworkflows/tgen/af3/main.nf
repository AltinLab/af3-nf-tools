include { FILTER_MISSING_MSA, STORE_MSA, RUN_MSA } from '../../../modules/tgen/af3/msa'


workflow MSA_WORKFLOW {
    take:
    meta_fasta

    main:
    filt = filter_missing_msa(meta_fasta)
    complete = run_msa(filt)
    store = store_msa(complete)

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