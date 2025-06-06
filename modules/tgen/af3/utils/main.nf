process SEQ_LIST_TO_FASTA {
    queue       'compute'
    executor    "slurm"
    cpus        1
    memory      '1GB'
    clusterOptions '--nodes=1 --ntasks=1 --time=00:10:00'

    input:
      tuple val(meta), val(seq_list)

    output:
      tuple val(meta), path("${meta.job_name}.fasta")

    script:
    """
    filename="${meta.job_name}.fasta"
    : > "\$filename"

    i=1
    for seq in ${seq_list}; do
        echo ">\$i"   >> "\$filename"
        echo "\$seq"  >> "\$filename"
        i=\$(( i + 1 ))
    done
    """
}
