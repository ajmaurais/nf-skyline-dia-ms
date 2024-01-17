// modules
include { PANORAMA_GET_RAW_FILE } from "../modules/panorama"
include { PANORAMA_GET_RAW_FILE_LIST } from "../modules/panorama"
include { MSCONVERT } from "../modules/msconvert"
include { ADJUST_MZMLS } from "../modules/msconvert"

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
            
            if(params.ms_file_ext == 'mzML') {
                wide_mzml_ch_unadjusted = PANORAMA_GET_RAW_FILE.out.panorama_file
            }
            if (params.ms_file_ext == 'raw') {
                wide_mzml_ch_unadjusted = MSCONVERT(
                    PANORAMA_GET_RAW_FILE.out.panorama_file,
                    params.msconvert.do_demultiplex,
                    params.msconvert.do_simasspectra
                )
            }

        } else {

            file_glob = params.quant_spectra_glob
            spectra_dir = file(params.quant_spectra_dir, checkIfExists: true)
            data_files = file("$spectra_dir/${file_glob}")

            if(data_files.size() < 1) {
                error "No files found for: $spectra_dir/${file_glob}"
            }

            mzml_files = data_files.findAll { it.name.endsWith('.mzML') }
            raw_files = data_files.findAll { it.name.endsWith('.raw') }

            if(mzml_files.size() < 1 && raw_files.size() < 1) {
                error "No raw or mzML files found in: $spectra_dir"
            }

            if(mzml_files.size() > 0 && raw_files.size() > 0) {
                error "Matched raw files and mzML files for: $spectra_dir/${file_glob}. Please choose a file matching string that will only match one or the other."
            }

            if(mzml_files.size() > 0) {
                wide_mzml_ch_unadjusted = Channel.fromList(mzml_files)
            } else {
                wide_mzml_ch_unadjusted = MSCONVERT(
                    Channel.fromList(raw_files),
                    params.msconvert.do_demultiplex,
                    params.msconvert.do_simasspectra
                )
            }
        }

        if(params.adjust_ms_file_mzs_ppm != null){
            ADJUST_MZMLS(params.adjust_ms_file_mzs_ppm, wide_mzml_ch_unadjusted)
            wide_mzml_ch = ADJUST_MZMLS.out.adjusted_mzmls
        } else {
            wide_mzml_ch = wide_mzml_ch_unadjusted
        }
}
