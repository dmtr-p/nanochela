import { Channel, NewMessage } from './types.js';

/**
 * Escapes characters that are significant in XML so the string can be safely embedded in XML content.
 *
 * @param s - The input string to escape; if `s` is falsy, it is treated as an empty string.
 * @returns The input with `&`, `<`, `>`, and `"` replaced by their corresponding XML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`); returns an empty string when the input is falsy.
 */
export function escapeXml(s: string): string {
  if (!s) return '';
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Formats an array of messages into an XML-like string suitable for transmission or logging.
 *
 * Each input message becomes a `<message>` element with `sender` and `time` attributes. If a message has a `reply_context`,
 * a `<reply>` child is included with the original reply sender and either the reply text or the literal string `[non-text message]`.
 * All message text and sender names are escaped for XML safety.
 *
 * @param messages - Array of messages to format
 * @returns A string containing a `<messages>` root element with one `<message>` entry per input message
 */
export function formatMessages(messages: NewMessage[]): string {
  const lines = messages.map((m) => {
    let inner = '';
    if (m.reply_context) {
      const replyText =
        m.reply_context.text !== null
          ? escapeXml(m.reply_context.text)
          : '[non-text message]';
      inner += `<reply to="${escapeXml(m.reply_context.sender_name)}">${replyText}</reply>`;
    }
    inner += escapeXml(m.content);
    return `<message sender="${escapeXml(m.sender_name)}" time="${m.timestamp}">${inner}</message>`;
  });
  return `<messages>\n${lines.join('\n')}\n</messages>`;
}

export function stripInternalTags(text: string): string {
  return text.replace(/<internal>[\s\S]*?<\/internal>/g, '').trim();
}

export function formatOutbound(rawText: string): string {
  const text = stripInternalTags(rawText);
  if (!text) return '';
  return text;
}

export function routeOutbound(
  channels: Channel[],
  jid: string,
  text: string,
): Promise<void> {
  const channel = channels.find((c) => c.ownsJid(jid) && c.isConnected());
  if (!channel) throw new Error(`No channel for JID: ${jid}`);
  return channel.sendMessage(jid, text);
}

export function findChannel(
  channels: Channel[],
  jid: string,
): Channel | undefined {
  return channels.find((c) => c.ownsJid(jid));
}