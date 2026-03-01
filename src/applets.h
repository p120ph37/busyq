/*
 * applets.h — Canonical applet registry for busyq (X-macro pattern)
 *
 * Single source of truth for all busyq applets.  Define APPLET(module,
 * command, entry_func) before including this file; the macro is invoked
 * once per active applet.
 *
 * IMPORTANT: Applet entries MUST be sorted lexicographically by command
 * name (the second APPLET argument).  This ordering enables O(log n)
 * binary search in the dispatch table.  A CI check enforces this — new
 * applets must be inserted at their correct sorted position.
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
 *   coreutils  - busyq-coreutils: libcoreutils (per-command entry points)
 *   gawk       - busyq-gawk: libgawk (awk, gawk)
 *   sed        - busyq-sed: libsed
 *   grep       - busyq-grep: libgrep (grep, egrep, fgrep)
 *   diffutils  - busyq-diffutils: libdiffutils (diff, cmp, diff3, sdiff)
 *   findutils  - busyq-findutils: libfindutils (find, xargs)
 *   ed         - busyq-ed: libed
 *   patch      - busyq-patch: libpatch
 *   tar        - busyq-tar: libtar
 *   gzip       - busyq-gzip: libgzip (gzip, gunzip, zcat)
 *   bzip2      - busyq-bzip2: libbzip2 (bzip2, bunzip2, bzcat)
 *   xz         - busyq-xz: libxz (xz, unxz, xzcat, lzma, unlzma, lzcat)
 *   cpio       - busyq-cpio: libcpio
 *   lzop       - busyq-lzop: liblzop
 *   zip        - busyq-zip: libzip + libunzip (zip, unzip)
 *   bc         - busyq-bc: libbc (bc, dc)
 *   less       - busyq-less: libless
 *   strings    - busyq-strings: libstrings
 *   time       - busyq-time: libtime
 *   dos2unix   - busyq-dos2unix: libdos2unix (dos2unix, unix2dos)
 *   sharutils  - busyq-sharutils: libsharutils (uuencode, uudecode)
 *   reset      - busyq-reset: libtset (reset, tset)
 *   which      - busyq-which: libwhich
 *   wget       - busyq-wget: libwget
 *   netcat     - busyq-netcat: libnc (nc)
 *   iputils    - busyq-iputils: libping (ping)
 *   hostname   - busyq-hostname: libhostname
 *   whois      - busyq-whois: libwhois
 *   procps     - busyq-procps: libprocps (ps, free, top, pgrep, etc.)
 *   psmisc     - busyq-psmisc: libpsmisc (killall, fuser, pstree)
 *   lsof       - busyq-lsof: liblsof
 */

/* ---- If APPLET was not defined by the includer, provide a no-op ---- */
#ifndef APPLET
#define APPLET(module, command, entry_func)
#define _APPLETS_H_UNDEF_APPLET
#endif

