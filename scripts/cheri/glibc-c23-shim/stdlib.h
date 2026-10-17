/* glibc >= 2.43 C23 const-preserving <stdlib.h> shim.
 * See string.h in this directory for the full rationale.
 *
 * glibc 2.43 const-generic-izes: bsearch.
 */
#pragma once

#include_next <stdlib.h>

#undef bsearch
