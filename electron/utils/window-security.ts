function normalizedPathname(pathname: string): string {
  return pathname.length > 1 ? pathname.replace(/\/+$/u, "") : pathname;
}

export function isAllowedRendererNavigation(
  targetUrl: string,
  rendererEntryUrl: string,
): boolean {
  try {
    const target = new URL(targetUrl);
    const entry = new URL(rendererEntryUrl);
    return (
      target.protocol === entry.protocol &&
      target.host === entry.host &&
      normalizedPathname(target.pathname) === normalizedPathname(entry.pathname)
    );
  } catch {
    return false;
  }
}
