/**
 * Chat transcript labels in the viewer's local timezone (browser).
 * `datetime` on <time> stays UTC ISO; this only produces visible text.
 *
 * @param {string} isoString - value from HTML datetime (ISO-8601)
 * @param {Date} [now] - for tests; defaults to new Date()
 * @returns {string}
 */
export function formatChatTranscriptLabel(isoString, now = new Date()) {
  const dt = new Date(isoString)
  if (Number.isNaN(dt.getTime())) return ""

  const diffMs = now.getTime() - dt.getTime()
  const moreThan24h = diffMs > 86400000

  if (moreThan24h) {
    return `${dt.getFullYear()}-${pad2(dt.getMonth() + 1)}-${pad2(dt.getDate())} ${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`
  }

  return `${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`
}

function pad2(n) {
  return String(n).padStart(2, "0")
}

/**
 * Fills every `<time data-local-chat-time datetime="…">` (chat thread, header inbox, bells, account).
 * @param {ParentNode} [root]
 */
export function applyChatTranscriptTimes(root = document) {
  root.querySelectorAll("time[data-local-chat-time][datetime]").forEach((el) => {
    const iso = el.getAttribute("datetime")
    if (!iso) return
    el.textContent = formatChatTranscriptLabel(iso)
  })
}
