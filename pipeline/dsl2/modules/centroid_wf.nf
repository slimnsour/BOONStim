nextflow.preview.dsl = 2

process split_dscalar {

    label 'connectome'

    input:
    tuple val(sub), path(dscalar)

    output:
    tuple val(sub), val('L'), path('L.shape.gii'), emit: left
    tuple val(sub), val('R'), path('R.shape.gii'), emit: right

    shell:
    '''
    wb_command -cifti-separate \
                !{dscalar} \
                COLUMN \
                -metric CORTEX_LEFT L.shape.gii \
                -metric CORTEX_RIGHT R.shape.gii
    '''


}

process centroid_project2vol {

    label 'connectome'

    input:
    tuple val(sub), val(hemi), path(shape), path(pial), path(white), path(midthick), path(t1)

    output:
    tuple val(sub), val(hemi), path("${sub}.${hemi}.ribbon.nii.gz"), emit: ribbon

    shell:
    '''
    wb_command -metric-to-volume-mapping \
                !{shape} \
                !{midthick} \
                !{t1} \
                -ribbon-constrained \
                    !{white} \
                    !{pial} \
                !{sub}.!{hemi}.ribbon.nii.gz
    '''
}

process add_centroid_niftis {

    label 'connectome'

    input:
    tuple val(sub), path(nifti1), path(nifti2)

    output:
    tuple val(sub), path('combined.nii.gz'), emit: sumvol

    shell:
    '''
    wb_command -volume-math \
                "x + y" \
                -var x !{nifti1} \
                -var y !{nifti2} \
                combined.nii.gz
    '''
}

process normalize_vol {

    label 'connectome'
    input:
    tuple val(sub), path(vol)

    output:
    tuple val(sub), path('normalized.nii.gz'), emit: normvol

    shell:
    '''
    wb_command -volume-math 'a' fixed.nii.gz -var a !{vol} -fixnan 0

    sum=$(wb_command -volume-stats \
                fixed.nii.gz \
                -reduce SUM)

    wb_command -volume-math \
                "x/${sum}" \
                -var x fixed.nii.gz \
                normalized.nii.gz
    '''

}

process compute_weighted_centroid{

    label 'rtms'

    input:
    tuple val(sub), path(vol)

    output:
    tuple val(sub), path('ras_coord.txt'), emit: coord

    shell:
    '''
    #!/usr/bin/env python

    import nibabel as nib
    import numpy as np

    #Load image
    img = nib.load("!{vol}")
    affine = img.affine
    data = img.get_data()

    #Mask
    x,y,z = np.where(data > 0)
    coords = np.array([x,y,z])
    vals = data[(x,y,z)]

    #Compute
    weighted_vox = np.dot(coords,vals)[:,np.newaxis]
    r_weighted_vox = np.dot(affine[:3,:3],weighted_vox)
    weighted_coord = r_weighted_vox + affine[:3,3:4]

    #Save
    np.savetxt("ras_coord.txt",weighted_coord)
    '''


}

workflow centroid_wf{

    get:
        dscalar
        pial
        white
        midthick
        t1

    main:

        //Split into shapes
        split_dscalar(dscalar)

        //Formulate inputs and mix
        left_project_input = split_dscalar.out.left
                                        .join(pial, by:[0,1])
                                        .join(white, by:[0,1])
                                        .join(midthick, by:[0,1])
                                        .join(t1, by:0)

        right_project_input = split_dscalar.out.right
                                        .join(pial, by:[0,1])
                                        .join(white, by:[0,1])
                                        .join(midthick, by:[0,1])
                                        .join(t1, by:0)

        //Combine into one stream
        project_input = left_project_input.mix(right_project_input)
        centroid_project2vol(project_input)

        //Gather together T1 outputs and sum to form full image
        add_niftis_input = centroid_project2vol.out.ribbon
                                    .groupTuple(by: 0, size: 2)
                                    .map{ s,h,n -> [ s,n[0],n[1] ] }
        add_centroid_niftis(add_niftis_input)

        //Re-normalize
        normalize_vol(add_centroid_niftis.out.sumvol)
        normalize_vol.out.normvol

        //Calculate centroid
        compute_weighted_centroid(normalize_vol.out.normvol)

    emit:
        centroid = compute_weighted_centroid.out.coord










}
