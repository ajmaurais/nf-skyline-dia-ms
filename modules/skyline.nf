def check_max_mem(obj) {
    try {
        if (obj.compareTo(params.max_memory as nextflow.util.MemoryUnit) == 1)
            return (params.max_memory as nextflow.util.MemoryUnit) - 1.Gb
        else
            return obj
    } catch (all) {
        println "   ### ERROR ###   Max memory '${params.max_memory}' is not valid! Using default value: $obj"
        return obj
    }
}

process SKYLINE_ADD_LIB {
    publishDir "${params.result_dir}/skyline/add-lib", failOnError: true, mode: 'copy', enabled: params.skyline.save_intermediate_output
    label 'process_medium'
    label 'process_short'
    label 'error_retry'
    container "proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.24054-2352758"

    input:
        path skyline_template_zipfile
        path fasta
        path elib

    output:
        path("results.sky.zip"), emit: skyline_zipfile
        path("skyline_add_library.log"), emit: log

    script:
    """
    unzip ${skyline_template_zipfile}

    wine SkylineCmd \
        --in="${skyline_template_zipfile.baseName}" \
        --log-file=skyline_add_library.log \
        --import-fasta="${fasta}" \
        --add-library-path="${elib}" \
        --out="results.sky" \
        --save \
        --share-zip="results.sky.zip" \
        --share-type="complete"
    """
}

process SKYLINE_IMPORT_MZML {
    publishDir "${params.result_dir}/skyline/import-spectra", failOnError: true, mode: 'copy', enabled: params.skyline.save_intermediate_output
    label 'process_medium'
    // memory 30.GB
    // cpus 4
    // time 8.h
    label 'error_retry'
    container "proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.24054-2352758"
    stageInMode "${workflow.profile == 'aws' ? 'symlink' : 'link'}"

    input:
        path skyline_zipfile
        path mzml_file

    output:
        path("*.skyd"), emit: skyd_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:

    // if( workflow.profile == 'aws' )
    """
    unzip ${skyline_zipfile}

    cp ${mzml_file} /tmp/${mzml_file}

    wine SkylineCmd \
        --in="${skyline_zipfile.baseName}" \
        --import-no-join \
        --import-file="/tmp/${mzml_file}" \
    > >(tee 'import_${mzml_file.baseName}.stdout') 2> >(tee 'import_${mzml_file.baseName}.stderr' >&2)
    """

    // else
    // """
    // unzip ${skyline_zipfile}

    // wine SkylineCmd \
    //     --in="${skyline_zipfile.baseName}" \
    //     --import-no-join \
    //     --import-file="${mzml_file}" \
    // > >(tee 'import_${mzml_file.baseName}.stdout') 2> >(tee 'import_${mzml_file.baseName}.stderr' >&2)
    // """

    stub:
    """
    touch "${mzml_file.baseName}.skyd"
    touch stub.stderr stub.stdout
    """
}

