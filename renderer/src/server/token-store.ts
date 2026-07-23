let accessToken: string | undefined;

export function getAccessToken(): string | undefined {
  return accessToken;
}

export function setAccessToken(value: string | undefined): void {
  accessToken = value;
}