/* ==================================================================== */
/* Applet enable/disable defaults (sorted by APPLET_ macro name)         */
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
#ifndef APPLET_bc
#define APPLET_bc _BQ_DEFAULT
#endif
#ifndef APPLET_busyq
#define APPLET_busyq 1
#endif
#ifndef APPLET_bzip2
#define APPLET_bzip2 _BQ_DEFAULT
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
#ifndef APPLET_cmp
#define APPLET_cmp _BQ_DEFAULT
#endif
#ifndef APPLET_comm
#define APPLET_comm _BQ_DEFAULT
#endif
#ifndef APPLET_cp
#define APPLET_cp _BQ_DEFAULT
#endif
#ifndef APPLET_cpio
#define APPLET_cpio _BQ_DEFAULT
#endif
#ifndef APPLET_csplit
#define APPLET_csplit _BQ_DEFAULT
#endif
#ifndef APPLET_curl
#define APPLET_curl _BQ_DEFAULT
#endif
#ifndef APPLET_cut
#define APPLET_cut _BQ_DEFAULT
#endif
#ifndef APPLET_date
#define APPLET_date _BQ_DEFAULT
#endif
#ifndef APPLET_dc
#define APPLET_dc _BQ_DEFAULT
#endif
#ifndef APPLET_dd
#define APPLET_dd _BQ_DEFAULT
#endif
#ifndef APPLET_df
#define APPLET_df _BQ_DEFAULT
#endif
#ifndef APPLET_diff
#define APPLET_diff _BQ_DEFAULT
#endif
#ifndef APPLET_diff3
#define APPLET_diff3 _BQ_DEFAULT
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
#ifndef APPLET_dos2unix
#define APPLET_dos2unix _BQ_DEFAULT
#endif
#ifndef APPLET_du
#define APPLET_du _BQ_DEFAULT
#endif
#ifndef APPLET_echo
#define APPLET_echo _BQ_DEFAULT
#endif
#ifndef APPLET_ed
#define APPLET_ed _BQ_DEFAULT
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
#ifndef APPLET_find
#define APPLET_find _BQ_DEFAULT
#endif
#ifndef APPLET_fmt
#define APPLET_fmt _BQ_DEFAULT
#endif
#ifndef APPLET_fold
#define APPLET_fold _BQ_DEFAULT
#endif
#ifndef APPLET_free
#define APPLET_free _BQ_DEFAULT
#endif
#ifndef APPLET_fuser
#define APPLET_fuser _BQ_DEFAULT
#endif
#ifndef APPLET_gawk
#define APPLET_gawk _BQ_DEFAULT
#endif
#ifndef APPLET_grep
#define APPLET_grep _BQ_DEFAULT
#endif
#ifndef APPLET_groups
#define APPLET_groups _BQ_DEFAULT
#endif
#ifndef APPLET_gzip
#define APPLET_gzip _BQ_DEFAULT
#endif
#ifndef APPLET_head
#define APPLET_head _BQ_DEFAULT
#endif
#ifndef APPLET_hostid
#define APPLET_hostid _BQ_DEFAULT
#endif
#ifndef APPLET_hostname
#define APPLET_hostname _BQ_DEFAULT
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
#ifndef APPLET_jq
#define APPLET_jq _BQ_DEFAULT
#endif
#ifndef APPLET_kill
#define APPLET_kill _BQ_DEFAULT
#endif
#ifndef APPLET_killall
#define APPLET_killall _BQ_DEFAULT
#endif
#ifndef APPLET_less
#define APPLET_less _BQ_DEFAULT
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
#ifndef APPLET_lsof
#define APPLET_lsof _BQ_DEFAULT
#endif
#ifndef APPLET_lzop
#define APPLET_lzop _BQ_DEFAULT
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
#ifndef APPLET_nc
#define APPLET_nc _BQ_DEFAULT
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
#ifndef APPLET_patch
#define APPLET_patch _BQ_DEFAULT
#endif
#ifndef APPLET_pathchk
#define APPLET_pathchk _BQ_DEFAULT
#endif
#ifndef APPLET_pgrep
#define APPLET_pgrep _BQ_DEFAULT
#endif
#ifndef APPLET_pidof
#define APPLET_pidof _BQ_DEFAULT
#endif
#ifndef APPLET_ping
#define APPLET_ping _BQ_DEFAULT
#endif
#ifndef APPLET_pinky
#define APPLET_pinky _BQ_DEFAULT
#endif
#ifndef APPLET_pmap
#define APPLET_pmap _BQ_DEFAULT
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
#ifndef APPLET_ps
#define APPLET_ps _BQ_DEFAULT
#endif
#ifndef APPLET_pstree
#define APPLET_pstree _BQ_DEFAULT
#endif
#ifndef APPLET_ptx
#define APPLET_ptx _BQ_DEFAULT
#endif
#ifndef APPLET_pwd
#define APPLET_pwd _BQ_DEFAULT
#endif
#ifndef APPLET_pwdx
#define APPLET_pwdx _BQ_DEFAULT
#endif
#ifndef APPLET_readlink
#define APPLET_readlink _BQ_DEFAULT
#endif
#ifndef APPLET_realpath
#define APPLET_realpath _BQ_DEFAULT
#endif
#ifndef APPLET_reset
#define APPLET_reset _BQ_DEFAULT
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
#ifndef APPLET_sdiff
#define APPLET_sdiff _BQ_DEFAULT
#endif
#ifndef APPLET_sed
#define APPLET_sed _BQ_DEFAULT
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
#ifndef APPLET_slabtop
#define APPLET_slabtop _BQ_DEFAULT
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
#ifndef APPLET_ssl_client
#  if BUSYQ_SSL
#    define APPLET_ssl_client _BQ_DEFAULT
#  else
#    define APPLET_ssl_client 0
#  endif
#endif
#ifndef APPLET_stat
#define APPLET_stat _BQ_DEFAULT
#endif
#ifndef APPLET_strings
#define APPLET_strings _BQ_DEFAULT
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
#ifndef APPLET_sysctl
#define APPLET_sysctl _BQ_DEFAULT
#endif
#ifndef APPLET_tac
#define APPLET_tac _BQ_DEFAULT
#endif
#ifndef APPLET_tail
#define APPLET_tail _BQ_DEFAULT
#endif
#ifndef APPLET_tar
#define APPLET_tar _BQ_DEFAULT
#endif
#ifndef APPLET_tee
#define APPLET_tee _BQ_DEFAULT
#endif
#ifndef APPLET_test
#define APPLET_test _BQ_DEFAULT
#endif
#ifndef APPLET_time
#define APPLET_time _BQ_DEFAULT
#endif
#ifndef APPLET_timeout
#define APPLET_timeout _BQ_DEFAULT
#endif
#ifndef APPLET_tload
#define APPLET_tload _BQ_DEFAULT
#endif
#ifndef APPLET_top
#define APPLET_top _BQ_DEFAULT
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
#ifndef APPLET_unzip
#define APPLET_unzip _BQ_DEFAULT
#endif
#ifndef APPLET_uptime
#define APPLET_uptime _BQ_DEFAULT
#endif
#ifndef APPLET_users
#define APPLET_users _BQ_DEFAULT
#endif
#ifndef APPLET_uudecode
#define APPLET_uudecode _BQ_DEFAULT
#endif
#ifndef APPLET_uuencode
#define APPLET_uuencode _BQ_DEFAULT
#endif
#ifndef APPLET_vdir
#define APPLET_vdir _BQ_DEFAULT
#endif
#ifndef APPLET_vmstat
#define APPLET_vmstat _BQ_DEFAULT
#endif
#ifndef APPLET_w
#define APPLET_w _BQ_DEFAULT
#endif
#ifndef APPLET_watch
#define APPLET_watch _BQ_DEFAULT
#endif
#ifndef APPLET_wc
#define APPLET_wc _BQ_DEFAULT
#endif
#ifndef APPLET_wget
#define APPLET_wget _BQ_DEFAULT
#endif
#ifndef APPLET_which
#define APPLET_which _BQ_DEFAULT
#endif
#ifndef APPLET_who
#define APPLET_who _BQ_DEFAULT
#endif
#ifndef APPLET_whoami
#define APPLET_whoami _BQ_DEFAULT
#endif
#ifndef APPLET_whois
#define APPLET_whois _BQ_DEFAULT
#endif
#ifndef APPLET_xargs
#define APPLET_xargs _BQ_DEFAULT
#endif
#ifndef APPLET_xz
#define APPLET_xz _BQ_DEFAULT
#endif
#ifndef APPLET_yes
#define APPLET_yes _BQ_DEFAULT
#endif
#ifndef APPLET_zip
#define APPLET_zip _BQ_DEFAULT
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
/* Applet entries — sorted lexicographically by command name             */
/*                                                                       */
/* This ordering is REQUIRED for binary search dispatch.  Insert new     */
/* applets at their correct sorted position.  CI enforces this.          */
/*                                                                       */
/* Each APPLET(module, command, entry_func) invocation is guarded by     */
/* _BQ_IF(APPLET_<flag>).  When applets.h is included with a            */
/* consumer-defined APPLET macro, only enabled entries expand.            */
/*                                                                       */
/* Coreutils entry points: single_binary_main_TOOL() from               */
/* --enable-single-binary build.  Special names:                         */
/*   [       -> single_binary_main__        (bracket sanitized to _)     */
/*   install -> single_binary_main_ginstall (avoids make target clash)   */
/* ==================================================================== */