process SKYLINE_MERGE_RESULTS {
    publishDir "${params.result_dir}/skyline/import-spectra", failOnError: true, mode: 'copy', enabled: params.skyline.save_intermediate_output
    cpus 16
    memory { check_max_mem(3.GB * skyd_files.size()) } // Allocate 1 GB of RAM per mzml file
    time 8.h
    // label 'error_retry'
    stageInMode "${workflow.profile == 'aws' ? 'symlink' : 'copy'}"
    container "proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.24054-2352758"

    input:
        path skyline_zipfile
        path skyd_files
        path mzml_files
        val final_skyline_doc_name
        path fasta

    output:
        path("*.sky.zip"), emit: final_skyline_zipfile
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    unzip ${skyline_zipfile}

    mv -v ${mzml_files} /tmp/
    cp -v ${skyd_files} /tmp/

    echo '--in="${skyline_zipfile.baseName}"' > batch_commands.bat
    echo '--import-file="${(mzml_files as List).collect{ '/tmp/' + file(it).name }.join('" --import-file="')}"' >> batch_commands.bat

    if ${params.skyline.group_by_gene} ; then
        echo '--import-fasta="${fasta}" --associate-proteins-gene-level-parsimony --associate-proteins-shared-peptides=DuplicatedBetweenProteins --associate-proteins-min-peptides=1 --associate-proteins-remove-subsets' >> batch_commands.bat
    fi

    if ${params.skyline.minimize} ; then
        echo '--chromatograms-discard-unused --chromatograms-limit-noise=1 --share-type="minimal" --out="${final_skyline_doc_name}.sky" --save --share-zip="${final_skyline_doc_name}.sky.zip"' >> batch_commands.bat
    else
        echo '--out="${final_skyline_doc_name}.sky" --save --share-zip="${final_skyline_doc_name}.sky.zip"' >> batch_commands.bat
    fi

    wine SkylineCmd --batch-commands=batch_commands.bat \
        > >(tee 'merge_skyline.stdout') 2> >(tee 'merge_skyline.stderr' >&2)
    """

    stub:
    """
    touch final.sky.zip
    touch stub.stdout stub.stderr
    """
}

process SKYLINE_EXPORT_REPORT {
    publishDir "${params.result_dir}/skyline/reports", failOnError: true, mode: 'copy'
    label 'process_high_memory'
    // label 'error_retry'
    container "proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.24054-2352758"

    input:
        path sky_file
        path sky_artifacts
        path report_template

    output:
        path("${report_name}.tsv"), emit: report
        // path("skyline-export-report.log"), emit: log

    script:
    report_name = report_template.baseName
    """
    wine SkylineCmd --in="${sky_file}" \
        --report-add="${report_template}" \
        --report-conflict-resolution="overwrite" --report-format="tsv" --report-invariant \
        --report-name="${report_name}" --report-file="${report_name}.tsv"
    """

    stub:
    """
    touch ${report_name}.tsv
    touch skyline-export-report.log
    """
}

process ANNOTATION_TSV_TO_CSV {
    publishDir "${params.result_dir}/skyline/annotate", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'error_retry'
    container 'quay.io/mauraisa/dia_qc_report:1.10'

    input:
        path annotation_tsv

    output:
        path("annotation_csv.csv"), emit: annotation_csv
        path("sky_annotation_definitions.bat"), emit: annotation_definitions

    shell:
        '''
        #!/usr/bin/env python3

        from csv import DictReader
        from pyDIAUtils.metadata import Dtype

        def write_csv_row(elems, out):
            out.write('"{}"\\n'.format('","'.join(elems)))

        with open("!{annotation_tsv}", 'r') as inF:
            data = list(DictReader(inF, delimiter='\\t'))

        annotation_headers = [x for x in data[0].keys() if x != 'Replicate']
        with open('annotation_csv.csv', 'w') as outF:
            # write header
            write_csv_row(['ElementLocator'] + [f'annotation_{x}' for x in annotation_headers], outF)

            for line in data:
                row = [f'Replicate:/{line["Replicate"]}']
                for header in annotation_headers:
                    row.append(line[header])
                write_csv_row(row, outF)

        types = dict()
        for header in annotation_headers:
            types[header] = max(Dtype.infer_type(row[header]) for row in data)

        def get_sky_type(dtype):
            if dtype is Dtype.BOOL:
                return 'true_false'
            if dtype is Dtype.INT or dtype is Dtype.FLOAT:
                return 'number'
            return 'text'

        # write commands to add annotationd definitions to skyline file
        with open('sky_annotation_definitions.bat', 'w') as outF:
            for name, dtype in types.items():
                outF.write(f'--annotation-name="{name}" --annotation-targets=replicate')
                outF.write(f' --annotation-type={get_sky_type(dtype)}\\n')
        '''
}

process SKYLINE_ANNOTATE_DOCUMENT {
    publishDir "${params.result_dir}/skyline/annotate", failOnError: true, mode: 'copy'
    label 'process_medium'
    // label 'error_retry'
    stageInMode 'link'
    container 'proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.24054-2352758'

    input:
        path sky_zip_file
        path annotation_csv
        path annotation_definitions
        val sky_doc_name

    output:
        path("${sky_doc_name}_annotated.sky.zip"), emit: sky_zip_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr
        env(sky_zip_hash), emit: file_hash
        env(sky_zip_size), emit: file_size

    shell:
    """
    unzip ${sky_zip_file}

    echo '--in="${sky_zip_file.baseName}"' > add_annotations.bat
    cat ${annotation_definitions} >> add_annotations.bat
    echo '--import-annotations="${annotation_csv}"' >> add_annotations.bat
    echo '--save --out="${sky_doc_name}_annotated.sky" --share-zip="${sky_doc_name}_annotated.sky.zip"' >> add_annotations.bat

    wine SkylineCmd --batch-commands=add_annotations.bat \
        > >(tee 'annotate_doc.stdout') 2> >(tee 'annotate_doc.stderr' >&2)

    sky_zip_hash=\$( md5sum ${sky_doc_name}_annotated.sky.zip |awk '{print \$1}' )
    sky_zip_size=\$( du -L ${sky_doc_name}_annotated.sky.zip |awk '{print \$1}' )
    """

    stub:
    '''
    touch "final_annotated.sky.zip"
    touch stub.stdout stub.stderr
    sky_zip_hash=\$( md5sum final_annotated.sky.zip |awk '{print \$1}' )
    sky_zip_size=\$( du -L final_annotated.sky.zip |awk '{print \$1}' )
    '''
}

process UNZIP_SKY_FILE {
    label 'process_high_memory'
    container "${workflow.profile == 'aws' ? 'public.ecr.aws/docker/library/ubuntu:22.04' : 'ubuntu:22.04'}"

    input:
        path(sky_zip_file)

    output:
        path("*.sky"), emit: sky_file
        path("*.{skyd,[eb]lib,[eb]libc,protdb,sky.view}"), emit: sky_artifacts
        path("*.archive_files.txt"), emit: log

    script:
    """
    unzip -o ${sky_zip_file} |tee ${sky_zip_file.baseName}.archive_files.txt
    """

    stub:
    """
    touch ${sky_zip_file.baseName}
    touch ${sky_zip_file.baseName}d
    touch lib.blib
    touch ${sky_zip_file.baseName}.archive_files.txt
    """
}
