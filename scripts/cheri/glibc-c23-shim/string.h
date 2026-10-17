/* glibc >= 2.43 C23 const-preserving <string.h> shim.
 *
 * SCOPE: shipped copy (plan 2026-10-14-cheri-lanes-bringup).  Reached via
 * CHERI_CROSS_CPATH (env.sh) on the CheriBSD legs of scripts/cheri/build_image.sh
 * (--cheribsd/extra-env=CPATH=...), which injects it into the world build's
 * host-tools stage.
 *
 * WHY: glibc 2.43 implements C23's const-preserving string functions as
 * _Generic macros, e.g. at /usr/include/string.h:263-265
 *     #  define strchr(S, C) \
 *          __glibc_const_generic (S, const char *, strchr (S, C))
 * so strchr(const char *, int) now yields `const char *`. Code written for
 * C17 -- which assigns the result to a plain `char *`, entirely correctly at
 * the time -- then trips -Wincompatible-pointer-types-discards-qualifiers.
 * FreeBSD's bootstrap tools promote exactly that diagnostic to an error
 * (tools/build/mk/Makefile.boot:41), so the CheriBSD world build dies in
 * stage 1.1 on lib/libc/stdlib/getopt.c:89 and getopt_long.c:494.
 *
 * HOW: the macro is what changes the declared return type; the plain C17
 * declaration sits right above it (string.h:261,
 *     extern char *strchr (const char *__s, int __c) ...
 * so undefining the macro restores the pre-C23 type exactly. `#include_next`
 * keeps glibc's header as the source of truth -- this shim only removes the
 * macro layer on top of it.
 *
 * The undefs are enumerated exhaustively from this glibc's own headers; every
 * symbol glibc 2.43 const-generic-izes is listed here (string.h: memchr,
 * strchr, strpbrk, strrchr, strstr).
 *
 * SAFETY: reached only through CPATH, which is searched after every -I. The
 * FreeBSD cross-build stage resolves <string.h> from its own sysroot via -I,
 * so this shim never applies there -- it is self-scoping to the host-tools
 * stage that needs it. Undefining a name that is not a macro is a no-op, so
 * the shim is inert on any glibc that predates this change.
 */
#pragma once

#include_next <string.h>

#undef memchr
#undef strchr
#undef strpbrk
#undef strrchr
#undef strstr
