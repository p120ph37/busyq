/*
 * Minimal reset/tset implementation for busyq.
 * Uses the public ncurses/terminfo API instead of ncurses internals.
 *
 * When invoked as "reset": resets terminal to sane defaults and sends
 * terminfo reset/init strings.
 * When invoked as "tset": same behavior (simplified from full tset).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <curses.h>
#include <term.h>

int tset_main(int argc, char **argv)
{
    struct termios tty;
    int err;

    /* Reset terminal line discipline to sane defaults (like "stty sane") */
    if (tcgetattr(STDIN_FILENO, &tty) == 0) {
        tty.c_iflag |= BRKINT | ICRNL | IMAXBEL;
        tty.c_iflag &= ~(IGNBRK | INLCR | IGNCR | IXOFF | IUCLC);
        tty.c_oflag |= OPOST | ONLCR;
        tty.c_oflag &= ~(OLCUC | OCRNL | ONOCR | ONLRET);
        tty.c_lflag |= ECHO | ECHOE | ECHOK | ECHOCTL | ECHOKE | ICANON | ISIG | IEXTEN;
        tty.c_lflag &= ~(ECHONL | NOFLSH | XCASE | TOSTOP | ECHOPRT);
        tty.c_cc[VMIN] = 1;
        tty.c_cc[VTIME] = 0;
        tcsetattr(STDIN_FILENO, TCSADRAIN, &tty);
    }

    /* Use terminfo to send reset/init sequences */
    if (setupterm(NULL, STDOUT_FILENO, &err) == OK) {
        const char *s;

        /* Send init strings (is1, is2, is3) */
        if ((s = tigetstr("is1")) != NULL && s != (char *)-1)
            putp(s);
        if ((s = tigetstr("is2")) != NULL && s != (char *)-1)
            putp(s);
        if ((s = tigetstr("is3")) != NULL && s != (char *)-1)
            putp(s);

        /* Send reset strings (rs1, rs2, rs3) */
        if ((s = tigetstr("rs1")) != NULL && s != (char *)-1)
            putp(s);
        if ((s = tigetstr("rs2")) != NULL && s != (char *)-1)
            putp(s);
        if ((s = tigetstr("rs3")) != NULL && s != (char *)-1)
            putp(s);

        /* Reset character attributes */
        if ((s = exit_attribute_mode) != NULL)
            putp(s);

        /* Clear screen */
        if ((s = clear_screen) != NULL)
            putp(s);

        fflush(stdout);
    }

    return 0;
}
