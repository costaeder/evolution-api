export function extractNumber(jid: string): string {
  if (jid.includes('@lid')) {
    return jid;
  }
  return jid.split('@')[0];
}
