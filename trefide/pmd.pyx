# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False
# cython: initializedcheck=False
# cython: nonecheck=False

import os

import numpy as np
cimport numpy as np

from cython.parallel import parallel, prange
from libc.stdlib cimport abort, calloc, malloc, free


# -----------------------------------------------------------------------------#
# ------------------------- Imports From Libtrefide.so ------------------------#
# -----------------------------------------------------------------------------#


cdef extern from "trefide.h":
    size_t pmd(const int d1, 
               const int d2, 
               const int t,
               double* R, 
               double* U,
               double* V,
               const double lambda_tv,
               const double spatial_thresh,
               const size_t max_components,
               const size_t max_iters,
               const double tol) nogil

    void batch_pmd(const int bheight, 
                   const int bwidth, 
                   const int t,
                   const int b,
                   double** Rpt, 
                   double** Upt,
                   double** Vpt,
                   size_t* Kpt,
                   const double lambda_tv,
                   const double spatial_thresh,
                   const size_t max_components,
                   const size_t max_iters,
                   const double tol) nogil


# -----------------------------------------------------------------------------#
# -------------------------- Single-Block Wrapper -----------------------------#
# -----------------------------------------------------------------------------#


cpdef size_t decompose(const int d1, 
                       const int d2, 
                       const int t,
                       double[::1] Y, 
                       double[::1] U,
                       double[::1] V,
                       const double lambda_tv,
                       const double spatial_thresh,
                       const size_t max_components,
                       const size_t max_iters,
                       const double tol) nogil:
    """ Wrap the single patch cpp PMD functions """

    # Turn Off Gil To Take Advantage Of Multithreaded MKL Libs
    with nogil:
        return pmd(d1, d2, t, &Y[0], &U[0], &V[0], lambda_tv, 
                   spatial_thresh, max_components, max_iters, tol)


# -----------------------------------------------------------------------------#
# --------------------------- Multi-Block Wrappers ----------------------------#
# -----------------------------------------------------------------------------#


cpdef batch_decompose(const int d1, 
                      const int d2, 
                      const int t,
                      double[:, :, ::1] Y, 
                      const int bheight,
                      const int bwidth,
                      const double lambda_tv,
                      const double spatial_thresh,
                      const size_t max_components,
                      const size_t max_iters,
                      const double tol):
    """ Wrapper for the .cpp parallel_factor_patch which wraps the .cpp function 
     factor_patch with OpenMP directives to parallelize batch processing."""

    # Initialize Counters
    cdef size_t iu, ku
    cdef int i, j, k, b, bi, bj
    cdef int nbi = int(d1/bheight)
    cdef int nbj = int(d2/bwidth)
    cdef int num_blocks = nbi * nbj

    # Compute block-start indices and spatial cutoff
    indices = np.transpose([np.tile(range(nbi), nbj), np.repeat(range(nbj), nbi)])

    # Preallocate Space For Outputs
    cdef double[:,::1] U = np.zeros((num_blocks, bheight * bwidth * max_components), dtype=np.float64)
    cdef double[:,::1] V = np.zeros((num_blocks, t * max_components), dtype=np.float64)
    cdef size_t[::1] K = np.empty((num_blocks,), dtype=np.uint64)

    # Allocate Input Pointers
    cdef double** Rp = <double **> malloc(num_blocks * sizeof(double*))
    cdef double** Vp = <double **> malloc(num_blocks * sizeof(double*))
    cdef double** Up = <double **> malloc(num_blocks * sizeof(double*))

    # Release Gil Prior To Referencing Address & Calling Multithreaded Code
    with nogil:

        # Assign Pre-allocated Output Memory To Pointer Array & Allocate Residual Pointers
        for b in range(num_blocks):
            Rp[b] = <double *> malloc(bheight * bwidth * t * sizeof(double))
            Up[b] = &U[b,0]
            Vp[b] = &V[b,0] 

        # Copy Contents Of Raw Blocks Into Residual Pointers
        for bj in range(nbj):
            for bi in range(nbi):
                for k in range(t):
                    for j in range(bwidth):
                        for i in range(bheight):
                            Rp[bi + (bj * nbi)][i + (j * bheight) + (k * bheight * bwidth)] =\
                                    Y[(bi * bheight) + i, (bj * bwidth) + j, k]

        # Factor Blocks In Parallel
        batch_pmd(bheight, bwidth, t, num_blocks, Rp, Up, Vp, &K[0],
                  lambda_tv, spatial_thresh, max_components, max_iters,tol)

        # Free Allocated Memory
        for b in range(num_blocks):
            free(Rp[b])
        free(Rp)
        free(Up)
        free(Vp)
            
    # Format Components & Return To Numpy Array
    return (np.asarray(U).reshape((num_blocks, bheight, bwidth, max_components), order='F'), 
            np.asarray(V).reshape((num_blocks, max_components, t), order='C'), 
            np.asarray(K), indices.astype(np.uint64))


cpdef double[:,:,::1] batch_recompose(double[:, :, :, :] U, 
                                      double[:,:,::1] V, 
                                      size_t[::1] K, 
                                      size_t[:,:] indices):
    """ Reconstruct A Denoised Movie """

    # Get Block Size Info From Spatial
    cdef size_t num_blocks = U.shape[0]
    cdef size_t bheight = U.shape[1]
    cdef size_t bwidth = U.shape[2]
    cdef size_t t = V.shape[2]

    # Get Mvie Size Infro From Indices
    cdef size_t nbi, nbj
    nbi = np.max(indices[:,0]) + 1
    nbj = np.max(indices[:,1]) + 1
    cdef size_t d1 = nbi * bheight
    cdef size_t d2 = nbj * bwidth

    # Allocate Space For reconstructed Movies
    Yd = np.zeros(d1*d2*t, dtype=np.float64).reshape((d1,d2,t))

    # Loop Over Blocks
    cdef size_t bdx, idx, jdx, kdx
    for bdx in range(nbi*nbj):
        idx = indices[bdx,0] * bheight
        jdx = indices[bdx,1] * bwidth
        Yd[idx:idx+bheight, jdx:jdx+bwidth,:] += np.reshape(
                np.dot(U[bdx,:,:,:K[bdx]],
                       V[bdx,:K[bdx],:]),
                (bheight,bwidth,t),
                order='F')
    # Rank One updates
    return Yd
