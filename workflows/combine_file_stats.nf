// Modules
include { CALCULATE_FILE_STATS as QC_FILE_STATS } from "../modules/s3"
include { CALCULATE_FILE_STATS as GENE_REPORT_STATS } from "../modules/s3"
include { CALCULATE_FILE_STATS as WORKFLOW_VERSIONS_STATS } from "../modules/s3"
include { CALCULATE_FILE_STATS as SPECLIB_FILE_STATS } from "../modules/s3"
include { CALCULATE_FILE_STATS as FASTA_FILE_STATS } from "../modules/s3"
include { GZIP_FILE as GZIP_MZML } from "../modules/s3"
include { WRITE_FILE_STATS } from "../modules/s3"

workflow combine_file_stats {

    take:
        // search files
        fasta
        spectral_library

        // mzml files
        mzml_files
        mzml_hashes

        // ENCYCLOPEDIA_SEARCH_FILE artifacts
        // encyclopedia_search_files
        // encyclopedia_file_hashes

        // // ENCYCLOPEDIA_CREATE_ELIB
        // quant_elib
        // quant_elib_hash

        // Skyline files
        final_skyline_file
        final_skyline_hash

        // Reports
        qc_reports

        // gene and precursor matrices
        gene_reports

        // workflow versions
        workflow_versions

    emit:
        file_hashes
        // gziped_mzml_files

    main:

        //s3_directory = "/${params.s3_upload.prefix_dir == null ? '' : params.s3_upload.prefix_dir + '/'}${params.pdc.study_id}"

        // GZIP_MZML(mzml_files)
        QC_FILE_STATS(qc_reports)
        GENE_REPORT_STATS(gene_reports)
        WORKFLOW_VERSIONS_STATS(workflow_versions)
        FASTA_FILE_STATS(fasta)
        SPECLIB_FILE_STATS(spectral_library)

        // file_stats = GZIP_MZML.out.map{
        //     it -> tuple(it[0], "/mzml", it[2], it[0].size())
        // }.concat(
        //      encyclopedia_file_hashes.map{
        //         it -> it.readLines()
        //     }.flatten().map{
        //         it -> elems = it.split(); return tuple(elems[1], elems[0])
        //     }.join(
        //         encyclopedia_search_files.map{ it -> tuple(it.name, it.size()) }
        //     ).map{
        //         it -> tuple(it[0], "encyclopedia/search_file", it[1], it[2])
        //     }
        // ).concat(
        //     quant_elib.map{
        //         it -> tuple(it.name, it.size())
        //     }.combine(quant_elib_hash).map{
        //         it -> tuple(it[0], "encyclopedia/create_elib", it[2], it[1])
        //     }.concat(
        //         final_skyline_file.map{
        //             it -> tuple(it.name, it.size())
        //         }.combine(quant_elib_hash).map{
        //             it -> tuple(it[0], "skyline", it[2], it[1])
        //         })
        // ).concat(
        
        mzml_stats = mzml_files.map{
                it -> tuple(it.name, "", it.size())
            }.join(mzml_hashes)
        // mzml_stats.view()
        
        skyline_stats = final_skyline_file.map{
                it-> tuple(it.name, it.size())
            }.combine(final_skyline_hash).map{
                it -> tuple(it[0], "${params.result_dir}/skyline", it[2], it[1])
            }
        // skyline_stats.view()

        // encyclopedia_stats = quant_elib.map{
        //         it-> tuple(it.name, it.size())
        //     }.combine(quant_elib_hash).map{
        //         it -> tuple(it[0], "${params.result_dir}/encyclopedia/create-elib", it[2], it[1])
        //     }
        // encyclopedia_stats.view()

        file_stats = qc_reports.map{
                it -> tuple(it.name, "qc_reports", it.size())
            }.concat(
                gene_reports.map{it -> tuple(it.name, "${params.result_dir}/gene_reports", it.size()) },
                spectral_library.map{it -> tuple(it.name, "${params.result_dir}", it.size()) },
                workflow_versions.map{it -> tuple(it.name, "${params.result_dir}/qc_reports", it.size()) }
                
            ).join(QC_FILE_STATS.out.concat(GENE_REPORT_STATS.out,
                                            WORKFLOW_VERSIONS_STATS.out,
                                            FASTA_FILE_STATS.out,
                                            SPECLIB_FILE_STATS.out)).map{
                it -> tuple(it[0], it[1], it[3], it[2])
            }
        //)
        
        file_stats = file_stats.concat(
            mzml_stats,
            skyline_stats
        )
        file_stats.view()

        file_paths = file_stats.map{ it[1] }
        file_names = file_stats.map{ it[0] }
        file_hashes = file_stats.map{ it[2] }
        file_sizes = file_stats.map{ it[3] }
        WRITE_FILE_STATS(file_paths.collect(), file_names.collect(),
                         file_hashes.collect(), file_sizes.collect())

        file_hashes = WRITE_FILE_STATS.out
        // gziped_mzml_files = GZIP_MZML.out.map{ it -> it[1] }
}

