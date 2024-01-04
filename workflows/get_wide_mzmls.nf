// modules
include { PANORAMA_GET_RAW_FILE } from "../modules/panorama"
include { PANORAMA_GET_RAW_FILE_LIST } from "../modules/panorama"
include { MSCONVERT } from "../modules/msconvert"

workflow get_wide_mzmls {

   emit:
       wide_mzml_ch

    main:

        if(params.quant_spectra_dir.contains("https://")) {

            spectra_dirs_ch = Channel.from(params.quant_spectra_dir)
                                    .splitText()               // split multiline input
                                    .map{ it.trim() }          // removing surrounding whitespace
                                    .filter{ it.length() > 0 } // skip empty lines

            // get raw files from panorama
            PANORAMA_GET_RAW_FILE_LIST(spectra_dirs_ch, params.quant_spectra_glob, params.ms_file_ext)

            placeholder_ch = PANORAMA_GET_RAW_FILE_LIST.out.raw_file_placeholders.transpose()
            PANORAMA_GET_RAW_FILE(placeholder_ch)
            
            if(params.ms_file_ext == 'mzML' || params.ms_file_ext == 'd') {
                wide_mzml_ch = PANORAMA_GET_RAW_FILE.out.panorama_file
                return
            }
            if (params.ms_file_ext == 'raw') {
                wide_mzml_ch = MSCONVERT(
                    PANORAMA_GET_RAW_FILE.out.panorama_file,
                    params.msconvert.do_demultiplex,
                    params.msconvert.do_simasspectra
                )
                return
            }

        } else {

            file_glob = params.quant_spectra_glob
            spectra_dir = file(params.quant_spectra_dir, checkIfExists: true)
            data_files = file("$spectra_dir/${file_glob}")

            println(data_files)

            if(data_files.size() < 1) {
                error "No files found for: $spectra_dir/${file_glob}"
            }

            mzml_files = data_files.findAll { it.name.endsWith('.mzML') }
            raw_files = data_files.findAll { it.name.endsWith('.raw') }
            bruker_files = data_files.findAll { it.name.endsWith('.d') }

            file_types_found = [mzml_files.size(), raw_files.size(), bruker_files.size()].collect{it > 0 ? 1 : 0}.sum()

            if(file_types_found == 0) {
                error "No raw, mzML, or d files found in: $spectra_dir"
            }

            if(file_types_found > 1) {
                error "Matched multiple file types for: $spectra_dir/${file_glob}. Please choose a file matching string that will only match one or the other."
            }

            if(mzml_files.size() > 0) {
                wide_mzml_ch = Channel.fromList(mzml_files)
            }
            else if(bruker_files.size() > 0) {
                wide_mzml_ch = Channel.fromList(bruker_files) 
            } else {
                wide_mzml_ch = MSCONVERT(
                    Channel.fromList(raw_files),
                    params.msconvert.do_demultiplex,
                    params.msconvert.do_simasspectra
                )
            }
        }
}
