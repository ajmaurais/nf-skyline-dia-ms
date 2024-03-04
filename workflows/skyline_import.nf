// Modules
include { SKYLINE_ADD_LIB } from "../modules/skyline"
include { SKYLINE_IMPORT_MZML } from "../modules/skyline"
include { SKYLINE_MERGE_RESULTS } from "../modules/skyline"
include { ANNOTATION_TSV_TO_CSV } from "../modules/skyline"
include { SKYLINE_ANNOTATE_DOCUMENT } from "../modules/skyline"

workflow skyline_import {

    take:
        skyline_template_zipfile
        fasta
        elib
        wide_mzml_file_ch

    emit:
        skyline_results

    main:

        // add library to skyline file
        SKYLINE_ADD_LIB(skyline_template_zipfile, fasta, elib)
        skyline_zipfile = SKYLINE_ADD_LIB.out.skyline_zipfile

        // import spectra into skyline file
        SKYLINE_IMPORT_MZML(skyline_zipfile, wide_mzml_file_ch)

        // merge sky files
        SKYLINE_MERGE_RESULTS(
            skyline_zipfile,
            SKYLINE_IMPORT_MZML.out.skyd_file.collect(),
            wide_mzml_file_ch.collect(),
            params.final_skyline_doc_name,
            fasta
        )

        annotation_csv = null
        if(params.skyline.annotation_tsv != null) {
            ANNOTATION_TSV_TO_CSV(params.skyline.annotation_tsv)
            annotation_csv = ANNOTATION_TSV_TO_CSV.out.annotation_csv
        }
        else if (params.skyline.annotation_csv != null) {
            annotation_csv = params.skyline.annotation_csv
        }

        if(annotation_csv != null) {
            SKYLINE_ANNOTATE_DOCUMENT(SKYLINE_MERGE_RESULTS.out.final_skyline_zipfile,
                                      annotation_csv,
                                      ANNOTATION_TSV_TO_CSV.out.annotation_definitions,
                                      params.final_skyline_doc_name)
            skyline_results = SKYLINE_ANNOTATE_DOCUMENT.out.sky_zip_file
        } else {
            skyline_results = SKYLINE_MERGE_RESULTS.out.final_skyline_zipfile
        }
}

