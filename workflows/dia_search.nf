
include { encyclopedia } from "../subworkflows/encyclopedia"
include { diann_search } from "../subworkflows/diann_search"
include { cascadia_search } from "../subworkflows/cascadia_search"

workflow dia_search{
    take:
        search_engine
        fasta
        spectral_library
        narrow_mzml_ch
        wide_mzml_ch

    main:

        // Variables which must be defined by earch search engine
        search_engine_version = null
        all_search_file_ch = null
        final_speclib = null

        if(params.search_engine.toLowerCase() == 'encyclopedia') {

            all_diann_file_ch = Channel.empty()  // will be no diann
            all_cascadia_file_ch = Channel.empty()

            encyclopedia(fasta, spectral_library,
                        narrow_mzml_ch, wide_mzml_ch)

            search_engine_version = encyclopedia.out.version
            search_file_stats = encyclopedia.out.search_file_stats

            final_speclib = encyclopedia.out.final_elib
            all_elib_ch = encyclopedia.out.all_elib_ch

        } else if(params.search_engine.toLowerCase() == 'diann') {

            if(!params.fasta) {
                error "The parameter \'fasta\' is required when using diann."
            }

            if (params.chromatogram_library_spectra_dir != null) {
                log.warn "The parameter 'chromatogram_library_spectra_dir' is set to a value (${params.chromatogram_library_spectra_dir}) but will be ignored."
            }

            if (params.encyclopedia.quant.params != null) {
                log.warn "The parameter 'encyclopedia.quant.params' is set to a value (${params.encyclopedia.quant.params}) but will be ignored."
            }

            if (params.encyclopedia.chromatogram.params != null) {
                log.warn "The parameter 'encyclopedia.chromatogram.params' is set to a value (${params.encyclopedia.chromatogram.params}) but will be ignored."
            }

            if(params.spectral_library) {

                // convert spectral library to required format for dia-nn
                if(params.spectral_library.endsWith(".blib")) {
                    ENCYCLOPEDIA_BLIB_TO_DLIB(
                        fasta,
                        spectral_library
                    )

                    ENCYCLOPEDIA_DLIB_TO_TSV(
                        ENCYCLOPEDIA_BLIB_TO_DLIB.out.dlib
                    )

                    spectral_library_to_use = ENCYCLOPEDIA_DLIB_TO_TSV.out.tsv

                } else if(params.spectral_library.endsWith(".dlib")) {
                    ENCYCLOPEDIA_DLIB_TO_TSV(
                        spectral_library
                    )

                    spectral_library_to_use = ENCYCLOPEDIA_DLIB_TO_TSV.out.tsv

                } else {
                    spectral_library_to_use = spectral_library
                }
            } else {
                // no spectral library
                spectral_library_to_use = Channel.empty()
            }


            all_elib_ch = Channel.empty()  // will be no encyclopedia
            all_cascadia_file_ch = Channel.empty()

            all_mzml_ch = wide_mzml_ch

            diann_search(
                wide_mzml_ch,
                fasta,
                spectral_library_to_use
            )

            search_engine_version = diann_search.out.diann_version
            search_file_stats = diann_search.out.output_file_stats

            // create compatible spectral library for Skyline, if needed
            if(!params.skyline.skip) {
                BLIB_BUILD_LIBRARY(diann_search.out.speclib,
                                diann_search.out.precursor_tsv)

                final_speclib = BLIB_BUILD_LIBRARY.out.blib
            } else {
                final_speclib = Channel.empty()
            }

            // all files to upload to panoramaweb (if requested)
            all_diann_file_ch = diann_search.out.speclib.concat(
                diann_search.out.precursor_tsv
            ).concat(
                diann_search.out.quant_files.flatten()
            ).concat(
                final_speclib
            ).concat(
                diann_search.out.stdout
            ).concat(
                diann_search.out.stderr
            ).concat(
                diann_search.out.predicted_speclib
            )
        } else if(params.search_engine.toLowerCase() == 'cascadia') {

            if (params.spectral_library != null) {
                log.warn "The parameter 'spectral_library' is set to a value (${params.spectral_library}) but will be ignored."
            }

            all_elib_ch = Channel.empty()  // will be no encyclopedia
            all_diann_file_ch = Channel.empty() // will be no diann

            all_mzml_ch = wide_mzml_ch

            cascadia_search(
                wide_mzml_ch
            )

            search_engine_version = cascadia_search.out.cascadia_version
            search_file_stats = cascadia_search.out.output_file_stats
            final_speclib = cascadia_search.out.blib
            fasta = cascadia_search.out.fasta

            // all files to upload to panoramaweb (if requested)
            all_cascadia_file_ch = cascadia_search.out.blib.concat(
                cascadia_search.out.fasta
            ).concat(
                cascadia_search.out.stdout
            ).concat(
                cascadia_search.out.stderr
            )

        } else {
            error "'${params.search_engine}' is an invalid argument for params.search_engine!"
        }

        // Check that all required variables were defined
        if(search_engine_version == null) {
            error "Search engine version not set!"
        }
        if(all_search_file_ch == null) {
            error "Search engine file Channel not set!"
        }
        if(final_speclib == null) {
            error "Final spectral library not set!"
        }

    emit:
        search_engine = params.search_engine
        search_engine_version
        all_search_files = all_search_file_ch
        final_speclib
}