
def round_bytes(bytes) {
    // Breaks for memory allocation intervals in GB
    breaks = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]

    size_gb = breaks.find{ it -> return(((it - 0.5) * (1024L ** 3)) > bytes) }
    if (size_gb == null) {
        error 'File size too large to allocate memory for process!'
    }
    return "${size_gb} GB"
}

process GET_DOCKER_INFO {
    publishDir "${params.result_dir}/s3", failOnError: true, mode: 'copy'
    label 'process_low'
    container 'quay.io/mauraisa/s3_client:0.9'

    output:
        path('s3_client_versions.txt'), emit: info_file

    shell:
        '''
        echo -e "GIT_HASH=${GIT_HASH}" > s3_client_versions.txt
        echo -e "GIT_BRANCH=${GIT_BRANCH}" >> s3_client_versions.txt
        echo -e "GIT_REPO=${GIT_REPO}" >> s3_client_versions.txt
        echo -e "GIT_SHORT_HASH=${GIT_SHORT_HASH}" >> s3_client_versions.txt
        echo -e "GIT_UNCOMMITTED_CHANGES=${GIT_UNCOMMITTED_CHANGES}" >> s3_client_versions.txt
        echo -e "GIT_LAST_COMMIT=${GIT_LAST_COMMIT}" >> s3_client_versions.txt
        echo -e "DOCKER_IMAGE=${DOCKER_IMAGE}" >> s3_client_versions.txt
        echo -e "DOCKER_TAG=${DOCKER_TAG}" >> s3_client_versions.txt
        '''
}

process UPLOAD_FILE {
    container 'quay.io/mauraisa/s3_client:0.9'
    label 'error_retry'
    publishDir "${params.result_dir}/s3", failOnError: true, mode: 'copy'
    memory { round_bytes(file_to_upload.size()) }
    cpus 2
    time '8 h'

    input:
        val bucket_name
        val access_key
        val destination_path
        path file_to_upload

    output:
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    shell:
        '''
        s3_client -b "!{bucket_name}" \
            -k "!{access_key}" \
            -s ${S3_SECRET_ACCESS_KEY} \
            put "!{file_to_upload}" "!{destination_path}" \
            > >(tee 's3_upload_file-!{file_to_upload.baseName}.stdout') \
              2> >(tee 's3_upload_file-!{file_to_upload.baseName}.stderr' >&2)
        '''

    // stub:
    // """
    // touch stub.stdout stub.stderr
    // """
}

process GZIP_FILE {
    label 'process_medium'
    // label 'error_retry'
    memory { round_bytes(file_to_upload.size()) }
    cpus 1
    time '1 h'
    container "${workflow.profile == 'aws' ? 'public.ecr.aws/docker/library/ubuntu:22.04' : 'ubuntu:22.04'}"

    input:
        path(unziped_file)

    output:
        tuple val("${unziped_file.baseName}"), path("${unziped_file.baseName}.mzML.gz"), env(md5_sum)

    shell:
        '''
        cp !{unziped_file} /tmp
        pushd /tmp
        gzip "!{unziped_file.baseName}.mzML"
        popd
        cp -v "/tmp/!{unziped_file.baseName}.mzML.gz" .
        md5_sum=$( md5sum "!{unziped_file.baseName}.mzML.gz" |awk '{print $1}' )
        '''
}

process CALCULATE_FILE_STATS {
    label 'process_low'
    label 'error_retry'
    memory { round_bytes(file_to_upload.size()) }
    cpus 1
    time '1 h'
    container "${workflow.profile == 'aws' ? 'public.ecr.aws/docker/library/ubuntu:22.04' : 'ubuntu:22.04'}"

    input:
        path(file_to_check)

    output:
        tuple val("${file_to_check.name}"), env(md5_sum)

    shell:
        '''
        md5_sum=$( md5sum !{file_to_check} |awk '{print $1}' )
        '''
}

process WRITE_FILE_STATS {
    label 'process_low'
    label 'error_retry'
    container "${workflow.profile == 'aws' ? 'public.ecr.aws/docker/library/python:3.13.0a4' : 'python:3.13.0a4'}"
    publishDir "${params.result_dir}/s3", failOnError: true, mode: 'copy'

    input:
        val paths
        val fnames
        val md5_sums
        val file_sizes

    output:
        path("file_checksums.tsv")

    script:
        """
        #!/usr/bin/env python3

        file_paths = [ '${paths.join("', '")}' ]
        file_names = [ '${fnames.join("', '")}' ]
        hashes = [ '${md5_sums.join("', '")}' ]
        file_sizes = [ '${file_sizes.join("', '")}' ]

        with open('file_checksums.tsv', 'w') as outF:
            outF.write('s3_path\\tfile\\tsize\\tmd5_sum\\n')
            for path, name, f_size, md5 in zip(file_paths, file_names, file_sizes, hashes):
                outF.write(f'{path}\\t{name}\\t{f_size}\\t{md5}\\n')
        """
}

process UPLOAD_MANY_FILES {
    label 'process_high_memory'
    label 'error_retry'
    container 'quay.io/mauraisa/s3_client:0.9'
    // publishDir "${params.result_dir}/s3", failOnError: true, mode: 'copy'

    input:
        val bucket_name
        val access_key
        val destination_path
        path files_to_upload

    output:
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    shell:
        files = "${(files_to_upload as List).collect{ file(it).name }.join(' ')}"
        '''
        echo !{files}
        s3_client -b "!{bucket_name}" \
            -k "!{access_key}" \
            -s ${S3_SECRET_ACCESS_KEY} \
            put !{files} \
            "!{destination_path}"
            > >(tee 's3_upload_file.stdout') 2> >(tee 's3_upload_file.stderr' >&2)
        '''

    stub:
    """
    touch stub.stdout stub.stderr
    """
}

