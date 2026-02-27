/*
 * applets.h — Canonical applet registry for busyq (X-macro pattern)
 *
 * Single source of truth for all busyq applets.  Define APPLET(module,
 * command, entry_func) before including this file; the macro is invoked
 * once per active applet.
 *
 * Filtering for custom builds
 * ---------------------------
 * Compile with -DBUSYQ_CUSTOM_APPLETS plus -DAPPLET_<command>=1 for
 * each desired applet.  Applets not explicitly enabled are excluded
 * and their entry functions are never referenced, allowing LTO to
 * strip the corresponding code.
 *
 *   Example (direct cc):
 *     cc -DBUSYQ_CUSTOM_APPLETS -DAPPLET_curl=1 -DAPPLET_jq=1 \
 *        -DAPPLET_ls=1 src/applets.c -Isrc/ libbusyq.a ...
 *
 *   Example (cmake):
 *     cmake --preset no-ssl -DBUSYQ_APPLETS="curl;jq;ls"
 *
 * The "core" module (busyq help) is always included.
 *
 * Modules and their vcpkg ports / libraries
 * ------------------------------------------
 *   core       - busyq built-in (no external library needed)
 *   curl       - busyq-curl: libcurlmain + libcurl + deps
 *   jq         - busyq-jq: libjqmain + libjq + libonig
 *   ssl        - mbedtls: libmbedtls + libmbedx509 + libmbedcrypto
 *   coreutils  - busyq-coreutils: libcoreutils
 */

/* ---- If APPLET was not defined by the includer, provide a no-op ---- */
#ifndef APPLET
#define APPLET(module, command, entry_func)
#define _APPLETS_H_UNDEF_APPLET
#endif

/* ==================================================================== */
/* Applet enable/disable defaults                                        */
/*                                                                       */
/* Each APPLET_<command> macro is 0 or 1.  In a full build they all      */
/* default to 1.  With -DBUSYQ_CUSTOM_APPLETS, they default to 0 and    */
/* only the explicitly enabled ones (-DAPPLET_<command>=1) are active.   */
/* ==================================================================== */

#ifdef BUSYQ_CUSTOM_APPLETS
#  define _BQ_DEFAULT 0
#else
#  define _BQ_DEFAULT 1
#endif

/* Core — always enabled */
#ifndef APPLET_busyq
#define APPLET_busyq 1
#endif

/* curl */
#ifndef APPLET_curl
#define APPLET_curl _BQ_DEFAULT
#endif

/* jq */
#ifndef APPLET_jq
#define APPLET_jq _BQ_DEFAULT
#endif

/* ssl_client — also requires BUSYQ_SSL to be defined */
#ifndef APPLET_ssl_client
#  if BUSYQ_SSL
#    define APPLET_ssl_client _BQ_DEFAULT
#  else
#    define APPLET_ssl_client 0
#  endif
#endif