_BQ_IF(APPLET_test)(APPLET(coreutils, [, single_binary_main__))
_BQ_IF(APPLET_arch)(APPLET(coreutils, arch, single_binary_main_arch))
_BQ_IF(APPLET_gawk)(APPLET(gawk, awk, gawk_main))
_BQ_IF(APPLET_b2sum)(APPLET(coreutils, b2sum, single_binary_main_b2sum))
_BQ_IF(APPLET_base32)(APPLET(coreutils, base32, single_binary_main_base32))
_BQ_IF(APPLET_base64)(APPLET(coreutils, base64, single_binary_main_base64))
_BQ_IF(APPLET_basename)(APPLET(coreutils, basename, single_binary_main_basename))
_BQ_IF(APPLET_basenc)(APPLET(coreutils, basenc, single_binary_main_basenc))
_BQ_IF(APPLET_bc)(APPLET(bc, bc, bc_main))
_BQ_IF(APPLET_bzip2)(APPLET(bzip2, bunzip2, bzip2_main))
_BQ_IF(APPLET_busyq)(APPLET(core, busyq, busyq_help_main))
_BQ_IF(APPLET_bzip2)(APPLET(bzip2, bzcat, bzip2_main))
_BQ_IF(APPLET_bzip2)(APPLET(bzip2, bzip2, bzip2_main))
_BQ_IF(APPLET_cat)(APPLET(coreutils, cat, single_binary_main_cat))
_BQ_IF(APPLET_chcon)(APPLET(coreutils, chcon, single_binary_main_chcon))
_BQ_IF(APPLET_chgrp)(APPLET(coreutils, chgrp, single_binary_main_chgrp))
_BQ_IF(APPLET_chmod)(APPLET(coreutils, chmod, single_binary_main_chmod))
_BQ_IF(APPLET_chown)(APPLET(coreutils, chown, single_binary_main_chown))
_BQ_IF(APPLET_chroot)(APPLET(coreutils, chroot, single_binary_main_chroot))
_BQ_IF(APPLET_cksum)(APPLET(coreutils, cksum, single_binary_main_cksum))
_BQ_IF(APPLET_cmp)(APPLET(diffutils, cmp, cmp_main))
_BQ_IF(APPLET_comm)(APPLET(coreutils, comm, single_binary_main_comm))
_BQ_IF(APPLET_cp)(APPLET(coreutils, cp, single_binary_main_cp))
_BQ_IF(APPLET_cpio)(APPLET(cpio, cpio, cpio_main))
_BQ_IF(APPLET_csplit)(APPLET(coreutils, csplit, single_binary_main_csplit))
_BQ_IF(APPLET_curl)(APPLET(curl, curl, curl_main))
_BQ_IF(APPLET_cut)(APPLET(coreutils, cut, single_binary_main_cut))
_BQ_IF(APPLET_date)(APPLET(coreutils, date, single_binary_main_date))
_BQ_IF(APPLET_dc)(APPLET(bc, dc, dc_main))
_BQ_IF(APPLET_dd)(APPLET(coreutils, dd, single_binary_main_dd))
_BQ_IF(APPLET_df)(APPLET(coreutils, df, single_binary_main_df))
_BQ_IF(APPLET_diff)(APPLET(diffutils, diff, diff_main))
_BQ_IF(APPLET_diff3)(APPLET(diffutils, diff3, diff3_main))
_BQ_IF(APPLET_dir)(APPLET(coreutils, dir, single_binary_main_dir))
_BQ_IF(APPLET_dircolors)(APPLET(coreutils, dircolors, single_binary_main_dircolors))
_BQ_IF(APPLET_dirname)(APPLET(coreutils, dirname, single_binary_main_dirname))
_BQ_IF(APPLET_dos2unix)(APPLET(dos2unix, dos2unix, dos2unix_main))
_BQ_IF(APPLET_du)(APPLET(coreutils, du, single_binary_main_du))
_BQ_IF(APPLET_echo)(APPLET(coreutils, echo, single_binary_main_echo))
_BQ_IF(APPLET_ed)(APPLET(ed, ed, ed_main))
_BQ_IF(APPLET_grep)(APPLET(grep, egrep, grep_main))
_BQ_IF(APPLET_env)(APPLET(coreutils, env, single_binary_main_env))
_BQ_IF(APPLET_expand)(APPLET(coreutils, expand, single_binary_main_expand))
_BQ_IF(APPLET_expr)(APPLET(coreutils, expr, single_binary_main_expr))
_BQ_IF(APPLET_factor)(APPLET(coreutils, factor, single_binary_main_factor))
_BQ_IF(APPLET_false)(APPLET(coreutils, false, single_binary_main_false))
_BQ_IF(APPLET_grep)(APPLET(grep, fgrep, grep_main))
_BQ_IF(APPLET_find)(APPLET(findutils, find, find_main))
_BQ_IF(APPLET_fmt)(APPLET(coreutils, fmt, single_binary_main_fmt))
_BQ_IF(APPLET_fold)(APPLET(coreutils, fold, single_binary_main_fold))
_BQ_IF(APPLET_free)(APPLET(procps, free, free_main))
_BQ_IF(APPLET_fuser)(APPLET(psmisc, fuser, fuser_main))
_BQ_IF(APPLET_gawk)(APPLET(gawk, gawk, gawk_main))
_BQ_IF(APPLET_grep)(APPLET(grep, grep, grep_main))
_BQ_IF(APPLET_groups)(APPLET(coreutils, groups, single_binary_main_groups))
_BQ_IF(APPLET_gzip)(APPLET(gzip, gunzip, gzip_main))
_BQ_IF(APPLET_gzip)(APPLET(gzip, gzip, gzip_main))
_BQ_IF(APPLET_head)(APPLET(coreutils, head, single_binary_main_head))
_BQ_IF(APPLET_hostid)(APPLET(coreutils, hostid, single_binary_main_hostid))
_BQ_IF(APPLET_hostname)(APPLET(hostname, hostname, hostname_main))
_BQ_IF(APPLET_id)(APPLET(coreutils, id, single_binary_main_id))
_BQ_IF(APPLET_install)(APPLET(coreutils, install, single_binary_main_ginstall))
_BQ_IF(APPLET_join)(APPLET(coreutils, join, single_binary_main_join))
_BQ_IF(APPLET_jq)(APPLET(jq, jq, jq_main))
_BQ_IF(APPLET_kill)(APPLET(coreutils, kill, single_binary_main_kill))
_BQ_IF(APPLET_killall)(APPLET(psmisc, killall, killall_main))
_BQ_IF(APPLET_less)(APPLET(less, less, less_main))
_BQ_IF(APPLET_link)(APPLET(coreutils, link, single_binary_main_link))
_BQ_IF(APPLET_ln)(APPLET(coreutils, ln, single_binary_main_ln))
_BQ_IF(APPLET_logname)(APPLET(coreutils, logname, single_binary_main_logname))
_BQ_IF(APPLET_ls)(APPLET(coreutils, ls, single_binary_main_ls))
_BQ_IF(APPLET_lsof)(APPLET(lsof, lsof, lsof_main))
_BQ_IF(APPLET_xz)(APPLET(xz, lzcat, xz_main))
_BQ_IF(APPLET_xz)(APPLET(xz, lzma, xz_main))
_BQ_IF(APPLET_lzop)(APPLET(lzop, lzop, lzop_main))
_BQ_IF(APPLET_md5sum)(APPLET(coreutils, md5sum, single_binary_main_md5sum))
_BQ_IF(APPLET_mkdir)(APPLET(coreutils, mkdir, single_binary_main_mkdir))
_BQ_IF(APPLET_mkfifo)(APPLET(coreutils, mkfifo, single_binary_main_mkfifo))
_BQ_IF(APPLET_mknod)(APPLET(coreutils, mknod, single_binary_main_mknod))
_BQ_IF(APPLET_mktemp)(APPLET(coreutils, mktemp, single_binary_main_mktemp))
_BQ_IF(APPLET_mv)(APPLET(coreutils, mv, single_binary_main_mv))
_BQ_IF(APPLET_nc)(APPLET(netcat, nc, nc_main))
_BQ_IF(APPLET_nice)(APPLET(coreutils, nice, single_binary_main_nice))
_BQ_IF(APPLET_nl)(APPLET(coreutils, nl, single_binary_main_nl))
_BQ_IF(APPLET_nohup)(APPLET(coreutils, nohup, single_binary_main_nohup))
_BQ_IF(APPLET_nproc)(APPLET(coreutils, nproc, single_binary_main_nproc))
_BQ_IF(APPLET_numfmt)(APPLET(coreutils, numfmt, single_binary_main_numfmt))
_BQ_IF(APPLET_od)(APPLET(coreutils, od, single_binary_main_od))
_BQ_IF(APPLET_paste)(APPLET(coreutils, paste, single_binary_main_paste))
_BQ_IF(APPLET_patch)(APPLET(patch, patch, patch_main))
_BQ_IF(APPLET_pathchk)(APPLET(coreutils, pathchk, single_binary_main_pathchk))
_BQ_IF(APPLET_pgrep)(APPLET(procps, pgrep, pgrep_main))
_BQ_IF(APPLET_pidof)(APPLET(procps, pidof, pidof_main))
_BQ_IF(APPLET_ping)(APPLET(iputils, ping, ping_main))
_BQ_IF(APPLET_pinky)(APPLET(coreutils, pinky, single_binary_main_pinky))
_BQ_IF(APPLET_pgrep)(APPLET(procps, pkill, pgrep_main))
_BQ_IF(APPLET_pmap)(APPLET(procps, pmap, pmap_main))
_BQ_IF(APPLET_pr)(APPLET(coreutils, pr, single_binary_main_pr))
_BQ_IF(APPLET_printenv)(APPLET(coreutils, printenv, single_binary_main_printenv))
_BQ_IF(APPLET_printf)(APPLET(coreutils, printf, single_binary_main_printf))
_BQ_IF(APPLET_ps)(APPLET(procps, ps, ps_main))
_BQ_IF(APPLET_pstree)(APPLET(psmisc, pstree, pstree_main))
_BQ_IF(APPLET_ptx)(APPLET(coreutils, ptx, single_binary_main_ptx))
_BQ_IF(APPLET_pwd)(APPLET(coreutils, pwd, single_binary_main_pwd))
_BQ_IF(APPLET_pwdx)(APPLET(procps, pwdx, pwdx_main))
_BQ_IF(APPLET_readlink)(APPLET(coreutils, readlink, single_binary_main_readlink))
_BQ_IF(APPLET_realpath)(APPLET(coreutils, realpath, single_binary_main_realpath))
_BQ_IF(APPLET_reset)(APPLET(reset, reset, tset_main))
_BQ_IF(APPLET_rm)(APPLET(coreutils, rm, single_binary_main_rm))
_BQ_IF(APPLET_rmdir)(APPLET(coreutils, rmdir, single_binary_main_rmdir))
_BQ_IF(APPLET_runcon)(APPLET(coreutils, runcon, single_binary_main_runcon))
_BQ_IF(APPLET_sdiff)(APPLET(diffutils, sdiff, sdiff_main))
_BQ_IF(APPLET_sed)(APPLET(sed, sed, sed_main))
_BQ_IF(APPLET_seq)(APPLET(coreutils, seq, single_binary_main_seq))
_BQ_IF(APPLET_sha1sum)(APPLET(coreutils, sha1sum, single_binary_main_sha1sum))
_BQ_IF(APPLET_sha224sum)(APPLET(coreutils, sha224sum, single_binary_main_sha224sum))
_BQ_IF(APPLET_sha256sum)(APPLET(coreutils, sha256sum, single_binary_main_sha256sum))
_BQ_IF(APPLET_sha384sum)(APPLET(coreutils, sha384sum, single_binary_main_sha384sum))
_BQ_IF(APPLET_sha512sum)(APPLET(coreutils, sha512sum, single_binary_main_sha512sum))
_BQ_IF(APPLET_shred)(APPLET(coreutils, shred, single_binary_main_shred))
_BQ_IF(APPLET_shuf)(APPLET(coreutils, shuf, single_binary_main_shuf))
_BQ_IF(APPLET_slabtop)(APPLET(procps, slabtop, slabtop_main))
_BQ_IF(APPLET_sleep)(APPLET(coreutils, sleep, single_binary_main_sleep))
_BQ_IF(APPLET_sort)(APPLET(coreutils, sort, single_binary_main_sort))
_BQ_IF(APPLET_split)(APPLET(coreutils, split, single_binary_main_split))
_BQ_IF(APPLET_ssl_client)(APPLET(ssl, ssl_client, ssl_client_main))
_BQ_IF(APPLET_stat)(APPLET(coreutils, stat, single_binary_main_stat))
_BQ_IF(APPLET_strings)(APPLET(strings, strings, strings_main))
_BQ_IF(APPLET_stty)(APPLET(coreutils, stty, single_binary_main_stty))
_BQ_IF(APPLET_sum)(APPLET(coreutils, sum, single_binary_main_sum))
_BQ_IF(APPLET_sync)(APPLET(coreutils, sync, single_binary_main_sync))
_BQ_IF(APPLET_sysctl)(APPLET(procps, sysctl, sysctl_main))
_BQ_IF(APPLET_tac)(APPLET(coreutils, tac, single_binary_main_tac))
_BQ_IF(APPLET_tail)(APPLET(coreutils, tail, single_binary_main_tail))
_BQ_IF(APPLET_tar)(APPLET(tar, tar, tar_main))
_BQ_IF(APPLET_tee)(APPLET(coreutils, tee, single_binary_main_tee))
_BQ_IF(APPLET_test)(APPLET(coreutils, test, single_binary_main_test))
_BQ_IF(APPLET_time)(APPLET(time, time, time_main))
_BQ_IF(APPLET_timeout)(APPLET(coreutils, timeout, single_binary_main_timeout))
_BQ_IF(APPLET_tload)(APPLET(procps, tload, tload_main))
_BQ_IF(APPLET_top)(APPLET(procps, top, top_main))
_BQ_IF(APPLET_touch)(APPLET(coreutils, touch, single_binary_main_touch))
_BQ_IF(APPLET_tr)(APPLET(coreutils, tr, single_binary_main_tr))
_BQ_IF(APPLET_true)(APPLET(coreutils, true, single_binary_main_true))
_BQ_IF(APPLET_truncate)(APPLET(coreutils, truncate, single_binary_main_truncate))
_BQ_IF(APPLET_reset)(APPLET(reset, tset, tset_main))
_BQ_IF(APPLET_tsort)(APPLET(coreutils, tsort, single_binary_main_tsort))
_BQ_IF(APPLET_tty)(APPLET(coreutils, tty, single_binary_main_tty))
_BQ_IF(APPLET_uname)(APPLET(coreutils, uname, single_binary_main_uname))
_BQ_IF(APPLET_unexpand)(APPLET(coreutils, unexpand, single_binary_main_unexpand))
_BQ_IF(APPLET_uniq)(APPLET(coreutils, uniq, single_binary_main_uniq))
_BQ_IF(APPLET_dos2unix)(APPLET(dos2unix, unix2dos, dos2unix_main))
_BQ_IF(APPLET_unlink)(APPLET(coreutils, unlink, single_binary_main_unlink))
_BQ_IF(APPLET_xz)(APPLET(xz, unlzma, xz_main))
_BQ_IF(APPLET_xz)(APPLET(xz, unxz, xz_main))
_BQ_IF(APPLET_unzip)(APPLET(zip, unzip, unzip_main))
_BQ_IF(APPLET_uptime)(APPLET(coreutils, uptime, single_binary_main_uptime))
_BQ_IF(APPLET_users)(APPLET(coreutils, users, single_binary_main_users))
_BQ_IF(APPLET_uudecode)(APPLET(sharutils, uudecode, uudecode_main))
_BQ_IF(APPLET_uuencode)(APPLET(sharutils, uuencode, uuencode_main))
_BQ_IF(APPLET_vdir)(APPLET(coreutils, vdir, single_binary_main_vdir))
_BQ_IF(APPLET_vmstat)(APPLET(procps, vmstat, vmstat_main))
_BQ_IF(APPLET_w)(APPLET(procps, w, w_main))
_BQ_IF(APPLET_watch)(APPLET(procps, watch, watch_main))
_BQ_IF(APPLET_wc)(APPLET(coreutils, wc, single_binary_main_wc))
_BQ_IF(APPLET_wget)(APPLET(wget, wget, wget_main))
_BQ_IF(APPLET_which)(APPLET(which, which, which_main))
_BQ_IF(APPLET_who)(APPLET(coreutils, who, single_binary_main_who))
_BQ_IF(APPLET_whoami)(APPLET(coreutils, whoami, single_binary_main_whoami))
_BQ_IF(APPLET_whois)(APPLET(whois, whois, whois_main))
_BQ_IF(APPLET_xargs)(APPLET(findutils, xargs, xargs_main))
_BQ_IF(APPLET_xz)(APPLET(xz, xz, xz_main))
_BQ_IF(APPLET_xz)(APPLET(xz, xzcat, xz_main))
_BQ_IF(APPLET_yes)(APPLET(coreutils, yes, single_binary_main_yes))
_BQ_IF(APPLET_gzip)(APPLET(gzip, zcat, gzip_main))
_BQ_IF(APPLET_zip)(APPLET(zip, zip, zip_main))

/* ==================================================================== */
/* Cleanup                                                               */
/* ==================================================================== */

#ifdef _APPLETS_H_UNDEF_APPLET
#undef APPLET
#undef _APPLETS_H_UNDEF_APPLET
#endif
