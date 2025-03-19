
include { encyclopedia } from "../subworkflows/encyclopedia"
include { diann } from "../subworkflows/diann"
include { cascadia } from "../subworkflows/cascadia"

workflow dia_search{
    take:
        search_engine
        fasta
        spectral_library
        narrow_ms_file_tuple_ch
        wide_ms_file_tuple_ch

    main:

        // Variables which must be defined by earch search engine
        search_engine_version = null
        all_search_file_ch = null
        final_speclib = null
        search_file_stats = null
        search_fasta = null

        wide_ms_file_ch = wide_ms_file_tuple_ch.map{ it -> it[1] }
        narrow_ms_file_ch = narrow_ms_file_tuple_ch.map{ it -> it[1] }

        wide_ms_file_tuple_ch.concat(narrow_ms_file_tuple_ch)
            .map{ it -> it[0] }
            .unique()
            .collect()
            .tap{unique_file_type_ch}
            .subscribe{ file_types ->
                if(file_types.size() > 1)
                    error "Multiple file types detected: ${file_types}"
            }

        if(search_engine.toLowerCase() == 'encyclopedia') {

            unique_file_type_ch.subscribe{ file_types ->
                if(file_types[0] != 'mzML')
                    error "EncyclopeDIA only supports mzML files"
            }

            encyclopedia(fasta, spectral_library,
                         narrow_ms_file_ch, wide_ms_file_ch)

            search_engine_version = encyclopedia.out.encyclopedia_version
            search_file_stats = encyclopedia.out.search_file_stats
            final_speclib = encyclopedia.out.final_elib
            all_search_file_ch = encyclopedia.out.search_files
            search_fasta = fasta

        } else if(search_engine.toLowerCase() == 'diann') {
            supported_file_types = ['mzML', 'd.zip']
            unique_file_type_ch.subscribe{ file_types ->
                if(!file_types[0] in supported_file_types)
                    error "MS file type '${file_types[0]}' not DiaNN supported types (${supported_file_types.join(', ')})"
            }

            diann(fasta, spectral_library, wide_ms_file_tuple_ch)

            search_engine_version = diann.out.diann_version
            search_file_stats = diann.out.search_file_stats
            final_speclib = diann.out.final_speclib
            all_search_file_ch = diann.out.search_files
            search_fasta = fasta

        } else if(search_engine.toLowerCase() == 'cascadia') {

            unique_file_type_ch.subscribe{ file_types ->
                if(file_types[0] != 'mzML')
                    error "Cascadia only supports mzML files"
            }

            cascadia(wide_ms_file_ch)

            search_engine_version = cascadia.out.cascadia_version
            search_file_stats = cascadia.out.search_file_stats
            final_speclib = cascadia.out.final_speclib
            all_search_file_ch = cascadia.out.all_search_files
            search_fasta = cascadia.out.fasta

        } else {
            error "'${search_engine}' is an invalid argument for params.search_engine!"
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
        if(search_file_stats == null) {
            error "Search file stats not set!"
        }
        if(search_fasta == null) {
            error "Search file fasta not set!"
        }

    emit:
        search_engine_version
        all_search_files = all_search_file_ch
        search_file_stats
        final_speclib
        search_fasta
}