/* GNU coreutils */
#ifndef APPLET_arch
#define APPLET_arch _BQ_DEFAULT
#endif
#ifndef APPLET_b2sum
#define APPLET_b2sum _BQ_DEFAULT
#endif
#ifndef APPLET_base32
#define APPLET_base32 _BQ_DEFAULT
#endif
#ifndef APPLET_base64
#define APPLET_base64 _BQ_DEFAULT
#endif
#ifndef APPLET_basename
#define APPLET_basename _BQ_DEFAULT
#endif
#ifndef APPLET_basenc
#define APPLET_basenc _BQ_DEFAULT
#endif
#ifndef APPLET_cat
#define APPLET_cat _BQ_DEFAULT
#endif
#ifndef APPLET_chcon
#define APPLET_chcon _BQ_DEFAULT
#endif
#ifndef APPLET_chgrp
#define APPLET_chgrp _BQ_DEFAULT
#endif
#ifndef APPLET_chmod
#define APPLET_chmod _BQ_DEFAULT
#endif
#ifndef APPLET_chown
#define APPLET_chown _BQ_DEFAULT
#endif
#ifndef APPLET_chroot
#define APPLET_chroot _BQ_DEFAULT
#endif
#ifndef APPLET_cksum
#define APPLET_cksum _BQ_DEFAULT
#endif
#ifndef APPLET_comm
#define APPLET_comm _BQ_DEFAULT
#endif
#ifndef APPLET_cp
#define APPLET_cp _BQ_DEFAULT
#endif
#ifndef APPLET_csplit
#define APPLET_csplit _BQ_DEFAULT
#endif
#ifndef APPLET_cut
#define APPLET_cut _BQ_DEFAULT
#endif
#ifndef APPLET_date
#define APPLET_date _BQ_DEFAULT
#endif
#ifndef APPLET_dd
#define APPLET_dd _BQ_DEFAULT
#endif
#ifndef APPLET_df
#define APPLET_df _BQ_DEFAULT
#endif
#ifndef APPLET_dir
#define APPLET_dir _BQ_DEFAULT
#endif
#ifndef APPLET_dircolors
#define APPLET_dircolors _BQ_DEFAULT
#endif
#ifndef APPLET_dirname
#define APPLET_dirname _BQ_DEFAULT
#endif
#ifndef APPLET_du
#define APPLET_du _BQ_DEFAULT
#endif
#ifndef APPLET_echo
#define APPLET_echo _BQ_DEFAULT
#endif
#ifndef APPLET_env
#define APPLET_env _BQ_DEFAULT
#endif
#ifndef APPLET_expand
#define APPLET_expand _BQ_DEFAULT
#endif
#ifndef APPLET_expr
#define APPLET_expr _BQ_DEFAULT
#endif
#ifndef APPLET_factor
#define APPLET_factor _BQ_DEFAULT
#endif
#ifndef APPLET_false
#define APPLET_false _BQ_DEFAULT
#endif
#ifndef APPLET_fmt
#define APPLET_fmt _BQ_DEFAULT
#endif
#ifndef APPLET_fold
#define APPLET_fold _BQ_DEFAULT
#endif
#ifndef APPLET_groups
#define APPLET_groups _BQ_DEFAULT
#endif
#ifndef APPLET_head
#define APPLET_head _BQ_DEFAULT
#endif
#ifndef APPLET_hostid
#define APPLET_hostid _BQ_DEFAULT
#endif
#ifndef APPLET_id
#define APPLET_id _BQ_DEFAULT
#endif
#ifndef APPLET_install
#define APPLET_install _BQ_DEFAULT
#endif
#ifndef APPLET_join
#define APPLET_join _BQ_DEFAULT
#endif
#ifndef APPLET_kill
#define APPLET_kill _BQ_DEFAULT
#endif
#ifndef APPLET_link
#define APPLET_link _BQ_DEFAULT
#endif
#ifndef APPLET_ln
#define APPLET_ln _BQ_DEFAULT
#endif
#ifndef APPLET_logname
#define APPLET_logname _BQ_DEFAULT
#endif
#ifndef APPLET_ls
#define APPLET_ls _BQ_DEFAULT
#endif
#ifndef APPLET_md5sum
#define APPLET_md5sum _BQ_DEFAULT
#endif
#ifndef APPLET_mkdir
#define APPLET_mkdir _BQ_DEFAULT
#endif
#ifndef APPLET_mkfifo
#define APPLET_mkfifo _BQ_DEFAULT
#endif
#ifndef APPLET_mknod
#define APPLET_mknod _BQ_DEFAULT
#endif
#ifndef APPLET_mktemp
#define APPLET_mktemp _BQ_DEFAULT
#endif
#ifndef APPLET_mv
#define APPLET_mv _BQ_DEFAULT
#endif
#ifndef APPLET_nice
#define APPLET_nice _BQ_DEFAULT
#endif
#ifndef APPLET_nl
#define APPLET_nl _BQ_DEFAULT
#endif
#ifndef APPLET_nohup
#define APPLET_nohup _BQ_DEFAULT
#endif
#ifndef APPLET_nproc
#define APPLET_nproc _BQ_DEFAULT
#endif
#ifndef APPLET_numfmt
#define APPLET_numfmt _BQ_DEFAULT
#endif
#ifndef APPLET_od
#define APPLET_od _BQ_DEFAULT
#endif
#ifndef APPLET_paste
#define APPLET_paste _BQ_DEFAULT
#endif
#ifndef APPLET_pathchk
#define APPLET_pathchk _BQ_DEFAULT
#endif
#ifndef APPLET_pinky
#define APPLET_pinky _BQ_DEFAULT
#endif
#ifndef APPLET_pr
#define APPLET_pr _BQ_DEFAULT
#endif
#ifndef APPLET_printenv
#define APPLET_printenv _BQ_DEFAULT
#endif
#ifndef APPLET_printf
#define APPLET_printf _BQ_DEFAULT
#endif
#ifndef APPLET_ptx
#define APPLET_ptx _BQ_DEFAULT
#endif
#ifndef APPLET_pwd
#define APPLET_pwd _BQ_DEFAULT
#endif
#ifndef APPLET_readlink
#define APPLET_readlink _BQ_DEFAULT
#endif
#ifndef APPLET_realpath
#define APPLET_realpath _BQ_DEFAULT
#endif
#ifndef APPLET_rm
#define APPLET_rm _BQ_DEFAULT
#endif
#ifndef APPLET_rmdir
#define APPLET_rmdir _BQ_DEFAULT
#endif
#ifndef APPLET_runcon
#define APPLET_runcon _BQ_DEFAULT
#endif
#ifndef APPLET_seq
#define APPLET_seq _BQ_DEFAULT
#endif
#ifndef APPLET_sha1sum
#define APPLET_sha1sum _BQ_DEFAULT
#endif
#ifndef APPLET_sha224sum
#define APPLET_sha224sum _BQ_DEFAULT
#endif
#ifndef APPLET_sha256sum
#define APPLET_sha256sum _BQ_DEFAULT
#endif
#ifndef APPLET_sha384sum
#define APPLET_sha384sum _BQ_DEFAULT
#endif
#ifndef APPLET_sha512sum
#define APPLET_sha512sum _BQ_DEFAULT
#endif
#ifndef APPLET_shred
#define APPLET_shred _BQ_DEFAULT
#endif
#ifndef APPLET_shuf
#define APPLET_shuf _BQ_DEFAULT
#endif
#ifndef APPLET_sleep
#define APPLET_sleep _BQ_DEFAULT
#endif
#ifndef APPLET_sort
#define APPLET_sort _BQ_DEFAULT
#endif
#ifndef APPLET_split
#define APPLET_split _BQ_DEFAULT
#endif
#ifndef APPLET_stat
#define APPLET_stat _BQ_DEFAULT
#endif
#ifndef APPLET_stty
#define APPLET_stty _BQ_DEFAULT
#endif
#ifndef APPLET_sum
#define APPLET_sum _BQ_DEFAULT
#endif
#ifndef APPLET_sync
#define APPLET_sync _BQ_DEFAULT
#endif
#ifndef APPLET_tac
#define APPLET_tac _BQ_DEFAULT
#endif
#ifndef APPLET_tail
#define APPLET_tail _BQ_DEFAULT
#endif
#ifndef APPLET_tee
#define APPLET_tee _BQ_DEFAULT
#endif
#ifndef APPLET_test
#define APPLET_test _BQ_DEFAULT
#endif
#ifndef APPLET_timeout
#define APPLET_timeout _BQ_DEFAULT
#endif
#ifndef APPLET_touch
#define APPLET_touch _BQ_DEFAULT
#endif
#ifndef APPLET_tr
#define APPLET_tr _BQ_DEFAULT
#endif
#ifndef APPLET_true
#define APPLET_true _BQ_DEFAULT
#endif
#ifndef APPLET_truncate
#define APPLET_truncate _BQ_DEFAULT
#endif
#ifndef APPLET_tsort
#define APPLET_tsort _BQ_DEFAULT
#endif
#ifndef APPLET_tty
#define APPLET_tty _BQ_DEFAULT
#endif
#ifndef APPLET_uname
#define APPLET_uname _BQ_DEFAULT
#endif
#ifndef APPLET_unexpand
#define APPLET_unexpand _BQ_DEFAULT
#endif
#ifndef APPLET_uniq
#define APPLET_uniq _BQ_DEFAULT
#endif
#ifndef APPLET_unlink
#define APPLET_unlink _BQ_DEFAULT
#endif
#ifndef APPLET_uptime
#define APPLET_uptime _BQ_DEFAULT
#endif
#ifndef APPLET_users
#define APPLET_users _BQ_DEFAULT
#endif
#ifndef APPLET_vdir
#define APPLET_vdir _BQ_DEFAULT
#endif
#ifndef APPLET_wc
#define APPLET_wc _BQ_DEFAULT
#endif
#ifndef APPLET_who
#define APPLET_who _BQ_DEFAULT
#endif
#ifndef APPLET_whoami
#define APPLET_whoami _BQ_DEFAULT
#endif
#ifndef APPLET_yes
#define APPLET_yes _BQ_DEFAULT
#endif

