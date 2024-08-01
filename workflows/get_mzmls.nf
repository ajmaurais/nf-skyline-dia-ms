import java.security.MessageDigest
import groovy.io.FileType

// modules
include { PANORAMA_GET_RAW_FILE } from "../modules/panorama"
include { PANORAMA_GET_RAW_FILE_LIST } from "../modules/panorama"
include { MSCONVERT } from "../modules/msconvert"

// Calculate MD5 hash of file
def computeMd5(file) {
    MessageDigest md = MessageDigest.getInstance("MD5")
    file.withInputStream { stream ->
        byte[] buffer = new byte[8192]
        int bytesRead
        while ((bytesRead = stream.read(buffer)) != -1) {
            md.update(buffer, 0, bytesRead)
        }
    }
    byte[] digest = md.digest()
    return digest.collect { String.format("%02x", it) }.join('')
}

workflow get_mzmls {
    take:
        spectra_dir
        spectra_glob

    emit:
        mzml_ch
        // zipped_mzml_ch
        file_hash_ch

    main:

        if(spectra_dir.contains("https://")) {

            spectra_dirs_ch = Channel.from(spectra_dir)
                                    .splitText()               // split multiline input
                                    .map{ it.trim() }          // removing surrounding whitespace
                                    .filter{ it.length() > 0 } // skip empty lines

            // get raw files from panorama
            PANORAMA_GET_RAW_FILE_LIST(spectra_dirs_ch, spectra_glob)

            placeholder_ch = PANORAMA_GET_RAW_FILE_LIST.out.raw_file_placeholders.transpose()
            PANORAMA_GET_RAW_FILE(placeholder_ch)

            mzml_ch = MSCONVERT(
                PANORAMA_GET_RAW_FILE.out.panorama_file,
                params.msconvert.do_demultiplex,
                params.msconvert.do_simasspectra
            )

        } else {

            file_glob = spectra_glob
            spectra_dir = file(spectra_dir, checkIfExists: true)
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
                mzml_ch = Channel.fromList(mzml_files)
                file_hash_ch = mzml_ch.map { file ->
                    def md5 = computeMd5(file)
                    return [file: file, md5: md5]
                }
        
            } else {
                mzml_ch = MSCONVERT(
                    Channel.fromList(raw_files),
                    params.msconvert.do_demultiplex,
                    params.msconvert.do_simasspectra
                )
            }
        }

        MSCONVERT.out.file_hash.splitText().map{
            it -> elems = it.split();
            return tuple(elems[1], elems[0])
        }.set(file_hash_ch)
}
