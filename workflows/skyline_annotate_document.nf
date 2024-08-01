// Modules
include { METADATA_TO_SKY_ANNOTATIONS } from "../modules/skyline"
include { SKYLINE_MINIMIZE_DOCUMENT } from "../modules/skyline"
include { SKYLINE_ANNOTATE_DOCUMENT } from "../modules/skyline"

workflow skyline_annotate_doc {
    take:
        skyline_input
        replicate_metadata

    emit:
        skyline_results
        skyline_hash

    main:
        METADATA_TO_SKY_ANNOTATIONS(replicate_metadata)

        if(params.skyline.minimize) {
            SKYLINE_MINIMIZE_DOCUMENT(skyline_input)
            annotate_sky_input = SKYLINE_MINIMIZE_DOCUMENT.out.final_skyline_zipfile
        } else {
            annotate_sky_input = skyline_input
        }

        SKYLINE_ANNOTATE_DOCUMENT(annotate_sky_input,
                                  METADATA_TO_SKY_ANNOTATIONS.out.annotation_csv,
                                  METADATA_TO_SKY_ANNOTATIONS.out.annotation_definitions)

        skyline_results = SKYLINE_ANNOTATE_DOCUMENT.out.final_skyline_zipfile
        skyline_hash = SKYLINE_ANNOTATE_DOCUMENT.out.file_hash
}
