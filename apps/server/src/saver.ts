import { renameSync, writeFileSync } from "node:fs";

/**
 * Writes `get()` to `file` atomically (temp file, then rename, so a crash never leaves a truncated store).
 * save() coalesces a burst of changes into one write after `delayMs`; saveNow() writes at once, for money and for
 * anything a crash must not lose; flush() writes whatever is pending (called on exit).
 */
export function makeSaver(file: string, get: () => unknown, delayMs = 250) {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let dirty = false;
  const write = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    dirty = false;
    writeFileSync(`${file}.tmp`, JSON.stringify(get()));
    renameSync(`${file}.tmp`, file);
  };
  return {
    save() {
      dirty = true;
      timer ??= setTimeout(() => {
        timer = null;
        if (dirty) write();
      }, delayMs);
      timer.unref?.();
    },
    saveNow: write,
    flush() {
      if (dirty) write();
    },
  };
}