/* ==================================================================== */
/* Conditional-expansion helpers                                         */
/*                                                                       */
/* _BQ_IF(flag)(tokens) expands tokens when flag is 1, elides when 0.    */
/* Two-level indirection ensures the flag macro is fully expanded before  */
/* token-pasting selects _BQ_IF_0 or _BQ_IF_1.                          */
/* ==================================================================== */

#define _BQ_IF_0(...)
#define _BQ_IF_1(...) __VA_ARGS__
#define _BQ_IF2(n) _BQ_IF_##n
#define _BQ_IF(n) _BQ_IF2(n)

/* ==================================================================== */
/* Applet entries                                                        */
/*                                                                       */
/* Each APPLET(module, command, entry_func) invocation is guarded by     */
/* _BQ_IF(APPLET_<command>).  When applets.h is included with a          */
/* consumer-defined APPLET macro, only enabled entries expand.            */
/* ==================================================================== */

/* --- core (always included) --- */
APPLET(core, busyq, busyq_help_main)

/* --- curl --- */
_BQ_IF(APPLET_curl)(APPLET(curl, curl, curl_main))

/* --- jq --- */
_BQ_IF(APPLET_jq)(APPLET(jq, jq, jq_main))

/* --- ssl (requires BUSYQ_SSL) --- */
_BQ_IF(APPLET_ssl_client)(APPLET(ssl, ssl_client, ssl_client_main))

