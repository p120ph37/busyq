/* arc4random() compat for musl using getrandom() — ISC license */
/*
 * Minimal arc4random implementation for systems with getrandom()
 * but no arc4random (e.g., musl libc).
 */
#include <stdint.h>
#include <stdlib.h>
#include <sys/random.h>

uint32_t
arc4random(void)
{
	uint32_t val;
	getrandom(&val, sizeof(val), 0);
	return val;
}

void
arc4random_buf(void *buf, size_t nbytes)
{
	getrandom(buf, nbytes, 0);
}

uint32_t
arc4random_uniform(uint32_t upper_bound)
{
	uint32_t r, min;

	if (upper_bound < 2)
		return 0;

	/* Rejection sampling for uniform distribution */
	min = -upper_bound % upper_bound;
	for (;;) {
		r = arc4random();
		if (r >= min)
			break;
	}
	return r % upper_bound;
}
