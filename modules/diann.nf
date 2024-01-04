
process DIANN_SEARCH {
    publishDir "${params.results_dir}/diann", failOnError: true, mode: 'copy'
    label 'process_high_constant'
    container "mauraisa/diann:1.8.1"
    
    input:
        path ms_files
        path fasta_file
        path spectral_library
    
    output:
        path("report.tsv.speclib"), emit: speclib
        path("report.tsv"), emit: precursor_tsv

    script:
        ms_file_args = "--f '${ms_files.join('\' --f \'')}'"
        """
        diann ${ms_file_args} \
            --threads ${task.cpus} \
            --fasta "${fasta_file}" \
            --lib "${spectral_library}" \
            --unimod4 --qvalue 0.01 --cut 'K*,R*,!*P' --reanalyse --smart-profiling
        mv -v lib.tsv.speclib report.tsv.speclib
        """

    stub:
        """
        touch report.tsv.speclib report.tsv
        """
}


process BLIB_BUILD_LIBRARY {
    publishDir "${params.results_dir}/diann", failOnError: true, mode: 'copy'
    label 'process_medium'
    container 'quay.io/protio/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.23187-2243781'

    input:
        path speclib
        path precursor_tsv

    output:
        path('lib.blib'), emit: blib

    script:
        """
        cp "${speclib}" "/tmp/${speclib}"
        cp "${precursor_tsv}" "/tmp/${precursor_tsv}"

        wine BlibBuild.exe "/tmp/${speclib}" lib_redundant.blib
        wine BlibFilter.exe lib_redundant.blib lib.blib
        """

    stub:
        """
        touch lib.blib
        """
}

