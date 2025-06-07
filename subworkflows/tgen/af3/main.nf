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
    new_msa = STORE_MSA
}

workflow INFERENCE_WORKFLOW {
    take:
    meta_fasta

    main:

    json = COMPOSE_INFERENCE_JSON(meta_fasta)

    batched_json = json.collate(params.collate_inf_size).map { batch ->
        def allMeta    = batch.collect { it[0] }
        def allSeqLists = batch.collect { it[1] }
        tuple(allMeta, allSeqLists)
    }

    inference = BATCHED_INFERENCE(batched_json).flatMap { metas, inf_dirs ->
        metas.indices.collect { idx ->
        tuple( metas[idx], inf_dirs[idx] )
        }
    }

    if (params.compress_inf == true) {
        // Clean up inference directory
        inference = CLEAN_INFERENCE_DIR(inference)
    }

    emit:
    new_inference = inference
}
