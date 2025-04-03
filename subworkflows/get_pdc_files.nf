
include { GET_STUDY_METADATA } from "../modules/pdc.nf"
include { METADATA_TO_SKY_ANNOTATIONS } from "../modules/pdc.nf"
include { GET_FILE } from "../modules/pdc.nf"
include { MSCONVERT } from "../modules/msconvert.nf"
include { UNZIP_DIRECTORY as UNZIP_BRUKER_D } from "../modules/msconvert.nf"

workflow get_pdc_study_metadata {
    main:
        if(params.pdc.metadata_tsv == null) {
            GET_STUDY_METADATA(params.pdc.study_id)
            metadata = GET_STUDY_METADATA.out.metadata
            annotations_csv = GET_STUDY_METADATA.out.skyline_annotations
            study_name = GET_STUDY_METADATA.out.study_name
        } else {
            metadata = Channel.fromPath(file(params.pdc.metadata_tsv, checkIfExists: true))
            METADATA_TO_SKY_ANNOTATIONS(metadata)
            annotations_csv = METADATA_TO_SKY_ANNOTATIONS.out
            study_name = params.pdc.study_name
        }

    emit:
        study_name
        metadata
        annotations_csv
}

workflow get_pdc_files {
    main:
        get_pdc_study_metadata()
        metadata = get_pdc_study_metadata.out.metadata

        metadata \
            | splitJson() \
            | map{row -> tuple(row['url'], row['file_name'], row['md5sum'], row['file_size'])} \
            | GET_FILE

        split_ms_file_ch = GET_FILE.out.downloaded_file
            .branch{ raw:   it.name.endsWith('.raw')
                     d_zip: it.name.endsWith('.d.zip')
                     other: true
                        error "Unknown file type: " + it.name
            }

        MSCONVERT(split_ms_file_ch.raw)
        UNZIP_BRUKER_D(split_ms_file_ch.d_zip)

    emit:
        study_name = get_pdc_study_metadata.out.study_name
        metadata
        annotations_csv = get_pdc_study_metadata.out.annotations_csv
        ms_file_ch = MSCONVERT.out.concat(UNZIP_BRUKER_D.out)
}
