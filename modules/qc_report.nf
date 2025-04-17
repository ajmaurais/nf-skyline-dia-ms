
def format_flag(var, flag) {
    def ret = (var == null ? "" : "${flag} ${var}")
    return ret
}

def format_flags(vars, flag) {
    if(vars instanceof List) {
        return (vars == null ? "" : "${flag} \'${vars.join('\' ' + flag + ' \'')}\'")
    }
    return format_flag(vars, flag)
}

process MAKE_EMPTY_FILE {
    container params.images.ubuntu
    label 'process_low'

    input:
        val file_name

    output:
        path("${file_name}")

    script:
    """
    touch ${file_name}
    """
}

process MERGE_REPORTS {
    publishDir params.output_directories.qc_report, failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        val study_names
        path replicate_reports
        path precursor_reports
        path replicate_metadata

    output:
        path('qc_report_data.db3'), emit: final_db
        path('dia_qc_version.txt'), emit: dia_qc_version
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        def metadata_arg = replicate_metadata.name == 'EMPTY' ? '' : "-m $replicate_metadata"

        """
        study_names_array=( '${study_names.join("' '")}' )
        replicate_reports_array=( '${replicate_reports.join("' '")}' )
        precursor_reports_array=( '${precursor_reports.join("' '")}' )

        for i in \${!study_names_array[@]} ; do
            echo "Working on \${study_names_array[\$i]}..."

            dia_qc parse --ofname qc_report_data.db3 --overwriteMode=append \
                --projectName="\${study_names_array[\$i]}" \
                ${metadata_arg} ${params.skyline.group_by_gene ? "--groupBy=gene" : ""} \
                "\${replicate_reports_array[\$i]}" \
                "\${precursor_reports_array[\$i]}" \
                > >(tee -a "merge_reports.stdout") 2> >(tee -a "merge_reports.stderr" >&2)

            echo "Done!"
        done

        # get dia_qc version and git info
        dia_qc --version|awk '{print \$3}'|xargs -0 printf 'dia_qc_version=%s' > dia_qc_version.txt
        echo "dia_qc_git_repo='\$GIT_REPO - \$GIT_BRANCH [\$GIT_SHORT_HASH]'" >> dia_qc_version.txt
        """

    stub:
    """
    touch merge_reports.stdout merge_reports.stderr qc_report_data.db3

    # get dia_qc version and git info
    dia_qc --version|awk '{print \$3}'|xargs -0 printf 'dia_qc_version=%s' > dia_qc_version.txt
    echo "dia_qc_git_repo='\$GIT_REPO - \$GIT_BRANCH [\$GIT_SHORT_HASH]'" >> dia_qc_version.txt
    """
}

process FILTER_IMPUTE_NORMALIZE {
    publishDir params.output_directories.qc_report, failOnError: true, mode: 'copy'
    stageInMode 'copy' // The input file is modified in place. Copying is necissary to avoid problems with caching.
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        path database

    output:
        path("${database.name}"), emit: final_db
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        """
        if ${params.qc_report.exclude_projects != null || params.qc_report.exclude_replicates != null ? 'true' : 'false'} ; then
            dia_qc filter \
            ${format_flags(params.qc_report.exclude_replicates, "--excludeRep")} \
            ${format_flags(params.qc_report.exclude_projects, "--excludeProject")} \
            ${database} \
            > >(tee "filter_db.stdout") 2> >(tee "filter_db.stderr" >&2)
        fi

        if ${params.qc_report.imputation_method == null ? 'false' : 'true'} ; then
            dia_qc impute -m=${params.qc_report.imputation_method} ${database} \
                > >(tee "impute_db.stdout") 2> >(tee "impute_db.stderr" >&2)
        fi

        if ${params.qc_report.normalization_method == null ? 'false' : 'true'} ; then
            dia_qc normalize -m=${params.qc_report.normalization_method} ${database} \
                > >(tee "normalize_db.stdout") 2> >(tee "normalize_db.stderr" >&2)
        fi
        """

    stub:
        """
        touch ${database} normalize_impute.stderr normalize_impute.stdout
        """
}

process GENERATE_QC_QMD {
    publishDir params.output_directories.qc_report, failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        val batch
        path database

    output:
        tuple val(batch), path('*.qmd'), emit: qc_report_qmd
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        """
        dia_qc qc_qmd ${format_flag(batch, '--project')} \
            --title "${batch == null ? '' : batch + ' '}DIA QC report" \
            ${format_flags(params.qc_report.standard_proteins, '--addStdProtein')} \
            ${format_flags(params.qc_report.color_vars, '--addColorVar')} \
            ${database} \
        > >(tee "make_qmd${batch == null ? '' : '.' + batch}.stdout") 2> >(tee "make_qmd${batch == null ? '' : '.' + batch}.stderr")
        """

    stub:
        """
        touch make_qmd.stdout make_qmd.stderr "${batch == null ? '' : batch + '_'}qc_report.qmd"
        """
}

