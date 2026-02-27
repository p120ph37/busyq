/* strings.c - minimal standalone strings implementation for busyq */
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>

static int min_len = 4;

static void scan_file(FILE *fp) {
    int c;
    char *buf = NULL;
    size_t len = 0, cap = 0;

    while ((c = fgetc(fp)) != EOF) {
        if (c >= 32 && c < 127) {
            if (len >= cap) {
                cap = cap ? cap * 2 : 256;
                buf = realloc(buf, cap);
                if (!buf) exit(1);
            }
            buf[len++] = c;
        } else {
            if (len >= (size_t)min_len) {
                fwrite(buf, 1, len, stdout);
                putchar('\n');
            }
            len = 0;
        }
    }
    if (len >= (size_t)min_len) {
        fwrite(buf, 1, len, stdout);
        putchar('\n');
    }
    free(buf);
}

int main(int argc, char **argv) {
    int i;
    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1] == 'n' && argv[i][2] == '\0' && i + 1 < argc) {
            min_len = atoi(argv[++i]);
            if (min_len < 1) min_len = 4;
        } else if (argv[i][0] == '-' && argv[i][1] >= '0' && argv[i][1] <= '9') {
            min_len = atoi(argv[i] + 1);
            if (min_len < 1) min_len = 4;
        }
    }

    int found_file = 0;
    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            if (argv[i][1] == 'n') i++;
            continue;
        }
        found_file = 1;
        FILE *fp = fopen(argv[i], "rb");
        if (!fp) { perror(argv[i]); continue; }
        scan_file(fp);
        fclose(fp);
    }
    if (!found_file) scan_file(stdin);
    return 0;
}
