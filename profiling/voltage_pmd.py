import numpy as np
from trefide.pmd import serial_batch_pmd, parallel_batch_pmd

if __name__ == "__main__":
    X = np.load("/home/ian/devel/trefide/data/prepared_sampleMovie.npy")
    X = np.tile(X, (5, 2))
    d1, d2, T = X.shape

    K = 20
    maxiter = 50
    tol = 5e-3
    bheight = 20
    bwidth = 100
    spatial_cutoff = (bheight*bwidth / ((bheight*(bwidth-1) + bwidth*(bheight-1))))
    w = .0025
    
    # U, V, K, indices = serial_batch_pmd(d1, d2, T, X, bheight, bwidth, w, spatial_cutoff, K, maxiter, tol)
    U, V, K, indices = parallel_batch_pmd(d1, d2, T, X, bheight, bwidth, w, spatial_cutoff, K, maxiter, tol)
