nextflow.preview.dsl = 2

process create_surface_view{

    label 'rtms'
    containerOptions "-B ${params.bin}:/scripts"

    input:
    tuple val(sub), path(weightfunc), path(l_pial),\
    path(r_pial), path("${sub}.sulc.dscalar.nii")

    output:
    tuple val(sub), path("${sub}_qc-wf_view-*.png"), emit: qc_imgs

    shell:
    '''

    # Run script to generate QC images
    /scripts/gen_surf_qc.py !{weightfunc} !{l_pial} !{r_pial} \
                            --bg_surf !{sub}.sulc.dscalar.nii !{sub}_qc-wf
    '''


}

/*
Workflow for generating QC images
*/
workflow qc_wf{

    take:
        weightfunc
        l_pial
        r_pial
        sulc

    main:
        i_create_surface_view = weightfunc
                                .join(l_pial).join(r_pial)
                                .join(sulc) | view
        create_surface_view(i_create_surface_view)

    emit:
        surf_qc = create_surface_view.out.qc_imgs

}
