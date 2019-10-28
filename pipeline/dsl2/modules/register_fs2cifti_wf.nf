nextflow.preview.dsl=2


process convert_sulcal{

    label 'freesurfer'

    input:
    tuple val(sub), val(hemi), path(sulc), path(white)

    output:
    tuple val(sub), val(hemi), path("${hemi}.sulc.native.shape.gii")
    
    """
    export FS_LICENSE=/license/license.txt
    mris_convert -c $sulc $white ${hemi}.sulc.native.shape.gii
    """

}

process assign_sulcal{
    
    label 'connectome'

    input:
    tuple val(sub), val(hemi), val(structure), path(sulc)

    output:
    tuple val(sub), val(hemi), path(sulc)

    """
    wb_command -set-structure $sulc $structure
    """


}

process invert_sulcal{
    
    label 'connectome'

    input:
    tuple val(sub), val(hemi), path(sulc)

    output:
    tuple val(sub), val(hemi), path(sulc)

    """
    wb_command -metric-math 'a*(-1)' -var 'a' $sulc $sulc
    """
}

process convert_sphere{
    
    label 'freesurfer'

    input:
    tuple val(sub), val(hemi), path(sphere), val(output)

    output:
    tuple val(sub), val(hemi), path("${output}.surf.gii")

    '''
    export FS_LICENSE=/license/license.txt
    mris_convert !{sphere} !{sphere}.surf.gii
    mv !{sphere}.surf.gii !{output}.surf.gii
    '''
}

process assign_sphere{
    
    label 'connectome'

    input:
    tuple val(sub), val(structure), path(sphere)

    output:
    tuple val(sub), path(sphere)

    """
    wb_command -set-structure ${sphere} ${structure} -surface-type "SPHERICAL"
    """

}

process deform_sphere{

    label 'connectome'
    containerOptions "-B ${params.atlas}:/atlas"

    input:
    tuple val(sub), val(hemi), path(sphere)

    output:
    tuple val(sub), val(hemi), file("${hemi}.sphere.reg.reg_LR.native.surf.gii")

    '''
    wb_command -surface-sphere-project-unproject \
                !{sphere} \
                /atlas/fsaverage.!{hemi}.sphere.164k_fs_!{hemi}.surf.gii \
                /atlas/fs_!{hemi}-to-fs_LR_fsasverage.!{hemi}_LR.spherical_std.164k_fs_!{hemi}.surf.gii \
                !{hemi}.sphere.reg.reg_LR.native.surf.gii
    '''

}

process spherical_affine{
    
    label 'connectome'
    
    input:
    tuple val(sub), val(hemi), path(sphere), path(reg_LR_sphere)

    output:
    tuple val(sub), val(hemi), path(sphere), path("${hemi}_affine.mat")

    """
    wb_command -surface-affine-regression \
                ${sphere} \
                ${reg_LR_sphere} \
                ${hemi}_affine.mat
    """
}

process normalize_rotation{
    
    label 'numpy'
    
    input:
    tuple val(sub), val(hemi), path(affine)
    
    output:
    tuple val(sub), val(hemi), path("norm_affine.mat")

    shell:
    '''
    #!/usr/bin/env python

    import numpy as np

    M = np.genfromtxt("!{affine}")
    M[:,3] = 0
    M[3,3] = 1

    linear_map = M[:3,:3]
    U,S,V = np.linalg.svg(linear_map)
    M[:3,:3] = np.matmul(U,V)
    np.savetxt("norm_affine.mat",M)
    '''

}

process apply_affine{

    label 'connectome'
    
    input:
    tuple val(sub), val(hemi), path(sphere), path(affine)

    output:
    tuple val(sub), val(hemi), path("${hemi}.sphere_rot.surf.gii")

    """
    wb_command -surface-apply-affine \
                $sphere \
                $affine \
                ${hemi}.sphere_rot.surf.gii

    wb_command -surface-modify-sphere \
                ${hemi}.sphere_rot.surf.gii \
                100 \
                ${hemi}.sphere_rot.surf.gii
    """

}