/* --- GNU coreutils (single-binary dispatch on argv[0]) --- */
_BQ_IF(APPLET_arch)(APPLET(coreutils, arch, coreutils_main))
_BQ_IF(APPLET_b2sum)(APPLET(coreutils, b2sum, coreutils_main))
_BQ_IF(APPLET_base32)(APPLET(coreutils, base32, coreutils_main))
_BQ_IF(APPLET_base64)(APPLET(coreutils, base64, coreutils_main))
_BQ_IF(APPLET_basename)(APPLET(coreutils, basename, coreutils_main))
_BQ_IF(APPLET_basenc)(APPLET(coreutils, basenc, coreutils_main))
_BQ_IF(APPLET_cat)(APPLET(coreutils, cat, coreutils_main))
_BQ_IF(APPLET_chcon)(APPLET(coreutils, chcon, coreutils_main))
_BQ_IF(APPLET_chgrp)(APPLET(coreutils, chgrp, coreutils_main))
_BQ_IF(APPLET_chmod)(APPLET(coreutils, chmod, coreutils_main))
_BQ_IF(APPLET_chown)(APPLET(coreutils, chown, coreutils_main))
_BQ_IF(APPLET_chroot)(APPLET(coreutils, chroot, coreutils_main))
_BQ_IF(APPLET_cksum)(APPLET(coreutils, cksum, coreutils_main))
_BQ_IF(APPLET_comm)(APPLET(coreutils, comm, coreutils_main))
_BQ_IF(APPLET_cp)(APPLET(coreutils, cp, coreutils_main))
_BQ_IF(APPLET_csplit)(APPLET(coreutils, csplit, coreutils_main))
_BQ_IF(APPLET_cut)(APPLET(coreutils, cut, coreutils_main))
_BQ_IF(APPLET_date)(APPLET(coreutils, date, coreutils_main))
_BQ_IF(APPLET_dd)(APPLET(coreutils, dd, coreutils_main))
_BQ_IF(APPLET_df)(APPLET(coreutils, df, coreutils_main))
_BQ_IF(APPLET_dir)(APPLET(coreutils, dir, coreutils_main))
_BQ_IF(APPLET_dircolors)(APPLET(coreutils, dircolors, coreutils_main))
_BQ_IF(APPLET_dirname)(APPLET(coreutils, dirname, coreutils_main))
_BQ_IF(APPLET_du)(APPLET(coreutils, du, coreutils_main))
_BQ_IF(APPLET_echo)(APPLET(coreutils, echo, coreutils_main))
_BQ_IF(APPLET_env)(APPLET(coreutils, env, coreutils_main))
_BQ_IF(APPLET_expand)(APPLET(coreutils, expand, coreutils_main))
_BQ_IF(APPLET_expr)(APPLET(coreutils, expr, coreutils_main))
_BQ_IF(APPLET_factor)(APPLET(coreutils, factor, coreutils_main))
_BQ_IF(APPLET_false)(APPLET(coreutils, false, coreutils_main))
_BQ_IF(APPLET_fmt)(APPLET(coreutils, fmt, coreutils_main))
_BQ_IF(APPLET_fold)(APPLET(coreutils, fold, coreutils_main))
_BQ_IF(APPLET_groups)(APPLET(coreutils, groups, coreutils_main))
_BQ_IF(APPLET_head)(APPLET(coreutils, head, coreutils_main))
_BQ_IF(APPLET_hostid)(APPLET(coreutils, hostid, coreutils_main))
_BQ_IF(APPLET_id)(APPLET(coreutils, id, coreutils_main))
_BQ_IF(APPLET_install)(APPLET(coreutils, install, coreutils_main))
_BQ_IF(APPLET_join)(APPLET(coreutils, join, coreutils_main))
_BQ_IF(APPLET_kill)(APPLET(coreutils, kill, coreutils_main))
_BQ_IF(APPLET_link)(APPLET(coreutils, link, coreutils_main))
_BQ_IF(APPLET_ln)(APPLET(coreutils, ln, coreutils_main))
_BQ_IF(APPLET_logname)(APPLET(coreutils, logname, coreutils_main))
_BQ_IF(APPLET_ls)(APPLET(coreutils, ls, coreutils_main))
_BQ_IF(APPLET_md5sum)(APPLET(coreutils, md5sum, coreutils_main))
_BQ_IF(APPLET_mkdir)(APPLET(coreutils, mkdir, coreutils_main))
_BQ_IF(APPLET_mkfifo)(APPLET(coreutils, mkfifo, coreutils_main))
_BQ_IF(APPLET_mknod)(APPLET(coreutils, mknod, coreutils_main))
_BQ_IF(APPLET_mktemp)(APPLET(coreutils, mktemp, coreutils_main))
_BQ_IF(APPLET_mv)(APPLET(coreutils, mv, coreutils_main))
_BQ_IF(APPLET_nice)(APPLET(coreutils, nice, coreutils_main))
_BQ_IF(APPLET_nl)(APPLET(coreutils, nl, coreutils_main))
_BQ_IF(APPLET_nohup)(APPLET(coreutils, nohup, coreutils_main))
_BQ_IF(APPLET_nproc)(APPLET(coreutils, nproc, coreutils_main))
_BQ_IF(APPLET_numfmt)(APPLET(coreutils, numfmt, coreutils_main))
_BQ_IF(APPLET_od)(APPLET(coreutils, od, coreutils_main))
_BQ_IF(APPLET_paste)(APPLET(coreutils, paste, coreutils_main))
_BQ_IF(APPLET_pathchk)(APPLET(coreutils, pathchk, coreutils_main))
_BQ_IF(APPLET_pinky)(APPLET(coreutils, pinky, coreutils_main))
_BQ_IF(APPLET_pr)(APPLET(coreutils, pr, coreutils_main))
_BQ_IF(APPLET_printenv)(APPLET(coreutils, printenv, coreutils_main))
_BQ_IF(APPLET_printf)(APPLET(coreutils, printf, coreutils_main))
_BQ_IF(APPLET_ptx)(APPLET(coreutils, ptx, coreutils_main))
_BQ_IF(APPLET_pwd)(APPLET(coreutils, pwd, coreutils_main))
_BQ_IF(APPLET_readlink)(APPLET(coreutils, readlink, coreutils_main))
_BQ_IF(APPLET_realpath)(APPLET(coreutils, realpath, coreutils_main))
_BQ_IF(APPLET_rm)(APPLET(coreutils, rm, coreutils_main))
_BQ_IF(APPLET_rmdir)(APPLET(coreutils, rmdir, coreutils_main))
_BQ_IF(APPLET_runcon)(APPLET(coreutils, runcon, coreutils_main))
_BQ_IF(APPLET_seq)(APPLET(coreutils, seq, coreutils_main))
_BQ_IF(APPLET_sha1sum)(APPLET(coreutils, sha1sum, coreutils_main))
_BQ_IF(APPLET_sha224sum)(APPLET(coreutils, sha224sum, coreutils_main))
_BQ_IF(APPLET_sha256sum)(APPLET(coreutils, sha256sum, coreutils_main))
_BQ_IF(APPLET_sha384sum)(APPLET(coreutils, sha384sum, coreutils_main))
_BQ_IF(APPLET_sha512sum)(APPLET(coreutils, sha512sum, coreutils_main))
_BQ_IF(APPLET_shred)(APPLET(coreutils, shred, coreutils_main))
_BQ_IF(APPLET_shuf)(APPLET(coreutils, shuf, coreutils_main))
_BQ_IF(APPLET_sleep)(APPLET(coreutils, sleep, coreutils_main))
_BQ_IF(APPLET_sort)(APPLET(coreutils, sort, coreutils_main))
_BQ_IF(APPLET_split)(APPLET(coreutils, split, coreutils_main))
_BQ_IF(APPLET_stat)(APPLET(coreutils, stat, coreutils_main))
_BQ_IF(APPLET_stty)(APPLET(coreutils, stty, coreutils_main))
_BQ_IF(APPLET_sum)(APPLET(coreutils, sum, coreutils_main))
_BQ_IF(APPLET_sync)(APPLET(coreutils, sync, coreutils_main))
_BQ_IF(APPLET_tac)(APPLET(coreutils, tac, coreutils_main))
_BQ_IF(APPLET_tail)(APPLET(coreutils, tail, coreutils_main))
_BQ_IF(APPLET_tee)(APPLET(coreutils, tee, coreutils_main))
_BQ_IF(APPLET_test)(APPLET(coreutils, test, coreutils_main))
/* [ is an alias for test — included when test is enabled */
_BQ_IF(APPLET_test)(APPLET(coreutils, [, coreutils_main))
_BQ_IF(APPLET_timeout)(APPLET(coreutils, timeout, coreutils_main))
_BQ_IF(APPLET_touch)(APPLET(coreutils, touch, coreutils_main))
_BQ_IF(APPLET_tr)(APPLET(coreutils, tr, coreutils_main))
_BQ_IF(APPLET_true)(APPLET(coreutils, true, coreutils_main))
_BQ_IF(APPLET_truncate)(APPLET(coreutils, truncate, coreutils_main))
_BQ_IF(APPLET_tsort)(APPLET(coreutils, tsort, coreutils_main))
_BQ_IF(APPLET_tty)(APPLET(coreutils, tty, coreutils_main))
_BQ_IF(APPLET_uname)(APPLET(coreutils, uname, coreutils_main))
_BQ_IF(APPLET_unexpand)(APPLET(coreutils, unexpand, coreutils_main))
_BQ_IF(APPLET_uniq)(APPLET(coreutils, uniq, coreutils_main))
_BQ_IF(APPLET_unlink)(APPLET(coreutils, unlink, coreutils_main))
_BQ_IF(APPLET_uptime)(APPLET(coreutils, uptime, coreutils_main))
_BQ_IF(APPLET_users)(APPLET(coreutils, users, coreutils_main))
_BQ_IF(APPLET_vdir)(APPLET(coreutils, vdir, coreutils_main))
_BQ_IF(APPLET_wc)(APPLET(coreutils, wc, coreutils_main))
_BQ_IF(APPLET_who)(APPLET(coreutils, who, coreutils_main))
_BQ_IF(APPLET_whoami)(APPLET(coreutils, whoami, coreutils_main))
_BQ_IF(APPLET_yes)(APPLET(coreutils, yes, coreutils_main))

/* ==================================================================== */
/* Cleanup                                                               */
/* ==================================================================== */

#ifdef _APPLETS_H_UNDEF_APPLET
#undef APPLET
#undef _APPLETS_H_UNDEF_APPLET
#endif