process GENERATE_BATCH_REPORT {
    publishDir params.output_directories.batch_report, pattern: '*.rmd', failOnError: true, mode: 'copy'
    publishDir params.output_directories.batch_report_tables, pattern: '*.tsv', failOnError: true, mode: 'copy'
    publishDir params.output_directories.batch_report_plots, pattern: "plots/*.${params.batch_report.plot_ext}", failOnError: true, mode: 'copy'
    publishDir params.output_directories.batch_report, pattern: '*.std{err,out}', failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.batch_report

    input:
        path normalized_db

    output:
        path("bc_report.rmd"), emit: bc_rmd
        path("bc_report.html"), emit: bc_html
        path("*.tsv"), emit: tsv_reports, optional: true
        path("plots/*"), emit: bc_plots, optional: true
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        """
        dia_qc batch_rmd \
            ${format_flag(params.batch_report.method, "--bcMethod")} \
            ${format_flag(params.batch_report.batch1, "--batch1")} \
            ${format_flag(params.batch_report.batch2, "--batch2")} \
            ${format_flags(params.qc_report.color_vars, "--addColor")} \
            ${format_flag(params.batch_report.control_key, "--controlKey")} \
            ${format_flags(params.batch_report.control_values, "--addControlValue")} \
            ${format_flags(params.batch_report.covariate_vars, "--addCovariate")} \
            ${format_flag(params.batch_report.plot_ext, "--savePlots")} \
            --precursorTables 70 --proteinTables 70 \
            ${normalized_db} \
        > >(tee "generate_batch_rmd.stdout") 2> >(tee "generate_batch_rmd.stderr" >&2)

        mkdir plots
        Rscript -e "rmarkdown::render('bc_report.rmd')" \
            > >(tee -a "render_batch_rmd.stdout") 2> >(tee -a "render_batch_rmd.stderr" >&2)
        """

    stub:
        """
        touch bc_report.rmd bc_report.html
        touch generate_batch_rmd.stdout generate_batch_rmd.stderr
        """
}

process EXPORT_TABLES {
    publishDir params.output_directories.qc_report_tables, pattern: '*.tsv', failOnError: true, mode: 'copy'
    publishDir params.output_directories.qc_report, pattern: '*.stdout', failOnError: true, mode: 'copy'
    publishDir params.output_directories.qc_report, pattern: '*.stderr', failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        path precursor_db

    output:
        path('*.tsv'), emit: tables
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    dia_qc db_export --precursorTables=30 --proteinTables=30 ${precursor_db} \
        > >(tee "export_tables.stdout") 2> >(tee "export_tables.stderr")
    """

    stub:
    """
    touch export_tables.stdout export_tables.stderr stub.tsv
    """
}

process RENDER_QC_REPORT {
    publishDir params.output_directories.qc_report, pattern: "*.${report_format}", failOnError: true, mode: 'copy'
    publishDir params.output_directories.qc_report, pattern: '*.stdout', failOnError: true, mode: 'copy'
    publishDir params.output_directories.qc_report, pattern: '*.stderr', failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        tuple val(batch), path(qmd), val(report_format)
        path database

    output:
        path("${qmd.baseName}.${report_format}"), emit: qc_report
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        def batch_str = (batch == null ? '' : "${batch}_")
        """
        quarto render ${qmd} --to '${report_format}' \
            > >(tee "render_${batch_str}${report_format}_qc_report.stdout") 2> >(tee "render_${batch_str}${report_format}_report.stderr")
        """

    stub:
        """
        touch "${qmd.name}.${report_format}"
        touch stub.stdout stub.stderr
        """
}

process EXPORT_GENE_REPORTS {
    publishDir params.output_directories.gene_reports, failOnError: true, mode: 'copy'
    label 'process_high_memory'
    container params.images.qc_pipeline

    input:
        path batch_db
        path gene_level_data
        val file_prefix

    output:
        path("*.tsv"), emit: gene_reports
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        """
        dia_qc export_gene_matrix --prefix=${file_prefix} --useAliquotId \
            '${gene_level_data}' '${batch_db}'  \
            > >(tee "export_reports.stdout") 2> >(tee "export_reports.stderr" >&2)
        """

    stub:
        """
        touch stub.tsv
        touch stub.stdout stub.stderr
        """
}