process msm_sulc {

    label 'connectome'
    containerOptions "-B ${params.atlasdir}:/atlas -B ${params.msm_conf}:/msm_conf"
    
    input:
    tuple val(sub), val(hemi), path(sphere), path(sulc), val(structure)

    output:
    tuple val(sub), val(hemi), path(sphere), path("${hemi}.sphere.reg_msm.surf.gii")

    shell:
    '''
    /msm/msm --inmesh=!{sphere} \
             --indata=!{sulc} \
             --refmesh=/atlas/fsaverage.!{hemi}_LR.spherical_std.164k_fs_LR.surf.gii \
             --refdata=/atlas/!{hemi}.refsulc.164k_fs_LR.shape.gii \
             --conf=/msm_conf/MSMSulcStrainFinalconf \
             --out=!{hemi}. \
             --verbose

    mv "${hemi}.sphere.reg.surf.gii" \
       "${hemi}.sphere.reg_msm.surf.gii"

    wb_command -set-structure !{hemi}.sphere.reg_msm.surf.gii \
                                !{structure}
    '''

}

process areal_distortion{

    label 'connectome'

    input:
    tuple val(sub), val(hemi), path(sphere), path(msm_sphere)

    output:
    path("${hemi}.areal_distortion_shape.gii"), emit: areal

    


}

workflow registration_wf {

    get:
        fs_dirs

    main:
        
        // Might have to migrate this over fs2gifti
        // Convert sulcal information from freesurfer to connectome workbench
        sulcal_input = fs_dirs
                            .spread ( ['L','R'] )
                            .map{s,f,h ->   [
                                                s,
                                                h,
                                                "${f}/surf/${h[2].toLowerCase()}h.sulc",
                                                "${f}/surf/${h[2].toLowerCase()}h.white"
                                            ]
                                }
        convert_sulcal(sulcal_input)

        // Assign structure to sulcal map then invert
        structure_map = ['L' : 'CORTEX_LEFT', 'R' : 'CORTEX_RIGHT' ]
        assign_input = convert.sulcal.out
                                    .map{ s,h,g ->  [
                                                        s,h
                                                        structure_map[h],
                                                        g
                                                    ]
                                        }
        assign_sulcal(assign_input)
        invert_sulcal(assign_sulcal.out)

        // Now convert spheres over, assign properties, 
        registration_spheres = fs_dirs
                                    .spread( ['L','R'] )
                                    .spread( ['sphere','sphere.reg'] )
                                    .map{ s,f,h,sph ->  [
                                                            s,sph,
                                                            "${f}/surf/${h.toLowerCase()}h.${sph}",
                                                            "${h}.${sph}"
                                                        ]
                                        }
        convert_sphere(registration_spheres)
        
        assign_sphere_input = convert_sphere.out
                                        .map{ s,h,sph ->[
                                                            s,
                                                            structure_map[h],
                                                            sph
                                                        ]
                                            }
        assign_sphere(assign_sphere_input)

        //Pull reg spheres and perform spherical deformation
        reg_sphere = assign_sphere.out
                        .filter { it.sph.name.contains('reg') }
                        .map{ s,sph ->  [
                                            s,
                                            sph.name.take(1),
                                            sph
                                        ]
                            }
        deform_sphere(reg_sphere.out)

        // Merge with native sphere and compute affine
        affine_input = assign_sphere.out
                                    .filter { !(it.sph.name.contains('reg')) }
                                    .map{ s,sph ->  [
                                                        s,
                                                        sph.name.take(1),
                                                        sph
                                                    ]
                                        }
                                    .join(deform_sphere, by : [0,1])
        spherical_affine(affine_input)

        // Normalize affine transformation
        normalization_input = spherical_affine.out
                                        .map { s,h,sph,aff-> [s,h,aff] }
        normalize_rotation(normalization_input)

        // Apply affine transformation to sphere
        rotation_input = affine_input
                                .join(normalize_rotation.out, by: [0,1])
        apply_affine(rotation_input)


        // Perform MSM
        msm_input = apply_affine.out
                            .join(invert_sulcal.out, by: [0,1])
                            .map{ s,h,sph,sulc ->   [
                                                        s,h,sph,sulc,
                                                        structure_map[h]
                                                    ]
                                }
        msm_sulc(msm_input)

        // Make areal distortion map
        areal_distortion(msm_input.out)
                                                    
                            
}
