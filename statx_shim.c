#define _GNU_SOURCE
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/stat.h>

int statx(int dirfd, const char *pathname, unsigned int flags,
          unsigned int mask, struct statx *buf) {
    return syscall(__NR_statx, dirfd, pathname, flags, mask, buf);
}
