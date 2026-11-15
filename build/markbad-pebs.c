// markbad-pebs — пометить PEB как плохие (MEMSETBADBLOCK) и проверить (MEMGETBADBLOCK).
//
// Зачем: деградировавшие PEB (маркера bad не имели, умерли по данным/ECC)
// после прошивки с обходом остаются стёртыми и БЕЗ пометки. UBI считает их
// свободными и при wear-leveling запишет туда новые данные — деградация
// вернётся. Пометка через MTD-API ставит тот же маркер, что и заводской bad:
// UBI их больше не трогает, nanddump печатает "Skipping", scan-bad-pebs видит.
//
// ВАЖНО: пометка необратима (обычных средств снятия нет). Блок должен быть
// вне использования: лучше из RAM-initramfs (UBI не подключён), либо на
// живой плате — но только стёртые дыры, не блоки с данными UBI!
//
// Использование: markbad-pebs /dev/mtd6 511 512 [номера PEB от начала раздела...]
// Коды возврата: 0 — все помечены и подтверждены; 1 — была ошибка.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <mtd/mtd-user.h>

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: %s /dev/mtdN PEB [PEB...]  (номера от начала раздела)\n",
			argv[0]);
		return 1;
	}

	int fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
		return 1;
	}

	mtd_info_t mi;
	if (ioctl(fd, MEMGETINFO, &mi) < 0) {
		fprintf(stderr, "MEMGETINFO: %s\n", strerror(errno));
		return 1;
	}
	printf("# %s: size=0x%x erase=0x%x, всего PEB: %u\n",
	       argv[1], (unsigned)mi.size, (unsigned)mi.erasesize,
	       (unsigned)(mi.size / mi.erasesize));

	int rc = 0;
	for (int i = 2; i < argc; i++) {
		char *end;
		long peb = strtol(argv[i], &end, 10);
		if (*argv[i] == '\0' || *end != '\0' || peb < 0) {
			fprintf(stderr, "PEB '%s': не номер\n", argv[i]);
			rc = 1;
			continue;
		}
		loff_t off = (loff_t)peb * mi.erasesize;
		if (off + mi.erasesize > (loff_t)mi.size) {
			fprintf(stderr, "PEB %ld: за пределами %s (%u PEB)\n",
				peb, argv[1], (unsigned)(mi.size / mi.erasesize));
			rc = 1;
			continue;
		}

		// Уже помечен?
		int bad = ioctl(fd, MEMGETBADBLOCK, &off);
		if (bad < 0) {
			fprintf(stderr, "PEB %ld: MEMGETBADBLOCK: %s\n", peb, strerror(errno));
			rc = 1;
			continue;
		}
		if (bad) {
			printf("PEB %ld: уже bad, пропускаю\n", peb);
			continue;
		}

		if (ioctl(fd, MEMSETBADBLOCK, &off) < 0) {
			fprintf(stderr, "PEB %ld: MEMSETBADBLOCK: %s\n", peb, strerror(errno));
			rc = 1;
			continue;
		}
		// Подтверждение тем же методом, которым читает nanddump/UBI.
		bad = ioctl(fd, MEMGETBADBLOCK, &off);
		if (bad != 1) {
			fprintf(stderr, "PEB %ld: ПОСЛЕ пометки MEMGETBADBLOCK=%d — не подтвердилось!\n",
				peb, bad);
			rc = 1;
			continue;
		}
		printf("PEB %ld: помечен bad (offset 0x%llx), подтверждено\n",
		       peb, (unsigned long long)off);
	}

	close(fd);
	return rc;
}
