/**
 * Run: `node --test assets/js/chat_transcript_time.test.mjs` from repo root
 * (fixed TZ keeps local wall-time assertions stable in CI).
 */
import assert from "node:assert/strict"
import { describe, it, before } from "node:test"
import { formatChatTranscriptLabel } from "./chat_transcript_time.mjs"

describe("formatChatTranscriptLabel", () => {
  before(() => {
    process.env.TZ = "America/Phoenix"
  })

  it("shows local HH:MM for a message within 24 hours", () => {
    const now = new Date("2025-03-21T18:00:00Z")
    const msg = "2025-03-21T17:00:00Z"
    assert.equal(formatChatTranscriptLabel(msg, now), "10:00")
  })

  it("shows YYYY-MM-DD HH:MM when more than 24 hours old", () => {
    const now = new Date("2025-03-23T18:00:00Z")
    const msg = "2025-03-21T17:00:00Z"
    assert.equal(formatChatTranscriptLabel(msg, now), "2025-03-21 10:00")
  })

  it("at exactly 24 hours shows time only", () => {
    const now = new Date("2025-03-22T17:00:00Z")
    const msg = "2025-03-21T17:00:00Z"
    assert.equal(formatChatTranscriptLabel(msg, now), "10:00")
  })

  it("one second past 24 hours shows the date", () => {
    const now = new Date("2025-03-22T17:00:01Z")
    const msg = "2025-03-21T17:00:00Z"
    assert.equal(formatChatTranscriptLabel(msg, now), "2025-03-21 10:00")
  })

  it("future-dated message shows time-only label", () => {
    const now = new Date("2025-03-21T12:00:00Z")
    const msg = "2025-03-21T18:00:00Z"
    assert.equal(formatChatTranscriptLabel(msg, now), "11:00")
  })

  it("returns empty string for invalid datetime", () => {
    assert.equal(formatChatTranscriptLabel("not-a-date", new Date()), "")
  })
})
