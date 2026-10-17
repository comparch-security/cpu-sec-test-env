/* glibc >= 2.43 C23 const-preserving <wchar.h> shim.
 * See string.h in this directory for the full rationale.
 *
 * glibc 2.43 const-generic-izes: wcschr, wcspbrk, wcsrchr, wcsstr, wmemchr.
 */
#pragma once

#include_next <wchar.h>

#undef wcschr
#undef wcspbrk
#undef wcsrchr
#undef wcsstr
#undef wmemchr
