#ifndef LINE_SEARCH_H
#define LINE_SEARCH_H

int line_search(const int n,           // data length
		const double *y,       // observations
		const double *wi,      // inverse observation weights
                const double delta,    // MSE constraint	
                double tau,            // step size in transformed space
                double *x,             // primal variable
		double *z,             // initial dual variable
		double *lambda,        // initial regularization parameter
		int *iters,            // pointer to iter # (so we can return it)
                const int max_interp,  // number of times to try interpolating
		const double tol,      // max num outer loop iterations
		const int verbose);

#endif /* LINE_SEARCH_H */