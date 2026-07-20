import { describe, expect, it } from "vitest";
import { retryTransientFilesystemOperation } from "../server/lib/filesystem.js";

function filesystemError(code: string): NodeJS.ErrnoException {
  const error = new Error(
    `filesystem failure: ${code}`,
  ) as NodeJS.ErrnoException;
  error.code = code;
  return error;
}

describe("transient filesystem retry", () => {
  it("retries a bounded Windows sharing violation", async () => {
    let attempts = 0;

    await retryTransientFilesystemOperation(() => {
      attempts += 1;
      if (attempts === 1) {
        return Promise.reject(filesystemError("EPERM"));
      }
      return Promise.resolve();
    }, [0]);

    expect(attempts).toBe(2);
  });

  it("does not retry a permanent filesystem error", async () => {
    let attempts = 0;
    const operation = retryTransientFilesystemOperation(() => {
      attempts += 1;
      return Promise.reject(filesystemError("EINVAL"));
    }, [0, 0]);

    await expect(operation).rejects.toThrow("EINVAL");
    expect(attempts).toBe(1);
  });
});
