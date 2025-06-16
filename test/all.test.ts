import { ChatwootService } from '../src/api/integrations/chatbot/chatwoot/services/chatwoot.service';

function assertEqual(actual: any, expected: any, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}. Expected ${expected} but got ${actual}`);
  }
}

// Test with identifier available
const bodyIdentifier = {
  meta: { sender: { identifier: '5511999999999@lid', phone_number: '+5511999999999' } },
  conversation: { meta: { sender: { identifier: 'other', phone_number: '+1' } } },
};
assertEqual(ChatwootService.extractChatId(bodyIdentifier), '5511999999999@lid', 'identifier priority');

// Test with phone_number containing @lid
const bodyPhoneLid = {
  conversation: { meta: { sender: { phone_number: '5511999998888@lid' } } },
};
assertEqual(ChatwootService.extractChatId(bodyPhoneLid), '5511999998888@lid', 'phone_number with @lid');

console.log('All tests passed');
