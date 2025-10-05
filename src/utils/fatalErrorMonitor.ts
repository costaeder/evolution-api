import { Logger } from '@config/logger.config';

const FATAL_PATTERNS = [/connection closed/i, /websocket was closed/i, /sendermessagekeys/i];
const DEFAULT_THRESHOLD = 3;

let fatalErrorCounter = 0;
const logger = new Logger('FatalErrorMonitor');

function matchesFatalPattern(error: unknown): boolean {
  const message =
    error instanceof Error
      ? `${error.name}: ${error.message}`
      : typeof error === 'string'
        ? error
        : JSON.stringify(error);
  return FATAL_PATTERNS.some((pattern) => pattern.test(message));
}

export function trackFatalError(error: unknown): void {
  if (!matchesFatalPattern(error)) {
    return;
  }

  fatalErrorCounter += 1;
  const threshold = Number(process.env.FATAL_ERROR_THRESHOLD ?? DEFAULT_THRESHOLD);
  logger.warn(`Fatal error detected (${fatalErrorCounter}/${threshold}): ${String(error)}`);

  if (process.env.EXIT_ON_FATAL?.toLowerCase() === 'true' && fatalErrorCounter >= threshold) {
    logger.error('Fatal error threshold reached. Exiting process for supervised restart.');
    process.exit(1);
  }
}

export function resetFatalErrorCounter(reason?: string): void {
  if (fatalErrorCounter > 0) {
    logger.verbose(`Resetting fatal error counter${reason ? ` due to ${reason}` : ''}.`);
  }
  fatalErrorCounter = 0;
}
