
process GENERATE_DIA_QC_REPORT_DB {
    publishDir "${params.result_dir}/qc_report", pattern: '*.db3', failOnError: true, mode: 'copy'
    publishDir "${params.result_dir}/qc_report", pattern: '*.qmd', failOnError: true, mode: 'copy'
    publishDir "${params.result_dir}/qc_report", pattern: '*.stdout', failOnError: true, mode: 'copy'
    publishDir "${params.result_dir}/qc_report", pattern: '*.stderr', failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container 'mauraisa/dia_qc_report:1.1'
    
    input:
        path replicate_report
        path precursor_report
        val standard_proteins
        val qc_report_title

    output:
        path('qc_report_data.db3'), emit: qc_report_db
        path('qc_report.qmd'), emit: qc_report_qmd

    script:
        standard_proteins_args = "--addStdProtein ${(standard_proteins as List).collect{it}.join(' --addStdProtein ')}"
        """
        parse_data --ofname qc_report_data.db3 '${replicate_report}' '${precursor_report}' \
            > >(tee "parse_data.stdout") 2> >(tee "parse_data.stderr")

        generate_qc_qmd ${standard_proteins_args} --title '${qc_report_title}' qc_report_data.db3 \
            > >(tee "make_qmd.stdout") 2> >(tee "make_qmd.stderr")
        """
}

process RENDER_QC_REPORT {
    publishDir "${params.result_dir}/qc_report", pattern: 'qc_report.*', failOnError: true, mode: 'copy'
    publishDir "${params.result_dir}/qc_report", pattern: '*.stdout', failOnError: true, mode: 'copy'
    publishDir "${params.result_dir}/qc_report", pattern: '*.stderr', failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container 'mauraisa/dia_qc_report:1.1'
    
    input:
        path qmd
        path database
        val report_format

    output:
        path("qc_report.${format}"), emit: qc_report

    script:
        format = report_format
        """
        quarto render qc_report.qmd --to '${format}' \
            > >(tee "render_${report_format}_report.stdout") 2> >(tee "render_${report_format}_report.stderr")
        """
    
    stub:
        """
        touch "qc_report.${format}"
        """
}

