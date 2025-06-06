include { FILTER_MISSING_MSA; 
            COMPOSE_EMPTY_MSA_JSON; 
            RUN_MSA;
            STORE_MSA;
            COMPOSE_INFERENCE_JSON;
            BATCHED_INFERENCE;
            CLEAN_INFERENCE_DIR;
            NO_OP_DAG_DEP} from '../../../modules/tgen/af3'


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
    
    // now EVERY inference depends on ALL MSA being done
    meta_fasta = NO_OP_DAG_DEP(meta_fasta, msa_ready)

    json = COMPOSE_INFERENCE_JSON(meta_fasta)

    batched_json = json.collate(params.collate_inf_size).map { batch ->
        def allMeta    = batch.collect { it[0] }
        def allSeqLists = batch.collect { it[1] }
        tuple(allMeta, allSeqLists)
    }

    inference = BATCHED_INFERENCE(batched_json)

    if (params.compress_inf == true) {
        // Clean up inference directory
        inference = CLEAN_INFERENCE_DIR(inference)
    }

    emit:
    new_inference = inference
}