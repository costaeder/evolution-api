import { trackFatalError } from '@utils/fatalErrorMonitor';

import { Logger } from './logger.config';

export function onUnexpectedError() {
  process.on('uncaughtException', (error, origin) => {
    const logger = new Logger('uncaughtException');
    logger.error({
      origin,
      stderr: process.stderr.fd,
      error,
    });
    trackFatalError(error);
  });

  process.on('unhandledRejection', (error, origin) => {
    const logger = new Logger('unhandledRejection');
    logger.error({
      origin,
      stderr: process.stderr.fd,
    });
    logger.error(error);
    trackFatalError(error);
  });
}
