if (!process.contextIsolated || !process.sandboxed) {
  throw new Error(
    "DNF Patch Studio requires context isolation and renderer sandboxing.",
  );
}

export {};
