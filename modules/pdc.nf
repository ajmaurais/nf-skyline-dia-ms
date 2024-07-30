
PDC_CLIENT_VERSION = '0.15'

process GET_DOCKER_INFO {
    publishDir "${params.result_dir}/pdc", failOnError: true, mode: 'copy'
    label 'process_low'
    container "quay.io/mauraisa/pdc_client:${PDC_CLIENT_VERSION}"

    output:
        path('pdc_versions.txt'), emit: info_file

    shell:
        '''
        echo -e "GIT_HASH=${GIT_HASH}" > pdc_versions.txt
        echo -e "GIT_BRANCH=${GIT_BRANCH}" >> pdc_versions.txt
        echo -e "GIT_REPO=${GIT_REPO}" >> pdc_versions.txt
        echo -e "GIT_SHORT_HASH=${GIT_SHORT_HASH}" >> pdc_versions.txt
        echo -e "GIT_UNCOMMITTED_CHANGES=${GIT_UNCOMMITTED_CHANGES}" >> pdc_versions.txt
        echo -e "GIT_LAST_COMMIT=${GIT_LAST_COMMIT}" >> pdc_versions.txt
        echo -e "DOCKER_IMAGE=${DOCKER_IMAGE}" >> pdc_versions.txt
        echo -e "DOCKER_TAG=${DOCKER_TAG}" >> pdc_versions.txt
        '''
}

process GET_STUDY_METADATA {
    publishDir "${params.result_dir}/pdc/study_metadata", failOnError: true, mode: 'copy'
    errorStrategy 'retry'
    maxRetries 5
    label 'process_low_constant'
    container "quay.io/mauraisa/pdc_client:${PDC_CLIENT_VERSION}"

    input:
        val pdc_study_id

    output:
        path('study_metadata.tsv'), emit: metadata
        path('study_metadata_annotations.csv'), emit: skyline_annotations
        env(study_id), emit: study_id
        env(study_name), emit: study_name

    shell:
    n_files_arg = params.pdc.n_raw_files == null ? "" : "--nFiles ${params.pdc.n_raw_files}"
    '''
    study_id=$(PDC_client studyID !{params.pdc.client_args} !{pdc_study_id} |tee study_id.txt)
    study_name=$(PDC_client studyName --normalize !{params.pdc.client_args} $study_id |tee study_name.txt)
    PDC_client metadata !{params.pdc.client_args} -f tsv !{n_files_arg} --skylineAnnotations ${study_id}
    '''
}

process METADATA_TO_SKY_ANNOTATIONS {
    label 'process_low_constant'
    container "quay.io/mauraisa/pdc_client:${PDC_CLIENT_VERSION}"

    input:
        path pdc_study_metadata

    output:
        path('skyline_annotations.csv'), emit: skyline_annotations

    shell:
    '''
    PDC_client metadataToSky !{pdc_study_metadata}
    '''
}

process GET_FILE {
    label 'process_low_constant'
    container "quay.io/mauraisa/pdc_client:${PDC_CLIENT_VERSION}"
    errorStrategy 'retry'
    maxRetries 1
    storeDir "${params.panorama_cache_directory}"

    input:
        tuple val(url), val(file_name), val(md5)

    output:
        path(file_name), emit: downloaded_file

    shell:
    '''
    PDC_client file -o '!{file_name}' -m '!{md5}' '!{url}'
    '''

    stub:
    """
    touch ${file_name}
    """
}
